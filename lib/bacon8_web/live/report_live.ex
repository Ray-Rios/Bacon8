defmodule Bacon8Web.ReportLive do
  @moduledoc """
  /report - report content (2026-11-03, `Bacon8.Moderation`). Open to everyone, signed in or not,
  so a person who was only sent a link can use it. Three forms:

    * **Report something** (`?kind=report`): what's wrong, where it is, what happened.
    * **Remove an intimate image** (`?kind=ncii_takedown`): the TAKE IT DOWN Act's request
      (signature, a good-faith statement that it was shared without consent, a way to reach the
      person). Answered within 48 hours; the image is hidden as soon as the request arrives.
    * **Copyright (DMCA)** (`?kind=dmca`): the notice 17 U.S.C. § 512(c)(3) describes.

  Report buttons beside content link here with `?type=<subject type>&id=<id>` (a chat message) or
  `?url=<link>`. Limited to 8 a visitor an hour (the address; behind a proxy that hides addresses,
  everyone shares one limit, BACON8.md §2, 2026-10-27).
  """
  use Bacon8Web, :live_view

  alias Bacon8.Moderation

  @kinds [{"report", "Report something"}, {"ncii_takedown", "Remove an intimate image"}, {"dmca", "Copyright (DMCA)"}]
  @per_hour 8
  # everyone signed out behind a proxy that hides addresses shares one bucket (BACON8.md §2,
  # 2026-10-27): big enough not to lose a real report, small enough to stop a flood
  @shared_per_hour 60

  @impl true
  def mount(params, _session, socket) do
    ip = Bacon8Web.ClientIP.from_socket(socket)

    kind = if params["kind"] in Enum.map(@kinds, &elem(&1, 0)), do: params["kind"], else: "report"

    form = %{
      "kind" => kind,
      "category" => if(kind == "ncii_takedown", do: "ncii", else: if(kind == "dmca", do: "copyright", else: params["category"] || "")),
      "subject_url" => params["url"] || "",
      "subject_type" => params["type"] || "",
      "subject_id" => params["id"] || "",
      "details" => "",
      "reporter_name" => (socket.assigns[:current_user] && socket.assigns.current_user.name) || "",
      "reporter_email" => (socket.assigns[:current_user] && socket.assigns.current_user.email) || "",
      "signature" => "",
      "sworn" => "false"
    }

    {:ok, assign(socket, page_title: "Report content", kinds: @kinds, form: form, errors: [], done: nil, ip: ip)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case params["kind"] do
      k when k in ["report", "ncii_takedown", "dmca"] -> {:noreply, assign(socket, form: kind_defaults(socket.assigns.form, k))}
      _ -> {:noreply, socket}
    end
  end

  defp kind_defaults(form, kind) do
    category =
      case kind do
        "ncii_takedown" -> "ncii"
        "dmca" -> "copyright"
        _ -> if(form["category"] in ["ncii", "copyright"], do: "", else: form["category"])
      end

    Map.merge(form, %{"kind" => kind, "category" => category})
  end

  # whose reports these are: the account, else a real address, else everyone behind the proxy
  defp rate_key(socket) do
    cond do
      user = socket.assigns[:current_user] -> {"report:user:#{user.id}", @per_hour}
      Bacon8.Security.blockable_ip?(socket.assigns.ip) -> {"report:ip:#{socket.assigns.ip}", @per_hour}
      true -> {"report:anonymous", @shared_per_hour}
    end
  end

  @impl true
  def handle_event("change", %{"r" => r}, socket), do: {:noreply, assign(socket, form: Map.merge(socket.assigns.form, r))}

  def handle_event("submit", %{"r" => r} = params, socket) do
    form = Map.merge(socket.assigns.form, r)
    {key, limit} = rate_key(socket)

    cond do
      # the field people can't see: only a bot fills it in
      (params["website"] || "") != "" ->
        {:noreply, assign(socket, done: "ok")}

      Bacon8.RateLimiter.check_and_increment_rate(key, limit, 3_600_000) != :ok ->
        {:noreply, assign(socket, form: form, errors: ["That's a lot of reports from here: try again in an hour, or write to us (see Contact)."])}

      true ->
        attrs =
          form
          |> Map.take(~w(kind category subject_url subject_type subject_id details reporter_name reporter_email signature))
          |> Map.put("sworn", form["sworn"] in ["true", "on"])
          |> Map.put("reporter_id", socket.assigns[:current_user] && socket.assigns.current_user.id)
          |> Map.put("reporter_ip", socket.assigns.ip)

        case Moderation.create_report(attrs) do
          {:ok, report} ->
            {:noreply, assign(socket, done: String.slice(report.id, 0, 8) |> String.upcase(), form: form)}

          {:error, %Ecto.Changeset{} = cs} ->
            {:noreply, assign(socket, form: form, errors: errors(cs))}
        end
    end
  end

  defp errors(cs) do
    labels = %{subject_url: "Where it is", category: "What's wrong", reporter_name: "Your name", reporter_email: "Your email", signature: "Signature", sworn: "The statement", details: "Details"}

    Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
    end)
    |> Enum.flat_map(fn {field, msgs} -> Enum.map(msgs, &"#{Map.get(labels, field, field)}: #{&1}") end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-4 py-8 text-gray-200">
      <div class="dark-glass rounded-xl p-6 space-y-5">
        <div>
          <h1 class="text-2xl font-bold text-white">Report content</h1>
          <p class="mt-1 text-sm text-gray-400">
            Tell us about something on this site that's illegal or breaks the rules. You don't need an account.
            If someone is in danger right now, call your local emergency number first.
          </p>
        </div>

        <div :if={@done} class="rounded-lg border border-green-800 bg-green-950/50 p-4 space-y-2">
          <p class="text-green-200 font-semibold">Thank you. We have your report{if @done != "ok", do: " (reference #{@done})"}.</p>
          <p :if={@form["kind"] == "ncii_takedown"} class="text-sm text-green-100">
            The image is hidden while we review your request, and we act on it within 48 hours.
            We'll write to the address you gave.
          </p>
          <p :if={@form["kind"] != "ncii_takedown"} class="text-sm text-green-100">Staff review every report. We may write to you if you gave an email address.</p>
        </div>

        <div :if={!@done} class="space-y-5">
          <div class="flex flex-wrap gap-1">
            <.link :for={{k, label} <- @kinds} patch={"/report?kind=#{k}"} class={"px-3 py-1.5 rounded text-sm " <> if(@form["kind"] == k, do: "bg-sky-700 text-white", else: "bg-gray-800 hover:bg-gray-700")}>{label}</.link>
          </div>

          <ul :if={@errors != []} class="rounded border border-red-800 bg-red-950/60 p-3 text-sm text-red-200 list-disc list-inside">
            <li :for={e <- @errors}>{e}</li>
          </ul>

          <form phx-change="change" phx-submit="submit" class="space-y-4 text-sm">
            <input type="hidden" name="r[kind]" value={@form["kind"]} />
            <input type="hidden" name="r[subject_type]" value={@form["subject_type"]} />
            <input type="hidden" name="r[subject_id]" value={@form["subject_id"]} />
            <div class="hidden" aria-hidden="true"><label>Website <input name="website" tabindex="-1" autocomplete="off" /></label></div>

            <fieldset :if={@form["kind"] == "report"} class="space-y-1">
              <legend class="font-semibold text-gray-100 mb-1">What's wrong?</legend>
              <label :for={c <- Moderation.categories()} :if={c.id not in ["ncii", "copyright"]} class="flex items-start gap-2">
                <input type="radio" name="r[category]" value={c.id} checked={@form["category"] == c.id} class="mt-1" />
                <span>{c.label}</span>
              </label>
              <p class="text-gray-400 pt-1">
                An intimate image of you shared without your consent? Use <.link patch="/report?kind=ncii_takedown" class="text-sky-400 underline">Remove an intimate image</.link>.
                Your copyrighted work? Use <.link patch="/report?kind=dmca" class="text-sky-400 underline">Copyright</.link>.
              </p>
            </fieldset>

            <div :if={@form["kind"] == "ncii_takedown"} class="rounded bg-gray-900/60 p-3 text-gray-300 space-y-1">
              <p>For a sexual or intimate image (real, edited or AI-made) of you, posted without your consent. You may also ask for someone you are authorized to act for.</p>
              <p>We hide it as soon as this arrives and remove it, and copies of it we find, within 48 hours (the TAKE IT DOWN Act).</p>
            </div>

            <div :if={@form["kind"] == "dmca"} class="rounded bg-gray-900/60 p-3 text-gray-300">
              <p>A notice under the Digital Millennium Copyright Act. Knowingly false notices can make you liable for damages. If it isn't your work, or you're unsure, ask a lawyer first.</p>
            </div>

            <label :if={@form["subject_id"] == ""} class="block">
              <span class="font-semibold text-gray-100">Where is it?</span> <span class="text-gray-400">(a link to the page or file)</span>
              <input name="r[subject_url]" value={@form["subject_url"]} placeholder="https://..." class="mt-1 w-full bg-gray-900 rounded px-3 py-2" />
            </label>
            <p :if={@form["subject_id"] != ""} class="text-gray-400">You're reporting the {String.replace(@form["subject_type"], "_", " ")} you clicked Report on.</p>

            <label class="block">
              <span class="font-semibold text-gray-100">{if @form["kind"] == "dmca", do: "Your work, and how this infringes it", else: "What happened?"}</span>
              <textarea name="r[details]" rows="4" class="mt-1 w-full bg-gray-900 rounded px-3 py-2">{@form["details"]}</textarea>
            </label>

            <div class="grid sm:grid-cols-2 gap-3">
              <label class="block">Your name{if @form["kind"] != "report", do: " *"}
                <input name="r[reporter_name]" value={@form["reporter_name"]} class="mt-1 w-full bg-gray-900 rounded px-3 py-2" />
              </label>
              <label class="block">Your email{if @form["kind"] != "report", do: " *"}
                <input name="r[reporter_email]" type="email" value={@form["reporter_email"]} class="mt-1 w-full bg-gray-900 rounded px-3 py-2" />
              </label>
            </div>

            <div :if={@form["kind"] != "report"} class="space-y-2">
              <label class="flex items-start gap-2">
                <input type="hidden" name="r[sworn]" value="false" />
                <input type="checkbox" name="r[sworn]" value="true" checked={@form["sworn"] in ["true", "on"]} class="mt-1" />
                <span :if={@form["kind"] == "ncii_takedown"}>
                  I am the person shown, or authorized to act for them, and I believe in good faith that this image was published without their consent.
                </span>
                <span :if={@form["kind"] == "dmca"}>
                  I have a good faith belief that this use of the material is not authorized by the copyright owner, its agent or the law. The information in this notice is accurate and, under penalty of perjury, I am the owner of the right I say is infringed, or authorized to act for the owner.
                </span>
              </label>
              <label class="block">Signature: type your full name *
                <input name="r[signature]" value={@form["signature"]} class="mt-1 w-full bg-gray-900 rounded px-3 py-2" />
              </label>
            </div>

            <button type="submit" class="bg-sky-700 hover:bg-sky-600 text-white px-5 py-2 rounded font-medium">Send</button>
          </form>

          <p class="text-xs text-gray-500">
            Reports go to the site's staff. We don't show your name or email to the person you report. Sexual content involving a minor is
            reported to the National Center for Missing &amp; Exploited Children (NCMEC), as US law requires; you can also report it to
            NCMEC yourself at report.cybertip.org.
          </p>
        </div>
      </div>
    </div>
    """
  end
end

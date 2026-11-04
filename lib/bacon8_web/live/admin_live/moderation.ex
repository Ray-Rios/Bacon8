defmodule Bacon8Web.AdminLive.Moderation do
  @moduledoc """
  /admin/moderation - the trust & safety queue (2026-11-03, `Bacon8.Moderation`): open reports
  by priority and due time (a TAKE IT DOWN request is due 48 hours after it arrives), what each
  names, the actions, the case history; files nobody may upload again; evidence kept for the law.

  A report of sexual content involving a minor never shows the content here: staff act on the
  report and what the hub knows (who posted what, when, its hash), keep the evidence, and file a
  CyberTipline report with NCMEC. Admins only.
  """
  use Bacon8Web, :live_view

  alias Bacon8.Moderation
  alias Bacon8Web.Components.AdminSidebar

  on_mount {Bacon8Web.UserAuth, :require_admin_user}

  @tabs [{"open", "Open"}, {"actioned", "Actioned"}, {"dismissed", "Dismissed"}, {"blocked", "Blocked files"}, {"holds", "Evidence holds"}]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Bacon8.PubSub, Moderation.topic())
    {:ok, assign(socket, page_title: "Admin - Moderation", tabs: @tabs, tab: "open", report: nil, now: DateTime.utc_now())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = if params["tab"] in Enum.map(@tabs, &elem(&1, 0)), do: params["tab"], else: "open"
    report = params["id"] && Moderation.get_report(params["id"])
    {:noreply, assign(socket, tab: tab, report: report, now: DateTime.utc_now())}
  end

  @impl true
  def handle_info({event, id}, socket) when event in [:report_created, :report_updated] do
    report = if socket.assigns.report && socket.assigns.report.id == id, do: Moderation.get_report(id), else: socket.assigns.report
    {:noreply, assign(socket, report: report, now: DateTime.utc_now())}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("act", %{"action" => action} = params, socket) do
    case socket.assigns.report do
      report when is_nil(report) or action not in ~w(preserve_remove remove block_hash restore ncmec_reported ban_owner dismiss resolve note) ->
        {:noreply, socket}

      report ->
        case Moderation.act(report, action, socket.assigns.current_user, params) do
          {:ok, report} -> {:noreply, socket |> assign(report: report) |> put_flash(:info, "Done.")}
          {:error, msg} -> {:noreply, put_flash(socket, :error, msg)}
        end
    end
  end

  def handle_event("block", %{"sha256" => sha, "reason" => reason}, socket) do
    case Moderation.block_hash(sha, reason, socket.assigns.current_user) do
      :ok -> {:noreply, put_flash(socket, :info, "Blocked.")}
      {:error, msg} -> {:noreply, put_flash(socket, :error, msg)}
    end
  end

  def handle_event("unblock", %{"sha256" => sha}, socket) do
    Moderation.unblock_hash(sha, socket.assigns.current_user)
    {:noreply, put_flash(socket, :info, "Unblocked.")}
  end

  def handle_event("release", %{"id" => id}, socket) do
    case Moderation.release_hold(id, socket.assigns.current_user) do
      :ok -> {:noreply, put_flash(socket, :info, "Released: the body goes at the next clean-up unless something else uses it.")}
      {:error, msg} -> {:noreply, put_flash(socket, :error, msg)}
    end
  end

  defp cat_label(cat), do: (Moderation.category(cat) || %{label: cat}).label

  defp kind_label("ncii_takedown"), do: "TAKE IT DOWN request"
  defp kind_label("dmca"), do: "DMCA notice"
  defp kind_label(_), do: "Report"

  defp prio_class(0), do: "bg-red-800 text-white"
  defp prio_class(1), do: "bg-orange-800 text-white"
  defp prio_class(2), do: "bg-gray-700 text-gray-200"
  defp prio_class(_), do: "bg-gray-800 text-gray-400"

  defp due(nil, _now), do: nil

  defp due(at, now) do
    s = DateTime.diff(at, now)

    cond do
      s < 0 -> "overdue by #{fmt_span(-s)}"
      true -> "due in #{fmt_span(s)}"
    end
  end

  defp fmt_span(s) when s >= 3600, do: "#{div(s, 3600)} h #{div(rem(s, 3600), 60)} min"
  defp fmt_span(s), do: "#{div(s, 60)} min"

  defp child_case?(report), do: report.category in ["csam", "child_exploitation"]

  @impl true
  def render(assigns) do
    assigns = assign(assigns, counts: Moderation.counts(assigns.now))

    ~H"""
    <AdminSidebar.admin_layout current_path="/admin/moderation">
      <div class="max-w-7xl mx-auto space-y-4 text-sm text-gray-300">
        <div class="dark-glass p-6 rounded-xl flex flex-wrap items-center justify-between gap-4">
          <div>
            <h1 class="text-2xl font-bold text-white">Moderation</h1>
            <p class="mt-1 text-gray-400">
              {@counts.open} open · <span class={@counts.urgent > 0 && "text-orange-300"}>{@counts.urgent} urgent</span> · <span class={@counts.overdue > 0 && "text-red-400 font-semibold"}>{@counts.overdue} overdue</span>.
              The public form is <a href="/report" target="_blank" class="text-sky-400 underline">/report</a>.
            </p>
          </div>
          <div class="flex flex-wrap gap-1">
            <.link :for={{id, l} <- @tabs} patch={"/admin/moderation?tab=#{id}"} class={"px-3 py-1.5 rounded " <> if(@tab == id, do: "bg-sky-700 text-white", else: "bg-gray-800 hover:bg-gray-700")}>{l}</.link>
          </div>
        </div>

        {if @tab in ["open", "actioned", "dismissed"], do: queue(assigns), else: if(@tab == "blocked", do: blocked(assigns), else: holds(assigns))}
      </div>
    </AdminSidebar.admin_layout>
    """
  end

  defp queue(assigns) do
    assigns = assign(assigns, reports: Moderation.list_reports(assigns.tab))

    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
      <div class="dark-glass rounded-xl p-3 space-y-1 max-h-[75vh] overflow-auto">
        <.link :for={r <- @reports} patch={"/admin/moderation?tab=#{@tab}&id=#{r.id}"} class={"block rounded px-2 py-2 " <> if(@report && @report.id == r.id, do: "bg-sky-900", else: "hover:bg-gray-800")}>
          <div class="flex items-center gap-2">
            <span class={"text-[10px] px-1.5 rounded " <> prio_class(r.priority)}>P{r.priority}</span>
            <span class="text-white truncate">{cat_label(r.category)}</span>
          </div>
          <div class="text-xs text-gray-500 flex justify-between gap-2">
            <span>{kind_label(r.kind)} · {Calendar.strftime(r.inserted_at, "%b %d %H:%M")}</span>
            <span :if={r.status == "open" && r.due_at} class={DateTime.compare(r.due_at, @now) == :lt && "text-red-400"}>{due(r.due_at, @now)}</span>
          </div>
        </.link>
        <p :if={@reports == []} class="text-gray-500 p-2">Nothing here.</p>
      </div>

      <div :if={@report} class="dark-glass rounded-xl p-4 lg:col-span-2 space-y-4">
        <div class="flex flex-wrap items-start justify-between gap-2">
          <div>
            <h2 class="text-xl text-white font-semibold">{cat_label(@report.category)}</h2>
            <p class="text-gray-400">{kind_label(@report.kind)} · {@report.status} · filed {Calendar.strftime(@report.inserted_at, "%Y-%m-%d %H:%M")} UTC · ref {String.upcase(String.slice(@report.id, 0, 8))}</p>
          </div>
          <span :if={@report.status == "open" && @report.due_at} class="px-2 py-1 rounded bg-red-900 text-red-100">{due(@report.due_at, @now)}</span>
        </div>

        <div :if={child_case?(@report)} class="rounded border border-red-800 bg-red-950/50 p-3 text-red-100 space-y-1">
          <p class="font-semibold">Suspected abuse of a child. The content is not shown here, on purpose.</p>
          <p>Don't open, download, forward or screenshot it, and don't ask the reporter for a copy. 1) <b>Keep evidence &amp; remove</b>. 2) File a CyberTipline report at report.cybertip.org (NCMEC) with what's below, as soon as you reasonably can: US law requires it once we know. 3) Record its number here. 4) Then ban the account.</p>
        </div>
        <div :if={@report.kind == "ncii_takedown"} class="rounded border border-orange-800 bg-orange-950/40 p-3 text-orange-100">
          A TAKE IT DOWN Act request: remove it (and copies) within 48 hours of the request if it's valid. It has been hidden since it arrived.
        </div>

        <div class="grid md:grid-cols-2 gap-4">
          <div class="rounded bg-gray-900/60 p-3 space-y-1">
            <h3 class="text-gray-400 font-semibold">What it names</h3>
            <p class="text-white break-all">{@report.subject_snapshot["title"] || @report.subject_url}</p>
            <p class="text-gray-400">{@report.subject_type}{if @report.subject_snapshot["hidden"], do: " · hidden"}</p>
            <p :if={@report.subject_url} class="break-all text-gray-400">{@report.subject_url}</p>
            <p :if={@report.subject_snapshot["content_type"]}>{@report.subject_snapshot["content_type"]} · {@report.subject_snapshot["size"]} bytes</p>
            <p :if={@report.subject_snapshot["sha256"]} class="font-mono text-xs break-all">sha256 {@report.subject_snapshot["sha256"]}</p>
            <p :if={@report.subject_owner_id}>Posted by account <.link navigate={"/admin/user-management?q=#{@report.subject_owner_id}"} class="text-sky-400 underline font-mono text-xs">{@report.subject_owner_id}</.link></p>
            <p :if={@report.subject_snapshot["url"]}>Where: <a href={@report.subject_snapshot["url"]} target="_blank" class="text-sky-400 underline">{@report.subject_snapshot["url"]}</a></p>
            <div :if={@report.subject_snapshot["text"] && !child_case?(@report)} class="mt-2 rounded bg-gray-950 p-2 whitespace-pre-wrap">{@report.subject_snapshot["text"]}</div>
            <p :if={(@report.subject_snapshot["files"] || []) != []}>{length(@report.subject_snapshot["files"])} attached file(s)</p>
          </div>
          <div class="rounded bg-gray-900/60 p-3 space-y-1">
            <h3 class="text-gray-400 font-semibold">From</h3>
            <p>{@report.reporter_name || "(no name)"} {if @report.reporter_email, do: "<#{@report.reporter_email}>"}</p>
            <p :if={@report.reporter_id} class="font-mono text-xs">account {@report.reporter_id}</p>
            <p :if={@report.signature}>Signed: {@report.signature}{if @report.sworn, do: " · statement confirmed"}</p>
            <div :if={@report.details} class="mt-2 rounded bg-gray-950 p-2 whitespace-pre-wrap">{@report.details}</div>
            <p :if={@report.ncmec_report_id} class="mt-2 text-green-300">CyberTipline report {@report.ncmec_report_id}</p>
          </div>
        </div>

        <div :if={@report.status == "open"} class="space-y-2">
          <div class="flex flex-wrap gap-2">
            <button phx-click="act" phx-value-action="preserve_remove" data-confirm="Keep the evidence for a year, hide it and block its files?" class="bg-red-800 hover:bg-red-700 text-white px-3 py-1.5 rounded">Keep evidence &amp; remove</button>
            <button phx-click="act" phx-value-action="remove" data-confirm="Delete it and block its files?" class="bg-gray-700 hover:bg-gray-600 text-white px-3 py-1.5 rounded">Remove</button>
            <button phx-click="act" phx-value-action="block_hash" class="bg-gray-700 hover:bg-gray-600 text-white px-3 py-1.5 rounded">Block its files</button>
            <button phx-click="act" phx-value-action="restore" data-confirm="Show it again?" class="bg-gray-700 hover:bg-gray-600 text-white px-3 py-1.5 rounded">Restore</button>
            <button :if={@report.subject_owner_id} phx-click="act" phx-value-action="ban_owner" data-confirm="Ban the account that posted it? Its posts and messages are deleted at once." class="bg-gray-700 hover:bg-red-800 text-white px-3 py-1.5 rounded">Ban the poster</button>
          </div>
          <form :if={child_case?(@report)} phx-submit="act" class="flex flex-wrap items-end gap-2">
            <input type="hidden" name="action" value="ncmec_reported" />
            <label>CyberTipline report number <input name="ncmec_report_id" class="block bg-gray-900 rounded px-2 py-1" /></label>
            <button class="bg-gray-700 hover:bg-gray-600 text-white px-3 py-1.5 rounded">Record it</button>
          </form>
          <form phx-submit="act" class="space-y-2">
            <textarea name="note" rows="2" placeholder="A note for the history (what you checked, why)" class="w-full bg-gray-900 rounded px-2 py-1"></textarea>
            <div class="flex flex-wrap gap-2">
              <button name="action" value="note" class="bg-gray-700 hover:bg-gray-600 text-white px-3 py-1.5 rounded">Add note</button>
              <button name="action" value="resolve" class="bg-sky-700 hover:bg-sky-600 text-white px-3 py-1.5 rounded">Close: dealt with</button>
              <button name="action" value="dismiss" class="bg-gray-700 hover:bg-gray-600 text-white px-3 py-1.5 rounded">Close: nothing wrong</button>
            </div>
          </form>
        </div>

        <div class="rounded bg-gray-900/60 p-3">
          <h3 class="text-gray-400 font-semibold mb-1">History</h3>
          <ol class="space-y-1">
            <li :for={a <- @report.actions} class="flex gap-2">
              <span class="text-gray-500 whitespace-nowrap">{Calendar.strftime(a.inserted_at, "%b %d %H:%M")}</span>
              <span class="text-white">{a.action}</span>
              <span class="text-gray-400">{a.note}</span>
            </li>
          </ol>
        </div>
      </div>

      <div :if={!@report} class="dark-glass rounded-xl p-6 lg:col-span-2 text-gray-400">Pick a report.</div>
    </div>
    """
  end

  defp blocked(assigns) do
    assigns = assign(assigns, rows: Moderation.list_blocked())

    ~H"""
    <div class="dark-glass rounded-xl p-4 space-y-3">
      <p class="text-gray-400">Files nobody can upload again (drive, chat, blog, avatars), by SHA-256. Removing one through a report blocks it; you can add a known-bad hash too.</p>
      <form phx-submit="block" class="flex flex-wrap gap-2 items-end">
        <label>SHA-256 <input name="sha256" class="block w-[34rem] max-w-full bg-gray-900 rounded px-2 py-1 font-mono text-xs" /></label>
        <label>Why <input name="reason" class="block bg-gray-900 rounded px-2 py-1" /></label>
        <button class="bg-gray-700 hover:bg-gray-600 text-white px-3 py-1.5 rounded">Block</button>
      </form>
      <table class="w-full text-left">
        <thead class="text-gray-500"><tr><th>sha256</th><th>why</th><th>when</th><th></th></tr></thead>
        <tbody>
          <tr :for={b <- @rows} class="border-t border-gray-800">
            <td class="font-mono text-xs break-all">{b.sha256}</td>
            <td>{b.reason}</td>
            <td>{Calendar.strftime(b.inserted_at, "%Y-%m-%d")}</td>
            <td><button phx-click="unblock" phx-value-sha256={b.sha256} data-confirm="Let this file be uploaded again?" class="text-gray-400 hover:text-white">unblock</button></td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp holds(assigns) do
    assigns = assign(assigns, rows: Moderation.list_holds())

    ~H"""
    <div class="dark-glass rounded-xl p-4 space-y-3">
      <p class="text-gray-400">
        Evidence kept for the law: file bodies (out of the site's reach and its clean-up) and what we knew. A provider that reports to NCMEC keeps
        the report's contents for a year (18 U.S.C. § 2258A). Release one only when its time is up and no law-enforcement request is open.
      </p>
      <table class="w-full text-left">
        <thead class="text-gray-500"><tr><th>report</th><th>what</th><th>file</th><th>keep until</th><th></th></tr></thead>
        <tbody>
          <tr :for={h <- @rows} class="border-t border-gray-800">
            <td><.link patch={"/admin/moderation?tab=actioned&id=#{h.report_id}"} class="text-sky-400 underline font-mono text-xs">{String.slice(h.report_id, 0, 8)}</.link></td>
            <td>{h.subject_type}</td>
            <td class="font-mono text-xs">{h.sha256 && String.slice(h.sha256, 0, 16)}</td>
            <td>{Calendar.strftime(h.preserve_until, "%Y-%m-%d")}{if h.released_at, do: " · released"}</td>
            <td><button :if={!h.released_at} phx-click="release" phx-value-id={h.id} data-confirm="Release this evidence? Only when its year is up and nobody has asked for it." class="text-gray-400 hover:text-white">release</button></td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end
end

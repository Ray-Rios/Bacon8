defmodule FeedbackWeb.FeedbackLive do
  @moduledoc """
  /feedback - Suggestions & Bugs: the list (tabs, filters, votes) and, at /feedback/new, the
  form for a new one with screenshots (picked, dropped or pasted). Members only: a guest, or
  anyone signed out, is sent away.
  """
  use Bacon8Web, :live_view

  import FeedbackWeb.Components

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns[:current_user]

    cond do
      is_nil(user) ->
        {:ok,
         socket
         |> put_flash(:error, "Sign in to suggest things and report bugs.")
         |> redirect(to: "/login")}

      not Feedback.member?(user) ->
        {:ok,
         socket |> put_flash(:error, "Suggestions & Bugs is for members.") |> redirect(to: "/")}

      true ->
        if connected?(socket), do: Phoenix.PubSub.subscribe(Bacon8.PubSub, Feedback.topic())

        {:ok,
         socket
         |> assign(
           page_title: "Suggestions & Bugs",
           admin?: Feedback.admin?(user),
           areas: Feedback.areas(),
           error: nil
         )
         |> assign(form: new_form())
         |> allow_upload(:shots,
           accept: ~w(.png .jpg .jpeg .webp .gif),
           max_entries: Feedback.max_shots(),
           max_file_size: Feedback.max_shot_bytes()
         )}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = %{
      "group" =>
        pick(params["group"], ["active", "live", "closed", "review", "claude", "all"], "active"),
      "kind" => pick(params["kind"], ["all", "suggestion", "bug"], "all"),
      "area" => params["area"] || "all",
      "sort" => pick(params["sort"], ["top", "new"], "top"),
      "q" => params["q"] || ""
    }

    socket =
      socket
      |> assign(filters: filters)
      |> load()

    socket =
      if socket.assigns.live_action == :new do
        kind = pick(params["kind"], ["suggestion", "bug"], "suggestion")

        assign(socket,
          form:
            new_form(%{
              "kind" => kind,
              "area" => pick(params["area"], Enum.map(socket.assigns.areas, &elem(&1, 0)), "site")
            }),
          error: nil
        )
      else
        socket
      end

    {:noreply, socket}
  end

  defp pick(v, allowed, default), do: if(v in allowed, do: v, else: default)

  defp load(socket) do
    f = socket.assigns.filters

    items =
      Feedback.list_items(socket.assigns.current_user,
        group: f["group"],
        kind: if(f["kind"] == "all", do: nil, else: f["kind"]),
        area: f["area"],
        sort: f["sort"],
        q: f["q"]
      )

    assign(socket, items: items, counts: Feedback.counts())
  end

  defp new_form(params \\ %{"kind" => "suggestion", "area" => "site"}) do
    %Feedback.Item{}
    |> Feedback.Item.content_changeset(params)
    |> Map.put(:action, nil)
    |> to_form(as: :item)
  end

  # ---------------------------------------------------------------- events

  @impl true
  def handle_event("filter", params, socket) do
    query =
      %{
        "group" => socket.assigns.filters["group"],
        "kind" => params["kind"],
        "area" => params["area"],
        "sort" => params["sort"],
        "q" => params["q"]
      }
      |> Enum.reject(fn {k, v} ->
        v in [nil, ""] or (k in ["kind", "area"] and v == "all") or (k == "sort" and v == "top") or
          (k == "group" and v == "active")
      end)
      |> Map.new()

    {:noreply, push_patch(socket, to: "/feedback?" <> URI.encode_query(query))}
  end

  # (the attribute is phx-value-vote, not phx-value-value: LiveView sends a button's own empty value over a phx-value-value)
  def handle_event("vote", %{"id" => id, "vote" => v}, socket) do
    user = socket.assigns.current_user

    with {value, ""} when value in [-1, 0, 1] <- Integer.parse(to_string(v)),
         %Feedback.Item{} = item <- Enum.find(socket.assigns.items, &(&1.id == id)),
         {:ok, _} <- Feedback.vote(item, user, value) do
      {:noreply, load(socket)}
    else
      {:error, reason} -> {:noreply, put_flash(socket, :error, reason_text(reason))}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("validate", %{"item" => params}, socket) do
    form =
      %Feedback.Item{}
      |> Feedback.Item.content_changeset(params)
      |> Map.put(:action, :validate)
      |> to_form(as: :item)

    {:noreply, assign(socket, form: form)}
  end

  def handle_event("cancel_shot", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :shots, ref)}

  def handle_event("save", %{"item" => params}, socket) do
    user = socket.assigns.current_user

    # Upload temp files only live inside the consume callback, so the item is written there.
    entries = socket.assigns.uploads.shots.entries

    if Enum.any?(entries, &(not &1.done?)) do
      {:noreply, assign(socket, error: "Wait for the screenshots to finish uploading.")}
    else
      result =
        if entries == [] do
          Feedback.create_item(user, params, [])
        else
          paths =
            consume_uploaded_entries(socket, :shots, fn %{path: path}, entry ->
              {:postpone, {path, entry.client_name}}
            end)

          Feedback.create_item(user, params, paths)
        end

      case result do
        {:ok, item} ->
          # Postponed entries are cleaned up when the view moves on.
          {:noreply,
           socket
           |> put_flash(:info, "Thanks! It's posted as ##{item.number}.")
           |> push_navigate(to: "/feedback/#{item.id}")}

        {:error, %Ecto.Changeset{} = cs} ->
          {:noreply,
           assign(socket, form: to_form(Map.put(cs, :action, :insert), as: :item), error: nil)}

        {:error, reason} ->
          {:noreply, assign(socket, error: reason_text(reason))}
      end
    end
  end

  @impl true
  def handle_info({:feedback, _what, _id}, socket), do: {:noreply, load(socket)}
  def handle_info(_msg, socket), do: {:noreply, socket}

  # ---------------------------------------------------------------- view

  @impl true
  def render(assigns) do
    ~H"""
    <div class="fixed inset-x-0 top-[30px] bottom-[35px] z-30 overflow-y-auto bg-gradient-to-b from-gray-950 via-black to-black">
      <div class="mx-auto max-w-5xl px-4 py-10 sm:px-6">
        <header class="mb-8 flex flex-wrap items-end justify-between gap-4">
          <div>
            <h1 class="text-3xl font-bold tracking-tight text-white sm:text-4xl">Suggestions &amp; Bugs</h1>
            <p class="mt-2 max-w-2xl text-gray-400">
              Ideas for the site and the games, and anything that's broken. Vote for what matters most;
              approved ones go to Claude to build.
            </p>
          </div>
          <div class="flex gap-2">
            <.link patch="/feedback/new?kind=suggestion" id="new-suggestion" class="rounded-lg bg-yellow-500/90 px-4 py-2 text-sm font-semibold text-black hover:bg-yellow-400">
              💡 Suggest
            </.link>
            <.link patch="/feedback/new?kind=bug" id="new-bug" class="rounded-lg bg-red-600 px-4 py-2 text-sm font-semibold text-white hover:bg-red-500">
              🐞 Report a bug
            </.link>
          </div>
        </header>

        <nav class="mb-4 flex flex-wrap gap-1 border-b border-gray-800" aria-label="Lists">
          <.group_tab group="active" label="Active" filters={@filters} count={count(@counts, ~w(open approved queued in_progress needs_info ready deploying))} />
          <.group_tab group="live" label="Live" filters={@filters} count={count(@counts, ~w(deployed))} />
          <.group_tab group="closed" label="Closed" filters={@filters} count={count(@counts, ~w(rejected duplicate failed))} />
          <.group_tab :if={@admin?} group="review" label="To review" filters={@filters} count={count(@counts, ~w(open))} />
          <.group_tab :if={@admin?} group="claude" label="With Claude" filters={@filters} count={count(@counts, ~w(queued in_progress needs_info ready deploying failed))} />
        </nav>

        <form id="feedback-filters" phx-change="filter" phx-submit="filter" class="mb-6 grid grid-cols-2 gap-2 sm:grid-cols-[1fr_auto_auto_auto]">
          <input
            type="search"
            name="q"
            value={@filters["q"]}
            placeholder="Search…"
            phx-debounce="300"
            class="col-span-2 rounded-lg border border-gray-800 bg-gray-950 px-3 py-2 text-sm text-white placeholder-gray-500 focus:border-orange-500 focus:ring-0 sm:col-span-1"
          />
          <select name="kind" class="rounded-lg border border-gray-800 bg-gray-950 py-2 text-sm text-gray-200 focus:border-orange-500 focus:ring-0">
            <option value="all" selected={@filters["kind"] == "all"}>Both kinds</option>
            <option value="suggestion" selected={@filters["kind"] == "suggestion"}>Suggestions</option>
            <option value="bug" selected={@filters["kind"] == "bug"}>Bugs</option>
          </select>
          <select name="area" class="rounded-lg border border-gray-800 bg-gray-950 py-2 text-sm text-gray-200 focus:border-orange-500 focus:ring-0">
            <option value="all" selected={@filters["area"] == "all"}>Everywhere</option>
            <option :for={{slug, name} <- @areas} value={slug} selected={@filters["area"] == slug}>{name}</option>
          </select>
          <select name="sort" class="rounded-lg border border-gray-800 bg-gray-950 py-2 text-sm text-gray-200 focus:border-orange-500 focus:ring-0">
            <option value="top" selected={@filters["sort"] == "top"}>Top voted</option>
            <option value="new" selected={@filters["sort"] == "new"}>Newest</option>
          </select>
        </form>

        <ul id="feedback-items" class="space-y-2">
          <li :for={item <- @items} id={"item-#{item.id}"} class="flex gap-3 rounded-xl border border-gray-800/80 bg-gray-950/60 p-3 transition hover:border-gray-700">
            <.vote_box item={item} can_vote={Feedback.can_vote?(item, @current_user)} />
            <.link navigate={"/feedback/#{item.id}"} class="min-w-0 flex-1">
              <div class="flex flex-wrap items-center gap-2">
                <.kind_badge kind={item.kind} />
                <span class="rounded-md bg-gray-800/80 px-2 py-0.5 text-xs text-gray-300">{Feedback.area_name(item.area)}</span>
                <.status_pill status={item.status} />
              </div>
              <h2 class="mt-1.5 truncate font-semibold text-white">
                <span class="mr-1 font-normal text-gray-500">#{item.number}</span>{item.title}
              </h2>
              <p class="mt-1 line-clamp-2 text-sm text-gray-400">{item.body}</p>
              <p class="mt-1.5 text-xs text-gray-500">
                {name_of(item.author)} · {ago(item.inserted_at)}<span :if={item.shots != []}> · 📷 {length(item.shots)}</span>
              </p>
            </.link>
          </li>
        </ul>

        <div :if={@items == []} class="rounded-xl border border-dashed border-gray-800 py-16 text-center text-gray-500">
          Nothing here yet.
        </div>
      </div>

      <.new_dialog :if={@live_action == :new} form={@form} areas={@areas} uploads={@uploads} error={@error} filters={@filters} />
    </div>
    """
  end

  defp count(counts, statuses), do: Enum.reduce(statuses, 0, &(&2 + Map.get(counts, &1, 0)))

  attr(:group, :string, required: true)
  attr(:label, :string, required: true)
  attr(:filters, :map, required: true)
  attr(:count, :integer, default: 0)

  defp group_tab(assigns) do
    ~H"""
    <.link
      patch={"/feedback" <> if(@group == "active", do: "", else: "?group=#{@group}")}
      id={"tab-#{@group}"}
      class={[
        "-mb-px border-b-2 px-3 py-2 text-sm font-medium transition",
        if(@filters["group"] == @group, do: "border-orange-500 text-white", else: "border-transparent text-gray-400 hover:text-gray-200")
      ]}
    >
      {@label} <span class="ml-1 rounded-full bg-gray-800 px-1.5 text-xs text-gray-400">{@count}</span>
    </.link>
    """
  end

  attr(:form, :any, required: true)
  attr(:areas, :list, required: true)
  attr(:uploads, :any, required: true)
  attr(:error, :string, default: nil)
  attr(:filters, :map, required: true)

  defp new_dialog(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/70 p-4 backdrop-blur-sm sm:items-center">
      <div class="w-full max-w-2xl rounded-2xl border border-gray-800 bg-gray-950 p-6 shadow-2xl" phx-hook="FeedbackPaste" id="feedback-new" data-upload="shots">
        <div class="mb-5 flex items-center justify-between">
          <h2 class="text-xl font-semibold text-white">
            {if @form[:kind].value == "bug", do: "🐞 Report a bug", else: "💡 Make a suggestion"}
          </h2>
          <.link patch="/feedback" class="rounded p-1 text-gray-400 hover:bg-gray-800 hover:text-white" aria-label="Close">✕</.link>
        </div>

        <.form for={@form} id="feedback-form" phx-change="validate" phx-submit="save" class="space-y-4">
          <div class="grid grid-cols-2 gap-3">
            <label class="block">
              <span class="mb-1 block text-xs font-medium uppercase tracking-wide text-gray-400">Kind</span>
              <select name={@form[:kind].name} class="w-full rounded-lg border border-gray-800 bg-black text-sm text-white focus:border-orange-500 focus:ring-0">
                <option value="suggestion" selected={@form[:kind].value == "suggestion"}>💡 Suggestion</option>
                <option value="bug" selected={@form[:kind].value == "bug"}>🐞 Bug</option>
              </select>
            </label>
            <label class="block">
              <span class="mb-1 block text-xs font-medium uppercase tracking-wide text-gray-400">About</span>
              <select name={@form[:area].name} class="w-full rounded-lg border border-gray-800 bg-black text-sm text-white focus:border-orange-500 focus:ring-0">
                <option :for={{slug, name} <- @areas} value={slug} selected={@form[:area].value == slug}>{name}</option>
              </select>
            </label>
          </div>

          <label class="block">
            <span class="mb-1 block text-xs font-medium uppercase tracking-wide text-gray-400">Title</span>
            <input
              type="text"
              name={@form[:title].name}
              value={@form[:title].value}
              maxlength="140"
              placeholder={if @form[:kind].value == "bug", do: "What's broken, in a few words", else: "Your idea, in a few words"}
              class="w-full rounded-lg border border-gray-800 bg-black text-white placeholder-gray-600 focus:border-orange-500 focus:ring-0"
            />
            <.errors field={@form[:title]} />
          </label>

          <label class="block">
            <span class="mb-1 block text-xs font-medium uppercase tracking-wide text-gray-400">Details</span>
            <textarea
              name={@form[:body].name}
              rows="6"
              maxlength="10000"
              placeholder={
                if @form[:kind].value == "bug",
                  do: "What happened, what you expected, and how to make it happen again (where you were, what you clicked).",
                  else: "What you'd like, and why it would make things better."
              }
              class="w-full rounded-lg border border-gray-800 bg-black text-sm text-white placeholder-gray-600 focus:border-orange-500 focus:ring-0"
            >{@form[:body].value}</textarea>
            <.errors field={@form[:body]} />
          </label>

          <div>
            <span class="mb-1 block text-xs font-medium uppercase tracking-wide text-gray-400">Screenshots</span>
            <div
              phx-drop-target={@uploads.shots.ref}
              class="rounded-lg border border-dashed border-gray-700 bg-black/40 p-4 text-center text-sm text-gray-400"
            >
              <label class="cursor-pointer text-orange-400 hover:underline">Choose pictures<.live_file_input upload={@uploads.shots} class="sr-only" /></label><span>, drop them here, or paste one (Ctrl+V). Up to {Feedback.max_shots()}, 10 MB each.</span>
            </div>
            <div :if={@uploads.shots.entries != []} class="mt-3 grid grid-cols-3 gap-2 sm:grid-cols-6">
              <div :for={entry <- @uploads.shots.entries} class="relative overflow-hidden rounded-md border border-gray-800">
                <.live_img_preview entry={entry} class="h-20 w-full object-cover" />
                <button
                  type="button"
                  phx-click="cancel_shot"
                  phx-value-ref={entry.ref}
                  class="absolute right-1 top-1 rounded bg-black/70 px-1 text-xs text-white hover:bg-red-600"
                  aria-label="Remove"
                >
                  ✕
                </button>
                <div class="absolute inset-x-0 bottom-0 h-1 bg-gray-800">
                  <div class="h-1 bg-orange-500" style={"width: #{entry.progress}%"}></div>
                </div>
                <p :for={err <- upload_errors(@uploads.shots, entry)} class="bg-red-900/80 px-1 text-[10px] text-red-100">{upload_error(err)}</p>
              </div>
            </div>
            <p :for={err <- upload_errors(@uploads.shots)} class="mt-1 text-xs text-red-400">{upload_error(err)}</p>
          </div>

          <p :if={@error} class="rounded-md bg-red-500/10 px-3 py-2 text-sm text-red-300">{@error}</p>

          <div class="flex justify-end gap-2 pt-2">
            <.link patch="/feedback" class="rounded-lg px-4 py-2 text-sm text-gray-300 hover:bg-gray-800">Cancel</.link>
            <button type="submit" phx-disable-with="Posting…" class="rounded-lg bg-orange-600 px-5 py-2 text-sm font-semibold text-white hover:bg-orange-500">
              Post
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  attr(:field, Phoenix.HTML.FormField, required: true)

  defp errors(assigns) do
    ~H"""
    <p :for={{msg, opts} <- if(Phoenix.Component.used_input?(@field), do: @field.errors, else: [])} class="mt-1 text-xs text-red-400">
      {Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)}
    </p>
    """
  end
end

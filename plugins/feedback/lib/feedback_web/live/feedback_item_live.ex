defmodule FeedbackWeb.FeedbackItemLive do
  @moduledoc """
  /feedback/:id - one suggestion or bug: votes, screenshots, Claude's report and the history.
  Its author can change or delete it while it is open; an admin can change it at any time
  (adding notes for Claude), approve, decline, mark it a duplicate, submit it to Claude, and
  press Deploy on a change Claude held back.
  """
  use Bacon8Web, :live_view

  import FeedbackWeb.Components

  @impl true
  def mount(%{"id" => id}, _session, socket) do
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
        case Feedback.get_item(id, user) do
          nil ->
            {:ok,
             socket
             |> put_flash(:error, "That suggestion isn't there any more.")
             |> push_navigate(to: "/feedback")}

          item ->
            if connected?(socket), do: Phoenix.PubSub.subscribe(Bacon8.PubSub, Feedback.topic())

            {:ok,
             socket
             |> assign(
               admin?: Feedback.admin?(user),
               areas: Feedback.areas(),
               editing?: false,
               note: "",
               dup_of: "",
               error: nil
             )
             |> assign_item(item)
             |> allow_upload(:shots,
               accept: ~w(.png .jpg .jpeg .webp .gif),
               max_entries: Feedback.max_shots(),
               max_file_size: Feedback.max_shot_bytes(),
               auto_upload: true,
               progress: &handle_progress/3
             )}
        end
    end
  end

  defp assign_item(socket, item) do
    socket
    |> assign(item: item, page_title: "##{item.number} #{item.title}")
    |> assign(form: item |> Feedback.Item.admin_changeset(%{}) |> to_form(as: :item))
    |> assign(agent: if(socket.assigns.admin?, do: Feedback.agent(), else: nil))
  end

  defp reload(socket) do
    case Feedback.get_item(socket.assigns.item.id, socket.assigns.current_user) do
      nil -> socket |> put_flash(:info, "It was deleted.") |> push_navigate(to: "/feedback")
      item -> assign_item(socket, item)
    end
  end

  # ---------------------------------------------------------------- events

  @impl true
  def handle_event("vote", %{"value" => v}, socket) do
    with {value, ""} when value in [-1, 0, 1] <- Integer.parse(to_string(v)),
         {:ok, _} <- Feedback.vote(socket.assigns.item, socket.assigns.current_user, value) do
      {:noreply, reload(socket)}
    else
      {:error, reason} -> {:noreply, put_flash(socket, :error, reason_text(reason))}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("edit", _, socket), do: {:noreply, assign(socket, editing?: true)}

  def handle_event("cancel_edit", _, socket),
    do: {:noreply, assign(socket, editing?: false) |> reload()}

  def handle_event("validate", %{"item" => params}, socket) do
    form =
      socket.assigns.item
      |> Feedback.Item.admin_changeset(params)
      |> Map.put(:action, :validate)
      |> to_form(as: :item)

    {:noreply, assign(socket, form: form)}
  end

  def handle_event("save", %{"item" => params}, socket) do
    case Feedback.update_item(socket.assigns.item, socket.assigns.current_user, params) do
      {:ok, _} ->
        {:noreply, socket |> assign(editing?: false) |> put_flash(:info, "Saved.") |> reload()}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, assign(socket, form: to_form(Map.put(cs, :action, :update), as: :item))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, reason_text(reason))}
    end
  end

  def handle_event("delete", _, socket) do
    case Feedback.delete_item(socket.assigns.item, socket.assigns.current_user) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Deleted.") |> push_navigate(to: "/feedback")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, reason_text(reason))}
    end
  end

  def handle_event("delete_shot", %{"id" => id}, socket) do
    with %Feedback.Shot{} = shot <- Enum.find(socket.assigns.item.shots, &(&1.id == id)),
         {:ok, _} <- Feedback.delete_shot(shot, socket.assigns.current_user) do
      {:noreply, reload(socket)}
    else
      {:error, reason} -> {:noreply, put_flash(socket, :error, reason_text(reason))}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("shots_change", _, socket), do: {:noreply, socket}

  def handle_event("note", %{"note" => note} = p, socket),
    do: {:noreply, assign(socket, note: note, dup_of: p["of"] || socket.assigns.dup_of)}

  def handle_event("move", %{"action" => action} = p, socket) do
    opts = [note: p["note"] || socket.assigns.note, of: p["of"] || socket.assigns.dup_of]

    case Feedback.moderate(socket.assigns.item, socket.assigns.current_user, action, opts) do
      {:ok, item} ->
        {:noreply,
         socket
         |> assign(note: "", dup_of: "")
         |> put_flash(:info, moved_text(action, item))
         |> reload()}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, reason_text(reason)) |> reload()}
    end
  end

  defp moved_text("submit", _), do: "Submitted: it's in Claude's queue."

  defp moved_text("deploy", _),
    do: "Deploy requested: Claude's runner deploys it on its next pass."

  defp moved_text(_, item), do: "Now: " <> status_label(item.status) <> "."

  # Screenshots added on the item page upload straight away and are stored as each one finishes.
  defp handle_progress(:shots, entry, socket) do
    if entry.done? do
      # The temp file only exists inside the callback, so the screenshot is stored there.
      result =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          {:ok,
           Feedback.add_shots(socket.assigns.item, socket.assigns.current_user, [
             {path, entry.client_name}
           ])}
        end)

      socket =
        case result do
          {:ok, _} -> socket
          {:error, reason} -> put_flash(socket, :error, reason_text(reason))
        end

      {:noreply, reload(socket)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:feedback, :deleted, id}, %{assigns: %{item: %{id: id}}} = socket),
    do:
      {:noreply, socket |> put_flash(:info, "It was deleted.") |> push_navigate(to: "/feedback")}

  def handle_info({:feedback, _what, id}, %{assigns: %{item: %{id: id}}} = socket),
    do: {:noreply, reload(socket)}

  def handle_info({:feedback, :agent, _}, socket), do: {:noreply, reload(socket)}
  def handle_info(_msg, socket), do: {:noreply, socket}

  # ---------------------------------------------------------------- view

  @impl true
  def render(assigns) do
    ~H"""
    <div class="fixed inset-x-0 top-[30px] bottom-[35px] z-30 overflow-y-auto bg-gradient-to-b from-gray-950 via-black to-black">
      <div class="mx-auto max-w-4xl px-4 py-8 sm:px-6">
        <.link navigate="/feedback" class="text-sm text-gray-400 hover:text-white">← Suggestions &amp; Bugs</.link>

        <article class="mt-4 rounded-2xl border border-gray-800 bg-gray-950/70 p-5 sm:p-6">
          <div class="flex gap-4">
            <.vote_box item={@item} can_vote={Feedback.can_vote?(@item, @current_user)} size="lg" />
            <div class="min-w-0 flex-1">
              <div class="flex flex-wrap items-center gap-2">
                <.kind_badge kind={@item.kind} />
                <span class="rounded-md bg-gray-800/80 px-2 py-0.5 text-xs text-gray-300">{Feedback.area_name(@item.area)}</span>
                <.status_pill status={@item.status} />
              </div>
              <h1 class="mt-2 text-2xl font-bold text-white"><span class="mr-1 font-normal text-gray-500">#{@item.number}</span>{@item.title}</h1>
              <p class="mt-1 text-sm text-gray-500">{name_of(@item.author)} · {ago(@item.inserted_at)}</p>
              <p :if={@item.status == "duplicate" and @item.duplicate_of} class="mt-2 text-sm text-gray-400">
                Duplicate of
                <.link navigate={"/feedback/#{@item.duplicate_of.id}"} class="text-orange-400 hover:underline">#{@item.duplicate_of.number} {@item.duplicate_of.title}</.link>
              </p>
            </div>
            <div :if={Feedback.can_edit?(@item, @current_user) and not @editing?} class="flex shrink-0 items-start gap-1">
              <button type="button" phx-click="edit" id="edit-item" class="rounded-lg px-3 py-1.5 text-sm text-gray-300 hover:bg-gray-800">Edit</button>
              <button
                type="button"
                phx-click="delete"
                id="delete-item"
                data-confirm="Delete this for good?"
                class="rounded-lg px-3 py-1.5 text-sm text-red-400 hover:bg-red-500/10"
              >
                Delete
              </button>
            </div>
          </div>

          <div :if={not @editing?} class="mt-5 whitespace-pre-wrap break-words text-gray-200">{@item.body}</div>

          <.form :if={@editing?} for={@form} id="edit-form" phx-change="validate" phx-submit="save" class="mt-5 space-y-3">
            <div class="grid grid-cols-2 gap-3">
              <select name={@form[:kind].name} class="rounded-lg border border-gray-800 bg-black text-sm text-white">
                <option value="suggestion" selected={@form[:kind].value == "suggestion"}>💡 Suggestion</option>
                <option value="bug" selected={@form[:kind].value == "bug"}>🐞 Bug</option>
              </select>
              <select name={@form[:area].name} class="rounded-lg border border-gray-800 bg-black text-sm text-white">
                <option :for={{slug, name} <- @areas} value={slug} selected={@form[:area].value == slug}>{name}</option>
              </select>
            </div>
            <input type="text" name={@form[:title].name} value={@form[:title].value} maxlength="140" class="w-full rounded-lg border border-gray-800 bg-black text-white" />
            <textarea name={@form[:body].name} rows="8" maxlength="10000" class="w-full rounded-lg border border-gray-800 bg-black text-sm text-white">{@form[:body].value}</textarea>
            <label :if={@admin?} class="block">
              <span class="mb-1 block text-xs font-medium uppercase tracking-wide text-violet-300">Notes for Claude (admins only; sent with the item)</span>
              <textarea name={@form[:admin_note].name} rows="4" maxlength="10000" class="w-full rounded-lg border border-violet-900/60 bg-black text-sm text-white" placeholder="What to do exactly, what not to touch, how to check it.">{@form[:admin_note].value}</textarea>
            </label>
            <p :for={{f, {msg, _}} <- @form.source.errors} class="text-xs text-red-400">{Phoenix.Naming.humanize(f)} {msg}</p>
            <div class="flex justify-end gap-2">
              <button type="button" phx-click="cancel_edit" class="rounded-lg px-4 py-2 text-sm text-gray-300 hover:bg-gray-800">Cancel</button>
              <button type="submit" class="rounded-lg bg-orange-600 px-4 py-2 text-sm font-semibold text-white hover:bg-orange-500">Save</button>
            </div>
          </.form>

          <section :if={@item.shots != [] or Feedback.can_edit?(@item, @current_user)} class="mt-6">
            <h2 class="mb-2 text-xs font-medium uppercase tracking-wide text-gray-500">Screenshots</h2>
            <div class="grid grid-cols-2 gap-3 sm:grid-cols-3">
              <div :for={shot <- @item.shots} class="group relative overflow-hidden rounded-lg border border-gray-800 bg-black">
                <a href={"/feedback/shots/#{shot.id}"} target="_blank" rel="noopener">
                  <img src={"/feedback/shots/#{shot.id}"} alt={shot.filename} loading="lazy" class="aspect-video w-full object-cover transition group-hover:opacity-90" />
                </a>
                <button
                  :if={Feedback.can_edit?(@item, @current_user)}
                  type="button"
                  phx-click="delete_shot"
                  phx-value-id={shot.id}
                  data-confirm="Remove this screenshot?"
                  class="absolute right-1 top-1 rounded bg-black/70 px-1.5 text-xs text-white opacity-0 transition hover:bg-red-600 group-hover:opacity-100"
                  aria-label="Remove screenshot"
                >
                  ✕
                </button>
              </div>
              <form
                :if={Feedback.can_edit?(@item, @current_user) and length(@item.shots) < Feedback.max_shots()}
                id="add-shots"
                phx-change="shots_change"
                phx-drop-target={@uploads.shots.ref}
                phx-hook="FeedbackPaste"
                data-upload="shots"
                class="flex aspect-video items-center justify-center rounded-lg border border-dashed border-gray-700 text-center text-sm text-gray-500"
              >
                <label class="cursor-pointer px-3 hover:text-gray-300">
                  + Add, drop or paste <.live_file_input upload={@uploads.shots} class="sr-only" />
                </label>
              </form>
            </div>
            <p :for={err <- upload_errors(@uploads.shots)} class="mt-1 text-xs text-red-400">{upload_error(err)}</p>
          </section>

          <section :if={@admin? and @item.admin_note && not @editing?} class="mt-6 rounded-lg border border-violet-900/50 bg-violet-950/20 p-4">
            <h2 class="mb-1 text-xs font-medium uppercase tracking-wide text-violet-300">Notes for Claude</h2>
            <div class="whitespace-pre-wrap text-sm text-gray-300">{@item.admin_note}</div>
          </section>
        </article>

        <section :if={@item.agent_summary || @item.commit_sha || @item.hold_reason} id="claude-report" class="mt-4 rounded-2xl border border-violet-800/50 bg-violet-950/20 p-5">
          <h2 class="flex items-center gap-2 font-semibold text-violet-200">🤖 Claude's report</h2>
          <div :if={@item.agent_summary} class="mt-2 whitespace-pre-wrap text-sm text-gray-200">{@item.agent_summary}</div>
          <p :if={@item.hold_reason} class="mt-3 rounded-md bg-orange-500/10 px-3 py-2 text-sm text-orange-200">
            Held for Deploy: {@item.hold_reason}
          </p>
          <p :if={@item.commit_sha} class="mt-3 text-xs text-gray-500">Commit <code class="text-gray-300">{String.slice(@item.commit_sha, 0, 10)}</code></p>
        </section>

        <section :if={@admin?} id="admin-panel" class="mt-4 rounded-2xl border border-orange-900/40 bg-orange-950/10 p-5">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <h2 class="font-semibold text-orange-200">Admin</h2>
            <p :if={@agent} class="text-xs text-gray-500">
              Claude's runner: {runner_line(@agent)} ·
              <.link navigate="/admin/feedback/agent" class="text-orange-300 hover:underline">settings</.link>
            </p>
          </div>
          <form id="move-form" phx-change="note" phx-submit="move" class="mt-3 space-y-3">
            <textarea
              name="note"
              rows="2"
              maxlength="10000"
              placeholder="A note for the history (for a decline: why; the author is told)"
              class="w-full rounded-lg border border-gray-800 bg-black text-sm text-white placeholder-gray-600"
            >{@note}</textarea>
            <div class="flex flex-wrap items-center gap-2">
              <button
                :for={action <- Feedback.actions_for(@item)}
                :if={action != "duplicate"}
                type="button"
                phx-click="move"
                phx-value-action={action}
                phx-value-note={@note}
                id={"action-#{action}"}
                data-confirm={confirm_text(action, @agent)}
                class={["rounded-lg px-3 py-1.5 text-sm font-medium", action_class(action)]}
              >
                {action_label(action)}
              </button>
              <span :if={"duplicate" in Feedback.actions_for(@item)} class="flex items-center gap-1">
                <input name="of" value={@dup_of} placeholder="#" class="w-16 rounded-lg border border-gray-800 bg-black py-1 text-sm text-white" />
                <button type="button" phx-click="move" phx-value-action="duplicate" phx-value-of={@dup_of} phx-value-note={@note} id="action-duplicate" class="rounded-lg bg-gray-800 px-3 py-1.5 text-sm text-gray-200 hover:bg-gray-700">
                  Duplicate of
                </button>
              </span>
            </div>
          </form>
          <p :if={@item.status == "approved"} class="mt-3 text-xs text-gray-500">
            Submit puts it in Claude's queue. Claude's runner on the dev PC takes items one at a time, fixes and tests them, commits, and reports back here{if @agent && @agent.auto_deploy, do: "; auto-deploy is on, so a change that passes its tests and review goes live by itself", else: "; auto-deploy is off, so each change waits for Deploy"}.
          </p>
        </section>

        <section class="mt-6">
          <h2 class="mb-3 text-xs font-medium uppercase tracking-wide text-gray-500">History</h2>
          <ol class="relative space-y-3 border-l border-gray-800 pl-5">
            <li :for={e <- @item.events} class="text-sm">
              <span class={["absolute -left-[5px] mt-1.5 h-2.5 w-2.5 rounded-full", if(e.actor_kind == "agent", do: "bg-violet-400", else: "bg-gray-600")]}></span>
              <span class="text-gray-300">{if e.actor_kind == "agent", do: "Claude", else: name_of(e.actor)}</span>
              <span :if={e.to_status && e.from_status} class="text-gray-500">
                moved it from {status_label(e.from_status)} to <span class="text-gray-300">{status_label(e.to_status)}</span>
              </span>
              <span :if={e.to_status && is_nil(e.from_status)} class="text-gray-500">posted it</span>
              <span class="text-gray-600">· {ago(e.inserted_at)}</span>
              <div :if={e.note} class="mt-0.5 whitespace-pre-wrap text-gray-400">{e.note}</div>
            </li>
          </ol>
        </section>
      </div>
    </div>
    """
  end

  defp runner_line(%{token_hash: nil}), do: "not set up"
  defp runner_line(%{paused: true}), do: "paused"
  defp runner_line(%{last_seen_at: nil}), do: "never called"
  defp runner_line(%{last_seen_at: t}), do: "last called " <> ago(t)

  defp action_label("submit"), do: "🤖 Submit to Claude"
  defp action_label("approve"), do: "Approve"
  defp action_label("reject"), do: "Decline"
  defp action_label("reopen"), do: "Reopen"
  defp action_label("withdraw"), do: "Take back from Claude"
  defp action_label("deploy"), do: "🚀 Deploy"
  defp action_label("mark_live"), do: "Mark as live"
  defp action_label(other), do: other

  defp action_class("submit"), do: "bg-violet-600 text-white hover:bg-violet-500"
  defp action_class("deploy"), do: "bg-orange-600 text-white hover:bg-orange-500"
  defp action_class("approve"), do: "bg-emerald-600 text-white hover:bg-emerald-500"
  defp action_class("reject"), do: "bg-gray-800 text-red-300 hover:bg-red-500/20"
  defp action_class(_), do: "bg-gray-800 text-gray-200 hover:bg-gray-700"

  defp confirm_text("submit", _),
    do:
      "Send this to Claude's queue? Claude reads the title, the details, the screenshots and your notes for Claude."

  defp confirm_text("deploy", _),
    do: "Deploy this change to production? Claude's runner backs up both databases first."

  defp confirm_text(_, _), do: nil
end

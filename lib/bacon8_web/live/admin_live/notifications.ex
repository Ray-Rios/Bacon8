defmodule Bacon8Web.AdminLive.Notifications do
  @moduledoc """
  /admin/notifications (2026-11-03): push notifications to phones and browsers (`Bacon8.Push`).

    * whether they're set up, and how (a key pair made here or by `mix bacon8.gen.vapid`, put in
      the deployment's secrets);
    * how many devices and people have them on, and a test to your own devices;
    * announcements: one notification to everyone (or only the admins), in each person's bell and
      on every device they turned notifications on for.

  Admins only. Announcements and key pairs made here go in the audit log (a key pair's private
  half never does: it's shown once, here, and kept nowhere).
  """
  use Bacon8Web, :live_view

  import Ecto.Query

  alias Bacon8.{Audit, Notifications, Push, Repo}
  alias Bacon8.Accounts.User
  alias Bacon8.Push.WebPush
  alias Bacon8Web.Components.AdminSidebar

  on_mount {Bacon8Web.UserAuth, :require_admin_user}

  @max_people 5000

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Admin - Notifications",
       keys: nil,
       form: to_form(%{"title" => "", "body" => "", "path" => "/", "audience" => "everyone"}, as: :a),
       sending: false
     )}
  end

  @impl true
  def handle_event("make_keys", _params, socket) do
    Audit.log(socket.assigns.current_user.id, "push_keys_made", "push", nil, %{})
    {:noreply, assign(socket, keys: WebPush.generate_keys())}
  end

  def handle_event("hide_keys", _params, socket), do: {:noreply, assign(socket, keys: nil)}

  def handle_event("test", _params, socket) do
    results = Push.send_test(socket.assigns.current_user)
    sent = Enum.count(results, &(&1 == :sent))

    msg =
      if results == [],
        do: "You have no devices with notifications on. Turn them on at /profile?tab=notifications first.",
        else: "Sent to #{sent} of your #{length(results)} device(s)."

    {:noreply, put_flash(socket, :info, msg)}
  end

  def handle_event("check", %{"a" => a}, socket), do: {:noreply, assign(socket, form: to_form(a, as: :a))}

  def handle_event("announce", %{"a" => a}, socket) do
    title = String.trim(a["title"] || "")
    body = String.trim(a["body"] || "")
    path = String.trim(a["path"] || "/")
    audience = if a["audience"] == "admins", do: "admins", else: "everyone"

    cond do
      socket.assigns.sending ->
        {:noreply, socket}

      title == "" ->
        {:noreply, put_flash(socket, :error, "An announcement needs a title.")}

      String.length(title) > 80 or String.length(body) > 240 ->
        {:noreply, put_flash(socket, :error, "Keep the title to 80 characters and the message to 240 (it has to fit a lock screen).")}

      not String.starts_with?(path, "/") or String.starts_with?(path, "//") ->
        {:noreply, put_flash(socket, :error, "The link is a page on this site, like /chat or /blog/our-news.")}

      true ->
        ids = audience_ids(audience)
        admin = socket.assigns.current_user
        lv = self()

        Push.background(fn ->
          n = Enum.count(ids, &match?({:ok, _}, announce(&1, admin, title, body, path)))
          send(lv, {:announced, n})
        end)

        Audit.log(admin.id, "announcement_sent", "push", nil, %{detail: "#{audience}: #{title}", people: length(ids)})
        {:noreply, socket |> assign(sending: true) |> put_flash(:info, "Sending to #{length(ids)} people…")}
    end
  end

  @impl true
  def handle_info({:announced, n}, socket) do
    {:noreply,
     socket
     |> assign(sending: false, form: to_form(%{"title" => "", "body" => "", "path" => "/", "audience" => "everyone"}, as: :a))
     |> put_flash(:info, "Announced to #{n} people.")}
  end

  # the bell's own messages (the admin's notifications arrive here too)
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp announce(user_id, admin, title, body, path) do
    Notifications.create_notification(%{
      type: "system",
      title: title,
      content: body,
      user_id: user_id,
      actor_id: admin.id,
      source_kind: "announcement",
      metadata: %{"path" => path, "source_name" => "Announcement"}
    })
  end

  defp audience_ids("admins"), do: Repo.all(from u in User, where: u.is_admin == true, select: u.id)

  defp audience_ids(_everyone),
    do: Repo.all(from u in User, where: is_nil(u.role) or u.role != "banned", order_by: u.inserted_at, limit: @max_people, select: u.id)

  @impl true
  def render(assigns) do
    assigns = assign(assigns, status: Push.status(), stats: Push.stats(), mine: length(Push.list_subscriptions(assigns.current_user.id)))

    ~H"""
    <AdminSidebar.admin_layout current_path="/admin/notifications">
      <div class="max-w-5xl mx-auto space-y-4 text-sm text-gray-300">
        <div class="dark-glass p-6 rounded-xl">
          <h1 class="text-2xl font-bold text-white">Notifications</h1>
          <p class="mt-1 text-gray-400">
            Push notifications to phones and browsers. Everything that rings the bell (mentions, invitations, replies, reports
            for the admins, announcements) also goes to each device whose person turned notifications on, at
            <a href="/profile?tab=notifications" class="text-sky-400 underline">/profile?tab=notifications</a> or in the chat sidebar.
          </p>
        </div>

        <div class="dark-glass p-6 rounded-xl space-y-3">
          <h2 class="text-lg font-semibold text-white">Status</h2>
          <%= case @status do %>
            <% :ok -> %>
              <p class="text-green-300">On. {@stats.devices} device(s) for {@stats.people} people. {@mine} of them are yours.</p>
              <button type="button" phx-click="test" class="rounded bg-gray-700 px-3 py-1.5 text-white hover:bg-gray-600">Send a test to my devices</button>
            <% {:error, msg} -> %>
              <p class="text-red-300">Not working: {msg}</p>
            <% :off -> %>
              <p class="text-amber-300">Not set up: the site offers no notifications and sends none.</p>
              <ol class="list-decimal pl-5 space-y-1">
                <li>Make a key pair (below, or <code class="text-gray-200">mix bacon8.gen.vapid</code> in a throwaway container, which writes <code>.env.push</code>).</li>
                <li>Put <code>VAPID_PUBLIC_KEY</code>, <code>VAPID_PRIVATE_KEY</code> and <code>VAPID_SUBJECT</code> (<code>mailto:</code> an address the push services can write to) in the deployment's secrets, next to the others. Never in git.</li>
                <li>Restart the site. This page then says "On".</li>
              </ol>
              <p class="text-gray-400">Keep the pair for good: a new one stops every device until its person turns notifications on again.</p>
              <button :if={!@keys} type="button" phx-click="make_keys" class="rounded bg-sky-700 px-3 py-1.5 text-white hover:bg-sky-600">Make a key pair</button>
          <% end %>

          <div :if={@keys} class="rounded-lg border border-amber-600 bg-amber-950/40 p-4 space-y-2">
            <p class="text-amber-200">Shown once and kept nowhere. Copy both into the deployment's secrets now; the private key is a secret.</p>
            <pre id="vapid-keys" class="whitespace-pre-wrap break-all rounded bg-black/60 p-3 text-xs text-gray-200">VAPID_PUBLIC_KEY={@keys.public}
    VAPID_PRIVATE_KEY={@keys.private}
    VAPID_SUBJECT=mailto:you@example.com</pre>
            <div class="flex gap-2">
              <button type="button" phx-hook="CopyText" id="copy-vapid" data-target="vapid-keys" class="rounded bg-gray-700 px-3 py-1.5 text-white hover:bg-gray-600">Copy</button>
              <button type="button" phx-click="hide_keys" class="rounded bg-gray-800 px-3 py-1.5 text-white hover:bg-gray-700">Hide</button>
            </div>
          </div>
        </div>

        <div class="dark-glass p-6 rounded-xl space-y-3">
          <h2 class="text-lg font-semibold text-white">Announce</h2>
          <p class="text-gray-400">One notification to everyone (or only the admins): in each person's bell, and on their phones if they turned notifications on. Use it for news people want, not often.</p>
          <.form for={@form} phx-change="check" phx-submit="announce" class="space-y-3">
            <div>
              <label class="block text-xs text-gray-400">Title (up to 80 characters)</label>
              <input type="text" name="a[title]" value={@form[:title].value} maxlength="80" class="w-full rounded bg-gray-900 border border-gray-700 px-3 py-2 text-white" />
            </div>
            <div>
              <label class="block text-xs text-gray-400">Message (up to 240)</label>
              <textarea name="a[body]" maxlength="240" rows="3" class="w-full rounded bg-gray-900 border border-gray-700 px-3 py-2 text-white">{@form[:body].value}</textarea>
            </div>
            <div class="flex flex-wrap gap-4">
              <div>
                <label class="block text-xs text-gray-400">Opens (a page on this site)</label>
                <input type="text" name="a[path]" value={@form[:path].value} class="rounded bg-gray-900 border border-gray-700 px-3 py-2 text-white" />
              </div>
              <div>
                <label class="block text-xs text-gray-400">To</label>
                <select name="a[audience]" class="rounded bg-gray-900 border border-gray-700 px-3 py-2 text-white">
                  <option value="everyone" selected={@form[:audience].value != "admins"}>Everyone</option>
                  <option value="admins" selected={@form[:audience].value == "admins"}>Only the admins</option>
                </select>
              </div>
            </div>
            <button type="submit" disabled={@sending} class="rounded bg-sky-700 px-4 py-2 font-medium text-white hover:bg-sky-600 disabled:opacity-50">
              {if @sending, do: "Sending…", else: "Send announcement"}
            </button>
          </.form>
        </div>
      </div>
    </AdminSidebar.admin_layout>
    """
  end
end

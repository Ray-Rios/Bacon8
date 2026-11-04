defmodule Bacon8Web.PushOptIn do
  @moduledoc """
  "Notify me on this device" (2026-11-03, `Bacon8.Push`): turns push notifications on or off for
  the browser or installed web app it runs in, and (in full) lists the person's devices with a
  test button and a lock-screen preview switch.

  The `PushOptIn` hook (assets/js/push_opt_in.ts) does the browser's part. The permission prompt
  only appears straight from a tap, so the buttons that ask (`data-push="on"`/`"off"`) are
  handled in the browser, which then tells this component (`push_device`, `push_subscribed`,
  `push_unsubscribed`, `push_failed`).

      <.live_component module={Bacon8Web.PushOptIn} id="chat-push" current_user={@current_user} compact />

  `compact` (the chat sidebar) is one line and reads nothing from the database until the browser
  says it can do push; the full one is the profile's Notifications tab.
  """
  use Bacon8Web, :live_component

  alias Bacon8.Push

  @impl true
  def mount(socket), do: {:ok, assign(socket, device: nil, state: nil, message: nil, subs: [], tested_at: nil)}

  @impl true
  def update(assigns, socket) do
    socket = socket |> assign(assigns) |> assign_new(:compact, fn -> false end) |> assign(status: Push.status())
    socket = assign(socket, public_key: if(socket.assigns.status == :ok, do: Push.public_key()))
    {:ok, if(socket.assigns.compact, do: socket, else: load(socket))}
  end

  defp load(socket), do: assign(socket, subs: Push.list_subscriptions(socket.assigns.current_user.id))

  @impl true
  def handle_event("push_device", params, socket) do
    device = %{
      supported: params["supported"] == true,
      ios: params["ios"] == true,
      standalone: params["standalone"] == true,
      permission: to_string(params["permission"] || "default"),
      endpoint: if(is_binary(params["endpoint"]), do: params["endpoint"])
    }

    {:noreply, socket |> assign(device: device) |> assign(state: state(device, socket.assigns.current_user))}
  end

  def handle_event("push_subscribed", %{"subscription" => sub} = params, socket) when is_map(sub) do
    ua = if is_binary(params["ua"]), do: params["ua"]

    case Push.subscribe(socket.assigns.current_user, sub, ua) do
      {:ok, saved} ->
        device = Map.merge(socket.assigns.device || %{supported: true, ios: false, standalone: false}, %{permission: "granted", endpoint: saved.endpoint})
        {:noreply, socket |> assign(device: device, state: :on, message: "Notifications are on for this device.") |> reload()}

      {:error, msg} ->
        {:noreply, assign(socket, message: msg)}
    end
  end

  def handle_event("push_unsubscribed", %{"endpoint" => endpoint}, socket) do
    Push.unsubscribe(socket.assigns.current_user, endpoint)
    device = Map.put(socket.assigns.device || %{supported: true, ios: false, standalone: false, permission: "granted"}, :endpoint, nil)
    {:noreply, socket |> assign(device: device, state: :off, message: "Notifications are off for this device.") |> reload()}
  end

  def handle_event("push_failed", %{"reason" => reason}, socket) do
    {:noreply, assign(socket, message: "This browser wouldn't turn notifications on (#{String.slice(to_string(reason), 0, 120)}).")}
  end

  def handle_event("test", _params, socket) do
    if socket.assigns.tested_at && DateTime.diff(DateTime.utc_now(), socket.assigns.tested_at) < 10 do
      {:noreply, socket}
    else
      results = Push.send_test(socket.assigns.current_user)
      sent = Enum.count(results, &(&1 == :sent))

      message =
        cond do
          results == [] -> "No devices have notifications on yet."
          sent == length(results) -> "Sent to #{plural(sent, "device")}. It should arrive in a few seconds."
          true -> "Sent to #{sent} of #{plural(length(results), "device")}; the others didn't take it (any that are gone have been removed)."
        end

      {:noreply, socket |> assign(message: message, tested_at: DateTime.utc_now()) |> reload()}
    end
  end

  def handle_event("remove", %{"id" => id}, socket) do
    Push.remove_subscription(socket.assigns.current_user, id)
    socket = reload(socket)
    {:noreply, assign(socket, state: state(socket.assigns.device, socket.assigns.current_user))}
  end

  def handle_event("previews", %{"id" => id} = params, socket) do
    Push.set_previews(socket.assigns.current_user, id, params["on"] == "true")
    {:noreply, reload(socket)}
  end

  defp reload(socket), do: if(socket.assigns.compact, do: socket, else: load(socket))

  # what to show for this device
  defp state(nil, _user), do: nil
  defp state(%{supported: false, ios: true, standalone: false}, _user), do: :home_screen
  defp state(%{supported: false}, _user), do: :unsupported
  defp state(%{permission: "denied"}, _user), do: :blocked
  defp state(%{endpoint: endpoint}, user) when is_binary(endpoint), do: if(Push.registered?(user, endpoint), do: :on, else: :off)
  defp state(_device, _user), do: :off

  defp plural(1, word), do: "1 #{word}"
  defp plural(n, word), do: "#{n} #{word}s"

  @impl true
  def render(%{compact: true} = assigns) do
    ~H"""
    <div id={@id} phx-hook="PushOptIn" phx-target={@myself} data-key={@public_key} class="mb-4 text-xs text-gray-400">
      <%= cond do %>
        <% @status != :ok or @state in [nil, :unsupported] -> %>
        <% @state == :home_screen -> %>
          <p>🔔 On an iPhone or iPad: tap Share, then <span class="text-gray-200">Add to Home Screen</span>, and open Bacon8 from there to get notifications.</p>
        <% @state == :blocked -> %>
          <p>🔕 Notifications are blocked for this site in this browser's settings.</p>
        <% @state == :on -> %>
          <p>🔔 Notifications are on for this device · <.link navigate="/profile?tab=notifications" class="text-cyan-400 hover:underline">settings</.link></p>
        <% true -> %>
          <button type="button" data-push="on" class="w-full rounded border border-cyan-500/40 bg-cyan-500/10 px-2 py-1.5 text-left text-cyan-200 hover:bg-cyan-500/20">
            🔔 Notify me on this device about mentions and invitations
          </button>
      <% end %>
      <p :if={@message} class="mt-1 text-gray-300">{@message}</p>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div id={@id} phx-hook="PushOptIn" phx-target={@myself} data-key={@public_key} class="space-y-5 text-sm text-gray-300">
      <p>
        Get a notification on your phone or computer when someone mentions you, invites you to a channel or replies to you,
        even when Bacon8 isn't open. It works in Chrome, Edge, Firefox and Samsung Internet on Android and computers, and on
        iPhone and iPad (iOS 16.4 or later) once Bacon8 is on the Home Screen. Turn it on separately on each device.
      </p>

      <%= cond do %>
        <% @status == :off -> %>
          <p class="rounded-lg border border-gray-700 bg-gray-800/50 p-4">This site hasn't set up notifications yet.</p>
        <% match?({:error, _}, @status) -> %>
          <p class="rounded-lg border border-red-700 bg-red-900/30 p-4">Notifications aren't working on this site right now.</p>
        <% true -> %>
          <div class="rounded-lg border border-gray-700 bg-gray-800/50 p-4 space-y-3">
            <h3 class="font-medium text-white">This device</h3>
            <%= case @state do %>
              <% nil -> %>
                <p class="text-gray-400">Checking what this browser can do…</p>
              <% :home_screen -> %>
                <ol class="list-decimal pl-5 space-y-1">
                  <li>Tap the Share button (the square with an arrow) in Safari.</li>
                  <li>Choose <span class="text-white">Add to Home Screen</span>, then <span class="text-white">Add</span>.</li>
                  <li>Open Bacon8 from its new icon, sign in, and come back to this page to turn notifications on.</li>
                </ol>
              <% :unsupported -> %>
                <p>This browser can't get push notifications. On Android use Chrome, Firefox, Edge or Samsung Internet.</p>
              <% :blocked -> %>
                <p>Notifications are blocked for this site. Allow them in this browser's site settings (the icon left of the address), then reload this page.</p>
              <% :on -> %>
                <div class="flex flex-wrap items-center gap-3">
                  <span class="text-green-300">🔔 On for this device.</span>
                  <button type="button" data-push="off" class="rounded bg-gray-700 px-3 py-1.5 text-white hover:bg-gray-600">Turn off on this device</button>
                </div>
              <% :off -> %>
                <button type="button" data-push="on" class="rounded bg-cyan-600 px-4 py-2 font-medium text-white hover:bg-cyan-500">
                  🔔 Turn on notifications on this device
                </button>
            <% end %>
          </div>

          <div class="rounded-lg border border-gray-700 bg-gray-800/50 p-4 space-y-3">
            <div class="flex flex-wrap items-center justify-between gap-2">
              <h3 class="font-medium text-white">Your devices ({length(@subs)})</h3>
              <button :if={@subs != []} type="button" phx-click="test" phx-target={@myself} class="rounded bg-gray-700 px-3 py-1.5 text-white hover:bg-gray-600">
                Send a test
              </button>
            </div>
            <p :if={@subs == []} class="text-gray-400">None yet.</p>
            <ul class="divide-y divide-gray-700">
              <li :for={s <- @subs} class="flex flex-wrap items-center justify-between gap-2 py-2">
                <div>
                  <div class="text-gray-200">
                    {Push.device_label(s.user_agent)}
                    <span :if={@device && @device.endpoint == s.endpoint} class="ml-1 rounded bg-cyan-900/60 px-1.5 text-xs text-cyan-200">this one</span>
                  </div>
                  <div class="text-xs text-gray-500">
                    Since {Calendar.strftime(s.inserted_at, "%b %-d, %Y")}{if s.last_used_at, do: " · last sent #{Calendar.strftime(s.last_used_at, "%b %-d")}"}
                  </div>
                </div>
                <div class="flex items-center gap-3">
                  <label class="flex items-center gap-1 text-xs text-gray-400" title="Off: the lock screen says only that something is new">
                    <input type="checkbox" checked={s.previews} phx-click="previews" phx-value-id={s.id} phx-value-on={to_string(!s.previews)} phx-target={@myself} class="rounded" />
                    Show message text
                  </label>
                  <button type="button" phx-click="remove" phx-value-id={s.id} phx-target={@myself} class="text-xs text-red-400 hover:underline">Remove</button>
                </div>
              </li>
            </ul>
          </div>
      <% end %>

      <p :if={@message} class="text-gray-200">{@message}</p>
    </div>
    """
  end
end

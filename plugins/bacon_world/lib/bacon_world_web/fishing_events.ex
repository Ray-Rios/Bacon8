defmodule BaconWorldWeb.FishingEvents do
  @moduledoc """
  Fishing (2026-10-26), a part of `BaconWorldWeb.PlayLive`. The water is `BaconWorld.Water`.

  The server keeps the clock, so a client can't fish faster or pick its catch:

    * `"fish_cast"` `%{x, z}` (scene units: where the bobber lands) - with a fishing pole in the
      right hand, standing by water, onto water within reach. Replies `%{ok, water}`; then, after
      a few seconds, a fish bites: the server pushes `"fish_bite"`.
    * `"fish_reel"` - within `window_ms/0` of the bite (and still where you cast from): most of the
      time you land it (`BaconWorld.Water.roll/2` says what) and it goes in the bags. Replies
      `%{ok, result, item_id, inventory}`; `result` is `"caught"`, `"early"` (nothing had bitten),
      `"late"`, `"slipped"`, `"moved"`, `"full"` (no room in the bags) or `"none"`.
    * `"fish_stop"` - the line comes in (the client moved, swung, opened a window...).

  A bite nobody answers in time escapes: the server pushes `"fish_escaped"`.
  """
  import Phoenix.LiveView, only: [push_event: 3]
  import Phoenix.Component, only: [assign: 3]

  alias BaconWorld.{Inventory, Water}
  alias BaconWorld.Mobs.Brain

  @bite_ms 3_500..12_000
  @window_ms 1_800
  @catch_chance 0.8
  # metres the angler may shift after casting before the line counts as abandoned
  @stay 2.5

  def window_ms, do: @window_ms

  def handle_event("fish_cast", %{"x" => bx, "z" => bz}, socket) when is_number(bx) and is_number(bz) do
    u = Brain.u()

    with %{} = me <- current(socket),
         false <- socket.assigns[:is_dead?] || false,
         true <- holding_pole?(me.character_id) || {:error, :no_pole},
         {px, pz} = metres(me),
         {:ok, kind} <- Water.cast(px, pz, bx / u, bz / u) do
      token = make_ref()
      Process.send_after(self(), {:fish_bite, token}, Enum.random(@bite_ms))
      {:reply, %{ok: true, water: Atom.to_string(kind), name: Water.name_at(bx / u, bz / u)}, assign(socket, :fishing, %{token: token, kind: kind, at: {px, pz}, bite_at: nil})}
    else
      {:error, reason} -> {:reply, %{ok: false, error: message(reason)}, assign(socket, :fishing, nil)}
      _ -> {:reply, %{ok: false, error: "You can't fish right now."}, assign(socket, :fishing, nil)}
    end
  end

  def handle_event("fish_cast", _params, socket), do: {:reply, %{ok: false, error: "You can't fish there."}, socket}

  def handle_event("fish_reel", _params, socket) do
    f = socket.assigns[:fishing]
    socket = assign(socket, :fishing, nil)
    me = current(socket)

    cond do
      is_nil(f) or is_nil(me) -> {:reply, %{ok: false, result: "none"}, socket}
      moved?(me, f) -> {:reply, %{ok: false, result: "moved"}, socket}
      is_nil(f.bite_at) -> {:reply, %{ok: false, result: "early"}, socket}
      now() - f.bite_at > @window_ms -> {:reply, %{ok: false, result: "late"}, socket}
      :rand.uniform() > @catch_chance -> {:reply, %{ok: false, result: "slipped"}, socket}
      true -> land(me.character_id, Water.roll(f.kind), socket)
    end
  end

  def handle_event("fish_stop", _params, socket), do: {:reply, %{ok: true}, assign(socket, :fishing, nil)}

  @doc "The bite (PlayLive's `{:fish_bite, token}`): tell the client, start the clock."
  def bite(token, socket) do
    case socket.assigns[:fishing] do
      %{token: ^token, bite_at: nil} = f ->
        Process.send_after(self(), {:fish_escape, token}, @window_ms + 150)
        socket |> assign(:fishing, %{f | bite_at: now()}) |> push_event("fish_bite", %{window_ms: @window_ms})

      _ ->
        socket
    end
  end

  @doc "Nobody reeled in (PlayLive's `{:fish_escape, token}`)."
  def escape(token, socket) do
    case socket.assigns[:fishing] do
      %{token: ^token} -> socket |> assign(:fishing, nil) |> push_event("fish_escaped", %{})
      _ -> socket
    end
  end

  defp land(character_id, item_id, socket) do
    case Inventory.add(character_id, item_id, 1) do
      {:ok, _} -> {:reply, %{ok: true, result: "caught", item_id: item_id, inventory: Inventory.payload(character_id)}, socket}
      {:error, :inventory_full} -> {:reply, %{ok: false, result: "full", item_id: item_id}, socket}
      _ -> {:reply, %{ok: false, result: "slipped"}, socket}
    end
  end

  defp holding_pole?(character_id) do
    character_id |> Inventory.equipment() |> Inventory.gear_ids() |> Map.get("main") == "fishing_pole"
  end

  defp moved?(me, %{at: {x, z}}) do
    {px, pz} = metres(me)
    :math.sqrt((px - x) * (px - x) + (pz - z) * (pz - z)) > @stay
  end

  defp metres(%{position: %{x: x, z: z}}), do: {(x || 0.0) / Brain.u(), (z || 0.0) / Brain.u()}
  defp metres(_), do: {0.0, 0.0}

  defp message(:no_pole), do: "You need a fishing pole in your hands to fish."
  defp message(:not_at_water), do: "You need to stand at the water's edge to fish."
  defp message(:not_on_water), do: "Your line has to land on the water."
  defp message(:too_far), do: "You can't cast that far."
  defp message(_), do: "You can't fish right now."

  defp now, do: System.monotonic_time(:millisecond)

  defp current(socket), do: socket.assigns[:current_character_runtime] || socket.assigns[:current_character_payload]
end

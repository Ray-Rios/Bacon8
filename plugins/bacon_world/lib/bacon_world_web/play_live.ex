defmodule BaconWorldWeb.PlayLive do
  @moduledoc """
  /games/bacon_world - character select and creator, then the live 3D zone.

  The 3D client is the `WorldCharacterUIScene` hook (this plugin's
  `assets/js`): the select screen and creator are `front-ui.ts` over the 3D stage
  (`character-stage.ts`), and characters are dressed from their appearance
  (`human-factory.ts`, `BaconWorld.Appearance`). The server is authoritative: it checks every move for speed,
  bounds and collisions, runs combat, and relays positions and chat to
  nearby players over PubSub and Presence.

  `?ch=<character id>` re-enters the world after a reconnect or reload.
  """
  use Bacon8Web, :live_view
  require Logger
  alias BaconWorld.{Combat, Items, Models, World}
  alias BaconWorldWeb.GameEvents
  alias Phoenix.PubSub
  alias Bacon8Web.Presence

  @max_move_speed 30.0
  @interest_radius 2000.0
  @chat_radius 64.0
  @collision_radius 1.1
  @min_dt_seconds 0.04
  @position_persist_interval_ms 1000
  @presence_broadcast_interval_ms 100

  # Fighting, looting and the inventory (BaconWorldWeb.GameEvents).
  @game_events ~w(fetch_mobs melee_attack loot_open loot_take loot_all loot_close
                  inventory_fetch inventory_move inventory_equip inventory_unequip inventory_destroy
                  merchant_open merchant_buy merchant_sell)

  on_mount {Bacon8Web.UserAuth, :require_authenticated_user}

  @impl true
  def handle_params(%{"ch" => character_id}, _uri, socket) do
    if connected?(socket) do
      case World.character_login_payload(socket.assigns.current_user.id, character_id) do
        {:ok, payload} ->
          if account_online_elsewhere?(socket) do
            Logger.warning("bacon_world:handle_params account_already_online user_id=#{socket.assigns.current_user.id} character_id=#{payload.character_id}")
            {:noreply,
             socket
             |> put_flash(:error, "You already have a character logged in from another session. Log out there first.")
             |> push_patch(to: ~p"/games/bacon_world")}
          else
            socket = socket |> leave_zone_presence() |> join_zone_presence(payload) |> track_account_presence(payload.character_id)

            {:noreply,
             socket
             |> assign(
               current_character_payload: payload,
               current_character_runtime: payload,
               world_mode?: true,
               last_world_update_ms: System.monotonic_time(:millisecond)
             )
             |> push_event("zone_presence_state", %{online_characters: socket.assigns.zone_online_characters})
             |> push_event("character_login_ready", payload)
             |> schedule_regen(payload.character_id)}
          end

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_params(_params, _uri, socket) do
    if socket.assigns.world_mode? do
      socket =
        socket
        |> leave_world()
        |> push_event("zone_presence_state", %{online_characters: []})
        |> push_event("world_logged_out", %{})

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_user
    characters = World.list_user_characters(current_user.id)
    available_models = Models.list()

    if connected?(socket) do
      PubSub.subscribe(Bacon8.PubSub, characters_topic(current_user.id))
    end

    {:ok,
     assign(socket,
       page_title: "Bacon World",
       human_assets: Models.human_assets(),
       item_catalog: Items.catalog_payload(),
       equipment: %{},
       swing_at: %{},
       mobs_zone: nil,
       looting: nil,
       level: 1,
       characters: characters,
       selected_character_id: nil,
       current_character_payload: nil,
      current_character_runtime: nil,
       world_mode?: false,
       has_characters?: characters != [],
       scene_characters: to_scene_characters(characters),
       current_zone_topic: nil,
      current_presence_key: nil,
      account_presence_tracked?: false,
      account_presence_ref: nil,
       zone_online_characters: [],
       last_world_update_ms: nil,
      last_position_persist_ms: nil,
      last_presence_update_ms: nil,
      last_remote_broadcast_ms: nil,
      pending_respawn_timer: nil,
      pending_spawn_coords: nil,
      is_dead?: false,
       scene_model_paths: Enum.map(available_models, & &1.model_path),
        available_models: available_models,
       create_form: to_form(%{"name" => "", "character_type" => "", "model_path" => ""}, as: "character")
     )}
  end

  @impl true
  def handle_event("back_to_games", _params, socket) do
    socket =
      if socket.assigns.world_mode? do
        socket
        |> leave_world()
        |> push_event("zone_presence_state", %{online_characters: []})
        |> push_event("world_logged_out", %{})
      else
        socket
      end

    {:noreply, push_navigate(socket, to: ~p"/games")}
  end

  def handle_event("validate_character", %{"character" => params}, socket) do
    {:noreply, assign(socket, create_form: to_form(params, as: "character"))}
  end

  def handle_event("create_character", %{"character" => params}, socket) do
    Logger.info("bacon_world:create_character user_id=#{socket.assigns.current_user.id} name=#{inspect(params["name"])} type=#{inspect(params["character_type"])} model=#{inspect(params["model_path"])}")

    case World.create_character(socket.assigns.current_user.id, params) do
      {:ok, _character} ->
        characters = World.list_user_characters(socket.assigns.current_user.id)
        Logger.info("bacon_world:create_character success user_id=#{socket.assigns.current_user.id} character_count=#{length(characters)}")

        PubSub.broadcast(Bacon8.PubSub, characters_topic(socket.assigns.current_user.id), :characters_updated)

        {:noreply,
         socket
         |> assign(
           characters: characters,
           has_characters?: true,
           scene_characters: to_scene_characters(characters),
           create_form: to_form(%{"name" => "", "character_type" => "", "model_path" => ""}, as: "character")
         )
         |> put_flash(:info, "Character created and approved.")}

      {:error, :character_limit_reached} ->
        Logger.warning("bacon_world:create_character limit_reached user_id=#{socket.assigns.current_user.id}")
        {:noreply, put_flash(socket, :error, "You already have the maximum of 16 characters.")}

      {:error, :invalid_model_path} ->
        Logger.warning("bacon_world:create_character invalid_model user_id=#{socket.assigns.current_user.id} model=#{inspect(params["model_path"])}")
        {:noreply, put_flash(socket, :error, "Selected model is not valid.")}

      {:error, :default_zone_missing} ->
        Logger.error("bacon_world:create_character missing_default_zone user_id=#{socket.assigns.current_user.id}")
        {:noreply, put_flash(socket, :error, "The lobby zone is missing. Run mix bacon8.migrate.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        Logger.warning("bacon_world:create_character changeset_error user_id=#{socket.assigns.current_user.id} errors=#{inspect(changeset.errors)}")
        {:noreply,
         socket
         |> assign(create_form: to_form(changeset, as: "character"))
         |> put_flash(:error, "Please fix the highlighted character fields.")}
    end
  end

  def handle_event("select_character", %{"character_id" => character_id}, socket) do
    character = World.get_character_for_user(socket.assigns.current_user.id, character_id)

    if character do
      Logger.info("bacon_world:select_character user_id=#{socket.assigns.current_user.id} character_id=#{character.id} name=#{character.name}")
      {:noreply, assign(socket, selected_character_id: character.id, scene_characters: to_scene_characters(socket.assigns.characters))}
    else
      Logger.warning("bacon_world:select_character not_found user_id=#{socket.assigns.current_user.id} character_id=#{character_id}")
      {:noreply, put_flash(socket, :error, "Could not select that character.")}
    end
  end

  def handle_event("three_ui_creator_focus", _params, socket) do
    {:noreply, put_flash(socket, :info, "Use the creation form below to make a character.")}
  end

  def handle_event("three_ui_create_character", params, socket) do
    user_id = socket.assigns.current_user.id
    normalized_params = normalize_three_ui_create_params(params, socket.assigns.scene_model_paths)
    Logger.info("bacon_world:three_ui_create_character user_id=#{user_id} name=#{inspect(normalized_params["name"])} body=#{inspect(get_in(normalized_params, ["appearance", "body"]))}")

    case World.create_character(user_id, normalized_params) do
      {:ok, character} ->
        characters = World.list_user_characters(user_id)
        Logger.info("bacon_world:three_ui_create_character success user_id=#{user_id} character_count=#{length(characters)}")

        PubSub.broadcast(Bacon8.PubSub, characters_topic(user_id), :characters_updated)

        {:reply, %{ok: true, character_id: character.id},
         socket
         |> assign(
           characters: characters,
           has_characters?: true,
           selected_character_id: character.id,
           scene_characters: to_scene_characters(characters),
           create_form: to_form(%{"name" => "", "character_type" => "", "model_path" => ""}, as: "character")
         )}

      {:error, reason} ->
        Logger.warning("bacon_world:three_ui_create_character failed user_id=#{user_id} reason=#{inspect(create_error_reason(reason))}")
        {:reply, %{ok: false, error: create_error_message(reason)}, socket}
    end
  end

  def handle_event("three_ui_update_appearance", %{"character_id" => character_id, "appearance" => look}, socket) do
    user_id = socket.assigns.current_user.id

    if active_account_character_id(user_id) == character_id do
      {:reply, %{ok: false, error: "Leave the world with this character before changing its look."}, socket}
    else
      case World.update_appearance(user_id, character_id, look) do
        {:ok, _look} ->
          characters = World.list_user_characters(user_id)
          PubSub.broadcast(Bacon8.PubSub, characters_topic(user_id), :characters_updated)
          {:reply, %{ok: true}, assign(socket, characters: characters, scene_characters: to_scene_characters(characters))}

        {:error, :not_found} ->
          {:reply, %{ok: false, error: "Character not found."}, socket}

        {:error, reason} ->
          Logger.warning("bacon_world:update_appearance failed user_id=#{user_id} character_id=#{character_id} reason=#{inspect(reason)}")
          {:reply, %{ok: false, error: "That look couldn't be saved."}, socket}
      end
    end
  end

  def handle_event("three_ui_update_appearance", _params, socket) do
    {:reply, %{ok: false, error: "That look couldn't be saved."}, socket}
  end

  # Other players' looks, for drawing them (the client batches unknown ids).
  def handle_event("fetch_appearances", %{"ids" => ids}, socket) when is_list(ids) do
    {:reply, %{appearances: World.appearances_for(ids)}, socket}
  end

  def handle_event("fetch_appearances", _params, socket), do: {:reply, %{appearances: %{}}, socket}

  def handle_event("login_character", _params, socket) do
    selected_character_id = socket.assigns.selected_character_id
    Logger.info("bacon_world:login_character user_id=#{socket.assigns.current_user.id} selected_character_id=#{inspect(selected_character_id)}")

    case selected_character_id && World.character_login_payload(socket.assigns.current_user.id, selected_character_id) do
      {:ok, payload} ->
        if account_online_elsewhere?(socket) do
          Logger.warning("bacon_world:login_character account_already_online user_id=#{socket.assigns.current_user.id} character_id=#{payload.character_id}")
          {:noreply, put_flash(socket, :error, "You already have a character logged in from another session. Log out there first.")}
        else
          socket = socket |> leave_zone_presence() |> join_zone_presence(payload) |> track_account_presence(payload.character_id)
          Logger.info("bacon_world:login_character success user_id=#{socket.assigns.current_user.id} character_id=#{payload.character_id} zone=#{payload.zone.slug}")

          {:noreply,
           socket
           |> assign(
             current_character_payload: payload,
             current_character_runtime: payload,
             world_mode?: true,
             last_world_update_ms: System.monotonic_time(:millisecond)
           )
           |> push_event("zone_presence_state", %{online_characters: socket.assigns.zone_online_characters})
           |> push_event("character_login_ready", payload)
           |> push_patch(to: ~p"/games/bacon_world?ch=#{payload.character_id}")}
        end

      _ ->
        Logger.warning("bacon_world:login_character missing_selection user_id=#{socket.assigns.current_user.id}")
        {:noreply, put_flash(socket, :error, "Select a character before logging in.")}
    end
  end

  def handle_event("logout_character", _params, socket) do
    {:noreply,
     socket
     |> leave_world()
     |> push_event("zone_presence_state", %{online_characters: []})
     |> push_event("world_logged_out", %{})
     |> push_patch(to: ~p"/games/bacon_world")}
  end

  def handle_event("delete_character", %{"character_id" => character_id}, socket) do
    user_id = socket.assigns.current_user.id

    if active_account_character_id(user_id) == character_id do
      Logger.warning("bacon_world:delete_character blocked_active user_id=#{user_id} character_id=#{character_id}")
      {:noreply, put_flash(socket, :error, "Log out of this character before deleting it.")}
    else
      case World.delete_character_for_user(user_id, character_id) do
        {:ok, character} ->
          characters = World.list_user_characters(user_id)
          selected_character_id = if socket.assigns.selected_character_id == character.id, do: nil, else: socket.assigns.selected_character_id

          Logger.info("bacon_world:delete_character success user_id=#{user_id} character_id=#{character.id} remaining=#{length(characters)}")

          PubSub.broadcast(Bacon8.PubSub, characters_topic(user_id), :characters_updated)

          {:noreply,
           socket
           |> assign(
             characters: characters,
             selected_character_id: selected_character_id,
             has_characters?: characters != [],
             scene_characters: to_scene_characters(characters)
           )
           |> put_flash(:info, "Character deleted.")}

        {:error, :not_found} ->
          Logger.warning("bacon_world:delete_character not_found user_id=#{user_id} character_id=#{character_id}")
          {:noreply, put_flash(socket, :error, "Character not found.")}

        {:error, reason} ->
          Logger.warning("bacon_world:delete_character failed user_id=#{user_id} character_id=#{character_id} reason=#{inspect(reason)}")
          {:noreply, put_flash(socket, :error, "Could not delete character.")}
      end
    end
  end

  def handle_event("toggle_calendar", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("toggle_start_menu", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("open_app", _params, socket) do
    {:noreply, socket}
  end

  def handle_event(event, params, socket) when event in @game_events do
    GameEvents.handle_event(event, params, socket)
  end

  def handle_event("world_position_update", params, socket) do
    with %{"x" => raw_x, "y" => raw_y, "z" => raw_z, "heading" => raw_heading} <- stringify_keys(params),
         {:ok, x} <- to_float(raw_x),
         {:ok, y} <- to_float(raw_y),
         {:ok, z} <- to_float(raw_z),
         {:ok, heading} <- to_float(raw_heading),
         motion = motion_flags(params),
         %{} = current_character <- current_character(socket),
         :ok <- validate_ground_bounds(y),
         :ok <- validate_move_speed(socket, current_character.position, x, y, z),
         :ok <- validate_player_collision(socket.assigns.zone_online_characters || [], current_character.character_id, current_character.position, x, z) do
      topic = socket.assigns.current_zone_topic
      now_ms = System.monotonic_time(:millisecond)

      last_presence_ms = socket.assigns.last_presence_update_ms || (now_ms - @presence_broadcast_interval_ms - 1)
      should_broadcast = not is_nil(topic) and now_ms - last_presence_ms >= @presence_broadcast_interval_ms

      if should_broadcast do
        presence_updated_at = System.system_time(:millisecond)

        Presence.update(self(), topic, current_character.character_id, fn meta ->
          Map.merge(meta, %{x: x, y: y, z: z, heading: heading, updated_at: presence_updated_at})
        end)
      end

      if not is_nil(topic) do
        PubSub.broadcast(Bacon8.PubSub, topic, {:zone_position_update, %{
          character_id: current_character.character_id,
          character_name: current_character.name,
          character_type: current_character.character_type,
          model_path: current_character.model_path,
          user_id: socket.assigns.current_user.id,
          x: x,
          y: y,
          z: z,
          heading: heading,
          m: motion,
          hp: Map.get(current_character, :hp, 10),
          max_hp: Map.get(current_character, :max_hp, 10)
        }})
      end

      last_persist_ms = socket.assigns.last_position_persist_ms || (now_ms - @position_persist_interval_ms - 1)
      should_persist = now_ms - last_persist_ms >= @position_persist_interval_ms

      if should_persist do
        persist_character_position_async(socket.assigns.current_user.id, current_character, x, y, z, heading)
      end

      {:noreply,
       assign(socket,
         current_character_runtime:
           Map.put(current_character, :position, %{
             x: x,
             y: y,
             z: z,
             heading: heading
           }),
         last_world_update_ms: now_ms,
         last_presence_update_ms: if(should_broadcast, do: now_ms, else: last_presence_ms),
         last_position_persist_ms: if(should_persist, do: now_ms, else: last_persist_ms)
       )}
    else
      {:error, :invalid_move} ->
        Logger.warning("bacon_world:world_position_update_REJECTED invalid_move character_id=#{inspect(current_character(socket) && current_character(socket).character_id)}")
        {:noreply, push_authoritative_correction(socket)}

      other ->
        Logger.warning("bacon_world:world_position_update_REJECTED other=#{inspect(other)} character_id=#{inspect(current_character(socket) && current_character(socket).character_id)}")
        {:noreply, socket}
    end
  end

  def handle_event("world_chat_message", %{"message" => raw_message}, socket) do
    message = raw_message |> to_string() |> String.trim()

    cond do
      message == "" ->
        {:noreply, socket}

      String.length(message) > 220 ->
        {:noreply, put_flash(socket, :error, "Chat message is too long.")}

      is_nil(socket.assigns.current_zone_topic) or is_nil(current_character(socket)) ->
        {:noreply, socket}

      true ->
        current = current_character(socket)

        payload = %{
          character_id: current.character_id,
          character_name: current.name,
          message: message,
          x: current.position.x,
          y: current.position.y,
          z: current.position.z,
          sent_at: DateTime.utc_now() |> DateTime.to_iso8601()
        }

        PubSub.broadcast(Bacon8.PubSub, socket.assigns.current_zone_topic, {:zone_chat_message, payload})
        {:noreply, socket}
    end
  end

  # No spells yet (Throw Stone, the old web-lobby test, is retired): melee first.
  def handle_event("cast_spell", _params, socket),
    do: {:noreply, push_event(socket, "spell_error", %{reason: "unknown_spell"})}

  def handle_event("toggle_pvp", _params, socket) do
    with %{} = current <- current_character(socket),
         {:ok, flag} <- World.toggle_pvp(socket.assigns.current_user.id, current.character_id) do
      {:noreply, push_event(socket, "pvp_flag_changed", %{pvp_flagged: flag})}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("respawn_now", _params, socket) do
    current = current_character(socket)

    if current && socket.assigns.world_mode? do
      if timer = socket.assigns[:pending_respawn_timer] do
        Process.cancel_timer(timer)
      end

      {:noreply, respawn(socket, current)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:auto_respawn, character_id}, socket) do
    current = current_character(socket)

    if socket.assigns.world_mode? && current && current.character_id == character_id do
      {:noreply, respawn(socket, current)}
    else
      {:noreply, assign(socket, pending_respawn_timer: nil, pending_spawn_coords: nil, is_dead?: false)}
    end
  end

  # One regeneration timer per LiveView: a tick from an older chain (an earlier login) is dropped.
  def handle_info({:regen_tick, character_id, token}, socket) do
    if token == socket.assigns[:regen_token], do: regen(socket, character_id), else: {:noreply, socket}
  end

  def handle_info(%{event: "presence_diff"}, socket) do
    case socket.assigns.current_zone_topic do
      nil ->
        {:noreply, socket}

      topic ->
        zone_online_characters =
          topic
          |> list_zone_online_characters()
          |> visible_zone_online_characters(current_character(socket))

        {:noreply,
         socket
         |> assign(zone_online_characters: zone_online_characters)
         |> push_event("zone_presence_state", %{online_characters: zone_online_characters})}
    end
  end

  def handle_info({:zone_chat_message, payload}, socket) do
    if within_chat_radius?(socket, payload) do
      {:noreply, push_event(socket, "zone_chat_message", payload)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:zone_position_update, payload}, socket) do
    current = current_character(socket)

    cond do
      is_nil(current) ->
        {:noreply, socket}

      payload.character_id == current.character_id ->
        {:noreply, socket}

      true ->
        {:noreply, push_event(socket, "zone_position_update", payload)}
    end
  end

  def handle_info({:mob_events, events}, socket), do: {:noreply, GameEvents.mob_events(events, socket)}
  def handle_info({:mob_motion, list}, socket), do: {:noreply, GameEvents.mob_motion(list, socket)}
  def handle_info({:zone_gear, payload}, socket), do: {:noreply, GameEvents.zone_gear(payload, socket)}
  def handle_info({:zone_swing, payload}, socket), do: {:noreply, GameEvents.zone_swing(payload, socket)}
  def handle_info({:pvp_hit, hit}, socket), do: {:noreply, GameEvents.pvp_hit(hit, socket)}
  def handle_info({:zone_hp, payload}, socket), do: {:noreply, GameEvents.zone_hp(payload, socket)}

  def handle_info(:characters_updated, socket) do
    characters = World.list_user_characters(socket.assigns.current_user.id)

    selected_character_id =
      if Enum.any?(characters, &(&1.id == socket.assigns.selected_character_id)) do
        socket.assigns.selected_character_id
      else
        nil
      end

    {:noreply,
     assign(socket,
       characters: characters,
       selected_character_id: selected_character_id,
       has_characters?: characters != [],
       scene_characters: to_scene_characters(characters)
     )}
  end

  @impl true
  def terminate(_reason, socket) do
    _socket = socket |> leave_zone_presence() |> untrack_account_presence()
    :ok
  end

  # Account-wide presence: only one character may be logged in per account at a time,
  # regardless of which browser/session/zone it's in.
  defp account_topic(user_id), do: "bacon_world:account:#{user_id}"

  # Other tabs of the same account refresh their character list on changes.
  defp characters_topic(user_id), do: "bacon_world:user:#{user_id}:characters"

  defp account_online_elsewhere?(socket) do
    user_id = socket.assigns.current_user.id
    own_ref = socket.assigns[:account_presence_ref]

    account_topic(user_id)
    |> Presence.list()
    |> Map.get(user_id, %{metas: []})
    |> Map.get(:metas, [])
    |> Enum.any?(fn meta -> meta[:phx_ref] != own_ref end)
  end

  defp active_account_character_id(user_id) do
    case account_topic(user_id) |> Presence.list() |> Map.get(user_id) do
      %{metas: [meta | _]} -> meta[:character_id]
      _ -> nil
    end
  end

  defp track_account_presence(socket, character_id) do
    user_id = socket.assigns.current_user.id

    if connected?(socket) and !socket.assigns[:account_presence_tracked?] do
      case Presence.track(self(), account_topic(user_id), user_id, %{
             character_id: character_id,
             joined_at: System.system_time(:millisecond)
           }) do
        {:ok, ref} -> assign(socket, account_presence_tracked?: true, account_presence_ref: ref)
        _ -> assign(socket, account_presence_tracked?: true)
      end
    else
      socket
    end
  end

  defp untrack_account_presence(socket) do
    if socket.assigns[:account_presence_tracked?] do
      Presence.untrack(self(), account_topic(socket.assigns.current_user.id), socket.assigns.current_user.id)
    end

    assign(socket, account_presence_tracked?: false, account_presence_ref: nil)
  end

  defp join_zone_presence(socket, payload) do
    zone_id = payload.zone.id
    topic = "bacon_world:zone:#{zone_id}"

    presence_key = payload.character_id

    if connected?(socket) do
      if socket.assigns.current_zone_topic do
        previous_topic = socket.assigns.current_zone_topic
        PubSub.unsubscribe(Bacon8.PubSub, previous_topic)
        if socket.assigns.current_presence_key do
          Presence.untrack(self(), previous_topic, socket.assigns.current_presence_key)
        end

        # Cleanup legacy presence keys from earlier versions that tracked by user_id.
        Presence.untrack(self(), previous_topic, socket.assigns.current_user.id)
      end

      PubSub.subscribe(Bacon8.PubSub, topic)

      Presence.track(self(), topic, presence_key, %{
        user_id: socket.assigns.current_user.id,
        character_id: payload.character_id,
        character_name: payload.name,
        character_type: payload.character_type,
        model_path: payload.model_path,
        x: payload.position.x,
        y: payload.position.y,
        z: payload.position.z,
        heading: payload.position.heading,
        updated_at: System.system_time(:millisecond),
        joined_at: DateTime.utc_now() |> DateTime.to_iso8601()
      } |> Map.merge(GameEvents.presence_meta(payload)))

      Logger.info("bacon_world:join_zone_presence user_id=#{socket.assigns.current_user.id} character_id=#{payload.character_id} topic=#{topic}")

    end

    socket = assign(socket, current_presence_key: presence_key)

    zone_online_characters =
      topic
      |> list_zone_online_characters()
      |> visible_zone_online_characters(payload)

    socket
    |> assign(current_zone_topic: topic, zone_online_characters: zone_online_characters)
    |> GameEvents.join(payload)

  end

  defp leave_zone_presence(socket) do
    socket = GameEvents.leave(socket)

    case socket.assigns.current_zone_topic do
      nil ->
        socket

      topic ->
        if socket.assigns.current_presence_key do
          Presence.untrack(self(), topic, socket.assigns.current_presence_key)
        end

        PubSub.unsubscribe(Bacon8.PubSub, topic)
        socket
    end
  end

  defp leave_world(socket) do
    socket
    |> leave_zone_presence()
    |> untrack_account_presence()
    |> assign(
      world_mode?: false,
      current_character_payload: nil,
      current_character_runtime: nil,
      current_zone_topic: nil,
      current_presence_key: nil,
      zone_online_characters: [],
      last_world_update_ms: nil,
      last_presence_update_ms: nil,
      last_remote_broadcast_ms: nil,
      last_position_persist_ms: nil
    )
  end

  defp list_zone_online_characters(topic) do
    topic
    |> Presence.list()
    |> Enum.flat_map(fn {_key, %{metas: metas}} -> metas end)
    |> Enum.reject(&is_nil(&1[:character_id]))
    |> Enum.reduce(%{}, fn meta, acc ->
      character_id = meta[:character_id]

      case Map.get(acc, character_id) do
        nil ->
          Map.put(acc, character_id, meta)

        existing_meta ->
          if presence_meta_updated_at(meta) >= presence_meta_updated_at(existing_meta) do
            Map.put(acc, character_id, meta)
          else
            acc
          end
      end
    end)
    |> Map.values()
    |> Enum.map(fn meta ->
      %{
        character_id: meta[:character_id],
        character_name: meta[:character_name],
        character_type: meta[:character_type],
        model_path: meta[:model_path],
        user_id: meta[:user_id],
        x: meta[:x] || 0.0,
        y: meta[:y] || 0.0,
        z: meta[:z] || 0.0,
        heading: meta[:heading] || 0.0,
        level: meta[:level] || 1,
        hp: meta[:hp],
        max_hp: meta[:max_hp],
        gear: meta[:gear] || %{},
        dead: meta[:dead] == true
      }
    end)
  end

  defp presence_meta_updated_at(meta), do: meta[:updated_at] || 0

  defp visible_zone_online_characters(characters, nil), do: characters

  defp visible_zone_online_characters(characters, current_character_payload) do
    cx = current_character_payload.position.x || 0.0
    cz = current_character_payload.position.z || 0.0

    Enum.filter(characters, fn character ->
      dx = (character.x || 0.0) - cx
      dz = (character.z || 0.0) - cz
      :math.sqrt(dx * dx + dz * dz) <= @interest_radius
    end)
  end

  defp validate_ground_bounds(y) do
    if y < -1.0 or y > 25.0, do: {:error, :invalid_move}, else: :ok
  end

  defp validate_move_speed(socket, current_position, x, y, z) do
    last_ms = socket.assigns.last_world_update_ms || System.monotonic_time(:millisecond)
    now_ms = System.monotonic_time(:millisecond)
    dt = max((now_ms - last_ms) / 1000.0, @min_dt_seconds)

    dx = x - (current_position.x || 0.0)
    dy = y - (current_position.y || 0.0)
    dz = z - (current_position.z || 0.0)

    speed = :math.sqrt(dx * dx + dy * dy + dz * dz) / dt

    if speed > @max_move_speed, do: {:error, :invalid_move}, else: :ok
  end

  # Back to life at the zone's spawn point (moved clear of other players). The zone's
  # presence gets the new position at once: the creatures read it, and until the client
  # moved they kept attacking the spot where you died (2026-10-23).
  defp respawn(socket, current) do
    spawn = socket.assigns[:pending_spawn_coords] || %{x: 0.0, y: 0.0, z: 0.0, heading: 0.0}
    spawn = free_spawn(spawn, socket.assigns[:zone_online_characters] || [], current.character_id)
    pos = %{x: spawn.x, y: spawn.y, z: spawn.z, heading: spawn.heading}

    persist_character_position_async(socket.assigns.current_user.id, current, spawn.x, spawn.y, spawn.z, spawn.heading)

    if topic = socket.assigns[:current_zone_topic] do
      Presence.update(self(), topic, current.character_id, fn meta ->
        Map.merge(meta, %{x: spawn.x, y: spawn.y, z: spawn.z, heading: spawn.heading, updated_at: System.system_time(:millisecond)})
      end)

      # and the others see you there now, not when you first move
      PubSub.broadcast(Bacon8.PubSub, topic, {:zone_position_update, %{
        character_id: current.character_id,
        character_name: current.name,
        character_type: current.character_type,
        model_path: current.model_path,
        user_id: socket.assigns.current_user.id,
        x: spawn.x,
        y: spawn.y,
        z: spawn.z,
        heading: spawn.heading,
        m: 0,
        hp: current.max_hp,
        max_hp: current.max_hp
      }})
    end

    socket
    |> assign(
      pending_respawn_timer: nil,
      pending_spawn_coords: nil,
      is_dead?: false,
      current_character_runtime: Map.put(current, :position, pos),
      last_world_update_ms: System.monotonic_time(:millisecond)
    )
    |> GameEvents.set_dead(false)
    |> GameEvents.broadcast_hp(current.character_id, current.max_hp, current.max_hp, "alive")
    |> push_event("character_respawned", %{
      spawn_coords: pos,
      hp: current.max_hp,
      max_hp: current.max_hp,
      mp: current.max_mp,
      max_mp: current.max_mp
    })
  end

  # A move into another (living) player is refused, but a move that takes you farther from
  # one you already overlap is fine: otherwise two players on the same spot (a respawn, a
  # login) could never separate (2026-10-23: stuck on another player after respawning).
  defp validate_player_collision(online_characters, character_id, from, x, z) do
    fx = (from && from[:x]) || x
    fz = (from && from[:z]) || z

    blocked? =
      online_characters
      |> Enum.reject(&(&1.character_id == character_id or &1[:dead] == true))
      |> Enum.any?(fn other ->
        ox = other.x || 0.0
        oz = other.z || 0.0
        new_d = :math.sqrt((ox - x) * (ox - x) + (oz - z) * (oz - z))
        old_d = :math.sqrt((ox - fx) * (ox - fx) + (oz - fz) * (oz - fz))
        new_d < @collision_radius and new_d < old_d - 1.0e-6
      end)

    if blocked?, do: {:error, :invalid_move}, else: :ok
  end

  @doc false
  # The spawn point, or the nearest spot around it clear of other living players.
  def free_spawn(spawn, online_characters, character_id) do
    others = Enum.reject(online_characters, &(&1.character_id == character_id or &1[:dead] == true))
    clear? = fn x, z -> Enum.all?(others, fn o -> :math.pow((o.x || 0.0) - x, 2) + :math.pow((o.z || 0.0) - z, 2) >= :math.pow(@collision_radius * 1.2, 2) end) end

    candidates =
      [{0.0, 0.0}] ++
        for ring <- 1..4, i <- 0..7 do
          a = (i + ring * 0.5) * :math.pi() / 4
          r = ring * @collision_radius * 1.5
          {r * :math.sin(a), r * :math.cos(a)}
        end

    case Enum.find(candidates, fn {dx, dz} -> clear?.(spawn.x + dx, spawn.z + dz) end) do
      {dx, dz} -> %{spawn | x: spawn.x + dx, z: spawn.z + dz}
      nil -> spawn
    end
  end

  defp push_authoritative_correction(socket) do
    current = current_character(socket)

    if current do
      push_event(socket, "world_position_corrected", %{
        x: current.position.x,
        y: current.position.y,
        z: current.position.z,
        heading: current.position.heading
      })
    else
      socket
    end
  end

  defp persist_character_position_async(user_id, current_character, x, y, z, heading) do
    Task.start(fn ->
      position = %{x: x, y: y, z: z, heading: heading}

      case World.save_position(user_id, current_character.character_id, current_character.zone.slug, position) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning(
            "bacon_world:position_persist_failed user_id=#{user_id} character_id=#{current_character.character_id} reason=#{inspect(reason)}"
          )
      end
    end)

    :ok
  end

  defp within_chat_radius?(socket, payload) do
    case current_character(socket) do
      nil ->
        false

      current ->
        dx = (payload[:x] || payload["x"] || 0.0) - (current.position.x || 0.0)
        dz = (payload[:z] || payload["z"] || 0.0) - (current.position.z || 0.0)
        :math.sqrt(dx * dx + dz * dz) <= @chat_radius
    end
  end

  defp current_character(socket) do
    socket.assigns.current_character_runtime || socket.assigns.current_character_payload
  end

  defp regen(socket, character_id) do
    current = current_character(socket)

    # Only regen if still logged in as this character, and alive
    if socket.assigns.world_mode? && current && current.character_id == character_id && !socket.assigns[:is_dead?] do
      case Combat.get_character_stats(character_id) do
        {:ok, %{hp: hp, max_hp: max_hp, mp: mp, max_mp: max_mp}}
            when hp < max_hp or mp < max_mp ->
          # About a twelfth of the pool every 4 s (EverQuest-slow, but not 10 HP slow).
          new_hp = min(hp + max(1, div(max_hp, 12)), max_hp)
          new_mp = min(mp + max(1, div(max_mp, 12)), max_mp)
          {:ok, _} = Combat.update_character_hp_mp(character_id, new_hp, new_mp)
          socket =
            socket
            |> push_event("character_stats_update", %{hp: new_hp, max_hp: max_hp, mp: new_mp, max_mp: max_mp})
            |> then(fn s -> if new_hp != hp, do: GameEvents.broadcast_hp(s, character_id, new_hp, max_hp, "hurt"), else: s end)
          {:noreply, schedule_regen(socket, character_id)}

        _ ->
          # Already full — skip DB write, still reschedule
          {:noreply, schedule_regen(socket, character_id)}
      end
    else
      # Left the world: stop. Dead: keep the chain going (respawn heals anyway).
      if socket.assigns.world_mode? && current && current.character_id == character_id,
        do: {:noreply, schedule_regen(socket, character_id)},
        else: {:noreply, socket}
    end
  end

  # (Re)starts the 4 s regeneration tick; a new token orphans any older chain.
  defp schedule_regen(socket, character_id) do
    token = make_ref()
    Process.send_after(self(), {:regen_tick, character_id, token}, 4_000)
    assign(socket, regen_token: token)
  end

  # What the body is doing, for everyone else's animation: bit 1 crouching, bit 2 airborne.
  defp motion_flags(params) do
    case params["m"] || params[:m] do
      m when is_integer(m) and m >= 0 and m <= 3 -> m
      _ -> 0
    end
  end

  defp to_float(value) when is_float(value), do: {:ok, value}
  defp to_float(value) when is_integer(value), do: {:ok, value * 1.0}

  defp to_float(value) when is_binary(value) do
    case Float.parse(value) do
      {parsed, _rest} -> {:ok, parsed}
      :error -> {:error, :invalid_move}
    end
  end

  defp to_float(_value), do: {:error, :invalid_move}

  defp to_scene_characters(characters) do
    gear = World.gear_for(characters)

    Enum.map(characters, fn character ->
      %{
        id: character.id,
        name: character.name,
        character_type: character.character_type,
        model_path: character.model_path,
        appearance: character.appearance,
        level: character.level,
        gear: gear[character.id] || %{}
      }
    end)
  end

  defp create_error_reason(%Ecto.Changeset{errors: errors}), do: {:changeset, Keyword.keys(errors)}
  defp create_error_reason(reason), do: reason

  defp create_error_message(:character_limit_reached), do: "You already have the maximum of 16 characters."
  defp create_error_message(:invalid_model_path), do: "That body type isn't available right now."
  defp create_error_message(:invalid_appearance), do: "That look couldn't be saved. Try another."
  defp create_error_message(:default_zone_missing), do: "The world isn't set up yet (the lobby zone is missing)."

  defp create_error_message(%Ecto.Changeset{} = changeset) do
    case changeset.errors[:name] do
      {"has already been taken", _} -> "That name is taken. Try another."
      {_msg, opts} -> if opts[:validation] == :length, do: "Names need 2 to 24 characters.", else: "That name can't be used."
      nil -> "Please check the name and title."
    end
  end

  defp create_error_message(_), do: "Something went wrong. Try again."

  defp scene_state(assigns) do
    cond do
      assigns.world_mode? and assigns.current_character_payload != nil -> "world"
      !assigns.has_characters? -> "intro"
      is_nil(assigns.selected_character_id) -> "selection"
      true -> "ready"
    end
  end

  defp stringify_keys(params) do
    Map.new(params, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      pair -> pair
    end)
  end

  defp normalize_three_ui_create_params(params, available_model_paths) do
    name =
      params
      |> Map.get("name", Map.get(params, :name, ""))
      |> to_string()
      |> String.trim()

    character_type =
      params
      |> Map.get("character_type", Map.get(params, :character_type, ""))
      |> to_string()
      |> String.trim()

    model_path =
      params
      |> Map.get("model_path", Map.get(params, :model_path, ""))
      |> to_string()
      |> String.trim()

    fallback_name = "Traveler#{System.unique_integer([:positive]) |> Integer.to_string() |> String.slice(-6, 6)}"
    fallback_type = "AA"
    fallback_model = List.first(available_model_paths) || ""

    base = %{
      "name" => if(String.length(name) >= 2, do: name, else: fallback_name),
      "character_type" => if(String.length(character_type) >= 2, do: character_type, else: fallback_type),
      "model_path" => if(model_path != "", do: model_path, else: fallback_model)
    }

    case Map.get(params, "appearance") do
      look when is_map(look) -> Map.put(base, "appearance", look)
      _ -> base
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="fixed top-[30px] inset-x-0 bottom-0 z-40 overflow-hidden">
        <%= unless @world_mode? do %>
          <button
            type="button"
            phx-click="back_to_games"
            class="absolute top-3 left-3 z-50 glass-dark text-white text-sm px-3 py-1.5 rounded-md border border-gray-700 hover:border-blue-400 transition-colors duration-300"
          >
            ← Games
          </button>
        <% end %>
        <div
          id="world-character-scene"
          class="absolute inset-0 w-full h-full"
          phx-hook="WorldCharacterUIScene"
          data-ui-state={scene_state(assigns)}
          data-selected-character-id={@selected_character_id}
          data-can-login={to_string(!is_nil(@selected_character_id))}
          data-characters={Jason.encode!(@scene_characters)}
          data-model-paths={Jason.encode!(@scene_model_paths)}
          data-available-models={Jason.encode!(@available_models)}
          data-current-player={Jason.encode!(@current_character_payload)}
          data-human-assets={Jason.encode!(@human_assets)}
          data-item-catalog={Jason.encode!(@item_catalog)}
          phx-update="ignore"
        ></div>

    </div>
    """
  end
end

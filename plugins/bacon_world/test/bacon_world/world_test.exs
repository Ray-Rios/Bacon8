defmodule BaconWorld.WorldTest do
  # Not async: the models folder is application config, shared by all tests.
  use Bacon8.DataCase, async: false

  alias Bacon8.Games
  alias BaconWorld.{Combat, Items, Models, World}
  alias BaconWorld.Mobs.Brain
  alias BaconWorldWeb.GameEvents

  setup do
    # A tiny models folder, so tests never walk a real (possibly huge) one.
    dir = Path.join(System.tmp_dir!(), "bacon_world_models_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "heroes"))
    File.write!(Path.join(dir, "heroes/runner.glb"), "glTF")
    File.write!(Path.join(dir, "notes.txt"), "not a model")

    Application.put_env(:bacon8, Models, roots: [dir])

    on_exit(fn ->
      Application.delete_env(:bacon8, Models)
      File.rm_rf!(dir)
    end)

    %{model: "/models/heroes/runner.glb", user_id: Ecto.UUID.generate()}
  end

  defp create!(user_id, model, name) do
    {:ok, c} = World.create_character(user_id, %{"name" => name, "character_type" => "Explorer", "model_path" => model})
    c
  end

  test "characters are platform GameCharacters for the bacon_world game", %{user_id: user_id, model: model} do
    c = create!(user_id, model, "Wesley")

    assert {:ok, game} = Bacon8.Plugins.ensure_game("bacon_world")
    assert game.slug == "bacon_world"
    assert [%{id: id}] = Enum.filter(Games.list_characters(game.id, user_id), &(&1.name == "Wesley"))
    assert id == c.id

    assert %{hp: 40, max_hp: 40, mp: 20, max_mp: 20, level: 1, pvp_flagged: false, character_type: "Explorer", zone_slug: "lobby"} = c
    assert [%{name: "Wesley"}] = World.list_user_characters(user_id)
    # Throw Stone (the old web-lobby test) is retired: no starter spells.
    assert [] = Combat.list_character_spells(c.id)
  end

  test "the model list and model validation use the models folder", %{model: model} do
    assert Models.list() == [%{label: "heroes/runner.glb", model_path: model}]
    assert {:ok, ^model} = Models.validate(model)

    for bad <- ["/models/notes.txt", "/models/heroes/missing.glb", "/models/../heroes/runner.glb", "/etc/passwd", nil] do
      assert {:error, :invalid_model_path} = Models.validate(bad)
    end
  end

  test "creation is validated", %{user_id: user_id, model: model} do
    assert {:error, :invalid_model_path} =
             World.create_character(user_id, %{"name" => "Bob", "character_type" => "Explorer", "model_path" => "/etc/passwd"})

    assert {:error, %Ecto.Changeset{} = cs} =
             World.create_character(user_id, %{"name" => "B", "character_type" => "Explorer", "model_path" => model})

    assert %{name: [_]} = errors_on(cs)

    # Names are unique per game, across accounts.
    create!(user_id, model, "Taken")

    assert {:error, %Ecto.Changeset{}} =
             World.create_character(Ecto.UUID.generate(), %{"name" => "Taken", "character_type" => "Explorer", "model_path" => model})
  end

  test "at most 16 characters per user", %{user_id: user_id, model: model} do
    for n <- 1..World.max_characters_per_user(), do: create!(user_id, model, "Char #{n}")

    assert {:error, :character_limit_reached} =
             World.create_character(user_id, %{"name" => "One more", "character_type" => "Explorer", "model_path" => model})
  end

  test "other users can't see, move, flag or delete your characters", %{user_id: user_id, model: model} do
    c = create!(user_id, model, "Mine")
    other = Ecto.UUID.generate()

    assert World.get_character_for_user(other, c.id) == nil
    assert {:error, :not_found} = World.character_login_payload(other, c.id)
    assert {:error, :not_found} = World.save_position(other, c.id, "lobby", %{x: 1.0, y: 0.0, z: 1.0, heading: 0.0})
    assert {:error, :not_found} = World.toggle_pvp(other, c.id)
    assert {:error, :not_found} = World.delete_character_for_user(other, c.id)
    assert {:error, :not_found} = World.delete_character_for_user(user_id, "not-a-uuid")
  end

  test "login payload, position saves and the PvP flag", %{user_id: user_id, model: model} do
    c = create!(user_id, model, "Walker")

    assert {:ok, payload} = World.character_login_payload(user_id, c.id)
    assert %{name: "Walker", zone: %{slug: "lobby"}, spells: []} = payload

    assert {:ok, %{"hp" => 5}} = Combat.update_character_hp_mp(c.id, 5, 10)
    assert :ok = World.save_position(user_id, c.id, "lobby", %{x: 3.0, y: 0.5, z: -2.0, heading: 1.5})
    assert {:ok, true} = World.toggle_pvp(user_id, c.id)

    # Each write touched only its own keys.
    assert %{hp: 5, pvp_flagged: true, position: %{x: 3.0, y: 0.5, z: -2.0, heading: 1.5}} =
             World.get_character_for_user(user_id, c.id)

    assert {:ok, %{x: _, heading: _}} = Combat.respawn_character(c.id)
    assert %{hp: 40, position: %{x: x, z: z}} = World.get_character_for_user(user_id, c.id)
    assert x == 0.0 and z == 0.0
  end

  # A LiveView socket in a zone, standing at (x, z) metres, with the players it sees.
  defp zone_socket(c, {x, z}, others, topic) do
    u = Brain.u()

    %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        mobs_zone: "lobby",
        current_zone_topic: topic,
        zone_online_characters: others,
        current_character_runtime: %{character_id: c.id, name: c.name, position: %{x: x * u, y: 0.0, z: z * u}, hp: 40, max_hp: 40, mp: 20, max_mp: 20}
      }
    }
  end

  defp seen(c, {x, z}), do: %{character_id: c.id, character_name: c.name, x: x * Brain.u(), z: z * Brain.u(), level: 1, dead: false}

  defp swing(socket, me, {x, z}, heading) do
    u = Brain.u()
    GameEvents.pvp_swing(socket, me, %{id: me.character_id, level: 1, x: x * u, z: z * u, heading: heading, item: Items.fist(), heavy: false, target: nil})
  end

  test "PvP melee needs both players flagged and the target in front and in reach", %{user_id: user_id, model: model} do
    attacker = create!(user_id, model, "Brawler")
    target = create!(Ecto.UUID.generate(), model, "Target")
    topic = "bacon_world:test:#{System.unique_integer([:positive])}"
    Phoenix.PubSub.subscribe(Bacon8.PubSub, topic)

    me = %{character_id: attacker.id, name: attacker.name}
    close = zone_socket(attacker, {0.0, 0.0}, [seen(target, {0.0, 1.0})], topic)

    # Neither flagged, then only the attacker: nothing.
    assert [] = swing(close, me, {0.0, 0.0}, 0.0)
    {:ok, true} = World.toggle_pvp(user_id, attacker.id)
    assert [] = swing(close, me, {0.0, 0.0}, 0.0)

    {:ok, true} = World.toggle_pvp(target.user_id, target.id)
    # Behind the swing, or out of reach: nothing.
    assert [] = swing(close, me, {0.0, 0.0}, :math.pi())
    assert [] = swing(zone_socket(attacker, {0.0, 0.0}, [seen(target, {0.0, 6.0})], topic), me, {0.0, 0.0}, 0.0)

    # In front: a hit or a miss, broadcast to the zone.
    assert [%{attacker_id: aid, target_id: tid, hit: hit, damage: dmg}] = swing(close, me, {0.0, 0.0}, 0.0)
    assert aid == attacker.id and tid == target.id
    assert if(hit, do: dmg > 0, else: dmg == 0)
    assert_receive {:pvp_hit, %{target_id: ^tid}}

    # The target's LiveView applies it, and tells the zone the new health.
    victim = zone_socket(target, {0.0, 1.0}, [], topic)
    GameEvents.pvp_hit(%{attacker_id: aid, attacker_name: "Brawler", target_id: tid, target_name: "Target", hit: true, damage: 7, crit: false}, victim)
    assert %{hp: 33} = World.get_character_for_user(target.user_id, target.id)
    assert_receive {:zone_hp, %{character_id: ^tid, hp: 33, state: "hurt"}}

    # Someone else's LiveView only passes it on.
    bystander = zone_socket(attacker, {0.0, 0.0}, [], topic)
    GameEvents.pvp_hit(%{attacker_id: aid, attacker_name: "Brawler", target_id: tid, target_name: "Target", hit: true, damage: 7, crit: false}, bystander)
    assert %{hp: 33} = World.get_character_for_user(target.user_id, target.id)
  end

  test "a character whose model was removed wears the first model still offered", %{user_id: user_id, model: model} do
    c = create!(user_id, model, "Remodelled")
    {:ok, _} = Games.update_character(Games.get_character!(c.id), %{settings: %{"model_path" => "/models/gone/away.glb"}})

    assert %{model_path: ^model} = World.get_character_for_user(user_id, c.id)
  end

  test "a respawn lands clear of other living players" do
    spawn = %{x: 0.0, y: 0.0, z: 0.0, heading: 0.0}
    assert BaconWorldWeb.PlayLive.free_spawn(spawn, [], "me") == spawn
    blocker = %{character_id: "other", x: 0.1, z: 0.0, dead: false}
    moved = BaconWorldWeb.PlayLive.free_spawn(spawn, [blocker], "me")
    assert :math.sqrt(:math.pow(moved.x - 0.1, 2) + :math.pow(moved.z, 2)) > 1.1
    # a corpse doesn't block, nor do you yourself
    assert BaconWorldWeb.PlayLive.free_spawn(spawn, [%{blocker | dead: true}, %{blocker | character_id: "me"}], "me") == spawn
  end
end

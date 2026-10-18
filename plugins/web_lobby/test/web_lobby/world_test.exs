defmodule WebLobby.WorldTest do
  # Not async: the models folder is application config, shared by all tests.
  use Bacon8.DataCase, async: false

  alias Bacon8.Games
  alias WebLobby.{Combat, Models, World}

  setup do
    # A tiny models folder, so tests never walk a real (possibly huge) one.
    dir = Path.join(System.tmp_dir!(), "web_lobby_models_#{System.unique_integer([:positive])}")
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

  test "characters are platform GameCharacters for the web_lobby game", %{user_id: user_id, model: model} do
    c = create!(user_id, model, "Wesley")

    assert {:ok, game} = Bacon8.Plugins.ensure_game("web_lobby")
    assert game.slug == "web_lobby"
    assert [%{id: id}] = Enum.filter(Games.list_characters(game.id, user_id), &(&1.name == "Wesley"))
    assert id == c.id

    assert %{hp: 10, max_hp: 10, mp: 10, max_mp: 10, pvp_flagged: false, character_type: "Explorer", zone_slug: "lobby"} = c
    assert [%{name: "Wesley"}] = World.list_user_characters(user_id)
    assert [%{slug: "throw_stone"}] = Combat.list_character_spells(c.id)
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
    assert %{name: "Walker", zone: %{slug: "lobby"}, spells: [%{slug: "throw_stone", mp_cost: 1}]} = payload

    assert {:ok, %{"hp" => 5}} = Combat.update_character_hp_mp(c.id, 5, 10)
    assert :ok = World.save_position(user_id, c.id, "lobby", %{x: 3.0, y: 0.5, z: -2.0, heading: 1.5})
    assert {:ok, true} = World.toggle_pvp(user_id, c.id)

    # Each write touched only its own keys.
    assert %{hp: 5, pvp_flagged: true, position: %{x: 3.0, y: 0.5, z: -2.0, heading: 1.5}} =
             World.get_character_for_user(user_id, c.id)

    assert {:ok, %{x: _, heading: _}} = Combat.respawn_character(c.id)
    assert %{hp: 10, position: %{x: x, z: z}} = World.get_character_for_user(user_id, c.id)
    assert x == 0.0 and z == 0.0
  end

  test "throw stone needs both players flagged and in range", %{user_id: user_id, model: model} do
    caster = create!(user_id, model, "Caster")
    target = create!(Ecto.UUID.generate(), model, "Target")
    near = %{x: 0.0, z: 0.0}
    close = %{x: 5.0, z: 0.0}

    assert {:error, :pvp_not_flagged} = Combat.cast_throw_stone(caster.id, target.id, near, close)

    {:ok, true} = World.toggle_pvp(user_id, caster.id)
    {:ok, true} = World.toggle_pvp(target.user_id, target.id)

    assert {:error, :out_of_range} = Combat.cast_throw_stone(caster.id, target.id, near, %{x: 500.0, z: 0.0})
    assert {:error, :character_not_found} = Combat.cast_throw_stone(caster.id, "not-a-uuid", near, close)

    assert {:ok, %{caster_mp: 9, target_hp: hp, hit: hit}} = Combat.cast_throw_stone(caster.id, target.id, near, close)
    assert hp == if(hit, do: 9, else: 10)
    assert %{mp: 9} = World.get_character_for_user(user_id, caster.id)
  end

  test "characters of other games can't be targeted", %{user_id: user_id, model: model} do
    caster = create!(user_id, model, "Lobbyist")
    {:ok, true} = World.toggle_pvp(user_id, caster.id)

    {:ok, other_game} = Games.create_game(%{slug: "other-game", name: "Other"})

    {:ok, outsider} =
      Games.create_character(%{user_id: Ecto.UUID.generate(), game_id: other_game.id, name: "Outsider", stats: %{"pvp_flagged" => true}})

    assert {:error, :character_not_found} = Combat.cast_throw_stone(caster.id, outsider.id, %{x: 0.0, z: 0.0}, %{x: 1.0, z: 0.0})
  end
end

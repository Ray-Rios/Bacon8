defmodule Bacon8.BuildingTest do
  # Build mode on the hub for every game (2026-11-14): the shared catalogue, who may place what,
  # placing, moving, deleting and smashing by game and zone, the zone's revision, and Bacon World's
  # rows kept apart through its views of the same tables.
  use Bacon8.DataCase, async: false

  import Ecto.Query
  alias Bacon8.{Building, GamesRepo}
  alias Bacon8.Building.Placement

  setup do
    Building.reset()
    :ok
  end

  defp user(role, extra \\ %{}), do: Map.merge(%{id: Ecto.UUID.generate(), role: role, is_admin: false}, extra)
  defp at(asset, x, z, extra \\ %{}), do: Map.merge(%{"asset" => asset, "x" => x, "y" => 0.0, "z" => z}, extra)

  test "the catalogue is Bacon World's props and building kit, the same for every game" do
    ids = MapSet.new(Building.catalogue("rays_space_sim"), & &1.id)
    assert MapSet.member?(ids, "P_Barrel") and MapSet.member?(ids, "K_Wall_Stone") and MapSet.member?(ids, "X_Plinth")
    assert Enum.count(Building.catalogue("tears_of_babylon")) == 255
    # its own explosive barrel (2026-11-25), only in its catalogue
    assert Building.asset("tears_of_babylon", "X_ExplosiveBarrel").model == "Barrel"
    assert Building.asset("rays_space_sim", "X_ExplosiveBarrel") == nil
    refute Enum.any?(Building.catalogue("rays_space_sim"), &String.starts_with?(&1.id, "mob:")), "creatures are Bacon World's own"
    assert Building.asset("rays_space_sim", "P_TreeOak").category == "Trees & plants"
  end

  test "who may place what: members place props, the waystone is admins', guests nothing; admins change it" do
    member = user("member")
    admin = user("member", %{is_admin: true})
    assert Building.can_place?("rays_space_sim", member, "P_Barrel")
    refute Building.can_place?("rays_space_sim", member, "P_Waystone")
    refute Building.can_place?("rays_space_sim", user("guest"), "P_Barrel")
    assert {:error, _} = Building.set_rule(member, "P_Barrel", "gm")
    assert {:ok, "gm"} = Building.set_rule(admin, "P_Barrel", "gm")
    refute Building.can_place?("tears_of_babylon", member, "P_Barrel"), "one rule for every game"
    assert {:ok, 40} = Building.set_hp(admin, "P_Crate", 40)
    assert Enum.find(Building.catalogue_for("rays_space_sim", member), &(&1.id == "P_Crate")).hp == 40
  end

  test "place, move, delete, by game and zone, in a frame, with the revision going up" do
    member = user("member")
    Phoenix.PubSub.subscribe(Bacon8.PubSub, Building.topic("rays_space_sim", "sol"))
    r0 = Building.revision("rays_space_sim", "sol")
    assert {:ok, v} = Building.place("rays_space_sim", "sol", member, at("K_Wall_Stone", 10.0, -4.0, %{"frame" => "earth", "rot" => 7.0, "scale" => 9, "data" => %{"q" => [0, 0, 0, 1], "junk" => 1}}))
    assert_receive {:build_placed, %{id: id}}
    assert v.frame == "earth" and v.scale == 2.0 and abs(v.rot - (7.0 - 2 * :math.pi())) < 1.0e-9
    assert v.data == %{"q" => [0.0, 0.0, 0.0, 1.0]}, "only a turn and a stretch are kept"
    assert v.hp == 10 and v.placed_by == member.id
    assert Building.revision("rays_space_sim", "sol") == r0 + 1
    assert [%{id: ^id}] = Building.list("rays_space_sim", "sol", frame: "earth")
    assert [] == Building.list("rays_space_sim", "sol", frame: "mars")
    assert [] == Building.list("tears_of_babylon", "sol"), "another game's zone of the same name is its own"

    assert {:ok, m} = Building.move("rays_space_sim", "sol", member, id, %{"x" => 12.0})
    assert m.x == 12.0 and m.z == -4.0 and m.frame == "earth" and m.data["q"] == [0.0, 0.0, 0.0, 1.0]
    assert {:error, _} = Building.place("rays_space_sim", "sol", member, at("P_Waystone", 0.0, 0.0))
    assert {:error, _} = Building.place("rays_space_sim", "sol", member, at("P_Nope", 0.0, 0.0))
    assert {:error, _} = Building.place("rays_space_sim", "sol", member, at("P_Barrel", "x", 0.0))
    assert {:error, _} = Building.delete("rays_space_sim", "sol", user("guest"), id)
    assert {:ok, _} = Building.delete("rays_space_sim", "sol", member, id, smash: true)
    assert_receive {:build_removed, ^id, "K_Wall_Stone", :smashed}
    assert [] == Building.list("rays_space_sim", "sol")
  end

  test "damage lowers the HP, and at 0 the piece is smashed" do
    member = user("member")
    {:ok, %{id: id}} = Building.place("tears_of_babylon", "valley", member, at("P_Barrel", 1.0, 1.0))
    Phoenix.PubSub.subscribe(Bacon8.PubSub, Building.topic("tears_of_babylon", "valley"))
    assert {:ok, :damaged, %{hp: 6}} = Building.damage("tears_of_babylon", "valley", member, id, 4)
    assert_receive {:build_damaged, ^id, "P_Barrel", 6, 10, 4}
    assert [%{hp: 6}] = Building.list("tears_of_babylon", "valley")
    assert {:error, _} = Building.damage("tears_of_babylon", "valley", user("guest"), id, 50)
    assert {:ok, :destroyed, _} = Building.damage("tears_of_babylon", "valley", member, id, 50)
    assert_receive {:build_removed, ^id, "P_Barrel", :smashed}
    assert Building.get("tears_of_babylon", "valley", id) == nil
  end

  test "Bacon World's rows are its own through its view, and land in the shared table" do
    member = user("member")
    {:ok, _} = Building.place("rays_space_sim", "lobby", member, at("P_Barrel", 1.0, 1.0))
    if Code.ensure_loaded?(BaconWorld.Placement) do
      bw = struct(BaconWorld.Placement, %{zone: "lobby", asset: "P_Crate", x: 0.0, y: 0.0, z: 0.0})
      {:ok, p} = GamesRepo.insert(bw)
      assert [%{asset: "P_Crate"}] = GamesRepo.all(from(q in BaconWorld.Placement, where: q.zone == "lobby"))
      assert GamesRepo.get(Placement, p.id).game_slug == "bacon_world"
    end

    assert GamesRepo.aggregate(from(q in Placement, where: q.game_slug == "rays_space_sim"), :count) == 1
  end
end

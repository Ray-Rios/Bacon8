defmodule BaconWorld.Mobs.CampLayout do
  @moduledoc """
  A managed camp's decor (2026-11-03): its `features` (campfire, tents, palisade, ...) laid out
  around it as ordinary build-mode placements (`BaconWorld.Building.place_system/3`, origin
  `"camp:c:<camp id>"`), so builders can move them like anything else and the client draws them
  with no new code. The same camp always gets the same layout (the camp id seeds the dice);
  "Generate decor" on the admin page replaces what is there.

  Pieces come from the build catalogue (`BaconWorld.Building.catalogue/0`); the palisade, the
  graves and the ruins follow the camp's `theme`.
  """

  alias BaconWorld.Building
  alias BaconWorld.Mobs.Camps

  @two_pi 2 * :math.pi()

  @doc "The origin tag of a camp's decor placements."
  def origin(camp_id), do: "camp:" <> Camps.key(camp_id)

  @doc """
  The camp's decor as placement attrs (metres and radians, string keys, ready for
  `BaconWorld.Building.place_system/3`): `[%{"asset", "x", "z", "rot", "scale"}]`. Pieces the
  catalogue doesn't have are left out.
  """
  def pieces(camp_id, camp) do
    s0 = :rand.seed_s(:exsss, seed(camp_id))
    r = Camps.radius(camp)
    rot = (camp[:rot] || 0.0) * 1.0
    theme = camp[:theme] || "none"
    feats = camp[:features] || []

    {pieces, _s} =
      Enum.reduce(feats, {[], s0}, fn f, {acc, s} ->
        {ps, s} = feature(f, r, theme, camp, s)
        {acc ++ ps, s}
      end)

    cx = (camp[:x] || 0.0) * 1.0
    cz = (camp[:z] || 0.0) * 1.0

    pieces
    |> Enum.map(fn {asset, lx, lz, lrot, scale} ->
      # turn the layout with the camp
      {x, z} = {lx * :math.cos(rot) - lz * :math.sin(rot), lx * :math.sin(rot) + lz * :math.cos(rot)}
      %{"asset" => asset, "x" => Float.round(cx + x, 2), "z" => Float.round(cz + z, 2), "rot" => wrap(lrot + rot), "scale" => Float.round(scale * 1.0, 2)}
    end)
    |> Enum.filter(&(Building.asset(&1["asset"]) != nil))
  end

  defp seed(id) do
    <<a::32, b::32, c::32, _::binary>> = :crypto.hash(:sha256, to_string(id))
    {a, b, c}
  end

  defp tents(camp, r) do
    case camp[:size] do
      "small" -> 1
      "medium" -> 2
      "large" -> 3
      "huge" -> 4
      _ -> r |> Kernel./(5) |> round() |> max(1) |> min(5)
    end
  end

  # each feature: {[{asset, x, z, rot, scale}], rand state}; the gate faces +x (east, before the camp's turn)
  defp feature("campfire", _r, _theme, _camp, s) do
    {[{"P_Campfire", 0.0, 0.0, 0.0, 1.0}, {"P_Log", 1.9, 0.4, 1.4, 1.0}, {"P_Log", -1.7, -0.9, 0.3, 1.0}, {"P_Stool", 0.4, 1.9, 0.0, 1.0}, {"P_Stool", -0.6, -1.9, 0.0, 1.0}], s}
  end

  defp feature("tents", r, _theme, camp, s) do
    n = tents(camp, r)
    {jit, s} = :rand.uniform_s(s)

    ps =
      for i <- 0..(n - 1)//1 do
        # around the back half, away from the gate
        a = :math.pi() * 0.45 + i * (:math.pi() * 1.1 / max(n, 1)) + jit * 0.2
        {"P_Tent", r * 0.72 * :math.cos(a), r * 0.72 * :math.sin(a), a + :math.pi(), 1.0}
      end

    {ps, s}
  end

  defp feature("palisade", r, theme, _camp, s) do
    asset =
      case theme do
        t when t in ["goblin", "orc", "bandit"] -> "K_Wall_Palisade_Vertical"
        "graveyard" -> "K_Fence_Stone"
        t when t in ["ruins", "barrow"] -> "K_Wall_Stone_Half"
        _ -> "K_Fence_Wood"
      end

    ring = r + 1.0
    n = max(6, round(@two_pi * ring / 3.0))
    step = @two_pi / n
    # leave the gate (two segments) at angle 0
    ps =
      for i <- 0..(n - 1)//1, a <- [i * step], abs(angle_diff(a, 0.0)) > step * 1.1 do
        {asset, ring * :math.cos(a), ring * :math.sin(a), a + :math.pi() / 2, 1.0}
      end

    {ps, s}
  end

  defp feature("banners", r, _theme, _camp, s) do
    g = r + 1.6
    {[{"P_Banner", g, 2.6, 0.0, 1.0}, {"P_Banner", g, -2.6, 0.0, 1.0}], s}
  end

  defp feature("supplies", r, _theme, _camp, s) do
    {a, s} = :rand.uniform_s(s)
    a = -:math.pi() / 2 + (a - 0.5) * 0.8
    {cx, cz} = {r * 0.55 * :math.cos(a), r * 0.55 * :math.sin(a)}
    set = [{"P_Crate", 0.0, 0.0}, {"P_CrateSmall", 1.1, 0.3}, {"P_BarrelSide", -1.0, 0.6}, {"P_Sack", 0.4, -1.0}, {"P_SackPile", -0.9, -0.8}, {"P_CrateStack", 1.3, -1.1}]
    {for({asset, dx, dz} <- set, do: {asset, cx + dx, cz + dz, a, 1.0}), s}
  end

  defp feature("braziers", r, _theme, _camp, s) do
    n = if r >= 12, do: 4, else: 3
    {for(i <- 0..(n - 1)//1, a <- [:math.pi() / n + i * @two_pi / n], do: {"P_Brazier", r * 0.92 * :math.cos(a), r * 0.92 * :math.sin(a), 0.0, 1.0}), s}
  end

  defp feature("graves", r, _theme, _camp, s), do: scatter("P_Tombstone", max(4, round(r * 0.6)), r * 0.3, r * 0.85, s, fn _a -> -:math.pi() / 2 end)
  defp feature("bones", r, _theme, _camp, s), do: scatter("P_Skull", max(4, round(r * 0.5)), r * 0.2, r * 0.95, s, &(&1 * 3.0))

  defp feature("weapon_rack", r, _theme, _camp, s) do
    a = :math.pi() * 0.25
    {x, z} = {r * 0.6 * :math.cos(a), r * 0.6 * :math.sin(a)}
    {[{"P_WeaponRack", x, z, a + :math.pi(), 1.0}, {"P_TrainingDummy", x + 1.8, z + 0.6, a + :math.pi(), 1.0}], s}
  end

  defp feature("forge", r, _theme, _camp, s) do
    a = -:math.pi() * 0.3
    {x, z} = {r * 0.6 * :math.cos(a), r * 0.6 * :math.sin(a)}
    {[{"P_Forge", x, z, a + :math.pi(), 1.0}, {"P_Anvil", x - 1.6, z + 0.4, a, 1.0}, {"P_Woodpile", x + 1.4, z - 1.2, a, 1.0}], s}
  end

  defp feature("cauldron", _r, _theme, _camp, s), do: {[{"P_Cauldron", -2.6, 1.2, 0.0, 1.0}], s}

  defp feature("treasure", r, _theme, _camp, s) do
    x = -r * 0.3
    {[{"P_Chest", x, 0.0, 0.0, 1.0}, {"P_CoinPile", x + 0.9, 0.8, 0.0, 1.0}, {"P_GemPile", x + 0.8, -0.9, 0.0, 1.0}], s}
  end

  defp feature("throne", r, _theme, _camp, s), do: {[{"P_Throne", -r * 0.4, 0.0, 0.0, 1.0}], s}

  defp feature("ruins", r, _theme, _camp, s) do
    {[
       {"K_Pillar_Stone", r * 0.8, r * 0.45, 0.0, 1.0},
       {"K_Pillar_Stone", -r * 0.75, r * 0.5, 0.0, 1.0},
       {"K_Pillar_Stone", -r * 0.2, -r * 0.85, 0.0, 1.0},
       {"K_Wall_Stone_Half", -r * 0.85, -r * 0.2, :math.pi() / 2, 1.0},
       {"K_Wall_Stone_Half", r * 0.35, -r * 0.8, 0.2, 1.0},
       {"K_Arch_Stone", -r * 0.55, r * 0.8, 0.6, 1.0}
     ], s}
  end

  defp feature("rocks", r, _theme, _camp, s) do
    {ps, s} = scatter("P_Boulder", 2, r + 1.5, r + 4.0, s, &(&1 * 2.0))
    {more, s} = scatter("P_Rock2", 3, r + 1.0, r + 3.5, s, &(&1 * 1.3))
    {ps ++ more, s}
  end

  defp feature("dead_trees", r, _theme, _camp, s), do: scatter("P_TreeDead", 3, r + 2.5, r + 6.0, s, &(&1 * 1.7))
  defp feature(_unknown, _r, _theme, _camp, s), do: {[], s}

  # `n` of an asset at random angles between two radii
  defp scatter(asset, n, r0, r1, s, turn) do
    Enum.reduce(1..n, {[], s}, fn _, {acc, s} ->
      {u, s} = :rand.uniform_s(s)
      {v, s} = :rand.uniform_s(s)
      {w, s} = :rand.uniform_s(s)
      a = u * @two_pi
      rr = r0 + (r1 - r0) * v
      {acc ++ [{asset, rr * :math.cos(a), rr * :math.sin(a), turn.(a), 0.85 + w * 0.4}], s}
    end)
  end

  defp angle_diff(a, b) do
    d = :math.fmod(a - b + :math.pi(), @two_pi)
    d = if d < 0, do: d + @two_pi, else: d
    d - :math.pi()
  end

  defp wrap(a) do
    a = :math.fmod(a, @two_pi)
    Float.round(if(a < 0, do: a + @two_pi, else: a), 4)
  end
end

defmodule BaconWorld.Mobs do
  @moduledoc """
  Creatures, combat against them and their loot. One zone process per zone holds
  them (`BaconWorld.Mobs.Zone`); this module is how a player's LiveView talks to
  it. Calls return an error instead of crashing when the zone isn't running (it is
  starting, or moving to another node).
  """

  alias BaconWorld.Mobs.{Keeper, Zone}

  @zones ["lobby"]

  @doc "The plugin's processes: a keeper per zone with creatures."
  def children, do: Enum.map(@zones, &{Keeper, &1})

  @doc "The PubSub topic a zone's creatures are broadcast on."
  def topic(slug), do: "bacon_world:mobs:#{slug}"

  @doc "Every creature (and corpse) in the zone, as `BaconWorld.Mobs.Brain.view/1` maps."
  def snapshot(slug), do: call(slug, :snapshot, [])

  @doc "A player's swing (see `BaconWorld.Mobs.Brain.melee/4`). `{:ok, hits}`."
  def melee(slug, attack), do: call(slug, {:melee, attack}, {:error, :mobs_unavailable})

  def loot_open(slug, mob_id, character_id, pos), do: call(slug, {:loot_open, mob_id, character_id, pos}, {:error, :mobs_unavailable})
  def loot_take(slug, mob_id, character_id, index), do: call(slug, {:loot_take, mob_id, character_id, index}, {:error, :mobs_unavailable})
  def loot_return(slug, mob_id, item), do: cast(slug, {:loot_return, mob_id, item})
  def loot_close(slug, mob_id, character_id), do: cast(slug, {:loot_close, mob_id, character_id})

  defp call(slug, msg, default) do
    GenServer.call(Zone.name(slug), msg, 3_000)
  catch
    :exit, _ -> default
  end

  defp cast(slug, msg), do: GenServer.cast(Zone.name(slug), msg)
end

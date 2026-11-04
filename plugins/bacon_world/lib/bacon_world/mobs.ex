defmodule BaconWorld.Mobs do
  @moduledoc """
  Creatures, combat against them and their loot. One zone process per zone holds
  them (`BaconWorld.Mobs.Zone`); this module is how a player's LiveView talks to
  it. Calls return an error instead of crashing when the zone isn't running (it is
  starting, or moving to another node).
  """

  alias BaconWorld.Mobs.{Keeper, Zone}

  @zones ["lobby"]

  @doc "The zones that have creatures (a zone process each)."
  def zone_slugs, do: @zones

  @doc """
  The plugin's processes: a keeper per zone with creatures, and a supervisor for the keepers of
  the zones beyond the lobby (started as players enter them, `ensure_zone/1`).
  """
  def children, do: [{DynamicSupervisor, name: __MODULE__.Extra, strategy: :one_for_one} | Enum.map(@zones, &{Keeper, &1})]

  @doc """
  Makes sure zone `slug`'s creatures run (zones beyond the lobby, 2026-11-02: their keeper starts
  on this node as the first player enters; the keeper keeps one zone process in the cluster).
  """
  def ensure_zone(slug) when slug in @zones, do: :ok

  def ensure_zone(slug) when is_binary(slug) do
    if :global.whereis_name(Zone.name(slug) |> elem(1)) == :undefined do
      case DynamicSupervisor.start_child(__MODULE__.Extra, Keeper.child_spec(slug)) do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
        _ -> :ok
      end
    else
      :ok
    end
  catch
    :exit, _ -> :ok
  end

  @doc "The PubSub topic a zone's creatures are broadcast on."
  def topic(slug), do: "bacon_world:mobs:#{slug}"

  @doc "Every creature (and corpse) in the zone, as `BaconWorld.Mobs.Brain.view/1` maps."
  def snapshot(slug), do: call(slug, :snapshot, [])

  @doc "A player's swing (see `BaconWorld.Mobs.Brain.melee/4`). `{:ok, hits}`."
  def melee(slug, attack), do: call(slug, {:melee, attack}, {:error, :mobs_unavailable})

  @doc "A spell landing on a creature (`Brain.spell_hit/3`): a hit map or `{:error, reason}`."
  def spell_hit(slug, attack), do: call(slug, {:spell_hit, attack}, {:error, :mobs_unavailable})

  @doc "An area, cone or chain spell/skill (`Brain.spell_aoe/3`): `{:ok, hits}` or `{:error, reason}`."
  def spell_aoe(slug, attack), do: call(slug, {:spell_aoe, attack}, {:error, :mobs_unavailable})

  @doc "Taunts nearby creatures (`Brain.taunt/3`): `{:ok, count}`."
  def taunt(slug, attack), do: call(slug, {:taunt, attack}, {:error, :mobs_unavailable})

  @doc "Roots a creature (`Brain.root/3`): `:ok` or `{:error, reason}`."
  def root(slug, attack), do: call(slug, {:root, attack}, {:error, :mobs_unavailable})

  @doc """
  Replaces the creatures of one placed spawn (`BaconWorld.Building`): `points` in
  `BaconWorld.Mobs.Spawns.points/0`'s shape, all with ids `"p:<placement_id>:<n>"`; `[]` removes
  them. The old ones vanish and the new ones rise at once.
  """
  def put_points(slug, placement_id, points), do: cast(slug, {:put_points, placement_id, points})

  @doc """
  A managed camp (`BaconWorld.Mobs.Camps`) was saved (or deleted: `camp` nil): its creatures in
  zone `slug` start over. Moving a camp to another zone: call it for the old zone with nil.
  """
  def put_camp(slug, camp_id, camp), do: cast(slug, {:put_camp, camp_id, camp})

  @doc "A managed camp's creatures and clears, for the admin: `{:ok, status}` or `{:error, reason}`."
  def camp_status(slug, camp_id), do: call(slug, {:camp_status, camp_id}, {:error, :mobs_unavailable})

  @doc "Brings back at once a managed camp's dead and gone creatures."
  def respawn_camp(slug, camp_id), do: cast(slug, {:camp_respawn, camp_id})

  @doc "Clears a managed camp out: its creatures vanish and come back on their timers."
  def despawn_camp(slug, camp_id), do: cast(slug, {:camp_despawn, camp_id})

  def loot_open(slug, mob_id, character_id, pos), do: call(slug, {:loot_open, mob_id, character_id, pos}, {:error, :mobs_unavailable})
  def loot_take(slug, mob_id, character_id, index), do: call(slug, {:loot_take, mob_id, character_id, index}, {:error, :mobs_unavailable})
  def loot_return(slug, mob_id, item), do: cast(slug, {:loot_return, mob_id, item})
  def loot_close(slug, mob_id, character_id), do: cast(slug, {:loot_close, mob_id, character_id})

  defp call(slug, msg, default) do
    GenServer.call(Zone.name(slug), msg, 3_000)
  catch
    :exit, _ -> default
  end

  defp cast(slug, msg) do
    GenServer.cast(Zone.name(slug), msg)
  catch
    :exit, _ -> :ok
  end
end

defmodule BaconWorld.Combat do
  @moduledoc """
  Spells, HP/MP, PvP flags and respawning. Server-authoritative: the client
  asks, this module decides. (Melee lives in `BaconWorld.Melee` and
  `BaconWorldWeb.GameEvents`.)
  """

  import Ecto.Query, only: [from: 2]

  alias Bacon8.GamesRepo
  alias BaconWorld.{CharacterSpell, Spell, World}

  # Spells retired from the old web-lobby game: never granted or listed (their rows
  # stay in the database until the owner OKs a cleanup migration).
  @retired ~w(throw_stone)

  def get_spell_by_slug(slug) when is_binary(slug), do: GamesRepo.get_by(Spell, slug: slug)

  def list_character_spells(character_id) do
    from(cs in CharacterSpell,
      join: s in assoc(cs, :spell),
      where: cs.character_id == ^character_id and s.slug not in ^@retired,
      order_by: s.name,
      select: s
    )
    |> GamesRepo.all()
  end

  @doc "What the client gets to know about a spell."
  def spell_payload(%Spell{} = s) do
    Map.take(s, [:slug, :name, :mp_cost, :base_damage, :range, :recast_ms, :projectile_type])
  end

  @doc "Grants the starter spells to a freshly created character (none yet: melee comes first)."
  def grant_starter_spells(_character_id), do: :ok

  def get_character_stats(character_id) do
    with {:ok, c} <- World.fetch_character(character_id) do
      {:ok, %{hp: World.stat(c, "hp"), max_hp: World.stat(c, "max_hp"), mp: World.stat(c, "mp"), max_mp: World.stat(c, "max_mp")}}
    end
  end

  @doc "Sets HP and MP, clamped to 0..max."
  def update_character_hp_mp(character_id, hp, mp) when is_integer(hp) and is_integer(mp) do
    with {:ok, c} <- World.fetch_character(character_id) do
      patch = %{"hp" => clamp(hp, World.stat(c, "max_hp")), "mp" => clamp(mp, World.stat(c, "max_mp"))}
      World.merge_stats(World.by_id_query(c.id), patch)
      {:ok, patch}
    end
  end

  @doc """
  Full HP/MP and back to where the character is bound (a binding stone, `BaconWorld.Building.bind/4`),
  else the zone's spawn point. Returns the point; a bind in another zone carries `zone:` (its slug), and
  the LiveView moves the character there when it respawns (2026-11-02, owner: Recall and respawning
  stayed in the current zone at the bind's coordinates).
  """
  def respawn_character(character_id) do
    with {:ok, c} <- World.fetch_character(character_id) do
      zone = World.zone_for((c.settings || %{})["zone_slug"])
      %{x: x, y: y, z: z, heading: h} = spawn = respawn_point(c, zone)

      World.merge_stats(World.by_id_query(c.id), %{"hp" => World.stat(c, "max_hp"), "mp" => World.stat(c, "max_mp")})
      # a bind in another zone: that zone's position is saved by the move (BaconWorldWeb.PlayLive.transfer_to_zone/7)
      if spawn[:zone] == nil,
        do: World.merge_settings(World.by_id_query(c.id), %{"position" => %{"x" => x, "y" => y, "z" => z, "heading" => h}})

      {:ok, spawn}
    end
  end

  @doc false
  def respawn_point(c, zone) do
    case bind_point(c) do
      nil -> World.spawn_point(zone)
      %{zone: slug} = b -> if slug == ((c.settings || %{})["zone_slug"] || "lobby"), do: Map.delete(b, :zone), else: b
    end
  end

  @doc """
  Where the character is bound: `%{x, y, z, heading, zone}` (scene units; `zone` the bind's zone slug),
  or nil when it never bound. Recall (BaconWorldWeb.SkillEvents) and respawning read it.
  """
  def bind_point(c) do
    case (c.settings || %{})["bind"] do
      %{"x" => x, "z" => z} = b when is_number(x) and is_number(z) ->
        %{x: x * 1.0, y: (b["y"] || 0.0) * 1.0, z: z * 1.0, heading: (b["heading"] || 0.0) * 1.0, zone: b["zone"] || "lobby"}

      _ ->
        nil
    end
  end

  @doc "True when the character is flagged for PvP (both sides must be for a swing to land)."
  def pvp_flagged?(character_id) do
    case World.fetch_character(character_id) do
      {:ok, c} -> World.stat(c, "pvp_flagged") == true
      _ -> false
    end
  end

  defp clamp(value, max_value), do: value |> min(max_value) |> max(0)
end

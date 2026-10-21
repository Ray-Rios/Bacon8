defmodule BaconWorld.Combat do
  @moduledoc """
  Spells, HP/MP and respawning. Server-authoritative: the client asks, this
  module decides.
  """

  import Ecto.Query, only: [from: 2]

  alias Bacon8.GamesRepo
  alias BaconWorld.{CharacterSpell, Spell, World}

  @throw_stone_hit_chance 0.85

  def get_spell_by_slug(slug) when is_binary(slug), do: GamesRepo.get_by(Spell, slug: slug)

  def list_character_spells(character_id) do
    from(cs in CharacterSpell,
      join: s in assoc(cs, :spell),
      where: cs.character_id == ^character_id,
      order_by: s.name,
      select: s
    )
    |> GamesRepo.all()
  end

  @doc "What the client gets to know about a spell."
  def spell_payload(%Spell{} = s) do
    Map.take(s, [:slug, :name, :mp_cost, :base_damage, :range, :recast_ms, :projectile_type])
  end

  @doc "Grants the starter spells to a freshly created character."
  def grant_starter_spells(character_id) do
    case get_spell_by_slug("throw_stone") do
      nil ->
        :ok

      spell ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        GamesRepo.insert!(
          %CharacterSpell{character_id: character_id, spell_id: spell.id, unlocked_at: now},
          on_conflict: :nothing,
          conflict_target: [:character_id, :spell_id]
        )

        :ok
    end
  end

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

  @doc "Full HP/MP and back to the zone's spawn point. Returns the spawn point."
  def respawn_character(character_id) do
    with {:ok, c} <- World.fetch_character(character_id) do
      zone = World.zone_for((c.settings || %{})["zone_slug"])
      %{x: x, y: y, z: z, heading: h} = spawn = World.spawn_point(zone)

      World.merge_stats(World.by_id_query(c.id), %{"hp" => World.stat(c, "max_hp"), "mp" => World.stat(c, "max_mp")})
      World.merge_settings(World.by_id_query(c.id), %{"position" => %{"x" => x, "y" => y, "z" => z, "heading" => h}})
      {:ok, spawn}
    end
  end

  @doc """
  Throw Stone. Both characters must be PvP-flagged and in range; the caster
  pays MP; a hit does the spell's damage, and a kill respawns the target
  (its LiveView moves it when it receives `:zone_spell_result`).

  Returns `{:ok, result}` or `{:error, reason}`.
  """
  def cast_throw_stone(caster_id, target_id, caster_pos, target_pos) do
    with {:ok, spell} <- fetch_spell("throw_stone"),
         {:ok, caster} <- World.fetch_character(caster_id),
         {:ok, target} <- World.fetch_character(target_id),
         :ok <- check_pvp(caster, target),
         :ok <- check_mp(caster, spell.mp_cost),
         :ok <- check_range(caster_pos, target_pos, spell.range) do
      hit = :rand.uniform() <= @throw_stone_hit_chance
      damage = if hit, do: spell.base_damage, else: 0

      caster_mp = World.stat(caster, "mp") - spell.mp_cost
      target_hp_before = World.stat(target, "hp")
      target_hp = max(0, target_hp_before - damage)

      {:ok, _} = update_character_hp_mp(caster.id, World.stat(caster, "hp"), caster_mp)
      {:ok, _} = update_character_hp_mp(target.id, target_hp, World.stat(target, "mp"))

      died = target_hp == 0 and target_hp_before > 0

      spawn_coords =
        if died do
          case respawn_character(target.id) do
            {:ok, spawn} -> spawn
            _ -> nil
          end
        end

      {:ok,
       %{
         hit: hit,
         damage: damage,
         caster_mp: caster_mp,
         caster_max_mp: World.stat(caster, "max_mp"),
         target_hp: target_hp,
         target_max_hp: World.stat(target, "max_hp"),
         target_died: died,
         spawn_coords: spawn_coords,
         target_id: target.id,
         caster_id: caster.id
       }}
    end
  end

  defp fetch_spell(slug) do
    case get_spell_by_slug(slug) do
      nil -> {:error, :spell_not_found}
      spell -> {:ok, spell}
    end
  end

  defp check_pvp(caster, target) do
    if World.stat(caster, "pvp_flagged") and World.stat(target, "pvp_flagged"), do: :ok, else: {:error, :pvp_not_flagged}
  end

  defp check_mp(character, cost), do: if(World.stat(character, "mp") >= cost, do: :ok, else: {:error, :insufficient_mp})

  defp check_range(%{x: cx, z: cz}, %{x: tx, z: tz}, max_range) do
    if :math.sqrt(:math.pow(tx - cx, 2) + :math.pow(tz - cz, 2)) <= max_range, do: :ok, else: {:error, :out_of_range}
  end

  defp check_range(_, _, _), do: {:error, :invalid_position}

  defp clamp(value, max_value), do: value |> min(max_value) |> max(0)
end

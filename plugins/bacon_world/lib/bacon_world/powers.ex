defmodule BaconWorld.Powers do
  @moduledoc """
  Gear powers (2026-11-01, owner: "Each one will have its own in-game unique special power (surprise
  me)"): the jeweller's ten polished sets (`BaconWorld.Items` `jewel_sets/0`) each carry one. A
  power works while the set's bottom piece is worn (every body wears that piece; the top is the
  female's half of the look), so one character has at most one jeweller's power at a time.

  Pure functions; `BaconWorldWeb.GameEvents` applies them where swings land, kills happen and hits
  are taken. They work on the basic swings (both hands, heavy too), not on skills and spells.

    * `"midas"`     Midas Ward: one hit in five you take turns to gold: no damage, and a copper for
                    every two points it would have done.
    * `"thorns"`    Thornbite: a creature that strikes you takes back a third of the damage.
    * `"brilliance"` Brilliance: +15% chance of a critical hit.
    * `"snare"`     Silken Snare: one swing in four roots what it hits for 2 seconds.
    * `"starlit"`   Starlit Mind: swings restore mana, a quarter of the damage they do.
    * `"starfire"`  Starfire: one swing in five bursts into starfire for double damage.
    * `"lasso"`     Long Lasso: swings reach 1.5 m further; one in three drags what it hits to you.
    * `"riptide"`   Riptide: swings heal you for 15% of the damage they do.
    * `"bloom"`     Bloom: each kill heals you for 12% of your health.
    * `"phoenix"`   Phoenix Rebirth: a killing blow leaves you on a third of your health instead;
                    once every five minutes.
  """

  alias BaconWorld.Items

  @powers %{
    "midas" => %{name: "Midas Ward", summary: "One hit in five you take turns to gold: no damage, and a copper for every two points it would have done."},
    "thorns" => %{name: "Thornbite", summary: "A creature that strikes you takes back a third of the damage."},
    "brilliance" => %{name: "Brilliance", summary: "+15% chance of a critical hit with your swings."},
    "snare" => %{name: "Silken Snare", summary: "One swing in four roots what it hits for 2 seconds."},
    "starlit" => %{name: "Starlit Mind", summary: "Your swings restore mana: a quarter of the damage they do."},
    "starfire" => %{name: "Starfire", summary: "One swing in five bursts into starfire for double damage."},
    "lasso" => %{name: "Long Lasso", summary: "Your swings reach 1.5 m further, and one in three drags what it hits to you."},
    "riptide" => %{name: "Riptide", summary: "Your swings heal you for 15% of the damage they do."},
    "bloom" => %{name: "Bloom", summary: "Every kill heals you for 12% of your health."},
    "phoenix" => %{name: "Phoenix Rebirth", summary: "A killing blow leaves you standing on a third of your health instead. Once every five minutes."},
    # the jeweller's heels: the client runs faster (Items run_speed 1.5); nothing to do here
    "swift" => %{name: "Swift Heels", summary: "You run 50% faster."}
  }

  @phoenix_cooldown_ms 300_000

  @doc "A power's name and summary, or nil."
  def get(id) when is_binary(id), do: Map.get(@powers, id)
  def get(_), do: nil

  @doc "All the power ids."
  def ids, do: Map.keys(@powers)

  @doc "How long Phoenix Rebirth rests between uses (ms)."
  def phoenix_cooldown_ms, do: @phoenix_cooldown_ms

  @doc "The powers worn: from an equipment map (`slot => item | item id | nil`), as a list of ids."
  def active(equipment) when is_map(equipment) do
    equipment
    |> Map.values()
    |> Enum.flat_map(fn
      %{power: p} when is_binary(p) -> [p]
      id when is_binary(id) -> case Items.get(id) do
          %{power: p} when is_binary(p) -> [p]
          _ -> []
        end
      _ -> []
    end)
    |> Enum.uniq()
  end

  def active(_), do: []

  @doc """
  A swing as the worn powers change it (the attack map `BaconWorld.Mobs.melee/2` takes), and the
  powers that fired (`["starfire", ...]`, for the combat log). `rand` returns a float in [0, 1).
  """
  def swing(powers, attack, rand \\ &:rand.uniform/0) do
    Enum.reduce(powers, {attack, []}, fn
      "brilliance", {a, fired} ->
        {Map.update(a, :crit_bonus, 0.15, &((&1 || 0.0) + 0.15)), fired}

      "starfire", {a, fired} ->
        if rand.() < 0.2, do: {Map.update(a, :mult, 2.0, &((&1 || 1.0) * 2.0)), ["starfire" | fired]}, else: {a, fired}

      "snare", {a, fired} ->
        if rand.() < 0.25, do: {Map.put(a, :root_ms, 2_000), ["snare" | fired]}, else: {a, fired}

      "lasso", {a, fired} ->
        a = Map.update(a, :extra_reach, 1.5, &((&1 || 0.0) + 1.5))
        if rand.() < 1 / 3, do: {Map.put(a, :pull_m, 1.5), ["lasso" | fired]}, else: {a, fired}

      _, acc ->
        acc
    end)
  end

  @doc "`{hp, mp}` a swing's hits give back (`hits`: `[%{damage: n}]`)."
  def after_swing(powers, hits) do
    dealt = hits |> Enum.map(&(Map.get(&1, :damage) || 0)) |> Enum.sum()
    hp = if "riptide" in powers, do: round(dealt * 0.15), else: 0
    mp = if "starlit" in powers, do: round(dealt * 0.25), else: 0
    {hp, mp}
  end

  @doc "Health a number of kills gives back (Bloom)."
  def on_kills(powers, kills, max_hp) when kills > 0 do
    if "bloom" in powers, do: round(max_hp * 0.12) * kills, else: 0
  end

  def on_kills(_, _, _), do: 0

  @doc """
  A hit about to be taken (after armour): `{:gold, coins}` when Midas Ward turns it to gold,
  else `{:hit, damage, thorns}` (`thorns`: the damage to send back to the creature, 0 for none).
  """
  def on_hit(powers, damage, rand \\ &:rand.uniform/0) do
    cond do
      damage > 0 and "midas" in powers and rand.() < 0.2 -> {:gold, max(1, div(damage, 2))}
      "thorns" in powers and damage > 0 -> {:hit, damage, max(1, round(damage / 3))}
      true -> {:hit, damage, 0}
    end
  end

  @doc """
  Phoenix Rebirth: when a hit would kill (`new_hp == 0`) and the power is ready (`last_at` the
  monotonic time it last fired, or nil), the health to stand back up on; else nil.
  """
  def rebirth(powers, new_hp, max_hp, last_at, now) do
    if new_hp == 0 and "phoenix" in powers and (is_nil(last_at) or now - last_at >= @phoenix_cooldown_ms) do
      max(1, div(max_hp, 3))
    end
  end
end

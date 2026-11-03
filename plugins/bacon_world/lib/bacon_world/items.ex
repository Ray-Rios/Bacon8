defmodule BaconWorld.Items do
  @moduledoc """
  Every item in Bacon World. Since 2026-11-02 (owner: "move everything into the DB") each item's
  definition is a row of `bacon_world_item_defs` (`BaconWorld.ItemDef`), edited on
  /admin/bacon_world/database; it was a catalogue in code until then. The table is filled once from
  `priv/seed/items.json` (that catalogue, exported) the first time the game reads it, and the
  catalogue is cached in `:persistent_term` (`reload/0` after an edit, on every node).
  Characters' copies are rows in `bacon_world_items` (`BaconWorld.Inventory`).

  Besides the fields below, `group` says which set an item belongs to (`"underwear:<set>"`,
  `"armor:<set>"`, `"robe"`, `"jewel:<set>"`), for `underwear_sets/0` and the others.

  Weapons read like EverQuest's: **DMG** is the most one hit does before bonuses,
  **DLY** the time between swings in tenths of a second, so a DMG 6 DLY 12 sword
  swings every 1.2 s. Each weapon is drawn with a model from
  `/models/Weapons/B8_Weapons.glb` (node `W_<model>`, icon
  `Weapons/icons/W_<model>.png`) and animated with an animation set from the B8
  packs (`anims.json` "sets": `sword_1h`, `two_hand`, ...).

  Clothes are items too: underwear (`"under_top"`, `"under_bottom"`), cloth armour
  (`"head"`, `"hands"`, `"arms"`, `"wrist"`, `"chest"`, `"legs"`, `"feet"`) and robes (`"chest"`). A worn item is drawn on the character: `wear` says
  which garment of each body model shows it and, for the garments made from the body,
  which design (`Humans/Wardrobe/<garment>__<design>.webp`); `colors` tints it (`main`,
  `trim`, `accent`; shoes use `upper`, `sole` and `laces`). Characters start in the
  linen set; Tilda the clothier sells the rest (`BaconWorld.Merchants`).

  Fields:

    * `id`, `name`
    * `kind` - `"weapon"`, `"shield"`, `"light"`, `"armor"` or `"junk"`
    * `slots` - where it can be equipped: `"main"` (right hand), `"off"` (left), or a
      worn slot (`"head"`, `"under_top"`, `"under_bottom"`, `"chest"`, `"legs"`, `"feet"`)
    * `hands` - 2 for two-handed weapons, which need the off hand empty
    * `set` - the animation set it is held and swung with
    * `skill` - EverQuest's weapon skill line, shown on the item
    * `dmg`, `dly`, `reach` (metres, from the grip), `ac` (shields)
    * `stack` - how many fit in one slot; `value` - in copper
    * `model` - the weapon model, or nil (the icon then comes from `icon`)
    * `icon_url` - an icon of its own (the plugin's `priv/static/icons`), for items without a model
      or weapon icon on the models volume (fishing, 2026-10-26)
    * `wear`, `colors` - how a worn item is drawn (above)
    * `ranged` - a bow (2026-10-28): shoots endless arrows out to `reach` (`BaconWorld.Melee`)
  """

  @fist %{id: "fist", name: "Fist", kind: "weapon", slots: [], hands: 1, set: "unarmed", skill: "Hand to Hand", dmg: 3, dly: 9, reach: 0.75, ac: 0, stack: 1, value: 0, model: nil, icon: nil}

  # What the jeweller's sets cost (Gems): a rule of the game, not an item's field.
  @jewel_price_gems 100

  @wear_slots ~w(head under_top under_bottom chest legs feet wrist arms hands)

  @defaults %{hands: 1, set: nil, skill: nil, dmg: 0, dly: 0, reach: 0, ac: 0, stack: 1, value: 0, model: nil, icon: nil, icon_url: nil,
              wear: nil, colors: nil, ranged: false, gems: nil, jewel: nil, power: nil, run_speed: nil, group: nil, slots: []}

  @starter_wear [{"homespun_top", "under_top"}, {"homespun_bottom", "under_bottom"}]

  @starter_kit [
    {"worn_short_sword", "main"},
    {"worn_round_shield", nil},
    {"grill_fork", nil},
    {"worn_club", nil},
    {"worn_spear", nil},
    {"worn_quarterstaff", nil},
    {"torch", nil}
  ]

  @doc "All items, as maps, in the catalogue's order."
  def all, do: catalogue().list

  @doc "An item by id, or nil."
  def get(id) when is_binary(id), do: Map.get(catalogue().by_id, id)
  def get(_), do: nil

  # ---------------------------------------------------------------- sets

  @doc "The underwear set ids, starter first (for the merchant and the tests)."
  def underwear_sets, do: groups("underwear:")

  @doc "The cloth armour set ids."
  def armor_sets, do: groups("armor:")

  @doc "The robe item ids."
  def robes, do: for(i <- all(), i.group == "robe", do: i.id)

  @doc "The jeweller's set ids (`jw_*`)."
  def jewel_sets, do: groups("jewel:")

  @doc "What a jeweller's set costs (Gems)."
  def jewel_price_gems, do: @jewel_price_gems

  @doc "What buying `item` from the jeweller gives a body: the heels alone, or the set's pieces."
  def jewel_bundle(%{slots: ["feet"], id: id}, _body), do: [id]
  def jewel_bundle(%{jewel: set}, body) when is_binary(set), do: jewel_pieces(set, body)

  @doc "The pieces of a jeweller's set a body wears (the male wears the bottom only)."
  def jewel_pieces(set, body \\ "female")
  def jewel_pieces(set, "male"), do: ["#{set}_bottom"]
  def jewel_pieces(set, _), do: ["#{set}_top", "#{set}_bottom"]

  defp groups(prefix) do
    all()
    |> Enum.flat_map(fn i -> if is_binary(i.group) and String.starts_with?(i.group, prefix), do: [String.replace_prefix(i.group, prefix, "")], else: [] end)
    |> Enum.uniq()
  end

  # ---------------------------------------------------------------- the table

  @cache {__MODULE__, :catalogue}
  @fields ~w(id name kind slots hands set skill dmg dly reach ac stack value model icon icon_url wear colors ranged gems jewel power run_speed group)a
  @field_names Map.new(@fields, &{Atom.to_string(&1), &1})

  defp catalogue do
    case :persistent_term.get(@cache, nil) do
      nil -> load()
      c -> c
    end
  end

  @doc "Forgets the cached catalogue on this node and the others (after an edit)."
  def reload do
    :persistent_term.erase(@cache)
    for n <- Node.list(), do: :erpc.cast(n, :persistent_term, :erase, [@cache])
    :ok
  end

  defp load do
    rows = (Application.get_env(:bacon8, __MODULE__, [])[:source] != :seed && from_db()) || seed_rows()
    list = rows |> Enum.sort_by(&(&1["position"] || 0)) |> Enum.map(&item/1)
    c = %{list: list, by_id: Map.new(list, &{&1.id, &1})}
    :persistent_term.put(@cache, c)
    c
  end

  @doc "An item map (atom keys, defaults filled) from a stored definition (string keys)."
  def item(data) when is_map(data) do
    Enum.reduce(data, @defaults, fn {k, v}, acc ->
      case Map.get(@field_names, to_string(k)) do
        nil -> acc
        key -> Map.put(acc, key, v)
      end
    end)
  end

  @doc "An item map as it is stored (string keys, only the item's fields)."
  def to_data(item), do: for({k, v} <- Map.take(item, @fields), into: %{}, do: {Atom.to_string(k), v})

  defp from_db do
    import Ecto.Query
    rows = Bacon8.GamesRepo.all(from d in BaconWorld.ItemDef, select: %{data: d.data, position: d.position})

    rows =
      if rows == [] do
        seed_db!()
        Bacon8.GamesRepo.all(from d in BaconWorld.ItemDef, select: %{data: d.data, position: d.position})
      else
        rows
      end

    Enum.map(rows, &Map.put(&1.data, "position", &1.position))
  rescue
    _ -> nil
  end

  # the first read: the table gets the catalogue as it was in code (priv/seed/items.json)
  defp seed_db! do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    entries =
      for r <- seed_rows() do
        %{id: r["id"], data: Map.delete(r, "position"), position: r["position"] || 0, inserted_at: now, updated_at: now}
      end

    entries
    |> Enum.chunk_every(100)
    |> Enum.each(&Bacon8.GamesRepo.insert_all(BaconWorld.ItemDef, &1, on_conflict: :nothing, conflict_target: [:id]))
  end

  @doc """
  Saves an item's definition (the database editor): `data` with string keys (the item's fields).
  `{:ok, item}` or `{:error, message}`. The catalogue is reloaded on every node; players see the
  change in what the server does at once, and in tooltips and looks on their next page load.
  """
  def save_def(%{"id" => id} = data) when is_binary(id) and id != "" do
    with true <- String.match?(id, ~r/^[a-z0-9_]{2,60}$/) || {:error, "An id is 2-60 lowercase letters, digits and underscores."},
         true <- data["kind"] in ~w(weapon shield light armor junk) || {:error, "Kind must be weapon, shield, light, armor or junk."},
         true <- (is_binary(data["name"]) and String.trim(data["name"]) != "") || {:error, "It needs a name."} do
      import Ecto.Query
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      clean = data |> item() |> to_data()
      pos = Bacon8.GamesRepo.one(from d in BaconWorld.ItemDef, where: d.id == ^id, select: d.position) ||
              (Bacon8.GamesRepo.one(from d in BaconWorld.ItemDef, select: max(d.position)) || 0) + 1

      Bacon8.GamesRepo.insert_all(BaconWorld.ItemDef, [%{id: id, data: clean, position: pos, inserted_at: now, updated_at: now}],
        on_conflict: {:replace, [:data, :updated_at]}, conflict_target: [:id])

      reload()
      {:ok, get(id)}
    end
  end

  def save_def(_), do: {:error, "An item needs an id."}

  @doc "Deletes an item's definition, unless a character owns one (`{:error, message}` then)."
  def delete_def(id) when is_binary(id) do
    import Ecto.Query
    owned = Bacon8.GamesRepo.one(from i in BaconWorld.InventoryItem, where: i.item_id == ^id, select: count(i.id))

    if owned > 0 do
      {:error, "#{owned} character(s) own one: it can't be deleted while they do."}
    else
      Bacon8.GamesRepo.delete_all(from d in BaconWorld.ItemDef, where: d.id == ^id)
      reload()
      :ok
    end
  end

  @doc "The seed catalogue (`priv/seed/items.json`), string keys."
  def seed_rows do
    [Bacon8.Plugins.priv_dir("bacon_world"), "seed", "items.json"]
    |> Path.join()
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("items")
  end

  @doc "What an empty hand swings with."
  def fist, do: @fist

  @doc "The starter kit, as `{item_id, slot or nil (first free bag slot)}`."
  def starter_kit, do: @starter_kit

  @doc "What every character starts out wearing, as `{item_id, slot}`."
  def starter_wear, do: @starter_wear

  @doc "The slots worn items go in (besides the hands)."
  def wear_slots, do: @wear_slots

  @doc "True for an item that is worn (underwear, cloth armour)."
  def wearable?(%{kind: "armor"}), do: true
  def wearable?(_), do: false

  @doc "True when `item` may go in equipment slot `slot` (a hand or a worn slot)."
  def equippable?(%{slots: slots}, slot), do: slot in slots
  def equippable?(_, _), do: false

  def two_handed?(%{hands: 2}), do: true
  def two_handed?(_), do: false

  @doc "What the 3D client needs about every item (no secrets here: it is all shown in tooltips)."
  def catalog_payload do
    Map.new(all(), fn i ->
      {i.id,
       %{
         name: i.name,
         kind: i.kind,
         slots: i.slots,
         hands: i.hands,
         set: i.set,
         skill: i.skill,
         dmg: i.dmg,
         dly: i.dly,
         reach: i.reach,
         ac: i.ac,
         stack: i.stack,
         value: i.value,
         model: i.model,
         icon: i.model || i.icon,
         icon_path: icon_path(i),
         # a picture of its own (the plugin's static files), instead of the models volume's
         icon_url: i.icon_url,
         wear: i.wear,
         colors: i.colors,
         # a bow: shoots arrows (BaconWorld.Melee.ranged?/1)
         ranged: i.ranged == true,
         # the jeweller's sets: bought with Gems, a power of their own (BaconWorld.Powers)
         gems: i.gems,
         jewel: i.jewel,
         power: power_payload(i.power),
         run_speed: Map.get(i, :run_speed)
       }}
    end)
  end

  # Where the inventory icon is, under /models.
  defp power_payload(nil), do: nil
  defp power_payload(id), do: (p = BaconWorld.Powers.get(id)) && %{id: id, name: p.name, summary: p.summary}

  defp icon_path(%{kind: "armor", id: id}), do: "Humans/Wardrobe/icons/#{id}.png"
  defp icon_path(%{model: m}) when is_binary(m), do: "Weapons/icons/W_#{m}.png"
  defp icon_path(%{icon: i}) when is_binary(i), do: "Weapons/icons/W_#{i}.png"
  defp icon_path(_), do: nil
end

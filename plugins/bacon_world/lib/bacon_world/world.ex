defmodule BaconWorld.World do
  @moduledoc """
  Bacon World's characters, zones and positions.

  Characters are the platform's `Bacon8.Games.GameCharacter` rows for this
  plugin's game, so they show up wherever the hub lists a player's characters.
  Lobby-specific data lives in the two JSON maps:

    * `stats`    - `"hp"`, `"max_hp"`, `"mp"`, `"max_mp"`, `"pvp_flagged"`
    * `settings` - `"character_type"`, `"model_path"`, `"zone_slug"`,
                   `"position" => %{"x", "y", "z", "heading"}`,
                   `"appearance"` (the look of a Bacon8 human; `BaconWorld.Appearance`)

  Writes to a single key go through `merge_stats/2` and `merge_settings/2`,
  which merge in SQL (`jsonb ||`), so a position save never overwrites HP that
  another player's spell just changed.
  """

  import Ecto.Query, only: [from: 2]

  alias Bacon8.{Games, GamesRepo}
  alias Bacon8.Games.GameCharacter
  alias BaconWorld.{Appearance, Combat, Models, Zone}

  @plugin_slug "bacon_world"
  @max_characters_per_user 16
  @default_zone_slug "lobby"
  @default_stats %{"hp" => 10, "max_hp" => 10, "mp" => 10, "max_mp" => 10, "pvp_flagged" => false}

  def max_characters_per_user, do: @max_characters_per_user

  @doc "This plugin's row in the `games` table (created on first use)."
  def game_id do
    case Bacon8.Plugins.ensure_game(@plugin_slug) do
      {:ok, game} -> {:ok, game.id}
      error -> error
    end
  end

  defp game_id! do
    {:ok, id} = game_id()
    id
  end

  # ---------------------------------------------------------------------------
  # Characters
  # ---------------------------------------------------------------------------

  @doc "The user's Lobby characters, oldest first, as `view/1` maps."
  def list_user_characters(user_id) when is_binary(user_id) do
    game_id = game_id!()

    from(c in GameCharacter, where: c.game_id == ^game_id and c.user_id == ^user_id, order_by: [asc: c.inserted_at])
    |> GamesRepo.all()
    |> Enum.map(&view/1)
  end

  @doc "One of the user's characters as a `view/1` map, or nil."
  def get_character_for_user(user_id, character_id) do
    case owned(user_id, character_id) do
      nil -> nil
      character -> view(character)
    end
  end

  @doc """
  Creates a character in the default zone with full HP/MP and the starter
  spells. With an `"appearance"` (a Bacon8 human's look), its body type picks the
  model and the normalised look is saved. Errors: `:character_limit_reached`,
  `:invalid_model_path`, `:invalid_appearance`, `:default_zone_missing`, or an
  `Ecto.Changeset` for bad name/type.
  """
  def create_character(user_id, attrs) when is_binary(user_id) and is_map(attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    with {:ok, game_id} <- game_id(),
         :ok <- ensure_character_cap(game_id, user_id),
         {:ok, fields} <- validate_new(attrs),
         {:ok, model_path, look} <- resolve_look(attrs),
         {:ok, zone} <- default_zone() do
      GamesRepo.transaction(fn ->
        settings =
          %{
            "character_type" => fields.character_type,
            "model_path" => model_path,
            "zone_slug" => zone.slug,
            "position" => spawn_position(zone)
          }
          |> then(&if(look, do: Map.put(&1, "appearance", look), else: &1))

        attrs = %{
          user_id: user_id,
          game_id: game_id,
          name: fields.name,
          stats: @default_stats,
          settings: settings
        }

        case Games.create_character(attrs) do
          {:ok, character} ->
            :ok = Combat.grant_starter_spells(character.id)
            view(character)

          {:error, changeset} ->
            GamesRepo.rollback(changeset)
        end
      end)
    end
  end

  # The model, and the look when one was sent: a look's body type decides the model.
  defp resolve_look(%{"appearance" => raw} = attrs) when not is_nil(raw) do
    fallback = Appearance.body_for_model(attrs["model_path"])

    with {:ok, look} <- Appearance.normalize(raw, fallback, Models.human_style_ids()),
         {:ok, path} <- Models.validate(Appearance.model_path(look["body"])) do
      {:ok, path, look}
    end
  end

  defp resolve_look(attrs) do
    with {:ok, path} <- Models.validate(attrs["model_path"]), do: {:ok, path, nil}
  end

  @doc """
  Saves a new look for one of the user's characters. The body type is fixed at
  creation, so a different `"body"` in `raw` is ignored. Returns `{:ok, look}`,
  `{:error, :not_found}` or `{:error, :invalid_appearance}`.
  """
  def update_appearance(user_id, character_id, raw) do
    case owned(user_id, character_id) do
      nil ->
        {:error, :not_found}

      character ->
        model = current_model((character.settings || %{})["model_path"])

        with true <- Appearance.human_model?(model) || {:error, :invalid_appearance},
             true <- is_map(raw) || {:error, :invalid_appearance},
             body = Appearance.body_for_model(model),
             {:ok, look} <- Appearance.normalize(Map.put(stringify(raw), "body", body), body, Models.human_style_ids()) do
          merge_settings(owned_query(user_id, character_id), %{"appearance" => look})
          {:ok, look}
        end
    end
  end

  @doc """
  The looks of up to 64 Bacon World characters by id (for drawing other players),
  as `%{id => look}`. Ids that aren't Bacon World characters are left out; a
  character that isn't a Bacon8 human maps to nil.
  """
  def appearances_for(ids) when is_list(ids) do
    uuids =
      ids
      |> Enum.take(64)
      |> Enum.flat_map(fn id ->
        case Ecto.UUID.cast(id) do
          {:ok, uuid} -> [uuid]
          :error -> []
        end
      end)
      |> Enum.uniq()

    if uuids == [] do
      %{}
    else
      game_id = game_id!()

      from(c in GameCharacter, where: c.game_id == ^game_id and c.id in ^uuids, select: {c.id, c.settings})
      |> GamesRepo.all()
      |> Map.new(fn {id, settings} ->
        settings = settings || %{}
        {id, Appearance.for_settings(settings, current_model(settings["model_path"]))}
      end)
    end
  end

  def appearances_for(_), do: %{}

  defp stringify(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)

  # Name and type rules beyond GameCharacter's: at least two characters each.
  defp validate_new(attrs) do
    types = %{name: :string, character_type: :string, model_path: :string}

    {%{}, types}
    |> Ecto.Changeset.cast(attrs, Map.keys(types))
    |> Ecto.Changeset.update_change(:name, &String.trim/1)
    |> Ecto.Changeset.update_change(:character_type, &String.trim/1)
    |> Ecto.Changeset.validate_required([:name, :character_type])
    |> Ecto.Changeset.validate_length(:name, min: 2, max: 24)
    |> Ecto.Changeset.validate_length(:character_type, min: 2, max: 40)
    |> Ecto.Changeset.apply_action(:insert)
  end

  def delete_character_for_user(user_id, character_id) do
    case owned(user_id, character_id) do
      nil -> {:error, :not_found}
      character -> with {:ok, deleted} <- Games.delete_character(character), do: {:ok, view(deleted)}
    end
  end

  @doc "Everything the 3D client needs to enter the world as this character."
  def character_login_payload(user_id, character_id) do
    case owned(user_id, character_id) do
      nil ->
        {:error, :not_found}

      character ->
        c = view(character)
        zone = zone_for(c.zone_slug)

        {:ok,
         %{
           user_id: character.user_id,
           character_id: c.id,
           name: c.name,
           character_type: c.character_type,
           model_path: c.model_path,
           hp: c.hp,
           max_hp: c.max_hp,
           mp: c.mp,
           max_mp: c.max_mp,
           pvp_flagged: c.pvp_flagged,
           appearance: c.appearance,
           spells: Enum.map(Combat.list_character_spells(c.id), &Combat.spell_payload/1),
           zone: %{id: zone && zone.id, name: zone && zone.name, slug: zone && zone.slug},
           position: c.position
         }}
    end
  end

  @doc "Saves where the character stands (and which zone), for the next login."
  def save_position(user_id, character_id, zone_slug, %{x: x, y: y, z: z, heading: heading}) do
    position = %{"x" => x, "y" => y, "z" => z, "heading" => heading}

    case merge_settings(owned_query(user_id, character_id), %{"position" => position, "zone_slug" => zone_slug}) do
      1 -> :ok
      0 -> {:error, :not_found}
    end
  end

  @doc "Flips the character's PvP flag. Returns `{:ok, new_flag}`."
  def toggle_pvp(user_id, character_id) do
    case owned(user_id, character_id) do
      nil ->
        {:error, :not_found}

      character ->
        flag = not stat(character, "pvp_flagged")
        merge_stats(by_id_query(character.id), %{"pvp_flagged" => flag})
        {:ok, flag}
    end
  end

  # ---------------------------------------------------------------------------
  # Shared helpers (also used by BaconWorld.Combat)
  # ---------------------------------------------------------------------------

  @doc false
  def fetch_character(character_id) do
    with {:ok, id} <- Ecto.UUID.cast(character_id),
         %GameCharacter{} = c <- GamesRepo.one(by_id_query(id)) do
      {:ok, c}
    else
      _ -> {:error, :character_not_found}
    end
  end

  @doc false
  def by_id_query(character_id) do
    game_id = game_id!()
    from(c in GameCharacter, where: c.id == ^character_id and c.game_id == ^game_id)
  end

  @doc false
  def merge_stats(query, patch) do
    {count, _} = GamesRepo.update_all(from(c in query, update: [set: [stats: fragment("coalesce(?, '{}'::jsonb) || ?", c.stats, type(^patch, :map))]]), [])
    count
  end

  @doc false
  def merge_settings(query, patch) do
    {count, _} =
      GamesRepo.update_all(from(c in query, update: [set: [settings: fragment("coalesce(?, '{}'::jsonb) || ?", c.settings, type(^patch, :map))]]), [])

    count
  end

  @doc "A stat with its default."
  def stat(%GameCharacter{stats: stats}, key), do: Map.get(stats || %{}, key, Map.fetch!(@default_stats, key))

  @doc "The zone with this slug, falling back to the default zone."
  def zone_for(slug) do
    (is_binary(slug) && GamesRepo.get_by(Zone, slug: slug)) || GamesRepo.get_by(Zone, slug: @default_zone_slug)
  end

  @doc "A zone's spawn point as a position map (atom keys)."
  def spawn_point(nil), do: %{x: 0.0, y: 0.0, z: 0.0, heading: 0.0}
  def spawn_point(%Zone{} = z), do: %{x: z.spawn_x, y: z.spawn_y, z: z.spawn_z, heading: z.spawn_heading}

  @doc "A GameCharacter as the plain map the LiveView works with."
  def view(%GameCharacter{} = c) do
    settings = c.settings || %{}
    pos = settings["position"] || %{}
    model_path = current_model(settings["model_path"])

    %{
      id: c.id,
      user_id: c.user_id,
      name: c.name,
      character_type: settings["character_type"] || "",
      model_path: model_path,
      appearance: Appearance.for_settings(settings, model_path),
      zone_slug: settings["zone_slug"] || @default_zone_slug,
      hp: stat(c, "hp"),
      max_hp: stat(c, "max_hp"),
      mp: stat(c, "mp"),
      max_mp: stat(c, "max_mp"),
      pvp_flagged: stat(c, "pvp_flagged"),
      position: %{
        x: num(pos["x"]),
        y: num(pos["y"]),
        z: num(pos["z"]),
        heading: num(pos["heading"])
      }
    }
  end

  # ---------------------------------------------------------------------------

  defp owned(user_id, character_id) do
    case Ecto.UUID.cast(character_id) do
      {:ok, _} -> GamesRepo.one(owned_query(user_id, character_id))
      :error -> nil
    end
  end

  defp owned_query(user_id, character_id) do
    game_id = game_id!()

    case Ecto.UUID.cast(character_id) do
      {:ok, id} -> from(c in GameCharacter, where: c.id == ^id and c.game_id == ^game_id and c.user_id == ^user_id)
      # Matches nothing.
      :error -> from(c in GameCharacter, where: false)
    end
  end

  defp ensure_character_cap(game_id, user_id) do
    count = GamesRepo.aggregate(from(c in GameCharacter, where: c.game_id == ^game_id and c.user_id == ^user_id), :count)
    if count >= @max_characters_per_user, do: {:error, :character_limit_reached}, else: :ok
  end

  defp default_zone do
    case GamesRepo.get_by(Zone, slug: @default_zone_slug) do
      nil -> {:error, :default_zone_missing}
      zone -> {:ok, zone}
    end
  end

  defp spawn_position(zone) do
    %{x: x, y: y, z: z, heading: h} = spawn_point(zone)
    %{"x" => x, "y" => y, "z" => z, "heading" => h}
  end

  defp num(n) when is_number(n), do: n * 1.0
  defp num(_), do: 0.0

  # Models are files on a volume, curated by supported_models.txt, so one can be
  # removed after characters picked it. Those characters wear the first model still
  # offered instead of an empty path (which the client draws as a grey box).
  defp current_model(path) when is_binary(path) and path != "" do
    case Models.validate(path) do
      {:ok, path} -> path
      {:error, _} -> default_model()
    end
  end

  defp current_model(_), do: default_model()

  defp default_model do
    case Models.list() do
      [%{model_path: path} | _] -> path
      [] -> ""
    end
  end
end

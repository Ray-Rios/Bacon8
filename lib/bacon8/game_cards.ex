defmodule Bacon8.GameCards do
  @moduledoc """
  The cards on /games: one per active plugin game, a literal card with a front and a
  back (BACON8.md §9, "Game cards"). The front cycles through pictures; hovering turns
  the card over to the back, which has a picture, the details and a Play button.

  ## Where a card comes from

  A plugin ships its card in its own folder, served at `/plugins/<slug>/card/...` by
  `Bacon8Web.Plugs.PluginStatic`:

      plugins/<slug>/priv/static/card/
        front-1.webp, front-2.webp ...   the front's pictures, shown in number order
        back.webp                        the back's picture (optional: the first front otherwise)
        card.json                        optional text, all keys optional:
                                         {"tagline": "...", "details": "...",
                                          "play_label": "Play", "seconds": 5}

  Pictures may be `.webp`, `.png`, `.jpg`, `.jpeg` or `.avif`. Without a tagline the card
  shows the game's `description` (`game/0`).

  ## In the browser, or a download (2026-10-29)

  `kind` is `"browser"` (Play opens the game's path) or `"download"` (a game you install). A
  download game's card points at a **page** (`page`, a CMS page's slug): its Play button opens
  `/pages/<slug>`, an ordinary page the admins edit in the page builder (what the game is, the
  download button, requirements). The default kind comes from the plugin's `game/0` (`kind:`),
  else `"browser"`; card.json may set `"kind"` and `"page"` too.

  ## Changing it from the admin

  Each plugin's admin section embeds `Bacon8Web.GameCardAdmin`. What an admin saves is a
  row in `game_cards` that overrides the folder field by field (a saved picture list
  replaces the folder's, so the folder's pictures can be removed too). Uploaded pictures
  live on the uploads volume under `public/game_cards/<slug>/`; files no saved card uses
  are deleted on the next save. "Reset" deletes the row and the uploads: the folder rules again.
  """

  import Ecto.Query

  alias Bacon8.GameCards.Card
  alias Bacon8.Repo

  @image_exts ~w(.webp .png .jpg .jpeg .avif)
  @max_fronts 8
  @default_seconds 5
  @fields ~w(fronts back tagline details play_label seconds kind page)
  @kinds ~w(browser download)
  @limits %{"tagline" => 140, "details" => 2000, "play_label" => 24}
  @topic "game_cards"

  @type t :: %{
          slug: String.t(),
          fronts: [String.t()],
          back: String.t() | nil,
          tagline: String.t() | nil,
          details: String.t() | nil,
          play_label: String.t(),
          seconds: pos_integer(),
          kind: String.t(),
          page: String.t() | nil,
          play_path: String.t() | nil,
          customized: boolean()
        }

  @doc "What a game can be: played in the browser, or downloaded."
  def kinds, do: @kinds

  def image_exts, do: @image_exts
  def max_fronts, do: @max_fronts

  @doc "PubSub topic: `{:game_card_changed, slug}` after a save or reset."
  def topic, do: @topic

  @doc "The cards of these plugins, keyed by plugin slug (one query)."
  @spec for_plugins([String.t()]) :: %{String.t() => t()}
  def for_plugins(slugs) do
    rows = Repo.all(from c in Card, where: c.plugin_slug in ^slugs) |> Map.new(&{&1.plugin_slug, &1.data})
    Map.new(slugs, &{&1, build(&1, Map.get(rows, &1))})
  end

  @doc "One plugin's card."
  @spec get(String.t()) :: t()
  def get(slug) do
    build(slug, case Repo.get(Card, slug) do
      nil -> nil
      card -> card.data
    end)
  end

  @doc "The card the plugin's folder gives, ignoring any saved changes."
  @spec defaults(String.t()) :: t()
  def defaults(slug), do: build(slug, nil)

  @doc "The folder's card with these saved fields (a `game_cards` row's data, or a draft) over it."
  @spec from_data(String.t(), map() | nil) :: t()
  def from_data(slug, saved), do: build(slug, saved)

  defp build(slug, saved) do
    base = folder(slug)
    data = if is_map(saved), do: Map.merge(base, Map.take(saved, @fields)), else: base

    kind = if data["kind"] in @kinds, do: data["kind"], else: default_kind(slug)
    page = if kind == "download", do: text(data["page"])

    %{
      slug: slug,
      kind: kind,
      page: page,
      # where Play goes when it isn't the game's own path: a download game's page
      play_path: page && "/pages/#{page}",
      fronts: data["fronts"] |> List.wrap() |> Enum.filter(&is_binary/1) |> Enum.take(@max_fronts),
      back: if(is_binary(data["back"]) and data["back"] != "", do: data["back"]),
      tagline: text(data["tagline"]),
      details: text(data["details"]),
      play_label: text(data["play_label"]) || "Play",
      seconds: seconds(data["seconds"]),
      customized: is_map(saved)
    }
  end

  defp default_kind(slug) do
    case Bacon8.Plugins.get(slug) do
      nil -> "browser"
      mod -> if match?(%{kind: "download"}, Bacon8.Plugins.game_info(mod)), do: "download", else: "browser"
    end
  end

  defp text(s) when is_binary(s) do
    case String.trim(s) do
      "" -> nil
      t -> t
    end
  end

  defp text(_), do: nil

  defp seconds(n) when is_integer(n), do: n |> max(2) |> min(60)

  defp seconds(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> seconds(n)
      :error -> @default_seconds
    end
  end

  defp seconds(_), do: @default_seconds

  # plugins/<slug>/priv/static/card/: the pictures by name, and card.json.
  defp folder(slug) do
    dir = card_dir(slug)
    files = case File.ls(dir) do
      {:ok, names} -> names
      _ -> []
    end

    url = fn name -> "/plugins/#{slug}/card/#{name}" end

    fronts =
      files
      |> Enum.filter(&(String.starts_with?(&1, "front") and image?(&1)))
      |> Enum.sort_by(&{number(&1), &1})
      |> Enum.map(url)

    back = Enum.find(files, &(Path.rootname(&1) == "back" and image?(&1)))
    json = read_json(Path.join(dir, "card.json"))

    %{
      "fronts" => fronts,
      "back" => back && url.(back),
      "tagline" => json["tagline"],
      "details" => json["details"],
      "play_label" => json["play_label"],
      "seconds" => json["seconds"],
      "kind" => json["kind"],
      "page" => json["page"]
    }
  end

  @doc "The plugin's card folder (`priv/static/card/`)."
  def card_dir(slug), do: Path.join([Bacon8.Plugins.priv_dir(slug), "static", "card"])

  defp image?(name), do: String.downcase(Path.extname(name)) in @image_exts

  defp number(name) do
    case Regex.run(~r/(\d+)/, name) do
      [_, n] -> String.to_integer(n)
      _ -> 0
    end
  end

  defp read_json(path) do
    with {:ok, body} <- File.read(path), {:ok, %{} = map} <- Jason.decode(body) do
      map
    else
      _ -> %{}
    end
  end

  # ---------------------------------------------------------------------------
  # Saving
  # ---------------------------------------------------------------------------

  @doc """
  Saves an admin's card for a plugin. `attrs` has string keys from #{inspect(@fields)}.
  Pictures must be the plugin's own (`/plugins/<slug>/card/...`) or uploaded for this
  card (`/uploads/public/game_cards/<slug>/...`).
  """
  @spec save(String.t(), map(), map() | nil) :: {:ok, t()} | {:error, String.t()}
  def save(slug, attrs, actor \\ nil) when is_binary(slug) and is_map(attrs) do
    with :ok <- known(slug),
         {:ok, data} <- validate(slug, attrs) do
      now = DateTime.utc_now()

      Repo.insert!(
        %Card{plugin_slug: slug, data: data, updated_by_id: actor_id(actor), inserted_at: now, updated_at: now},
        on_conflict: [set: [data: data, updated_by_id: actor_id(actor), updated_at: now]],
        conflict_target: :plugin_slug
      )

      prune_uploads(slug, [data["back"] | data["fronts"]])
      changed(slug)
      {:ok, get(slug)}
    end
  end

  @doc "Back to the plugin folder's card: deletes the saved row and this card's uploads."
  @spec reset(String.t()) :: {:ok, t()}
  def reset(slug) when is_binary(slug) do
    Repo.delete_all(from c in Card, where: c.plugin_slug == ^slug)
    prune_uploads(slug, [])
    changed(slug)
    {:ok, get(slug)}
  end

  defp changed(slug), do: Phoenix.PubSub.broadcast(Bacon8.PubSub, @topic, {:game_card_changed, slug})

  defp known(slug) do
    case Bacon8.Plugins.get(slug) do
      nil -> {:error, "No plugin #{slug} is installed."}
      _ -> :ok
    end
  end

  defp actor_id(%{id: id}), do: id
  defp actor_id(_), do: nil

  @doc false
  def validate(slug, attrs) do
    fronts = attrs |> Map.get("fronts", []) |> List.wrap()
    back = Map.get(attrs, "back")

    cond do
      length(fronts) > @max_fronts ->
        {:error, "A card can show up to #{@max_fronts} front pictures."}

      not Enum.all?(fronts, &own_picture?(slug, &1)) ->
        {:error, "A front picture isn't one of this card's."}

      back not in [nil, ""] and not own_picture?(slug, back) ->
        {:error, "The back picture isn't one of this card's."}

      attrs["kind"] not in [nil, "" | @kinds] ->
        {:error, "A game is played in the browser or downloaded."}

      attrs["kind"] == "download" and attrs["page"] not in [nil, ""] and is_nil(Bacon8.Content.get_page_by_slug(attrs["page"])) ->
        {:error, "That page doesn't exist."}

      too_long = Enum.find(@limits, fn {k, max} -> String.length(to_string(attrs[k] || "")) > max end) ->
        {key, max} = too_long
        {:error, "#{String.replace(key, "_", " ") |> String.capitalize()} is longer than #{max} characters."}

      true ->
        {:ok,
         %{
           "fronts" => fronts,
           "back" => if(back in [nil, ""], do: nil, else: back),
           "tagline" => to_string(attrs["tagline"] || ""),
           "details" => to_string(attrs["details"] || ""),
           "play_label" => to_string(attrs["play_label"] || ""),
           "seconds" => seconds(attrs["seconds"]),
           "kind" => if(attrs["kind"] in @kinds, do: attrs["kind"], else: nil),
           "page" => if(attrs["kind"] == "download", do: to_string(attrs["page"] || ""), else: "")
         }}
    end
  end

  defp own_picture?(slug, url) when is_binary(url) do
    folder = "/plugins/#{slug}/card/"
    uploads = "/uploads/public/game_cards/#{slug}/"

    cond do
      String.contains?(url, "..") -> false
      String.starts_with?(url, folder) -> image?(url) and File.regular?(Path.join(card_dir(slug), Path.basename(url)))
      String.starts_with?(url, uploads) -> image?(url) and File.regular?(Path.join(upload_dir(slug), Path.basename(url)))
      true -> false
    end
  end

  defp own_picture?(_, _), do: false

  # ---------------------------------------------------------------------------
  # Uploads
  # ---------------------------------------------------------------------------

  @doc "Where this card's uploaded pictures live (on the uploads volume)."
  def upload_dir(slug), do: Path.join([Bacon8.Uploads.public_dir(), "game_cards", slug])

  @doc """
  Keeps an uploaded picture for a plugin's card (a LiveView upload's temp file).
  Checks the file really is a WebP, PNG, JPEG or AVIF. Returns its URL; it is used
  once a save names it.
  """
  @spec store_upload(String.t(), Path.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def store_upload(slug, tmp_path, client_name) do
    ext = client_name |> Path.extname() |> String.downcase()

    with :ok <- known(slug),
         true <- ext in @image_exts || {:error, "Pictures must be #{Enum.join(@image_exts, ", ")}."},
         {:ok, head} <- read_head(tmp_path),
         true <- picture_bytes?(head) || {:error, "That file isn't a picture."} do
      dir = upload_dir(slug)
      File.mkdir_p!(dir)
      name = (:crypto.strong_rand_bytes(9) |> Base.url_encode64(padding: false)) <> ext
      File.cp!(tmp_path, Path.join(dir, name))
      {:ok, "/uploads/public/game_cards/#{slug}/#{name}"}
    end
  end

  defp read_head(path) do
    case File.open(path, [:read, :binary], &IO.binread(&1, 16)) do
      {:ok, head} when is_binary(head) -> {:ok, head}
      _ -> {:error, "The upload couldn't be read."}
    end
  end

  defp picture_bytes?(<<"RIFF", _::binary-size(4), "WEBP", _::binary>>), do: true
  defp picture_bytes?(<<0x89, "PNG", _::binary>>), do: true
  defp picture_bytes?(<<0xFF, 0xD8, 0xFF, _::binary>>), do: true
  defp picture_bytes?(<<_::binary-size(4), "ftypavi", _::binary>>), do: true
  defp picture_bytes?(_), do: false

  # Deletes this card's uploads that `keep` doesn't name.
  defp prune_uploads(slug, keep) do
    dir = upload_dir(slug)
    keep = keep |> Enum.filter(&is_binary/1) |> MapSet.new(&Path.basename/1)

    case File.ls(dir) do
      {:ok, names} -> for n <- names, not MapSet.member?(keep, n), do: File.rm(Path.join(dir, n))
      _ -> :ok
    end

    :ok
  end
end

defmodule Bacon8Web.GameCardAdmin do
  @moduledoc """
  The "Game card" section a plugin puts on its admin page (BACON8.md §9):

      <.live_component module={Bacon8Web.GameCardAdmin} id="game-card"
        plugin="bacon_world" current_user={@current_user} />

  A live preview of the card (hover it to turn it over) beside the editor: the front's
  pictures (add, reorder, remove), the back's picture, the tagline, the details, the
  Play button's label and how long each picture shows, and (2026-10-29) whether the game is played
  in the browser or downloaded, and a download game's page (Play opens it). Save writes `Bacon8.GameCards`;
  "Reset" goes back to the plugin folder's card (`priv/static/card/`). Pictures upload
  as soon as they're picked but count only once saved.
  """
  use Bacon8Web, :live_component

  alias Bacon8.GameCards
  alias Bacon8Web.Components.GameCard

  @accept ~w(.webp .png .jpg .jpeg .avif)
  @max_bytes 10_000_000

  @impl true
  def update(%{plugin: slug} = assigns, socket) do
    socket = assign(socket, assigns)

    if socket.assigns[:draft] do
      {:ok, socket}
    else
      game =
        case Bacon8.Plugins.get(slug) do
          nil -> nil
          mod -> Bacon8.Plugins.game_info(mod)
        end

      card = GameCards.get(slug)

      {:ok,
       socket
       |> assign(game: game, saved: card, draft: draft_of(card), dirty: false, status: nil, error: nil, pages: page_choices())
       |> allow_upload(:fronts,
         accept: @accept,
         max_entries: GameCards.max_fronts(),
         max_file_size: @max_bytes,
         auto_upload: true,
         progress: &handle_progress/3
       )
       |> allow_upload(:back,
         accept: @accept,
         max_entries: 1,
         max_file_size: @max_bytes,
         auto_upload: true,
         progress: &handle_progress/3
       )}
    end
  end

  defp draft_of(card) do
    %{
      "fronts" => card.fronts,
      "back" => card.back,
      "tagline" => card.tagline || "",
      "details" => card.details || "",
      "play_label" => card.play_label,
      "seconds" => card.seconds,
      "kind" => card.kind,
      "page" => card.page || ""
    }
  end

  # The pages a download game's card can point at: title and slug, drafts marked.
  defp page_choices do
    Bacon8.Content.list_pages()
    |> Enum.sort_by(&String.downcase(&1.title || ""))
    |> Enum.map(&{"#{&1.title}#{if &1.is_published, do: "", else: " (draft)"} · /pages/#{&1.slug}", &1.slug})
  end

  # A picture finished uploading: keep it (GameCards checks it) and put it in the draft.
  defp handle_progress(name, entry, socket) do
    if entry.done? do
      slug = socket.assigns.plugin

      result =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          {:ok, GameCards.store_upload(slug, path, entry.client_name)}
        end)

      case result do
        {:ok, url} ->
          draft = socket.assigns.draft

          draft =
            case name do
              :back -> Map.put(draft, "back", url)
              :fronts -> Map.update!(draft, "fronts", &Enum.take(&1 ++ [url], GameCards.max_fronts()))
            end

          {:noreply, assign(socket, draft: draft, dirty: true, error: nil, status: nil)}

        {:error, reason} ->
          {:noreply, assign(socket, error: reason)}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("draft", %{"card" => params}, socket) do
    draft = Map.merge(socket.assigns.draft, Map.take(params, ~w(tagline details play_label seconds kind page)))
    {:noreply, assign(socket, draft: draft, dirty: true, status: nil)}
  end

  def handle_event("draft", _params, socket), do: {:noreply, socket}

  def handle_event("move", %{"i" => i, "by" => by}, socket) do
    fronts = socket.assigns.draft["fronts"]
    i = String.to_integer(i)
    j = i + String.to_integer(by)

    fronts =
      if j >= 0 and j < length(fronts) do
        a = Enum.at(fronts, i)
        b = Enum.at(fronts, j)
        fronts |> List.replace_at(i, b) |> List.replace_at(j, a)
      else
        fronts
      end

    {:noreply, put_draft(socket, "fronts", fronts)}
  end

  def handle_event("remove_front", %{"i" => i}, socket) do
    {:noreply, put_draft(socket, "fronts", List.delete_at(socket.assigns.draft["fronts"], String.to_integer(i)))}
  end

  def handle_event("clear_back", _params, socket), do: {:noreply, put_draft(socket, "back", nil)}

  def handle_event("cancel_upload", %{"ref" => ref, "name" => name}, socket) do
    {:noreply, cancel_upload(socket, String.to_existing_atom(name), ref)}
  end

  def handle_event("save", _params, socket) do
    case GameCards.save(socket.assigns.plugin, socket.assigns.draft, socket.assigns[:current_user]) do
      {:ok, card} ->
        {:noreply, assign(socket, saved: card, draft: draft_of(card), dirty: false, status: "Saved. /games shows it now.", error: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, error: reason, status: nil)}
    end
  end

  def handle_event("revert", _params, socket) do
    {:noreply, assign(socket, draft: draft_of(socket.assigns.saved), dirty: false, status: nil, error: nil)}
  end

  def handle_event("reset", _params, socket) do
    {:ok, card} = GameCards.reset(socket.assigns.plugin)
    {:noreply, assign(socket, saved: card, draft: draft_of(card), dirty: false, status: "Back to the plugin's own card.", error: nil)}
  end

  defp put_draft(socket, key, value),
    do: assign(socket, draft: Map.put(socket.assigns.draft, key, value), dirty: true, status: nil)

  @impl true
  def render(%{game: nil} = assigns) do
    ~H"""
    <section id={@id} class="rounded-lg border border-gray-700 bg-gray-900/60 p-6 text-gray-400">
      This plugin has no game, so it has no card on /games.
    </section>
    """
  end

  def render(assigns) do
    assigns = assign(assigns, :preview, GameCards.from_data(assigns.plugin, assigns.draft))

    ~H"""
    <section id={@id} class="rounded-lg border border-gray-700 bg-gray-900/60 p-6">
      <div class="flex flex-wrap items-baseline justify-between gap-2 mb-5">
        <div>
          <h2 class="text-xl font-semibold text-white">Game card</h2>
          <p class="text-sm text-gray-400">
            {@game.name}'s card on <a href="/games" target="_blank" class="text-blue-400 hover:underline">/games</a>.
            Hover the preview to turn it over.
            <%= if @saved.customized do %>
              Changed here (the plugin's own card is in <code class="text-gray-300">priv/static/card/</code>).
            <% else %>
              This is the plugin's own card, from <code class="text-gray-300">priv/static/card/</code>.
            <% end %>
          </p>
        </div>
        <span :if={@dirty} class="text-sm text-amber-400">Unsaved changes</span>
      </div>

      <div class="flex flex-col lg:flex-row gap-8">
        <div class="w-full max-w-[300px] mx-auto lg:mx-0 flex-none">
          <GameCard.game_card id={"gc-preview-#{@plugin}"} game={@game} card={@preview} preview />
        </div>

        <form
          id={"#{@id}-form"}
          phx-change="draft"
          phx-submit="save"
          phx-target={@myself}
          class="flex-1 min-w-0 space-y-6"
        >
          <div>
            <div class="flex items-center justify-between mb-2">
              <h3 class="text-sm font-semibold text-gray-200">
                Front pictures <span class="font-normal text-gray-500">(shown in turn; up to {GameCards.max_fronts()})</span>
              </h3>
              <label
                :if={length(@draft["fronts"]) < GameCards.max_fronts()}
                for={@uploads.fronts.ref}
                class="cursor-pointer bg-gray-700 hover:bg-gray-600 text-white px-3 py-1.5 rounded-md text-sm"
              >
                Add pictures
              </label>
            </div>
            <.live_file_input upload={@uploads.fronts} class="hidden" />
            <div class="flex flex-wrap gap-3">
              <div
                :for={{src, i} <- Enum.with_index(@draft["fronts"])}
                class="relative w-24 rounded-md overflow-hidden border border-gray-600 bg-black"
              >
                <img src={src} class="w-24 h-32 object-cover" alt="" />
                <span class="absolute top-1 left-1 text-[10px] bg-black/70 text-white rounded px-1">{i + 1}</span>
                <div class="absolute bottom-0 inset-x-0 flex justify-between bg-black/70 text-white text-xs">
                  <button type="button" phx-click="move" phx-value-i={i} phx-value-by="-1" phx-target={@myself} class="px-2 py-1 hover:bg-white/20" title="Earlier">◀</button>
                  <button type="button" phx-click="remove_front" phx-value-i={i} phx-target={@myself} class="px-2 py-1 hover:bg-red-600" title="Remove">✕</button>
                  <button type="button" phx-click="move" phx-value-i={i} phx-value-by="1" phx-target={@myself} class="px-2 py-1 hover:bg-white/20" title="Later">▶</button>
                </div>
              </div>
              <.upload_tiles upload={@uploads.fronts} myself={@myself} name="fronts" />
              <p :if={@draft["fronts"] == [] and @uploads.fronts.entries == []} class="text-sm text-gray-500">
                No pictures: the card shows the game's icon.
              </p>
            </div>
          </div>

          <div>
            <div class="flex items-center justify-between mb-2">
              <h3 class="text-sm font-semibold text-gray-200">
                Back picture <span class="font-normal text-gray-500">(without one, the first front, blurred)</span>
              </h3>
              <div class="flex gap-2">
                <label for={@uploads.back.ref} class="cursor-pointer bg-gray-700 hover:bg-gray-600 text-white px-3 py-1.5 rounded-md text-sm">
                  {if @draft["back"], do: "Replace", else: "Choose"}
                </label>
                <button
                  :if={@draft["back"]}
                  type="button"
                  phx-click="clear_back"
                  phx-target={@myself}
                  class="bg-gray-700 hover:bg-gray-600 text-white px-3 py-1.5 rounded-md text-sm"
                >
                  Remove
                </button>
              </div>
            </div>
            <.live_file_input upload={@uploads.back} class="hidden" />
            <div class="flex flex-wrap gap-3">
              <img :if={@draft["back"]} src={@draft["back"]} class="w-24 h-32 object-cover rounded-md border border-gray-600" alt="" />
              <.upload_tiles upload={@uploads.back} myself={@myself} name="back" />
            </div>
          </div>

          <div class="grid sm:grid-cols-2 gap-4">
            <label class="block sm:col-span-2">
              <span class="text-sm font-semibold text-gray-200">Tagline</span>
              <span class="text-xs text-gray-500">(front, under the name; empty: the game's description)</span>
              <input
                type="text"
                name="card[tagline]"
                value={@draft["tagline"]}
                maxlength="140"
                placeholder={@game.description}
                class="mt-1 w-full rounded-md bg-gray-800 border-gray-600 text-white text-sm"
              />
            </label>
            <label class="block sm:col-span-2">
              <span class="text-sm font-semibold text-gray-200">Details</span>
              <span class="text-xs text-gray-500">(the back; a blank line starts a new paragraph)</span>
              <textarea
                name="card[details]"
                rows="6"
                maxlength="2000"
                class="mt-1 w-full rounded-md bg-gray-800 border-gray-600 text-white text-sm"
              >{@draft["details"]}</textarea>
            </label>
            <label class="block">
              <span class="text-sm font-semibold text-gray-200">How it's played</span>
              <select name="card[kind]" class="mt-1 w-full rounded-md bg-gray-800 border-gray-600 text-white text-sm">
                <option value="browser" selected={@draft["kind"] != "download"}>In the browser</option>
                <option value="download" selected={@draft["kind"] == "download"}>Download</option>
              </select>
            </label>
            <label :if={@draft["kind"] == "download"} class="block">
              <span class="text-sm font-semibold text-gray-200">The game's page</span>
              <span class="text-xs text-gray-500">(Play opens it)</span>
              <select name="card[page]" class="mt-1 w-full rounded-md bg-gray-800 border-gray-600 text-white text-sm">
                <option value="">No page: Play opens the game's own path</option>
                <option :for={{label, slug} <- @pages} value={slug} selected={@draft["page"] == slug}>{label}</option>
              </select>
              <span class="mt-1 block text-xs">
                <a :if={@draft["page"] not in [nil, ""]} href={"/pages/#{@draft["page"]}?edit=1"} target="_blank" class="text-blue-400 hover:underline">Edit this page</a>
                <span :if={@draft["page"] not in [nil, ""]} class="text-gray-600"> · </span>
                <a href="/admin/pages" target="_blank" class="text-blue-400 hover:underline">All pages</a>
              </span>
            </label>
            <label class="block">
              <span class="text-sm font-semibold text-gray-200">Play button</span>
              <input
                type="text"
                name="card[play_label]"
                value={@draft["play_label"]}
                maxlength="24"
                class="mt-1 w-full rounded-md bg-gray-800 border-gray-600 text-white text-sm"
              />
            </label>
            <label class="block">
              <span class="text-sm font-semibold text-gray-200">Seconds per picture</span>
              <input
                type="number"
                name="card[seconds]"
                value={@draft["seconds"]}
                min="2"
                max="60"
                class="mt-1 w-full rounded-md bg-gray-800 border-gray-600 text-white text-sm"
              />
            </label>
          </div>

          <p :if={@error} class="text-sm text-red-400">{@error}</p>
          <p :if={@status} class="text-sm text-green-400">{@status}</p>

          <div class="flex flex-wrap gap-2">
            <button type="submit" class="bg-blue-600 hover:bg-blue-500 text-white px-4 py-2 rounded-md text-sm font-medium">
              Save
            </button>
            <button
              :if={@dirty}
              type="button"
              phx-click="revert"
              phx-target={@myself}
              class="bg-gray-700 hover:bg-gray-600 text-white px-4 py-2 rounded-md text-sm font-medium"
            >
              Undo changes
            </button>
            <button
              :if={@saved.customized}
              type="button"
              phx-click="reset"
              phx-target={@myself}
              data-confirm="Go back to the plugin's own card? Pictures uploaded here are deleted."
              class="bg-red-900 hover:bg-red-800 text-white px-4 py-2 rounded-md text-sm font-medium"
            >
              Reset to the plugin's card
            </button>
          </div>
        </form>
      </div>
    </section>
    """
  end

  attr :upload, :any, required: true
  attr :myself, :any, required: true
  attr :name, :string, required: true

  defp upload_tiles(assigns) do
    ~H"""
    <div
      :for={entry <- @upload.entries}
      class="relative w-24 h-32 rounded-md border border-dashed border-gray-500 bg-gray-800 flex flex-col items-center justify-center text-xs text-gray-300 p-1"
    >
      <span class="truncate w-full text-center">{entry.client_name}</span>
      <span>{entry.progress}%</span>
      <span :for={err <- upload_errors(@upload, entry)} class="text-red-400 text-center">{upload_error(err)}</span>
      <button
        type="button"
        phx-click="cancel_upload"
        phx-value-ref={entry.ref}
        phx-value-name={@name}
        phx-target={@myself}
        class="absolute top-0 right-1 text-gray-400 hover:text-white"
      >
        ✕
      </button>
    </div>
    <p :for={err <- upload_errors(@upload)} class="text-sm text-red-400">{upload_error(err)}</p>
    """
  end

  defp upload_error(:too_large), do: "Larger than 10 MB."
  defp upload_error(:not_accepted), do: "Not a WebP, PNG, JPEG or AVIF."
  defp upload_error(:too_many_files), do: "Too many pictures."
  defp upload_error(other), do: to_string(other)
end

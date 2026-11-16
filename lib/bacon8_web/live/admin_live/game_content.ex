defmodule Bacon8Web.AdminLive.GameContent do
  @moduledoc """
  /admin/content - every game's definitions (2026-11-15; `Bacon8.GameContent`): pick a game, a kind
  (zone, camp, monster, loot table, item...) and a definition, and change its data. What is saved
  is live at once: game clients and servers pick it up by the kind's revision. Every change is
  listed under History and can be undone, a deletion too.

  This is the hub's own editor: plain, and the same for every game. A definition's data is shown
  and edited as JSON; a game that wants forms, pickers and previews builds them on the same
  service (Bacon World's Studio is the example, and edits its own rows there: here they are read-only).
  Admins only (the API lets GMs change definitions too).
  """
  use Bacon8Web, :live_view

  alias Bacon8.{GameContent, Games}
  alias Bacon8Web.Components.AdminSidebar

  on_mount {Bacon8Web.UserAuth, :require_admin_user}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Admin - Game content", games: games(), game: nil, kind: nil, kinds: [], rows: [], id: nil, text: "", error: nil, saved: nil, history: [], query: "", new_kind: "")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    game = params["game"]
    kind = params["kind"]
    game = if game && Enum.any?(socket.assigns.games, &(&1.slug == game)), do: game

    {:noreply,
     socket
     |> assign(game: game, kind: game && kind, id: nil, text: "", error: nil, saved: nil, query: "")
     |> load()}
  end

  defp games do
    Games.list_games() |> Enum.filter(& &1.is_active) |> Enum.sort_by(& &1.name) |> Enum.map(&%{slug: &1.slug, name: &1.name})
  end

  defp load(%{assigns: %{game: nil}} = socket), do: assign(socket, kinds: [], rows: [], history: [])

  defp load(%{assigns: %{game: game, kind: kind}} = socket) do
    assign(socket,
      kinds: GameContent.kinds(game),
      rows: if(kind, do: GameContent.list(game, kind), else: []),
      history: GameContent.history(game, kind: kind, limit: 30)
    )
  end

  defp pretty(data), do: Jason.encode!(data, pretty: true)

  @impl true
  def handle_event("open", %{"id" => id}, %{assigns: %{game: game, kind: kind}} = socket) when is_binary(kind) do
    case GameContent.get(game, kind, id) do
      nil -> {:noreply, socket}
      data -> {:noreply, assign(socket, id: id, text: pretty(data), error: nil, saved: nil)}
    end
  end

  def handle_event("new", _params, socket), do: {:noreply, assign(socket, id: "", text: "{\n}", error: nil, saved: nil)}

  def handle_event("filter", %{"query" => query}, socket), do: {:noreply, assign(socket, query: String.trim(query))}

  def handle_event("new_kind", %{"kind" => kind}, %{assigns: %{game: game}} = socket) when is_binary(game) do
    kind = kind |> String.trim() |> String.downcase()
    if kind == "", do: {:noreply, socket}, else: {:noreply, push_patch(socket, to: "/admin/content/#{game}/#{URI.encode(kind)}")}
  end

  def handle_event("save", %{"def_id" => id, "data" => text}, %{assigns: %{game: game, kind: kind, current_user: user}} = socket) when is_binary(kind) do
    id = String.trim(id)

    with {:ok, data} <- decode(text), {:ok, _} <- GameContent.put(game, kind, id, data, user) do
      {:noreply, socket |> assign(id: id, text: pretty(data), error: nil, saved: "Saved #{id}.") |> load()}
    else
      {:error, message} -> {:noreply, assign(socket, id: id, text: text, error: message, saved: nil)}
    end
  end

  def handle_event("delete", %{"id" => id}, %{assigns: %{game: game, kind: kind, current_user: user}} = socket) when is_binary(kind) do
    case GameContent.delete(game, kind, id, user) do
      :ok -> {:noreply, socket |> assign(id: nil, text: "", error: nil, saved: "Deleted #{id}. (History can bring it back.)") |> load()}
      {:error, message} -> {:noreply, assign(socket, error: message)}
    end
  end

  def handle_event("undo", %{"change" => change}, %{assigns: %{game: game, current_user: user}} = socket) when is_binary(game) do
    case GameContent.undo(game, String.to_integer(change), user) do
      {:ok, _} -> {:noreply, socket |> assign(id: nil, text: "", error: nil, saved: "Put back.") |> load()}
      {:error, message} -> {:noreply, assign(socket, error: message)}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp decode(text) do
    case Jason.decode(text) do
      {:ok, %{} = data} -> {:ok, data}
      {:ok, _} -> {:error, "A definition's data is an object: { ... }"}
      {:error, %Jason.DecodeError{} = e} -> {:error, "That isn't JSON: " <> Exception.message(e)}
    end
  end

  defp shown(rows, ""), do: rows
  defp shown(rows, query) do
    q = String.downcase(query)
    Enum.filter(rows, fn r -> String.contains?(String.downcase(r.id), q) or String.contains?(String.downcase(to_string(r.data["name"])), q) end)
  end

  defp summary(%{} = data) do
    [data["name"], data["zone"] && "zone #{data["zone"]}"] |> Enum.reject(&is_nil/1) |> Enum.join(" · ")
  end

  defp change_line(h) do
    case h.action do
      "create" -> "created"
      "delete" -> "deleted"
      _ -> "changed"
    end
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, read_only: assigns.game != nil and GameContent.read_only?(assigns.game))

    ~H"""
    <AdminSidebar.admin_layout current_path="/admin/content">
      <div class="max-w-7xl mx-auto">
        <div class="dark-glass p-4 sm:p-8 rounded-xl">
          <h1 class="text-3xl font-bold text-white">Game content</h1>
          <p class="text-gray-400 mt-1 mb-6">
            Each game's zones, camps, creature types, loot tables and items, kept on the hub. A change is live at once and can be undone.
          </p>

          <div class="flex flex-wrap gap-2 mb-6" id="content-games">
            <.link :for={g <- @games} patch={"/admin/content/#{g.slug}"}
              class={["px-3 py-1.5 rounded-lg text-sm", if(g.slug == @game, do: "bg-cyan-600 text-white", else: "bg-gray-800 text-gray-300 hover:bg-gray-700")]}>
              {g.name}
            </.link>
            <span :if={@games == []} class="text-gray-500 text-sm">No game is switched on yet (Plugins).</span>
          </div>

          <div :if={@game} class="grid gap-6 lg:grid-cols-[14rem_18rem_1fr]">
            <div>
              <h2 class="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-2">Kinds</h2>
              <ul id="content-kinds" class="space-y-1">
                <li :for={k <- @kinds}>
                  <.link patch={"/admin/content/#{@game}/#{k.kind}"}
                    class={["flex justify-between px-3 py-1.5 rounded text-sm", if(k.kind == @kind, do: "bg-gray-700 text-white", else: "text-gray-300 hover:bg-gray-800")]}>
                    <span>{k.kind}</span><span class="text-gray-500">{k.count}</span>
                  </.link>
                </li>
              </ul>
              <p :if={@kinds == []} class="text-gray-500 text-sm">Nothing yet.</p>
              <form :if={!@read_only} phx-submit="new_kind" class="mt-3 flex gap-2">
                <input type="text" name="kind" value={@new_kind} placeholder="new kind" class="w-full bg-gray-800 border border-gray-600 text-white rounded px-2 py-1 text-sm" />
                <button type="submit" class="px-2 py-1 rounded bg-gray-700 hover:bg-gray-600 text-white text-sm">+</button>
              </form>
              <p :if={@read_only} class="mt-3 text-xs text-amber-300">
                This game's definitions are edited in its own Studio. They are shown here to read.
              </p>
            </div>

            <div :if={@kind}>
              <div class="flex items-center justify-between mb-2">
                <h2 class="text-xs font-semibold text-gray-500 uppercase tracking-wide">{@kind}</h2>
                <button :if={!@read_only} type="button" phx-click="new" class="px-2 py-1 rounded bg-cyan-700 hover:bg-cyan-600 text-white text-xs">+ New</button>
              </div>
              <form phx-change="filter" phx-submit="filter" class="mb-2">
                <input type="search" name="query" value={@query} placeholder="Find by id or name" phx-debounce="200"
                  class="w-full bg-gray-800 border border-gray-600 text-white rounded px-2 py-1 text-sm" />
              </form>
              <ul id="content-rows" class="max-h-[32rem] overflow-y-auto divide-y divide-gray-800 rounded border border-gray-800">
                <li :for={r <- shown(@rows, @query)}>
                  <button type="button" phx-click="open" phx-value-id={r.id}
                    class={["w-full text-left px-3 py-2 text-sm", if(r.id == @id, do: "bg-gray-700 text-white", else: "text-gray-200 hover:bg-gray-800")]}>
                    <span class="block font-mono text-xs text-cyan-300 break-all">{r.id}</span>
                    <span class="block text-gray-400 text-xs">{summary(r.data)}</span>
                  </button>
                </li>
              </ul>
              <p :if={@rows == []} class="px-3 py-6 text-center text-gray-500 text-sm">No {@kind} yet.</p>
            </div>

            <div :if={@kind}>
              <p :if={@saved} id="content-saved" class="mb-3 rounded bg-emerald-900/40 border border-emerald-700 px-3 py-2 text-sm text-emerald-200">{@saved}</p>
              <p :if={@error} id="content-error" class="mb-3 rounded bg-red-900/40 border border-red-700 px-3 py-2 text-sm text-red-200">{@error}</p>

              <form :if={@id != nil} id="content-editor" phx-submit="save" class="mb-8">
                <label class="block text-xs text-gray-400 mb-1">Id</label>
                <input type="text" name="def_id" value={@id} readonly={@read_only} placeholder="letters, digits and _ . : -"
                  class="w-full bg-gray-800 border border-gray-600 text-white rounded px-2 py-1 text-sm font-mono mb-3" />
                <label class="block text-xs text-gray-400 mb-1">Data (JSON)</label>
                <textarea name="data" rows="22" spellcheck="false" readonly={@read_only}
                  class="w-full bg-gray-900 border border-gray-600 text-gray-100 rounded px-3 py-2 text-xs font-mono">{@text}</textarea>
                <div :if={!@read_only} class="mt-3 flex gap-2">
                  <button type="submit" class="px-4 py-2 rounded-lg bg-cyan-600 hover:bg-cyan-500 text-white text-sm">Save</button>
                  <button :if={@id != ""} type="button" phx-click="delete" phx-value-id={@id} data-confirm={"Delete #{@id}?"} data-confirm-tone="danger"
                    class="px-4 py-2 rounded-lg bg-red-800 hover:bg-red-700 text-white text-sm">Delete</button>
                </div>
              </form>
              <p :if={@id == nil} class="mb-8 text-gray-500 text-sm">Pick a definition to see it{if !@read_only, do: ", or make a new one"}.</p>

              <h2 class="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-2">History</h2>
              <ul id="content-history" class="divide-y divide-gray-800 rounded border border-gray-800">
                <li :for={h <- @history} class="flex flex-wrap items-baseline gap-x-3 gap-y-1 px-3 py-2 text-sm">
                  <span class="text-gray-500 whitespace-nowrap">{Calendar.strftime(h.inserted_at, "%Y-%m-%d %H:%M")} UTC</span>
                  <span class="text-gray-200">{h.user_name || "system"} {change_line(h)}</span>
                  <code class="rounded bg-gray-800 px-2 py-0.5 text-xs text-cyan-300 break-all">{h.kind} {h.ref_id}</code>
                  <button :if={!@read_only} type="button" phx-click="undo" phx-value-change={h.id}
                    class="ml-auto px-2 py-0.5 rounded bg-gray-700 hover:bg-gray-600 text-white text-xs">Undo</button>
                </li>
              </ul>
              <p :if={@history == []} class="px-3 py-6 text-center text-gray-500 text-sm">No changes yet.</p>
            </div>
          </div>
        </div>
      </div>
    </AdminSidebar.admin_layout>
    """
  end
end

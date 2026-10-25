defmodule BaconWorldWeb.Admin.SkillTreeLive do
  @moduledoc """
  /admin/bacon_world/skills - the skill tree editor (`BaconWorld.SkillTree`).

  The editor itself is the `BaconWorldSkillTreeEditor` hook (`skill-tree-editor.ts`):
  the tree on a canvas you can pan and zoom, the abilities (`BaconWorld.Abilities`:
  spells, skills, buffs) in a palette to drag onto nodes, and tools to add, move, join
  and delete nodes. It sends the whole tree on Save; this page validates and stores
  it. Players see a saved tree within seconds; nodes taken away hand their points
  back.
  """
  use Bacon8Web, :live_view

  alias BaconWorld.{Abilities, SkillTree}
  alias Bacon8Web.Components.AdminSidebar

  on_mount {Bacon8Web.UserAuth, :require_admin_user}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Admin - Bacon World skill tree",
       tree_json: Jason.encode!(SkillTree.current()),
       catalog_json: Jason.encode!(Abilities.payload()),
       default_json: Jason.encode!(SkillTree.default())
     )}
  end

  @impl true
  def handle_event("save", %{"tree" => tree}, socket) do
    case SkillTree.save(tree, socket.assigns.current_user.id) do
      {:ok, clean} ->
        {:reply, %{ok: true, tree: clean}, put_flash(socket, :info, "Saved: #{length(clean["nodes"])} nodes. Players see it within a few seconds.")}

      {:error, msg} ->
        {:reply, %{ok: false, error: msg}, put_flash(socket, :error, "Not saved: #{msg}")}
    end
  end

  def handle_event("reset", _params, socket) do
    {:ok, tree} = SkillTree.reset()
    {:reply, %{ok: true, tree: tree}, put_flash(socket, :info, "The shipped tree is back.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AdminSidebar.admin_layout current_path="/admin/bacon_world/skills">
      <div class="max-w-7xl mx-auto space-y-4">
        <div class="dark-glass p-6 rounded-xl">
          <h1 class="text-2xl font-bold text-white">Bacon World: skill tree</h1>
          <p class="mt-1 text-sm text-gray-400">
            Everyone starts in the middle with the start node and spends a point a level on a node joined to one they have.
            Drag an ability from the palette onto a node. Double-click empty space to add a node joined to the selected one;
            Shift-click two nodes to join or unjoin them; drag a node to move it (it snaps to the grid); Delete removes the selected node.
            Save when done.
          </p>
        </div>
        <div
          id="bw-skill-editor"
          phx-hook="BaconWorldSkillTreeEditor"
          phx-update="ignore"
          data-tree={@tree_json}
          data-catalog={@catalog_json}
          data-default={@default_json}
          class="dark-glass rounded-xl"
          style="height: 72vh; min-height: 520px; position: relative; overflow: hidden;"
        >
        </div>
      </div>
    </AdminSidebar.admin_layout>
    """
  end
end

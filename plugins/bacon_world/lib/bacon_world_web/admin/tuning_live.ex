defmodule BaconWorldWeb.Admin.TuningLive do
  @moduledoc """
  /admin/bacon_world/tuning - live world & combat formula tuning (`BaconWorld.Tuning`).

  Exposes the melee, spell, Armour Class (AC) mitigation, and world/progression
  knobs with a live formula reference and sample damage calculator. Saved values
  persist in `bacon_world_skill_trees` under slug `"tuning"` and take effect
  immediately across the cluster.
  """
  use Bacon8Web, :live_view

  alias BaconWorld.Tuning
  alias Bacon8Web.Components.AdminSidebar

  on_mount {Bacon8Web.UserAuth, :require_admin_user}

  @groups [
    {"melee", "⚔️ Melee Combat", "Base weapon rolls, level scaling, critical hits, and heavy swings."},
    {"spells", "✨ Spell Combat", "Spell critical hit rate and critical damage multiplier."},
    {"armour", "🛡️ Armour & AC Mitigation", "Hyperbolic Armour Class reduction: AC / (AC + soft_cap), capped at max_mitigation."},
    {"world", "🌍 World & Progression", "Experience gain, creature health/damage multipliers, and out-of-combat regeneration."}
  ]

  @impl true
  def mount(_params, _session, socket) do
    values = Tuning.current()

    {:ok,
     assign(socket,
       page_title: "Admin - Bacon World tuning",
       groups: @groups,
       specs: Tuning.specs(),
       values: values,
       preview: sample_preview(values)
     )}
  end

  @impl true
  def handle_event("preview", %{"tuning" => raw}, socket) do
    merged = merge_preview(socket.assigns.values, raw)
    {:noreply, assign(socket, values: merged, preview: sample_preview(merged))}
  end

  def handle_event("save", %{"tuning" => raw}, socket) do
    {:ok, saved} = Tuning.save(raw, socket.assigns.current_user.id)

    {:noreply,
     socket
     |> assign(values: saved, preview: sample_preview(saved))
     |> put_flash(:info, "World tuning saved. Changes are live for all players and creatures.")}
  end

  def handle_event("reset", _params, socket) do
    {:ok, defaults} = Tuning.reset()

    {:noreply,
     socket
     |> assign(values: defaults, preview: sample_preview(defaults))
     |> put_flash(:info, "World tuning reset to shipped defaults.")}
  end

  defp merge_preview(current, raw) do
    Enum.reduce(Tuning.specs(), current, fn spec, acc ->
      case Map.get(raw, spec.key) do
        nil ->
          acc

        val ->
          case Float.parse(to_string(val)) do
            {f, _} -> Map.put(acc, spec.key, f)
            :error -> acc
          end
      end
    end)
  end

  defp sample_preview(v) do
    # Sample: Level 9 warrior with a 10 DMG weapon, +10% Might buff
    lvl = 9
    wpn = 10
    lvl_bonus = div(lvl, max(1, round(v["melee_level_div"] || 3)))
    base = wpn + lvl_bonus
    spread = v["melee_spread"] || 0.25
    heavy_mult = v["heavy_damage_mult"] || 1.5
    crit_mult = v["melee_crit_mult"] || 1.75
    min_normal = max(1, round(base * (1.0 - spread)))
    max_normal = max(1, round(base * (1.0 + spread)))
    max_heavy_crit = max(1, round(base * (1.0 + spread) * heavy_mult * crit_mult))

    soft_cap = max(1.0, (v["ac_soft_cap"] || 50.0) * 1.0)
    max_mit = v["ac_max_mitigation"] || 0.75

    ac_samples =
      for ac <- [5, 15, 30, 50, 100] do
        red = min(max_mit, ac / (ac + soft_cap))
        taken = max(1, round(20 * (1.0 - red)))
        {ac, Float.round(red * 100.0, 1), taken}
      end

    %{
      lvl: lvl,
      wpn: wpn,
      lvl_bonus: lvl_bonus,
      min_normal: min_normal,
      max_normal: max_normal,
      max_heavy_crit: max_heavy_crit,
      ac_samples: ac_samples
    }
  end

  defp format_val(val, step) when step >= 1, do: to_string(round(val * 1.0))
  defp format_val(val, _step), do: :erlang.float_to_binary(val * 1.0, [:compact, decimals: 3])

  @impl true
  def render(assigns) do
    ~H"""
    <AdminSidebar.admin_layout current_path="/admin/bacon_world/tuning">
      <div class="max-w-6xl mx-auto space-y-6">
        <div class="dark-glass p-6 rounded-xl flex flex-wrap items-center justify-between gap-4">
          <div>
            <h1 class="text-2xl font-bold text-white">Bacon World: World &amp; Combat Tuning</h1>
            <p class="mt-1 text-sm text-gray-400">
              Live combat formulas, Armour Class (AC) mitigation, regeneration, and progression multipliers.
            </p>
          </div>
          <div class="flex flex-wrap gap-2">
            <.link
              navigate="/admin/bacon_world"
              class="bg-gray-700 hover:bg-gray-600 text-white px-4 py-2 rounded-md text-sm font-medium"
            >
              ← Card &amp; Home
            </.link>
            <.link
              navigate="/admin/bacon_world/skills"
              class="bg-gray-700 hover:bg-gray-600 text-white px-4 py-2 rounded-md text-sm font-medium"
            >
              🌳 Skill tree
            </.link>
            <button
              type="button"
              phx-click="reset"
              data-confirm="Reset all world tuning parameters to their shipped defaults?"
              class="bg-amber-700/80 hover:bg-amber-600 text-white px-4 py-2 rounded-md text-sm font-medium"
            >
              ↺ Reset defaults
            </button>
            <a href="/games/bacon_world" class="bg-blue-600 hover:bg-blue-500 text-white px-4 py-2 rounded-md text-sm font-medium">
              ▶ Play
            </a>
          </div>
        </div>

        <div class="dark-glass p-6 rounded-xl space-y-4">
          <h2 class="text-lg font-semibold text-amber-300">📜 How Damage &amp; Armour Are Calculated</h2>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm text-gray-300">
            <div class="bg-gray-900/60 border border-gray-800 rounded-lg p-4 space-y-2">
              <div class="font-semibold text-white">Melee &amp; Weapon Skills</div>
              <p class="text-xs text-gray-400 leading-relaxed">
                <code>base = weapon_dmg + div(level, melee_level_div)</code><br />
                <code>roll = base × uniform(1 - spread, 1 + spread)</code><br />
                <code>damage = round(roll × heavy_mult × crit_mult × skill_mult × (1 + melee_pct / 100))</code>
              </p>
              <div class="text-xs text-amber-200/90 pt-1">
                Sample (Lvl <%= @preview.lvl %>, <%= @preview.wpn %> DMG weapon, +<%= @preview.lvl_bonus %> lvl bonus):
                normal swing <strong><%= @preview.min_normal %>–<%= @preview.max_normal %></strong>,
                heavy crit up to <strong><%= @preview.max_heavy_crit %></strong>.
              </div>
            </div>

            <div class="bg-gray-900/60 border border-gray-800 rounded-lg p-4 space-y-2">
              <div class="font-semibold text-white">Armour Class (AC) &amp; Absorb Shields</div>
              <p class="text-xs text-gray-400 leading-relaxed">
                <code>reduction = min(ac_max_mitigation, total_ac / (total_ac + ac_soft_cap))</code><br />
                <code>mitigated = max(1, round(raw_damage × (1 - reduction)))</code><br />
                Active absorb shields (<em>Ice Barrier</em>, <em>Divine Shield</em>, <em>Shield Wall</em>, etc.) add temporary AC and absorb remaining damage before HP is reduced.
              </p>
              <div class="flex flex-wrap gap-2 pt-1 text-xs">
                <%= for {ac, pct, taken} <- @preview.ac_samples do %>
                  <span class="bg-gray-800 px-2 py-1 rounded text-gray-200">
                    <strong><%= ac %> AC</strong>: -<%= pct %>% (<%= taken %> of 20)
                  </span>
                <% end %>
              </div>
            </div>
          </div>
        </div>

        <form phx-change="preview" phx-submit="save" class="space-y-6">
          <%= for {group_id, title, subtitle} <- @groups do %>
            <div class="dark-glass p-6 rounded-xl space-y-4">
              <div>
                <h2 class="text-lg font-semibold text-white"><%= title %></h2>
                <p class="text-xs text-gray-400"><%= subtitle %></p>
              </div>
              <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                <%= for spec <- Enum.filter(@specs, &(&1.group == group_id)) do %>
                  <div class="bg-gray-900/60 border border-gray-800 rounded-lg p-4 flex flex-col justify-between gap-2">
                    <div>
                      <div class="flex items-center justify-between gap-2">
                        <label for={"tuning-#{spec.key}"} class="text-sm font-medium text-white">
                          <%= spec.label %>
                        </label>
                        <span class="text-xs font-mono text-gray-500">
                          default: <%= format_val(spec.default, spec.step) %> <%= spec.unit %>
                        </span>
                      </div>
                      <p class="text-xs text-gray-400 mt-1"><%= spec.desc %></p>
                    </div>
                    <div class="flex items-center gap-2 mt-2">
                      <input
                        id={"tuning-#{spec.key}"}
                        type="number"
                        name={"tuning[#{spec.key}]"}
                        value={format_val(Map.get(@values, spec.key, spec.default), spec.step)}
                        min={spec.min}
                        max={spec.max}
                        step={spec.step}
                        class="w-full bg-gray-950 border border-gray-700 rounded px-3 py-1.5 text-sm text-white font-mono focus:border-amber-400 focus:outline-none"
                      />
                      <span class="text-xs text-gray-400 shrink-0"><%= spec.unit %></span>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>

          <div class="flex justify-end gap-3">
            <button
              type="submit"
              class="bg-amber-600 hover:bg-amber-500 text-white px-6 py-2.5 rounded-lg text-sm font-semibold shadow-lg"
            >
              💾 Save World Tuning
            </button>
          </div>
        </form>
      </div>
    </AdminSidebar.admin_layout>
    """
  end
end

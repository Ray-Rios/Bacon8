defmodule Bacon8.Repo.Migrations.RaysSpaceSimDownloadPage do
  use Ecto.Migration

  # RaysSpaceSim is a download game (2026-10-29): its card on /games now opens a CMS page the
  # admins edit in the page builder, picked on /admin/rays_space_sim ("The game's page";
  # Bacon8.GameCards `kind` and `page`). This creates that page, /pages/rays-space-sim
  # (published, so Play works for everyone; edit or unpublish it like any page), and points the
  # card at it. A page already at that slug is kept as it is and used; a card already saved
  # keeps everything else it has. `down` changes nothing: the page is content, not schema.

  @slug "rays-space-sim"

  def up do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    repo().insert_all(
      "pages",
      [
        %{
          id: Ecto.UUID.bingenerate(),
          title: "RaysSpaceSim",
          slug: @slug,
          content: Jason.encode!(content()),
          excerpt: "Download the RaysSpaceSim launcher for Windows: it installs the game, keeps it up to date and signs you in.",
          meta_description: "Download RaysSpaceSim for Windows.",
          template_type: "default",
          is_published: true,
          published_at: now,
          category: "games",
          order: 0,
          show_share_buttons: false,
          share_platforms: [],
          share_buttons_colored: false,
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: :nothing,
      conflict_target: [:slug]
    )

    data = Jason.encode!(%{"kind" => "download", "page" => @slug})

    execute("""
    INSERT INTO game_cards (plugin_slug, data, inserted_at, updated_at)
    VALUES ('rays_space_sim', '#{data}'::jsonb, NOW(), NOW())
    ON CONFLICT (plugin_slug) DO UPDATE SET data = game_cards.data || EXCLUDED.data, updated_at = NOW()
    """)
  end

  def down, do: :ok

  defp content do
    row = fn blocks, settings -> %{"columns" => [%{"width" => "full", "blocks" => blocks}], "settings" => settings} end

    %{
      "version" => 1,
      "rows" => [
        row.(
          [
            %{"type" => "heading", "content" => "Fly your own ship", "settings" => %{"level" => 2}},
            %{
              "type" => "text",
              "content" =>
                "<p>RaysSpaceSim is our space game for Windows. Fly, explore and build with other players, and open a Holo-sim: a world of your own that the members of one of your chat channels can join.</p>"
            },
            %{
              "type" => "button",
              "content" => "Download the launcher",
              "settings" => %{"url" => "/games/rays-space-sim/launcher", "style" => "primary", "align" => "left"}
            },
            %{"type" => "text", "content" => "<p><small>Windows 10 or 11. Sign in with your Bacon8 account.</small></p>"}
          ],
          %{"width" => "normal", "space" => "l"}
        ),
        row.(
          [
            %{"type" => "heading", "content" => "How it works", "settings" => %{"level" => 3}},
            %{
              "type" => "text",
              "content" =>
                "<ul><li>The launcher installs the game and keeps it up to date by itself.</li><li>It signs you in with the account you use here.</li><li>Holo-sims live in Chat: each one belongs to a channel, and that channel's members are who may join.</li></ul>"
            }
          ],
          %{"width" => "normal"}
        )
      ]
    }
  end
end

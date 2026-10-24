defmodule Bacon8.Repo.Migrations.CreditMakehuman do
  use Ecto.Migration

  # Bacon World's humans are now built on MakeHuman (the female 2026-10-22, the male
  # 2026-10-24), so the Credits page (/pages/credits) line for the old base bodies is
  # replaced. The page is content the owner edits: only a page that doesn't mention
  # MakeHuman yet is touched. The old "Base bodies" line is swapped where it still reads
  # as written; otherwise a short "Characters" row is appended instead.
  # `down` changes nothing.

  @old "<li>Base bodies: <em>Human Base Meshes</em> by Blender Studio (CC0).</li>"
  @new "<li>Bodies, skins, hair and clothes: <a href=\"https://www.makehumancommunity.org\">MakeHuman</a> and its community asset packs (CC0).</li>"
  @row_html """
  <h2>Characters</h2>
  <p>Bodies, skins, hair and clothes: <a href="https://www.makehumancommunity.org">MakeHuman</a> and its community asset packs (CC0).</p>
  """

  def up do
    # `content` is a text column holding the page builder's JSON (rows > columns > blocks).
    %{rows: rows} = repo().query!("SELECT id, content FROM pages WHERE slug = 'credits'")

    for [id, raw] <- rows, is_binary(raw), not String.contains?(raw, "MakeHuman"),
        {:ok, %{} = content} <- [Jason.decode(raw)] do
      swapped = swap(content)
      updated = if String.contains?(Jason.encode!(swapped), "MakeHuman"), do: swapped, else: append(content)

      repo().query!("UPDATE pages SET content = $2, updated_at = NOW() WHERE id = $1", [id, Jason.encode!(updated)])
    end
  end

  def down, do: :ok

  defp swap(%{"rows" => rows} = content) when is_list(rows),
    do: %{content | "rows" => Enum.map(rows, &swap_row/1)}

  defp swap(content), do: content

  defp swap_row(%{"columns" => cols} = row) when is_list(cols),
    do: %{row | "columns" => Enum.map(cols, &swap_col/1)}

  defp swap_row(row), do: row

  defp swap_col(%{"blocks" => blocks} = col) when is_list(blocks),
    do: %{col | "blocks" => Enum.map(blocks, &swap_block/1)}

  defp swap_col(col), do: col

  defp swap_block(%{"content" => html} = b) when is_binary(html),
    do: %{b | "content" => String.replace(html, @old, @new)}

  defp swap_block(b), do: b

  defp append(content) do
    row = %{"columns" => [%{"width" => "full", "blocks" => [%{"type" => "text", "content" => @row_html}]}]}
    Map.update(content, "rows", [row], fn r when is_list(r) -> r ++ [row]; _ -> [row] end)
  end
end

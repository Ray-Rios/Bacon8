defmodule Bacon8.Repo.Migrations.CreditCc0Textures do
  use Ecto.Migration

  # Adds a "Textures" section to the Credits page (/pages/credits) for the CC0 surface
  # textures Bacon World uses (ambientCG and Poly Haven). The owner asked for it
  # (2026-10-23). The page is content the owner edits, so this only appends a row
  # when the page exists and doesn't mention ambientCG yet; everything else on it is
  # left as it is. `down` changes nothing.

  @html """
  <h2>Textures</h2>
  <p>Surface textures: <a href="https://ambientcg.com">ambientCG</a> and <a href="https://polyhaven.com">Poly Haven</a>, CC0 1.0.</p>
  """

  def up do
    # `content` is a text column holding the page builder's JSON (rows > columns > blocks).
    %{rows: rows} = repo().query!("SELECT id, content FROM pages WHERE slug = 'credits'")

    # Only a page whose content is the builder's JSON is touched (never replaced wholesale).
    for [id, raw] <- rows, is_binary(raw), not String.contains?(raw, "ambientCG"),
        {:ok, %{} = content} <- [Jason.decode(raw)] do
      row = %{"columns" => [%{"width" => "full", "blocks" => [%{"type" => "text", "content" => @html}]}]}
      updated = Map.update(content, "rows", [row], fn r when is_list(r) -> r ++ [row]; _ -> [row] end)
      repo().query!("UPDATE pages SET content = $2, updated_at = NOW() WHERE id = $1", [id, Jason.encode!(updated)])
    end
  end

  def down, do: :ok
end

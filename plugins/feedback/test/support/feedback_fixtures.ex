defmodule Feedback.Fixtures do
  @moduledoc "Users, pictures and items for the Suggestions & Bugs tests."

  @png <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, "pretend pixels">>

  def png, do: @png

  def member(attrs \\ %{}), do: Bacon8.DataCase.user_fixture(attrs)
  def guest, do: member(%{role: "guest"})
  def admin, do: member(%{role: "admin", is_admin: true})

  def item(author, attrs \\ %{}, shots \\ []) do
    attrs =
      Map.merge(
        %{
          "kind" => "suggestion",
          "area" => "site",
          "title" => "Dark mode for the chat",
          "body" => "The chat is too bright at night."
        },
        Map.new(attrs)
      )

    {:ok, item} = Feedback.create_item(author, attrs, shots)
    item
  end

  @doc "An item moved along by an admin: \"approved\", \"queued\" (submitted to Claude)..."
  def item_at(status, author, admin) do
    i = item(author)

    path =
      case status do
        "open" -> []
        "approved" -> ["approve"]
        "queued" -> ["approve", "submit"]
      end

    Enum.reduce(path, i, fn action, acc ->
      {:ok, next} = Feedback.moderate(acc, admin, action)
      next
    end)
  end
end

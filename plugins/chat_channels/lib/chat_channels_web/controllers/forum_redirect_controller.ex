defmodule ChatChannelsWeb.ForumRedirectController do
  @moduledoc "Old /forum links answer 301 to the same place under /chat, keeping the query string."
  use Bacon8Web, :controller

  def index(conn, _params), do: moved(conn, "/chat")

  def channel(conn, %{"channel_id" => id}), do: moved(conn, "/chat/" <> URI.encode(id, &URI.char_unreserved?/1))

  defp moved(conn, to) do
    to = if conn.query_string == "", do: to, else: to <> "?" <> conn.query_string

    conn
    |> put_status(301)
    |> redirect(to: to)
  end
end

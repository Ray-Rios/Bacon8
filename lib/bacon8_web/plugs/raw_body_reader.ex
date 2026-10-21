defmodule Bacon8Web.RawBodyReader do
  @moduledoc """
  `Plug.Parsers` body reader that keeps the raw request body in
  `conn.private[:raw_body]` for the paths plugins ask for
  (`c:Bacon8.Plugin.raw_body_paths/0`), e.g. the store's payment webhooks.

  A provider like Stripe signs the exact bytes it sent; once the JSON parser
  has decoded them they can't be rebuilt, so the signature has to be checked
  against this copy. Other requests are read normally and nothing is kept.
  """

  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {status, body, conn} when status in [:ok, :more] ->
        conn =
          if keep_raw?(conn),
            do: Plug.Conn.put_private(conn, :raw_body, (conn.private[:raw_body] || "") <> body),
            else: conn

        {status, body, conn}

      other ->
        other
    end
  end

  defp keep_raw?(conn) do
    Enum.any?(Bacon8.Plugins.raw_body_paths(), &String.starts_with?(conn.request_path, &1))
  end
end

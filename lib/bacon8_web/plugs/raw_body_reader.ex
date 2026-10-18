defmodule Bacon8Web.RawBodyReader do
  @moduledoc """
  `Plug.Parsers` body reader that keeps the raw request body for payment
  webhooks (`/api/webhooks/payments/...`) in `conn.private[:raw_body]`.

  Stripe signs the exact bytes it sent; once the JSON parser has decoded them
  they can't be rebuilt, so the signature has to be checked against this copy.
  Other requests are read normally and nothing is kept.
  """

  @prefix "/api/webhooks/payments/"

  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {status, body, conn} when status in [:ok, :more] ->
        conn =
          if String.starts_with?(conn.request_path, @prefix),
            do: Plug.Conn.put_private(conn, :raw_body, (conn.private[:raw_body] || "") <> body),
            else: conn

        {status, body, conn}

      other ->
        other
    end
  end
end

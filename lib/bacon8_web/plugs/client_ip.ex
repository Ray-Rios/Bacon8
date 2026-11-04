defmodule Bacon8Web.ClientIP do
  @moduledoc """
  Who is really on the other end (2026-11-04, BACON8.md §6 invariant 19). Every request passes the
  endpoint's `plug Bacon8Web.ClientIP` first, which replaces `conn.remote_ip` with the visitor's
  address, so the blocker, the honeypot, rate limits, sign-in throttling and `/admin/security`
  all see the same, real one. LiveViews use `from_socket/1` (the socket has no plug).

  **A header is believed only from a proxy we run.** The TCP peer must be in `trusted` (private,
  loopback and link-local ranges by default: the ingress controller's pod). Then:

    1. `X-Real-IP`, which ingress-nginx always overwrites with the address it worked out (so a
       visitor can't send one of their own through it); else
    2. `X-Forwarded-For`, read from the right, skipping trusted hops: the first untrusted entry is
       the visitor (the left end is whatever the visitor wrote, and is never believed).

  Anything else, or anything that doesn't parse, leaves the peer address. Which address nginx puts
  in `X-Real-IP` is nginx's business: behind Cloudflare it takes it from `CF-Connecting-IP`, and
  only from the tunnel's pods (`k3s/cloudflared/README.md`).

      config :bacon8, Bacon8Web.ClientIP, trusted: ["10.0.0.0/8", "172.16.0.0/12", ...]
  """
  @behaviour Plug
  import Bitwise

  @default_trusted ~w(127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 ::1/128 fc00::/7 fe80::/10)

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts), do: %{conn | remote_ip: from_conn(conn)}

  @doc "The visitor's address as a tuple, from a conn's peer and its headers."
  def from_conn(%Plug.Conn{} = conn) do
    resolve(conn.remote_ip, first(Plug.Conn.get_req_header(conn, "x-real-ip")), first(Plug.Conn.get_req_header(conn, "x-forwarded-for")))
  end

  @doc "The visitor's address as text, for a LiveView (from `:peer_data` and `:x_headers`), or nil."
  def from_socket(socket) do
    peer =
      case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
        %{address: addr} -> addr
        _ -> nil
      end

    headers = Phoenix.LiveView.get_connect_info(socket, :x_headers) || []
    real = headers |> List.keyfind("x-real-ip", 0) |> header_value()
    fwd = headers |> List.keyfind("x-forwarded-for", 0) |> header_value()

    case peer do
      nil -> nil
      peer -> peer |> resolve(real, fwd) |> format()
    end
  end

  @doc "Text for an address tuple (`\"203.0.113.7\"`); text passes through."
  def format(ip) when is_tuple(ip), do: ip |> :inet.ntoa() |> to_string()
  def format(ip) when is_binary(ip), do: ip
  def format(_), do: "unknown"

  @doc false
  def resolve(peer, real_ip, forwarded_for) do
    if trusted?(peer) do
      with nil <- parse(real_ip),
           nil <- rightmost_untrusted(forwarded_for) do
        peer
      end
    else
      peer
    end
  end

  defp rightmost_untrusted(nil), do: nil

  defp rightmost_untrusted(list) do
    list
    |> String.split(",")
    |> Enum.map(&parse(String.trim(&1)))
    |> Enum.reverse()
    |> Enum.reduce_while(nil, fn
      nil, _ -> {:halt, nil}
      ip, _ -> if trusted?(ip), do: {:cont, nil}, else: {:halt, ip}
    end)
  end

  defp first([v | _]), do: v
  defp first(_), do: nil

  defp header_value({_k, v}), do: v
  defp header_value(_), do: nil

  defp parse(nil), do: nil

  defp parse(s) when is_binary(s) do
    case :inet.parse_strict_address(String.to_charlist(String.trim(s))) do
      {:ok, ip} -> ip
      _ -> nil
    end
  end

  @doc "True when `ip` is in one of the trusted ranges."
  def trusted?(ip) when is_tuple(ip) do
    Application.get_env(:bacon8, __MODULE__, [])
    |> Keyword.get(:trusted, @default_trusted)
    |> Enum.any?(&in_cidr?(ip, &1))
  end

  def trusted?(_), do: false

  @doc false
  def in_cidr?(ip, cidr) do
    [addr, bits] =
      case String.split(cidr, "/") do
        [a, b] -> [a, String.to_integer(b)]
        [a] -> [a, nil]
      end

    case :inet.parse_strict_address(String.to_charlist(addr)) do
      {:ok, net} when tuple_size(net) == tuple_size(ip) ->
        width = if tuple_size(ip) == 4, do: 32, else: 128
        bits = bits || width
        shift = width - bits
        (to_int(ip) >>> shift) == (to_int(net) >>> shift)

      _ ->
        false
    end
  end

  defp to_int({a, b, c, d}), do: (a <<< 24) + (b <<< 16) + (c <<< 8) + d
  defp to_int(t) when tuple_size(t) == 8, do: t |> Tuple.to_list() |> Enum.reduce(0, fn x, acc -> (acc <<< 16) + x end)
end

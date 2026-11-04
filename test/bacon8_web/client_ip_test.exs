defmodule Bacon8Web.ClientIPTest do
  # The visitor's real address (2026-11-04): headers are believed only from our own proxy.
  use ExUnit.Case, async: true
  import Plug.Test
  alias Bacon8Web.ClientIP

  defp at(peer, headers) do
    Enum.reduce(headers, %{conn(:get, "/") | remote_ip: peer}, fn {k, v}, c -> Plug.Conn.put_req_header(c, k, v) end)
  end

  @nginx {10, 1, 0, 23}

  test "from our ingress, X-Real-IP is the visitor" do
    assert ClientIP.call(at(@nginx, [{"x-real-ip", "203.0.113.7"}]), []).remote_ip == {203, 0, 113, 7}
  end

  test "X-Forwarded-For is read from the right: what the visitor wrote on the left is never believed" do
    conn = at(@nginx, [{"x-forwarded-for", "6.6.6.6, 198.51.100.9, 10.1.0.5"}])
    assert ClientIP.from_conn(conn) == {198, 51, 100, 9}
  end

  test "a visitor talking to us directly can't name anyone else" do
    conn = at({198, 51, 100, 9}, [{"x-real-ip", "1.2.3.4"}, {"x-forwarded-for", "1.2.3.4"}])
    assert ClientIP.from_conn(conn) == {198, 51, 100, 9}
  end

  test "rubbish headers leave the peer; IPv6 works" do
    assert ClientIP.from_conn(at(@nginx, [{"x-real-ip", "not an address"}])) == @nginx
    assert ClientIP.from_conn(at(@nginx, [{"x-real-ip", "2001:db8::1"}])) == {8193, 3512, 0, 0, 0, 0, 0, 1}
    assert ClientIP.format({203, 0, 113, 7}) == "203.0.113.7"
  end

  test "ranges" do
    assert ClientIP.in_cidr?({172, 20, 1, 1}, "172.16.0.0/12")
    refute ClientIP.in_cidr?({172, 32, 1, 1}, "172.16.0.0/12")
    assert ClientIP.trusted?({192, 168, 65, 3})
    refute ClientIP.trusted?({8, 8, 8, 8})
    assert ClientIP.in_cidr?({0, 0, 0, 0, 0, 0, 0, 1}, "::1/128")
  end
end

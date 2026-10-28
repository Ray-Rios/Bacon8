defmodule Bacon8.SecurityAddressesTest do
  # Behind Docker Desktop every visitor arrives from the node's own address (192.168.65.3). That
  # address names no one, so it is never blocked and never what sign-ins are throttled by.
  use Bacon8.DataCase, async: false
  import Plug.Test, only: [conn: 2]

  alias Bacon8.{Accounts, Security}

  @gateway "192.168.65.3"

  defp unique, do: System.unique_integer([:positive])

  describe "blockable_ip?/1" do
    test "public addresses can be blocked" do
      for ip <- ["203.0.113.9", "8.8.8.8", "172.32.0.1", "100.63.0.1", "2001:db8::1"], do: assert(Security.blockable_ip?(ip), ip)
    end

    test "private, loopback, link-local, gateway and non-addresses can't" do
      for ip <- [@gateway, "192.168.0.10", "10.1.2.3", "172.16.0.1", "172.31.255.255", "127.0.0.1", "169.254.1.1", "100.64.0.1", "0.0.0.0", "::1", "fd00::1", "fe80::1", "::ffff:192.168.65.3", "unknown", "", "not an ip"] do
        refute Security.blockable_ip?(ip), ip
      end

      refute Security.blockable_ip?(nil)
    end
  end

  test "throttle_key is the address when it names a visitor, else the account (any case)" do
    assert Security.throttle_key("203.0.113.9", "Me@Example.com") == "203.0.113.9"
    assert Security.throttle_key(@gateway, " Me@Example.com ") == "account:me@example.com"
  end

  describe "blocking" do
    test "an internal address can't be blocked, a public one can" do
      attrs = %{identifier_type: "ip", reason: "x", blocked_at: DateTime.utc_now(), auto_blocked: false}
      assert {:error, :not_blockable} = Security.block_identifier(Map.put(attrs, :identifier, @gateway))
      assert {:ok, _} = Security.block_identifier(Map.put(attrs, :identifier, "203.0.113.#{rem(unique(), 200) + 1}"))
    end

    test "a stale block of the gateway is ignored by the blocker, a public one still blocks" do
      public = "203.0.113.#{rem(unique(), 200) + 1}"
      :ets.insert(:blocked_ips, {@gateway, System.system_time(:second)})
      :ets.insert(:blocked_ips, {public, System.system_time(:second)})
      on_exit(fn -> :ets.delete(:blocked_ips, @gateway); :ets.delete(:blocked_ips, public) end)

      call = fn ip -> Bacon8Web.Plugs.IpBlockerPlug.call(%{conn(:get, "/") | remote_ip: ip}, []) end

      refute call.({192, 168, 65, 3}).halted
      assert call.({203, 0, 113, String.to_integer(List.last(String.split(public, ".")))}).halted
    end

    test "the honeypot never auto-blocks the gateway, however many scans come from it" do
      :ets.delete(:blocked_ips, @gateway)
      :ets.delete(:honeypot_tracker, "suspicious:#{@gateway}")

      for _ <- 1..8 do
        conn = %{conn(:get, "/wp-login.php") | remote_ip: {192, 168, 65, 3}}
        assert Bacon8Web.Plugs.HoneypotPlug.call(conn, []).halted
      end

      assert :ets.lookup(:blocked_ips, @gateway) == []
    end
  end

  describe "sign-in limits when everyone shares one address" do
    test "wrong passwords for one account don't lock out the others" do
      a = "nobody-a-#{unique()}@example.com"
      b = "nobody-b-#{unique()}@example.com"

      # the per-address limit is 20 attempts: go well past it on account a
      results = for _ <- 1..25, do: Accounts.authenticate_user_secure(a, "wrong-password", ip_address: @gateway)
      assert {:error, msg} = List.last(results)
      assert is_binary(msg), "account a should now be throttled"

      # account b is untouched: it gets an ordinary wrong-password answer, not a lock-out
      assert {:error, :invalid_credentials} = Accounts.authenticate_user_secure(b, "wrong-password", ip_address: @gateway)
    end

    test "a real address is still throttled by itself" do
      ip = "203.0.113.#{rem(unique(), 200) + 1}"
      results = for n <- 1..25, do: Accounts.authenticate_user_secure("someone#{n}-#{unique()}@example.com", "wrong", ip_address: ip)
      assert {:error, msg} = List.last(results)
      assert is_binary(msg)
    end
  end
end

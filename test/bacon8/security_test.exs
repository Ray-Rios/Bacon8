defmodule Bacon8.SecurityTest do
  # Bacon8.Security beyond addresses (security_addresses_test.exs has those): the block list and
  # its expiry, the allow list, the sign-in gate that puts them together with the rate limiter,
  # what a sign-in leaves behind, device fingerprints and the suspicious-request counts
  # (2026-11-15; BACON8.md §13 listed the module as untested).
  use Bacon8.DataCase, async: false

  alias Bacon8.{RateLimiter, Security}

  defp n, do: System.unique_integer([:positive])
  defp public_ip, do: "203.0.113.#{rem(n(), 250) + 1}"
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
  defp block(identifier, extra \\ %{}) do
    Security.block_identifier(Map.merge(%{identifier: identifier, identifier_type: "ip", reason: "test", blocked_at: now(), auto_blocked: false}, extra))
  end

  describe "the block list" do
    test "a block holds until it is lifted" do
      ip = public_ip()
      refute Security.blocked?(ip)
      assert {:ok, _} = block(ip)
      assert Security.blocked?(ip)
      assert Enum.any?(Security.list_blocked_identifiers(), &(&1.identifier == ip))
      assert {:ok, _} = Security.unblock_identifier(ip)
      refute Security.blocked?(ip)
      assert Security.unblock_identifier(ip) == {:error, :not_found}
    end

    test "a block with an end holds until then, and not after" do
      still = public_ip()
      over = public_ip()
      assert {:ok, _} = block(still, %{expires_at: DateTime.add(now(), 3600, :second)})
      assert {:ok, _} = block(over, %{expires_at: DateTime.add(now(), -60, :second)})
      assert Security.blocked?(still)
      refute Security.blocked?(over)
    end

    test "the same address is blocked once; a fingerprint is its own kind of identifier" do
      ip = public_ip()
      assert {:ok, _} = block(ip)
      assert {:error, %Ecto.Changeset{}} = block(ip)
      print = "fp-#{n()}"
      assert {:ok, _} = Security.block_identifier(%{identifier: print, identifier_type: "fingerprint", blocked_at: now()})
      assert Security.blocked?(print, "fingerprint")
      refute Security.blocked?(print, "ip")
    end
  end

  describe "the sign-in gate (check_login_security/3)" do
    test "a blocked address is refused; an allowed one gets through even when blocked or throttled" do
      ip = public_ip()
      assert Security.check_login_security(ip) == {:ok, :allowed}
      assert {:ok, _} = block(ip)
      assert Security.check_login_security(ip) == {:error, :blocked}

      assert {:ok, _} = Security.allow_identifier(%{identifier: ip, identifier_type: "ip", added_at: now()})
      assert {:error, %Ecto.Changeset{}} = Security.allow_identifier(%{identifier: ip, identifier_type: "ip", added_at: now()})
      assert Security.allowed?(ip)
      assert Security.check_login_security(ip) == {:ok, :allowed}
      assert {:ok, _} = Security.disallow_identifier(ip)
      assert Security.check_login_security(ip) == {:error, :blocked}
      assert Security.disallow_identifier(ip) == {:error, :not_found}
    end

    test "a blocked device is refused whatever address it comes from" do
      print = "fp-#{n()}"
      assert {:ok, _} = Security.block_identifier(%{identifier: print, identifier_type: "fingerprint", blocked_at: now()})
      assert Security.check_login_security(public_ip(), print) == {:error, :blocked}
      assert Security.check_login_security(public_ip(), "fp-other-#{n()}") == {:ok, :allowed}
    end

    test "wrong passwords slow an address down; a right one clears it" do
      ip = public_ip()
      for _ <- 1..3, do: Security.record_login_result(ip, false, %{identifier_type: "ip", ip_address: ip})
      assert %{failed_attempts: 3} = RateLimiter.get_stats(ip)
      assert {:error, {:rate_limited, seconds}} = Security.check_login_security(ip)
      assert seconds in 1..5

      Security.record_login_result(ip, true, %{identifier_type: "ip", ip_address: ip})
      assert %{failed_attempts: 0} = RateLimiter.get_stats(ip)
      assert Security.check_login_security(ip) == {:ok, :allowed}

      # every try is on record, the failures listed for the admin
      attempts = Security.get_login_attempts(ip)
      assert length(attempts) == 4
      assert Enum.count(attempts, & &1.successful) == 1
      assert Enum.count(Security.get_recent_failed_attempts(), &(&1.identifier == ip)) == 3
    end
  end

  describe "devices and suspicious requests" do
    test "a fingerprint is made once and then only seen again; it can be tied to a user and trusted" do
      print = "fp-#{n()}"
      assert {:ok, first} = Security.get_or_create_fingerprint(print, %{user_agent: "test", platform: "web"})
      assert {:ok, again} = Security.get_or_create_fingerprint(print, %{user_agent: "other"})
      assert again.id == first.id
      assert again.user_agent == "test"

      user = user_fixture()
      assert {:ok, tied} = Security.associate_fingerprint_with_user(print, user.id)
      assert tied.user_id == user.id
      assert {:ok, %{trusted: true}} = Security.trust_fingerprint(print)
    end

    test "suspicious requests are counted per address inside the window" do
      ip = public_ip()
      other = public_ip()
      for path <- ["/wp-login.php", "/.env"], do: assert({:ok, _} = Security.record_suspicious_request(%{ip_address: ip, path: path, method: "GET", request_type: "php_probe"}))
      assert {:ok, _} = Security.record_suspicious_request(%{ip_address: other, path: "/x", method: "GET", request_type: "php_probe"})
      assert Security.count_suspicious_requests(ip, 600) == 2
      assert Security.count_suspicious_requests(other, 600) == 1
      assert Security.count_suspicious_requests(ip, -5) == 0
      assert {:error, %Ecto.Changeset{}} = Security.record_suspicious_request(%{ip_address: ip})
      assert Enum.any?(Security.get_recent_suspicious_requests(), &(&1.ip_address == ip))
    end

    test "the dashboard's numbers come back as numbers" do
      stats = Security.get_security_stats()
      assert is_map(stats) and map_size(stats) > 0
      assert is_map(Security.get_suspicious_stats())
    end
  end
end

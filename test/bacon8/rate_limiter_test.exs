defmodule Bacon8.RateLimiterTest do
  # The three in-memory limiters every sign-in and API call passes (2026-11-15; BACON8.md §13 listed
  # them as untested): Bacon8.RateLimiter (growing waits after wrong passwords, then a block),
  # Bacon8.Accounts.RateLimit (per-hour caps on sign-ins, registrations and password resets) and
  # Bacon8Web.Plugs.RateLimitPlug (the sliding window in front of the API). They are shared
  # processes and tables, so every test uses identifiers of its own.
  use ExUnit.Case, async: false
  import Plug.Test, only: [conn: 2]

  alias Bacon8.RateLimiter
  alias Bacon8.Accounts.RateLimit
  alias Bacon8Web.Plugs.RateLimitPlug

  defp id(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
  # casts are handled in order, so a call after them has seen them all
  defp fail(identifier, n), do: Enum.each(1..n, fn _ -> RateLimiter.record_failure(identifier) end)

  describe "RateLimiter: wrong passwords" do
    test "someone new may try; two failures cost nothing" do
      who = id("fresh")
      assert RateLimiter.check_attempt(who) == {:ok, :allowed}
      fail(who, 2)
      assert RateLimiter.check_attempt(who) == {:ok, :allowed}
      assert %{failed_attempts: 2, blocked: false} = RateLimiter.get_stats(who)
    end

    test "the wait grows: seconds after three, half a minute after five, five minutes after seven" do
      who = id("slow")
      fail(who, 3)
      assert {:error, wait3} = RateLimiter.check_attempt(who)
      assert wait3 in 1..5
      fail(who, 2)
      assert {:error, wait5} = RateLimiter.check_attempt(who)
      assert wait5 in 25..30
      fail(who, 2)
      assert {:error, wait7} = RateLimiter.check_attempt(who)
      assert wait7 in 295..300
    end

    test "a right password clears the count" do
      who = id("cleared")
      fail(who, 4)
      assert {:error, _} = RateLimiter.check_attempt(who)
      RateLimiter.record_success(who)
      assert RateLimiter.check_attempt(who) == {:ok, :allowed}
      assert %{failed_attempts: 0} = RateLimiter.get_stats(who)
    end

    test "ten failures block until someone unblocks; a success does not lift a block" do
      who = id("blocked")
      fail(who, 10)
      assert RateLimiter.check_attempt(who) == {:error, :blocked}
      assert Enum.any?(RateLimiter.list_blocked(), &(&1.identifier == who and &1.reason == "Too many failed attempts"))
      RateLimiter.record_success(who)
      assert RateLimiter.check_attempt(who) == {:error, :blocked}
      RateLimiter.unblock(who)
      assert RateLimiter.check_attempt(who) == {:ok, :allowed}
      refute Enum.any?(RateLimiter.list_blocked(), &(&1.identifier == who))
    end

    test "a block by hand names its reason, and one person's failures are not another's" do
      a = id("a")
      b = id("b")
      RateLimiter.block(a, "scanner")
      # (asking about a blocked identifier used to crash the limiter and wipe every count)
      limiter = Process.whereis(RateLimiter)
      assert %{blocked: true, block_reason: "scanner"} = RateLimiter.get_stats(a)
      assert Process.whereis(RateLimiter) == limiter
      assert RateLimiter.check_attempt(a) == {:error, :blocked}
      assert RateLimiter.check_attempt(b) == {:ok, :allowed}
      RateLimiter.unblock(a)
    end

    test "the sliding window lets max through, then says when it opens again" do
      key = id("window")
      now = System.system_time(:millisecond)
      for _ <- 1..3, do: assert(RateLimiter.check_and_increment_rate(key, 3, 60_000) == :ok)
      assert {:error, :rate_limited, reset} = RateLimiter.check_and_increment_rate(key, 3, 60_000)
      assert reset > now and reset <= now + 61_000
      # a window already over counts none of them
      assert RateLimiter.check_and_increment_rate(key, 3, 0) == :ok
    end
  end

  describe "Accounts.RateLimit: per-hour caps" do
    test "20 sign-ins an hour for one key, each key on its own" do
      who = id("login")
      for _ <- 1..19, do: RateLimit.record_login_attempt(who)
      assert RateLimit.check_login_limit(who) == :ok
      RateLimit.record_login_attempt(who)
      assert {:error, "Too many login attempts" <> _} = RateLimit.check_login_limit(who)
      assert RateLimit.check_login_limit(id("login")) == :ok
    end

    test "5 registrations an hour for one address, 3 password resets for one email" do
      ip = id("reg")
      for _ <- 1..5, do: RateLimit.record_registration_attempt(ip)
      assert {:error, _} = RateLimit.check_registration_limit(ip)

      email = id("reset") <> "@example.com"
      for _ <- 1..2, do: RateLimit.record_password_reset_attempt(email)
      assert RateLimit.check_password_reset_limit(email) == :ok
      RateLimit.record_password_reset_attempt(email)
      assert {:error, _} = RateLimit.check_password_reset_limit(email)
    end

    test "the counts are separate per kind" do
      who = id("mixed")
      RateLimit.record_login_attempt(who)
      RateLimit.record_login_attempt(who)
      RateLimit.record_registration_attempt(who)
      counts = Map.new(RateLimit.get_attempt_counts(who))
      assert counts[:rate_limit_logins] == 2
      assert counts[:rate_limit_registrations] == 1
      assert counts[:rate_limit_password_resets] == 0
    end

    test "the address is the connection's (set once by ClientIP), as text" do
      assert RateLimit.get_client_ip(%{conn(:get, "/") | remote_ip: {203, 0, 113, 7}}) == "203.0.113.7"
    end
  end

  describe "RateLimitPlug: the window in front of the API" do
    defp from(ip), do: %{conn(:post, "/api/auth/login") | remote_ip: ip}
    defp address, do: {198, 51, 100 + rem(System.unique_integer([:positive]), 100), rem(System.unique_integer([:positive]), 250) + 1}

    test "sign-in: five tries in five minutes, the sixth is a 429 that says when to come back" do
      opts = RateLimitPlug.init(endpoint: "auth_login")
      ip = address()
      for _ <- 1..5, do: refute(RateLimitPlug.call(from(ip), opts).halted)
      refused = RateLimitPlug.call(from(ip), opts)
      assert refused.halted and refused.status == 429
      assert Plug.Conn.get_resp_header(refused, "x-ratelimit-remaining") == ["0"]
      assert %{"retry_after" => after_s} = Jason.decode!(refused.resp_body)
      assert after_s in 0..300
    end

    test "one address being limited leaves the others alone, and each endpoint counts apart" do
      login = RateLimitPlug.init(endpoint: "auth_login")
      ip = address()
      for _ <- 1..6, do: RateLimitPlug.call(from(ip), login)
      assert RateLimitPlug.call(from(ip), login).halted
      refute RateLimitPlug.call(from(address()), login).halted
      refute RateLimitPlug.call(from(ip), RateLimitPlug.init(endpoint: "api_general")).halted
    end

    test "an endpoint nobody named gets the general limit; a custom limit is honoured" do
      assert %{limits: %{attempts: 200, window_ms: 60_000}} = RateLimitPlug.init(endpoint: "something_else")
      opts = RateLimitPlug.init(endpoint: "auth_verify", limits: %{"auth_verify" => %{attempts: 1, window_ms: 60_000}})
      ip = address()
      refute RateLimitPlug.call(from(ip), opts).halted
      assert RateLimitPlug.call(from(ip), opts).halted
    end
  end
end

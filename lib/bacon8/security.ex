defmodule Bacon8.Security do
  @moduledoc """
  The Security context handles authentication security, rate limiting,
  device fingerprinting, and behavioral analysis.
  """

  import Ecto.Query, warn: false
  alias Bacon8.Repo
  alias Bacon8.Security.{LoginAttempt, BlockedIdentifier, DeviceFingerprint, BehavioralData, AllowedIdentifier, SuspiciousRequest}
  alias Bacon8.RateLimiter

  ## Addresses we can't tell apart

  @doc """
  True for an address that identifies one visitor on the public internet, so it makes sense to block
  or rate-limit it.

  False for private, loopback and link-local addresses, and for anything that isn't an address.
  Behind Docker Desktop every visitor arrives from the node's own address (192.168.65.3): it names
  no one, and blocking it would shut the whole site out.
  """
  def blockable_ip?(ip) when is_binary(ip) do
    case :inet.parse_address(String.to_charlist(String.trim(ip))) do
      {:ok, addr} -> public_address?(addr)
      _ -> false
    end
  end

  def blockable_ip?(_), do: false

  defp public_address?({0, 0, 0, 0}), do: false
  defp public_address?({127, _, _, _}), do: false
  defp public_address?({10, _, _, _}), do: false
  defp public_address?({172, b, _, _}) when b in 16..31, do: false
  defp public_address?({192, 168, _, _}), do: false
  defp public_address?({169, 254, _, _}), do: false
  defp public_address?({100, b, _, _}) when b in 64..127, do: false
  defp public_address?({_, _, _, _}), do: true
  defp public_address?({0, 0, 0, 0, 0, 0, 0, 1}), do: false
  defp public_address?({0, 0, 0, 0, 0, 0xFFFF, hi, lo}), do: public_address?({div(hi, 256), rem(hi, 256), div(lo, 256), rem(lo, 256)})
  defp public_address?({first, _, _, _, _, _, _, _}) when first in 0xFC00..0xFDFF, do: false
  defp public_address?({first, _, _, _, _, _, _, _}) when first in 0xFE80..0xFEBF, do: false
  defp public_address?({_, _, _, _, _, _, _, _}), do: true

  @doc """
  What a login or sign-in attempt is throttled by: the visitor's address when it names one visitor,
  else the account being tried. (Throttling by an address everyone shares would let any five wrong
  passwords lock every member out.)
  """
  def throttle_key(ip, account) do
    if blockable_ip?(ip), do: ip, else: "account:" <> (account |> to_string() |> String.trim() |> String.downcase())
  end

  ## Login Attempts

  @doc """
  Records a login attempt.
  """
  def record_login_attempt(attrs) do
    %LoginAttempt{}
    |> LoginAttempt.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets login attempts for an identifier within a time window.
  """
  def get_login_attempts(identifier, hours_ago \\ 24) do
    time_threshold = DateTime.utc_now() |> DateTime.add(-hours_ago * 3600, :second)
    
    from(la in LoginAttempt,
      where: la.identifier == ^identifier and la.last_attempt_at > ^time_threshold,
      order_by: [desc: la.last_attempt_at]
    )
    |> Repo.all()
  end

  @doc """
  Gets recent failed login attempts across all identifiers.
  """
  def get_recent_failed_attempts(limit \\ 100) do
    from(la in LoginAttempt,
      where: la.successful == false,
      order_by: [desc: la.last_attempt_at],
      limit: ^limit,
      preload: [:user]
    )
    |> Repo.all()
  end

  ## Blocked Identifiers

  @doc """
  Checks if an identifier is blocked.
  """
  def blocked?(identifier, identifier_type \\ "ip") do
    case Repo.get_by(BlockedIdentifier, identifier: identifier, identifier_type: identifier_type) do
      nil -> 
        false
      %BlockedIdentifier{expires_at: nil} -> 
        true
      %BlockedIdentifier{expires_at: expires_at} -> 
        DateTime.compare(DateTime.utc_now(), expires_at) == :lt
    end
  end

  @doc """
  Blocks an identifier.
  """
  def block_identifier(attrs) do
    identifier = attrs[:identifier] || attrs["identifier"]
    type = attrs[:identifier_type] || attrs["identifier_type"]

    if type == "ip" and not blockable_ip?(identifier) do
      # (an address that isn't one visitor's: blocking it would block everyone behind it)
      {:error, :not_blockable}
    else
      result =
        %BlockedIdentifier{}
        |> BlockedIdentifier.changeset(attrs)
        |> Repo.insert()

      with {:ok, b} <- result,
           do: Bacon8.Audit.log(b.blocked_by_user_id, "security.blocked", "identifier", nil, %{identifier: b.identifier, type: b.identifier_type, reason: b.reason})

      result
    end
  end

  @doc """
  Unblocks an identifier.
  """
  def unblock_identifier(identifier, identifier_type \\ "ip") do
    case Repo.get_by(BlockedIdentifier, identifier: identifier, identifier_type: identifier_type) do
      nil ->
        {:error, :not_found}

      blocked ->
        with {:ok, _} = done <- Repo.delete(blocked) do
          Bacon8.Audit.log(nil, "security.unblocked", "identifier", nil, %{identifier: identifier, type: identifier_type})
          done
        end
    end
  end

  @doc """
  Lists all blocked identifiers.
  """
  def list_blocked_identifiers do
    from(bi in BlockedIdentifier,
      order_by: [desc: bi.blocked_at],
      preload: [:blocked_by_user]
    )
    |> Repo.all()
  end

  @doc """
  Lists blocked identifiers history (including expired/unblocked) for the last 90 days.
  """
  def list_blocked_history(days \\ 90) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days, :day)
    
    from(bi in BlockedIdentifier,
      where: bi.blocked_at >= ^cutoff,
      order_by: [desc: bi.blocked_at],
      preload: [:blocked_by_user]
    )
    |> Repo.all()
  end

  ## Allowed Identifiers

  @doc """
  Checks if an identifier is on the allowlist.
  """
  def allowed?(identifier, identifier_type \\ "ip") do
    case Repo.get_by(AllowedIdentifier, identifier: identifier, identifier_type: identifier_type) do
      nil -> false
      _allowed -> true
    end
  end

  @doc """
  Adds an identifier to the allowlist.
  """
  def allow_identifier(attrs) do
    %AllowedIdentifier{}
    |> AllowedIdentifier.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Removes an identifier from the allowlist.
  """
  def disallow_identifier(identifier, identifier_type \\ "ip") do
    case Repo.get_by(AllowedIdentifier, identifier: identifier, identifier_type: identifier_type) do
      nil -> {:error, :not_found}
      allowed -> Repo.delete(allowed)
    end
  end

  @doc """
  Lists all allowed identifiers.
  """
  def list_allowed_identifiers do
    from(ai in AllowedIdentifier,
      order_by: [desc: ai.added_at],
      preload: [:added_by_user]
    )
    |> Repo.all()
  end

  ## Device Fingerprints

  @doc """
  Gets or creates a device fingerprint.
  """
  def get_or_create_fingerprint(fingerprint_hash, attrs \\ %{}) do
    case Repo.get_by(DeviceFingerprint, fingerprint_hash: fingerprint_hash) do
      nil ->
        %DeviceFingerprint{}
        |> DeviceFingerprint.changeset(Map.merge(attrs, %{
          fingerprint_hash: fingerprint_hash,
          first_seen_at: DateTime.utc_now(),
          last_seen_at: DateTime.utc_now()
        }))
        |> Repo.insert()
      
      fingerprint ->
        fingerprint
        |> DeviceFingerprint.changeset(%{last_seen_at: DateTime.utc_now()})
        |> Repo.update()
    end
  end

  @doc """
  Associates a fingerprint with a user.
  """
  def associate_fingerprint_with_user(fingerprint_hash, user_id) do
    case Repo.get_by(DeviceFingerprint, fingerprint_hash: fingerprint_hash) do
      nil -> {:error, :not_found}
      fingerprint ->
        fingerprint
        |> DeviceFingerprint.changeset(%{user_id: user_id})
        |> Repo.update()
    end
  end

  @doc """
  Trusts a device fingerprint.
  """
  def trust_fingerprint(fingerprint_hash) do
    case Repo.get_by(DeviceFingerprint, fingerprint_hash: fingerprint_hash) do
      nil -> {:error, :not_found}
      fingerprint ->
        fingerprint
        |> DeviceFingerprint.changeset(%{trusted: true})
        |> Repo.update()
    end
  end

  ## Behavioral Data

  @doc """
  Records behavioral data for analysis.
  """
  def record_behavioral_data(attrs) do
    %BehavioralData{}
    |> BehavioralData.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets behavioral data for a device fingerprint.
  """
  def get_behavioral_data(device_fingerprint_id, limit \\ 10) do
    from(bd in BehavioralData,
      where: bd.device_fingerprint_id == ^device_fingerprint_id,
      order_by: [desc: bd.timestamp],
      limit: ^limit
    )
    |> Repo.all()
  end

  ## High-level Security Checks

  @doc """
  Comprehensive security check for login attempts.
  Returns {:ok, :allowed} or {:error, reason}
  """
  def check_login_security(identifier, fingerprint_hash \\ nil, _ip_address \\ nil) do
    # Check allowlist first (bypass all checks)
    cond do
      allowed?(identifier, "ip") or (fingerprint_hash && allowed?(fingerprint_hash, "fingerprint")) ->
        {:ok, :allowed}
      
      # Check blocklist (an address that isn't one visitor's is never blocked)
      (blockable_ip?(identifier) and blocked?(identifier, "ip")) or (fingerprint_hash && blocked?(fingerprint_hash, "fingerprint")) ->
        {:error, :blocked}
      
      # Check rate limiter
      true ->
        case RateLimiter.check_attempt(identifier) do
          {:ok, :allowed} -> {:ok, :allowed}
          {:error, seconds} -> {:error, {:rate_limited, seconds}}
        end
    end
  end

  @doc """
  Records the result of a login attempt and updates all tracking.
  """
  def record_login_result(identifier, successful, attrs \\ %{}) do
    # Record in database
    record_login_attempt(Map.merge(attrs, %{
      identifier: identifier,
      successful: successful,
      last_attempt_at: DateTime.utc_now()
    }))

    # Update rate limiter
    if successful do
      RateLimiter.record_success(identifier)
    else
      RateLimiter.record_failure(identifier)
    end
  end

  @doc """
  Gets security statistics for the admin dashboard.
  """
  def get_security_stats do
    now = DateTime.utc_now()
    one_hour_ago = DateTime.add(now, -3600, :second)
    one_day_ago = DateTime.add(now, -86400, :second)

    %{
      total_attempts_last_hour: count_attempts_since(one_hour_ago),
      total_attempts_last_day: count_attempts_since(one_day_ago),
      failed_attempts_last_hour: count_failed_attempts_since(one_hour_ago),
      failed_attempts_last_day: count_failed_attempts_since(one_day_ago),
      blocked_identifiers: count_blocked_identifiers(),
      allowed_identifiers: count_allowed_identifiers(),
      unique_fingerprints: count_unique_fingerprints(),
      rate_limiter_blocked: length(RateLimiter.list_blocked())
    }
  end

  defp count_attempts_since(timestamp) do
    from(la in LoginAttempt, where: la.last_attempt_at > ^timestamp)
    |> Repo.aggregate(:count)
  end

  defp count_failed_attempts_since(timestamp) do
    from(la in LoginAttempt, 
      where: la.last_attempt_at > ^timestamp and la.successful == false
    )
    |> Repo.aggregate(:count)
  end

  defp count_blocked_identifiers do
    Repo.aggregate(BlockedIdentifier, :count)
  end

  defp count_allowed_identifiers do
    Repo.aggregate(AllowedIdentifier, :count)
  end

  defp count_unique_fingerprints do
    Repo.aggregate(DeviceFingerprint, :count)
  end

  ## Suspicious Requests

  @doc """
  Records a suspicious request.
  """
  def record_suspicious_request(attrs) do
    %SuspiciousRequest{}
    |> SuspiciousRequest.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Counts suspicious requests from an IP within a time window (in seconds).
  """
  def count_suspicious_requests(ip_address, time_window_seconds) do
    cutoff = DateTime.add(DateTime.utc_now(), -time_window_seconds, :second)
    
    from(sr in SuspiciousRequest,
      where: sr.ip_address == ^ip_address and sr.inserted_at >= ^cutoff
    )
    |> Repo.aggregate(:count)
  end

  @doc """
  Gets recent suspicious requests for the admin dashboard.
  """
  def get_recent_suspicious_requests(limit \\ 100) do
    from(sr in SuspiciousRequest,
      order_by: [desc: sr.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Gets suspicious request statistics.
  """
  def get_suspicious_stats do
    now = DateTime.utc_now()
    one_hour_ago = DateTime.add(now, -3600, :second)
    one_day_ago = DateTime.add(now, -86400, :second)

    %{
      total_last_hour: count_suspicious_since(one_hour_ago),
      total_last_day: count_suspicious_since(one_day_ago),
      by_type_last_day: suspicious_by_type_since(one_day_ago),
      top_offenders: top_suspicious_ips(one_day_ago, 10)
    }
  end

  defp count_suspicious_since(timestamp) do
    from(sr in SuspiciousRequest, where: sr.inserted_at > ^timestamp)
    |> Repo.aggregate(:count)
  end

  defp suspicious_by_type_since(timestamp) do
    from(sr in SuspiciousRequest,
      where: sr.inserted_at > ^timestamp,
      group_by: sr.request_type,
      select: {sr.request_type, count(sr.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp top_suspicious_ips(timestamp, limit) do
    from(sr in SuspiciousRequest,
      where: sr.inserted_at > ^timestamp,
      group_by: sr.ip_address,
      select: {sr.ip_address, count(sr.id)},
      order_by: [desc: count(sr.id)],
      limit: ^limit
    )
    |> Repo.all()
  end
end

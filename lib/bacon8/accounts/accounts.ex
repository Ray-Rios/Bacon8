defmodule Bacon8.Accounts do
  import Ecto.Query
  alias Bacon8.Repo
  alias Bacon8.Accounts.User
  
  require Logger

  # ---------------------
  # List all users
  # ---------------------
  def list_users do
    Repo.all(User)
  end

  # ---------------------
  # Get User by id
  # ---------------------
  def get_user(id) when is_binary(id), do: Repo.get(User, id)
  def get_user!(id), do: Repo.get!(User, id)

  # ---------------------
  # Enhanced registration with security checks
  # ---------------------
  def register_user(attrs, opts \\ []) do
    ip_address = Keyword.get(opts, :ip_address)
    email = String.trim(attrs["email"] || "")
    username = String.trim(attrs["name"] || "")
    
    # Check if user already exists with this email or username
    cond do
      get_user_by_email(email) != nil ->
        existing_user = get_user_by_email(email)
        # Check if email is verified - allow re-registration if not verified
        if existing_user.email_verified_at do
          {:error, :email_taken, "An account with this email address already exists."}
        else
          # Email not verified, resend verification email
          case Bacon8.Accounts.EmailVerification.send_verification_email(existing_user) do
            {:ok, message} ->
              {:ok, existing_user, message}
            {:error, _email_error} ->
              {:ok, existing_user, "Please check your email for the verification code."}
          end
        end
      
      get_user_by_username(username) != nil ->
        {:error, :username_taken, "This username is already taken. Please choose a different one."}
      
      true ->
        # No existing user, proceed with normal registration
        with :ok <- check_registration_rate_limit(ip_address),
             {:ok, user} <- create_user_with_verification(attrs, ip_address) do
          
          # Record the registration attempt for rate limiting
          if ip_address, do: Bacon8.Accounts.RateLimit.record_registration_attempt(ip_address)
          
          # Send verification email
          case Bacon8.Accounts.EmailVerification.send_verification_email(user) do
            {:ok, message} ->
              {:ok, user, message}
            {:error, _email_error} ->
              # User created but email failed - still return success
              {:ok, user, "Account created but verification email could not be sent. Please contact support."}
          end
        else
          {:error, %Ecto.Changeset{} = changeset} ->
            # Check if this is a unique constraint error
            case changeset.errors do
              [email: {_msg, [constraint: :unique, constraint_name: _]}] ->
                {:error, :email_taken, "An account with this email address already exists."}
              [name: {_msg, [constraint: :unique, constraint_name: _]}] ->
                {:error, :username_taken, "This username is already taken. Please choose a different one."}
              _ ->
                {:error, changeset}
            end
          error ->
            error
        end
    end
  end
  defp check_registration_rate_limit(nil), do: :ok
  defp check_registration_rate_limit(ip_address) do
    Bacon8.Accounts.RateLimit.check_registration_limit(ip_address)
  end

  defp create_user_with_verification(attrs, ip_address) do
    attrs_with_ip = if ip_address, do: Map.put(attrs, "registration_ip", ip_address), else: attrs
    
    Repo.transaction(fn ->
      # Check if this is the first user (should be admin)
      user_count = count_users()
      is_first_user = user_count == 0
      
      # Determine role: first user is always admin, others use the default role setting
      attrs_with_role = if is_first_user do
        attrs_with_ip
        |> Map.put("role", "admin")
        |> Map.put("is_admin", true)
      else
        # Get the default role from settings (defaults to "member" if not set)
        default_role = Bacon8.Settings.get_default_user_role()
        
        # Map role to is_admin flag
        is_admin = default_role == "admin"
        
        attrs_with_ip
        |> Map.put("role", default_role)
        |> Map.put("is_admin", is_admin)
      end
      
      # Create the user
      case %User{}
           |> User.registration_changeset(attrs_with_role)
           |> Repo.insert() do
        {:ok, user} ->
          user
        
        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  # ---------------------
  # Update profile (name/email)
  # ---------------------
  def update_profile(%User{} = user, attrs) do
    Repo.transaction(fn ->
      case user
           |> User.profile_changeset(attrs)
           |> Repo.update() do
        {:ok, updated_user} ->
          updated_user
        
        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  # ---------------------
  # Update password
  # ---------------------
  def update_password(%User{} = user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> Repo.update()
  end

  # ---------------------
  # Get user by email
  # ---------------------
  def get_user_by_email(email) when is_binary(email), do: Repo.get_by(User, email: email)

  # ---------------------
  # Get user by username (name field)
  # ---------------------
  def get_user_by_username(username) when is_binary(username), do: Repo.get_by(User, name: username)

  @doc """
  Get multiple users by their usernames.
  Returns a list of users matching the given usernames (case-insensitive).
  """
  def get_users_by_usernames(usernames) when is_list(usernames) do
    # Normalize usernames for case-insensitive matching
    lower_usernames = Enum.map(usernames, &String.downcase/1)
    
    from(u in User, where: fragment("lower(?)", u.name) in ^lower_usernames)
    |> Repo.all()
  end

  # ---------------------
  # Check if username is available
  # ---------------------
  def username_available?(username) when is_binary(username) do
    username = String.trim(username)
    case get_user_by_username(username) do
      nil -> true
      _user -> false
    end
  end

  # ---------------------
  # Get user by email or username  
  # ---------------------
  def get_user_by_email_or_username(identifier) when is_binary(identifier) do
    # Check if identifier contains @ (likely email) or not (likely username/name)
    if String.contains?(identifier, "@") do
      Repo.get_by(User, email: identifier)
    else
      # Try to find by name field (which serves as username)
      Repo.get_by(User, name: identifier)
    end
  end

  # ---------------------
  # Check user password
  # ---------------------
  def check_password(%User{password_hash: hash}, password) when is_binary(password) do
    Pbkdf2.verify_pass(password, hash)
  end

  # ---------------------
  # Enhanced authentication with security checks
  # ---------------------
  def authenticate_user_secure(identifier, password, opts \\ []) when is_binary(identifier) and is_binary(password) do
    ip_address = Keyword.get(opts, :ip_address)
    user_agent = Keyword.get(opts, :user_agent, "Unknown")
    
    # Check rate limiting first
    with :ok <- check_login_rate_limit(ip_address) do
      start_time = System.monotonic_time(:millisecond)
      
      result = case get_user_by_email_or_username(identifier) do
        nil ->
          # Still run password check to prevent timing attacks
          Pbkdf2.no_user_verify()
          # Record failed attempt for unknown user
          record_failed_login(ip_address, nil, identifier, user_agent: user_agent)
          {:error, :invalid_credentials}

        user ->
          if check_password(user, password) do
            # Additional security checks
            cond do
              user.role == "banned" || user.role == "BANNED" ->
                {:error, :account_banned}
              
              user.status == "disabled" ->
                {:error, :account_disabled}
              
              user.locked_until && DateTime.compare(DateTime.utc_now(), user.locked_until) == :lt ->
                {:error, :account_locked}
              
              is_nil(user.email_verified_at) ->
                {:error, :email_not_verified}
              
              true ->
                # Reset failed login attempts on successful login
                reset_failed_login_attempts(user, ip_address, user_agent: user_agent)
                {:ok, user}
            end
          else
            # Record failed login attempt
            record_failed_login(ip_address, user, identifier, user_agent: user_agent)
            {:error, :invalid_credentials}
          end
      end
      
      end_time = System.monotonic_time(:millisecond)
      Logger.info("Authentication took #{end_time - start_time}ms")
      
      result
    else
      {:error, rate_limit_error} when is_binary(rate_limit_error) ->
        {:error, rate_limit_error}
      
      {:error, _} ->
        {:error, "Too many login attempts. Please try again later."}
    end
  end

  defp check_login_rate_limit(nil), do: :ok
  defp check_login_rate_limit(ip_address) do
    Bacon8.Accounts.RateLimit.check_login_limit(ip_address)
  end



  defp record_failed_login(ip_address, user, identifier_attempted, opts) do
    user_agent = Keyword.get(opts, :user_agent, "Unknown")
    
    # Record in RateLimiter
    if ip_address, do: Bacon8.Accounts.RateLimit.record_login_attempt(ip_address)
    
    # Record in Security Context
    Bacon8.Security.record_login_attempt(%{
      identifier: identifier_attempted || (user && user.email) || "unknown",
      identifier_type: "ip",
      ip_address: ip_address,
      user_agent: user_agent,
      successful: false,
      user_id: user && user.id
    })
  end

  defp reset_failed_login_attempts(user, ip_address, opts) do
    user_agent = Keyword.get(opts, :user_agent, "Unknown")
    
    # Record successful login in Security Context
    Bacon8.Security.record_login_attempt(%{
      identifier: user.email,
      identifier_type: "ip",
      ip_address: ip_address,
      user_agent: user_agent,
      successful: true,
      user_id: user.id
    })

    # Reset failed login attempts and update last login information
    user
    |> User.reset_failed_login_changeset(ip_address)
    |> Repo.update()
  end

  # Email verification functions
  def verify_user_email(token) do
    Bacon8.Accounts.EmailVerification.verify_email(token)
  end

  def verify_user_with_code(email, code) do
    Bacon8.Accounts.EmailVerification.verify_email_with_code(email, code)
  end

  def verify_user_email_direct(user) do
    # Direct email verification without token (for development)
    user
    |> User.verify_email_changeset()
    |> Repo.update()
  end

  def resend_verification_email(email) do
    Bacon8.Accounts.EmailVerification.resend_verification_email(email)
  end

  # Account management
  def unlock_user_account(user) do
    user
    |> User.reset_failed_login_changeset()
    |> Repo.update()
  end

  def is_account_secure?(user) do
    User.email_verified?(user) and not User.account_locked?(user)
  end

  # ---------------------
  # Session token functions
  # ---------------------
  def generate_user_session_token(_user) do
    token = :crypto.strong_rand_bytes(32)
    # For now, just return the token - implement UserToken later if needed
    token
  end

  def get_user_by_session_token(_token) do
    # For now, return nil - implement UserToken later if needed
    nil
  end

  def delete_user_session_token(_token) do
    # For now, just return ok - implement UserToken later if needed
    :ok
  end

  # ---------------------
  # Admin functions
  # ---------------------
  def make_admin(%User{} = user) do
    user
    |> User.admin_changeset(%{is_admin: true})
    |> Repo.update()
  end

  def remove_admin(%User{} = user) do
    user
    |> User.admin_changeset(%{is_admin: false})
    |> Repo.update()
  end

  @roles ~w(admin gm editor moderator member guest banned)

  @doc """
  The ONLY way to change a user's role (BACON8.md §7). Every caller - admin
  pages, the admin API, the API toolbox - goes through here so the side effects
  below cannot be skipped:

    * becoming **guest** or **banned**: the drive is locked and scheduled for
      purge in 30 days and storage-tier entitlements are revoked
    * leaving guest/banned: the drive is unlocked (if not yet purged); the user
      is back on the free tier
    * becoming **banned**: sessions are disconnected and `cleanup_banned_user/1`
      runs

  `opts[:actor]` (the admin making the change) is recorded in the log line.
  """
  def change_role(%User{} = user, role, opts \\ []) when is_binary(role) do
    require Logger
    new_role = if role in @roles, do: role, else: "member"
    old_role = user.role

    Repo.transaction(fn ->
      updated =
        user
        |> User.role_changeset(%{is_admin: new_role == "admin", role: new_role})
        |> Repo.update()
        |> case do
          {:ok, u} -> u
          {:error, changeset} -> Repo.rollback(changeset)
        end

      drive = Bacon8.Drive.on_role_change(updated, old_role, new_role)

      {updated, drive}
    end)
    |> case do
      {:ok, {updated, drive}} ->
        actor = case opts[:actor] do
          %{id: id} -> id
          _ -> "system"
        end

        Logger.info(
          "Role change #{user.id}: #{old_role} -> #{new_role} by #{actor}; " <>
            "drive=#{drive}"
        )

        if new_role == "banned" and old_role != "banned" do
          disconnect_user_sessions(updated)
          cleanup_banned_user(updated)
        end

        {:ok, updated}

      error ->
        error
    end
  end

  @doc "Deprecated name for `change_role/3`."
  def update_user_role(%User{} = user, role) when is_binary(role), do: change_role(user, role)

  def cleanup_banned_user(%User{id: user_id} = user) do
    require Logger
    Logger.info("Cleaning up banned user #{user_id}")

    Repo.transaction(fn ->
      import Ecto.Query
      
      # 1. Delete all forum messages
      {deleted_count, _} = Repo.delete_all(from(m in Bacon8.Forum.Message, where: m.user_id == ^user_id))
      Logger.info("Deleted #{deleted_count} forum messages for banned user #{user_id}")

      # 2. Delete all reactions
      {deleted_reactions, _} = Repo.delete_all(from(r in Bacon8.Forum.Reaction, where: r.user_id == ^user_id))
      Logger.info("Deleted #{deleted_reactions} reactions for banned user #{user_id}")

      # 3. User files are NOT deleted here: they follow the drive's 30-day hold
      #    (Bacon8.Drive.on_role_change/3, purged by Bacon8.Drive.Janitor).

      # 4. Delete Posts (Blog/Content)
      {posts_deleted, _} = Repo.delete_all(from(p in Bacon8.Content.Post, where: p.user_id == ^user_id))
      Logger.info("Deleted #{posts_deleted} posts for banned user #{user_id}")

      # 5. Delete Comments
      {comments_deleted, _} = Repo.delete_all(from(c in Bacon8.Content.Comment, where: c.user_id == ^user_id))
      Logger.info("Deleted #{comments_deleted} comments for banned user #{user_id}")

      # 6-8. Game tables removed from codebase

      # 9. Delete Device Fingerprints & Login Attempts
      {fp_deleted, _} = Repo.delete_all(from(df in Bacon8.Security.DeviceFingerprint, where: df.user_id == ^user_id))
      {login_deleted, _} = Repo.delete_all(from(la in Bacon8.Security.LoginAttempt, where: la.user_id == ^user_id))
      Logger.info("Deleted #{fp_deleted} fingerprints and #{login_deleted} login attempts for banned user #{user_id}")

      # 10. Delete Tokens
      {tokens_deleted, _} = Repo.delete_all(from(t in Bacon8.Accounts.UserToken, where: t.user_id == ^user_id))
      Logger.info("Deleted #{tokens_deleted} user tokens for banned user #{user_id}")

      # 11. Clear avatar URL in database
      user
      |> User.avatar_changeset(%{avatar_url: nil, avatar_file: nil})
      |> Repo.update()
    end)
    |> case do
      {:ok, _} ->
        # 12. The upload directory is kept: it holds files under the 30-day
        #     hold (and legacy copies until the drive import is retired).
        :ok
      {:error, reason} ->
        Logger.error("Failed to cleanup banned user #{user_id}: #{inspect(reason)}")
    end
  end

  def disconnect_user_sessions(%User{id: user_id}) do
    require Logger
    Logger.info("Broadcasting disconnect to user_sessions:#{user_id}")
    # Use Phoenix.PubSub directly for cluster-wide message delivery
    Phoenix.PubSub.broadcast(Bacon8.PubSub, "user_sessions:#{user_id}", %{event: "disconnect", user_id: user_id})
  end

  def count_users do
    Repo.aggregate(User, :count, :id)
  end

  def count_admin_users do
    import Ecto.Query
    from(u in User, where: u.is_admin == true)
    |> Repo.aggregate(:count, :id)
  end

  def count_active_users do
    import Ecto.Query
    # Users who have logged in in the last 30 days
    thirty_days_ago = DateTime.utc_now() |> DateTime.add(-30, :day)
    from(u in User, where: u.last_login_at > ^thirty_days_ago or u.is_online == true)
    |> Repo.aggregate(:count, :id)
  end

  def list_recent_users(limit \\ 5) do
    import Ecto.Query
    from(u in User, order_by: [desc: u.inserted_at], limit: ^limit)
    |> Repo.all()
  end

  # ---------------------
  # User management functions
  # ---------------------
  def create_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  def update_user(%User{} = user, attrs) do
    user
    |> User.admin_changeset(attrs)
    |> Repo.update()
  end

  def update_user_position(%User{} = user, attrs) do
    user
    |> User.position_changeset(attrs)
    |> Repo.update()
  end

  def update_user_profile(%User{} = user, attrs) do
    update_profile(user, attrs)
  end

  def change_user_profile(%User{} = user, attrs \\ %{}) do
    User.profile_changeset(user, attrs)
  end

  def update_user_password(%User{} = user, attrs) do
    user
    |> User.password_change_changeset(attrs)
    |> Repo.update()
  end

  def update_avatar(%User{} = user, attrs) do
    user
    |> User.avatar_changeset(attrs)
    |> Repo.update()
  end

  def enable_user(%User{} = user) do
    # When admin enables a user, also verify their email (acts like admin bypass)
    attrs = %{status: "active"}
    
    # If email not yet verified, verify it now
    attrs = if is_nil(user.email_verified_at) do
      Map.put(attrs, :email_verified_at, DateTime.utc_now())
    else
      attrs
    end
    
    user
    |> User.admin_changeset(attrs)
    |> Repo.update()
  end

  def disable_user(%User{} = user) do
    result = user
    |> User.status_changeset(%{status: "disabled"})
    |> Repo.update()
    
    case result do
      {:ok, updated_user} ->
        disconnect_user_sessions(updated_user)
        {:ok, updated_user}
      error -> error
    end
  end

  # ---------------------
  # Two-factor authentication
  # ---------------------
  def enable_two_factor(%User{} = user, secret, backup_codes) do
    user
    |> User.two_factor_changeset(%{
      two_factor_secret: secret,
      two_factor_enabled: true,
      two_factor_backup_codes: backup_codes
    })
    |> Repo.update()
  end

  def disable_two_factor(%User{} = user) do
    user
    |> User.two_factor_changeset(%{
      two_factor_secret: nil,
      two_factor_enabled: false,
      two_factor_backup_codes: []
    })
    |> Repo.update()
  end

  # ---------------------
  # Delete user
  # ---------------------

  # Rows other tables keep for the record (BACON8.md §8): store orders, the
  # Gem ledger, license keys sold.
  defp has_purchases?(user_id) do
    Repo.exists?(from o in Bacon8.Store.Order, where: o.user_id == ^user_id) or
      Repo.exists?(from a in Bacon8.Wallet.Account, where: a.user_id == ^user_id) or
      Repo.exists?(from k in Bacon8.Store.LicenseKey, where: k.user_id == ^user_id)
  end

  # The account can never sign in again and nothing in it identifies the
  # person; its id stays so purchase records still point somewhere.
  defp anonymize!(%User{id: user_id} = user) do
    tag = String.slice(user_id, 0, 8)
    now = DateTime.utc_now()

    Repo.update_all(
      from(e in Bacon8.Entitlements.Entitlement, where: e.user_id == ^user_id and is_nil(e.revoked_at)),
      set: [revoked_at: now, revoked_reason: "account deleted", updated_at: now]
    )

    user
    |> Ecto.Changeset.change(
      email: "deleted-#{user_id}@deleted.invalid",
      name: "deleted-#{tag}",
      password_hash: Base.encode64(:crypto.strong_rand_bytes(48)),
      status: "disabled",
      role: "guest",
      is_admin: false,
      is_online: false,
      bio: nil,
      avatar_url: nil,
      avatar_file: nil,
      two_factor_secret: nil,
      two_factor_enabled: false,
      two_factor_backup_codes: [],
      background_custom_data: %{},
      blocked_user_ids: [],
      channel_order: [],
      email_verification_token: nil,
      password_reset_token: nil,
      registration_ip: nil,
      last_login_ip: nil,
      stripe_customer_id: nil
    )
    |> Repo.update!()
  end

  def delete_user(%User{} = user) do
    Repo.transaction(fn ->
      import Ecto.Query

      user_id = user.id
      Logger.debug("delete_user: starting cascade for user_id=#{user_id}")

      # Nullify self-referential relationships to avoid constraint errors
      {updated_approved_by, _} =
        Repo.update_all(
          from(u in User, where: u.approved_by_id == ^user_id),
          set: [approved_by_id: nil]
        )
      Logger.debug("delete_user: nullified approved_by_id on #{updated_approved_by} users")

      # Remove dependent records that don't rely on DB-level cascades
      {tokens_deleted, _} = Repo.delete_all(from(t in Bacon8.Accounts.UserToken, where: t.user_id == ^user_id))
      Logger.debug("delete_user: deleted #{tokens_deleted} user tokens")

      {reactions_deleted, _} = Repo.delete_all(from(r in Bacon8.Forum.Reaction, where: r.user_id == ^user_id))
      Logger.debug("delete_user: deleted #{reactions_deleted} chat reactions")

      {chat_msgs_deleted, _} = Repo.delete_all(from(m in Bacon8.Forum.Message, where: m.user_id == ^user_id))
      Logger.debug("delete_user: deleted #{chat_msgs_deleted} chat messages")

      # Game tables have been removed from the codebase

      {files_deleted, _} = Repo.delete_all(from(f in Bacon8.Files.UserFile, where: f.user_id == ^user_id))
      Logger.debug("delete_user: deleted #{files_deleted} user files")

      {posts_deleted, _} = Repo.delete_all(from(p in Bacon8.Content.Post, where: p.user_id == ^user_id))
      Logger.debug("delete_user: deleted #{posts_deleted} posts")

      {comments_nullified, _} = Repo.update_all(from(c in Bacon8.Content.Comment, where: c.user_id == ^user_id), set: [user_id: nil])
      Logger.debug("delete_user: nullified user_id on #{comments_nullified} comments")

      {fp_deleted, _} = Repo.delete_all(from(df in Bacon8.Security.DeviceFingerprint, where: df.user_id == ^user_id))
      Logger.debug("delete_user: deleted #{fp_deleted} device fingerprints")

      {login_deleted, _} = Repo.delete_all(from(la in Bacon8.Security.LoginAttempt, where: la.user_id == ^user_id))
      Logger.debug("delete_user: deleted #{login_deleted} login attempts")

      {allowed_nullified, _} = Repo.update_all(from(ai in Bacon8.Security.AllowedIdentifier, where: ai.added_by_user_id == ^user_id), set: [added_by_user_id: nil])
      Logger.debug("delete_user: nullified added_by_user_id on #{allowed_nullified} allowed_identifiers")

      {blocked_nullified, _} = Repo.update_all(from(bi in Bacon8.Security.BlockedIdentifier, where: bi.blocked_by_user_id == ^user_id), set: [blocked_by_user_id: nil])
      Logger.debug("delete_user: nullified blocked_by_user_id on #{blocked_nullified} blocked_identifiers")

      if has_purchases?(user_id) do
        # Store orders and the Gem ledger must outlive the account (sales
        # records), so the row stays and everything personal goes.
        anonymized = anonymize!(user)
        Logger.info("delete_user: user_id=#{user_id} has purchases; anonymized instead of deleted")
        anonymized
      else
        case Repo.delete(user) do
          {:ok, deleted_user} ->
            Logger.debug("delete_user: user record deleted successfully user_id=#{user_id}")
            deleted_user

          {:error, changeset} ->
            Logger.error("delete_user: failed to delete user record user_id=#{user_id} error=#{inspect(changeset.errors)}")
            Repo.rollback(changeset)
        end
      end
    end)
    |> case do
      {:ok, deleted_user} ->
        # Cleanup user's upload directory from filesystem
        user_upload_dir = Bacon8.Uploads.user_dir(deleted_user.id)
        case File.rm_rf(user_upload_dir) do
          {:ok, _files} ->
            Logger.info("delete_user: removed upload directory #{user_upload_dir}")
          {:error, reason, _} ->
            Logger.error("delete_user: failed to remove upload directory #{user_upload_dir}: #{inspect(reason)}")
        end

        {:ok, deleted_user}

      {:error, reason} ->
        Logger.error("delete_user: transaction failed for user_id=#{user.id} reason=#{inspect(reason)}")
        {:error, reason}
    end
  end



  # ---------------------
  # Safe delete user
  # ---------------------
  def safe_delete_user(%User{} = user) do
    delete_user(user)
  end

  # ---------------------
  # Password Reset Functions
  # ---------------------
  
  def send_password_reset_email(identifier, _ip_address \\ nil) when is_binary(identifier) do
    identifier = String.trim(identifier)
    
    # Check rate limiting first (use email/username for rate limiting)
    with :ok <- check_password_reset_rate_limit(identifier) do
      # Find user by email or username
      case get_user_by_email_or_username(identifier) do
        nil ->
          # Don't reveal if user exists or not - always return success message
          # But record the attempt for rate limiting
          Bacon8.Accounts.RateLimit.record_password_reset_attempt(identifier)
          {:ok, "If an account with that email/username exists, you should receive an email with instructions shortly."}
          
        %User{} = user ->
          # Generate reset token and send email
          with {:ok, user_with_token} <- generate_password_reset_token(user) do
            case Bacon8.Email.send_password_reset_email(user_with_token) do
              {:ok, _} -> 
                # Record the attempt for rate limiting (use the identifier, not IP)
                Bacon8.Accounts.RateLimit.record_password_reset_attempt(identifier)
                {:ok, "If an account with that email/username exists, you should receive an email with instructions shortly."}
              {:error, _reason} ->
                {:error, "Unable to send password reset email. Please try again later."}
            end
          else
            {:error, _changeset} ->
              {:error, "Unable to send password reset email. Please try again later."}
          end
      end
    else
      {:error, :rate_limited} ->
        {:error, :rate_limited}
    end
  end

  defp generate_password_reset_token(%User{} = user) do
    # Generate a secure random token
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    
    # Update user with token and timestamp
    changeset = User.password_reset_changeset(user, %{
      password_reset_token: token,
      password_reset_sent_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    
    case Repo.update(changeset) do
      {:ok, updated_user} -> {:ok, updated_user}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def reset_password_with_token(token, new_password) when is_binary(token) and is_binary(new_password) do
    with %User{} = user <- get_user_by_reset_token(token),
         :ok <- validate_reset_token_expiry(user),
         {:ok, updated_user} <- update_user_password_and_clear_token(user, new_password) do
      {:ok, updated_user}
    else
      nil -> {:error, :invalid_token}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_user_by_reset_token(token) when is_binary(token) do
    Repo.get_by(User, password_reset_token: token)
  end

  def validate_reset_token_expiry(%User{password_reset_sent_at: nil}), do: {:error, :invalid_token}
  def validate_reset_token_expiry(%User{password_reset_sent_at: sent_at}) do
    # Token expires after 1 hour
    expiry_time = DateTime.add(sent_at, 3600, :second)
    
    if DateTime.compare(DateTime.utc_now(), expiry_time) == :lt do
      :ok
    else
      {:error, :token_expired}
    end
  end

  defp update_user_password_and_clear_token(%User{} = user, new_password) do
    changeset = User.password_update_changeset(user, %{
      password: new_password,
      password_reset_token: nil,
      password_reset_sent_at: nil
    })
    
    case Repo.update(changeset) do
      {:ok, updated_user} -> {:ok, updated_user}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp check_password_reset_rate_limit(nil), do: :ok
  defp check_password_reset_rate_limit(identifier) do
    case Bacon8.Accounts.RateLimit.check_password_reset_limit(identifier) do
      :ok -> :ok
      {:error, _reason} -> {:error, :rate_limited}
    end
  end

  # ---------------------
  # User Blocking System
  # ---------------------
  
  @doc "Block a user from sending invites"
  def block_user(blocker_id, blocked_id) when blocker_id != blocked_id do
    user = get_user!(blocker_id)
    current_blocked = Map.get(user, :blocked_user_ids, [])
    
    if blocked_id in current_blocked do
      {:ok, user}
    else
      user
      |> Ecto.Changeset.change(blocked_user_ids: [blocked_id | current_blocked])
      |> Repo.update()
    end
  end
  def block_user(id, id), do: {:error, :cannot_block_self}

  @doc "Unblock a user"
  def unblock_user(blocker_id, blocked_id) do
    user = get_user!(blocker_id)
    current_blocked = Map.get(user, :blocked_user_ids, [])
    
    user
    |> Ecto.Changeset.change(blocked_user_ids: List.delete(current_blocked, blocked_id))
    |> Repo.update()
  end

  @doc "Get list of blocked users with their details"
  def list_blocked_users(user_id) do
    user = get_user!(user_id)
    blocked_ids = Map.get(user, :blocked_user_ids, [])
    
    if Enum.empty?(blocked_ids) do
      []
    else
      from(u in User,
        where: u.id in ^blocked_ids,
        select: %{id: u.id, name: u.name, email: u.email, avatar_url: u.avatar_url}
      )
      |> Repo.all()
    end
  end

  # ---------------------
  # User Preferences
  # ---------------------
  
  @doc "Update user invite preferences"
  def update_invite_preferences(user_id, attrs) do
    user = get_user!(user_id)
    
    user
    |> Ecto.Changeset.cast(attrs, [:allow_channel_invites])
    |> Repo.update()
  end

  @doc "Update user audio preferences"
  def update_audio_preferences(%User{} = user, attrs) do
    user
    |> Ecto.Changeset.cast(attrs, [:notification_sound_enabled, :master_volume])
    |> Ecto.Changeset.validate_number(:master_volume, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> Repo.update()
  end
  def update_audio_preferences(user_id, attrs) when is_binary(user_id) do
    case get_user(user_id) do
      nil -> {:error, :user_not_found}
      user -> update_audio_preferences(user, attrs)
    end
  end
end

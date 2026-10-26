defmodule Bacon8.Accounts.User do
  use Ecto.Schema
  use Arc.Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users" do
    field :email, :string
    field :name, :string
    field :password, :string, virtual: true, redact: true
    field :current_password, :string, virtual: true, redact: true
    field :password_confirmation, :string, virtual: true, redact: true
    field :password_hash, :string, redact: true
    field :confirmed_at, :utc_datetime
    field :avatar_shape, :string, default: "circle"
    field :avatar_color, :string, default: "#3B82F6"
    field :avatar_opacity, :integer, default: 100
    field :avatar_file, Bacon8.Avatar.Type
    field :avatar_url, :string
    field :is_online, :boolean, default: false
    field :is_admin, :boolean, default: false
    field :status, :string, default: "active"
    field :role, :string, default: "member"
    field :two_factor_secret, :string
    field :two_factor_enabled, :boolean, default: false
    field :two_factor_backup_codes, {:array, :string}, default: []
    field :position_x, :float, default: 400.0
    field :position_y, :float, default: 300.0
    field :last_activity, :utc_datetime
    field :bio, :string

    # Background customization - NOW ENABLED
    field :background_preference, :string, default: "galaxy"
    field :background_custom_data, :map, default: %{}

    # Blocking and notification preferences
    field :blocked_user_ids, {:array, :binary_id}, default: []
    field :notification_sound_enabled, :boolean, default: true
    field :master_volume, :float, default: 0.7

    # Email verification & security fields
    field :email_verified_at, :utc_datetime
    field :email_verification_token, :string
    field :email_verification_sent_at, :utc_datetime
    field :failed_login_attempts, :integer, default: 0
    field :locked_until, :utc_datetime
    field :password_reset_token, :string
    field :password_reset_sent_at, :utc_datetime
    field :approved_at, :utc_datetime
    field :registration_ip, :string
    field :last_login_ip, :string
    field :last_login_at, :utc_datetime
    
    # The payment provider's customer record, for card subscriptions (BACON8.md §8).
    field :stripe_customer_id, :string

    belongs_to :approved_by, __MODULE__, foreign_key: :approved_by_id, on_replace: :nilify

    has_many :posts, Bacon8.Content.Post, on_delete: :nilify_all
    has_many :comments, Bacon8.Content.Comment, on_delete: :nilify_all
    has_many :files, Bacon8.Files.UserFile, on_delete: :delete_all

    timestamps(type: :utc_datetime)
  end

  # Registration (new user) - Enhanced security validation
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :password, :registration_ip, :role, :is_admin])
    |> validate_required([:email, :password])
    |> validate_email()
    |> validate_password()
    |> validate_name()
    |> validate_inclusion(:role, ["admin", "gm", "editor", "moderator", "member", "guest", "banned"])
    |> unique_constraint(:email, message: "An account with this email already exists")
    |> put_email_verification_token()
    |> put_password_hash()
    # New users start as "pending" until email is verified
    |> put_change(:status, "pending")
  end

  # Enhanced email validation
  defp validate_email(changeset) do
    changeset
    |> validate_format(:email, ~r/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/, 
        message: "Please enter a valid email address")
    |> validate_length(:email, max: 255)
    |> update_change(:email, &String.downcase/1)
  end

  # Enhanced password validation
  defp validate_password(changeset) do
    changeset
    |> validate_length(:password, min: 8, max: 128, 
        message: "Password must be between 8 and 128 characters")
    |> validate_format(:password, ~r/[a-z]/, 
        message: "Password must contain at least one lowercase letter")
    |> validate_format(:password, ~r/[A-Z]/, 
        message: "Password must contain at least one uppercase letter")
    |> validate_format(:password, ~r/[0-9]/, 
        message: "Password must contain at least one number")
    |> validate_format(:password, ~r/[^a-zA-Z0-9]/, 
        message: "Password must contain at least one special character")
  end

  # Name validation
  defp validate_name(changeset) do
    changeset
    |> validate_length(:name, min: 2, max: 100)
    |> validate_format(:name, ~r/^[a-zA-Z0-9\-_\.]+$/, 
        message: "Name can only contain letters, numbers, hyphens, underscores, and periods (no spaces)")
    |> unique_constraint(:name, 
        name: :users_name_unique_index,
        message: "This username is already taken. Please choose a different one.")
  end

  # Generate email verification token
  defp put_email_verification_token(changeset) do
    if changeset.valid? do
      token = :crypto.strong_rand_bytes(32) |> Base.url_encode64()
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      changeset
      |> put_change(:email_verification_token, token)
      |> put_change(:email_verification_sent_at, now)
    else
      changeset
    end
  end

  # Update profile (email/name/avatar)

  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email, :avatar_shape, :avatar_color, :avatar_opacity, :avatar_url, :bio])
    |> validate_required([:name, :email])
    |> validate_format(:email, ~r/@/)
    |> validate_number(:avatar_opacity, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_length(:bio, max: 500)
    |> unique_constraint(:email)
  end

  # Admin changeset: allow updating status and correct roles
  def admin_changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email, :avatar_shape, :avatar_color, :avatar_opacity, :avatar_url, :status, :email_verified_at, :background_preference, :background_custom_data])
    |> validate_required([:name, :email])
    |> validate_format(:email, ~r/@/)
    |> validate_inclusion(:role, ["admin", "gm", "editor", "moderator", "member", "guest", "banned"])
    |> validate_inclusion(:status, ["active", "disabled", "unverified"], message: "Invalid status")
    |> validate_number(:avatar_opacity, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_inclusion(:background_preference, ["galaxy", "nebula", "starfield", "void", "gradient", "solid"])
    |> unique_constraint(:email)
  end

  # Update password only
  def password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_length(:password, min: 6)
    |> put_password_hash()
  end

  # Password change with current password verification
  def password_change_changeset(user, attrs) do
    user
    |> cast(attrs, [:current_password, :password, :password_confirmation])
    |> validate_required([:current_password, :password, :password_confirmation])
    |> validate_current_password()
    |> validate_password()
    |> validate_password_confirmation()
    |> put_password_hash()
  end

  # Validate current password
  defp validate_current_password(changeset) do
    current_password = get_change(changeset, :current_password)
    
    if current_password && changeset.data.password_hash do
      if valid_password?(changeset.data, current_password) do
        changeset
      else
        add_error(changeset, :current_password, "is incorrect")
      end
    else
      add_error(changeset, :current_password, "is required")
    end
  end

  # Validate password confirmation
  defp validate_password_confirmation(changeset) do
    password = get_change(changeset, :password)
    password_confirmation = get_change(changeset, :password_confirmation)
    
    if password && password_confirmation do
      if password == password_confirmation do
        changeset
      else
        add_error(changeset, :password_confirmation, "does not match password")
      end
    else
      changeset
    end
  end

  def role_changeset(user, attrs) do
    user
    |> cast(attrs, [:is_admin, :role])
    |> validate_required([:is_admin])
    |> validate_inclusion(:role, ["admin", "gm", "editor", "moderator", "member", "guest", "banned"])
  end

  # Avatar changeset
  def avatar_changeset(user, attrs) do
    user
    |> cast(attrs, [:avatar_shape, :avatar_color, :avatar_opacity, :avatar_url])
    |> cast_attachments(attrs, [:avatar_file])
    |> validate_number(:avatar_opacity, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
  end

  # Position changeset
  def position_changeset(user, attrs) do
    user
    |> cast(attrs, [:position_x, :position_y])
    |> validate_number(:position_x, greater_than_or_equal_to: 0)
    |> validate_number(:position_y, greater_than_or_equal_to: 0)
  end

  # Status changeset
  def status_changeset(user, attrs) do
    user
    |> cast(attrs, [:status])
  end

  # Two-factor authentication changeset
  def two_factor_changeset(user, attrs) do
    user
    |> cast(attrs, [:two_factor_secret, :two_factor_enabled, :two_factor_backup_codes])
  end

  # Password validation
  def valid_password?(%__MODULE__{password_hash: hash}, password) when is_binary(password) do
    Pbkdf2.verify_pass(password, hash)
  end

  def valid_password?(_, _), do: false

  # Two-factor authentication helpers
  def generate_two_factor_secret do
    :crypto.strong_rand_bytes(20) |> Base.encode32()
  end

  def generate_backup_codes do
    for _ <- 1..10, do: :crypto.strong_rand_bytes(4) |> Base.encode16()
  end

  # CMS Role capabilities (integrated from CMS system)
  def get_capabilities(%__MODULE__{role: role}) do
    case role do
      "administrator" -> [
        "manage_options", "edit_posts", "edit_others_posts", "edit_published_posts",
        "publish_posts", "delete_posts", "delete_others_posts", "delete_published_posts",
        "edit_pages", "edit_others_pages", "edit_published_pages", "publish_pages",
        "delete_pages", "delete_others_pages", "delete_published_pages",
        "manage_categories", "manage_links", "moderate_comments", "upload_files",
        "import", "unfiltered_html", "edit_themes", "install_themes", "update_themes",
        "delete_themes", "edit_plugins", "install_plugins", "update_plugins",
        "delete_plugins", "edit_users", "list_users", "delete_users", "promote_users",
        "remove_users", "add_users", "create_users", "edit_dashboard", "update_core",
        "list_roles", "promote_users", "edit_theme_options", "delete_site", "manage_network",
        "manage_sites", "manage_network_users", "manage_network_plugins", "manage_network_themes",
        "manage_network_options", "upgrade_network", "setup_network"
      ]
      "editor" -> [
        "edit_posts", "edit_others_posts", "edit_published_posts", "publish_posts",
        "delete_posts", "delete_others_posts", "delete_published_posts",
        "edit_pages", "edit_others_pages", "edit_published_pages", "publish_pages",
        "delete_pages", "delete_others_pages", "delete_published_pages",
        "manage_categories", "manage_links", "moderate_comments", "upload_files",
        "unfiltered_html"
      ]
      "author" -> [
        "edit_posts", "edit_published_posts", "publish_posts", "delete_posts",
        "delete_published_posts", "upload_files"
      ]
      "contributor" -> [
        "edit_posts", "delete_posts"
      ]
      "subscriber" -> [
        "read"
      ]
      _ -> []
    end
  end

  def can?(%__MODULE__{} = user, capability) do
    capability in get_capabilities(user)
  end

  # Internal helper
  defp put_password_hash(changeset) do
    if pwd = get_change(changeset, :password) do
      hash = Pbkdf2.hash_pwd_salt(pwd)
      put_change(changeset, :password_hash, hash)
    else
      changeset
    end
  end

  # Security helper functions
  def email_verified?(user), do: !is_nil(user.email_verified_at)
  def account_locked?(user), do: !is_nil(user.locked_until) && DateTime.after?(user.locked_until, DateTime.utc_now())
  def account_approved?(user), do: !is_nil(user.approved_at)

  # For dev environment - auto-verify emails from localhost/test domains
  def auto_verify_dev_emails?(email) do
    dev_domains = ["localhost", "test.com", "example.com", "dev.local"]
    domain = email |> String.split("@") |> List.last()
    Enum.member?(dev_domains, domain)
  end

  # Generate password reset token
  def password_reset_changeset(user, attrs \\ %{}) do
    token = attrs["password_reset_token"] || attrs[:password_reset_token] || 
            (:crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false))
    sent_at = attrs["password_reset_sent_at"] || attrs[:password_reset_sent_at] ||
              (DateTime.utc_now() |> DateTime.truncate(:second))
    
    user
    |> change()
    |> put_change(:password_reset_token, token)
    |> put_change(:password_reset_sent_at, sent_at)
  end

  # Update password and clear reset token
  def password_update_changeset(user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_password()
    |> put_password_hash()
    |> put_change(:password_reset_token, nil)
    |> put_change(:password_reset_sent_at, nil)
  end

  # Verify email changeset
  def verify_email_changeset(user) do
    user
    |> change()
    |> put_change(:email_verified_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> put_change(:email_verification_token, nil)
    # Activate user after email verification (unless manually disabled)
    |> put_change(:status, if(user.status == "disabled", do: "disabled", else: "active"))
  end

  # Lock account changeset
  def lock_account_changeset(user, lock_duration_minutes \\ 30) do
    locked_until = DateTime.utc_now() |> DateTime.add(lock_duration_minutes * 60, :second) |> DateTime.truncate(:second)
    user
    |> change()
    |> put_change(:locked_until, locked_until)
  end

  # Increment failed login attempts
  def increment_failed_login_changeset(user) do
    attempts = (user.failed_login_attempts || 0) + 1
    changeset = user
    |> change()
    |> put_change(:failed_login_attempts, attempts)
    
    # Lock account after 5 failed attempts
    if attempts >= 5 do
      lock_account_changeset(user)
    else
      changeset
    end
  end

  # Reset failed login attempts
  def reset_failed_login_changeset(user, login_ip \\ nil) do
    changeset = user
    |> change()
    |> put_change(:failed_login_attempts, 0)
    |> put_change(:locked_until, nil)
    |> put_change(:last_login_at, DateTime.utc_now() |> DateTime.truncate(:second))
    
    if login_ip do
      put_change(changeset, :last_login_ip, login_ip)
    else
      changeset
    end
  end
end

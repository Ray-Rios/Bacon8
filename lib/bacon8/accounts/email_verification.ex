defmodule Bacon8.Accounts.EmailVerification do
  @moduledoc """
  Handles email verification functionality with rate limiting and security features.
  
  In development, emails are sent to Mailhog (http://localhost:8025) and certain
  domains can be auto-verified for testing convenience.
  """
  
  alias Bacon8.{Repo, Accounts}
  alias Bacon8.Accounts.User
  import Ecto.Query

  # Rate limiting: max 3 verification emails per hour per email
  @max_verification_emails_per_hour 3
  @verification_token_expiry_hours 24
  @auto_verify_in_dev true

  def send_verification_email(user) do
    with :ok <- check_rate_limit(user),
         :ok <- check_existing_verification(user) do
      
      # In development, auto-verify certain domains or just log
      if @auto_verify_in_dev and Application.get_env(:bacon8, :environment) == :dev do
        handle_dev_verification(user)
      else
        send_email_via_service(user)
      end
    end
  end

  def verify_email(token) when is_binary(token) do
    query = from u in User,
      where: u.email_verification_token == ^token,
      where: u.email_verified_at |> is_nil(),
      where: u.email_verification_sent_at > ago(@verification_token_expiry_hours, "hour")

    case Repo.one(query) do
      %User{} = user ->
        user
        |> User.verify_email_changeset()
        |> Repo.update()
        |> case do
          {:ok, verified_user} ->
            {:ok, verified_user}
          {:error, changeset} ->
            {:error, "Failed to verify email: #{format_errors(changeset)}"}
        end
      
      nil ->
        {:error, "Invalid or expired verification token"}
    end
  end

  def verify_email_with_code(email, code) when is_binary(email) and is_binary(code) do
    # Find user by email with pending verification
    query = from u in User,
      where: u.email == ^email,
      where: u.email_verified_at |> is_nil(),
      where: u.email_verification_sent_at > ago(@verification_token_expiry_hours, "hour")

    case Repo.one(query) do
      %User{} = user ->
        # Generate expected code from token for comparison (works for both dev and prod)
        expected_code = if user.email_verification_token do
          user.email_verification_token
          |> String.slice(0, 6)
          |> String.to_charlist()
          |> Enum.map(&rem(&1, 10))
          |> Enum.map(&to_string/1)
          |> Enum.join()
          |> String.pad_leading(6, "0")
        else
          # No token available
          nil
        end

        if expected_code && code == expected_code do
          user
          |> User.verify_email_changeset()
          |> Repo.update()
          |> case do
            {:ok, verified_user} ->
              {:ok, verified_user}
            {:error, changeset} ->
              {:error, "Failed to verify email: #{format_errors(changeset)}"}
          end
        else
          {:error, "Invalid verification code"}
        end
      
      nil ->
        {:error, "No pending verification found for this email or verification expired"}
    end
  end

  def resend_verification_email(email) when is_binary(email) do
    case Accounts.get_user_by_email(email) do
      %User{email_verified_at: nil} = user ->
        send_verification_email(user)
      
      %User{email_verified_at: verified_at} when not is_nil(verified_at) ->
        {:error, "Email is already verified"}
      
      nil ->
        {:error, "No account found with that email address"}
    end
  end

  def verification_required?(user) do
    is_nil(user.email_verified_at) and not User.auto_verify_dev_emails?(user.email)
  end

  # Private functions

  defp check_rate_limit(user) do
    one_hour_ago = DateTime.utc_now() |> DateTime.add(-1, :hour)
    
    recent_count = from(u in User,
      where: u.email == ^user.email,
      where: u.email_verification_sent_at > ^one_hour_ago,
      select: count(u.id)
    ) |> Repo.one()

    if recent_count >= @max_verification_emails_per_hour do
      {:error, "Too many verification emails sent. Please wait before requesting another."}
    else
      :ok
    end
  end

  defp check_existing_verification(user) do
    if user.email_verified_at do
      {:error, "Email is already verified"}
    else
      :ok
    end
  end

  defp handle_dev_verification(user) do
    cond do
      User.auto_verify_dev_emails?(user.email) ->
        # Auto-verify dev emails
        user
        |> User.verify_email_changeset()
        |> Repo.update()
        |> case do
          {:ok, _verified_user} ->
            {:ok, "Email auto-verified for development (domain: #{get_domain(user.email)})"}
          {:error, changeset} ->
            {:error, format_errors(changeset)}
        end
      
      true ->
        # Log to console and send to Mailhog
        verification_url = get_verification_url(user.email_verification_token)
        
        IO.puts("""
        
        📧 DEV EMAIL VERIFICATION
        ========================
        To: #{user.email}
        Subject: Verify your account
        
        Click this link to verify your email:
        #{verification_url}
        
        Or check Mailhog at: http://localhost:8025
        ========================
        """)
        
        send_email_via_service(user)
    end
  end

  defp send_email_via_service(user) do
    # Generate a 6-digit verification code
    verification_code = generate_verification_code(user.email_verification_token)
    
    {:ok, message} = Bacon8.Email.Service.send_verification_email(user, verification_code)
    
    # Update the sent timestamp
    user
    |> Ecto.Changeset.change(email_verification_sent_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
    
    {:ok, message}
  end

  # Generate a consistent 6-digit code from the token
  defp generate_verification_code(token) when is_binary(token) do
    token
    |> String.slice(0, 6)
    |> String.to_charlist()
    |> Enum.map(&rem(&1, 10))
    |> Enum.map(&to_string/1)
    |> Enum.join()
    |> String.pad_leading(6, "0")
  end

  defp get_verification_url(token) do
    base_url = Application.get_env(:bacon8, Bacon8Web.Endpoint)[:url][:host] || "localhost"
    port = Application.get_env(:bacon8, Bacon8Web.Endpoint)[:http][:port] || 4000
    "http://#{base_url}:#{port}/auth/verify-email?token=#{token}"
  end

  defp get_domain(email) do
    email |> String.split("@") |> List.last()
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
    |> Enum.join("; ")
  end
end
defmodule Bacon8.Email.Service do
  @moduledoc """
  Email service for sending transactional emails via Swoosh.
  Uses async sending to prevent blocking the UI.
  """

  require Logger
  alias Bacon8.Mailer
  alias Bacon8.Emails

  @doc """
  Sends verification email asynchronously.
  Returns immediately, email is sent in background.
  """
  def send_verification_email(user, verification_code) do
    Logger.info("Queueing verification email to #{user.email}")
    
    # Send async to prevent blocking the UI
    Task.Supervisor.start_child(Bacon8.EmailTaskSupervisor, fn ->
      do_send_verification_email(user, verification_code)
    end)
    
    {:ok, "Verification email queued"}
  end

  defp do_send_verification_email(user, verification_code) do
    Logger.info("Sending verification email to #{user.email}")
    
    email = Emails.verification_email(user, verification_code)
    
    case Mailer.deliver(email) do
      {:ok, _metadata} ->
        Logger.info("Verification email sent successfully to #{user.email}")
        :ok
      {:error, reason} ->
        Logger.error("Failed to send verification email to #{user.email}: #{inspect(reason)}")
        :error
    end
  end

  @doc """
  Sends password reset email asynchronously.
  Returns immediately, email is sent in background.
  """
  def send_password_reset_email(user, reset_token) do
    Logger.info("Queueing password reset email to #{user.email}")
    
    reset_url = get_password_reset_url(reset_token)
    
    # Send async to prevent blocking the UI
    Task.Supervisor.start_child(Bacon8.EmailTaskSupervisor, fn ->
      do_send_password_reset_email(user, reset_url)
    end)
    
    {:ok, "Password reset email queued"}
  end

  defp do_send_password_reset_email(user, reset_url) do
    Logger.info("Sending password reset email to #{user.email}")
    
    email = Emails.password_reset_email(user, reset_url)
    
    case Mailer.deliver(email) do
      {:ok, _metadata} ->
        Logger.info("Password reset email sent successfully to #{user.email}")
        :ok
      {:error, reason} ->
        Logger.error("Failed to send password reset email to #{user.email}: #{inspect(reason)}")
        :error
    end
  end

  # Helper to build password reset URL
  defp get_password_reset_url(token) do
    base_url = case get_env() do
      "prod" ->
        url_config = Application.get_env(:bacon8, Bacon8Web.Endpoint)[:url]
        scheme = url_config[:scheme] || "https"
        host = url_config[:host] || "your-domain.com"
        port = url_config[:port]
        
        if port && port != 443 && port != 80 do
          "#{scheme}://#{host}:#{port}"
        else
          "#{scheme}://#{host}"
        end
      _ ->
        host = Application.get_env(:bacon8, Bacon8Web.Endpoint)[:url][:host] || "localhost"
        port = Application.get_env(:bacon8, Bacon8Web.Endpoint)[:http][:port] || 4000
        "http://#{host}:#{port}"
    end
    
    "#{base_url}/reset-password?token=#{token}"
  end

  defp get_env do
    System.get_env("MIX_ENV") || "dev"
  end
end

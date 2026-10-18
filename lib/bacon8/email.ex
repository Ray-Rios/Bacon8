defmodule Bacon8.Email do
  @moduledoc """
  Main email interface module that wraps the Email.Service functionality.
  """

  alias Bacon8.Email.Service

  def send_password_reset_email(%{password_reset_token: token} = user) when not is_nil(token) do
    {:ok, _} = Service.send_password_reset_email(user, token)
    {:ok, "Password reset email sent"}
  end

  def send_password_reset_email(_user) do
    {:error, "No password reset token found"}
  end

  def send_verification_email(user, verification_code) do
    Service.send_verification_email(user, verification_code)
  end
end
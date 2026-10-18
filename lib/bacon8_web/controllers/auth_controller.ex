defmodule Bacon8Web.AuthController do
  use Bacon8Web, :controller
  alias Bacon8.Accounts

  # Called when login succeeds
  def login_success(conn, %{"user_id" => user_id} = params) do
    case Accounts.get_user(user_id) do
      nil ->
        conn
        |> put_flash(:error, "User not found")
        |> redirect(to: ~p"/login")

      user ->
        conn = conn
               |> put_session(:user_id, user.id)
               |> configure_session(renew: false)

        # If JWT token is provided, store it for unified API access
        conn = case params["token"] do
          nil -> conn
          token -> put_session(conn, :jwt_token, token)
        end

        conn
        |> put_flash(:info, "Successfully logged in! You now have unified access to all features.")
        |> redirect(to: ~p"/games")
    end
  end

  # Logs out the user and returns them to homepage
  def logout(conn, params) do
    {flash_type, message} = case params["reason"] do
      "suspended" -> {:error, "Your account has been suspended."}
      _ -> {:info, "You have been logged out"}
    end

    conn
    |> clear_session()
    |> put_flash(flash_type, message)
    |> redirect(to: ~p"/")
  end
end

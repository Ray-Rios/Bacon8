defmodule Bacon8Web.AuthController do
  use Bacon8Web, :controller
  alias Bacon8.Accounts

  # The sign-in page (AuthLive) checks the password inside a LiveView, which cannot write the
  # session cookie, so it sends the browser here to have the session set. What proves the
  # password was checked is the hand-off: a token AuthLive signs for that user, good for
  # @handoff_max_age seconds. Until 2026-11-15 this action trusted the `user_id` in the URL by
  # itself, so anyone who knew an account's id (ids appear in pages and API answers) could open
  # /auth/login_success?user_id=<id> and be signed in as that account, admins included.
  @handoff_salt "login handoff"
  @handoff_max_age 60

  @doc "The hand-off token for `user_id` (signed by the sign-in page once the password is checked)."
  def handoff_token(user_id) when is_binary(user_id) do
    Phoenix.Token.sign(Bacon8Web.Endpoint, @handoff_salt, user_id)
  end

  # Called when login succeeds
  def login_success(conn, %{"user_id" => user_id, "handoff" => handoff} = params)
      when is_binary(user_id) and is_binary(handoff) do
    with {:ok, ^user_id} <- Phoenix.Token.verify(Bacon8Web.Endpoint, @handoff_salt, handoff, max_age: @handoff_max_age),
         %Bacon8.Accounts.User{} = user <- Accounts.get_user(user_id) do
      # a new session id on sign-in (a cookie planted before the sign-in is worth nothing after it)
      conn =
        conn
        |> configure_session(renew: true)
        |> put_session(:user_id, user.id)

      # The API token for the page's own calls, kept only when it is this user's
      conn =
        case params["token"] do
          token when is_binary(token) ->
            case Bacon8.Auth.Guardian.decode_and_verify(token) do
              {:ok, %{"sub" => ^user_id}} -> put_session(conn, :jwt_token, token)
              _ -> conn
            end

          _ ->
            conn
        end

      conn
      |> put_flash(:info, "Successfully logged in! You now have unified access to all features.")
      |> redirect(to: ~p"/games")
    else
      _ -> login_refused(conn)
    end
  end

  def login_success(conn, _params), do: login_refused(conn)

  defp login_refused(conn) do
    conn
    |> put_flash(:error, "Please sign in again.")
    |> redirect(to: ~p"/login")
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

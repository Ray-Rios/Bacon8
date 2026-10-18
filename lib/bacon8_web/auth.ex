defmodule Bacon8Web.Auth do
  import Plug.Conn
  import Phoenix.Controller
  alias Bacon8.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    user = case get_session(conn, :user_token) do
      nil -> 
        # Fallback to user_id approach
        case get_session(conn, :user_id) do
          nil -> nil
          user_id -> Accounts.get_user(user_id)
        end
      user_token -> 
        Accounts.get_user_by_session_token(user_token)
    end
    assign(conn, :current_user, user)
  end

  def log_in_user(conn, user) do
    token = Accounts.generate_user_session_token(user)
    
    conn
    |> renew_session()
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, "users_sessions:#{Base.url_encode64(token)}")
  end

  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_user_session_token(user_token)
    
    conn
    |> renew_session()
    |> delete_session(:user_token)
    |> delete_session(:live_socket_id)
  end

  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> redirect(to: "/login")
      |> halt()
    end
  end

  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    socket = assign_current_user(socket, session)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You must log in to access this page.")
        |> Phoenix.LiveView.redirect(to: "/login")

      {:halt, socket}
    end
  end

  def on_mount(:maybe_authenticated, _params, session, socket) do
    {:cont, assign_current_user(socket, session)}
  end

  def on_mount(:ensure_admin, _params, session, socket) do
    socket = assign_current_user(socket, session)

    cond do
      is_nil(socket.assigns.current_user) ->
        socket =
          socket
          |> Phoenix.LiveView.put_flash(:error, "You must log in to access this page.")
          |> Phoenix.LiveView.redirect(to: "/login")

        {:halt, socket}

      not socket.assigns.current_user.is_admin ->
        socket =
          socket
          |> Phoenix.LiveView.put_flash(:error, "You must be an admin to access this page.")
          |> Phoenix.LiveView.redirect(to: "/")

        {:halt, socket}

      true ->
        {:cont, socket}
    end
  end

  defp assign_current_user(socket, session) do
    Phoenix.Component.assign_new(socket, :current_user, fn ->
      case session["user_token"] do
        nil ->
          # Fallback to user_id approach
          case session["user_id"] do
            nil -> nil
            user_id -> Accounts.get_user(user_id)
          end
        user_token ->
          Accounts.get_user_by_session_token(user_token)
      end
    end)
  end
end
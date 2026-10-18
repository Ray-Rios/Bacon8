defmodule Bacon8Web.UserAuth do
  @moduledoc """
  Handles user authentication for LiveViews.
  """

  use Phoenix.Component
  import Phoenix.LiveView
  require Logger

  alias Bacon8.Accounts

  @doc """
  LiveView `on_mount` hook.

  Modes:
    * `:default` → assigns current_user if present (public pages).
    * `:require_authenticated_user` → assigns and redirects if missing.
    * `:require_admin_user` → assigns and redirects if missing or not admin.
  """
  def on_mount(:default, _params, session, socket) do
    socket = assign_current_user(socket, session)
    user = socket.assigns.current_user
    
    # For authenticated users, always check status and subscribe to disconnect events
    if user do
      if user.status != "active" or user.role == "banned" do
        {:halt,
         socket
         |> put_flash(:error, "Your account has been suspended.")
         |> logout()}
      else
        socket = setup_disconnect_subscription(socket, user)
        {:cont, socket}
      end
    else
      {:cont, socket}
    end
  end

  def on_mount(:require_authenticated_user, _params, session, socket) do
    socket = assign_current_user(socket, session)
    user = socket.assigns.current_user

    cond do
      # Check if user is banned or disabled
      user && (user.status != "active" or user.role == "banned") ->
        {:halt,
         socket
         |> put_flash(:error, "Your account has been suspended.")
         |> logout()}

      user ->
        socket = setup_disconnect_subscription(socket, user)
        {:cont, socket}

      true ->
        {:halt, push_navigate(socket, to: "/login")}
    end
  end

  def on_mount(:require_admin_user, _params, session, socket) do
    socket = assign_current_user(socket, session)
    user = socket.assigns.current_user

    cond do
      user == nil ->
        {:halt, push_navigate(socket, to: "/login")}

      # Check if user is banned or disabled (even if they were admin)
      user.status != "active" or user.role == "banned" ->
        {:halt,
         socket
         |> put_flash(:error, "Your account has been suspended.")
         |> logout()}

      not user.is_admin ->
        {:halt, push_navigate(socket, to: "/")}

      true ->
        socket = setup_disconnect_subscription(socket, user)
        {:cont, socket}
    end
  end

  @doc """
  Logs out the current user from a LiveView.

  - Clears `:user_id` from the session
  - Removes `:current_user`
  - Redirects to `/login`
  """
  def logout(socket) do
    socket
    |> Phoenix.LiveView.push_event("clear-session", %{}) # JS hook can clear local storage if used
    |> assign(:current_user, nil)
    |> Phoenix.LiveView.redirect(to: "/auth/logout") # Use controller logout to clear cookie
  end

  # --- Helpers ---

  # Sets up PubSub subscription and hook for disconnect events
  # Only attaches hook once per socket lifecycle (tracked via assign)
  defp setup_disconnect_subscription(socket, user) do
    # Only set up once - check if we've already done this
    already_attached = socket.assigns[:auth_hook_attached] == true
    
    if already_attached do
      socket
    else
      if connected?(socket) do
        Logger.debug("UserAuth: subscribing user #{user.id} to disconnect topic")
        # Use Phoenix.PubSub directly for cluster-wide message delivery
        Phoenix.PubSub.subscribe(Bacon8.PubSub, "user_sessions:#{user.id}")
      end
      
      socket
      |> assign(:auth_hook_attached, true)
      |> attach_hook(:auth_security, :handle_info, &handle_auth_info/2)
    end
  end

  # Handle Phoenix.PubSub broadcasts (plain map format)
  defp handle_auth_info(%{event: "disconnect"} = msg, socket) do
    require Logger
    user_id = socket.assigns.current_user && socket.assigns.current_user.id
    Logger.info("Received disconnect broadcast for user #{user_id}: #{inspect(msg)}")
    {:halt,
     socket
     |> put_flash(:error, "Your session has been terminated.")
     |> logout()}
  end
  
  # Fallback for Phoenix.Socket.Broadcast format (from Endpoint.broadcast)
  defp handle_auth_info(%Phoenix.Socket.Broadcast{topic: "user_sessions:" <> _, event: "disconnect"}, socket) do
    require Logger
    Logger.info("Received disconnect broadcast (Broadcast struct) for user #{socket.assigns.current_user && socket.assigns.current_user.id}")
    {:halt,
     socket
     |> put_flash(:error, "Your session has been terminated.")
     |> logout()}
  end
  
  defp handle_auth_info(_, socket), do: {:cont, socket}

  defp assign_current_user(socket, %{"user_id" => user_id}) do
    assign_new(socket, :current_user, fn ->
      Accounts.get_user(user_id)
    end)
  end

  defp assign_current_user(socket, _session) do
    assign_new(socket, :current_user, fn -> nil end)
  end
end

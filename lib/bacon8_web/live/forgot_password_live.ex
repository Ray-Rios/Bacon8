defmodule Bacon8Web.ForgotPasswordLive do
  use Bacon8Web, :live_view
  alias Bacon8.Accounts
  
  def mount(_params, session, socket) do
    current_user = maybe_fetch_user(session["user_id"])
    
    # Store IP address during mount since connect_info is only available here
    # Use x-forwarded-for header when behind proxy/load balancer
    ip_address = get_client_ip_from_socket(socket)

    # If user is already logged in, redirect to desktop
    if current_user do
      {:ok, redirect(socket, to: ~p"/games")}
    else
      form_data = %{}
      form = to_form(form_data, as: "forgot_password")
      
      {:ok,
       assign(socket,
         current_user: current_user,
         form: form,
         form_data: form_data,
         errors: [],
         loading: false,
         ip_address: ip_address,
         success_message: nil,
         page_title: "Forgot Password"
       )}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  def handle_event("validate", %{"forgot_password" => params}, socket) do
    form_data = Map.merge(socket.assigns.form_data, params)
    form = to_form(form_data, as: "forgot_password")
    
    {:noreply, assign(socket, form: form, form_data: form_data)}
  end

  def handle_event("submit", %{"forgot_password" => params}, socket) do
    email_or_username = String.trim(params["email_or_username"] || "")
    ip_address = socket.assigns.ip_address

    # Set loading state
    socket = assign(socket, loading: true)
    
    # Process forgot password request
    case Accounts.send_password_reset_email(email_or_username, ip_address) do
      {:ok, _message} ->
        {:noreply,
         socket
         |> assign(loading: false, success_message: "If an account with that email/username exists, you should receive an email with instructions shortly.")
        }
      {:error, :rate_limited} ->
        {:noreply,
         socket
         |> assign(loading: false)
         |> put_flash(:error, "Too many password reset attempts. Please wait before trying again.")
        }
      {:error, message} ->
        {:noreply,
         socket
         |> assign(loading: false)
         |> put_flash(:error, message)
        }
    end
  end

  defp maybe_fetch_user(nil), do: nil
  defp maybe_fetch_user(user_id) when is_binary(user_id) do
    case Bacon8.Accounts.get_user(user_id) do
      nil -> nil
      user -> user
    end
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center px-4 sm:px-6 lg:px-8 relative z-10">
      <div class="auth-glass-panel rounded-xl shadow-2xl p-8 max-w-md w-full space-y-8">
        <!-- Back to Home Link -->
        <div class="text-left">
          <.link 
            navigate={~p"/"} 
            class="inline-flex items-center text-blue-400 hover:text-blue-300 transition-colors text-sm"
          >
            <svg class="w-4 h-4 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7"></path>
            </svg>
            Back to Home
          </.link>
        </div>
        
        <div class="text-center">
          <h2 class="mt-6 text-3xl font-extrabold text-white">
            Forgot your password?
          </h2>
          <p class="mt-2 text-sm text-gray-300">
            Enter your email address or username and we'll send you a link to reset your password.
          </p>
        </div>

        <%= if @success_message do %>
          <div class="bg-green-800 border border-green-600 text-green-200 px-4 py-3 rounded-lg mb-6">
            <%= @success_message %>
          </div>
          <div class="text-center">
            <p class="text-gray-400">
              Remember your password? 
              <.link navigate={~p"/login"} class="text-blue-400 hover:text-blue-300 transition-colors duration-300">
                Sign in
              </.link>
            </p>
          </div>
        <% else %>
          
          <.form 
            for={@form} 
            phx-submit="submit" 
            phx-change="validate"
            class="space-y-6"
          >
            <div>
              <label for="forgot_password_email_or_username" class="block text-sm font-medium text-gray-300 mb-2">
                Email Address or Username
              </label>
              <input 
                type="text" 
                name="forgot_password[email_or_username]" 
                id="forgot_password_email_or_username"
                value={@form_data["email_or_username"] || ""}
                required
                class="w-full px-4 py-3 glass-dark border border-gray-600 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all duration-300"
                placeholder="Enter your email or username"
              />
            </div>
            
            <button 
              type="submit"
              disabled={@loading}
              class={"w-full bg-gradient-to-r from-blue-600 to-purple-600 hover:from-blue-700 hover:to-purple-700 text-white font-medium py-3 rounded-lg transition-all duration-300 ease-in-out transform hover:scale-105 #{if @loading, do: "opacity-50 cursor-not-allowed", else: ""}"}
            >
              <%= if @loading do %>
                <div class="flex items-center justify-center">
                  <svg class="animate-spin -ml-1 mr-3 h-5 w-5 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                    <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                    <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                  </svg>
                  Sending Reset Link...
                </div>
              <% else %>
                Send Reset Link
              <% end %>
            </button>
          </.form>
          
          <div class="mt-6 text-center">
            <p class="text-gray-400">
              Remember your password? 
              <.link navigate={~p"/login"} class="text-blue-400 hover:text-blue-300 transition-colors duration-300">
                Sign in
              </.link>
            </p>
          </div>
        
        <% end %>
      </div>
    </div>
    """
  end

  # Extract client IP from socket, preferring x-forwarded-for header when behind proxy
  defp get_client_ip_from_socket(socket) do
    # First try x-forwarded-for header (set by load balancer/proxy)
    case get_connect_info(socket, :x_headers) do
      headers when is_list(headers) ->
        case List.keyfind(headers, "x-forwarded-for", 0) do
          {_, forwarded_for} ->
            # x-forwarded-for can contain multiple IPs: "client, proxy1, proxy2"
            # The first one is the original client IP
            forwarded_for
            |> String.split(",")
            |> List.first()
            |> String.trim()
          nil ->
            get_peer_ip(socket)
        end
      _ ->
        get_peer_ip(socket)
    end
  end

  defp get_peer_ip(socket) do
    case get_connect_info(socket, :peer_data) do
      %{address: {a, b, c, d}} -> "#{a}.#{b}.#{c}.#{d}"
      %{address: {a, b, c, d, e, f, g, h}} -> 
        "#{Integer.to_string(a, 16)}:#{Integer.to_string(b, 16)}:#{Integer.to_string(c, 16)}:#{Integer.to_string(d, 16)}:#{Integer.to_string(e, 16)}:#{Integer.to_string(f, 16)}:#{Integer.to_string(g, 16)}:#{Integer.to_string(h, 16)}"
      _ -> "unknown"
    end
  end
end
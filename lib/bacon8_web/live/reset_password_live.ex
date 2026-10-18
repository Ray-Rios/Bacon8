defmodule Bacon8Web.ResetPasswordLive do
  use Bacon8Web, :live_view
  alias Bacon8.Accounts
  
  def mount(%{"token" => token}, session, socket) do
    current_user = maybe_fetch_user(session["user_id"])

    # If user is already logged in, redirect to desktop
    if current_user do
      {:ok, redirect(socket, to: ~p"/games")}
    else
      # Validate the token first
      case validate_reset_token(token) do
        {:ok, user} ->
          form_data = %{}
          form = to_form(form_data, as: "reset_password")
          
          {:ok,
           assign(socket,
             current_user: current_user,
             form: form,
             form_data: form_data,
             errors: [],
             loading: false,
             reset_token: token,
             user: user,
             success: false,
             page_title: "Reset Password"
           )}
        {:error, reason} ->
          message = case reason do
            :invalid_token -> "The password reset link is invalid."
            :token_expired -> "The password reset link has expired. Please request a new one."
            _ -> "The password reset link is invalid or has expired."
          end
          
          {:ok,
           socket
           |> put_flash(:error, message)
           |> assign(
             current_user: current_user,
             invalid_token: true,
             page_title: "Reset Password"
           )}
      end
    end
  end

  def mount(_params, session, socket) do
    _current_user = maybe_fetch_user(session["user_id"])
    
    # If no token provided, redirect to forgot password page
    {:ok,
     socket
     |> put_flash(:error, "Invalid password reset link.")
     |> redirect(to: ~p"/forgot-password")}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  def handle_event("validate", %{"reset_password" => params}, socket) do
    form_data = Map.merge(socket.assigns.form_data, params)
    form = to_form(form_data, as: "reset_password")
    
    errors = validate_password_form(form_data)
    
    {:noreply, assign(socket, form: form, form_data: form_data, errors: errors)}
  end

  def handle_event("submit", %{"reset_password" => params}, socket) do
    password = String.trim(params["password"] || "")
    _password_confirmation = String.trim(params["password_confirmation"] || "")
    token = socket.assigns.reset_token

    errors = validate_password_form(params)

    if Enum.empty?(errors) do
      # Set loading state
      socket = assign(socket, loading: true)
      
      # Reset the password
      case Accounts.reset_password_with_token(token, password) do
        {:ok, _user} ->
          {:noreply,
           socket
           |> assign(loading: false, success: true)
           |> put_flash(:info, "Your password has been reset successfully. You can now log in with your new password.")
          }
        {:error, :invalid_token} ->
          {:noreply,
           socket
           |> assign(loading: false)
           |> put_flash(:error, "The password reset link is invalid.")
          }
        {:error, :token_expired} ->
          {:noreply,
           socket
           |> assign(loading: false)
           |> put_flash(:error, "The password reset link has expired. Please request a new one.")
          }
        {:error, %Ecto.Changeset{} = changeset} ->
          errors = extract_changeset_errors(changeset)
          {:noreply,
           socket
           |> assign(loading: false, errors: errors)
          }
        {:error, message} ->
          {:noreply,
           socket
           |> assign(loading: false)
           |> put_flash(:error, message)
          }
      end
    else
      {:noreply, assign(socket, errors: errors)}
    end
  end

  defp validate_reset_token(token) when is_binary(token) do
    case Accounts.get_user_by_reset_token(token) do
      nil -> {:error, :invalid_token}
      user -> 
        case Accounts.validate_reset_token_expiry(user) do
          :ok -> {:ok, user}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp validate_password_form(params) do
    password = String.trim(params["password"] || "")
    password_confirmation = String.trim(params["password_confirmation"] || "")
    
    errors = []
    
    errors = if String.length(password) < 8 do
      ["Password must be at least 8 characters long" | errors]
    else
      errors
    end
    
    errors = if password != password_confirmation do
      ["Password confirmation does not match" | errors]
    else
      errors
    end
    
    errors = if String.length(password) == 0 do
      ["Password is required" | errors]
    else
      errors
    end
    
    Enum.reverse(errors)
  end

  defp extract_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, messages} ->
      "#{Phoenix.Naming.humanize(field)} #{Enum.join(messages, ", ")}"
    end)
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
    <div class="min-h-screen bg-gradient-to-br from-gray-900 via-purple-900 to-blue-900 flex items-center justify-center px-4 sm:px-6 lg:px-8">
      <div class="max-w-md w-full space-y-8">
        <%= if assigns[:invalid_token] do %>
          <div class="text-center">
            <h2 class="mt-6 text-3xl font-extrabold text-white">
              Invalid Reset Link
            </h2>
            <p class="mt-2 text-sm text-gray-300">
              The password reset link is invalid or has expired.
            </p>
            <div class="mt-6">
              <.link navigate={~p"/forgot-password"} class="text-blue-400 hover:text-blue-300 transition-colors duration-300">
                Request a new password reset link
              </.link>
            </div>
          </div>
        <% else %>
          <%= if @success do %>
            <div class="text-center">
              <h2 class="mt-6 text-3xl font-extrabold text-white">
                Password Reset Successful!
              </h2>
              <p class="mt-2 text-sm text-gray-300">
                Your password has been updated successfully.
              </p>
              <div class="mt-6">
                <.link navigate={~p"/login"} class="w-full bg-gradient-to-r from-blue-600 to-purple-600 hover:from-blue-700 hover:to-purple-700 text-white font-medium py-3 px-6 rounded-lg transition-all duration-300 ease-in-out transform hover:scale-105 inline-block text-center">
                  Continue to Login
                </.link>
              </div>
            </div>
          <% else %>
            <div class="text-center">
              <h2 class="mt-6 text-3xl font-extrabold text-white">
                Reset Your Password
              </h2>
              <p class="mt-2 text-sm text-gray-300">
                Enter your new password below.
              </p>
            </div>

            <%= if not Enum.empty?(@errors) do %>
              <div class="bg-red-800 border border-red-600 text-red-200 px-4 py-3 rounded-lg mb-6">
                <ul class="list-disc list-inside">
                  <%= for error <- @errors do %>
                    <li><%= error %></li>
                  <% end %>
                </ul>
              </div>
            <% end %>

            <div class="glass-dark bg-opacity-50 backdrop-blur-lg rounded-xl shadow-2xl p-8 border border-gray-700">
              <.form 
                for={@form} 
                phx-submit="submit" 
                phx-change="validate"
                class="space-y-6"
              >
                <div>
                  <label for="reset_password_password" class="block text-sm font-medium text-gray-300 mb-2">
                    New Password
                  </label>
                  <input 
                    type="password" 
                    name="reset_password[password]" 
                    id="reset_password_password"
                    value={@form_data["password"] || ""}
                    required
                    class="w-full px-4 py-3 glass-dark border border-gray-600 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all duration-300"
                    placeholder="Enter your new password"
                  />
                </div>

                <div>
                  <label for="reset_password_password_confirmation" class="block text-sm font-medium text-gray-300 mb-2">
                    Confirm New Password
                  </label>
                  <input 
                    type="password" 
                    name="reset_password[password_confirmation]" 
                    id="reset_password_password_confirmation"
                    value={@form_data["password_confirmation"] || ""}
                    required
                    class="w-full px-4 py-3 glass-dark border border-gray-600 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all duration-300"
                    placeholder="Confirm your new password"
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
                      Updating Password...
                    </div>
                  <% else %>
                    Update Password
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
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end
end
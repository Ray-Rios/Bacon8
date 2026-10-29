defmodule Bacon8Web.AuthLive do
  use Bacon8Web, :live_view
  alias Bacon8.Accounts
  alias Bacon8.Auth.Guardian
  require Logger


  # ----------------
  # Mount
  # ----------------
  def mount(_params, session, socket) do
    current_user = maybe_fetch_user(session["user_id"])
    
    # Store IP address and user agent during mount since connect_info is only available here
    # Use x-forwarded-for header when behind proxy/load balancer, fallback to peer_data
    ip_address = get_client_ip_from_socket(socket)
    
    user_agent = case get_connect_info(socket, :user_agent) do
      nil -> "Unknown"
      ua -> ua
    end

    # If user is already logged in, redirect to desktop
    if current_user do
      # Check if user is banned/disabled before redirecting
      if current_user.status != "active" or current_user.role == "banned" do
        # If banned, force logout via controller to clear session
        {:ok, 
         socket
         |> redirect(to: "/auth/logout?reason=suspended")}
      else
        {:ok, redirect(socket, to: ~p"/games")}
      end
    else
      form_data = %{}
      form = to_form(form_data, as: "user")
      
      {:ok,
       assign(socket,
         current_user: current_user,
         form: form,
         form_data: form_data,  # Track form data separately
         errors: [],
         action: :login,
         loading: false,
         ip_address: ip_address,
         user_agent: user_agent
       )}
    end
  end

  # ----------------
  # Handle URL params with email verification routes
  # ----------------
  def handle_params(params, uri, socket) do
    action =
      case URI.parse(uri).path do
        "/register" -> :register
        "/login" -> :login
        "/auth/verify" -> :verify_code
        "/auth/verify-email" -> :verify_email
        "/auth/resend-verification" -> :resend_verification
        _ -> :login
      end

    socket = case action do
      :verify_email ->
        handle_email_verification(socket, params)
      :verify_code ->
        # Handle verification code page setup
        handle_verify_code_setup(socket, params)
      _ ->
        socket
    end

    page_title = case action do
      :login -> "Sign In"
      :register -> "Register"
      :verify_code -> "Verify Email"
      :verify_email -> "Email Verification"
      :resend_verification -> "Resend Verification"
    end

    {:noreply, assign(socket, action: action, page_title: page_title)}
  end

  defp handle_email_verification(socket, %{"token" => token}) do
    case Accounts.verify_user_email(token) do
      {:ok, user} ->
        socket
        |> put_flash(:info, "Email verified successfully! You can now log in.")
        |> assign(verified_user: user)
      {:error, message} ->
        socket
        |> put_flash(:error, message)
    end
  end

  defp handle_email_verification(socket, _params) do
    socket
    |> put_flash(:error, "Invalid verification link")
  end

  defp handle_verify_code_setup(socket, params) do
    # Get email from URL params (passed from registration)
    email = params["email"]
    verification_code = params["code"] # For dev environment
    
    socket
    |> assign(
      verification_email: email,
      verification_code_for_dev: verification_code,
      verification_form: to_form(%{}, as: "verification")
    )
  end

  # ----------------
  # Handle submit (updated to work with plain HTML form)
  # ----------------
  def handle_event("submit", %{"user" => user_params}, socket) do
    # Get form data directly from submit params
    email = String.trim(user_params["email"] || "")
    password = user_params["password"] || ""
    
    # Store the form data for potential error state preservation
    form_data = user_params
    form = to_form(form_data, as: "user")
    socket = assign(socket, form_data: form_data, form: form)
    
    cond do
      email == "" ->
        {:noreply, 
         socket
         |> put_flash(:error, "Email or username is required")
         |> assign(errors: ["Email or username is required"], loading: false)}
      
      password == "" ->
        {:noreply, 
         socket
         |> put_flash(:error, "Password is required")
         |> assign(errors: ["Password is required"], loading: false)}
      
      true ->
        # Set loading state
        socket = assign(socket, loading: true)
        
        case socket.assigns.action do
          :login -> do_login(socket, user_params)
          :register -> do_register(socket, user_params)
        end
    end
  end

  # Email verification actions
  def handle_event("verify_code", %{"verification" => verification_params}, socket) do
    code = verification_params["code"]
    # Use email from form if not already in socket assigns (for direct navigation to verify page)
    email = socket.assigns.verification_email || verification_params["email"]
    
    if !email do
      {:noreply,
       socket
       |> put_flash(:error, "Please provide your email address")
       |> assign(verification_form: to_form(%{}, as: "verification"))}
    else
      case Accounts.verify_user_with_code(email, code) do
        {:ok, _user} ->
          {:noreply,
           socket
           |> put_flash(:info, "Email verified successfully! You can now log in.")
           |> redirect(to: ~p"/login")}
        {:error, message} ->
          {:noreply,
           socket
           |> put_flash(:error, message)
           |> assign(verification_form: to_form(%{}, as: "verification"))}
      end
    end
  end

  # Handle device fingerprint from JavaScript hook
  def handle_event("device_fingerprint", %{"fingerprint" => fingerprint, "platform" => platform, "userAgent" => user_agent}, socket) do
    Logger.info("Received device fingerprint: #{fingerprint}, Platform: #{platform}, UserAgent: #{user_agent}")
    
    socket = assign(socket, device_fingerprint: fingerprint)
    {:noreply, socket}
  end

  def handle_event("resend_verification", %{"email" => email}, socket) do
    case Accounts.resend_verification_email(email) do
      {:ok, message} ->
        {:noreply, put_flash(socket, :info, message)}
      {:error, error} ->
        {:noreply, put_flash(socket, :error, error)}
    end
  end

  def handle_event("resend_verification", _params, socket) do
    {:noreply, put_flash(socket, :error, "Please enter your email address")}
  end

  # ----------------
  # Enhanced login with security features - Accept email or username
  # ----------------
  defp do_login(socket, %{"email" => identifier, "password" => password, "device_fingerprint" => fingerprint} = _params) do
    ip_address = socket.assigns.ip_address
    
    # Log for debugging
    require Logger
    Logger.info("Login attempt - IP: #{ip_address}, Email: #{identifier}, Fingerprint: #{inspect(fingerprint)}")
    
    # Wrap security check in try-rescue to catch database errors
    try do
      # Check security system first (rate limiting + blocklist)
      case Bacon8.Security.check_login_security(Bacon8.Security.throttle_key(ip_address, identifier), fingerprint, ip_address) do
        {:ok, :allowed} ->
          Logger.info("Security check passed, proceeding with authentication")
          # Proceed with authentication
          perform_login(socket, identifier, password, ip_address, fingerprint)
        
        {:error, reason} ->
          Logger.warning("Security check failed: #{inspect(reason)}")
          handle_security_error(socket, reason)
      end
    rescue
      e ->
        Logger.error("Security system error: #{inspect(e)}")
        Logger.error(Exception.format(:error, e, __STACKTRACE__))
        
        # If security system fails, show error to user but don't crash
        socket
        |> put_flash(:error, "Security system unavailable. Please contact the administrator.")
        |> assign(errors: ["Security system error. Please try again later or contact support."])
        |> then(&{:noreply, &1})
    end
  end
  
  # Handle old calls without device_fingerprint (backward compatibility)
  defp do_login(socket, %{"email" => _identifier, "password" => _password} = params) do
    # Get device_fingerprint or default to nil if empty
    fingerprint = case Map.get(params, "device_fingerprint", nil) do
      "" -> nil
      nil -> nil
      fp -> fp
    end
    
    do_login(socket, Map.put(params, "device_fingerprint", fingerprint))
  end
  
  defp handle_security_error(socket, :blocked) do
    form_data = Map.put(socket.assigns.form_data, "password", "")
    form = to_form(form_data, as: "user")
    
    {:noreply,
     socket
     |> assign(loading: false, form_data: form_data)
     |> put_flash(:error, "Access denied. Please contact support.")
     |> assign(form: form, errors: ["Access blocked"])}
  end
  
  defp handle_security_error(socket, {:rate_limited, seconds}) do
    form_data = Map.put(socket.assigns.form_data, "password", "")
    form = to_form(form_data, as: "user")
    
    minutes = div(seconds, 60)
    message = if minutes > 0 do
      "Too many failed attempts. Please wait #{minutes} minute(s) before trying again."
    else
      "Too many failed attempts. Please wait #{seconds} second(s) before trying again."
    end
    
    {:noreply,
     socket
     |> assign(loading: false, form_data: form_data)
     |> put_flash(:error, message)
     |> assign(form: form, errors: [message])}
  end
  
  defp handle_security_error(socket, reason) do
    form_data = Map.put(socket.assigns.form_data, "password", "")
    form = to_form(form_data, as: "user")
    
    {:noreply,
     socket
     |> assign(loading: false, form_data: form_data)
     |> put_flash(:error, "Security check failed. Please try again.")
     |> assign(form: form, errors: ["Security error: #{inspect(reason)}"])}
  end
  
  defp perform_login(socket, identifier, password, ip_address, fingerprint) do
    require Logger
    user_agent = socket.assigns.user_agent
    
    try do
      # Add timeout to prevent hanging
      # Pass user_agent so authenticate_user_secure can record it in security logs
      task = Task.async(fn -> 
        Accounts.authenticate_user_secure(identifier, password, 
          ip_address: ip_address, 
          user_agent: user_agent
        ) 
      end)
      
      case Task.yield(task, 10_000) || Task.shutdown(task) do
      {:ok, {:ok, user}} ->
        # Login tracking is handled by authenticate_user_secure
        
        # Get or create device fingerprint if provided
        if fingerprint do
          case Bacon8.Security.get_or_create_fingerprint(fingerprint, %{
            user_agent: user_agent,
            platform: "web"
          }) do
            {:ok, _device_fingerprint} ->
              Bacon8.Security.associate_fingerprint_with_user(fingerprint, user.id)
            _ -> :ok
          end
        end
        
        # Generate JWT token for unified API access
        {:ok, jwt_token, _claims} = Guardian.encode_and_sign(user)
        
        # Set the session with both user_id and jwt_token
        {:noreply,
         socket
         |> assign(loading: false)
         |> put_flash(:info, "Welcome back, #{user.email}!")
         |> assign(current_user: user)
         |> redirect(external: "/auth/login_success?user_id=#{user.id}&token=#{jwt_token}")}

      {:ok, {:error, :invalid_credentials}} ->
        # Failed login tracking is handled by authenticate_user_secure
        
        # Preserve entered identifier, clear password but keep form_data
        form_data = Map.put(socket.assigns.form_data, "password", "")
        form = to_form(form_data, as: "user")

        {:noreply,
         socket
         |> assign(loading: false, form_data: form_data)
         |> put_flash(:error, "Invalid email/username or password")
         |> assign(form: form, errors: ["Invalid email/username or password"])}
      
      {:ok, {:error, :account_banned}} ->
        form_data = Map.put(socket.assigns.form_data, "password", "")
        form = to_form(form_data, as: "user")

        {:noreply,
         socket
         |> assign(loading: false, form_data: form_data)
         |> put_flash(:error, "This account has been banned. Please contact support for assistance.")
         |> assign(form: form, errors: ["Account banned"])}
      
      {:ok, {:error, :account_disabled}} ->
        form_data = Map.put(socket.assigns.form_data, "password", "")
        form = to_form(form_data, as: "user")

        {:noreply,
         socket
         |> assign(loading: false, form_data: form_data)
         |> put_flash(:error, "This account has been disabled. Please contact an administrator.")
         |> assign(form: form, errors: ["Account disabled"])}
      
      {:ok, {:error, :account_locked}} ->
        form_data = Map.put(socket.assigns.form_data, "password", "")
        form = to_form(form_data, as: "user")

        {:noreply,
         socket
         |> assign(loading: false, form_data: form_data)
         |> put_flash(:error, "Account temporarily locked due to multiple failed attempts. Please try again later.")
         |> assign(form: form, errors: ["Account locked"])}

      {:ok, {:error, :email_not_verified}} ->
        # Find the user to get verification token for dev mode
        user = Accounts.get_user_by_email_or_username(identifier)
        
        verification_code = if get_env() == "dev" do
          # Extract 6-digit code from the verification token for dev display
          case user.email_verification_token do
            nil -> "123456" # fallback for dev
            token -> 
              # Take first 6 characters of base64 token and convert to digits
              token
              |> String.slice(0, 6)
              |> String.to_charlist()
              |> Enum.map(&rem(&1, 10))
              |> Enum.map(&to_string/1)
              |> Enum.join()
              |> String.pad_leading(6, "0")
          end
        else
          nil
        end
        
        redirect_params = %{email: user.email}
        redirect_params = if verification_code, do: Map.put(redirect_params, :code, verification_code), else: redirect_params

        {:noreply,
         socket
         |> assign(loading: false)
         |> put_flash(:info, "Please verify your email address before logging in. We've sent a verification code to your email.")
         |> redirect(to: ~p"/auth/verify?#{redirect_params}")}

      {:ok, {:error, rate_limit_message}} when is_binary(rate_limit_message) ->
        form_data = Map.put(socket.assigns.form_data, "password", "")
        form = to_form(form_data, as: "user")

        {:noreply,
         socket
         |> assign(loading: false, form_data: form_data)
         |> put_flash(:error, rate_limit_message)
         |> assign(form: form, errors: [rate_limit_message])}
      
      {:ok, {:error, _reason}} ->
        # Generic error fallback
        form_data = Map.put(socket.assigns.form_data, "password", "")
        form = to_form(form_data, as: "user")

        {:noreply,
         socket
         |> assign(loading: false, form_data: form_data)
         |> put_flash(:error, "Login failed. Please try again.")
         |> assign(form: form, errors: ["Login failed"])}
      
      nil ->
        # Timeout occurred
        form_data = Map.put(socket.assigns.form_data, "password", "")
        form = to_form(form_data, as: "user")
        
        {:noreply,
         socket
         |> assign(loading: false, form_data: form_data)
         |> put_flash(:error, "Login timeout - please try again")
         |> assign(form: form, errors: ["Login timeout"])}
      end
    rescue
      e ->
        Logger.error("Login exception: #{inspect(e)}")
        Logger.error("Stacktrace: #{inspect(__STACKTRACE__)}")
        
        form_data = Map.put(socket.assigns.form_data, "password", "")
        form = to_form(form_data, as: "user")
        
        {:noreply,
         socket
         |> assign(loading: false, form_data: form_data)
         |> put_flash(:error, "An error occurred during login. Please try again.")
         |> assign(form: form, errors: ["System error"])}
    end
  end

  # ----------------
  # Enhanced registration with security features
  # ----------------
  defp do_register(socket, user_params) do
    user_params = Map.put_new(user_params, "name", user_params["email"])
    ip_address = socket.assigns.ip_address

    case Accounts.register_user(user_params, ip_address: ip_address) do
      {:ok, user, message} ->
        # For dev environment, show the verification code in the URL
        # In production, this would just be sent via email
        verification_code = if get_env() == "dev" do
          # Extract 6-digit code from the verification token for dev display
          case user.email_verification_token do
            nil -> "123456" # fallback for dev
            token -> 
              # Take first 6 characters of base64 token and convert to digits
              token
              |> String.slice(0, 6)
              |> String.to_charlist()
              |> Enum.map(&rem(&1, 10))
              |> Enum.map(&to_string/1)
              |> Enum.join()
              |> String.pad_leading(6, "0")
          end
        else
          nil
        end
        
        redirect_params = %{email: user.email}
        redirect_params = if verification_code, do: Map.put(redirect_params, :code, verification_code), else: redirect_params

        {:noreply,
         socket
         |> assign(loading: false)
         |> put_flash(:info, "Account created successfully! #{message}")
         |> redirect(to: ~p"/auth/verify?#{redirect_params}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        errors =
          Enum.map(changeset.errors, fn {field, {msg, opts}} ->
            msg = if opts[:count], do: String.replace(msg, "%{count}", to_string(opts[:count])), else: msg
            "#{String.capitalize(to_string(field))} #{msg}"
          end)

        # Preserve form data on error
        form_data = Map.put(user_params, "password", "")  # Clear password for security
        form = to_form(form_data, as: "user")

        {:noreply,
         socket
         |> assign(loading: false, form_data: form_data)
         |> put_flash(:error, "Please fix the errors below")
         |> assign(form: form, errors: errors)}
         
      {:error, :email_already_exists_verified} ->
        # Email exists and is verified - show standard error
        form_data = Map.put(user_params, "password", "")  # Clear password for security
        form = to_form(form_data, as: "user")

        {:noreply,
         socket
         |> assign(loading: false, form_data: form_data)
         |> put_flash(:error, "An account with this email already exists. Please try logging in instead.")
         |> assign(form: form, errors: ["An account with this email already exists"])}

      {:error, reason, message} when reason in [:email_taken, :username_taken] ->
        register_failed(socket, user_params, message)

      {:error, message} when is_binary(message) ->
        # The sign-up limit for this address
        register_failed(socket, user_params, message)
    end
  end

  defp register_failed(socket, user_params, message) do
    form_data = Map.put(user_params, "password", "")
    form = to_form(form_data, as: "user")

    {:noreply,
     socket
     |> assign(loading: false, form_data: form_data)
     |> put_flash(:error, message)
     |> assign(form: form, errors: [message])}
  end

  # ----------------
  # Helper functions

  # ----------------
  defp maybe_fetch_user(nil), do: nil
  defp maybe_fetch_user(user_id), do: Accounts.get_user(user_id)

  # ----------------
  # Render
  # ----------------
  def render(assigns) do
    ~H"""
      
      <!-- Auth Form -->
      <div class="relative z-10 flex items-center justify-center min-h-screen py-12 px-4">
        <div class="glass-dark p-8 rounded-xl shadow-2xl w-full max-w-md">
          
          <%= if @action == :verify_code do %>
            <!-- Email Verification Form -->
            <h2 class="text-3xl font-bold text-white text-center mb-6">Verify Your Email</h2>
            
            <%= if @verification_email do %>
              <p class="text-gray-300 text-center mb-6">
                We've sent a 6-digit verification code to <span class="text-blue-400"><%= @verification_email %></span>
              </p>
            <% else %>
              <p class="text-gray-300 text-center mb-6">
                Please enter your email address and verification code below.
              </p>
            <% end %>
            
            <%= if @verification_code_for_dev do %>
              <div class="bg-yellow-500 bg-opacity-20 border border-yellow-500 text-yellow-200 px-4 py-3 rounded mb-4">
                <p class="text-sm"><strong>Dev Mode:</strong> Your verification code is <strong><%= @verification_code_for_dev %></strong></p>
              </div>
            <% end %>
            
            <%= if @errors != [] do %>
              <div class="bg-red-500 bg-opacity-20 border border-red-500 text-red-200 px-4 py-3 rounded mb-4">
                <%= for error <- @errors do %>
                  <p><%= error %></p>
                <% end %>
              </div>
            <% end %>
            
            <.form for={@verification_form} phx-submit="verify_code" class="space-y-4">
              <%= if !@verification_email do %>
                <div>
                  <label class="block text-white text-sm font-medium mb-2">Email Address</label>
                  <input 
                    type="email" 
                    name="verification[email]" 
                    required
                    class="w-full px-4 py-3 bg-gray-800 border border-gray-600 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all duration-300"
                    placeholder="Enter your email address"
                  />
                </div>
              <% end %>
              
              <div>
                <label class="block text-white text-sm font-medium mb-2">Verification Code</label>
                <input 
                  type="text" 
                  name="verification[code]" 
                  maxlength="6"
                  pattern="[0-9]{6}"
                  required
                  class="w-full px-4 py-3 bg-gray-800 border border-gray-600 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all duration-300 text-center text-2xl tracking-widest"
                  placeholder="000000"
                />
              </div>
              
              <button 
                type="submit"
                class="w-full bg-gradient-to-r from-green-600 to-blue-600 hover:from-green-700 hover:to-blue-700 text-white font-medium py-3 rounded-lg transition-all duration-300 ease-in-out transform hover:scale-105"
              >
                Verify Email
              </button>
            </.form>
            
            <div class="mt-6 text-center">
              <%= if @verification_email do %>
                <p class="text-gray-400">
                  Didn't receive the code? 
                  <button phx-click="resend_verification" phx-value-email={@verification_email} class="text-blue-400 hover:text-blue-300 transition-colors duration-300">
                    Resend
                  </button>
                </p>
              <% else %>
                <p class="text-gray-400">
                  Need to send a new verification code? Enter your email above and we'll resend it.
                </p>
              <% end %>
              
              <p class="text-gray-400 mt-2">
                <.link navigate={~p"/register"} class="text-blue-400 hover:text-blue-300 transition-colors duration-300">
                  ← Back to Registration
                </.link>
              </p>
            </div>
            
          <% else %>
            <!-- Login/Register Form -->
            <!-- Back to Home Link -->
            <div class="mb-4">
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
            
            <h2 class="text-3xl font-bold text-white text-center mb-6">
              <%= if @action == :login, do: "Sign In", else: "Create Account" %>
            </h2>
            
            <%= if @errors != [] do %>
              <div class="bg-red-500 bg-opacity-20 border border-red-500 text-red-200 px-4 py-3 rounded mb-4">
                <%= for error <- @errors do %>
                  <p><%= error %></p>
                <% end %>
              </div>
            <% end %>
            
            <div id="auth-security-wrapper" phx-hook="DeviceFingerprint">
              <form 
                id="auth-form"
                phx-submit="submit"
                class="space-y-4"
              >
                <input type="hidden" name="user[device_fingerprint]" value="" />
              <div>
                <label class="block text-white text-sm font-medium mb-2">
                  <%= if @action == :login, do: "Email or Username", else: "Email" %>
                </label>
                <input 
                  type={if @action == :login, do: "text", else: "email"} 
                  name="user[email]" 
                  id="user_email"
                  required
                  class="w-full px-4 py-3 glass-dark text-white focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all duration-300 rounded-lg"
                  placeholder={if @action == :login, do: "Enter your email or username", else: "Enter your email"}
                />
              </div>
              
              <div :if={@action == :register}>
                <label class="block text-white text-sm font-medium mb-2">Name</label>
                <input 
                  type="text" 
                  name="user[name]" 
                  id="user_name"
                  class="w-full px-4 py-3 glass-dark text-white focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all duration-300 rounded-lg"
                  placeholder="Enter your name"
                />
              </div>
              
              <div>
                <label class="block text-white text-sm font-medium mb-2">Password</label>
                <input 
                  type="password" 
                  name="user[password]" 
                  id="user_password"
                  required
                  class="w-full px-4 py-3 glass-dark text-white focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all duration-300 rounded-lg"
                  placeholder="Enter your password"
                />
              </div>

              <!-- Forgot Password Link (only show on login) -->
              <%= if @action == :login do %>
                <div class="text-right">
                  <.link navigate={~p"/forgot-password"} class="text-sm text-blue-400 hover:text-blue-300 transition-colors duration-300">
                    Forgot your password?
                  </.link>
                </div>
              <% end %>
              
              <button 
                type="submit"
                disabled={@loading}
                class={"w-full glass-button hover:glass-button text-white font-medium py-3 rounded-lg transition-all duration-300 ease-in-out transform hover:scale-105 #{if @loading, do: "opacity-50 cursor-not-allowed", else: ""}"}
              >
                <%= if @loading do %>
                  <div class="flex items-center justify-center">
                    <svg class="animate-spin -ml-1 mr-3 h-5 w-5 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                      <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                    </svg>
                    <%= if @action == :login, do: "Signing In...", else: "Creating Account..." %>
                  </div>
                <% else %>
                  <%= if @action == :login, do: "Sign In", else: "Create Account" %>
                <% end %>
              </button>
              </form>
            </div>
            
            <div class="mt-6 text-center">
              <%= if @action == :login do %>
                <p class="text-gray-400">
                  Don't have an account? 
                  <.link navigate={~p"/register"} class="text-blue-400 hover:text-blue-300 transition-colors duration-300">
                    Sign up
                  </.link>
                </p>
              <% else %>
                <p class="text-gray-400">
                  Already have an account? 
                  <.link navigate={~p"/login"} class="text-blue-400 hover:text-blue-300 transition-colors duration-300">
                    Sign in
                  </.link>
                </p>
              <% end %>
            </div>
          <% end %>
          </div>
      </div>
    """
  end

  defp get_env do
    System.get_env("MIX_ENV") || "dev"
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
            # Fall back to peer_data
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
        # IPv6 address
        "#{Integer.to_string(a, 16)}:#{Integer.to_string(b, 16)}:#{Integer.to_string(c, 16)}:#{Integer.to_string(d, 16)}:#{Integer.to_string(e, 16)}:#{Integer.to_string(f, 16)}:#{Integer.to_string(g, 16)}:#{Integer.to_string(h, 16)}"
      _ -> "unknown"
    end
  end
end

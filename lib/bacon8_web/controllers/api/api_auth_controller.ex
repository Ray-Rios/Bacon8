defmodule Bacon8Web.Api.ApiAuthController do
  use Bacon8Web, :controller
  alias Bacon8.Accounts
  alias Bacon8.Auth.Guardian

  # ===================================
  # UNIFIED AUTHENTICATION FUNCTIONS
  # ===================================

  # POST /api/auth/register - Unified registration for web and games
  def register(conn, %{"email" => email, "password" => password} = user_params) do
    formatted_params = %{
      "email" => email,
      "password" => password,
      "name" => user_params["name"] || email
    }

    ip_address = Bacon8.Accounts.RateLimit.get_client_ip(conn)

    case Accounts.register_user(formatted_params, ip_address: ip_address) do
      {:ok, user, verification_message} ->
        # Generate JWT token immediately for games, but require verification for web
        {:ok, token, _claims} = Guardian.encode_and_sign(user)
        
        conn
        |> put_status(:created)
        |> json(%{
          success: true,
          message: "Account created successfully",
          token: token,
          verification_info: verification_message,
          user: %{
            id: user.id,
            email: user.email,
            name: user.name,
            is_admin: user.is_admin,
            email_verified: !is_nil(user.email_verified_at)
          }
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        errors = format_changeset_errors(changeset)
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          success: false,
          message: "Registration failed",
          errors: errors
        })

      {:error, :email_taken, message} ->
        conn
        |> put_status(:conflict)
        |> json(%{
          success: false,
          message: message || "An account with this email already exists. Please try logging in instead.",
          redirect_to: "login"
        })

      {:error, :email_already_exists_verified} ->
        conn
        |> put_status(:conflict)
        |> json(%{
          success: false,
          message: "An account with this email already exists. Please try logging in instead.",
          redirect_to: "login"
        })

      {:error, :username_taken, message} ->
        conn
        |> put_status(:conflict)
        |> json(%{
          success: false,
          message: message
        })

      {:error, rate_limit_message} when is_binary(rate_limit_message) ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{
          success: false,
          message: rate_limit_message
        })
    end
  end

  # POST /api/auth/login - Accept email or username
  def login(conn, %{"email" => identifier, "password" => password}) do
    ip_address = Bacon8.Accounts.RateLimit.get_client_ip(conn)
    user_agent = get_user_agent(conn)

    case Accounts.authenticate_user_secure(identifier, password, ip_address: ip_address, user_agent: user_agent) do
      {:ok, user} ->
        # Generate JWT token using Guardian
        case Guardian.encode_and_sign(user) do
          {:ok, token, _claims} ->
            conn
            |> put_session(:user_id, user.id)
            |> configure_session(renew: true)
            |> put_status(:ok)
            |> json(%{
              success: true,
              message: "Login successful",
              token: token,
              user: %{
                id: user.id,
                email: user.email,
                name: user.name,
                is_admin: user.is_admin,
                email_verified: !is_nil(user.email_verified_at)
              }
            })
          {:error, reason} ->
            # Token generation failed, but still return success with session
            conn
            |> put_session(:user_id, user.id)
            |> configure_session(renew: true)
            |> put_status(:ok)
            |> json(%{
              success: true,
              message: "Login successful (token error: #{inspect(reason)})",
              user: %{
                id: user.id,
                email: user.email,
                name: user.name,
                is_admin: user.is_admin,
                email_verified: !is_nil(user.email_verified_at)
              }
            })
        end

      {:error, :invalid_credentials} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{success: false, error: "Invalid email or password"})

      {:error, :account_locked} ->
        conn
        |> put_status(:locked)
        |> json(%{success: false, error: "Account temporarily locked due to multiple failed attempts"})

      {:error, :email_not_verified} ->
        user = Accounts.get_user_by_email_or_username(identifier)
        conn
        |> put_status(:forbidden)
        |> json(%{
          success: false, 
          message: "Please verify your email address before logging in. Check your inbox for verification code.",
          error_code: "email_not_verified",
          redirect_to: "verify",
          email: user.email
        })

      {:error, rate_limit_message} when is_binary(rate_limit_message) ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{success: false, error: rate_limit_message})

      {:error, _reason} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{success: false, error: "Login failed"})
    end
  end

  # POST /api/auth/login - Alternative with username parameter
  def login(conn, %{"username" => identifier, "password" => password}) do
    login(conn, %{"email" => identifier, "password" => password})
  end

  # POST /api/auth/login - Handle missing credentials
  def login(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      success: false,
      error: "Email/username and password are required"
    })
  end

  # POST /api/auth/verify-email
  def verify_email(conn, %{"token" => token}) do
    case Accounts.verify_user_email(token) do
      {:ok, user} ->
        # Generate JWT token after successful email verification
        {:ok, jwt_token, _claims} = Guardian.encode_and_sign(user)
        
        conn
        |> put_status(:ok)
        |> json(%{
          success: true,
          message: "Email verified successfully",
          token: jwt_token,
          user: %{
            id: user.id,
            email: user.email,
            email_verified: true
          }
        })

      {:error, message} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          success: false,
          error: message
        })
    end
  end

  # POST /api/auth/resend-verification
  def resend_verification(conn, %{"email" => email}) do
    case Accounts.resend_verification_email(email) do
      {:ok, message} ->
        conn
        |> put_status(:ok)
        |> json(%{
          success: true,
          message: message
        })

      {:error, error_message} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          success: false,
          error: error_message
        })
    end
  end

  # POST /api/auth/dev-verify - Development only: verify any email
  # POST /api/auth/dev-verify
  #
  # Marks an account's email verified without the code. This is an unauthenticated
  # endpoint that takes an email and grants it the thing email verification exists
  # to prove, so in production it is an account-takeover primitive: register with
  # someone's address, call this, log in. `authenticate_user_secure/3` refuses a
  # login while `email_verified_at` is nil, and this is a way to fill that column
  # for any address at all.
  #
  # Gated on config rather than `Mix.env()` because Mix is not present in a
  # release, where `Mix.env/0` raises and this would 500 instead of 404.
  def dev_verify(conn, %{"email" => email}) do
    if !Application.get_env(:bacon8, :allow_dev_verify, false) do
      # 404, not 403. A 403 confirms the endpoint exists and is merely switched
      # off, which is a hint worth withholding.
      conn |> put_status(:not_found) |> json(%{success: false, error: "Not found"})
    else
      do_dev_verify(conn, email)
    end
  end

  defp do_dev_verify(conn, email) do
    case Accounts.get_user_by_email(email) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{success: false, error: "User not found"})

      user ->
        case Accounts.verify_user_email_direct(user) do
          {:ok, verified_user} ->
            conn
            |> put_status(:ok)
            |> json(%{
              success: true,
              message: "Email verified successfully (development)",
              user: %{
                id: verified_user.id,
                email: verified_user.email,
                email_verified: !is_nil(verified_user.email_verified_at)
              }
            })

          {:error, reason} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{success: false, error: "Verification failed: #{reason}"})
        end
    end
  end

  # POST /api/auth/authenticate
  def authenticate(conn, %{"email" => email, "password" => password}) do
    case Accounts.authenticate_for_api_server(email, password) do
      {:ok, %{user: user, api_token: token}} ->
        # Create API session on the API server
        case create_api_session(user, token) do
          {:ok, session_data} ->
            conn
            |> put_status(:ok)
            |> json(%{
              success: true,
              user: %{
                id: user.id,
                email: user.email,
                name: user.name,
                is_admin: user.is_admin
              },
              api_token: token,
              api_session: session_data
            })

          {:error, _reason} ->
            # Still return success for auth, but note API session creation failed
            conn
            |> put_status(:ok)
            |> json(%{
              success: true,
              user: %{
                id: user.id,
                email: user.email,
                name: user.name,
                is_admin: user.is_admin
              },
              api_token: token,
              api_session_error: "Could not create API session"
            })
        end

      {:error, :invalid_email} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{success: false, error: "Invalid email"})

      {:error, :invalid_password} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{success: false, error: "Invalid password"})

      {:error, _reason} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{success: false, error: "Authentication failed"})
    end
  end

  defp create_api_session(user, token) do
    api_server_url = System.get_env("API_SERVER_URL", "http://localhost:7000")
    
    payload = %{
      user_id: user.id,
      email: user.email,
      name: user.name,
      api_token: token,
      is_admin: user.is_admin
    }

    case HTTPoison.post("#{api_server_url}/auth/create_session", Jason.encode!(payload), [{"Content-Type", "application/json"}]) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, session_data} -> {:ok, session_data}
          {:error, _} -> {:error, :invalid_response}
        end
      
      {:ok, %HTTPoison.Response{status_code: _}} ->
        {:error, :api_server_error}
      
      {:error, _} ->
        {:error, :connection_failed}
    end
  end

  # POST /api/auth/verify - Unified JWT token verification
  def verify_token(conn, %{"token" => token}) do
    case Guardian.decode_and_verify(token) do
      {:ok, claims} ->
        case Guardian.resource_from_claims(claims) do
          {:ok, user} ->
            conn
            |> put_status(:ok)
            |> json(%{
              success: true,
              message: "Token valid",
              user: %{
                id: user.id,
                email: user.email,
                name: user.name,
                is_admin: user.is_admin,
                email_verified: !is_nil(user.email_verified_at)
              },
              claims: %{
                exp: claims["exp"],
                iat: claims["iat"],
                sub: claims["sub"]
              }
            })

          {:error, _reason} ->
            conn
            |> put_status(:unauthorized)
            |> json(%{success: false, error: "Invalid user in token"})
        end

      {:error, _reason} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{success: false, error: "Invalid or expired token"})
    end
  end

  # POST /api/auth/verify-bearer - Alternative endpoint for Authorization header
  def verify_bearer(conn, _params) do
    case Guardian.Plug.current_token(conn) do
      nil ->
        conn
        |> put_status(:unauthorized)
        |> json(%{success: false, error: "No token provided"})

      token ->
        verify_token(conn, %{"token" => token})
    end
  end

  # GET /api/auth/users (for API server to get user list)
  def list_users(conn, _params) do
    # This should be protected by API server authentication
    users = Accounts.list_users()
    
    user_data = Enum.map(users, fn user ->
      %{
        id: user.id,
        email: user.email,
        name: user.name,
        is_admin: user.is_admin,
        status: user.status || "active"
      }
    end)

    conn
    |> put_status(:ok)
    |> json(%{success: true, users: user_data})
  end

  # POST /api/auth/logout - API logout endpoint
  def logout(conn, _params) do
    # For stateless JWT tokens, logout is client-side (delete the token)
    # We could maintain a blacklist in the future if needed
    conn
    |> put_status(:ok)
    |> json(%{
      success: true,
      message: "Logged out successfully",
      action: "Please delete the JWT token from client storage"
    })
  end

  # POST /api/auth/verify-code - Verify 6-digit email verification code
  def verify_code(conn, %{"email" => email, "code" => code}) do
    case Accounts.verify_user_with_code(email, code) do
      {:ok, user} ->
        {:ok, token, _claims} = Guardian.encode_and_sign(user)
        
        conn
        |> put_status(:ok)
        |> json(%{
          success: true,
          message: "Email verified successfully",
          token: token,
          user: %{
            id: user.id,
            email: user.email,
            name: user.name,
            is_admin: user.is_admin,
            email_verified: true
          }
        })

      {:error, :invalid_code} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          success: false,
          message: "Invalid or expired verification code"
        })

      {:error, :user_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{
          success: false,
          message: "User not found"
        })

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          success: false,
          message: "Verification failed: #{reason}"
        })
    end
  end

  def verify_code(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      success: false,
      message: "Email and code are required"
    })
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp get_user_agent(conn) do
    case Plug.Conn.get_req_header(conn, "user-agent") do
      [user_agent | _] -> user_agent
      [] -> "Unknown"
    end
  end
end
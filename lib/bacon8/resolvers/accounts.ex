defmodule Bacon8.Resolvers.Accounts do
  alias Bacon8.Accounts
  alias Bacon8.Auth.Guardian

  # ----------------------------
  # Get current user
  # ----------------------------
  def get_current_user(_parent, _args, %{context: %{current_user: user}}) do
    {:ok, user}
  end

  def get_current_user(_parent, _args, _ctx), do: {:error, "Not logged in"}

  # ----------------------------
  # Register
  # ----------------------------
  def register(_parent, %{input: params}, _ctx) do
    case Accounts.create_user(params) do
      {:ok, user} ->
        {:ok, token, _claims} = Guardian.encode_and_sign(user)
        {:ok, %{token: token, user: user}}

      {:error, changeset} ->
        {:error, format_changeset_errors(changeset)}
    end
  end

  # ----------------------------
  # Login
  # ----------------------------
  def login(_parent, %{input: %{email: email, password: password}}, _ctx) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        {:ok, token, _claims} = Guardian.encode_and_sign(user)
        {:ok, %{token: token, user: user}}

      {:error, _reason} ->
        {:error, "Invalid email or password"}
    end
  end

  # ----------------------------
  # Update avatar
  # ----------------------------
  def update_avatar(_parent, %{input: input}, _ctx) do
    user = Accounts.get_user!(input.user_id)
    {:ok, Accounts.update_avatar(user, input)}
  end

  # ----------------------------
  # Helper for formatting Ecto errors
  # ----------------------------
  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end

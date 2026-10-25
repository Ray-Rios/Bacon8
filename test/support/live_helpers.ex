defmodule Bacon8.LiveHelpers do
  @moduledoc """
  Signing people in and reading a LiveView's state, for the LiveView tests of the core's
  pages (`test/bacon8_web/live/*`).
  """
  import Bacon8.DataCase, only: [user_fixture: 1]

  @doc "A user with a verified email."
  def verified(attrs \\ %{}) do
    user_fixture(Map.merge(%{email_verified_at: DateTime.utc_now() |> DateTime.truncate(:second)}, Map.new(attrs)))
  end

  @doc "A member, or staff: `\"admin\"` (also flagged `is_admin`, as an admin is), `\"gm\"` or `\"editor\"`."
  def person("member"), do: verified()
  def person("admin"), do: verified(%{role: "admin", is_admin: true})
  def person(role) when role in ~w(gm editor), do: verified(%{role: role})

  @doc "A connection with the user's session."
  def signed_in(user), do: Phoenix.ConnTest.build_conn() |> Plug.Test.init_test_session(%{"user_id" => user.id})

  @doc "The LiveView process's assigns (what the page holds, not what it renders)."
  def assigns(view), do: :sys.get_state(view.pid).socket.assigns

  @doc "The roles that may write content (the owner's rule, 2026-10-25), and one that may not."
  def staff_roles, do: ~w(admin gm editor)
end

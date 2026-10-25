defmodule Bacon8.PermissionsTest do
  # Who may open which part of /admin: admins all of it, GMs and editors the content area only.
  use ExUnit.Case, async: true

  alias Bacon8.Permissions

  defp user(role, is_admin \\ false), do: %{role: role, is_admin: is_admin}

  test "an admin may open every area, and is staff" do
    admin = user("admin", true)

    assert Permissions.admin?(admin)
    assert Permissions.can?(admin, :content)
    assert Permissions.can?(admin, :anything_at_all)
    assert Permissions.staff?(admin)
    assert Permissions.home_path(admin) == "/admin"
  end

  test "the admin flag decides, not the role's name" do
    refute Permissions.admin?(user("admin", false))
    refute Permissions.can?(user("admin", false), :content)
    assert Permissions.admin?(user("member", true))
  end

  test "GMs and editors may open the content area, and only that" do
    for role <- ~w(gm editor) do
      u = user(role)

      assert Permissions.can?(u, :content)
      refute Permissions.can?(u, :users)
      refute Permissions.can?(u, :tools)
      refute Permissions.can?(u, :admin)
      assert Permissions.areas(u) == [:content]
      assert Permissions.staff?(u)
      assert Permissions.home_path(u) == "/admin/pages"
      refute Permissions.admin?(u)
    end
  end

  test "members and other roles get nothing" do
    for role <- ["member", "guest", "banned", "moderator", "", nil, "ADMIN", "Editor"] do
      u = user(role)

      refute Permissions.can?(u, :content), "#{inspect(role)} got the content area"
      refute Permissions.staff?(u)
      assert Permissions.areas(u) == []
      assert Permissions.home_path(u) == "/"
    end
  end

  test "a visitor gets nothing, and nothing crashes on odd input" do
    refute Permissions.can?(nil, :content)
    refute Permissions.staff?(nil)
    assert Permissions.areas(nil) == []
    assert Permissions.areas(%{}) == []
    refute Permissions.admin?(nil)
    refute Permissions.admin?(%{})
  end
end

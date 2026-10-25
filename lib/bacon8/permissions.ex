defmodule Bacon8.Permissions do
  @moduledoc """
  Who may open which part of `/admin`.

  Admins (`is_admin`) may open all of it. Other staff roles may open the *areas* listed for
  their role, and nothing else: a GM or an editor can write pages and posts without being able
  to reach user management, the SQL console, security, email logs or the plugins page.

  An area is a section of the admin, named here and checked where a page mounts
  (`{Bacon8Web.UserAuth, {:require_area, area}}`). A page that doesn't name an area still
  needs an admin (`:require_admin_user`), so nothing is open to staff by accident.

  | Area | What it covers | Roles besides admin |
  |---|---|---|
  | `:content` | `/admin/pages` and `/admin/blog-management`, the sidebar's Content links | gm, editor |

  To give a role another area, add it to `@role_areas`; to open a page to an area, change its
  `on_mount`. A role that isn't listed, and a banned or suspended account, gets nothing
  (suspension is checked by the sign-in hooks).
  """

  @role_areas %{
    "gm" => [:content],
    "editor" => [:content]
  }

  @doc "True for an admin: the account flag, not the role name."
  def admin?(%{is_admin: true}), do: true
  def admin?(_), do: false

  @doc "True when `user` may open pages of `area`. Admins may open every area."
  def can?(nil, _area), do: false

  def can?(user, area) do
    admin?(user) or area in areas(user)
  end

  @doc "The areas a non-admin's role grants (an admin has them all, see `can?/2`)."
  def areas(%{role: role}) when is_binary(role), do: Map.get(@role_areas, role, [])
  def areas(_), do: []

  @doc "True when the user may open any part of the admin at all."
  def staff?(nil), do: false
  def staff?(user), do: admin?(user) or areas(user) != []

  @doc "Where the user's admin starts: the dashboard for an admin, else their first area's page."
  def home_path(user) do
    cond do
      admin?(user) -> "/admin"
      :content in areas(user) -> "/admin/pages"
      true -> "/"
    end
  end
end

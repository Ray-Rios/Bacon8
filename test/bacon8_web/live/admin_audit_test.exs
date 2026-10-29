defmodule Bacon8Web.AdminAuditTest do
  # /admin/audit (2026-10-29): the audit log the front page promises, and the admin actions that
  # write to it.
  use Bacon8.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Bacon8.LiveHelpers

  @endpoint Bacon8Web.Endpoint

  test "a role change and a plugin switched off are recorded and shown" do
    admin = person("admin")
    member = person("member")

    {:ok, _} = Bacon8.Accounts.change_role(member, "gm", actor: admin)
    {:ok, _} = Bacon8.Plugins.deactivate("fixture_plugin", admin)

    # (both in the same second: the order between them isn't fixed)
    assert %{actor: %{email: email}} = Enum.find(Bacon8.Audit.list(), &match?(%{entry: %{action: "plugin.deactivated", metadata: %{"slug" => "fixture_plugin"}}}, &1))
    assert email == admin.email
    assert Enum.any?(Bacon8.Audit.list(query: "user."), &(&1.entry.action == "user.role_changed" and &1.entry.target_id == member.id))

    {:ok, view, html} = live(signed_in(admin), "/admin/audit")
    assert html =~ "Audit log"
    assert html =~ "user.role_changed"
    assert html =~ "plugin.deactivated"

    html = view |> form("form", %{"query" => "plugin"}) |> render_change()
    assert html =~ "plugin.deactivated"
    refute html =~ "user.role_changed"

  end
end

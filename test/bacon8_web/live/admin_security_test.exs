defmodule Bacon8Web.AdminSecurityTest do
  # /admin/security: scans from the server's own gateway (every visitor looks like it behind Docker
  # Desktop) are shown with an explanation, and can't be blocked.
  use Bacon8.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Bacon8.LiveHelpers

  alias Bacon8.Security

  @endpoint Bacon8Web.Endpoint

  defp scan(ip, path),
    do: Security.record_suspicious_request(%{ip_address: ip, path: path, method: "GET", user_agent: "scanner", request_type: "env_file", blocked: false})

  test "the gateway is explained, offers no Block button, and refuses a block" do
    {:ok, _} = scan("192.168.65.3", "/blog/.env")
    {:ok, _} = scan("203.0.113.77", "/blog/.env")

    {:ok, view, html} = live(signed_in(person("admin")), "/admin/security")

    assert html =~ ~s(id="internal-address-note")
    assert html =~ "can&#39;t block" or html =~ "can't block"
    refute has_element?(view, ~s(button[phx-click="block_ip_quick"][phx-value-ip="192.168.65.3"]))
    assert has_element?(view, ~s(button[phx-click="block_ip_quick"][phx-value-ip="203.0.113.77"]))

    # even a hand-made event is refused, and nothing is blocked
    html = render_click(view, "block_ip_quick", %{"ip" => "192.168.65.3"})
    assert html =~ "internal address"
    refute Security.blocked?("192.168.65.3", "ip")
  end
end

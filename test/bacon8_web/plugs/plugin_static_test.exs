defmodule Bacon8Web.Plugs.PluginStaticTest do
  use ExUnit.Case, async: true
  import Plug.Test

  alias Bacon8Web.Plugs.PluginStatic

  defp run(path, method \\ :get), do: conn(method, path) |> PluginStatic.call(PluginStatic.init([]))

  test "serves an installed plugin's pictures and JSON from priv/static" do
    conn = run("/plugins/bacon_world/card/front-1.webp")
    assert conn.status == 200
    assert conn.halted
    assert ["image/webp" <> _] = Plug.Conn.get_resp_header(conn, "content-type")

    assert run("/plugins/bacon_world/card/card.json").status == 200
  end

  test "anything else under /plugins is a 404" do
    assert run("/plugins/bacon_world/card/missing.webp").status == 404
    assert run("/plugins/no_such_plugin/card/front-1.webp").status == 404
    assert run("/plugins/bacon_world/lib/bacon_world/plugin.ex").status == 404
    assert run("/plugins/bacon_world/card/../../lib/bacon_world/plugin.webp").status == 404
    assert run("/plugins/bacon_world/card/x.svg").status == 404
    assert run("/plugins/bacon_world/card/front-1.webp", :post).status == 404
    assert run("/plugins").status == 404
  end

  test "other paths pass through" do
    refute run("/games").halted
  end
end

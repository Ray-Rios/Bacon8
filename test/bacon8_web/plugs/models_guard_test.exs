defmodule Bacon8Web.Plugs.ModelsGuardTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  alias Bacon8Web.Plugs.ModelsGuard

  setup do
    root = Path.join(System.tmp_dir!(), "models_guard_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "Humans"))
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  defp run(path, root) do
    conn(:get, path) |> put_req_header("accept-encoding", "gzip") |> ModelsGuard.call(ModelsGuard.init(root: root))
  end

  test "only runtime formats get through", %{root: root} do
    assert run("/models/Humans/Male.blend", root).status == 404
    assert run("/models/Humans/Male.glb.gz", root).status == 404
    refute run("/models/Humans/Male.glb", root).halted
  end

  test "a .gz older than its file isn't used", %{root: root} do
    glb = Path.join(root, "Humans/Male.glb")
    File.write!(glb, "new")
    File.write!(glb <> ".gz", "old")
    File.touch!(glb <> ".gz", System.os_time(:second) - 60)
    assert get_req_header(run("/models/Humans/Male.glb", root), "accept-encoding") == []

    File.touch!(glb <> ".gz", System.os_time(:second) + 60)
    assert get_req_header(run("/models/Humans/Male.glb", root), "accept-encoding") == ["gzip"]
  end
end

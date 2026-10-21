defmodule Bacon8.ReleaseTest do
  # The web pods' init container waits on these (k3s/base/bacon8-deployment.yaml).
  use Bacon8.DataCase, async: false

  alias Bacon8.Release

  test "nothing is pending once the suite's databases are migrated (core and plugin folders)" do
    assert Release.pending_migrations() == []
  end

  test "await_migrations returns at once when nothing is pending" do
    assert Release.await_migrations(10) == :ok
  end
end

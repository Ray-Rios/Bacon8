defmodule Bacon8Web.DriveControllerRangeTest do
  use ExUnit.Case, async: true
  import Bacon8Web.DriveController, only: [parse_range: 2]

  test "parses single byte ranges" do
    assert parse_range("bytes=0-99", 1000) == {:ok, 0, 99}
    assert parse_range("bytes=900-", 1000) == {:ok, 900, 999}
    assert parse_range("bytes=-100", 1000) == {:ok, 900, 999}
    assert parse_range("bytes=990-5000", 1000) == {:ok, 990, 999}
    assert parse_range("bytes=-5000", 1000) == {:ok, 0, 999}
  end

  test "rejects unsatisfiable or malformed ranges" do
    assert parse_range("bytes=1000-", 1000) == :error
    assert parse_range("bytes=5-1", 1000) == :error
    assert parse_range("bytes=a-b", 1000) == :error
    assert parse_range("bytes=0-1,5-9", 1000) == :error
    assert parse_range("items=0-1", 1000) == :error
    assert parse_range("bytes=0-0", 0) == :error
  end
end

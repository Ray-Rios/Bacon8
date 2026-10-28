defmodule Bacon8Web.TaskbarStartMenuTest do
  # Suggestions & Bugs #1: the start menu listed Terminal, Calculator, Notepad, Media
  # Player and Settings, none of which did anything, and the taskbar pinned a second
  # File Explorer button next to the one already in the start menu.
  use Bacon8.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Bacon8.LiveHelpers

  @endpoint Bacon8Web.Endpoint

  test "the start menu offers File Manager only, once, and none of the removed apps" do
    {:ok, view, _html} = live(signed_in(person("member")), "/blog")

    html =
      view
      |> element("[aria-label='Start']")
      |> render_click()

    for removed <- ["Terminal", "Calculator", "Notepad", "Media Player"] do
      refute html =~ removed, "start menu still offers #{removed}"
    end

    refute html =~ ">Settings<", "start menu still offers Settings"
    assert html =~ "File Manager"

    assert html |> String.split("phx-value-app=\"file_manager\"") |> length() == 2,
           "File Manager should be pinned in the start menu only, not also on the taskbar"
  end
end

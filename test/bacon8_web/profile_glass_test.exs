defmodule Bacon8Web.ProfileGlassTest do
  # Choosing a glass preset on /profile. The custom tint outranks the theme everywhere it
  # is applied, so a preset that leaves it in place does nothing (reported 2026-10-25: the
  # flash said "Glass theme updated!" and the colours didn't change).
  use ExUnit.Case, async: true

  alias Bacon8Web.ProfileLive

  test "a preset replaces the theme and drops the custom tint" do
    data = %{"glass_theme" => "dark", "glass_custom_color" => "#cc44aa", "glass_opacity" => "0.25"}

    assert ProfileLive.glass_theme_choice(data, "blue") == %{"glass_theme" => "blue", "glass_opacity" => "0.25"}
  end

  test "the other settings are kept" do
    data = %{"glass_blur" => "20", "glass_opacity" => "0.5", "gradient_start" => "#112233", "glass_custom_color" => "#ffffff"}
    result = ProfileLive.glass_theme_choice(data, "teal")

    assert result["glass_blur"] == "20"
    assert result["glass_opacity"] == "0.5"
    assert result["gradient_start"] == "#112233"
    assert result["glass_theme"] == "teal"
    refute Map.has_key?(result, "glass_custom_color")
  end

  test "works when nothing was saved yet" do
    assert ProfileLive.glass_theme_choice(nil, "green") == %{"glass_theme" => "green"}
    assert ProfileLive.glass_theme_choice(%{}, "green") == %{"glass_theme" => "green"}
  end
end

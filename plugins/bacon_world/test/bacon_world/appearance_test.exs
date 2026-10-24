# The look normaliser: what a player sends is never stored as is.
defmodule BaconWorld.AppearanceTest do
  use ExUnit.Case, async: true
  alias BaconWorld.Appearance, as: A

  test "defaults round-trip" do
    for b <- ["male", "female"] do
      d = A.default(b)
      assert {:ok, ^d} = A.normalize(d)
    end
  end

  test "clamps, drops unknown keys, falls back per field" do
    raw = %{"body" => "female", "height" => 3, "shape" => %{"weight" => -7, "muscle" => "0.5", "evil" => 1, "chest" => 0.123456},
            "skin" => "red", "eyes" => "#00ff00", "hair" => %{"style" => "../../etc", "color" => "#abcdef"},
            "facial" => %{"style" => "FullBeard"}, "outfit" => %{"top" => %{"id" => "Top_Armor", "main" => "#123456"}}, "x" => 1}
    assert {:ok, a} = A.normalize(raw)
    assert a["height"] == 1.08
    assert a["shape"]["weight"] == -1.0
    assert a["shape"]["muscle"] == 0.5
    assert a["shape"]["chest"] == 0.123
    refute Map.has_key?(a["shape"], "evil")
    refute Map.has_key?(a, "x")
    assert a["skin"] == "#C68E6E"
    assert a["eyes"] == "#00FF00"
    assert a["hair"] == %{"style" => "Lob", "color" => "#ABCDEF"}
    assert a["facial"]["style"] == "none"
    # clothes are items now: an outfit in an old look is dropped
    refute Map.has_key?(a, "outfit")
  end

  test "male keeps the chest (pectorals) slider; styles checked against a manifest" do
    styles = %{"male" => %{"hair" => ["Buzz"], "facial" => ["Goatee"]}}
    assert {:ok, a} = A.normalize(%{"body" => "male", "shape" => %{"chest" => 1}, "hair" => %{"style" => "Mohawk"}, "facial" => %{"style" => "Goatee"}}, nil, styles)
    assert a["shape"]["chest"] == 1.0
    assert a["hair"]["style"] == "Short"
    assert a["facial"]["style"] == "Goatee"
    assert {:ok, %{"hair" => %{"style" => "none"}}} = A.normalize(%{"body" => "male", "hair" => %{"style" => "none"}}, nil, styles)
  end

  test "chest shaping is hers only; glute, waist and limb sliders kept and clamped for both" do
    shape = %{"chest_height" => 0.5, "chest_spacing" => -2, "chest_shape" => 0.25, "glute_lift" => -1, "arms" => 0.3, "thighs" => 1, "calves" => -0.2, "waist" => -0.6}
    assert {:ok, f} = A.normalize(%{"body" => "female", "shape" => shape}, nil)
    assert %{"chest_height" => 0.5, "chest_spacing" => -1.0, "chest_shape" => 0.25, "glute_lift" => +0.0, "arms" => 0.3, "thighs" => 1.0, "calves" => -0.2, "waist" => -0.6} = f["shape"]
    assert {:ok, m} = A.normalize(%{"body" => "male", "shape" => shape}, nil)
    assert Enum.all?(~w(chest_height chest_spacing chest_shape), &(m["shape"][&1] == 0.0))
    assert %{"glute_lift" => +0.0, "arms" => 0.3, "thighs" => 1.0, "calves" => -0.2, "waist" => -0.6} = m["shape"]
  end

  test "a retired style id maps to the style that replaced it" do
    styles = %{"female" => %{"hair" => ["Ponytail", "Lob"], "facial" => [], "aliases" => %{"HighPonytail" => "Ponytail", "Gone" => "Missing"}}}
    assert {:ok, a} = A.normalize(%{"body" => "female", "hair" => %{"style" => "HighPonytail"}}, nil, styles)
    assert a["hair"]["style"] == "Ponytail"
    # an alias to a style that isn't in the list falls back to the default
    assert {:ok, b} = A.normalize(%{"body" => "female", "hair" => %{"style" => "Gone"}}, nil, styles)
    assert b["hair"]["style"] == "Lob"
  end

  test "errors and body fallback" do
    assert {:error, :invalid_appearance} = A.normalize(%{"body" => "robot"})
    assert {:error, :invalid_appearance} = A.normalize("male")
    assert {:ok, %{"body" => "female"}} = A.normalize(%{}, "female")
    assert {:ok, %{"body" => "male"}} = A.normalize(%{body: "male", skin: "#FFFFFF"})
  end

  test "for_settings" do
    assert A.for_settings(%{}, "/models/heroes/runner.glb") == nil
    assert %{"body" => "female"} = A.for_settings(%{}, "/models/Humans/Female.glb")
    assert %{"body" => "male", "skin" => "#111111"} = A.for_settings(%{"appearance" => %{"body" => "female", "skin" => "#111111"}}, "/models/Humans/Male.glb")
    assert A.model_path("female") == "/models/Humans/Female.glb"
    assert A.human_model?("/models/Humans/Male.glb")
  end
end

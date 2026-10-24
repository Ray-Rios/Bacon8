defmodule BaconWorld.HumansTest do
  # Characters with a look (the Bacon8 humans). Not async: the models folder is app config.
  use Bacon8.DataCase, async: false

  alias BaconWorld.{Models, World}

  setup do
    dir = Path.join(System.tmp_dir!(), "bacon_world_humans_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "Humans/Hair"))
    File.write!(Path.join(dir, "Humans/Male.glb"), "glTF")
    File.write!(Path.join(dir, "Humans/Female.glb"), "glTF")
    File.write!(Path.join(dir, "supported_models.txt"), "Humans/Male.glb\nHumans/Female.glb\n")
    File.write!(Path.join(dir, "Humans/Male.json"), Jason.encode!(%{"hides" => %{"Top_Tee" => [1, 2]}, "clips" => ["Idle_Loop"]}))

    File.write!(
      Path.join(dir, "Humans/Hair/hair_manifest.json"),
      Jason.encode!(%{
        "version" => 1,
        "styles" => %{
          "Male" => %{"hair" => [%{"id" => "Buzz", "file" => "Hair_Male_Buzz.glb"}], "facial" => [%{"id" => "Goatee", "file" => "Facial_Male_Goatee.glb"}]},
          "Female" => %{"hair" => [%{"id" => "Bob", "file" => "Hair_Female_Bob.glb"}], "aliases" => %{"BobBangs" => "Bob", "Bad" => 7}}
        }
      })
    )

    Application.put_env(:bacon8, Models, roots: [dir])

    on_exit(fn ->
      Application.delete_env(:bacon8, Models)
      File.rm_rf!(dir)
    end)

    %{user_id: Ecto.UUID.generate()}
  end

  defp look(body, extra \\ %{}) do
    Map.merge(%{"body" => body, "skin" => "#8a5534", "hair" => %{"style" => if(body == "male", do: "Buzz", else: "Bob"), "color" => "#2b1e14"}}, extra)
  end

  test "human_assets reads the manifests; style ids per body" do
    assets = Models.human_assets()
    assert %{"Male" => %{"hides" => %{"Top_Tee" => [1, 2]}}} = assets["bodies"]
    refute Map.has_key?(assets["bodies"]["Male"], "clips")
    assert %{"male" => %{"hair" => ["Buzz"], "facial" => ["Goatee"]}, "female" => %{"hair" => ["Bob"], "facial" => []}} = Models.human_style_ids(assets)
    # retired ids and what replaced them (malformed entries dropped)
    assert Models.human_style_ids(assets)["female"]["aliases"] == %{"BobBangs" => "Bob"}
    assert Models.human_style_ids(assets)["male"]["aliases"] == %{}
  end

  test "a look picks the model from its body and is stored normalised", %{user_id: user_id} do
    {:ok, c} =
      World.create_character(user_id, %{
        "name" => "Ada",
        "character_type" => "Mage",
        "model_path" => "/models/Humans/Male.glb",
        "appearance" => look("female", %{"height" => 9, "hair" => %{"style" => "Mohawk"}})
      })

    assert c.model_path == "/models/Humans/Female.glb"
    assert %{"body" => "female", "height" => 1.08, "skin" => "#8A5534", "hair" => %{"style" => "Lob"}} = c.appearance

    assert {:ok, %{appearance: %{"body" => "female"}}} = World.character_login_payload(user_id, c.id)
    assert {:error, :invalid_appearance} =
             World.create_character(user_id, %{"name" => "Bot", "character_type" => "Mage", "model_path" => "x", "appearance" => "nope"})
  end

  test "characters without a stored look get the default for their model", %{user_id: user_id} do
    {:ok, c} = World.create_character(user_id, %{"name" => "Old", "character_type" => "Explorer", "model_path" => "/models/Humans/Male.glb"})
    assert %{"body" => "male", "hair" => %{"style" => "Short"}} = c.appearance
  end

  test "update_appearance keeps the body type and checks ownership", %{user_id: user_id} do
    {:ok, c} = World.create_character(user_id, %{"name" => "Bo", "character_type" => "Bard", "model_path" => "", "appearance" => look("male")})

    assert {:ok, %{"body" => "male", "facial" => %{"style" => "Goatee"}, "skin" => "#FFFFFF"}} =
             World.update_appearance(user_id, c.id, look("female", %{"skin" => "#ffffff", "facial" => %{"style" => "Goatee"}}))

    assert %{appearance: %{"skin" => "#FFFFFF"}, model_path: "/models/Humans/Male.glb"} = World.get_character_for_user(user_id, c.id)
    assert {:error, :not_found} = World.update_appearance(Ecto.UUID.generate(), c.id, look("male"))
    assert {:error, :invalid_appearance} = World.update_appearance(user_id, c.id, "male")
  end

  test "appearances_for: only Bacon World characters, at most 64 ids", %{user_id: user_id} do
    {:ok, a} = World.create_character(user_id, %{"name" => "One", "character_type" => "Bard", "model_path" => "", "appearance" => look("male")})
    {:ok, b} = World.create_character(Ecto.UUID.generate(), %{"name" => "Two", "character_type" => "Bard", "model_path" => "", "appearance" => look("female")})

    looks = World.appearances_for([a.id, b.id, "junk", Ecto.UUID.generate()])
    assert map_size(looks) == 2
    assert %{"body" => "male"} = looks[a.id]
    assert %{"body" => "female"} = looks[b.id]
    assert World.appearances_for(nil) == %{}
    assert World.appearances_for(List.duplicate(a.id, 100)) |> map_size() == 1
  end
end

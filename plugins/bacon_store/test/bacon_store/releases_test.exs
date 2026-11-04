defmodule BaconStore.ReleasesTest do
  # Plugins sold as downloads (2026-11-03): a zip packaged from a release branch carries
  # RELEASE.json; uploading it records the release of that branch and commit.
  use Bacon8.DataCase, async: true

  alias BaconStore.Store.{Catalog, Releases}

  @commit String.duplicate("ab12", 10)

  defp release_zip(manifest, extra \\ [{~c"bacon_world/README.md", "hello"}]) do
    path = Path.join(System.tmp_dir!(), "release_#{System.unique_integer([:positive])}.zip")
    files = extra ++ if(manifest, do: [{~c"RELEASE.json", Jason.encode!(manifest)}], else: [])
    {:ok, _} = :zip.create(String.to_charlist(path), files)
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp manifest(version, plugin \\ "bacon_world"),
    do: %{"plugin" => plugin, "version" => version, "branch" => "release/#{plugin}/#{version}", "commit" => @commit, "built_at" => "2026-11-03T22:00:00Z", "notes" => "first"}

  test "a release zip is recognised; anything else is an ordinary download" do
    assert {:ok, %{"version" => "1.0.0"}} = Releases.read_manifest(release_zip(manifest("1.0.0")))
    assert :none = Releases.read_manifest(release_zip(nil))
    assert :none = Releases.read_manifest(tmp_upload("not a zip"))
    assert {:error, msg} = Releases.read_manifest(release_zip(%{manifest("1.0.0") | "branch" => "main"}))
    assert msg =~ "release/bacon_world/1.0.0"
    assert {:error, _} = Releases.read_manifest(release_zip(%{manifest("1.0.0") | "commit" => "abc"}))
  end

  test "a plugin product: releases by version, one plugin per product, withdrawn ones leave the files" do
    {:ok, product} = Releases.ensure_plugin_product("bacon_world", "Bacon World", 2500)
    assert product.slug == "plugin-bacon-world" and product.active == false and product.kind == "download"
    # asking again finds it (its price stays the owner's)
    {:ok, again} = Releases.ensure_plugin_product("bacon_world", "Bacon World", 9900)
    assert again.id == product.id and again.price_cents == 2500

    {:ok, r1} = Releases.add_release(product, release_zip(manifest("1.0.0")), "bacon_world-1.0.0.zip", manifest("1.0.0"))
    {:ok, r2} = Releases.add_release(product, release_zip(manifest("1.1.0")), "bacon_world-1.1.0.zip", manifest("1.1.0"))
    assert {r1.branch, r1.commit} == {"release/bacon_world/1.0.0", @commit}
    assert Releases.latest(product).id == r2.id

    labels = product.id |> Catalog.get_product_for_admin() |> Catalog.downloads() |> Enum.map(& &1.label)
    assert Enum.sort(labels) == ["v1.0.0", "v1.1.0"]

    assert {:error, msg} = Releases.add_release(product, release_zip(manifest("1.1.0")), "again.zip", manifest("1.1.0"))
    assert msg =~ "already released"
    assert {:error, msg} = Releases.add_release(product, release_zip(manifest("2.0.0", "rays_space_sim")), "rss.zip", manifest("2.0.0", "rays_space_sim"))
    assert msg =~ "sells bacon_world"

    {:ok, yanked} = Releases.yank(r2)
    assert yanked.yanked_at
    assert Releases.latest(product).id == r1.id
    assert product.id |> Catalog.get_product_for_admin() |> Catalog.downloads() |> Enum.map(& &1.label) == ["v1.0.0"]
  end
end

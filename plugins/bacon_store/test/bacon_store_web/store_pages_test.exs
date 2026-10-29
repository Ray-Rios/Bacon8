defmodule BaconStoreWeb.StorePagesTest do
  use Bacon8.DataCase, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Plug.Conn, only: [get_resp_header: 2]

  alias BaconStore.{Store, Wallet}
  alias BaconStore.Store.Catalog

  @endpoint Bacon8Web.Endpoint

  setup do
    # The store is a plugin (ADR 0001, phase 3); tests start with none active.
    {:ok, _} = Bacon8.Plugins.activate("bacon_store")
    on_exit(fn -> :persistent_term.erase({Bacon8.Plugins, :active}) end)
    :ok
  end

  @png <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, "pretend pixels">>

  defp verified(attrs \\ %{}), do: user_fixture(Map.merge(%{email_verified_at: DateTime.utc_now() |> DateTime.truncate(:second)}, attrs))
  defp signed_in(user), do: build_conn() |> Plug.Test.init_test_session(%{"user_id" => user.id})

  defp on_sale_download(attrs \\ %{}) do
    {:ok, p} = Catalog.create_product(Map.merge(%{kind: "download", name: "Song Pack", price_gems: 300, active: true}, attrs))
    {:ok, img} = Catalog.add_file(p, "image", tmp_upload(@png), "cover.png")
    {:ok, file} = Catalog.add_file(p, "download", tmp_upload("zip bytes"), "songs.zip")
    {p, img, file}
  end

  test "an admin creates a download, uploads its image and file, and puts it on sale" do
    conn = signed_in(verified(%{role: "admin", is_admin: true}))

    {:ok, view, html} = live(conn, "/admin/bacon_store/products/new?kind=download")
    assert html =~ "New download"

    view |> form("#product-form", product: %{name: "Synthwave Pack", price: "4.99", price_gems: "499"}) |> render_submit()
    {path, _flash} = assert_redirect(view)
    product = Repo.get_by!(Store.Product, name: "Synthwave Pack")
    assert path == "/admin/bacon_store/products/#{product.id}"
    assert %{price_cents: 499, price_gems: 499, active: false, slug: "synthwave-pack"} = product

    {:ok, view, _} = live(conn, path)
    view |> file_input("#image-upload", :images, [%{name: "cover.png", content: @png, type: "image/png"}]) |> render_upload("cover.png")
    view |> file_input("#download-upload", :downloads, [%{name: "pack.zip", content: "zip", type: "application/zip"}]) |> render_upload("pack.zip")

    product = Catalog.get_product_for_admin(product.id)
    assert [%{filename: "cover.png"}] = Catalog.images(product)
    assert [%{filename: "pack.zip"}] = Catalog.downloads(product)

    view |> form("#product-form", product: %{active: "true"}) |> render_submit()
    assert Repo.get!(Store.Product, product.id).active
  end

  test "the editor shows what's wrong instead of saving" do
    conn = signed_in(verified(%{role: "admin", is_admin: true}))
    {:ok, view, _} = live(conn, "/admin/bacon_store/products/new?kind=item")

    html = view |> form("#product-form", product: %{name: "Sword"}) |> render_submit()
    assert html =~ "set a card price, a Gem price, or both"
    assert html =~ "required for a game item"
    assert Repo.get_by(Store.Product, name: "Sword") == nil
  end

  test "a buyer finds a product, buys it with Gems, and downloads it from the library" do
    {p, _img, file} = on_sale_download()
    user = verified()
    {:ok, _} = Wallet.grant(user, 1000, idempotency_key: "pages-test")

    {:ok, _view, html} = live(build_conn(), "/store")
    assert html =~ "Song Pack"

    # the old page sends you to the item's sheet on the storefront
    assert {:error, {:live_redirect, %{to: to}}} = live(signed_in(user), "/store/p/#{p.slug}")
    assert to == "/store?item=#{p.slug}"

    {:ok, view, html} = live(signed_in(user), to)
    assert html =~ "Pay with Gems"
    view |> element("button", "Pay with Gems") |> render_click()
    view |> element("button", "Confirm") |> render_click()
    assert_redirect(view, "/store/library")
    assert Wallet.balance(user) == 700

    {:ok, _view, html} = live(signed_in(user), "/store/library")
    assert html =~ "songs.zip"

    conn = signed_in(user) |> get("/store/download/#{file.id}")
    assert conn.status == 200
    assert conn.resp_body == "zip bytes"
    assert [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ "attachment"

    assert (signed_in(verified()) |> get("/store/download/#{file.id}")).status == 404
    assert (build_conn() |> get("/store/download/#{file.id}")).status == 404
  end

  describe "the storefront's glass cards (2026-10-28)" do
    test "everything on sale is a card; a click slides its sheet up, and it closes again" do
      {p, img, _} = on_sale_download(%{summary: "Eight tracks.", description: "Made in **2026**."})
      {:ok, pack} = Catalog.create_product(%{kind: "gem_pack", name: "Handful", gems: 500, price_cents: 500, active: true})

      {:ok, view, html} = live(build_conn(), "/store")
      # the cards' styles are on the page itself (not the literal template text)
      assert html =~ "<style data-store-cards"
      assert html =~ ".sc-grid {"
      refute html =~ "Phoenix.HTML.raw"
      assert html =~ ~s(id="sc-#{p.id}")
      assert html =~ ~s(id="sc-#{pack.id}")
      # the card's front shows its uploaded picture (it stands in for the kind's icon) and the
      # back the description
      assert html =~ "/store/media/#{img.id}"
      assert html =~ "<strong>2026</strong>"
      refute html =~ "sheet-"

      view |> render_hook("open_item", %{"slug" => p.slug})
      assert_patch(view, "/store?item=#{p.slug}")
      html = render(view)
      assert html =~ ~s(id="sheet-#{p.id}")
      assert html =~ "Sign in to buy"

      view |> render_hook("close_item", %{})
      assert_patch(view, "/store")
      refute render(view) =~ ~s(id="sheet-)

      # a Gem pack's sheet has its card price
      {:ok, _view, html} = live(build_conn(), "/store?item=#{pack.slug}")
      assert html =~ "Pay $5.00"

      # an unknown item: just the storefront
      {:ok, _view, html} = live(build_conn(), "/store?item=nope")
      refute html =~ ~s(id="sheet-)
    end

    test "the 3D picture: the Gem, a kind's icon, a picture, or the game's own model" do
      assert %{type: :gem} = Catalog.art(%Store.Product{kind: "gem_pack"})
      assert %{type: :spin, src: "/plugins/bacon_store/spin/kind_license_key"} = Catalog.art(%Store.Product{kind: "license_key", files: []})
      assert %{type: :spin, src: "/plugins/bacon_store/spin/kind_access"} = Catalog.art(%Store.Product{kind: "access", files: []})
      assert %{type: :spin, src: "/plugins/bacon_store/spin/kind_download"} = Catalog.art(%Store.Product{kind: "download", files: []})
      assert %{type: :spin, src: "/plugins/bacon_store/spin/kind_item"} = Catalog.art(%Store.Product{kind: "item", grant_kind: "other_game", grant_key: "x", files: []})

      # Bacon World draws its mounts (BaconWorld.Plugin.store_art/2), even with a picture uploaded
      mount = %Store.Product{kind: "item", grant_kind: "bacon_world_mount", grant_key: "frost_drake", files: []}
      assert %{type: :spin, src: "/plugins/bacon_world/store/mount_frost_drake"} = Catalog.art(mount)
    end
  end

  test "images are public while on sale; off sale only admins see them" do
    {p, img, _} = on_sale_download()
    assert (build_conn() |> get("/store/media/#{img.id}")).status == 200

    {:ok, _} = Store.update_product(p, %{active: false})
    assert (build_conn() |> get("/store/media/#{img.id}")).status == 404
    assert (signed_in(verified(%{role: "admin", is_admin: true})) |> get("/store/media/#{img.id}")).status == 200
  end

  describe "core pages show the store through plugin hooks (ADR 0001, phase 2)" do
    test "the admin dashboard shows the store's cards and recent orders" do
      admin = verified(%{role: "admin", is_admin: true})
      {:ok, _view, html} = live(signed_in(admin), "/admin")
      assert html =~ "Products on sale"
      assert html =~ "Revenue today"
      assert html =~ "Recent Orders"
    end

    test "the API toolbox lists and runs the store's action" do
      admin = verified(%{role: "admin", is_admin: true})
      {:ok, view, html} = live(signed_in(admin), "/admin/api-toolbox")
      assert html =~ "List Orders"
      assert html =~ "Store"

      html = render_submit(view, "execute_action", %{"action_id" => "list_orders"})
      assert html =~ "Fetched 0 orders"
    end

    test "the admin sidebar, site navigation and profile link to the store" do
      admin = verified(%{role: "admin", is_admin: true})
      {:ok, _view, html} = live(signed_in(admin), "/admin/bacon_store/orders")
      assert html =~ "/admin/bacon_store/products"

      {:ok, _view, html} = live(signed_in(admin), "/profile")
      assert html =~ ~s{href="/store/orders"}
      assert html =~ ~s{href="/store/library"}
    end

    test "the old core admin paths are gone; the store's admin lives under /admin/bacon_store" do
      admin = verified(%{role: "admin", is_admin: true})
      assert (signed_in(admin) |> get("/admin/products")).status == 404
      assert {:ok, _view, _html} = live(signed_in(admin), "/admin/bacon_store/products")
    end

    test "with the store inactive its pages answer 404 and core pages still render" do
      {:ok, _} = Bacon8.Plugins.deactivate("bacon_store")
      assert (build_conn() |> get("/store")).status == 404

      admin = verified(%{role: "admin", is_admin: true})
      {:ok, _view, html} = live(signed_in(admin), "/admin")
      refute html =~ "Recent Orders"
    end
  end
end

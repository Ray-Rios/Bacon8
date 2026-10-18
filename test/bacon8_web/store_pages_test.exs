defmodule Bacon8Web.StorePagesTest do
  use Bacon8.DataCase, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Plug.Conn, only: [get_resp_header: 2]

  alias Bacon8.{Store, Wallet}
  alias Bacon8.Store.Catalog

  @endpoint Bacon8Web.Endpoint
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

    {:ok, view, html} = live(conn, "/admin/products/new?kind=download")
    assert html =~ "New download"

    view |> form("#product-form", product: %{name: "Synthwave Pack", price: "4.99", price_gems: "499"}) |> render_submit()
    {path, _flash} = assert_redirect(view)
    product = Repo.get_by!(Store.Product, name: "Synthwave Pack")
    assert path == "/admin/products/#{product.id}"
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
    {:ok, view, _} = live(conn, "/admin/products/new?kind=item")

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

    {:ok, view, html} = live(signed_in(user), "/store/p/#{p.slug}")
    assert html =~ "Buy with Gems"
    view |> element("button", "Buy with Gems") |> render_click()
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

  test "images are public while on sale; off sale only admins see them" do
    {p, img, _} = on_sale_download()
    assert (build_conn() |> get("/store/media/#{img.id}")).status == 200

    {:ok, _} = Store.update_product(p, %{active: false})
    assert (build_conn() |> get("/store/media/#{img.id}")).status == 404
    assert (signed_in(verified(%{role: "admin", is_admin: true})) |> get("/store/media/#{img.id}")).status == 200
  end
end

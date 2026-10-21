defmodule BaconStore.StoreDigitalTest do
  # Not async: plugin hub events and the fake provider use global config.
  use Bacon8.DataCase, async: false

  alias Bacon8.{Accounts, Drive, Entitlements, Storage}
  alias BaconStore.{Store, Wallet}
  alias BaconStore.Payments.Fake
  alias BaconStore.Store.{Catalog, Fulfilment, Library}

  @png <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, "not really an image but sniffs as one">>

  defp buyer(gems \\ 0) do
    user = user_fixture(%{email_verified_at: DateTime.utc_now() |> DateTime.truncate(:second)})
    if gems > 0, do: {:ok, _} = Wallet.grant(user, gems, idempotency_key: "test-grant-#{user.id}")
    user
  end

  defp product!(attrs) do
    {:ok, p} = Catalog.create_product(Map.merge(%{active: true}, attrs))
    Repo.preload(p, [:category, :files])
  end

  defp private_channel! do
    Repo.insert!(%Bacon8.Forum.Channel{name: "vip-#{System.unique_integer([:positive])}", is_private: true})
  end

  describe "products" do
    test "each kind has its own rules" do
      assert {:error, cs} = Catalog.create_product(%{kind: "download", name: "No price"})
      assert %{price_cents: ["set a card price, a Gem price, or both"]} = errors_on(cs)

      assert {:error, cs} = Catalog.create_product(%{kind: "download", name: "Too cheap", price_cents: 10})
      assert %{price_cents: [_]} = errors_on(cs)

      assert {:ok, gems_only} = Catalog.create_product(%{kind: "download", name: "Gems Only", price_gems: 250})
      assert gems_only.price_cents == nil

      assert {:error, cs} = Catalog.create_product(%{kind: "item", name: "Sword", price_gems: 100})
      assert %{grant_kind: [_], grant_key: [_]} = errors_on(cs)

      assert {:error, cs} = Catalog.create_product(%{kind: "access", name: "VIP", price_gems: 100, grant_kind: "channel"})
      assert %{grant_key: [_]} = errors_on(cs)

      assert {:ok, slots} =
               Catalog.create_product(%{kind: "access", name: "Slots", price_gems: 100, grant_kind: "channel_slots", grant_quantity: 3, duration_days: 30})

      assert slots.duration_days == nil

      assert {:error, cs} = Catalog.create_product(%{kind: "gem_pack", name: "Loop", price_cents: 100, gems: 100, price_gems: 50})
      assert %{price_gems: [_]} = errors_on(cs)
    end

    test "a blank slug is made from the name, and kept unique" do
      assert {:ok, %{slug: "falcon-ship"}} = Catalog.create_product(%{kind: "download", name: "Falcon Ship!", price_gems: 1})
      assert {:ok, %{slug: "falcon-ship-2"}} = Catalog.create_product(%{kind: "download", name: "Falcon ship", price_gems: 1})
    end

    test "the storefront shows products on sale, by category, never Gem packs" do
      {:ok, music} = Catalog.create_category(%{name: "Music"})
      on = product!(%{kind: "download", name: "Album", price_gems: 10, category_id: music.id})
      _off = product!(%{kind: "download", name: "Hidden", price_gems: 10, active: false})

      assert Enum.map(Catalog.storefront(), & &1.id) == [on.id]
      assert Enum.map(Catalog.storefront("music"), & &1.id) == [on.id]
      assert Catalog.storefront("nope") == []
      assert [%{slug: "music"}] = Catalog.storefront_categories()
    end
  end

  describe "files" do
    test "images must be images; files share the blob store and survive blob GC" do
      p = product!(%{kind: "download", name: "Pack", price_gems: 10})

      assert {:error, :not_an_image} = Catalog.add_file(p, "image", tmp_upload("plain text"), "fake.png")
      assert {:ok, img} = Catalog.add_file(p, "image", tmp_upload(@png), "cover.png")
      assert img.content_type == "image/png"
      assert {:ok, dl} = Catalog.add_file(p, "download", tmp_upload("zip bytes"), "C:\\Users\\me\\game.zip", label: "Windows")
      assert dl.filename == "game.zip" and dl.label == "Windows"

      assert Drive.gc_blobs(-60) == 0
      assert Storage.exists?(dl.sha256)

      {:ok, _} = Catalog.delete_file(dl)
      assert Drive.gc_blobs(-60) == 1
      refute Storage.exists?(dl.sha256)
      assert Storage.exists?(img.sha256)
    end
  end

  describe "buying with Gems" do
    test "a download: Gems spent once, in the library, can't be bought twice" do
      p = product!(%{kind: "download", name: "Soundtrack", price_gems: 300})
      {:ok, file} = Catalog.add_file(p, "download", tmp_upload("music"), "ost.zip")
      user = buyer(1000)

      assert {:ok, order} = Store.buy_with_gems(user, p)
      assert %{status: "fulfilled", provider: "gems", amount_gems: 300} = order
      assert Wallet.balance(user) == 700
      assert Library.can_download?(user, file)
      refute Library.can_download?(buyer(), file)
      assert [%{id: id}] = Library.downloads(user)
      assert id == p.id

      assert {:error, :already_owned} = Store.buy_with_gems(user, p)
      assert Wallet.balance(user) == 700
    end

    test "not enough Gems leaves nothing behind" do
      p = product!(%{kind: "download", name: "Pricey", price_gems: 5000})
      user = buyer(100)

      assert {:error, :insufficient_gems} = Store.buy_with_gems(user, p)
      assert Wallet.balance(user) == 100
      assert Store.list_user_orders(user) == []
      refute Entitlements.active?(user, Fulfilment.download_kind(), p.id)
    end

    test "a card-only product can't be bought with Gems, and Gem packs never" do
      card_only = product!(%{kind: "download", name: "Card", price_cents: 500})
      assert {:error, :not_for_gems} = Store.buy_with_gems(buyer(1000), card_only)
      assert {:error, :not_for_gems} = Store.buy_with_gems(buyer(1000), Repo.get_by!(Store.Product, slug: "gems_500"))
    end

    test "a game item is granted, tells plugins, and can be limited to one" do
      p = product!(%{kind: "item", name: "Gold Sword", price_gems: 100, grant_kind: "fixture.item", grant_key: "sword", duration_days: 7, one_per_user: true})
      user = buyer(1000)

      assert {:ok, _} = Store.buy_with_gems(user, p)
      assert Entitlements.active?(user, "fixture.item", "sword")
      assert_received {:fixture_hub_event, {:entitlement_granted, %{kind: "fixture.item", key: "sword", ends_at: ends}}}
      assert DateTime.diff(ends, DateTime.utc_now(), :day) in 6..7
      assert {:error, :already_owned} = Store.purchase_check(user, p)

      # When the week is up the sweeper ends it, and plugins hear about that too.
      assert Fulfilment.expire(DateTime.add(DateTime.utc_now(), 8 * 86_400, :second)) == 1
      assert_received {:fixture_hub_event, {:entitlement_revoked, %{revoked_reason: "expired"}}}
      assert :ok = Store.purchase_check(user, p)
    end

    test "a channel pass joins the channel, stacks, and leaves when it runs out" do
      channel = private_channel!()
      p = product!(%{kind: "access", name: "VIP month", price_gems: 100, grant_kind: "channel", grant_key: channel.id, duration_days: 30})
      user = buyer(1000)

      assert {:ok, _} = Store.buy_with_gems(user, p)
      assert Bacon8.Forum.is_channel_member?(channel.id, user.id)

      # Buying again while it runs adds 30 days to the end.
      assert {:ok, _} = Store.buy_with_gems(user, p)
      last = user |> Entitlements.active("channel_access") |> Enum.map(& &1.ends_at) |> Enum.max(DateTime)
      assert DateTime.diff(last, DateTime.utc_now(), :day) in 59..60

      # After the first pass ends the second keeps them in; after both, they're out.
      Fulfilment.expire(DateTime.add(DateTime.utc_now(), 31 * 86_400, :second))
      assert Bacon8.Forum.is_channel_member?(channel.id, user.id)
      Fulfilment.expire(DateTime.add(DateTime.utc_now(), 61 * 86_400, :second))
      refute Bacon8.Forum.is_channel_member?(channel.id, user.id)
    end

    test "existing members can't buy a pass to a channel they're in" do
      channel = private_channel!()
      p = product!(%{kind: "access", name: "VIP", price_gems: 100, grant_kind: "channel", grant_key: channel.id})
      user = buyer(1000)
      {:ok, _} = Bacon8.Forum.create_channel_member(%{channel_id: channel.id, user_id: user.id, role: "member"})

      assert {:error, :already_member} = Store.buy_with_gems(user, p)
    end

    test "channel slots raise the allowance for good" do
      p = product!(%{kind: "access", name: "3 slots", price_gems: 100, grant_kind: "channel_slots", grant_quantity: 3})
      user = buyer(1000)
      before = Bacon8.Forum.channel_allowance(user.id)

      assert {:ok, _} = Store.buy_with_gems(user, p)
      assert Bacon8.Forum.channel_allowance(user.id) == before + 3
    end

    test "license keys: one per sale, then sold out" do
      p = product!(%{kind: "license_key", name: "Game key", price_gems: 100})
      assert {:ok, %{added: 1, skipped: 1}} = Catalog.add_license_keys(p, "AAAA-1111\n\nAAAA-1111\n")
      user = buyer(1000)

      assert {:ok, _} = Store.buy_with_gems(user, p)
      assert [%{code: "AAAA-1111"}] = Library.for_user(user).keys
      assert {:error, :sold_out} = Store.buy_with_gems(buyer(1000), p)
      assert %{available: 0, sold: 1} = Catalog.key_counts(p)
    end
  end

  describe "buying with a card" do
    test "a key is reserved during checkout and returned if the card is declined" do
      p = product!(%{kind: "license_key", name: "Key", price_cents: 500})
      {:ok, _} = Catalog.add_license_keys(p, "ONLY-ONE")

      {:ok, order, _} = Store.start_checkout(buyer(), p)
      assert %{reserved: 1, available: 0} = Catalog.key_counts(p)
      assert {:error, :sold_out} = Store.purchase_check(buyer(), p)

      :ok = Fake.fail(order.provider_ref)
      assert %{reserved: 0, available: 1} = Catalog.key_counts(p)
    end

    test "paid after the keys ran out: kept as paid for an admin to fix, then delivered" do
      p = product!(%{kind: "license_key", name: "Key", price_cents: 500, price_gems: 500})
      {:ok, _} = Catalog.add_license_keys(p, "FIRST")
      late = buyer()

      {:ok, order, _} = Store.start_checkout(late, p)
      {:ok, _} = Store.cancel_unpaid(order)
      {:ok, _} = Store.buy_with_gems(buyer(1000), p)

      # The late buyer pays anyway on the provider's page.
      assert :ok = Fake.complete(order.provider_ref, 500)
      assert %{status: "paid", failure_reason: reason} = Store.get_order(order.id)
      assert reason =~ "license keys"

      {:ok, _} = Catalog.add_license_keys(p, "SECOND")
      assert {:ok, %{status: "fulfilled"}} = Store.retry_delivery(Store.get_order(order.id))
      assert [%{code: "SECOND"}] = Library.for_user(late).keys
    end

    test "an open dispute takes away the download, the pass and the slots; winning gives them back" do
      dl = product!(%{kind: "download", name: "DL", price_cents: 500})
      {:ok, file} = Catalog.add_file(dl, "download", tmp_upload("y"), "y.zip")
      channel = private_channel!()
      pass = product!(%{kind: "access", name: "VIP", price_cents: 500, grant_kind: "channel", grant_key: channel.id})
      slots = product!(%{kind: "access", name: "Slots", price_cents: 500, grant_kind: "channel_slots", grant_quantity: 2})
      user = buyer()
      base = Bacon8.Forum.channel_allowance(user.id)

      orders =
        for p <- [dl, pass, slots] do
          {:ok, order, _} = Store.start_checkout(user, p)
          :ok = Fake.complete(order.provider_ref, 500)
          order
        end

      for o <- orders, do: :ok = Fake.dispute(o.provider_ref, :dispute_opened)
      refute Library.can_download?(user, file)
      refute Bacon8.Forum.is_channel_member?(channel.id, user.id)
      assert Bacon8.Forum.channel_allowance(user.id) == base
      assert Enum.any?(Library.for_user(user).grants, &(&1.state == :on_hold))
      assert_received {:fixture_hub_event, {:entitlement_revoked, %{revoked_reason: "disputed"}}}

      for o <- orders, do: :ok = Fake.dispute(o.provider_ref, :dispute_won)
      assert Library.can_download?(user, file)
      assert Bacon8.Forum.is_channel_member?(channel.id, user.id)
      assert Bacon8.Forum.channel_allowance(user.id) == base + 2
      assert_received {:fixture_hub_event, {:entitlement_granted, %{kind: "channel_access"}}}
    end

    test "a license key is on hold during a dispute and gone if it's lost" do
      p = product!(%{kind: "license_key", name: "Key", price_cents: 500})
      {:ok, _} = Catalog.add_license_keys(p, "HOLD-ME")
      user = buyer()
      {:ok, order, _} = Store.start_checkout(user, p)
      :ok = Fake.complete(order.provider_ref, 500)

      :ok = Fake.dispute(order.provider_ref, :dispute_opened)
      assert [%{revoked_at: %DateTime{}, order: %{status: "disputed"}}] = Library.for_user(user).keys
      :ok = Fake.dispute(order.provider_ref, :dispute_lost)
      assert [%{revoked_at: %DateTime{}, order: %{status: "charged_back"}}] = Library.for_user(user).keys
    end

    test "a lost chargeback takes back a download and channel slots" do
      dl = product!(%{kind: "download", name: "DL", price_cents: 500})
      {:ok, file} = Catalog.add_file(dl, "download", tmp_upload("x"), "x.zip")
      slots = product!(%{kind: "access", name: "Slots", price_cents: 500, grant_kind: "channel_slots", grant_quantity: 2})
      user = buyer()
      base = Bacon8.Forum.channel_allowance(user.id)

      for p <- [dl, slots] do
        {:ok, order, _} = Store.start_checkout(user, p)
        :ok = Fake.complete(order.provider_ref, 500)
        :ok = Fake.dispute(order.provider_ref, :dispute_opened)
        :ok = Fake.dispute(order.provider_ref, :dispute_lost)
      end

      refute Library.can_download?(Repo.reload(user), file)
      assert Bacon8.Forum.channel_allowance(user.id) == base
    end
  end

  describe "deleting a user" do
    test "a buyer is anonymized, not deleted; someone who never bought is deleted" do
      p = product!(%{kind: "download", name: "DL", price_gems: 10})
      bought = buyer(100)
      {:ok, _} = Store.buy_with_gems(bought, p)

      assert {:ok, _} = Accounts.delete_user(bought)
      kept = Repo.get!(Bacon8.Accounts.User, bought.id)
      assert kept.email == "deleted-#{bought.id}@deleted.invalid"
      assert kept.status == "disabled"
      refute Entitlements.active?(kept, Fulfilment.download_kind(), p.id)
      assert [_] = Store.list_user_orders(kept)

      never = buyer()
      assert {:ok, _} = Accounts.delete_user(never)
      assert Repo.get(Bacon8.Accounts.User, never.id) == nil
    end
  end
end

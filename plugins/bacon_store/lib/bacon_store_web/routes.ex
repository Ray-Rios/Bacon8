defmodule BaconStoreWeb.Routes do
  @moduledoc """
  Bacon Store's routes (BACON8.md §8, §9). The pages keep the paths they had in
  core: the plugin mounts at /store.
  """
  use Bacon8.Plugin.Routes

  # /store/...: products, the buyer's library, purchase history, and the fake
  # provider's checkout page (refuses unless the fake provider is enabled).
  site do
    live "/", StoreLive, :index
    live "/p/:slug", StoreProductLive, :show
    live "/library", StoreLibraryLive, :index
    live "/orders", StoreOrderLive, :index
    live "/orders/:id", StoreOrderLive, :show
    live "/fake-checkout/:ref", FakeCheckoutLive, :show
  end

  # Product images (public) and downloads (buyers only). Not :browser, whose
  # `accepts ["html"]` would refuse some <img>/<video> requests.
  site pipe_through: :drive_files do
    get "/media/:id", StoreFileController, :media
    get "/download/:id", StoreFileController, :download
  end

  # Payment provider webhooks: /api/store/webhooks/<provider>. Authenticated by
  # the provider's signature over the raw body (raw_body_paths/0).
  site_api pipe_through: :webhooks do
    post "/webhooks/:provider", PaymentWebhookController, :create
  end

  # /admin/bacon_store/...
  admin do
    live "/products", Admin.ProductsLive, :index
    live "/products/new", Admin.ProductEditorLive, :new
    live "/products/:id", Admin.ProductEditorLive, :edit
    live "/orders", Admin.OrdersLive, :index
    live "/orders/:id", Admin.OrdersLive, :show
  end
end

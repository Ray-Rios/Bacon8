defmodule BaconStoreWeb.StoreProductLive do
  @moduledoc """
  /store/p/:slug - an item's old page. Since 2026-10-28 an item's details and its pay buttons
  are a sheet that slides up over the storefront (`BaconStoreWeb.StoreLive`, `?item=<slug>`), so
  this sends links that still name the old page (the game's stable, the admin's "view" links,
  bookmarks) there.
  """
  use Bacon8Web, :live_view

  alias BaconStore.Store.Catalog

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Catalog.get_active_product_by_slug(slug) do
      nil -> {:ok, socket |> put_flash(:error, "That product isn't available.") |> push_navigate(to: ~p"/store")}
      p -> {:ok, push_navigate(socket, to: "/store?" <> URI.encode_query(%{"item" => p.slug}))}
    end
  end

  @impl true
  def render(assigns), do: ~H""
end

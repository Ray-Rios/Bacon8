defmodule BaconStoreWeb.StoreComponents do
  @moduledoc "Pieces shared by the store pages (BACON8.md §8)."
  use Phoenix.Component
  use Phoenix.VerifiedRoutes, endpoint: Bacon8Web.Endpoint, router: Bacon8Web.Router, statics: Bacon8Web.static_paths()

  alias BaconStore.Store
  alias BaconStore.Store.{Catalog, Product}

  @doc "URL of a product image."
  def media_url(%{id: id}), do: ~p"/store/media/#{id}"

  def kind_icon("gem_pack"), do: "💎"
  def kind_icon("download"), do: "⬇️"
  def kind_icon("item"), do: "⚔️"
  def kind_icon("access"), do: "🎟️"
  def kind_icon("license_key"), do: "🔑"
  def kind_icon(_), do: "🛍️"

  @doc "A product kind's icon on a page: the Gem (`<b8-gem>`, it floats and reacts) for Gem packs."
  attr :kind, :string, required: true
  attr :size, :integer, default: 20

  def kind_glyph(%{kind: "gem_pack"} = assigns), do: ~H"<Bacon8Web.Components.Gem.gem size={@size} />"
  def kind_glyph(assigns), do: ~H"{kind_icon(@kind)}"

  # The cards' and the sheet's styles, inlined so the first paint has them (store_cards.css).
  @css_path Path.expand("../../../priv/store_cards.css", __DIR__)
  @external_resource @css_path
  # (the whole tag, built here: HEEx doesn't interpolate inside <style>, so `<style>{@css}</style>`
  # would put the literal text on the page)
  @style_tag "<style data-store-cards>" <> File.read!(@css_path) <> "</style>"

  @doc "The storefront's card and sheet styles (priv/store_cards.css), once per page."
  def store_styles(assigns) do
    assigns = assign(assigns, :tag, Phoenix.HTML.raw(@style_tag))

    ~H"""
    {@tag}
    """
  end

  @doc """
  The product's picture (`BaconStore.Store.Catalog.art/1`): the Gem, the item turning in 3D
  (`<b8-spin>`, assets/js/store_spin.ts) or an uploaded picture. `still`: no idle turn (the
  blurred copy on a card's back).
  """
  attr :art, :map, required: true
  attr :still, :boolean, default: false
  attr :alt, :string, default: ""

  def art(%{art: %{type: :gem}} = assigns), do: ~H"<Bacon8Web.Components.Gem.gem still={@still} calm={@still} />"

  def art(%{art: %{type: :spin}} = assigns) do
    ~H"""
    <b8-spin src={@art.src} glow={@art.glow} still={@still} style={"--still:url(#{@art.src}.webp)"}></b8-spin>
    """
  end

  def art(%{art: %{type: :image}} = assigns) do
    ~H"""
    <img src={@art.url} alt={@alt} class="sc-img cover" loading="lazy" draggable="false" />
    """
  end

  @doc "A card's tint, from its art's glow colour (\"#RRGGBB\" -> rgba with `alpha`)."
  def tint(%{glow: "#" <> hex}, alpha) when byte_size(hex) == 6 do
    <<r::binary-2, g::binary-2, b::binary-2>> = hex
    "rgba(#{String.to_integer(r, 16)}, #{String.to_integer(g, 16)}, #{String.to_integer(b, 16)}, #{alpha})"
  end

  def tint(_art, alpha), do: "rgba(59, 130, 246, #{alpha})"

  @doc """
  A product as a glass card (priv/store_cards.css, the `StoreCard` hook): the item in 3D on the
  front with its name and price; turned over, the item blurred behind frosted glass with what it
  is. A click opens its sheet in `BaconStoreWeb.StoreLive` (`"open_item"`).
  """
  attr :product, Product, required: true
  attr :owned, :boolean, default: false

  def store_card(assigns) do
    p = assigns.product
    art = Catalog.art(p)
    assigns = assign(assigns, art: art, style: "--sc-tint:#{tint(art, 0.26)};--sc-shadow:#{tint(art, 0.5)}")

    ~H"""
    <div
      id={"sc-#{@product.id}"}
      class="sc"
      phx-hook="StoreCard"
      data-slug={@product.slug}
      data-spin-host
      data-gem-host
      tabindex="0"
      role="button"
      aria-label={"#{@product.name}: details and buying"}
      style={@style}
    >
      <div class="sc-inner">
        <div class="sc-face sc-front">
          <div class="sc-stage"><.art art={@art} alt={@product.name} /></div>
          <div class="sc-gloss"></div>
          <span :if={@product.badge} class="sc-badge">{@product.badge}</span>
          <span :if={@owned} class="sc-owned">Owned</span>
          <div class="sc-title">
            <div class="sc-kind">{Catalog.kind_label(@product.kind)}</div>
            <h3>{@product.name}</h3>
            <.card_price product={@product} />
          </div>
        </div>
        <div class="sc-face sc-back">
          <div class="sc-blur"><.art art={@art} still /></div>
          <div class="sc-gloss"></div>
          <div class="sc-panel">
            <div class="sc-kind">{Catalog.kind_label(@product.kind)}</div>
            <h3>{@product.name}</h3>
            <div class="sc-desc">
              <p :if={@product.summary}>{@product.summary}</p>
              {description_html(@product.description)}
            </div>
            <div class="sc-gets">{Catalog.describe(@product)}</div>
            <span class="sc-more">{if @owned, do: "Details", else: "View & buy"}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc "A card's price line: \"$4.99 or 💎 499\" (a Gem pack: its Gems for its price)."
  attr :product, Product, required: true

  def card_price(%{product: %{kind: "gem_pack"}} = assigns) do
    ~H"""
    <div class="sc-price"><span class="cash">{Store.format_price(@product.price_cents, @product.currency)}</span></div>
    """
  end

  def card_price(assigns) do
    ~H"""
    <div class="sc-price">
      <span :if={@product.price_cents} class="cash">{Store.format_price(@product.price_cents, @product.currency)}</span>
      <span :if={@product.price_cents && @product.price_gems} class="or">or</span>
      <span :if={@product.price_gems} class="gems"><Bacon8Web.Components.Gem.gems amount={@product.price_gems} /></span>
    </div>
    """
  end

  @doc "A product tile for the storefront grid (the old tile; the storefront uses `store_card/1`)."
  attr :product, Product, required: true
  attr :owned, :boolean, default: false

  def product_card(assigns) do
    assigns = assign(assigns, cover: Catalog.cover(assigns.product))

    ~H"""
    <.link
      navigate={~p"/store/p/#{@product.slug}"}
      class="group flex flex-col overflow-hidden rounded-xl border border-gray-800 bg-gray-950/80 transition hover:-translate-y-0.5 hover:border-blue-500/70 hover:shadow-lg hover:shadow-blue-900/20"
    >
      <div class="relative aspect-[16/10] overflow-hidden bg-gradient-to-br from-gray-900 to-gray-800">
        <img
          :if={@cover}
          src={media_url(@cover)}
          alt=""
          loading="lazy"
          class="h-full w-full object-cover transition duration-300 group-hover:scale-[1.03]"
        />
        <div :if={!@cover} class="flex h-full w-full items-center justify-center text-5xl opacity-80">
          <.kind_glyph kind={@product.kind} size={84} />
        </div>
        <span :if={@product.badge} class="absolute left-3 top-3 rounded-full bg-blue-600 px-2.5 py-0.5 text-xs font-semibold text-white shadow">
          {@product.badge}
        </span>
        <span :if={@owned} class="absolute right-3 top-3 rounded-full bg-green-600 px-2.5 py-0.5 text-xs font-semibold text-white shadow">
          Owned
        </span>
      </div>
      <div class="flex flex-1 flex-col p-4">
        <div class="text-xs font-medium uppercase tracking-wider text-gray-500">{Catalog.kind_label(@product.kind)}</div>
        <div class="mt-1 text-lg font-semibold leading-snug text-white">{@product.name}</div>
        <p :if={@product.summary} class="mt-1 line-clamp-2 text-sm text-gray-400">{@product.summary}</p>
        <div class="mt-auto pt-4"><.price_tags product={@product} /></div>
      </div>
    </.link>
    """
  end

  @doc "The product's card and/or Gem price."
  attr :product, Product, required: true
  attr :size, :string, default: "sm"

  def price_tags(assigns) do
    ~H"""
    <div class={["flex flex-wrap items-center gap-2", @size == "lg" && "text-xl", @size != "lg" && "text-sm"]}>
      <span :if={@product.price_cents} class="font-semibold text-white">
        {Store.format_price(@product.price_cents, @product.currency)}
      </span>
      <span :if={@product.price_cents && @product.price_gems} class="text-gray-600">or</span>
      <span :if={@product.price_gems} class="font-semibold text-sky-300"><Bacon8Web.Components.Gem.gems amount={@product.price_gems} /></span>
    </div>
    """
  end

  @doc """
  An admin-written description as HTML. Everything is escaped first, then a
  little formatting is applied: blank lines make paragraphs, lines starting
  with "- " make a list, **bold** and *italic*. No links or raw HTML.
  """
  def description_html(nil), do: ""

  def description_html(text) when is_binary(text) do
    text
    |> String.replace("\r\n", "\n")
    |> String.trim()
    |> String.split(~r/\n{2,}/)
    |> Enum.map(&block/1)
    |> Enum.join("\n")
    |> Phoenix.HTML.raw()
  end

  defp block(chunk) do
    lines = String.split(chunk, "\n")

    if Enum.all?(lines, &String.starts_with?(&1, "- ")) do
      items = Enum.map_join(lines, "", &"<li>#{inline(String.slice(&1, 2..-1//1))}</li>")
      ~s(<ul class="list-disc space-y-1 pl-5">#{items}</ul>)
    else
      "<p>" <> Enum.map_join(lines, "<br>", &inline/1) <> "</p>"
    end
  end

  defp inline(line) do
    line
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
    |> String.replace(~r/\*\*(.+?)\*\*/, "<strong>\\1</strong>")
    |> String.replace(~r/(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])/, "<em>\\1</em>")
  end

  @doc """
  The viewer's time zone, from the LiveView connect params (`timezone`, sent
  by app.ts), or "Etc/UTC" before the socket connects or if it's unknown.
  Call from `mount/3`.
  """
  def timezone(socket) do
    with true <- Phoenix.LiveView.connected?(socket),
         %{"timezone" => tz} when is_binary(tz) <- Phoenix.LiveView.get_connect_params(socket),
         {:ok, _} <- DateTime.shift_zone(DateTime.utc_now(), tz) do
      tz
    else
      _ -> "Etc/UTC"
    end
  end

  @doc "\"Oct 16, 2026, 4:27 PM\" in `tz` (with \"UTC\" when that's all we know)."
  def local_datetime(nil, _tz), do: ""

  def local_datetime(%DateTime{} = dt, tz) do
    local =
      case DateTime.shift_zone(dt, tz) do
        {:ok, shifted} -> shifted
        _ -> dt
      end

    Calendar.strftime(local, "%b %-d, %Y, %-I:%M %p") <> if(local.time_zone == "Etc/UTC", do: " UTC", else: "")
  end

  @doc "\"Oct 16, 2026\" in `tz`."
  def local_date(nil, _tz), do: ""

  def local_date(%DateTime{} = dt, tz) do
    case DateTime.shift_zone(dt, tz) do
      {:ok, shifted} -> Calendar.strftime(shifted, "%b %-d, %Y")
      _ -> Calendar.strftime(dt, "%b %-d, %Y")
    end
  end

  @doc """
  A purchase as a receipt card (2026-10-29): "Order #8008", each item with its price, the total and
  a stamp for its state (Paid, Pending, Void, Disputed, Charged back), like the front page's.
  `receipt` is `BaconStore.Store.receipt/1`. With `href` the card is a link; `show_buyer` adds the
  buyer's email (admins); `tz` sets the date's time zone.
  """
  attr :receipt, :map, required: true
  attr :href, :string, default: nil
  attr :patch, :boolean, default: false, doc: "the link patches (same LiveView) rather than navigates"
  attr :tz, :string, default: "Etc/UTC"
  attr :show_buyer, :boolean, default: false
  attr :id, :string, default: nil
  slot :inner_block

  def receipt(assigns) do
    ~H"""
    <.link :if={@href} id={@id} navigate={!@patch && @href} patch={@patch && @href} class="rc">
      <.receipt_body receipt={@receipt} tz={@tz} show_buyer={@show_buyer} />
      {render_slot(@inner_block)}
    </.link>
    <div :if={!@href} id={@id} class="rc">
      <.receipt_body receipt={@receipt} tz={@tz} show_buyer={@show_buyer} />
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :receipt, :map, required: true
  attr :tz, :string, required: true
  attr :show_buyer, :boolean, default: false

  defp receipt_body(assigns) do
    ~H"""
    <div class="rc-head">
      <Bacon8Web.Components.Bacon.bacon size={22} still calm />
      <span>
        Order #{@receipt.number || String.slice(@receipt.lead.id, 0, 6)}
        <span class="rc-date">{local_datetime(@receipt.inserted_at, @tz)}</span>
        <span :if={@show_buyer && @receipt.user} class="rc-buyer">{@receipt.user.email}</span>
      </span>
    </div>
    <div :for={o <- @receipt.orders} class="rc-line">
      <span>
        <.kind_glyph kind={o.product && o.product.kind} size={16} />
        {o.product_name}
        <span :if={o.status != @receipt.status} class="rc-tag">{stamp_label(o.status)}</span>
        <span :if={o.status == "paid" && o.failure_reason} class="rc-note">Paid; being delivered.</span>
      </span>
      <span>{BaconStore.Store.order_price(o)}</span>
    </div>
    <div class="rc-total"><span>Total</span><span>{@receipt.total}</span></div>
    <div class={["rc-stamp", stamp_class(@receipt.status)]}>{stamp_label(@receipt.status)}</div>
    """
  end

  @doc "The stamp on a receipt for an order status."
  def stamp_label(status) when status in ["paid", "fulfilled"], do: "Paid"
  def stamp_label("awaiting_payment"), do: "Unpaid"
  def stamp_label(status) when status in ["failed", "cancelled"], do: "Void"
  def stamp_label("disputed"), do: "Disputed"
  def stamp_label("charged_back"), do: "Charged back"
  def stamp_label(other), do: to_string(other)

  defp stamp_class(status) when status in ["paid", "fulfilled"], do: "is-paid"
  defp stamp_class("awaiting_payment"), do: "is-pending"
  defp stamp_class("disputed"), do: "is-disputed"
  defp stamp_class("charged_back"), do: "is-lost"
  defp stamp_class(_), do: "is-void"

  @doc """
  Small print under Buy buttons. The linked pages are CMS pages (/admin/pages),
  seeded as unpublished placeholders on 2026-10-21; publish them before taking
  real payments.
  """
  def small_print(assigns) do
    ~H"""
    <p class="text-xs text-gray-500">
      All sales are final (<a href="/pages/refunds" class="underline hover:text-gray-300">refunds &amp; cancellations</a>).
      Gems have no cash value (<a href="/pages/gems" class="underline hover:text-gray-300">Gems &amp; promotions</a>).
      Buying means you accept the <a href="/pages/terms" class="underline hover:text-gray-300">Terms</a>
      and the <a href="/pages/privacy" class="underline hover:text-gray-300">Privacy Policy</a>.
    </p>
    """
  end
end

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

  @doc "A product tile for the storefront grid."
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

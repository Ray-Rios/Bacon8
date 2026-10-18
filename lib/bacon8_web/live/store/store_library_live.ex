defmodule Bacon8Web.StoreLibraryLive do
  @moduledoc """
  /store/library - what the user owns from the store (BACON8.md §8):
  downloads with their current files, license keys, and items and passes.
  """
  use Bacon8Web, :live_view

  import Bacon8Web.StoreComponents
  alias Bacon8.Store.{Catalog, Library}

  on_mount {Bacon8Web.UserAuth, :require_authenticated_user}

  @impl true
  def mount(_params, _session, socket) do
    lib = Library.for_user(socket.assigns.current_user)

    {:ok,
     assign(socket,
       page_title: "Library",
       tz: timezone(socket),
       lib: lib,
       empty?: lib.downloads == [] and lib.keys == [] and lib.grants == []
     )}
  end

  @impl true
  def handle_event(event, _params, socket) when event in ["toggle_calendar", "toggle_start_menu", "open_app"],
    do: {:noreply, socket}

  defp state_text(:forever, _tz), do: "Yours to keep"
  defp state_text({:until, dt}, tz), do: "Until #{local_date(dt, tz)}"
  defp state_text({:expired, dt}, tz), do: "Ended #{local_date(dt, tz)}"
  defp state_text(:revoked, _tz), do: "Taken back (chargeback)"
  defp state_text(:on_hold, _tz), do: "On hold: your bank is disputing this payment"

  defp active?(state), do: state == :forever or match?({:until, _}, state)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="fixed top-[30px] inset-x-0 bottom-0 z-40 overflow-y-auto bg-black">
      <div class="mx-auto max-w-4xl px-6 py-12">
        <div class="mb-8 flex flex-wrap items-end justify-between gap-4">
          <div>
            <h1 class="text-4xl font-bold tracking-tight text-white">Library</h1>
            <p class="mt-2 text-gray-400">Everything you've bought. Downloads always get the latest files.</p>
          </div>
          <div class="flex gap-4 text-sm">
            <.link navigate={~p"/store"} class="text-blue-400 hover:underline">Store</.link>
            <.link navigate={~p"/store/orders"} class="text-blue-400 hover:underline">Purchase history</.link>
          </div>
        </div>

        <div :if={@empty?} class="rounded-2xl border border-gray-800 bg-gray-950/80 px-6 py-16 text-center">
          <p class="text-gray-400">Nothing here yet.</p>
          <.link navigate={~p"/store"} class="mt-4 inline-block rounded-lg bg-blue-600 px-4 py-2 font-semibold text-white hover:bg-blue-500">
            Browse the store
          </.link>
        </div>

        <section :if={@lib.downloads != []} class="mb-12">
          <h2 class="mb-4 text-xl font-semibold text-white">Downloads</h2>
          <div class="space-y-4">
            <div :for={p <- @lib.downloads} class="flex gap-4 rounded-xl border border-gray-800 bg-gray-950/80 p-4">
              <div class="h-20 w-32 flex-shrink-0 overflow-hidden rounded-lg bg-gray-900">
                <img :if={Catalog.cover(p)} src={media_url(Catalog.cover(p))} alt="" class="h-full w-full object-cover" />
                <div :if={!Catalog.cover(p)} class="flex h-full items-center justify-center text-3xl">⬇️</div>
              </div>
              <div class="min-w-0 flex-1">
                <.link navigate={~p"/store/p/#{p.slug}"} class="font-semibold text-white hover:underline">{p.name}</.link>
                <ul class="mt-2 space-y-1.5">
                  <li :for={f <- Catalog.downloads(p)} class="flex flex-wrap items-center justify-between gap-2 text-sm">
                    <span class="min-w-0 truncate text-gray-300">
                      {f.label || f.filename}
                      <span class="text-gray-600">· {Catalog.format_bytes(f.byte_size)}</span>
                    </span>
                    <a href={~p"/store/download/#{f.id}"} class="rounded-md bg-blue-600 px-3 py-1 text-xs font-semibold text-white hover:bg-blue-500">
                      Download
                    </a>
                  </li>
                </ul>
                <p :if={Catalog.downloads(p) == []} class="mt-2 text-sm text-gray-500">The files are being updated. Check back soon.</p>
              </div>
            </div>
          </div>
        </section>

        <section :if={@lib.keys != []} class="mb-12">
          <h2 class="mb-4 text-xl font-semibold text-white">License keys</h2>
          <div class="divide-y divide-gray-800 rounded-xl border border-gray-800 bg-gray-950/80">
            <div :for={k <- @lib.keys} class="flex flex-wrap items-center justify-between gap-3 px-4 py-3">
              <div class="min-w-0">
                <div class="text-sm text-gray-400">{k.product.name} · {local_date(k.sold_at, @tz)}</div>
                <code id={"key-#{k.id}"} class={["select-all break-all font-mono text-white", k.revoked_at && "line-through opacity-50"]}>{k.code}</code>
                <div :if={k.revoked_at} class="text-xs text-red-300">
                  {if k.order && k.order.status == "disputed",
                    do: "On hold: your bank is disputing this payment.",
                    else: "Revoked after a chargeback."}
                </div>
              </div>
              <button
                :if={!k.revoked_at}
                id={"copy-#{k.id}"}
                type="button"
                phx-hook="CopyText"
                data-target={"key-#{k.id}"}
                class="rounded-md bg-gray-800 px-3 py-1 text-xs font-semibold text-gray-200 hover:bg-gray-700"
              >
                Copy
              </button>
            </div>
          </div>
        </section>

        <section :if={@lib.grants != []} class="mb-12">
          <h2 class="mb-4 text-xl font-semibold text-white">Items and passes</h2>
          <div class="divide-y divide-gray-800 rounded-xl border border-gray-800 bg-gray-950/80">
            <div :for={g <- @lib.grants} class="flex flex-wrap items-center justify-between gap-3 px-4 py-3">
              <div>
                <div class={["font-medium", active?(g.state) && "text-white", !active?(g.state) && "text-gray-500"]}>{g.label}</div>
                <div :if={g.product && g.product.name != g.label} class="text-xs text-gray-500">{g.product.name}</div>
              </div>
              <span class={["text-sm", active?(g.state) && "text-green-300", !active?(g.state) && "text-gray-500"]}>{state_text(g.state, @tz)}</span>
            </div>
          </div>
        </section>

        <div class="border-t border-gray-900 pt-6"><.small_print /></div>
      </div>
    </div>
    """
  end
end

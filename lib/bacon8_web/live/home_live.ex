defmodule Bacon8Web.HomeLive do
  @moduledoc """
  The front door, for visitors (members go straight to /games). Rewritten 2026-10-28 to set
  the site's tone: the bacon sizzles into view in a puff of steam, and a big grill fork flies in and
  pins it to the page (rendered in Blender: library/pipeline/scripts/hero_forks.py, hero_steam.py);
  "Bringing home the bacon." types itself in, and hovering or tapping it says the old secret; Sign Up and Log In are there from the first moment.
  Scrolling down tells what the open-source repository is (a WordPress replacement and a game
  hosting platform) and what each part does, the page editor first.

  Everything moves with CSS (assets/css/intro.css: transforms and opacity, nothing that
  repaints); `IntroReveal` (assets/js/intro_reveal.ts) fades each section up as it comes into
  view. Without JavaScript, or with "reduce motion", it is all simply there.
  """
  use Bacon8Web, :live_view

  import Bacon8Web.Components.Bacon, only: [bacon: 1]
  import Bacon8Web.Components.Gem, only: [gem: 1]

  @repo "https://github.com/Ray-Rios/Bacon8"
  # the typed tagline: change the words here; the typing counts its letters (--n) itself
  @tagline "Bringing home the bacon."

  def mount(_params, _session, socket) do
    if socket.assigns.current_user do
      {:ok, push_navigate(socket, to: ~p"/games")}
    else
      {:ok, assign(socket, page_title: "Bringing home the bacon", repo: @repo, tagline: @tagline)}
    end
  end

  def render(assigns) do
    ~H"""
    <div id="intro" phx-hook="IntroReveal" phx-update="ignore" class="intro text-white">
      <%!-- ============================================================ the hero --%>
      <section class="intro-hero">
        <div class="intro-stage" aria-hidden="true">
          <%!-- the bacon sizzles into view, then a big grill fork (Blender: library/pipeline/scripts/
               hero_forks.py) flies in and pins it to the page --%>
          <div class="intro-baconbox">
            <div class="intro-puff"><img src="/images/intro/puff.webp" alt="" decoding="async" fetchpriority="low" /></div>
            <div class="intro-sizzle"><.bacon pinned calm /></div>
            <div class="intro-steam"><img src="/images/intro/steam.webp" alt="" decoding="async" fetchpriority="low" /></div>
            <div class="intro-forks">
              <.fork_img name="fork_l_air" class="if-l-air" />
              <.fork_img name="fork_l" class="if-l" />
            </div>
          </div>
        </div>

        <h1 class="intro-title">Bacon<span>8</span></h1>
        <p id="intro-tag" class="intro-tag" phx-hook="IntroTagline" data-alt="IT'S A SECRET TO EVERYBODY." tabindex="0" title="Psst">
          <span class="intro-type" style={"--n:#{String.length(@tagline)}"}>{@tagline}</span><b class="intro-caret">_</b>
        </p>
        <p class="intro-sub">
          An open-source replacement for WordPress that hosts your games too. Pages, blog, store,
          files, chat and games, in one repository you own.
        </p>
        <div class="intro-actions">
          <.link navigate={~p"/register"} class="intro-btn intro-btn-main">Sign Up</.link>
          <.link navigate={~p"/login"} class="intro-btn intro-btn-ghost">Log In</.link>
        </div>
        <a href="#intro-what" class="intro-cue">
          <span>See what's cooking</span>
          <svg viewBox="0 0 24 24" class="w-5 h-5"><path d="M6 9l6 6 6-6" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" /></svg>
        </a>
      </section>

      <%!-- ============================================================ what it is --%>
      <section id="intro-what" class="intro-sec" data-reveal>
        <p class="intro-kicker">One repository</p>
        <h2 class="intro-h2">Everything WordPress does. <em>Then it hosts your games.</em></h2>
        <div class="intro-two stag">
          <div class="intro-card" style="--i:0">
            <h3><.icon_svg name="site" /> Your website</h3>
            <ul>
              <li>Pages and a blog, built in a visual editor</li>
              <li>Members, roles and profiles</li>
              <li>A store, file storage and chat built in</li>
              <li>Plugins you drop into a folder</li>
              <li>An admin dashboard with an audit log</li>
            </ul>
          </div>
          <div class="intro-card" style="--i:1">
            <h3><.icon_svg name="game" /> Your games</h3>
            <ul>
              <li>A games hub with a card for every game</li>
              <li>An API for game clients and servers: sign-in, items, passes</li>
              <li>Zones and holo-sim instances, with chat where the players are</li>
              <li>Sell the game, and what's in it, in the same store</li>
              <li>Every game is a plugin, so it stays yours</li>
            </ul>
          </div>
        </div>
        <p class="intro-note">Built on Elixir and Phoenix LiveView: every page is live, with no page reloads and no PHP.</p>
      </section>

      <%!-- ============================================================ the editor --%>
      <section id="intro-editor" class="intro-sec intro-star" data-reveal>
        <p class="intro-kicker">The star of the show</p>
        <h2 class="intro-h2">A page editor that fits <em>in your hand.</em></h2>
        <div class="intro-split">
          <div class="intro-copy">
            <p>
              Build pages on your phone as easily as on a desktop. Tap <b class="intro-chip">+</b>
              to add a row, split it into columns, drop text, pictures or video into a cell.
              Tap <b class="intro-chip"><.icon_svg name="gear" /></b> to tune it.
            </p>
            <p>
              Rows, columns and cells keep everything centred and tidy on every screen, so a page
              you make on a phone looks right on a monitor too. Blog posts use the same editor.
            </p>
            <ul class="intro-ticks stag">
              <li style="--i:0">Rows, columns, cells</li>
              <li style="--i:1">+ to add, gear to tune</li>
              <li style="--i:2">Made for phones first</li>
              <li style="--i:3">Pages and blog posts</li>
            </ul>
          </div>
          <.editor_demo />
        </div>
      </section>

      <%!-- ============================================================ the store --%>
      <section id="intro-store" class="intro-sec" data-reveal>
        <p class="intro-kicker">The store</p>
        <h2 class="intro-h2">Bringing home <em>the bacon.</em></h2>
        <div class="intro-split">
          <div class="intro-copy">
            <p>
              Sell from day one. Checkout runs on Stripe, so payments go straight to your own
              Stripe account, and the store keeps the receipts.
            </p>
            <p>
              Real-life income or an in-game economy, it's the same store: sell downloads with
              license keys, game items and passes, or Gems, a currency for your community with
              its own ledger. Fill a cart and pay once: every purchase gets a receipt like this one,
              in the buyer's library and on the admin's orders page. Sales are final; disputes and
              chargebacks are handled from the admin pages.
            </p>
          </div>
          <div class="intro-receipt" aria-hidden="true">
            <div class="intro-receipt-head"><.bacon size={22} still calm /> Order #8008</div>
            <div class="intro-line" style="--i:0"><span>Season Pass</span><span>$9.99</span></div>
            <div class="intro-line" style="--i:1"><span>Soundtrack download</span><span>$4.99</span></div>
            <div class="intro-line" style="--i:2"><span><.gem size={16} still calm /> 1,500 Gems</span><span>$14.99</span></div>
            <div class="intro-total"><span>Total</span><span>$29.97</span></div>
            <div class="intro-paid">Paid</div>
          </div>
        </div>
      </section>

      <%!-- ============================================================ the rest --%>
      <section id="intro-more" class="intro-sec" data-reveal>
        <p class="intro-kicker">Built in</p>
        <h2 class="intro-h2">The rest of <em>the kitchen.</em></h2>
        <div class="intro-grid stag">
          <div class="intro-feature" style="--i:0">
            <div class="intro-art intro-art-drive" aria-hidden="true">
              <.icon_svg name="folder" /><i></i><i></i><i></i>
            </div>
            <h3>Your own file store</h3>
            <p>
              Every member gets a drive on the web: folders, drag-and-drop uploads, and sharing
              that's private, by link or public. A file is stored once however many times it's
              uploaded, and quotas follow each member's role.
            </p>
          </div>
          <div class="intro-feature" style="--i:1">
            <div class="intro-art intro-art-chat" aria-hidden="true"><i></i><i></i><i></i></div>
            <h3>Chat, with your games in it</h3>
            <p>
              Channels with presence and reactions, private channels, VIP passes sold in the store,
              and invites. Game instances like holo-sims get channels of their own, so players can
              talk where they play.
            </p>
          </div>
          <div class="intro-feature" style="--i:2">
            <div class="intro-art intro-art-shield" aria-hidden="true"><.icon_svg name="shield" /><i></i></div>
            <h3>Locked down by default</h3>
            <p>
              Email verification, failed-login tracking and lockouts, device fingerprints, block
              and allow lists, bot signals and rate limits, with moderation tools and an audit
              log for the admins.
            </p>
          </div>
          <div class="intro-feature" style="--i:3">
            <div class="intro-art intro-art-plug" aria-hidden="true"><.icon_svg name="plug" /></div>
            <h3>Plugins, WordPress-style</h3>
            <p>
              Drop a folder into <code>plugins/</code> and switch it on at /admin/plugins. A
              plugin brings its own pages, tables, admin screens and scripts, and talks to the
              site through public interfaces.
            </p>
          </div>
        </div>
      </section>

      <%!-- ============================================================ the plugins --%>
      <section id="intro-plugins" class="intro-sec" data-reveal>
        <p class="intro-kicker">In the box</p>
        <h2 class="intro-h2">The plugins it <em>comes with.</em></h2>
        <div class="intro-plugins stag">
          <div class="intro-plugin" style="--i:0">
            <span class="intro-plugin-icon"><.gem size={30} still calm /></span>
            <div>
              <h3>Store</h3>
              <p>Stripe Checkout, Gems, downloads and license keys, game items and passes.</p>
            </div>
          </div>
          <div class="intro-plugin" style="--i:1">
            <span class="intro-plugin-icon">💬</span>
            <div>
              <h3>Chat Channels</h3>
              <p>Channels, invites, presence and reactions, and chat for game instances.</p>
            </div>
          </div>
          <div class="intro-plugin" style="--i:2">
            <span class="intro-plugin-icon">💡</span>
            <div>
              <h3>Suggestions &amp; Bugs</h3>
              <p>Members suggest features and report bugs with screenshots, and vote on them.</p>
            </div>
          </div>
          <div class="intro-plugin" style="--i:3">
            <span class="intro-plugin-icon"><.bacon size={30} still calm /></span>
            <div>
              <h3>Your game</h3>
              <p>A game is a plugin too: its own pages, card on /games, API and store items.</p>
            </div>
          </div>
        </div>
      </section>

      <%!-- ============================================================ open source --%>
      <section id="intro-open" class="intro-sec intro-end" data-reveal>
        <h2 class="intro-h2">Fork it. Run it. <em>Make it yours.</em></h2>
        <p class="intro-sub">Bacon8 is open source under the MIT license.</p>
        <div class="intro-actions">
          <.link navigate={~p"/register"} class="intro-btn intro-btn-main">Sign Up</.link>
          <.link navigate={~p"/login"} class="intro-btn intro-btn-ghost">Log In</.link>
          <a href={@repo} target="_blank" rel="noopener noreferrer" class="intro-btn intro-btn-ghost">
            <.icon_svg name="github" /> Source on GitHub
          </a>
        </div>
      </section>
    </div>
    """
  end

  # The fork, 600 px for phones and 1000 for sharp screens.
  attr :name, :string, required: true
  attr :class, :string, default: nil

  defp fork_img(assigns) do
    ~H"""
    <img
      class={["ifk", @class]}
      src={"/images/intro/#{@name}-600.webp"}
      srcset={"/images/intro/#{@name}-600.webp 600w, /images/intro/#{@name}-1000.webp 1000w"}
      sizes="(max-width: 640px) 230vw, 1100px"
      alt=""
      decoding="async"
    />
    """
  end

  # The editor, in miniature: a row appears from the +, splits into two columns, the gear turns
  # and a cell fills. It loops gently while it's on screen.
  defp editor_demo(assigns) do
    ~H"""
    <div class="intro-phone" aria-hidden="true">
      <div class="intro-phone-bar"><i></i><i></i><i></i></div>
      <div class="ed-page">
        <div class="ed-row ed-r1"><div class="ed-cell ed-title"><b></b><b></b></div></div>
        <div class="ed-row ed-r2">
          <div class="ed-cell ed-c1"><span class="ed-pic"></span></div>
          <div class="ed-cell ed-c2"><b></b><b></b><b></b></div>
          <span class="ed-gear"><.icon_svg name="gear" /></span>
        </div>
        <div class="ed-row ed-r3"><div class="ed-cell"><b></b><b></b></div></div>
        <span class="ed-plus">+</span>
        <span class="ed-tap"></span>
      </div>
    </div>
    """
  end

  attr :name, :string, required: true

  defp icon_svg(%{name: "github"} = assigns) do
    ~H"""
    <svg viewBox="0 0 24 24" class="intro-ic" fill="currentColor"><path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z" /></svg>
    """
  end

  defp icon_svg(assigns) do
    assigns = assign(assigns, :d, icon_path(assigns.name))

    ~H"""
    <svg viewBox="0 0 24 24" class="intro-ic" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
      <path d={@d} />
    </svg>
    """
  end

  defp icon_path("site"), do: "M3 5h18v14H3z M3 9h18 M7 13h6 M7 16h4"
  defp icon_path("game"), do: "M6 9h12a4 4 0 0 1 0 8c-2 0-2.5-2-6-2s-4 2-6 2a4 4 0 0 1 0-8z M8 11v4 M6 13h4 M16 12h.01 M18 14h.01"
  defp icon_path("folder"), do: "M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"
  defp icon_path("shield"), do: "M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z M9 12l2 2 4-4"
  defp icon_path("plug"), do: "M9 3v5 M15 3v5 M6 8h12v3a6 6 0 0 1-12 0z M12 17v4"

  defp icon_path("gear"),
    do:
      "M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"
end

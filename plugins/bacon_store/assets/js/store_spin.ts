// <b8-spin>: a store item in 3D (2026-10-28). A turntable rendered in Blender
// (library/pipeline/scripts/store_turntables.py, then store_sheets.py) as a 48-frame sprite
// sheet, like the Gem (<b8-gem>, assets/js/fire_gem.ts): it turns slowly and floats, and when its
// card is hovered it reacts: a quick whirl with a hop, or a turn back and a glow. Server templates
// write it with `BaconStoreWeb.StoreComponents.art/1`:
//
//   <b8-spin src="/plugins/bacon_store/spin/kind_download" glow="#3A8CFF"></b8-spin>
//
// `src` is the sheets' base (`<src>-128.webp`, `-224.webp`, `-320.webp`, and `<src>.webp`, the
// still shown before this script runs). The element fills its box. `still`: no idle turn.
// One requestAnimationFrame loop drives every spin on the page (only those on screen).

const FRAMES = 48;
const COLS = 8;
const ROWS = 6;
const IDLE_FPS = 8;
const SIZES = [128, 224, 320];

const CSS = `
:host { display: block; position: relative; width: 100%; height: 100%; line-height: 0; }
.fl { position: absolute; inset: 0; will-change: transform; }
:host(:not([still])) .fl.on { animation: float var(--float-s, 4.2s) ease-in-out infinite; animation-delay: var(--float-d, 0s); }
@keyframes float { 0%, 100% { transform: translateY(2.5%); } 50% { transform: translateY(-2.5%); } }
.rx { position: absolute; inset: 0; transform-origin: 50% 75%; }
.glow { position: absolute; inset: 8%; border-radius: 50%; pointer-events: none; opacity: .38;
  background: radial-gradient(circle, var(--glow, rgba(120,170,255,.6)) 0%, transparent 66%); filter: blur(8px); }
.sp { position: absolute; inset: 0; background-repeat: no-repeat; background-size: ${COLS * 100}% ${ROWS * 100}%;
  filter: drop-shadow(0 10px 14px rgba(0,0,0,.55)); }
.shadow { position: absolute; left: 22%; right: 22%; bottom: 3%; height: 7%; border-radius: 50%;
  background: radial-gradient(closest-side, rgba(0,0,0,.55), transparent); }
`;

let sheet: CSSStyleSheet | null = null;
function styles(root: ShadowRoot) {
  try {
    if (!sheet) {
      sheet = new CSSStyleSheet();
      sheet.replaceSync(CSS);
    }
    root.adoptedStyleSheets = [sheet];
  } catch {
    const s = document.createElement("style");
    s.textContent = CSS;
    root.appendChild(s);
  }
}

const reduced = () => typeof window !== "undefined" && !!window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;

/** The sheet for a box `px` device pixels wide (pure; tested). */
export function sheetFor(px: number): number {
  return SIZES.find((s) => s >= px) ?? SIZES[SIZES.length - 1];
}

/** A frame's background-position (pure; tested). */
export function framePos(frame: number): string {
  const f = ((Math.floor(frame) % FRAMES) + FRAMES) % FRAMES;
  const c = f % COLS;
  const r = Math.floor(f / COLS);
  return `${(c / (COLS - 1)) * 100}% ${(r / (ROWS - 1)) * 100}%`;
}

const live = new Set<B8Spin>();
let raf = 0;
function loop(t: number) {
  for (const g of live) g.tick(t);
  raf = live.size ? requestAnimationFrame(loop) : 0;
}
function wake(g: B8Spin) {
  live.add(g);
  if (!raf) raf = requestAnimationFrame(loop);
}

const io =
  typeof IntersectionObserver !== "undefined"
    ? new IntersectionObserver((entries) => {
        for (const e of entries) {
          const g = e.target as B8Spin;
          g.onScreen = e.isIntersecting;
          if (e.isIntersecting) wake(g);
          else live.delete(g);
        }
      })
    : null;

const Base: typeof HTMLElement = typeof HTMLElement !== "undefined" ? HTMLElement : (class {} as any);

export class B8Spin extends Base {
  static observedAttributes = ["src", "glow"];
  onScreen = true;
  private frame = 0;
  private last = 0;
  private boost = 0;
  private boostUntil = 0;
  private busyUntil = 0;
  private flip = false;
  private els!: { fl: HTMLElement; rx: HTMLElement; sp: HTMLElement; glow: HTMLElement };
  private ro: ResizeObserver | null = null;
  private onHost = () => this.react();
  private host: Element | null = null;

  connectedCallback() {
    if (!this.shadowRoot) {
      const root = this.attachShadow({ mode: "open" });
      styles(root);
      const fl = document.createElement("span");
      fl.className = "fl";
      const rx = document.createElement("span");
      rx.className = "rx";
      const glow = document.createElement("span");
      glow.className = "glow";
      const shadow = document.createElement("span");
      shadow.className = "shadow";
      const sp = document.createElement("span");
      sp.className = "sp";
      rx.append(glow, shadow, sp);
      fl.append(rx);
      root.append(fl);
      this.els = { fl, rx, sp, glow };
    }
    this.setAttribute("aria-hidden", "true");
    // its card (or anything marked as its host) hovered makes it react
    this.host = this.closest("[data-spin-host]") || this;
    this.host.addEventListener("pointerenter", this.onHost);
    this.els.fl.style.setProperty("--float-s", `${3.8 + Math.random() * 1.2}s`);
    this.els.fl.style.setProperty("--float-d", `${-Math.random() * 4}s`);
    this.els.fl.classList.toggle("on", !reduced());
    this.applyLook();
    if (typeof ResizeObserver !== "undefined") {
      this.ro = new ResizeObserver(() => this.applySheet());
      this.ro.observe(this);
    }
    this.draw();
    if (io) io.observe(this);
    else wake(this);
  }

  disconnectedCallback() {
    io?.unobserve(this);
    this.ro?.disconnect();
    this.host?.removeEventListener("pointerenter", this.onHost);
    live.delete(this);
  }

  attributeChangedCallback() {
    if (this.els) this.applyLook();
  }

  private applyLook() {
    const glow = this.getAttribute("glow");
    if (glow) this.els.glow.style.setProperty("--glow", glow);
    this.applySheet();
  }

  private applySheet() {
    const src = this.getAttribute("src");
    if (!src) return;
    const px = (this.getBoundingClientRect().width || 160) * (window.devicePixelRatio || 1);
    this.els.sp.style.backgroundImage = `url(${src}-${sheetFor(px)}.webp)`;
  }

  private draw() {
    this.els.sp.style.backgroundPosition = framePos(this.frame);
  }

  tick(t: number) {
    if (!this.onScreen) return;
    const dt = this.last ? Math.min(0.1, (t - this.last) / 1000) : 0;
    this.last = t;
    let fps = this.hasAttribute("still") || reduced() ? 0 : IDLE_FPS;
    if (t < this.boostUntil) {
      const k = (this.boostUntil - t) / 1300;
      fps += this.boost * k * k;
    }
    if (fps !== 0) {
      this.frame += fps * dt;
      this.draw();
    }
  }

  /** Its card hovered: a whirl with a hop, or (every other time) a turn back and a glow. */
  react() {
    if (reduced()) return;
    const now = performance.now();
    if (now < this.busyUntil) return;
    this.busyUntil = now + 1000;
    this.flip = !this.flip;
    wake(this);
    if (this.flip) {
      this.boost = 120;
      this.boostUntil = now + 1300;
      this.els.rx.animate(
        [
          { transform: "translateY(0) scale(1)" },
          { transform: "translateY(2%) scale(1.04, .96)", offset: 0.15 },
          { transform: "translateY(-9%) scale(1.06)", offset: 0.5 },
          { transform: "translateY(0) scale(1)" },
        ],
        { duration: 900, easing: "cubic-bezier(.3,.7,.4,1)" },
      );
    } else {
      this.boost = -IDLE_FPS * 2.2;
      this.boostUntil = now + 900;
      this.els.rx.animate([{ transform: "scale(1)" }, { transform: "scale(1.08)" }, { transform: "scale(1)" }], { duration: 1000, easing: "ease-out" });
    }
    this.els.glow.animate(
      [{ opacity: 0.38, transform: "scale(1)" }, { opacity: 0.85, transform: "scale(1.18)" }, { opacity: 0.38, transform: "scale(1)" }],
      { duration: 1100, easing: "ease-out" },
    );
  }
}

if (typeof customElements !== "undefined" && !customElements.get("b8-spin")) {
  customElements.define("b8-spin", B8Spin);
}

// <b8-gem>: the Bacon8 Gem, the site's currency (Bacon Store's Gems) and the shop icon.
//
// A fiery gem rendered in Blender (library/pipeline/scripts/fire_gem.py) as a 48-frame
// turntable, shown here as a sprite that turns slowly and floats. Hovering makes it react,
// a different way each time: a whirl, a hop, a flare of embers, a burst of sparkles or a
// wobble. Server templates write it with `Bacon8Web.Components.Gem.gem/1`:
//
//   <b8-gem size="20"></b8-gem>          size in CSS px (default 1.25em of the text)
//   <b8-gem size="96" still></b8-gem>    no idle turning or floating (still reacts)
//   <b8-gem size="20" calm></b8-gem>     no hover reactions
//
// Everything lives in the element's shadow root, so LiveView patches leave it alone, and
// one requestAnimationFrame loop drives every gem on the page (only those on screen).
// Before this script runs, app.css shows a still picture in its place.

const FRAMES = 48;
const COLS = 8;
const ROWS = 6;
const IDLE_FPS = 9; // a turn every ~5 s
const SHEETS: Array<[number, string]> = [
  [64, "/images/gem/gem-64.webp"],
  [160, "/images/gem/gem-160.webp"],
  [288, "/images/gem/gem-288.webp"],
];

const CSS = `
:host { display: inline-block; position: relative; vertical-align: -0.22em; width: var(--gem-size, 1.25em); height: var(--gem-size, 1.25em); line-height: 0; }
.fl { position: absolute; inset: 0; will-change: transform; }
:host(:not([still])) .fl.on { animation: float var(--float-s, 3.6s) ease-in-out infinite; animation-delay: var(--float-d, 0s); }
@keyframes float {
  0%, 100% { transform: translateY(6%) rotate(-3deg); }
  50% { transform: translateY(-8%) rotate(3deg); }
}
.rx { position: absolute; inset: 0; transform-origin: 50% 70%; }
.glow { position: absolute; inset: -18%; border-radius: 50%; pointer-events: none;
  background: radial-gradient(circle, rgba(255,140,40,.55) 0%, rgba(255,80,10,.25) 35%, transparent 68%);
  opacity: .55; filter: blur(1px); }
.sp { position: absolute; inset: 0; background-repeat: no-repeat; background-size: ${COLS * 100}% ${ROWS * 100}%;
  filter: drop-shadow(0 0 .08em rgba(255,110,20,.75)); }
.fx { position: absolute; inset: -60%; pointer-events: none; overflow: visible; }
.em { position: absolute; border-radius: 50%; left: 50%; top: 50%;
  background: radial-gradient(circle, #fffbe6 0 25%, #ffc14d 45%, rgba(255,90,0,0) 72%);
  box-shadow: 0 0 6px 2px rgba(255,140,30,.6); }
.st { position: absolute; left: 50%; top: 50%;
  background: radial-gradient(circle, #fff 0 8%, transparent 9%),
    linear-gradient(90deg, transparent 47%, #fff 50%, transparent 53%),
    linear-gradient(0deg, transparent 47%, #fff 50%, transparent 53%);
  filter: drop-shadow(0 0 2px #ffd27a); }
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

const reduced = () => window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;

// One loop for all gems.
const live = new Set<B8Gem>();
let raf = 0;
function loop(t: number) {
  for (const g of live) g.tick(t);
  raf = live.size ? requestAnimationFrame(loop) : 0;
}
function wake(g: B8Gem) {
  live.add(g);
  if (!raf) raf = requestAnimationFrame(loop);
}

const io =
  typeof IntersectionObserver !== "undefined"
    ? new IntersectionObserver((entries) => {
        for (const e of entries) {
          const g = e.target as B8Gem;
          g.onScreen = e.isIntersecting;
          if (e.isIntersecting) wake(g);
          else live.delete(g);
        }
      })
    : null;

type Reaction = "whirl" | "hop" | "flare" | "sparkle" | "wobble";
const REACTIONS: Reaction[] = ["whirl", "hop", "flare", "sparkle", "wobble"];

export class B8Gem extends HTMLElement {
  static observedAttributes = ["size"];
  onScreen = true;
  private frame = Math.floor(Math.random() * FRAMES);
  private last = 0;
  private boostUntil = 0;
  private boost = 0;
  private lastReaction: Reaction | null = null;
  private busyUntil = 0;
  private els!: { fl: HTMLElement; rx: HTMLElement; sp: HTMLElement; glow: HTMLElement; fx: HTMLElement };

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
      const sp = document.createElement("span");
      sp.className = "sp";
      const fx = document.createElement("span");
      fx.className = "fx";
      rx.append(glow, sp);
      fl.append(rx, fx);
      root.append(fl);
      this.els = { fl, rx, sp, glow, fx };
      this.addEventListener("pointerenter", () => this.react());
      this.addEventListener("focusin", () => this.react());
      // A gem inside a link or button reacts when that is hovered too.
      const host = this.closest("a, button, [data-gem-host]");
      if (host && host !== this) host.addEventListener("pointerenter", () => this.react());
    }
    this.setAttribute("aria-hidden", this.getAttribute("aria-hidden") ?? "true");
    this.style.background = "none";
    this.applySize();
    this.els.fl.style.setProperty("--float-s", `${3.2 + Math.random() * 1.4}s`);
    this.els.fl.style.setProperty("--float-d", `${-Math.random() * 4}s`);
    this.els.fl.classList.toggle("on", !reduced());
    this.draw();
    if (io) io.observe(this);
    else wake(this);
  }

  disconnectedCallback() {
    io?.unobserve(this);
    live.delete(this);
  }

  attributeChangedCallback() {
    if (this.els) this.applySize();
  }

  private applySize() {
    const size = Number(this.getAttribute("size"));
    if (size > 0) this.style.setProperty("--gem-size", `${size}px`);
    requestAnimationFrame(() => {
      const px = this.getBoundingClientRect().width * (window.devicePixelRatio || 1);
      const pick = SHEETS.find(([s]) => s >= px) ?? SHEETS[SHEETS.length - 1];
      this.els.sp.style.backgroundImage = `url(${pick[1]})`;
    });
  }

  private draw() {
    const f = ((Math.floor(this.frame) % FRAMES) + FRAMES) % FRAMES;
    const c = f % COLS;
    const r = Math.floor(f / COLS);
    this.els.sp.style.backgroundPosition = `${(c / (COLS - 1)) * 100}% ${(r / (ROWS - 1)) * 100}%`;
  }

  tick(t: number) {
    if (!this.onScreen) return;
    const dt = this.last ? Math.min(0.1, (t - this.last) / 1000) : 0;
    this.last = t;
    let fps = this.hasAttribute("still") || reduced() ? 0 : IDLE_FPS;
    if (t < this.boostUntil) {
      const k = (this.boostUntil - t) / 1400; // eases out
      fps += this.boost * k * k;
    }
    if (fps > 0) {
      this.frame += fps * dt;
      this.draw();
    }
  }

  /** A hover: a different reaction from last time. */
  react() {
    if (this.hasAttribute("calm") || reduced()) return;
    const now = performance.now();
    if (now < this.busyUntil) return;
    const pool = REACTIONS.filter((r) => r !== this.lastReaction);
    const pick = pool[Math.floor(Math.random() * pool.length)];
    this.lastReaction = pick;
    this.busyUntil = now + 900;
    wake(this);
    this[pick]();
  }

  private whirl() {
    this.boost = 160;
    this.boostUntil = performance.now() + 1400;
    this.els.rx.animate(
      [{ transform: "scale(1)" }, { transform: "scale(1.22)" }, { transform: "scale(1)" }],
      { duration: 1200, easing: "ease-out" },
    );
    this.glowPulse(1.2, 1200);
  }

  private hop() {
    this.els.rx.animate(
      [
        { transform: "translateY(0) scale(1, 1)" },
        { transform: "translateY(4%) scale(1.15, .82)", offset: 0.15 },
        { transform: "translateY(-55%) scale(.9, 1.12)", offset: 0.45 },
        { transform: "translateY(0) scale(1.12, .86)", offset: 0.78 },
        { transform: "translateY(0) scale(1, 1)" },
      ],
      { duration: 820, easing: "cubic-bezier(.3,.7,.4,1)" },
    );
    this.boost = 60;
    this.boostUntil = performance.now() + 900;
  }

  private flare() {
    this.glowPulse(2.4, 1300);
    this.els.sp.animate(
      [{ filter: "drop-shadow(0 0 .08em rgba(255,110,20,.75)) brightness(1)" },
        { filter: "drop-shadow(0 0 .35em rgba(255,150,40,1)) brightness(1.55) saturate(1.3)" },
        { filter: "drop-shadow(0 0 .08em rgba(255,110,20,.75)) brightness(1)" }],
      { duration: 1300, easing: "ease-out" },
    );
    const size = this.getBoundingClientRect().width || 20;
    const n = size < 40 ? 6 : 12;
    for (let i = 0; i < n; i++) {
      const e = document.createElement("span");
      e.className = "em";
      const d = Math.max(2.5, size * (0.04 + Math.random() * 0.05));
      e.style.width = e.style.height = `${d}px`;
      e.style.left = `${50 + (Math.random() - 0.5) * 18}%`;
      e.style.top = `${46 + (Math.random() - 0.5) * 8}%`;
      this.els.fx.append(e);
      const dx = (Math.random() - 0.5) * size * 0.9;
      const dy = -size * (0.55 + Math.random() * 0.7);
      e.animate(
        [
          { transform: "translate(-50%, -50%) scale(1)", opacity: 0 },
          { opacity: 1, offset: 0.12 },
          { transform: `translate(calc(-50% + ${dx * 0.5}px), calc(-50% + ${dy * 0.6}px)) scale(.8)`, opacity: 0.9, offset: 0.6 },
          { transform: `translate(calc(-50% + ${dx}px), calc(-50% + ${dy}px)) scale(.2)`, opacity: 0 },
        ],
        { duration: 900 + Math.random() * 800, delay: Math.random() * 300, easing: "cubic-bezier(.2,.6,.4,1)", fill: "backwards" },
      ).onfinish = () => e.remove();
    }
  }

  private sparkle() {
    this.els.sp.animate(
      [{ filter: "drop-shadow(0 0 .08em rgba(255,110,20,.75)) brightness(1)" },
        { filter: "drop-shadow(0 0 .2em rgba(255,220,160,1)) brightness(1.8)", offset: 0.2 },
        { filter: "drop-shadow(0 0 .08em rgba(255,110,20,.75)) brightness(1)" }],
      { duration: 900 },
    );
    for (let i = 0; i < 5; i++) {
      const st = document.createElement("span");
      st.className = "st";
      const size = this.getBoundingClientRect().width || 20;
      const d = Math.min(64, Math.max(10, size * (0.16 + Math.random() * 0.18)));
      st.style.width = st.style.height = `${d}px`;
      st.style.left = `${22 + Math.random() * 56}%`;
      st.style.top = `${30 + Math.random() * 40}%`;
      this.els.fx.append(st);
      st.animate(
        [
          { transform: "translate(-50%,-50%) scale(0) rotate(0deg)", opacity: 1 },
          { transform: "translate(-50%,-50%) scale(1) rotate(45deg)", opacity: 1, offset: 0.4 },
          { transform: "translate(-50%,-50%) scale(0) rotate(90deg)", opacity: 0 },
        ],
        { duration: 700, delay: i * 110, easing: "ease-out", fill: "backwards" },
      ).onfinish = () => st.remove();
    }
  }

  private wobble() {
    this.els.rx.animate(
      [
        { transform: "rotate(0) scale(1)" },
        { transform: "rotate(-16deg) scale(1.18)", offset: 0.2 },
        { transform: "rotate(13deg) scale(1.18)", offset: 0.4 },
        { transform: "rotate(-8deg) scale(1.1)", offset: 0.6 },
        { transform: "rotate(4deg) scale(1.04)", offset: 0.8 },
        { transform: "rotate(0) scale(1)" },
      ],
      { duration: 900, easing: "ease-in-out" },
    );
    this.boost = -IDLE_FPS * 1.5; // turns back for a moment
    this.boostUntil = performance.now() + 700;
  }

  private glowPulse(k: number, ms: number) {
    this.els.glow.animate(
      [{ opacity: 0.55, transform: "scale(1)" }, { opacity: Math.min(1, 0.55 * k), transform: `scale(${0.9 + k * 0.25})` }, { opacity: 0.55, transform: "scale(1)" }],
      { duration: ms, easing: "ease-out" },
    );
  }
}

if (typeof customElements !== "undefined" && !customElements.get("b8-gem")) {
  customElements.define("b8-gem", B8Gem);
}

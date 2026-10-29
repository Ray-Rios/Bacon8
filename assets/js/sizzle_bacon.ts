// <b8-bacon>: two strips of bacon, the Bacon8 site icon (the desktop's Start button, the
// navbar's Games link; the favicon is the same picture, built by scripts/brand/).
//
// Modelled and rendered in Blender (library/pipeline/scripts/bacon_strips.py) as a 48-frame
// loop in which the strips sizzle: ripples run along them and the crisp edges tremble. Shown
// here as a sprite that sizzles slowly and bobs. Hovering makes it react, a different way each
// time: a spatter of grease, a curl of steam, a hop in the pan, crackling fat or a sizzling
// shiver. Server templates write it with `Bacon8Web.Components.Bacon.bacon/1`:
//
//   <b8-bacon size="20"></b8-bacon>          size in CSS px (default 1.25em of the text)
//   <b8-bacon size="96" still></b8-bacon>    no idle sizzle or bob (still reacts)
//   <b8-bacon size="20" calm></b8-bacon>     no hover reactions
//   <b8-bacon size="132" pinned></b8-bacon>  sizzles but doesn't bob (the front door: forked to the page)
//
// The same pattern as <b8-gem> (fire_gem.ts): a shadow root (LiveView patches leave it
// alone), one requestAnimationFrame loop for every strip on the page (only those on screen),
// and a still picture from app.css until this script runs.

const FRAMES = 48;
const COLS = 8;
const ROWS = 6;
const IDLE_FPS = 10; // a ripple every ~5 s
const SHEETS: Array<[number, string]> = [
  [64, "/images/bacon/bacon-64.webp"],
  [160, "/images/bacon/bacon-160.webp"],
  [288, "/images/bacon/bacon-288.webp"],
];

const CSS = `
:host { display: inline-block; position: relative; vertical-align: -0.22em; width: var(--bacon-size, 1.25em); height: var(--bacon-size, 1.25em); line-height: 0; }
.fl { position: absolute; inset: 0; will-change: transform; }
:host(:not([still]):not([pinned])) .fl.on { animation: bob var(--bob-s, 3.2s) ease-in-out infinite; animation-delay: var(--bob-d, 0s); }
@keyframes bob {
  0%, 100% { transform: translateY(3%) rotate(-1.5deg); }
  50% { transform: translateY(-4%) rotate(1.5deg); }
}
.rx { position: absolute; inset: 0; transform-origin: 50% 75%; }
.heat { position: absolute; inset: -14%; border-radius: 50%; pointer-events: none;
  background: radial-gradient(circle, rgba(255,120,40,.45) 0%, rgba(255,70,20,.18) 38%, transparent 66%);
  opacity: 0; filter: blur(1px); }
.sp { position: absolute; inset: 0; background-repeat: no-repeat; background-size: ${COLS * 100}% ${ROWS * 100}%;
  filter: drop-shadow(0 .03em .05em rgba(60,10,0,.45)); }
.fx { position: absolute; inset: -70%; pointer-events: none; overflow: visible; }
.gr { position: absolute; border-radius: 50%; left: 50%; top: 50%;
  background: radial-gradient(circle at 35% 35%, #fffbe8 0 20%, #ffd98a 45%, rgba(230,150,40,.85) 70%, rgba(200,110,20,0) 75%); }
.stm { position: absolute; left: 50%; top: 50%; border-radius: 50% 50% 45% 45%;
  background: radial-gradient(ellipse 40% 50% at 50% 55%, rgba(255,255,255,.5) 0%, rgba(255,255,255,.18) 55%, transparent 100%);
  filter: blur(2px); }
.pk { position: absolute; left: 50%; top: 50%; border-radius: 50%;
  background: radial-gradient(circle, #fff 0 18%, #ffe39a 40%, rgba(255,150,40,0) 70%);
  box-shadow: 0 0 4px 1px rgba(255,170,60,.7); }
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
const rnd = (a: number, b: number) => a + Math.random() * (b - a);

// One loop for all bacon.
const live = new Set<B8Bacon>();
let raf = 0;
function loop(t: number) {
  for (const b of live) b.tick(t);
  raf = live.size ? requestAnimationFrame(loop) : 0;
}
function wake(b: B8Bacon) {
  live.add(b);
  if (!raf) raf = requestAnimationFrame(loop);
}

const io =
  typeof IntersectionObserver !== "undefined"
    ? new IntersectionObserver((entries) => {
        for (const e of entries) {
          const b = e.target as B8Bacon;
          b.onScreen = e.isIntersecting;
          if (e.isIntersecting) wake(b);
          else live.delete(b);
        }
      })
    : null;

export type Reaction = "spatter" | "steam" | "hop" | "crackle" | "shiver";
export const REACTIONS: Reaction[] = ["spatter", "steam", "hop", "crackle", "shiver"];

/** A reaction other than the last one (the pick is `r`, 0..1). */
export function nextReaction(last: Reaction | null, r: number): Reaction {
  const pool = REACTIONS.filter((x) => x !== last);
  return pool[Math.min(pool.length - 1, Math.floor(r * pool.length))];
}

/** Which sheet cell shows `frame` (any number; wraps both ways): [column, row]. */
export function cell(frame: number): [number, number] {
  const f = ((Math.floor(frame) % FRAMES) + FRAMES) % FRAMES;
  return [f % COLS, Math.floor(f / COLS)];
}

export class B8Bacon extends HTMLElement {
  static observedAttributes = ["size"];
  onScreen = true;
  private frame = Math.floor(Math.random() * FRAMES);
  private last = 0;
  private boostUntil = 0;
  private boost = 0;
  private lastReaction: Reaction | null = null;
  private busyUntil = 0;
  private els!: { fl: HTMLElement; rx: HTMLElement; sp: HTMLElement; heat: HTMLElement; fx: HTMLElement };

  connectedCallback() {
    if (!this.shadowRoot) {
      const root = this.attachShadow({ mode: "open" });
      styles(root);
      const mk = (cls: string) => {
        const e = document.createElement("span");
        e.className = cls;
        return e;
      };
      const fl = mk("fl"), rx = mk("rx"), heat = mk("heat"), sp = mk("sp"), fx = mk("fx");
      rx.append(heat, sp);
      fl.append(rx, fx);
      root.append(fl);
      this.els = { fl, rx, sp, heat, fx };
      this.addEventListener("pointerenter", () => this.react());
      this.addEventListener("focusin", () => this.react());
      // Bacon inside a link or button reacts when that is hovered too.
      const host = this.closest("a, button, [data-bacon-host]");
      if (host && host !== this) host.addEventListener("pointerenter", () => this.react());
    }
    this.setAttribute("aria-hidden", this.getAttribute("aria-hidden") ?? "true");
    this.style.background = "none";
    this.applySize();
    this.els.fl.style.setProperty("--bob-s", `${2.8 + Math.random() * 1.2}s`);
    this.els.fl.style.setProperty("--bob-d", `${-Math.random() * 4}s`);
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
    if (size > 0) this.style.setProperty("--bacon-size", `${size}px`);
    requestAnimationFrame(() => {
      const px = this.getBoundingClientRect().width * (window.devicePixelRatio || 1);
      const pick = SHEETS.find(([s]) => s >= px) ?? SHEETS[SHEETS.length - 1];
      this.els.sp.style.backgroundImage = `url(${pick[1]})`;
    });
  }

  private draw() {
    const [c, r] = cell(this.frame);
    this.els.sp.style.backgroundPosition = `${(c / (COLS - 1)) * 100}% ${(r / (ROWS - 1)) * 100}%`;
  }

  tick(t: number) {
    if (!this.onScreen) return;
    const dt = this.last ? Math.min(0.1, (t - this.last) / 1000) : 0;
    this.last = t;
    let fps = this.hasAttribute("still") || reduced() ? 0 : IDLE_FPS;
    if (t < this.boostUntil) {
      const k = (this.boostUntil - t) / 1400; // eases out
      fps += this.boost * Math.min(1, k * k);
    }
    if (fps !== 0) {
      this.frame += fps * dt;
      this.draw();
    }
  }

  /** A hover: a different reaction from last time. */
  react() {
    if (this.hasAttribute("calm") || reduced()) return;
    const now = performance.now();
    if (now < this.busyUntil) return;
    const pick = nextReaction(this.lastReaction, Math.random());
    this.lastReaction = pick;
    this.busyUntil = now + 900;
    wake(this);
    this[pick]();
  }

  private get px() {
    return this.getBoundingClientRect().width || 20;
  }

  private sizzle(fps: number, ms: number) {
    this.boost = fps;
    this.boostUntil = performance.now() + ms;
  }

  private heatPulse(peak: number, ms: number) {
    this.els.heat.animate(
      [{ opacity: 0, transform: "scale(.9)" }, { opacity: peak, transform: "scale(1.1)", offset: 0.3 }, { opacity: 0, transform: "scale(1)" }],
      { duration: ms, easing: "ease-out" },
    );
  }

  /** Grease flies out in arcs and falls back. */
  private spatter(n = 0) {
    this.sizzle(70, 1300);
    this.heatPulse(0.7, 1000);
    this.els.rx.animate(
      [{ transform: "translate(0,0)" }, { transform: "translate(-2%,1%)" }, { transform: "translate(2%,-1%)" },
        { transform: "translate(-1%,0)" }, { transform: "translate(0,0)" }],
      { duration: 360, iterations: 2 },
    );
    const size = this.px;
    const count = n || (size < 40 ? 7 : 14);
    for (let i = 0; i < count; i++) {
      const g = document.createElement("span");
      g.className = "gr";
      const d = Math.max(2, size * rnd(0.03, 0.065));
      g.style.width = g.style.height = `${d}px`;
      g.style.left = `${50 + rnd(-22, 22)}%`;
      g.style.top = `${50 + rnd(-14, 14)}%`;
      this.els.fx.append(g);
      const dir = Math.random() < 0.5 ? -1 : 1;
      const dx = dir * size * rnd(0.25, 0.7);
      const up = -size * rnd(0.35, 0.8);
      const down = size * rnd(0.15, 0.45);
      g.animate(
        [
          { transform: "translate(-50%,-50%) scale(.3)", opacity: 0 },
          { transform: "translate(-50%,-50%) scale(1)", opacity: 1, offset: 0.08 },
          { transform: `translate(calc(-50% + ${dx * 0.55}px), calc(-50% + ${up}px)) scale(.95)`, opacity: 1, offset: 0.45 },
          { transform: `translate(calc(-50% + ${dx}px), calc(-50% + ${down}px)) scale(.5)`, opacity: 0 },
        ],
        { duration: rnd(650, 1050), delay: rnd(0, 260), easing: "cubic-bezier(.25,.6,.5,1)", fill: "backwards" },
      ).onfinish = () => g.remove();
    }
  }

  /** Wisps of steam curl up off the strips. */
  private steam() {
    this.sizzle(25, 1600);
    const size = this.px;
    for (let i = 0; i < 6; i++) {
      const s = document.createElement("span");
      s.className = "stm";
      const w = size * rnd(0.14, 0.22);
      s.style.width = `${w}px`;
      s.style.height = `${w * 2.6}px`;
      s.style.left = `${50 + rnd(-20, 20)}%`;
      s.style.top = `${48 + rnd(-6, 8)}%`;
      this.els.fx.append(s);
      const sway = rnd(-0.25, 0.25) * size;
      s.animate(
        [
          { transform: "translate(-50%,-50%) scale(.4)", opacity: 0 },
          { transform: `translate(calc(-50% + ${sway * 0.4}px), calc(-50% - ${size * 0.35}px)) scale(.9) rotate(${rnd(-15, 15)}deg)`, opacity: 0.7, offset: 0.35 },
          { transform: `translate(calc(-50% - ${sway * 0.3}px), calc(-50% - ${size * 0.75}px)) scale(1.3) rotate(${rnd(-30, 30)}deg)`, opacity: 0.35, offset: 0.7 },
          { transform: `translate(calc(-50% + ${sway}px), calc(-50% - ${size * 1.05}px)) scale(1.7)`, opacity: 0 },
        ],
        { duration: rnd(1400, 1900), delay: i * 170, easing: "ease-out", fill: "backwards" },
      ).onfinish = () => s.remove();
    }
  }

  /** A hop in the pan: squash, jump, land, a pop of grease on landing. */
  private hop() {
    this.els.rx.animate(
      [
        { transform: "translateY(0) scale(1,1) rotate(0)", easing: "ease-in" },
        { transform: "translateY(5%) scale(1.12,.84) rotate(0)", offset: 0.16, easing: "ease-out" },
        { transform: "translateY(-48%) scale(.94,1.08) rotate(-9deg)", offset: 0.48, easing: "ease-in" },
        { transform: "translateY(4%) scale(1.14,.84) rotate(2deg)", offset: 0.78, easing: "ease-out" },
        { transform: "translateY(0) scale(1,1) rotate(0)" },
      ],
      { duration: 900, easing: "linear" },
    );
    this.sizzle(45, 1100);
    setTimeout(() => this.spatter(5), 700);
  }

  /** Crackling fat: pops flash here and there, the heat flares. */
  private crackle() {
    this.sizzle(55, 1400);
    this.heatPulse(1, 1300);
    this.els.sp.animate(
      [{ filter: "drop-shadow(0 .03em .05em rgba(60,10,0,.45)) brightness(1)" },
        { filter: "drop-shadow(0 0 .25em rgba(255,140,40,.9)) brightness(1.25) saturate(1.25)", offset: 0.3 },
        { filter: "drop-shadow(0 .03em .05em rgba(60,10,0,.45)) brightness(1)" }],
      { duration: 1300, easing: "ease-out" },
    );
    const size = this.px;
    for (let i = 0; i < 16; i++) {
      const p = document.createElement("span");
      p.className = "pk";
      const d = Math.max(4, size * rnd(0.09, 0.17));
      p.style.width = p.style.height = `${d}px`;
      // along the diagonal the strips lie on (the fx layer is 2.4 times the icon: 1% of it is 2.4% of the icon)
      const t = rnd(-0.3, 0.3);
      p.style.left = `${50 + (t * 100 + rnd(-6, 6)) / 2.4}%`;
      p.style.top = `${50 - (t * 100 + rnd(-6, 6)) / 2.4}%`;
      this.els.fx.append(p);
      p.animate(
        [
          { transform: "translate(-50%,-50%) scale(0)", opacity: 1 },
          { transform: "translate(-50%,-50%) scale(1.2)", opacity: 1, offset: 0.3 },
          { transform: `translate(-50%, calc(-50% - ${size * 0.12}px)) scale(0)`, opacity: 0 },
        ],
        { duration: rnd(320, 520), delay: rnd(0, 1000), easing: "ease-out", fill: "backwards" },
      ).onfinish = () => p.remove();
    }
  }

  /** A sizzling shiver, fast and small, settling. */
  private shiver() {
    this.sizzle(90, 1500);
    this.heatPulse(0.5, 900);
    this.els.rx.animate(
      [
        { transform: "rotate(0) scale(1)" },
        { transform: "rotate(-6deg) scale(1.08)", offset: 0.1 },
        { transform: "rotate(5deg) scale(1.08)", offset: 0.22 },
        { transform: "rotate(-4deg) scale(1.06)", offset: 0.34 },
        { transform: "rotate(3deg) scale(1.05)", offset: 0.46 },
        { transform: "rotate(-2deg) scale(1.03)", offset: 0.6 },
        { transform: "rotate(1deg) scale(1.01)", offset: 0.78 },
        { transform: "rotate(0) scale(1)" },
      ],
      { duration: 900, easing: "ease-out" },
    );
  }
}

if (typeof customElements !== "undefined" && !customElements.get("b8-bacon")) {
  customElements.define("b8-bacon", B8Bacon);
}

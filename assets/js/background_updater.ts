// The site background (2026-10-28: Bacon8Web.Components.Cosmos; assets/css/cosmos.css).
//
// - Switches it live when the profile's background picker saves ("update_background" /
//   "background_update"): a cosmos kind is one attribute on #global-background-canvas (its
//   layers come from <template id="cosmos-layers"> if the page started on a flat colour); a
//   gradient or a solid colour empties it and paints it.
// - Parallax: with a mouse, the star layers lean with the pointer (--px/--py, -1..1), at most
//   once a frame. Touch screens don't get it (nothing to follow).
// - Pauses every animation while the tab is hidden.

const COSMOS = ["galaxy", "nebula", "starfield", "orbit", "aurora", "void"];

/** The CSS for a flat background (pure; tested). */
export function flatBackground(kind: string, custom: Record<string, string> = {}): string {
  if (kind === "gradient") return `linear-gradient(135deg, ${custom.gradient_start || "#3B82F6"}, ${custom.gradient_end || "#9333EA"})`;
  return custom.solid_color || "#0F172A";
}

/** The pointer's place as -1..1 from the middle of the window (pure; tested). */
export function lean(x: number, y: number, w: number, h: number): [number, number] {
  const c = (v: number) => Math.max(-1, Math.min(1, v));
  return [c((x / Math.max(1, w)) * 2 - 1), c((y / Math.max(1, h)) * 2 - 1)];
}

export const BackgroundUpdater = {
  mounted(this: any) {
    const apply = (data: any) => {
      this.updateBackground(data);
      if (data.global) window.dispatchEvent(new CustomEvent("background-update", { detail: data }));
    };
    this.handleEvent("update_background", apply);
    this.handleEvent("background_update", apply);
    this.onGlobal = (e: any) => this.updateBackground(e.detail);
    window.addEventListener("background-update", this.onGlobal);

    // parallax, mouse only
    let raf = 0;
    let px = 0, py = 0;
    this.onMove = (e: PointerEvent) => {
      if (e.pointerType !== "mouse") return;
      [px, py] = lean(e.clientX, e.clientY, window.innerWidth, window.innerHeight);
      if (raf) return;
      raf = requestAnimationFrame(() => {
        raf = 0;
        const el = document.getElementById("global-background-canvas");
        if (!el || !el.classList.contains("cosmos")) return;
        el.style.setProperty("--px", px.toFixed(3));
        el.style.setProperty("--py", py.toFixed(3));
      });
    };
    if (window.matchMedia?.("(hover: hover) and (pointer: fine)").matches) window.addEventListener("pointermove", this.onMove, { passive: true });

    this.onVisibility = () => document.getElementById("global-background-canvas")?.classList.toggle("c-paused", document.hidden);
    document.addEventListener("visibilitychange", this.onVisibility);
  },

  destroyed(this: any) {
    window.removeEventListener("background-update", this.onGlobal);
    window.removeEventListener("pointermove", this.onMove);
    document.removeEventListener("visibilitychange", this.onVisibility);
  },

  updateBackground(data: any) {
    const kind: string = data?.background || "galaxy";
    const el = document.getElementById("global-background-canvas");
    if (!el) return;
    if (COSMOS.includes(kind)) {
      if (!el.classList.contains("cosmos")) {
        const tpl = document.getElementById("cosmos-layers") as HTMLTemplateElement | null;
        el.replaceChildren(...(tpl ? Array.from(tpl.content.cloneNode(true).childNodes) : []));
        el.className = "cosmos";
        el.style.background = "";
      }
      el.setAttribute("data-cosmos", kind);
      el.setAttribute("data-bg-type", "cosmos");
    } else {
      el.replaceChildren();
      el.className = "fixed inset-0 z-0 pointer-events-none background-overlay";
      el.removeAttribute("data-cosmos");
      el.setAttribute("data-bg-type", kind);
      el.style.background = flatBackground(kind, data?.custom_data || {});
    }
  },
};

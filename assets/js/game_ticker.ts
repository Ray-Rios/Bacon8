// The front page's game status corner (Bacon8Web.Components.GameTicker, 2026-10-29): turns to the
// next game every data-seconds, pauses while pointed at or focused, keeps its place when LiveView
// re-renders (the numbers refresh every 15 s, and the server always marks the first slide), and
// hides for the rest of the visit when dismissed.
const HIDE_KEY = "b8-game-ticker-hidden";

export const GameTicker = {
  mounted(this: any) {
    this.index = 0;
    this.paused = false;
    try { if (sessionStorage.getItem(HIDE_KEY) === "1") this.el.classList.add("is-hidden"); } catch {}

    this.onClick = (e: Event) => {
      const t = e.target as HTMLElement;
      const go = t.closest("[data-gt-go]") as HTMLElement | null;
      if (go) { this.show(Number(go.dataset.gtGo)); this.restart(); return; }
      if (t.closest("[data-gt-close]")) {
        this.el.classList.add("is-hidden");
        try { sessionStorage.setItem(HIDE_KEY, "1"); } catch {}
      }
    };
    this.pause = () => { this.paused = true; };
    this.resume = () => { this.paused = false; };
    this.el.addEventListener("click", this.onClick);
    this.el.addEventListener("pointerenter", this.pause);
    this.el.addEventListener("pointerleave", this.resume);
    this.el.addEventListener("focusin", this.pause);
    this.el.addEventListener("focusout", this.resume);
    this.restart();
  },
  updated(this: any) { this.show(this.index); },
  destroyed(this: any) {
    clearInterval(this.timer);
    this.el.removeEventListener("click", this.onClick);
  },
  slides(this: any): HTMLElement[] { return Array.from(this.el.querySelectorAll("[data-gt-slide]")); },
  restart(this: any) {
    clearInterval(this.timer);
    const secs = Math.max(3, Number(this.el.dataset.seconds) || 6);
    if (window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    this.timer = setInterval(() => {
      if (!this.paused && !document.hidden) this.show(this.index + 1);
    }, secs * 1000);
  },
  show(this: any, i: number) {
    const slides = this.slides();
    if (slides.length === 0) return;
    this.index = ((i % slides.length) + slides.length) % slides.length;
    slides.forEach((s: HTMLElement, n: number) => s.classList.toggle("is-on", n === this.index));
    this.el.querySelectorAll("[data-gt-go]").forEach((d: Element, n: number) => d.classList.toggle("is-on", n === this.index));
  },
};

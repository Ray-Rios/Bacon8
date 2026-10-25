// The GameCard hook: a game's card on /games (Bacon8Web.Components.GameCard).
//
// - Cycles the front's pictures every `data-seconds` (crossfade: moves .on), only
//   while the card is on screen, the tab is visible and the card isn't turned over.
// - Mouse: hovering turns the card (CSS); a click anywhere on it presses Play.
// - Touch: a tap turns it over (.flipped), a tap on Play plays, another tap turns it back.
// - Keyboard: the card is focusable (focus turns it); Enter presses Play.

export const GameCard = {
  mounted(this: any) {
    const el = this.el as HTMLElement;
    this.index = 0;
    this.touch = false;
    this.visible = true;

    el.addEventListener("pointerdown", (e: PointerEvent) => {
      this.touch = e.pointerType !== "mouse";
    });
    el.addEventListener("click", (e: MouseEvent) => {
      const target = e.target as Element;
      if (target.closest(".gc-play")) return;
      if (this.touch) {
        el.classList.toggle("flipped");
        return;
      }
      (el.querySelector("a.gc-play") as HTMLAnchorElement | null)?.click();
    });
    el.addEventListener("keydown", (e: KeyboardEvent) => {
      if (e.key === "Enter" && e.target === el) {
        e.preventDefault();
        (el.querySelector("a.gc-play") as HTMLAnchorElement | null)?.click();
      }
    });
    // Tapping elsewhere turns a flipped card back.
    this.onDocTap = (e: Event) => {
      if (!el.contains(e.target as Node)) el.classList.remove("flipped");
    };
    document.addEventListener("pointerdown", this.onDocTap);

    if ("IntersectionObserver" in window) {
      this.io = new IntersectionObserver((entries) => {
        for (const entry of entries) this.visible = entry.isIntersecting;
      });
      this.io.observe(el);
    }

    this.start();
  },

  // A LiveView re-render puts .on back on the first picture: show the current one.
  updated(this: any) {
    this.show(this.index);
    this.start();
  },

  destroyed(this: any) {
    clearInterval(this.timer);
    this.io?.disconnect();
    document.removeEventListener("pointerdown", this.onDocTap);
  },

  start(this: any) {
    clearInterval(this.timer);
    const el = this.el as HTMLElement;
    const count = el.querySelectorAll(".gc-pic").length;
    if (count < 2) return;
    if (window.matchMedia?.("(prefers-reduced-motion: reduce)").matches) return;
    const seconds = Math.max(2, Number(el.dataset.seconds) || 5);
    this.timer = setInterval(() => {
      const turned = el.classList.contains("flipped") || el.matches(":hover") || el.matches(":focus-within");
      if (!this.visible || document.hidden || turned) return;
      this.show(this.index + 1);
    }, seconds * 1000);
  },

  show(this: any, i: number) {
    const el = this.el as HTMLElement;
    const pics = el.querySelectorAll(".gc-pic");
    if (!pics.length) return;
    this.index = ((i % pics.length) + pics.length) % pics.length;
    pics.forEach((p, k) => p.classList.toggle("on", k === this.index));
    el.querySelectorAll(".gc-dots i").forEach((d, k) => d.classList.toggle("on", k === this.index));
  },
};

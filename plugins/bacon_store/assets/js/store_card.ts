// The storefront's glass cards and the item sheet (2026-10-28; BaconStoreWeb.StoreLive,
// BaconStoreWeb.StoreComponents.store_card/1, styles in priv/store_cards.css).
//
// StoreCard: hovering turns a card over (CSS), like the games' cards; a click opens the item's
// sheet. On a touch screen the first tap turns it and the second opens it. Enter opens it too.
// StoreSheet: the sheet slides up from the bottom; Esc, the backdrop or ✕ slide it away again
// before the LiveView forgets it.

export const StoreCard = {
  mounted(this: any) {
    const el = this.el as HTMLElement;
    this.touch = false;
    const open = () => this.pushEvent("open_item", { slug: el.dataset.slug });
    el.addEventListener("pointerdown", (e: PointerEvent) => {
      this.touch = e.pointerType !== "mouse";
    });
    el.addEventListener("click", () => {
      if (this.touch && !el.classList.contains("flipped")) {
        document.querySelectorAll(".sc.flipped").forEach((c) => c !== el && c.classList.remove("flipped"));
        el.classList.add("flipped");
        return;
      }
      el.classList.remove("flipped");
      open();
    });
    el.addEventListener("keydown", (e: KeyboardEvent) => {
      if ((e.key === "Enter" || e.key === " ") && e.target === el) {
        e.preventDefault();
        open();
      }
    });
    this.onDocTap = (e: Event) => {
      if (!el.contains(e.target as Node)) el.classList.remove("flipped");
    };
    document.addEventListener("pointerdown", this.onDocTap);
  },
  destroyed(this: any) {
    document.removeEventListener("pointerdown", this.onDocTap);
  },
};

export const StoreSheet = {
  mounted(this: any) {
    const el = this.el as HTMLElement;
    this.close = () => {
      if (el.classList.contains("closing")) return;
      el.classList.add("closing");
      setTimeout(() => this.pushEvent("close_item", {}), 260);
    };
    el.addEventListener("click", (e: MouseEvent) => {
      if ((e.target as Element).closest("[data-sheet-close]")) this.close();
    });
    this.onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") this.close();
    };
    window.addEventListener("keydown", this.onKey);
    // the page behind doesn't scroll while the sheet is up
    this.scroller = document.querySelector("[data-store-scroll]") as HTMLElement | null;
    if (this.scroller) this.scroller.style.overflow = "hidden";
    (el.querySelector(".ss-panel") as HTMLElement | null)?.focus({ preventScroll: true });
  },
  updated(this: any) {
    // a new item in the same sheet: open again
    this.el.classList.remove("closing");
  },
  destroyed(this: any) {
    window.removeEventListener("keydown", this.onKey);
    if (this.scroller) this.scroller.style.overflow = "";
  },
};

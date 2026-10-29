// IntroReveal: the home page's sections fade up as they scroll into view (HomeLive,
// assets/css/intro.css). Without JavaScript everything is simply visible: the hiding only starts
// once this hook has marked what is already on screen, so nothing blinks.

/** Whether a box from `top` to `bottom` (px from the window's top) shows in a window `vh` tall (pure; tested). */
export function inView(top: number, bottom: number, vh: number, margin = 0.08): boolean {
  return bottom > 0 && top < vh * (1 - margin);
}

export const IntroReveal = {
  mounted(this: any) {
    const items: HTMLElement[] = Array.from(this.el.querySelectorAll("[data-reveal]"));
    const vh = window.innerHeight;
    for (const el of items) {
      const r = el.getBoundingClientRect();
      if (inView(r.top, r.bottom, vh)) el.classList.add("in");
    }
    this.el.classList.add("reveal-ready");
    if (!("IntersectionObserver" in window)) {
      items.forEach((el) => el.classList.add("in"));
      return;
    }
    this.io = new IntersectionObserver(
      (entries) => {
        for (const e of entries) {
          if (!e.isIntersecting) continue;
          e.target.classList.add("in");
          this.io.unobserve(e.target);
        }
      },
      { rootMargin: "0px 0px -8% 0px" },
    );
    items.filter((el) => !el.classList.contains("in")).forEach((el) => this.io.observe(el));
  },
  destroyed(this: any) {
    this.io?.disconnect();
  },
};

/**
 * IntroTagline: the front door's tagline. It types itself in with CSS; hovering it (or tapping it,
 * or focusing it with the keyboard) types the old secret, "IT'S A SECRET TO EVERYBODY.", and
 * leaving it types the tagline back.
 */
export const IntroTagline = {
  mounted(this: any) {
    const span = this.el.querySelector('.intro-type') as HTMLElement | null;
    if (!span) return;
    const main = span.textContent || '';
    // the typing's length always matches the words (a hand-set --n cut a longer tagline short)
    span.style.setProperty('--n', String(main.length));
    const alt = this.el.dataset.alt || '';
    let showing = main;
    let back: any = null;
    const type = (text: string) => {
      if (showing === text) return;
      showing = text;
      span.textContent = text;
      span.style.setProperty('--n', String(text.length));
      // a different (identical) animation name makes the typing start again
      const odd = span.classList.contains('again');
      span.classList.toggle('again', !odd);
      span.classList.toggle('again-2', odd);
    };
    this.secret = () => {
      clearTimeout(back);
      type(alt);
    };
    this.unsecret = () => {
      clearTimeout(back);
      back = setTimeout(() => type(main), 900);
    };
    this.tap = () => {
      if (showing === alt) return type(main);
      this.secret();
      back = setTimeout(() => type(main), 3500);
    };
    this.el.addEventListener('pointerenter', (e: PointerEvent) => e.pointerType === 'mouse' && this.secret());
    this.el.addEventListener('pointerleave', (e: PointerEvent) => e.pointerType === 'mouse' && this.unsecret());
    this.el.addEventListener('click', (e: MouseEvent) => {
      if ((e as any).pointerType === 'mouse' || matchMedia('(hover: hover)').matches) return;
      this.tap();
    });
    this.el.addEventListener('focus', this.secret);
    this.el.addEventListener('blur', this.unsecret);
  },
};

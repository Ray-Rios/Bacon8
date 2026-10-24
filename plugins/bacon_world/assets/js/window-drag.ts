// Movable in-game windows (the player, target, hotbar, inventory, loot and merchant windows
// and the chat). Drag a window by its title, or by any part of it that isn't a control
// (buttons, item slots, lists, inputs). Positions are saved per window in this browser
// (localStorage, `bacon_world:win:<key>`) and kept on screen when the view is resized.
// The Esc menu's "Reset windows" puts them back.

export const WIN_PREFIX = 'bacon_world:win:';

/** Elements a drag never starts on. */
const CONTROLS = 'button, input, textarea, select, a, label, .s, .x, .row, .list, [data-chat-log], [data-no-drag]';

type Pos = { x: number; y: number };

/** `pos` moved so a `w` x `h` window stays inside a `vw` x `vh` view (at least `keep` px visible each way). */
export function clampPos(pos: Pos, w: number, h: number, vw: number, vh: number, keep = 40): Pos {
  const minX = Math.min(0, -(w - keep)), maxX = Math.max(0, vw - Math.min(w, keep));
  const minY = 0, maxY = Math.max(0, vh - Math.min(h, keep));
  return { x: Math.round(Math.min(maxX, Math.max(minX, pos.x))), y: Math.round(Math.min(maxY, Math.max(minY, pos.y))) };
}

function load(key: string): Pos | null {
  try {
    const v = JSON.parse(window.localStorage.getItem(WIN_PREFIX + key) || 'null');
    return v && Number.isFinite(v.x) && Number.isFinite(v.y) ? { x: v.x, y: v.y } : null;
  } catch {
    return null;
  }
}

function save(key: string, p: Pos | null) {
  try {
    if (p) window.localStorage.setItem(WIN_PREFIX + key, JSON.stringify(p));
    else window.localStorage.removeItem(WIN_PREFIX + key);
  } catch {
    // storage blocked: the position lasts for this visit
  }
}

interface Movable { el: HTMLElement; key: string; place: (p: Pos) => void; defaults: Partial<CSSStyleDeclaration> }
const movables: Movable[] = [];

/**
 * Makes `el` (absolutely positioned inside its offset parent) movable and restores its saved
 * spot. `handle`, if given, limits where a drag can start (e.g. the chat's title row).
 */
export function makeMovable(el: HTMLElement, key: string, handle?: HTMLElement): () => void {
  const defaults = { left: el.style.left, top: el.style.top, right: el.style.right, bottom: el.style.bottom, transform: el.style.transform };
  const host = () => (el.offsetParent as HTMLElement | null) || el.parentElement || document.body;
  const place = (p: Pos, tries = 0) => {
    const hb = host().getBoundingClientRect();
    // Not laid out yet (the game's layer is still hidden while the world loads): placing now
    // would clamp everything into a 0 x 0 view, i.e. the top-left corner. Try again shortly.
    if (hb.width < 1 || hb.height < 1) {
      if (tries < 900) requestAnimationFrame(() => place(p, tries + 1));
      return;
    }
    const c = clampPos(p, el.offsetWidth, el.offsetHeight, hb.width, hb.height);
    el.style.left = `${c.x}px`;
    el.style.top = `${c.y}px`;
    el.style.right = 'auto';
    el.style.bottom = 'auto';
    el.style.transform = 'none';
  };
  const m: Movable = { el, key, place, defaults };
  movables.push(m);
  const saved = load(key);
  if (saved) place(saved);

  let start: { x: number; y: number; left: number; top: number } | null = null;
  let moved = false;
  const onDown = (e: MouseEvent) => {
    if (e.button !== 0) return;
    const t = e.target as HTMLElement;
    if (handle ? !handle.contains(t) : !!t.closest(CONTROLS)) return;
    if (handle && t.closest('button, input, a')) return;
    const r = el.getBoundingClientRect(), hb = host().getBoundingClientRect();
    start = { x: e.clientX, y: e.clientY, left: r.left - hb.left, top: r.top - hb.top };
    moved = false;
    e.preventDefault(); // no text selection
    e.stopPropagation(); // not a click on the world (camera, pointer lock)
    window.addEventListener('mousemove', onMove);
    window.addEventListener('mouseup', onUp, true);
  };
  const onMove = (e: MouseEvent) => {
    if (!start) return;
    const dx = e.clientX - start.x, dy = e.clientY - start.y;
    if (!moved && Math.hypot(dx, dy) < 3) return;
    moved = true;
    place({ x: start.left + dx, y: start.top + dy });
  };
  const onUp = (e: MouseEvent) => {
    window.removeEventListener('mousemove', onMove);
    window.removeEventListener('mouseup', onUp, true);
    if (start && moved) {
      e.stopPropagation();
      const hb = host().getBoundingClientRect(), r = el.getBoundingClientRect();
      save(key, { x: r.left - hb.left, y: r.top - hb.top });
    }
    start = null;
  };
  el.addEventListener('mousedown', onDown);
  return () => {
    el.removeEventListener('mousedown', onDown);
    const i = movables.indexOf(m);
    if (i >= 0) movables.splice(i, 1);
  };
}

/** Keeps every saved window on screen (call on resize, and when a window is shown). */
export function keepWindowsOnScreen(): void {
  for (const m of movables) {
    const p = load(m.key);
    if (p) m.place(p);
  }
}

/** Forgets every saved position and puts the windows back where they started. */
export function resetWindows(): void {
  for (const m of movables) {
    save(m.key, null);
    Object.assign(m.el.style, m.defaults);
  }
}

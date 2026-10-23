// Mouse movement for mouse-look, made safe for remote desktop.
//
// While the pointer is locked, Chrome keeps the hidden cursor inside the page by moving
// it back to the middle whenever it comes within 15% of an edge, and it measures every
// move from the cursor's previous position. On a local mouse that works. Over remote
// desktop (RDP, VNC and the like) the remote end sends where its cursor is, not how far
// it moved, and only learns about the move back to the middle a network round trip
// later. Until then every position it sends is still out near the edge, so each one
// arrives as a jump of a third of the page or more, all in the direction you're turning.
// Applied as they are, those jumps spin the camera; dropped, they lose the turn made in
// that time (the camera falls behind, then lurches). Later, each of Chrome's moves to the
// middle reaches the remote end and puts its cursor there, and the next move comes out
// short by however far the cursor had gone since.
//
// The filter keeps a small set of guesses about what happened (did Chrome move the
// cursor to the middle after the last event? has the remote end caught up with it?), and
// for each guess works out where both cursors are and how far the hand moved. Guesses
// that need the hand to jump about are dropped; the camera follows the steadiest one. On
// a local mouse the plainest guess (each report is the hand's move) always wins.

export interface Move {
  x: number;
  y: number;
}

export interface Page {
  width: number; // CSS pixels
  height: number;
  /** devicePixelRatio: Chrome may report movement in device pixels. */
  dpr: number;
}

/** The biggest believable move between two mouse events, per axis, for a page this size (CSS pixels). */
export function jumpLimit(width: number, height: number): Move {
  // Chrome's jumps are at least 35% of the page; a fast flick over a slow link is a few percent.
  return { x: Math.max(120, width * 0.22), y: Math.max(90, height * 0.22) };
}

// A guess about the two cursors, and how well it explains the moves so far.
interface Guess {
  remote: Move; // where the remote end has its cursor, from the middle of the page
  centred: boolean; // Chrome moved its cursor to the middle after the last event
  pending: number; // moves to the middle the remote end has yet to make
  // The remote end is catching up: it follows Chrome's moves to the middle about as far
  // apart as Chrome made them, so after one, another per event is expected until none are left.
  catching: boolean;
  total: Move; // the hand's movement so far, by this guess
  cost: number; // how unsteady that makes the hand (lower is better)
}

const GUESSES = 10;
const MAX_PENDING = 48; // a 400 ms round trip at 120 events a second
// Costs, in pixels of unsteadiness: a guess that needs more unusual events must explain
// the moves clearly better to win.
const CATCH_UP_COST = 3;
const CENTRE_COST = 1;
const RESYNC_COST = 60; // the cursors were somewhere unknown: assume the hand carried on
const IMPOSSIBLE = 1e6;
// How quickly the expected move follows the hand (per event): steady over bursty input.
const EXPECT_RATE = 0.35;
// Older unsteadiness counts for less, so the guesses recover from a bad patch.
const FORGET = 0.9;

const dist = (a: Move, b: Move) => Math.hypot(a.x - b.x, a.y - b.y);

export class MouseFilter {
  /** Moves seen, and moves repaired (where the camera did not simply follow the report). */
  moves = 0;
  repaired = 0;

  private guesses: Guess[] = [];
  private expect: Move = { x: 0, y: 0 }; // the hand's recent move per event, smoothed
  private remote = false;

  /** `page`: the page's size now. */
  constructor(private readonly page: () => Page) {
    this.reset();
  }

  /**
   * Forget the history (the pointer was locked or released, or steering started).
   * `cursor`: where the cursor is, from the middle of the page, if known.
   */
  reset(cursor: Move | null = null): void {
    this.guesses = [
      { remote: cursor ? { ...cursor } : { x: 0, y: 0 }, centred: false, pending: 0, catching: false, total: { x: 0, y: 0 }, cost: 0 },
    ];
    this.expect = { x: 0, y: 0 };
    this.remote = false;
  }

  /** True once remote-desktop jumps have been seen since the last reset. */
  get remoteDesktop(): boolean {
    return this.remote;
  }

  /** One mouse event's movementX/Y in, the hand's movement out. */
  filter(dx: number, dy: number): Move {
    this.moves++;
    const page = this.page();
    const lim = jumpLimit(page.width, page.height);
    // Chrome's edge zone, 15% in from each side, in the units movement comes in.
    const zoneMin = { x: page.width * 0.35, y: page.height * 0.35 };
    const zoneMax = { x: zoneMin.x * Math.max(1, page.dpr), y: zoneMin.y * Math.max(1, page.dpr) };
    const jump = Math.abs(dx) > lim.x || Math.abs(dy) > lim.y;
    if (jump) this.remote = true;

    const next: Guess[] = [];
    // A guess for this event: Chrome measured from `from`; the remote cursor started from
    // `was`; `landed`: Chrome's moves to the middle it caught up with just before (0, 1, or all).
    const add = (g: Guess, from: Move, was: Move, landed: number, extra: number, hand?: Move) => {
      const pos = { x: from.x + dx, y: from.y + dy }; // both cursors are here now
      const h = hand ?? { x: pos.x - was.x, y: pos.y - was.y };
      const expected = g.catching && g.pending > 0;
      const surprise = ((landed > 0) !== expected ? CATCH_UP_COST : 0) + (landed > 1 ? CATCH_UP_COST : 0);
      let cost = g.cost * FORGET + dist(h, this.expect) + extra + surprise;
      if (Math.abs(h.x) > lim.x || Math.abs(h.y) > lim.y) cost += IMPOSSIBLE;
      const total = { x: g.total.x + h.x, y: g.total.y + h.y };
      const pending = Math.max(0, g.pending - landed);
      const catching = landed > 0 && pending > 0;
      const ax = Math.abs(pos.x);
      const ay = Math.abs(pos.y);
      const surely = ax > zoneMax.x || ay > zoneMax.y;
      const maybe = ax > zoneMin.x || ay > zoneMin.y;
      // Does Chrome move its cursor to the middle now? Surely past the far edge of the
      // zone; between its possible edges (the units are not certain), keep both answers.
      if (maybe) next.push({ remote: pos, centred: true, pending: Math.min(MAX_PENDING, pending + 1), catching, total, cost });
      if (!surely) next.push({ remote: pos, centred: false, pending, catching, total, cost: cost + (maybe ? CENTRE_COST : 0) });
    };

    for (const g of this.guesses) {
      const chrome = g.centred ? { x: 0, y: 0 } : g.remote; // where Chrome measured from
      // The remote end has not caught up (or there was nothing to catch up with).
      add(g, chrome, g.remote, 0, 0);
      if (g.pending > 0) {
        // One of Chrome's moves to the middle reached the remote end just before this
        // event (or all of them did): its cursor started from the middle.
        add(g, chrome, { x: 0, y: 0 }, 1, 0);
        if (g.pending > 1) add(g, chrome, { x: 0, y: 0 }, g.pending, 0);
      }
      // Lost track: Chrome measured from the middle, the remote cursor was somewhere
      // unknown; the hand carried on.
      if (jump) add({ ...g, pending: g.pending + 1 }, { x: 0, y: 0 }, { x: 0, y: 0 }, 0, RESYNC_COST, { ...this.expect });
    }

    next.sort((a, b) => a.cost - b.cost);
    // The same situation reached two ways: keep the cheaper.
    const kept: Guess[] = [];
    for (const g of next) {
      if (kept.length >= GUESSES) break;
      const same = kept.some(
        (k) =>
          k.centred === g.centred &&
          k.pending === g.pending &&
          k.catching === g.catching &&
          dist(k.remote, g.remote) < 0.5 &&
          dist(k.total, g.total) < 0.5
      );
      if (!same) kept.push(g);
    }
    const base = kept[0].cost;
    for (const g of kept) g.cost -= base;
    this.guesses = kept;

    // The camera follows the best guess's total, a believable step at a time. (Totals are
    // kept relative to what the camera has been given, so they stay small.)
    const best = kept[0];
    const out = {
      x: Math.max(-lim.x, Math.min(lim.x, best.total.x)),
      y: Math.max(-lim.y, Math.min(lim.y, best.total.y)),
    };
    for (const g of kept) g.total = { x: g.total.x - out.x, y: g.total.y - out.y };
    if (Math.abs(out.x - dx) > 0.5 || Math.abs(out.y - dy) > 0.5) this.repaired++;
    this.expect = {
      x: this.expect.x + (out.x - this.expect.x) * EXPECT_RATE,
      y: this.expect.y + (out.y - this.expect.y) * EXPECT_RATE,
    };
    return out;
  }
}

export default MouseFilter;

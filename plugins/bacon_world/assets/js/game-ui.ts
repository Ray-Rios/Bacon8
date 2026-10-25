// Bacon World's in-game windows, EverQuest style: the player window (name, HP, mana,
// experience), the target window (con colour), the hotbar (left and right hand on
// the mouse buttons, Q E F Z X for the special attacks the skill tree will give),
// the inventory (I: two hands, what is worn and 24 bag slots; click
// an item to pick it up on the cursor, click a slot to put it down or swap; right-click
// to equip or unequip), the loot window and the merchant window (right-click a row to
// buy it; with the merchant open, right-click an item in your bags to sell it). Plain DOM with its
// own scoped CSS (.bwg).
import { describe, iconUrl, item, money } from './items';
import { keepWindowsOnScreen, makeMovable } from './window-drag';

export interface InvItem { slot: string; item_id: string; quantity: number }
export interface Inventory { items: InvItem[]; coins: number; bag_slots: number }
export interface LootItem { index: number; item_id: string; quantity: number }
export interface PlayerInfo { name: string; level: number; hp: number; maxHp: number; mp: number; maxMp: number; xp: number; xpNext: number; pvp: boolean; sound: boolean }
export interface TargetInfo { name: string; color: string; level?: number; hpPct: number; corpse?: boolean; kind: 'mob' | 'player' | 'npc'; sub?: string }
export interface MerchantInfo { id: string; name: string; title?: string }
export interface StockItem { item_id: string; price: number }

export interface GameUICallbacks {
  move(from: string, to: string): void;
  equip(slot: string): void;
  unequip(slot: string): void;
  destroy(slot: string): void;
  lootTake(index: number): void;
  lootAll(): void;
  lootClose(): void;
  buy(itemId: string): void;
  sell(slot: string): void;
  merchantClose(): void;
  cast(slug: string): void;
  pvp(): void;
  sound(): void;
  /** A window opened or closed (the scene frees the mouse for it). */
  windows(open: boolean): void;
}

const CSS = `
.bwg{position:absolute;inset:0;pointer-events:none;font:12px/1.3 "Trebuchet MS","Segoe UI",Arial,sans-serif;color:#e8dcc0;user-select:none;-webkit-user-select:none;z-index:5}
.bwg *{box-sizing:border-box}
.bwg .w{position:absolute;pointer-events:auto;background:var(--bwg-bg,rgba(17,15,13,.96));border:1px solid var(--bwg-border,#6d5b3c);border-radius:3px;box-shadow:inset 0 0 0 1px rgba(0,0,0,.7),0 8px 22px rgba(0,0,0,.55)}
.bwg .t{padding:3px 8px;background:linear-gradient(var(--bwg-title-a,#2c251c),var(--bwg-title-b,#191510));border-bottom:1px solid var(--bwg-border-soft,#4b3f2b);color:var(--bwg-accent,#e9cf8f);font-size:11px;letter-spacing:.08em;text-transform:uppercase;display:flex;justify-content:space-between;align-items:center;gap:8px}
.bwg .t b{font-weight:600;letter-spacing:.04em;text-transform:none;font-size:12px}
.bwg .x{cursor:pointer;color:var(--bwg-accent,#bfa66c);padding:0 2px}.bwg .x:hover{color:#fff}
.bwg .bar{position:relative;height:12px;background:#0a0908;border:1px solid #3b3226;border-radius:2px;overflow:hidden;margin-top:3px}
.bwg .bar i{position:absolute;inset:0 auto 0 0;transition:width .25s}
.bwg .bar span{position:absolute;inset:0;text-align:center;font-size:9px;line-height:10px;color:#fff;text-shadow:0 1px 1px #000}
.bwg .hp i{background:linear-gradient(#e5483a,#9c1f16)}.bwg .mp i{background:linear-gradient(#5b8cff,#2147a8)}.bwg .xp i{background:linear-gradient(#e8c25a,#9a7420)}
.bwg .pw{left:12px;top:12px;width:208px;padding:0 0 6px}
.bwg .pw .in{padding:2px 8px 0}
.bwg .row{display:flex;gap:4px;margin-top:5px}
.bwg .btn{pointer-events:auto;cursor:pointer;font:inherit;font-size:10px;color:#e8dcc0;background:linear-gradient(var(--bwg-title-a,#3a3024),var(--bwg-title-b,#211b14));border:1px solid var(--bwg-border,#6d5b3c);border-radius:2px;padding:2px 7px}
.bwg .btn:hover{border-color:#c9a65e;color:#fff}.bwg .btn.on{background:linear-gradient(#7a2a1f,#42140f);border-color:#d0573f}
.bwg .btn:disabled{opacity:.4;cursor:default}
.bwg .tw{left:50%;top:12px;transform:translateX(-50%);min-width:220px;padding:0 0 6px;display:none}
.bwg .tw .nm{padding:4px 8px 0;font-weight:700;text-align:center;text-shadow:0 1px 2px #000}
.bwg .tw .in{padding:0 8px}
.bwg .hb{left:50%;bottom:12px;transform:translateX(-50%);padding:5px 6px 6px;display:flex;flex-direction:column;gap:5px}
.bwg .hb .slots{display:flex;gap:4px;align-items:center}
.bwg .hb .sep{width:6px}
.bwg .s{position:relative;width:44px;height:44px;background:radial-gradient(circle at 50% 40%,#1c1915,#0a0908);border:1px solid #000;box-shadow:inset 0 0 0 1px #3b3226;border-radius:3px;display:flex;align-items:center;justify-content:center;pointer-events:auto}
.bwg .s img{width:38px;height:38px;object-fit:contain;filter:drop-shadow(0 1px 1px #000);pointer-events:none}
.bwg .s .k{position:absolute;left:3px;top:1px;font-size:9px;color:#bfa66c;text-shadow:0 1px 1px #000}
.bwg .s .q{position:absolute;right:3px;bottom:1px;font-size:10px;color:#fff;text-shadow:0 0 2px #000,0 0 2px #000}
.bwg .s .cd{position:absolute;inset:0;border-radius:3px;pointer-events:none}
.bwg .s .lk{color:#5d5446;font-size:16px}
.bwg .s.hov:hover,.bwg .s.drop:hover{box-shadow:inset 0 0 0 1px #c9a65e;cursor:pointer}
.bwg .s .lb{position:absolute;bottom:2px;left:0;right:0;text-align:center;font-size:8px;color:#7d6c4f;text-transform:uppercase;letter-spacing:.06em;pointer-events:none}
.bwg .s.off{opacity:.45}
.bwg .inv{right:16px;top:70px;width:662px;max-width:calc(100% - 24px);display:none}
.bwg .inv .body{display:flex;gap:12px;padding:10px}
.bwg .eq{display:grid;grid-template-columns:repeat(3,52px);gap:6px;align-content:start}
.bwg .eq .s{width:52px;height:52px}
.bwg .stats{flex:1;min-width:120px;font-size:11px;color:#cdbf9f}
.bwg .stats div{display:flex;justify-content:space-between;padding:2px 0;border-bottom:1px solid rgba(109,91,60,.25)}
.bwg .stats .coins{color:#f0d77a}
.bwg .bags{display:grid;grid-template-columns:repeat(6,44px);gap:4px}
.bwg .foot{display:flex;justify-content:space-between;gap:6px;padding:0 10px 10px}
.bwg .loot{left:50%;top:38%;transform:translate(-120%,-50%);display:none;width:262px}
.bwg .loot .grid{display:grid;grid-template-columns:repeat(5,44px);gap:4px;padding:10px}
.bwg .loot .foot{padding:0 10px 10px}
.bwg .mer{left:16px;top:70px;width:330px;max-width:calc(100% - 24px);display:none}
.bwg .mer .list{max-height:330px;overflow-y:auto;padding:6px 8px;display:flex;flex-direction:column;gap:3px}
.bwg .mer .row{display:flex;align-items:center;gap:8px;padding:3px 4px;border:1px solid transparent;border-radius:3px;cursor:pointer}
.bwg .mer .row:hover{border-color:#4b3f2b;background:rgba(201,166,94,.06)}
.bwg .mer .row.sel{border-color:#c9a65e;background:rgba(201,166,94,.12)}
.bwg .mer .row .s{width:36px;height:36px;flex:none}.bwg .mer .row .s img{width:32px;height:32px}
.bwg .mer .row .nm{flex:1;font-size:12px}.bwg .mer .row .pr{color:#f0d77a;font-size:11px;white-space:nowrap}
.bwg .mer .foot{align-items:center}
.bwg .mer .sellbox{display:flex;align-items:center;gap:8px;padding:6px 10px;border-top:1px solid #4b3f2b}
.bwg .mer .sellbox .msg2{flex:1;font-size:11px;color:#bfae88}
.bwg .mer .coins{color:#f0d77a;font-size:11px;padding:0 10px 6px}
.bwg .tip{position:fixed;display:none;pointer-events:none;max-width:240px;padding:6px 8px;background:var(--bwg-bg,rgba(10,9,8,.96));border:1px solid var(--bwg-border,#6d5b3c);border-radius:3px;font-size:11px;color:#d8ccb0;z-index:10;box-shadow:0 6px 14px rgba(0,0,0,.6)}
.bwg .tip b{display:block;color:#f0d77a;font-size:12px;margin-bottom:2px}
.bwg .cur{position:fixed;width:40px;height:40px;pointer-events:none;display:none;z-index:11;transform:translate(-50%,-50%)}
.bwg .cur img{width:100%;height:100%;object-fit:contain;filter:drop-shadow(0 2px 3px #000)}
.bwg .msg{position:absolute;left:50%;top:22%;transform:translateX(-50%);color:#f0d77a;font-size:15px;text-shadow:0 2px 4px #000,0 0 2px #000;pointer-events:none;opacity:0;transition:opacity .4s;text-align:center;white-space:nowrap}
@media (max-width:640px){.bwg .inv{left:8px;right:8px;width:auto;top:60px}.bwg .inv .body{flex-wrap:wrap}.bwg .loot{transform:translate(-50%,-50%)}.bwg .s{width:38px;height:38px}.bwg .bags{grid-template-columns:repeat(6,38px)}}
`;

type Attrs = Record<string, any>;
/** What a merchant pays for one of an item (BaconWorld.Merchants.buy_price/1: a quarter, at least a copper). */
export function sellPrice(id: string): number {
  const v = item(id)?.value || 0;
  return v > 0 ? Math.max(1, Math.trunc(v * 0.25)) : 0;
}

function h(tag: string, attrs: Attrs = {}, ...kids: Array<Node | string | null | undefined | false>): HTMLElement {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (v === undefined || v === null || v === false) continue;
    if (k === 'class') el.className = v;
    else if (k === 'style' && typeof v === 'object') Object.assign(el.style, v);
    else if (k.startsWith('on') && typeof v === 'function') (el as any)[k] = v;
    else el.setAttribute(k, v === true ? '' : String(v));
  }
  for (const c of kids) if (c !== null && c !== undefined && c !== false) el.append(c);
  return el;
}

const HAND_SLOTS: Array<[string, string]> = [['main', 'Primary'], ['off', 'Secondary']];
const WORN_SLOTS: Array<[string, string]> = [['chest', 'Chest'], ['legs', 'Legs'], ['feet', 'Feet'], ['under_top', 'Undershirt'], ['under_bottom', 'Underwear']];
const FUTURE_SLOTS = ['Head', 'Arms', 'Hands'];
const EQUIP_SLOTS = new Set(['main', 'off', ...WORN_SLOTS.map(([s]) => s)]);
const SPECIAL_KEYS = ['Q', 'E', 'F', 'Z', 'X'];

export class GameUI {
  readonly root: HTMLDivElement;
  private cb: GameUICallbacks;
  private style: HTMLStyleElement;
  private player: HTMLElement;
  private target: HTMLElement;
  private hotbar: HTMLElement;
  private inv: HTMLElement;
  private loot: HTMLElement;
  private mer: HTMLElement;
  private merchant: MerchantInfo | null = null;
  private stock: StockItem[] = [];
  private stockSel: string | null = null;
  private tip: HTMLElement;
  private cursorEl: HTMLElement;
  private msgEl: HTMLElement;
  private inventory: Inventory = { items: [], coins: 0, bag_slots: 24 };
  private lootItems: LootItem[] = [];
  private held: InvItem | null = null; // the item on the cursor
  private info: PlayerInfo | null = null;
  private hands: { left: string | null; right: string | null } = { left: null, right: null };
  // the Q..X slots, drawn by the skill bars (skills-ui.ts) once the skill tree is up
  private skillSlots: ((key: string) => HTMLElement) | null = null;
  private msgTimer: ReturnType<typeof setTimeout> | null = null;
  private onMouseMove = (e: MouseEvent) => this.follow(e);

  constructor(host: HTMLElement, cb: GameUICallbacks) {
    this.cb = cb;
    this.style = document.createElement('style');
    this.style.textContent = CSS;
    document.head.appendChild(this.style);
    this.root = h('div', { class: 'bwg' }) as HTMLDivElement;
    this.player = h('div', { class: 'w pw' });
    this.target = h('div', { class: 'w tw' });
    this.hotbar = h('div', { class: 'w hb' });
    this.inv = h('div', { class: 'w inv' });
    this.loot = h('div', { class: 'w loot' });
    this.mer = h('div', { class: 'w mer' });
    this.tip = h('div', { class: 'tip' });
    this.cursorEl = h('div', { class: 'cur' });
    this.msgEl = h('div', { class: 'msg' });
    this.root.append(this.player, this.target, this.hotbar, this.inv, this.loot, this.mer, this.msgEl, this.tip, this.cursorEl);
    host.appendChild(this.root);
    // Every window can be dragged to a new spot (window-drag.ts), remembered per browser.
    this.unmovable = [
      makeMovable(this.player, 'player'), makeMovable(this.target, 'target'), makeMovable(this.hotbar, 'hotbar'),
      makeMovable(this.inv, 'inventory'), makeMovable(this.loot, 'loot'), makeMovable(this.mer, 'merchant'),
    ];
    window.addEventListener('resize', keepWindowsOnScreen);
    window.addEventListener('mousemove', this.onMouseMove);
    // Clicks on the game world while holding an item put it back (EverQuest
    // would drop it on the ground; we don't have ground items yet).
    this.root.addEventListener('contextmenu', (e) => e.preventDefault());
    this.renderHotbar({ left: null, right: null });
  }

  private unmovable: Array<() => void> = [];

  dispose() {
    window.removeEventListener('mousemove', this.onMouseMove);
    window.removeEventListener('resize', keepWindowsOnScreen);
    this.unmovable.forEach((f) => f());
    this.root.remove();
    this.style.remove();
  }

  // ---------------------------------------------------------------- player

  setPlayer(p: PlayerInfo) {
    this.info = p;
    const pct = (a: number, b: number) => `${b > 0 ? Math.max(0, Math.min(100, (a / b) * 100)) : 0}%`;
    this.player.replaceChildren(
      h('div', { class: 't' }, h('b', {}, p.name), `Level ${p.level}`),
      h('div', { class: 'in' },
        h('div', { class: 'bar hp', title: 'Hit points' }, h('i', { style: { width: pct(p.hp, p.maxHp) } }), h('span', {}, `${p.hp} / ${p.maxHp}`)),
        h('div', { class: 'bar mp', title: 'Mana' }, h('i', { style: { width: pct(p.mp, p.maxMp) } }), h('span', {}, `${p.mp} / ${p.maxMp}`)),
        h('div', { class: 'bar xp', title: 'Experience to the next level' }, h('i', { style: { width: pct(p.xp, p.xpNext) } }), h('span', {}, p.xpNext > 0 ? `${Math.floor((p.xp / p.xpNext) * 100)}%` : 'max')),
        h('div', { class: 'row' },
          h('button', { class: 'btn' + (p.pvp ? ' on' : ''), title: 'Player versus player: both players must be flagged', onclick: () => this.cb.pvp() }, p.pvp ? 'PvP on' : 'PvP off'),
          h('button', { class: 'btn', onclick: () => this.cb.sound() }, p.sound ? 'Sound on' : 'Sound off'),
          h('button', { class: 'btn', title: 'Inventory (I)', onclick: () => this.toggleInventory() }, 'Inventory'))));
    if (this.inv.style.display === 'block') this.renderInventory();
  }

  // ---------------------------------------------------------------- target

  setTarget(t: TargetInfo | null) {
    if (!t) {
      this.target.style.display = 'none';
      return;
    }
    this.target.style.display = 'block';
    this.target.replaceChildren(
      h('div', { class: 'nm', style: { color: t.color } }, t.corpse ? `${t.name}'s corpse` : t.name),
      h('div', { class: 'in' },
        t.sub ? h('div', { style: { textAlign: 'center', fontSize: '10px', color: '#a8997a' } }, t.sub) : null,
        t.corpse || t.kind === 'npc' ? null : h('div', { class: 'bar hp' }, h('i', { style: { width: `${Math.round(t.hpPct)}%` } }), h('span', {}, `${Math.round(t.hpPct)}%`)),
        t.level ? h('div', { style: { textAlign: 'center', fontSize: '10px', color: '#a8997a', marginTop: '2px' } }, `Level ${t.level}`) : null));
  }

  // ---------------------------------------------------------------- hotbar

  /** The hands: item ids held (null = fist). */
  setHands(left: string | null, right: string | null) {
    this.renderHotbar({ left, right });
  }

  /** Who draws the Q E F Z X slots (skills-ui.ts). */
  setSkillSlots(fn: ((key: string) => HTMLElement) | null) {
    this.skillSlots = fn;
    this.refreshHotbar();
  }

  refreshHotbar() {
    this.renderHotbar(this.hands);
  }

  private renderHotbar(hands: { left: string | null; right: string | null }) {
    this.hands = hands;
    this.hideTip();
    const hand = (key: string, id: string | null, slot: string, label: string) => {
      const icon = id ? iconUrl(id) : null;
      const el = h('div', { class: 's hov', 'data-hot': slot },
        icon ? h('img', { src: icon, alt: '' }) : h('div', { style: { fontSize: '20px' } }, '✊'),
        h('span', { class: 'k' }, key), h('div', { class: 'cd' }));
      this.tipFor(el, () => [id ? item(id)!.name : 'Fist', `${label}${id && item(id)?.hands === 2 ? ' (both hands)' : ''}`, ...(id ? describe(id) : ['DMG: 3   DLY: 9'])]);
      return el;
    };
    const twoHanded = item(hands.right)?.hands === 2;
    const specials = SPECIAL_KEYS.map((k) => {
      if (this.skillSlots) return this.skillSlots(k);
      const el = h('div', { class: 's off', 'data-hot': k }, h('span', { class: 'lk' }, '🔒'), h('span', { class: 'k' }, k));
      this.tipFor(el, () => ['Special attack', 'Earned through the skill tree as you level up.']);
      return el;
    });
    this.hotbar.replaceChildren(
      h('div', { class: 'slots' },
        hand('L', twoHanded ? hands.right : hands.left, 'left', twoHanded ? 'Left mouse: quick swing' : 'Left mouse: left hand'),
        hand('R', hands.right, 'right', twoHanded ? 'Right mouse: heavy swing' : 'Right mouse: right hand'),
        h('div', { class: 'sep' }),
        ...specials));
  }

  /** Shows a swing or cast cooling down on its slot ('left', 'right', or a spell's slug). */
  cooldown(slot: string, ms: number) {
    const cd = this.hotbar.querySelector(`[data-hot="${slot}"] .cd`) as HTMLElement | null;
    if (!cd || ms <= 0) return;
    const start = performance.now();
    const step = () => {
      const t = (performance.now() - start) / ms;
      if (t >= 1) {
        cd.style.background = '';
        return;
      }
      const deg = Math.round(t * 360);
      cd.style.background = `conic-gradient(transparent 0deg ${deg}deg, rgba(0,0,0,.62) ${deg}deg 360deg)`;
      requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
  }

  // ---------------------------------------------------------------- inventory

  setInventory(inv: Inventory) {
    this.inventory = inv;
    // Whatever was on the cursor has been put somewhere by the server.
    this.setHeld(null);
    if (this.inv.style.display === 'block') this.renderInventory();
    if (this.isMerchantOpen()) this.renderMerchant();
  }

  isInventoryOpen(): boolean {
    return this.inv.style.display === 'block';
  }

  toggleInventory(open?: boolean) {
    const show = open ?? this.inv.style.display !== 'block';
    this.inv.style.display = show ? 'block' : 'none';
    if (show) this.renderInventory();
    else this.setHeld(null);
    this.cb.windows(this.anyOpen());
  }

  private bySlot(): Map<string, InvItem> {
    return new Map(this.inventory.items.map((i) => [i.slot, i]));
  }

  private renderInventory() {
    this.hideTip();
    const slots = this.bySlot();
    const slotEl = (slot: string, label?: string) => {
      const it = slots.get(slot);
      const icon = it ? iconUrl(it.item_id) : null;
      const el = h('div', { class: 's drop' },
        icon ? h('img', { src: icon, alt: '' }) : null,
        it && it.quantity > 1 ? h('span', { class: 'q' }, String(it.quantity)) : null,
        !it && label ? h('span', { class: 'lb' }, label) : null);
      el.onclick = (e) => {
        e.stopPropagation();
        this.clickSlot(slot);
      };
      el.oncontextmenu = (e) => {
        e.preventDefault();
        if (this.held || !it) return;
        if (EQUIP_SLOTS.has(slot)) this.cb.unequip(slot);
        else if (this.isMerchantOpen()) this.sellFromBag(it);
        else if (item(it.item_id)?.slots.length) this.cb.equip(slot);
      };
      if (it) {
        const hint = () => {
          if (!slot.startsWith('bag')) return 'Right-click to unequip';
          if (this.isMerchantOpen()) {
            const offer = sellPrice(it.item_id) * it.quantity;
            return offer > 0 ? `Right-click to sell for ${money(offer)}` : `${this.merchant?.name || 'The merchant'} won't buy this`;
          }
          return item(it.item_id)?.slots.length ? 'Right-click to equip' : '';
        };
        this.tipFor(el, () => [item(it.item_id)?.name || it.item_id, ...describe(it.item_id), hint()]);
      }
      return el;
    };
    const eq = h('div', { class: 'eq' },
      ...HAND_SLOTS.map(([s, label]) => slotEl(s, label)),
      ...FUTURE_SLOTS.slice(0, 1).map((label) => this.futureSlot(label)),
      ...WORN_SLOTS.map(([s, label]) => slotEl(s, label)),
      ...FUTURE_SLOTS.slice(1).map((label) => this.futureSlot(label)));
    const bags = h('div', { class: 'bags' }, ...Array.from({ length: this.inventory.bag_slots || 24 }, (_, i) => slotEl(`bag${i}`)));
    let ac = 0;
    for (const sl of EQUIP_SLOTS) ac += item(slots.get(sl)?.item_id)?.ac || 0;
    const p = this.info;
    const stats = h('div', { class: 'stats' },
      h('div', {}, h('span', {}, 'Level'), h('span', {}, String(p?.level ?? 1))),
      h('div', {}, h('span', {}, 'HP'), h('span', {}, `${p?.hp ?? 0} / ${p?.maxHp ?? 0}`)),
      h('div', {}, h('span', {}, 'Mana'), h('span', {}, `${p?.mp ?? 0} / ${p?.maxMp ?? 0}`)),
      h('div', {}, h('span', {}, 'AC'), h('span', {}, String(ac))),
      h('div', {}, h('span', {}, 'Exp'), h('span', {}, p && p.xpNext ? `${p.xp} / ${p.xpNext}` : '-')),
      h('div', { class: 'coins' }, h('span', {}, 'Coin'), h('span', {}, money(this.inventory.coins))));
    const destroy = h('button', { class: 'btn', disabled: !this.held, title: 'Destroy the item on your cursor', onclick: () => this.destroyHeld() }, 'Destroy') as HTMLButtonElement;
    this.inv.replaceChildren(
      h('div', { class: 't' }, h('b', {}, 'Inventory'), h('span', { class: 'x', onclick: () => this.toggleInventory(false) }, '✕')),
      h('div', { class: 'body' }, eq, stats, bags),
      h('div', { class: 'foot' }, destroy, h('span', { style: { fontSize: '10px', color: '#8d7d5e', alignSelf: 'center' } }, 'Click to pick up · right-click to equip'), h('button', { class: 'btn', onclick: () => this.toggleInventory(false) }, 'Done')));
  }

  private futureSlot(label: string): HTMLElement {
    const el = h('div', { class: 's off' }, h('span', { class: 'lb' }, label));
    this.tipFor(el, () => [label, 'Armour for this comes later.']);
    return el;
  }

  private clickSlot(slot: string) {
    const here = this.bySlot().get(slot) || null;
    if (!this.held) {
      if (here) this.setHeld(here);
      return;
    }
    const from = this.held.slot;
    if (from === slot) {
      this.setHeld(null);
      return;
    }
    // Put down (or swap): the server checks the rules and sends the new inventory.
    this.cb.move(from, slot);
  }

  private setHeld(it: InvItem | null) {
    this.held = it;
    const icon = it ? iconUrl(it.item_id) : null;
    this.cursorEl.replaceChildren(...(icon ? [h('img', { src: icon, alt: '' })] : []));
    this.cursorEl.style.display = it ? 'block' : 'none';
    if (this.isInventoryOpen()) {
      const destroy = this.inv.querySelector('.foot .btn') as HTMLButtonElement | null;
      if (destroy) destroy.disabled = !it;
    }
  }

  private destroyHeld() {
    const it = this.held;
    if (!it) return;
    const name = item(it.item_id)?.name || 'this';
    if (!window.confirm(`Destroy ${name}? It will be gone for good.`)) return;
    this.cb.destroy(it.slot);
    this.setHeld(null);
  }

  // ---------------------------------------------------------------- loot

  openLoot(corpseName: string, items: LootItem[]) {
    this.loot.style.display = 'block';
    this.lootItems = items;
    this.renderLoot(corpseName);
    this.cb.windows(true);
  }

  updateLoot(items: LootItem[]) {
    this.lootItems = items;
    const name = this.loot.dataset.name || 'Corpse';
    this.renderLoot(name);
  }

  isLootOpen(): boolean {
    return this.loot.style.display === 'block';
  }

  closeLoot(notify = true) {
    if (!this.isLootOpen()) return;
    this.loot.style.display = 'none';
    this.hideTip();
    if (notify) this.cb.lootClose();
    this.cb.windows(this.anyOpen());
  }

  private renderLoot(name: string) {
    this.hideTip();
    this.loot.dataset.name = name;
    const cells = Array.from({ length: 10 }, (_, i) => {
      const it = this.lootItems[i];
      if (!it) return h('div', { class: 's' });
      const icon = iconUrl(it.item_id);
      const el = h('div', { class: 's hov' }, icon ? h('img', { src: icon, alt: '' }) : null, it.quantity > 1 ? h('span', { class: 'q' }, String(it.quantity)) : null);
      el.onclick = () => this.cb.lootTake(it.index);
      el.oncontextmenu = (e) => {
        e.preventDefault();
        this.cb.lootTake(it.index);
      };
      this.tipFor(el, () => [item(it.item_id)?.name || it.item_id, ...describe(it.item_id), 'Click to loot']);
      return el;
    });
    this.loot.replaceChildren(
      h('div', { class: 't' }, h('b', {}, name), h('span', { class: 'x', onclick: () => this.closeLoot() }, '✕')),
      this.lootItems.length ? h('div', { class: 'grid' }, ...cells) : h('div', { style: { padding: '14px 10px', color: '#8d7d5e', textAlign: 'center' } }, 'Nothing left.'),
      h('div', { class: 'foot' },
        h('button', { class: 'btn', disabled: !this.lootItems.length, onclick: () => this.cb.lootAll() }, 'Loot all'),
        h('button', { class: 'btn', onclick: () => this.closeLoot() }, 'Done')));
  }

  // ---------------------------------------------------------------- merchant

  /** Opens a merchant's window (and the inventory beside it, to sell from). */
  openMerchant(info: MerchantInfo, stock: StockItem[]) {
    this.merchant = info;
    this.stock = stock;
    this.stockSel = null;
    this.mer.style.display = 'block';
    this.renderMerchant();
    if (!this.isInventoryOpen()) this.toggleInventory(true);
    this.cb.windows(true);
  }

  isMerchantOpen(): boolean {
    return this.mer.style.display === 'block';
  }

  merchantId(): string | null {
    return this.isMerchantOpen() ? this.merchant?.id || null : null;
  }

  closeMerchant(notify = true) {
    if (!this.isMerchantOpen()) return;
    this.mer.style.display = 'none';
    this.merchant = null;
    this.hideTip();
    if (notify) this.cb.merchantClose();
    this.cb.windows(this.anyOpen());
  }

  /** Sells a stack from the bags (right-click with the merchant open). */
  private sellFromBag(it: InvItem) {
    if (sellPrice(it.item_id) * it.quantity <= 0) {
      this.announce(`${this.merchant?.name || 'The merchant'} isn't interested in that.`, 1800);
      return;
    }
    this.hideTip();
    this.cb.sell(it.slot);
  }

  private renderMerchant() {
    if (!this.merchant) return;
    this.hideTip();
    const m = this.merchant;
    // Re-rendering replaces the list: keep its scroll position (a click used to jump it to the top).
    const scroll = (this.mer.querySelector('.list') as HTMLElement | null)?.scrollTop || 0;
    const rows = this.stock.map((s) => {
      const it = item(s.item_id);
      const icon = iconUrl(s.item_id);
      const row = h('div', { class: 'row' + (this.stockSel === s.item_id ? ' sel' : '') },
        h('div', { class: 's' }, icon ? h('img', { src: icon, alt: '' }) : null),
        h('span', { class: 'nm' }, it?.name || s.item_id),
        h('span', { class: 'pr' }, money(s.price)));
      row.onclick = () => {
        if (this.stockSel === s.item_id) return;
        this.stockSel = s.item_id;
        this.renderMerchant();
      };
      row.oncontextmenu = (e) => {
        e.preventDefault();
        this.stockSel = s.item_id;
        this.cb.buy(s.item_id);
      };
      this.tipFor(row, () => [it?.name || s.item_id, ...describe(s.item_id), `Price: ${money(s.price)}`, 'Right-click to buy']);
      return row;
    });
    const sel = this.stockSel ? this.stock.find((x) => x.item_id === this.stockSel) : null;
    const afford = !!sel && sel.price <= (this.inventory.coins || 0);
    const buy = h('button', { class: 'btn', disabled: !afford, onclick: () => sel && this.cb.buy(sel.item_id) }, sel ? `Buy (${money(sel.price)})` : 'Buy') as HTMLButtonElement;
    const list = h('div', { class: 'list' }, ...rows);
    this.mer.replaceChildren(
      h('div', { class: 't' }, h('b', {}, m.name), h('span', {}, m.title || 'Merchant'), h('span', { class: 'x', onclick: () => this.closeMerchant() }, '✕')),
      list,
      h('div', { class: 'coins' }, `Your money: ${money(this.inventory.coins)}`),
      h('div', { class: 'sellbox' }, h('span', { class: 'msg2' }, 'Right-click to buy. To sell, right-click an item in your bags.')),
      h('div', { class: 'foot' }, buy, h('button', { class: 'btn', onclick: () => this.closeMerchant() }, 'Done')));
    list.scrollTop = scroll;
  }


  // ---------------------------------------------------------------- misc

  /** Closes the topmost window. False when none was open (Esc then opens the menu). */
  closeTop(): boolean {
    if (this.held) {
      this.setHeld(null);
      return true;
    }
    if (this.isLootOpen()) {
      this.closeLoot();
      return true;
    }
    if (this.isMerchantOpen()) {
      this.closeMerchant();
      return true;
    }
    if (this.isInventoryOpen()) {
      this.toggleInventory(false);
      return true;
    }
    return false;
  }

  anyOpen(): boolean {
    return this.isInventoryOpen() || this.isLootOpen() || this.isMerchantOpen();
  }

  /** A big centred message for a moment ("You have gained a level!"). */
  announce(text: string, ms = 2600) {
    this.msgEl.textContent = text;
    this.msgEl.style.opacity = '1';
    if (this.msgTimer) clearTimeout(this.msgTimer);
    this.msgTimer = setTimeout(() => (this.msgEl.style.opacity = '0'), ms);
  }

  private follow(e: MouseEvent) {
    if (this.held) {
      this.cursorEl.style.left = `${e.clientX}px`;
      this.cursorEl.style.top = `${e.clientY}px`;
    }
    if (this.tip.style.display === 'block') {
      const x = Math.min(window.innerWidth - 250, e.clientX + 16);
      const y = Math.min(window.innerHeight - 120, e.clientY + 14);
      this.tip.style.left = `${x}px`;
      this.tip.style.top = `${y}px`;
    }
  }

  private tipFor(el: HTMLElement, lines: () => string[]) {
    el.onmouseenter = (e: MouseEvent) => {
      if (this.held) return;
      const [title, ...rest] = lines().filter((l) => l !== '');
      this.tip.replaceChildren(h('b', {}, title), ...rest.map((l) => h('div', {}, l)));
      this.tip.style.display = 'block';
      this.follow(e);
    };
    el.onmouseleave = () => this.hideTip();
  }

  private hideTip() {
    this.tip.style.display = 'none';
  }
}

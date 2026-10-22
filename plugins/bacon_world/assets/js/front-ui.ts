// Bacon World's front end: the character select screen and the character creator, as an
// HTML layer over the 3D stage (character-stage.ts). Plain DOM with its own scoped CSS,
// so it doesn't depend on the site's Tailwind build.
import {
  Appearance, Body, BOTTOMS, CLOTH_COLORS, EYE_COLORS, HAIR_COLORS, HEIGHT_RANGE, SHAPES, SHOES, SKIN_TONES, TOPS,
  defaultAppearance, normalizeAppearance, randomAppearance, shade,
} from './appearance';
import type { StyleEntry } from './human-factory';

export interface FrontCharacter {
  id: string;
  name: string;
  character_type: string;
  model_path?: string;
  appearance?: unknown;
  zone?: string | null;
  /** Experience level (no classes: everyone grows through one shared skill tree). */
  level?: number;
}

export interface FrontCallbacks {
  select(id: string): void;
  play(id: string): void;
  remove(id: string): void;
  create(name: string, a: Appearance): Promise<{ ok: boolean; error?: string; character_id?: string }>;
  updateLook(id: string, a: Appearance): Promise<{ ok: boolean; error?: string }>;
  preview(a: Appearance | null): void;
  framing(f: 'full' | 'upper' | 'face'): void;
  insets(left: number, right: number, top?: number, bottom?: number): void;
  styles(body: Body): { hair: StyleEntry[]; facial: StyleEntry[] };
  iconUrl(entry: StyleEntry): string | null;
  back(): void;
}

type Tab = 'body' | 'face' | 'hair' | 'outfit';
const MAX_CHARACTERS = 16;

const CSS = `
.bwf{position:absolute;inset:0;pointer-events:none;color:#E7F1FD;font-family:"Segoe UI",ui-sans-serif,system-ui,-apple-system,Roboto,sans-serif;z-index:15;-webkit-font-smoothing:antialiased}
.bwf *{box-sizing:border-box}
.bwf button{font:inherit;color:inherit;cursor:pointer;border:0;background:none}
.bwf button:disabled{cursor:default;opacity:.45}
.bwf-panel{pointer-events:auto;background:linear-gradient(180deg,rgba(17,24,38,.86),rgba(10,14,22,.84));border:1px solid rgba(231,241,253,.09);border-radius:18px;box-shadow:0 24px 70px rgba(0,0,0,.5),inset 0 1px 0 rgba(255,255,255,.04);backdrop-filter:blur(14px) saturate(1.15);-webkit-backdrop-filter:blur(14px) saturate(1.15)}
.bwf-brand{position:absolute;top:18px;left:50%;transform:translateX(-50%);text-align:center;pointer-events:none;letter-spacing:.32em;font-size:12px;font-weight:700;color:rgba(231,241,253,.6)}
.bwf-brand b{display:block;letter-spacing:.18em;font-size:22px;color:#E7F1FD;font-weight:800;margin-top:2px}
.bwf-roster{position:absolute;left:20px;top:64px;bottom:20px;width:300px;display:flex;flex-direction:column;padding:16px}
.bwf-roster h3{margin:0 0 2px;font-size:13px;letter-spacing:.14em;text-transform:uppercase;color:rgba(231,241,253,.55);font-weight:700;display:flex;justify-content:space-between}
.bwf-list{flex:1;overflow:auto;margin:10px -6px;padding:0 6px;display:flex;flex-direction:column;gap:8px;scrollbar-width:thin}
.bwf .bwf-card{display:flex;align-items:center;gap:12px;padding:10px 12px;border-radius:12px;background:rgba(231,241,253,.04);border:1px solid transparent;text-align:left;transition:background .15s,border-color .15s,transform .15s}
.bwf .bwf-card:hover{background:rgba(231,241,253,.08)}
.bwf .bwf-card.on{background:rgba(36,125,241,.18);border-color:rgba(36,125,241,.75);box-shadow:0 0 0 1px rgba(36,125,241,.25),0 8px 24px rgba(36,125,241,.18)}
.bwf-av{width:40px;height:40px;border-radius:50%;flex:none;display:grid;place-items:center;font-weight:800;font-size:15px;color:#14100F;position:relative;box-shadow:inset 0 -3px 0 rgba(0,0,0,.18)}
.bwf-av i{position:absolute;right:-2px;bottom:-2px;width:16px;height:16px;border-radius:50%;border:2px solid #111826}
.bwf-cn{font-weight:700;font-size:15px;line-height:1.2;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.bwf-cs{font-size:12px;color:rgba(231,241,253,.55);margin-top:2px}
.bwf .bwf-new{display:flex;align-items:center;justify-content:center;gap:8px;padding:12px;border-radius:12px;border:1px dashed rgba(231,241,253,.25);font-weight:700;font-size:14px;transition:border-color .15s,background .15s}
.bwf .bwf-new:hover:not(:disabled){border-color:#247DF1;background:rgba(36,125,241,.1)}
.bwf-hero{position:absolute;left:50%;bottom:30px;transform:translateX(-50%);display:flex;flex-direction:column;align-items:center;gap:14px;pointer-events:none}
.bwf-shade{position:absolute;left:0;right:0;bottom:0;height:230px;background:linear-gradient(0deg,rgba(5,7,12,.85),rgba(5,7,12,0));pointer-events:none}
.bwf-hero-name{font-size:38px;font-weight:800;letter-spacing:.02em;text-shadow:0 4px 24px rgba(0,0,0,.6)}
.bwf-hero-sub{font-size:13px;letter-spacing:.2em;text-transform:uppercase;color:rgba(231,241,253,.6);margin-top:-10px}
.bwf-actions{display:flex;gap:10px;pointer-events:auto}
.bwf .bwf-btn{white-space:nowrap;padding:11px 18px;border-radius:12px;font-weight:700;font-size:14px;background:rgba(231,241,253,.08);border:1px solid rgba(231,241,253,.12)!important;transition:background .15s,transform .1s}
.bwf .bwf-btn:hover:not(:disabled){background:rgba(231,241,253,.14)}
.bwf .bwf-btn:active:not(:disabled){transform:translateY(1px)}
.bwf .bwf-primary{background:linear-gradient(180deg,#3B8BFF,#247DF1);border-color:rgba(255,255,255,.18)!important;box-shadow:0 10px 30px rgba(36,125,241,.35);padding:13px 30px;font-size:16px;letter-spacing:.04em}
.bwf .bwf-primary:hover:not(:disabled){background:linear-gradient(180deg,#4F98FF,#2F86F5)}
.bwf .bwf-danger:hover:not(:disabled){background:rgba(220,60,60,.25)}
.bwf-hint{position:absolute;right:24px;bottom:22px;font-size:12px;color:rgba(231,241,253,.4);pointer-events:none}
.bwf-empty{position:absolute;left:max(24px,6vw);top:50%;transform:translateY(-50%);width:min(420px,calc(100% - 32px));padding:32px}
.bwf-empty h2{margin:0 0 10px;font-size:30px;line-height:1.15}
.bwf-empty .k{font-size:12px;letter-spacing:.24em;text-transform:uppercase;color:#5FA2FF;font-weight:700;margin-bottom:10px}
.bwf-empty p{margin:0 0 22px;color:rgba(231,241,253,.65);line-height:1.5}
.bwf-creator{position:absolute;right:20px;top:20px;bottom:20px;width:400px;display:flex;flex-direction:column;overflow:hidden}
.bwf-ctop{padding:18px 20px 12px;display:flex;align-items:center;justify-content:space-between;gap:10px}
.bwf-ctop h2{margin:0;font-size:20px}
.bwf-seg{display:inline-flex;background:rgba(231,241,253,.06);border-radius:10px;padding:3px;gap:2px}
.bwf-seg button{padding:6px 12px;border-radius:8px;font-size:13px;font-weight:700;color:rgba(231,241,253,.7)}
.bwf-seg button.on{background:#247DF1;color:#fff}
.bwf-tabs{display:flex;gap:4px;padding:0 14px;border-bottom:1px solid rgba(231,241,253,.08)}
.bwf-tabs button{flex:1;padding:10px 4px 12px;font-size:13px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;color:rgba(231,241,253,.5);border-bottom:2px solid transparent!important}
.bwf-tabs button.on{color:#E7F1FD;border-bottom-color:#247DF1!important}
.bwf-tb{flex:1;overflow:auto;padding:16px 20px 20px;scrollbar-width:thin}
.bwf-sec{margin:4px 0 18px}
.bwf-sec h4{margin:0 0 10px;font-size:12px;letter-spacing:.14em;text-transform:uppercase;color:rgba(231,241,253,.5);display:flex;justify-content:space-between;align-items:center}
.bwf-sl{margin:0 0 14px}
.bwf-sl label{display:flex;justify-content:space-between;font-size:13px;font-weight:600;margin-bottom:6px}
.bwf-sl label span{color:rgba(231,241,253,.5);font-weight:500;font-variant-numeric:tabular-nums}
.bwf-sl input{width:100%;-webkit-appearance:none;appearance:none;height:6px;border-radius:6px;background:linear-gradient(90deg,#247DF1 var(--p),rgba(231,241,253,.12) var(--p));outline:none}
.bwf-sl input.bi{background:linear-gradient(90deg,rgba(231,241,253,.12) min(var(--p),50%),#247DF1 min(var(--p),50%),#247DF1 max(var(--p),50%),rgba(231,241,253,.12) max(var(--p),50%))}
.bwf-sl input::-webkit-slider-thumb{-webkit-appearance:none;width:18px;height:18px;border-radius:50%;background:#E7F1FD;box-shadow:0 2px 8px rgba(0,0,0,.4);cursor:pointer}
.bwf-sl input::-moz-range-thumb{width:18px;height:18px;border:0;border-radius:50%;background:#E7F1FD;cursor:pointer}
.bwf-ends{display:flex;justify-content:space-between;font-size:11px;color:rgba(231,241,253,.35);margin-top:4px}
.bwf-sw{display:flex;flex-wrap:wrap;gap:7px}
.bwf-sw button{width:28px;height:28px;border-radius:50%;box-shadow:inset 0 0 0 1px rgba(255,255,255,.15);transition:transform .1s}
.bwf-sw button:hover{transform:scale(1.1)}
.bwf-sw button.on{box-shadow:0 0 0 2px #111826,0 0 0 4px #E7F1FD}
.bwf-sw label{width:28px;height:28px;border-radius:50%;display:grid;place-items:center;cursor:pointer;background:conic-gradient(#f43,#fd3,#3d6,#3cf,#63f,#f3c,#f43);position:relative}
.bwf-sw label input{position:absolute;opacity:0;width:100%;height:100%;cursor:pointer}
.bwf-sw label::after{content:"+";font-weight:900;color:#14100F;text-shadow:0 0 3px #fff}
.bwf-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:8px}
.bwf-tile{aspect-ratio:1;border-radius:12px;background:rgba(231,241,253,.05);border:1px solid rgba(231,241,253,.06)!important;display:flex;flex-direction:column;align-items:center;justify-content:flex-end;padding:4px;overflow:hidden;position:relative;transition:background .15s}
.bwf-tile img{position:absolute;inset:4px 4px 16px;width:calc(100% - 8px);height:calc(100% - 20px);object-fit:contain;filter:drop-shadow(0 3px 6px rgba(0,0,0,.4))}
.bwf-tile span{position:relative;font-size:10px;line-height:1.1;color:rgba(231,241,253,.75);text-align:center;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:100%}
.bwf-tile:hover{background:rgba(231,241,253,.1)}
.bwf-tile.on{border-color:#247DF1!important;background:rgba(36,125,241,.18)}
.bwf-tile .none{position:absolute;inset:0;display:grid;place-items:center;font-size:22px;color:rgba(231,241,253,.3)}
.bwf-row{display:flex;gap:10px;align-items:center}
.bwf-cfoot{padding:14px 20px 18px;border-top:1px solid rgba(231,241,253,.08);display:flex;flex-direction:column;gap:10px;background:rgba(7,9,14,.35)}
.bwf-in{flex:1;min-width:0;padding:11px 12px;border-radius:10px;background:rgba(231,241,253,.06);border:1px solid rgba(231,241,253,.12);color:#E7F1FD;font:inherit;font-size:14px;outline:none}
.bwf-in:focus{border-color:#247DF1;box-shadow:0 0 0 3px rgba(36,125,241,.2)}
select.bwf-in{flex:0 0 140px;appearance:auto}
select.bwf-in option{background:#111826}
.bwf-err{font-size:12px;color:#FF9B9B;min-height:16px}
.bwf-modal{position:absolute;inset:0;background:rgba(5,7,12,.6);display:grid;place-items:center;pointer-events:auto;z-index:5}
.bwf-modal .bwf-panel{width:min(380px,calc(100% - 32px));padding:24px}
.bwf-modal h3{margin:0 0 8px;font-size:19px}
.bwf-modal p{margin:0 0 20px;color:rgba(231,241,253,.7);line-height:1.5}
.bwf-load{position:absolute;inset:0;display:grid;place-items:center;pointer-events:none}
.bwf-load div{display:flex;flex-direction:column;align-items:center;gap:14px;font-size:13px;letter-spacing:.2em;text-transform:uppercase;color:rgba(231,241,253,.7)}
.bwf-load i{width:42px;height:42px;border-radius:50%;border:3px solid rgba(231,241,253,.15);border-top-color:#247DF1;animation:bwfspin .8s linear infinite}
.bwf-veil{position:absolute;inset:0;background:radial-gradient(ellipse at center,rgba(20,41,74,.92),rgba(5,7,12,.98));pointer-events:auto;z-index:6}
@keyframes bwfspin{to{transform:rotate(360deg)}}
@media (max-width:760px){
 .bwf-roster{left:10px;right:10px;top:auto;bottom:10px;width:auto;max-height:38vh}
 .bwf-hero{bottom:auto;top:56px}
 .bwf-hero-name{font-size:24px}
 .bwf-hint{display:none}
 .bwf-creator{left:8px;right:8px;top:auto;bottom:8px;width:auto;height:58vh}
 .bwf-grid{grid-template-columns:repeat(5,1fr)}
 .bwf-brand{display:none}
}
`;

function h<K extends keyof HTMLElementTagNameMap>(tag: K, attrs: Record<string, any> = {}, ...kids: Array<Node | string | null | false | undefined>): HTMLElementTagNameMap[K] {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (v == null || v === false) continue;
    if (k === 'class') el.className = v;
    else if (k === 'style' && typeof v === 'object') Object.assign(el.style, v);
    else if (k.startsWith('on') && typeof v === 'function') (el as any)[k.toLowerCase()] = v;
    else if (k === 'text') el.textContent = v;
    else el.setAttribute(k, v === true ? '' : String(v));
  }
  for (const kid of kids) if (kid != null && kid !== false) el.append(kid as any);
  return el;
}

const initials = (name: string) => name.trim().split(/\s+/).map((w) => w[0]).join('').slice(0, 2).toUpperCase() || '?';

export class FrontUI {
  private root: HTMLDivElement;
  private mode: 'hidden' | 'select' | 'creator' = 'hidden';
  private characters: FrontCharacter[] = [];
  private selectedId: string | null = null;
  private draft: Appearance = defaultAppearance('male');
  private draftName = '';
  private editingId: string | null = null;
  private tab: Tab = 'body';
  private busy = false;
  private error = '';
  private loadingEl: HTMLDivElement | null = null;
  private veil: HTMLDivElement | null = null;
  private pendingSelectName: string | null = null;
  private creatorScroll = 0;

  constructor(private host: HTMLElement, private cb: FrontCallbacks) {
    if (!document.getElementById('bwf-css')) {
      document.head.append(h('style', { id: 'bwf-css' }, CSS));
    }
    this.root = h('div', { class: 'bwf' });
    // keys typed into the UI never reach the game
    for (const ev of ['keydown', 'keyup', 'keypress']) this.root.addEventListener(ev, (e) => e.stopPropagation());
    host.appendChild(this.root);
    window.addEventListener('resize', () => this.reportInsets());
  }

  get current() {
    return this.mode;
  }

  // ---------------------------------------------------------------- state from the server

  setCharacters(list: FrontCharacter[], selectedId: string | null) {
    this.characters = list || [];
    if (this.pendingSelectName) {
      const match = [...this.characters].reverse().find((c) => c.name === this.pendingSelectName);
      if (match) {
        this.pendingSelectName = null;
        this.selectedId = match.id;
        this.cb.select(match.id);
      }
    } else if (selectedId && this.characters.some((c) => c.id === selectedId)) {
      this.selectedId = selectedId;
    }
    if (this.selectedId && !this.characters.some((c) => c.id === this.selectedId)) this.selectedId = null;
    if (!this.selectedId && this.characters.length) {
      this.selectedId = this.characters[this.characters.length - 1].id;
      this.cb.select(this.selectedId);
    }
    if (this.mode === 'select') this.renderSelect();
  }

  showSelect() {
    this.mode = 'select';
    this.editingId = null;
    this.renderSelect();
  }

  hide() {
    this.mode = 'hidden';
    this.root.replaceChildren();
    this.loadingEl = null;
    this.cb.insets(0, 0);
  }

  setLoading(on: boolean) {
    if (on && !this.loadingEl) {
      this.loadingEl = h('div', { class: 'bwf-load' }, h('div', {}, h('i'), 'Loading'));
      this.root.append(this.loadingEl);
    } else if (!on && this.loadingEl) {
      this.loadingEl.remove();
      this.loadingEl = null;
    }
  }

  /** Full-screen cover while the world loads after "Enter world". */
  setEntering(on: boolean, label = 'Entering Bacon World') {
    if (on && !this.veil) {
      this.veil = h('div', { class: 'bwf-veil' }, h('div', { class: 'bwf-load' }, h('div', {}, h('i'), label)));
      this.host.appendChild(this.veil);
    } else if (!on && this.veil) {
      const v = this.veil;
      this.veil = null;
      v.style.transition = 'opacity .5s';
      v.style.opacity = '0';
      setTimeout(() => v.remove(), 520);
    }
  }

  private selected(): FrontCharacter | null {
    return this.characters.find((c) => c.id === this.selectedId) || null;
  }

  private appearanceOf(c: FrontCharacter): Appearance {
    return normalizeAppearance(c.appearance, /female/i.test(c.model_path || '') ? 'female' : 'male');
  }

  private reportInsets() {
    const w = this.host.clientWidth;
    const h = this.host.clientHeight;
    const narrow = w <= 760;
    if (this.mode === 'select') {
      if (!narrow) this.cb.insets(this.characters.length ? 320 : Math.min(520, w * 0.42), 0, 0, 0);
      else this.cb.insets(0, 0, this.characters.length ? 190 : 0, this.characters.length ? Math.min(h * 0.38, 90 + 70 * this.characters.length) : h * 0.45);
    } else if (this.mode === 'creator') {
      if (!narrow) this.cb.insets(0, 420, 0, 0);
      else this.cb.insets(0, 0, 0, h * 0.58 + 8);
    } else this.cb.insets(0, 0, 0, 0);
  }

  // ---------------------------------------------------------------- select screen

  private renderSelect() {
    this.root.replaceChildren();
    this.loadingEl = null;
    this.reportInsets();
    this.cb.framing('full');
    const sel = this.selected();
    this.root.append(h('div', { class: 'bwf-brand' }, 'BACON8', h('b', {}, 'BACON WORLD')));

    if (!this.characters.length) {
      this.cb.preview(null);
      this.root.append(
        h('div', { class: 'bwf-empty bwf-panel' },
          h('div', { class: 'k' }, 'Welcome'),
          h('h2', {}, 'Step into Bacon World'),
          h('p', {}, 'Make a character to explore the world, meet other players and chat. You can have up to 16.'),
          h('button', { class: 'bwf-btn bwf-primary', onclick: () => this.openCreator(null) }, 'Create your character'))
      );
      return;
    }

    const list = h('div', { class: 'bwf-list' });
    for (const c of this.characters) {
      const a = this.appearanceOf(c);
      const card = h('button', { class: 'bwf-card' + (c.id === this.selectedId ? ' on' : ''), title: c.name },
        h('div', { class: 'bwf-av', style: { background: a.skin } }, initials(c.name), h('i', { style: { background: a.outfit.top.main } })),
        h('div', { style: { minWidth: '0' } }, h('div', { class: 'bwf-cn' }, c.name), h('div', { class: 'bwf-cs' }, `Level ${c.level || 1} · ${a.body === 'female' ? 'Female' : 'Male'}`)));
      card.onclick = () => {
        if (this.selectedId === c.id) return;
        this.selectedId = c.id;
        this.cb.select(c.id);
        this.renderSelect();
      };
      card.ondblclick = () => this.cb.play(c.id);
      list.append(card);
    }
    const full = this.characters.length >= MAX_CHARACTERS;
    this.root.append(
      h('div', { class: 'bwf-roster bwf-panel' },
        h('h3', {}, 'Characters', h('span', {}, `${this.characters.length} / ${MAX_CHARACTERS}`)),
        list,
        h('button', { class: 'bwf-new', disabled: full, onclick: () => this.openCreator(null), title: full ? 'You have the maximum of 16 characters' : '' }, '+ New character'))
    );

    if (sel) {
      this.cb.preview(this.appearanceOf(sel));
      const shift = this.host.clientWidth > 760 ? 160 : 0;
      this.root.append(
        h('div', { class: 'bwf-shade' }),
        h('div', { class: 'bwf-hero', style: { left: `calc(50% + ${shift}px)` } },
          h('div', { class: 'bwf-hero-name' }, sel.name),
          h('div', { class: 'bwf-hero-sub' }, `Level ${sel.level || 1}`),
          h('div', { class: 'bwf-actions' },
            h('button', { class: 'bwf-btn', onclick: () => this.openCreator(sel) }, 'Edit look'),
            h('button', { class: 'bwf-btn bwf-primary', onclick: () => this.cb.play(sel.id) }, 'Enter world'),
            h('button', { class: 'bwf-btn bwf-danger', onclick: () => this.confirmDelete(sel) }, 'Delete'))),
        h('div', { class: 'bwf-hint' }, 'Drag to turn · Double-click a character to play')
      );
    }
  }

  private confirmDelete(c: FrontCharacter) {
    const modal = h('div', { class: 'bwf-modal' },
      h('div', { class: 'bwf-panel' },
        h('h3', {}, `Delete ${c.name}?`),
        h('p', {}, 'This removes the character for good. Their look and progress cannot be brought back.'),
        h('div', { class: 'bwf-row', style: { justifyContent: 'flex-end' } },
          h('button', { class: 'bwf-btn', onclick: () => modal.remove() }, 'Keep'),
          h('button', { class: 'bwf-btn bwf-danger', style: { background: 'rgba(220,60,60,.35)' }, onclick: () => { modal.remove(); this.cb.remove(c.id); } }, 'Delete'))));
    modal.onclick = (e) => { if (e.target === modal) modal.remove(); };
    this.root.append(modal);
  }

  // ---------------------------------------------------------------- creator

  openCreator(edit: FrontCharacter | null) {
    this.mode = 'creator';
    this.editingId = edit ? edit.id : null;
    this.error = '';
    this.tab = 'body';
    if (edit) {
      this.draft = this.appearanceOf(edit);
      this.draftName = edit.name;
    } else {
      const body: Body = Math.random() < 0.5 ? 'male' : 'female';
      this.draft = this.randomFor(body);
      this.draftName = '';
    }
    this.renderCreator();
  }

  private randomFor(body: Body): Appearance {
    const st = this.cb.styles(body);
    return randomAppearance(body, st.hair.map((s) => s.id), st.facial.map((s) => s.id), (Math.random() * 1e9) | 0);
  }

  private change(mut: (a: Appearance) => void, rerender = true) {
    const a: Appearance = JSON.parse(JSON.stringify(this.draft));
    mut(a);
    this.draft = normalizeAppearance(a, a.body);
    this.cb.preview(this.draft);
    if (rerender) this.renderCreator();
  }

  private renderCreator() {
    const prevBody = this.root.querySelector('.bwf-tb') as HTMLDivElement | null;
    if (prevBody) this.creatorScroll = prevBody.scrollTop;
    this.root.replaceChildren();
    this.loadingEl = null;
    this.reportInsets();
    this.cb.framing(this.tab === 'face' || this.tab === 'hair' ? 'face' : this.tab === 'outfit' ? 'full' : 'full');
    this.cb.preview(this.draft);
    const a = this.draft;
    const editing = !!this.editingId;

    const bodySeg = h('div', { class: 'bwf-seg' },
      ...(['male', 'female'] as Body[]).map((b) => h('button', {
        class: a.body === b ? 'on' : '',
        disabled: editing,
        title: editing ? 'The body type is fixed once a character exists' : '',
        onclick: () => { if (a.body !== b) { this.draft = this.carryOver(this.randomFor(b), a); this.renderCreator(); } },
      }, b === 'male' ? 'Male' : 'Female')));

    const tabs = h('div', { class: 'bwf-tabs' },
      ...(['body', 'face', 'hair', 'outfit'] as Tab[]).map((t) => h('button', { class: this.tab === t ? 'on' : '', onclick: () => { this.tab = t; this.creatorScroll = 0; this.renderCreator(); } }, t)));

    const tb = h('div', { class: 'bwf-tb' }, ...this.tabContent());

    const nameIn = h('input', { class: 'bwf-in', maxlength: '24', placeholder: 'Name', value: this.draftName, disabled: editing }) as HTMLInputElement;
    nameIn.oninput = () => { this.draftName = nameIn.value; this.error = ''; errEl.textContent = ''; createBtn.disabled = !this.canSubmit(); };
    nameIn.onkeydown = (e) => { if (e.key === 'Enter' && this.canSubmit()) void this.submit(); };
    const errEl = h('div', { class: 'bwf-err' }, this.error);
    const createBtn = h('button', { class: 'bwf-btn bwf-primary', style: { flex: '1', padding: '12px' }, disabled: !this.canSubmit(), onclick: () => void this.submit() },
      this.busy ? 'Saving…' : editing ? 'Save look' : 'Create character') as HTMLButtonElement;

    const panel = h('div', { class: 'bwf-creator bwf-panel' },
      h('div', { class: 'bwf-ctop' }, h('h2', {}, editing ? 'Edit look' : 'New character'), bodySeg),
      tabs,
      tb,
      h('div', { class: 'bwf-cfoot' },
        h('div', { class: 'bwf-row' }, nameIn),
        errEl,
        h('div', { class: 'bwf-row' },
          h('button', { class: 'bwf-btn', onclick: () => this.leaveCreator() }, 'Back'),
          h('button', { class: 'bwf-btn', title: 'Randomise the look', onclick: () => { this.draft = this.randomFor(a.body); this.renderCreator(); } }, '🎲'),
          createBtn)));
    this.root.append(panel, h('div', { class: 'bwf-hint', style: { left: '24px' } }, 'Drag to turn · Scroll to zoom'));
    tb.scrollTop = this.creatorScroll;
    if (!editing && !this.draftName) setTimeout(() => nameIn.focus({ preventScroll: true }), 0);
  }

  /** Keeps colours and outfit when switching body type. */
  private carryOver(fresh: Appearance, old: Appearance): Appearance {
    return normalizeAppearance({ ...fresh, skin: old.skin, eyes: old.eyes, outfit: old.outfit, hair: { ...fresh.hair, color: old.hair.color } }, fresh.body);
  }

  private canSubmit() {
    if (this.busy) return false;
    if (this.editingId) return true;
    const n = this.draftName.trim();
    return n.length >= 2 && n.length <= 24;
  }

  private async submit() {
    if (!this.canSubmit()) return;
    this.busy = true;
    this.renderCreator();
    try {
      if (this.editingId) {
        const res = await this.cb.updateLook(this.editingId, this.draft);
        if (!res.ok) throw new Error(res.error || 'Could not save the look.');
        const id = this.editingId;
        const c = this.characters.find((x) => x.id === id);
        if (c) c.appearance = this.draft;
        this.busy = false;
        this.showSelect();
      } else {
        const name = this.draftName.trim();
        const res = await this.cb.create(name, this.draft);
        if (!res.ok) throw new Error(res.error || 'Could not create the character.');
        this.pendingSelectName = name;
        if (res.character_id) {
          this.pendingSelectName = null;
          this.selectedId = res.character_id;
          this.cb.select(res.character_id);
        }
        this.busy = false;
        this.showSelect();
      }
    } catch (err: any) {
      this.busy = false;
      this.error = err?.message || 'Something went wrong.';
      this.renderCreator();
    }
  }

  private leaveCreator() {
    this.editingId = null;
    if (this.characters.length) this.showSelect();
    else {
      this.mode = 'select';
      this.renderSelect();
    }
    this.cb.back();
  }

  // ---------------------------------------------------------------- creator controls

  private tabContent(): Node[] {
    const a = this.draft;
    if (this.tab === 'body') {
      return [
        this.section('Body', this.slider('Height', a.height, HEIGHT_RANGE[0], HEIGHT_RANGE[1], (v) => this.change((x) => { x.height = v; }, false),
          (v) => `${Math.round((a.body === 'female' ? 170 : 180) * v)} cm`, ['Short', 'Tall']),
          ...SHAPES.filter((s) => s.tab === 'body' && (!s.bodies || s.bodies.includes(a.body)))
          .map((s) => this.slider(s.label, a.shape[s.key], s.min, s.max, (v) => this.change((x) => { x.shape[s.key] = v; }, false), undefined, s.ends))),
        this.section('Skin', this.swatches(SKIN_TONES, a.skin, (c) => this.change((x) => { x.skin = c; }))),
      ];
    }
    if (this.tab === 'face') {
      return [
        this.section('Face shape', ...SHAPES.filter((s) => s.tab === 'face')
          .map((s) => this.slider(s.label, a.shape[s.key], s.min, s.max, (v) => this.change((x) => { x.shape[s.key] = v; }, false), undefined, s.ends))),
        this.section('Eyes', this.swatches(EYE_COLORS, a.eyes, (c) => this.change((x) => { x.eyes = c; }))),
        this.section(h('span', {}, 'Eyebrows'),
          h('div', { class: 'bwf-seg', style: { marginBottom: '10px' } },
            h('button', { class: a.brows ? '' : 'on', onclick: () => this.change((x) => { x.brows = null; }) }, 'Match hair'),
            h('button', { class: a.brows ? 'on' : '', onclick: () => this.change((x) => { x.brows = shade(x.hair.color, 0.85); }) }, 'Custom')),
          a.brows ? this.swatches(HAIR_COLORS, a.brows, (c) => this.change((x) => { x.brows = c; })) : null),
      ];
    }
    if (this.tab === 'hair') {
      const st = this.cb.styles(a.body);
      const out: Node[] = [
        this.section('Hairstyle', this.tiles([{ id: 'none', label: 'Bald', file: '' }, ...st.hair], a.hair.style, (id) => this.change((x) => { x.hair.style = id; }))),
        this.section('Hair colour', this.swatches(HAIR_COLORS, a.hair.color, (c) => this.change((x) => { x.hair.color = c; if (x.facial.color === a.hair.color) x.facial.color = c; }))),
      ];
      if (a.body === 'male' && st.facial.length) {
        out.push(this.section('Facial hair', this.tiles([{ id: 'none', label: 'Clean', file: '' }, ...st.facial], a.facial.style, (id) => this.change((x) => { x.facial.style = id; }))));
        if (a.facial.style !== 'none') out.push(this.section('Beard colour', this.swatches(HAIR_COLORS, a.facial.color, (c) => this.change((x) => { x.facial.color = c; }))));
      }
      return out;
    }
    const o = a.outfit;
    return [
      this.section('Top', this.choice(TOPS, o.top.id, (id) => this.change((x) => { x.outfit.top.id = id; })),
        this.label('Colour'), this.swatches(CLOTH_COLORS, o.top.main, (c) => this.change((x) => { x.outfit.top.main = c; x.outfit.top.trim = shade(c, 0.78); })),
        this.label('Trim'), this.swatches(CLOTH_COLORS, o.top.trim, (c) => this.change((x) => { x.outfit.top.trim = c; }))),
      this.section('Bottoms', this.choice(BOTTOMS, o.bottom.id, (id) => this.change((x) => { x.outfit.bottom.id = id; })),
        this.label('Colour'), this.swatches(CLOTH_COLORS, o.bottom.main, (c) => this.change((x) => { x.outfit.bottom.main = c; x.outfit.bottom.trim = shade(c, 0.8); }))),
      this.section('Shoes', this.choice(SHOES, o.shoes.id, (id) => this.change((x) => {
        x.outfit.shoes.id = id;
        if (id === 'Shoes_Boots') Object.assign(x.outfit.shoes, { upper: '#6B4A2F', sole: '#2A2522', laces: '#3D2B1F' });
        else Object.assign(x.outfit.shoes, { upper: '#3A3F47', sole: '#F4F4F4', laces: '#E8E8E8' });
      })),
        this.label('Colour'), this.swatches(CLOTH_COLORS, o.shoes.upper, (c) => this.change((x) => { x.outfit.shoes.upper = c; })),
        this.label('Sole'), this.swatches(['#F4F4F4', '#E7F1FD', '#9AA3AD', '#3A3F47', '#2A2522', '#14100F', '#8A6A4A', '#C8352E'], o.shoes.sole, (c) => this.change((x) => { x.outfit.shoes.sole = c; }))),
    ];
  }

  private section(title: string | Node, ...kids: Array<Node | null>): HTMLElement {
    return h('div', { class: 'bwf-sec' }, h('h4', {}, title), ...kids);
  }

  private label(t: string) {
    return h('div', { style: { fontSize: '12px', color: 'rgba(231,241,253,.5)', margin: '12px 0 8px' } }, t);
  }

  private slider(label: string, value: number, min: number, max: number, set: (v: number) => void, fmt?: (v: number) => string, ends?: [string, string]): HTMLElement {
    const bi = min < 0;
    const val = h('span', {}, fmt ? fmt(value) : bi ? `${value > 0 ? '+' : ''}${Math.round(value * 100)}` : `${Math.round(((value - min) / (max - min)) * 100)}`);
    const input = h('input', { type: 'range', min: String(min), max: String(max), step: '0.01', value: String(value), class: bi ? 'bi' : '' }) as HTMLInputElement;
    const paint = (v: number) => input.style.setProperty('--p', `${((v - min) / (max - min)) * 100}%`);
    paint(value);
    input.oninput = () => {
      const v = Number(input.value);
      paint(v);
      val.textContent = fmt ? fmt(v) : bi ? `${v > 0 ? '+' : ''}${Math.round(v * 100)}` : `${Math.round(((v - min) / (max - min)) * 100)}`;
      set(v);
    };
    input.ondblclick = () => { const d = bi ? 0 : min === HEIGHT_RANGE[0] ? 1 : 0; input.value = String(d); input.oninput!(new Event('input')); };
    return h('div', { class: 'bwf-sl' }, h('label', {}, label, val), input, ends ? h('div', { class: 'bwf-ends' }, h('span', {}, ends[0]), h('span', {}, ends[1])) : null);
  }

  private swatches(colors: string[], current: string, set: (c: string) => void): HTMLElement {
    const cur = (current || '').toUpperCase();
    const custom = h('input', { type: 'color', value: cur || '#ffffff', title: 'Custom colour' }) as HTMLInputElement;
    custom.oninput = () => set(custom.value.toUpperCase());
    return h('div', { class: 'bwf-sw' },
      ...colors.map((c) => h('button', { class: c.toUpperCase() === cur ? 'on' : '', style: { background: c }, title: c, onclick: () => set(c) })),
      h('label', { title: 'Custom colour' }, custom));
  }

  private tiles(entries: StyleEntry[], current: string, set: (id: string) => void): HTMLElement {
    return h('div', { class: 'bwf-grid' }, ...entries.map((e) => {
      const url = e.id === 'none' ? null : this.cb.iconUrl(e);
      return h('button', { class: 'bwf-tile' + (e.id === current ? ' on' : ''), title: e.label, onclick: () => set(e.id) },
        url ? h('img', { src: url, alt: '', loading: 'lazy', draggable: 'false' }) : h('div', { class: 'none' }, '∅'),
        h('span', {}, e.label));
    }));
  }

  private choice(options: { id: string; label: string }[], current: string, set: (id: string) => void): HTMLElement {
    return h('div', { class: 'bwf-seg', style: { display: 'flex' } }, ...options.map((o) => h('button', { class: o.id === current ? 'on' : '', style: { flex: '1' }, onclick: () => set(o.id) }, o.label)));
  }

  dispose() {
    this.root.remove();
    this.veil?.remove();
  }
}

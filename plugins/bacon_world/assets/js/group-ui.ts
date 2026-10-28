// The group window and the invitation (2026-10-28; BaconWorld.Groups, group-world.ts): EverQuest's
// group window, up to 20 members. Each row: the leader's crown, the name, the level and a health bar
// (from the zone's presence; a member elsewhere shows "away"). Click a row to target that member.
// Leader tools on each row (lead, kick) and Invite / Leave / Disband underneath. In the game's
// window style (game-ui.ts' .bwg).
import { makeMovable } from './window-drag';

export interface GroupMember { id: string; name: string }
export interface GroupView { id: string; leader: string; members: GroupMember[] }
/** What the window knows of a member from the zone (absent: in another zone or loading). */
export interface MemberState { level?: number; hp?: number; max_hp?: number; dead?: boolean }

export interface GroupActions {
  target(id: string): void;
  invite(): void;
  leave(): void;
  disband(): void;
  kick(id: string): void;
  lead(id: string): void;
  accept(): void;
  decline(): void;
}

/** A chat line's group command, if it is one (pure; tested). `/g` and `/gsay` carry the text. */
export function parseGroupCommand(text: string): { cmd: 'invite' | 'say' | 'disband' | 'leave' | 'kick' | 'lead' | 'accept' | 'decline'; arg: string } | null {
  const m = /^\/(\w+)\b\s*(.*)$/s.exec(text.trim());
  if (!m) return null;
  const arg = m[2].trim();
  switch (m[1].toLowerCase()) {
    case 'invite':
    case 'inv':
      return { cmd: 'invite', arg };
    case 'g':
    case 'gsay':
    case 'group':
      return { cmd: 'say', arg };
    case 'disband':
      // EverQuest: /disband <name> removes them (the leader's), /disband alone leaves or ends it
      return arg ? { cmd: 'kick', arg } : { cmd: 'disband', arg };
    case 'gleave':
    case 'leavegroup':
      return { cmd: 'leave', arg };
    case 'kick':
      return { cmd: 'kick', arg };
    case 'makeleader':
    case 'leader':
      return { cmd: 'lead', arg };
    case 'accept':
    case 'follow':
      return { cmd: 'accept', arg };
    case 'decline':
      return { cmd: 'decline', arg };
    default:
      return null;
  }
}

/** A health bar's fill for a member (pure; tested): 0..100, or null when unknown. */
export function memberHpPct(s: MemberState | undefined): number | null {
  if (!s) return null;
  if (s.dead) return 0;
  if (!s.max_hp || s.hp == null) return null;
  return Math.max(0, Math.min(100, Math.round((s.hp / s.max_hp) * 100)));
}

const CSS = `
.bwg .grp{left:16px;top:200px;width:200px;display:none}
.bwg .grp .list{padding:4px 6px;display:flex;flex-direction:column;gap:3px;max-height:56vh;overflow-y:auto}
.bwg .grp .row{position:relative;padding:3px 5px;border:1px solid #3b3226;border-radius:2px;background:rgba(255,255,255,.02);cursor:pointer}
.bwg .grp .row:hover{border-color:#8a7449}
.bwg .grp .row.me{border-color:#5a4c33}
.bwg .grp .row.tg{border-color:#c9a65e;background:rgba(201,166,94,.12)}
.bwg .grp .nm{display:flex;align-items:center;gap:4px;font-size:11px;color:#e8dcc0;white-space:nowrap;overflow:hidden}
.bwg .grp .nm b{font-weight:600;overflow:hidden;text-overflow:ellipsis}
.bwg .grp .nm .lv{margin-left:auto;font-size:9px;color:#a8997a}
.bwg .grp .crown{color:#f0d77a;font-size:10px}
.bwg .grp .away{font-size:9px;color:#8a7f69;font-style:italic;margin-top:2px}
.bwg .grp .bar{height:8px;margin-top:2px}
.bwg .grp .tools{position:absolute;right:3px;top:2px;display:none;gap:2px}
.bwg .grp .row:hover .tools{display:flex}
.bwg .grp .tools button{font-size:9px;padding:0 4px}
.bwg .grp .ft{display:flex;gap:4px;padding:5px 6px 6px;border-top:1px solid #4b3f2b}
.bwg .grp .ft .btn{flex:1}
.bwg .ginv{left:50%;top:22%;transform:translateX(-50%);width:280px;display:none;text-align:center}
.bwg .ginv p{margin:10px 12px;font-size:12px;color:#e8dcc0;line-height:1.4}
.bwg .ginv p b{color:#f0d77a}
.bwg .ginv .ft{display:flex;gap:6px;justify-content:center;padding:0 10px 10px}
`;

function h(tag: string, attrs: Record<string, any> = {}, ...kids: Array<Node | string | null | undefined | false>): HTMLElement {
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

export class GroupWindow {
  private el: HTMLElement;
  private inv: HTMLElement;
  private style: HTMLStyleElement;
  private group: GroupView | null = null;
  private unmove: () => void;
  private unmoveInv: () => void;
  private inviteTimer: any = null;

  constructor(root: HTMLElement, private me: () => string | null, private stateOf: (id: string) => MemberState | undefined, private targetId: () => string | null, private act: GroupActions) {
    this.style = document.createElement('style');
    this.style.textContent = CSS;
    document.head.appendChild(this.style);
    this.el = h('div', { class: 'w grp' });
    this.inv = h('div', { class: 'w ginv' });
    root.append(this.el, this.inv);
    this.unmove = makeMovable(this.el, 'group');
    this.unmoveInv = makeMovable(this.inv, 'group_invite');
  }

  get view() {
    return this.group;
  }

  set(g: GroupView | null) {
    this.group = g;
    this.el.style.display = g ? 'block' : 'none';
    this.render();
  }

  /** Someone invites you: Accept / Decline (it lapses with the server's minute). */
  invite(fromName: string) {
    this.inv.replaceChildren(
      h('div', { class: 't' }, h('b', {}, 'Group invitation'), h('span', { class: 'x', onclick: () => this.answer(false) }, '✕')),
      h('p', {}, h('b', {}, fromName), ' invites you to join a group.'),
      h('div', { class: 'ft' }, h('button', { class: 'btn', onclick: () => this.answer(true) }, 'Accept'), h('button', { class: 'btn', onclick: () => this.answer(false) }, 'Decline'))
    );
    this.inv.style.display = 'block';
    clearTimeout(this.inviteTimer);
    this.inviteTimer = setTimeout(() => (this.inv.style.display = 'none'), 60_000);
  }

  get inviting() {
    return this.inv.style.display === 'block';
  }

  hideInvite() {
    clearTimeout(this.inviteTimer);
    this.inv.style.display = 'none';
  }

  private answer(yes: boolean) {
    this.hideInvite();
    if (yes) this.act.accept();
    else this.act.decline();
  }

  /** Health and levels changed (the zone's presence): redraw the bars. */
  refresh() {
    if (this.group) this.render();
  }

  dispose() {
    clearTimeout(this.inviteTimer);
    this.unmove();
    this.unmoveInv();
    this.el.remove();
    this.inv.remove();
    this.style.remove();
  }

  private render() {
    const g = this.group;
    if (!g) {
      this.el.replaceChildren();
      return;
    }
    const me = this.me();
    const lead = g.leader === me;
    const tg = this.targetId();
    const rows = g.members.map((m) => {
      const st = this.stateOf(m.id);
      const pct = memberHpPct(st);
      const tools = lead && m.id !== me
        ? h('div', { class: 'tools' },
            h('button', { class: 'btn', title: 'Make leader', onclick: (e: Event) => { e.stopPropagation(); this.act.lead(m.id); } }, '♛'),
            h('button', { class: 'btn', title: 'Remove from the group', onclick: (e: Event) => { e.stopPropagation(); this.act.kick(m.id); } }, '✕'))
        : null;
      return h('div', { class: 'row' + (m.id === me ? ' me' : '') + (m.id === tg ? ' tg' : ''), onclick: () => this.act.target(m.id), 'data-member': m.id },
        h('div', { class: 'nm' }, g.leader === m.id ? h('span', { class: 'crown', title: 'Group leader' }, '♛') : null, h('b', {}, m.name), st?.level ? h('span', { class: 'lv' }, `${st.level}`) : null),
        pct === null
          ? h('div', { class: 'away' }, st ? '' : 'away')
          : h('div', { class: 'bar hp' }, h('i', { style: { width: `${pct}%` } }), h('span', {}, st?.dead ? 'dead' : `${pct}%`)),
        tools);
    });
    this.el.replaceChildren(
      h('div', { class: 't' }, h('b', {}, `Group (${g.members.length}/20)`)),
      h('div', { class: 'list' }, ...rows),
      h('div', { class: 'ft' },
        lead ? h('button', { class: 'btn', title: 'Invite your target (or /invite Name)', onclick: () => this.act.invite() }, 'Invite') : null,
        h('button', { class: 'btn', onclick: () => this.act.leave() }, 'Leave'),
        lead ? h('button', { class: 'btn', onclick: () => this.act.disband() }, 'Disband') : null)
    );
  }
}

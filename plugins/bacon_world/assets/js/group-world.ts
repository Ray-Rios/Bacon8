// Groups (2026-10-28; BaconWorldWeb.GroupEvents, BaconWorld.Groups): the hook's half. The group
// window (group-ui.ts), the invitation, the chat commands (/invite, /g, /disband, /kick,
// /makeleader, /accept, /decline), and a groupmate's share of experience and coins. Mixed into the
// world hook like game-world.ts.
import { GroupWindow, parseGroupCommand, type GroupView, type MemberState } from './group-ui';
import { moneyWords } from './items';

const GROUP_COLOR = '#8FE3FF';

function reply(hook: any, event: string, payload: object, fallback: any = { ok: false, error: 'No answer from the server.' }): Promise<any> {
  return new Promise((resolve) => {
    const timer = setTimeout(() => resolve(fallback), 6000);
    try {
      hook.pushEvent(event, payload, (res: any) => {
        clearTimeout(timer);
        resolve(res ?? fallback);
      });
    } catch {
      clearTimeout(timer);
      resolve(fallback);
    }
  });
}

export const GroupWorld = {
  /** The server's group news (registered once, with the hook's other events). */
  initGroupEvents(this: any) {
    this.handleEvent('group_update', (p: any) => this.onGroupUpdate(p?.group || null));
    this.handleEvent('group_invite', (p: any) => {
      this.combatLog(`${p.from_name} invites you to join a group. (/accept or /decline)`, GROUP_COLOR);
      this.groupWindow?.invite(p.from_name);
      this.audio?.play('click', 0.6);
    });
    this.handleEvent('group_notice', (p: any) => this.combatLog(p.text, GROUP_COLOR));
    this.handleEvent('group_chat', (p: any) => {
      const mine = p.from === this.state?.currentPlayer?.character_id;
      this.combatLog(mine ? `You tell your party, '${p.text}'` : `${p.name} tells the group, '${p.text}'`, '#7FE0FF');
    });
    this.handleEvent('xp_gained', (p: any) => this.applyProgress?.(p));
    this.handleEvent('group_coins', (p: any) => {
      this.combatLog(`You receive ${moneyWords(p.coins)} as your split.`, '#F0D77A');
      this.audio?.play('coins', 0.6);
      if (this.inventory && p.total_coins != null) {
        this.inventory = { ...this.inventory, coins: p.total_coins };
        this.gameUI?.setInventory(this.inventory);
      }
    });
  },

  /** The window, once the game's layer is up. */
  initGroups(this: any) {
    if (this.groupWindow || !this.gameUI?.root) return;
    this.groupWindow = new GroupWindow(
      this.gameUI.root,
      () => this.state?.currentPlayer?.character_id || null,
      (id: string) => this.groupMemberState(id),
      () => this.targetId || null,
      {
        target: (id: string) => this.setTarget?.(id),
        invite: () => void this.groupInvite(''),
        leave: () => void this.groupAct('group_leave', {}),
        disband: () => void this.groupAct('group_disband', {}),
        kick: (id: string) => void this.groupAct('group_kick', { target: id }),
        lead: (id: string) => void this.groupAct('group_leader', { target: id }),
        accept: () => void this.groupAct('group_accept', {}),
        decline: () => void this.groupAct('group_decline', {}),
      }
    );
    void reply(this, 'group_fetch', {}).then((res: any) => res?.ok && this.onGroupUpdate(res.group || null));
  },

  disposeGroups(this: any) {
    this.groupWindow?.dispose();
    this.groupWindow = null;
    this.group = null;
  },

  onGroupUpdate(this: any, g: GroupView | null) {
    const had = !!this.group;
    this.group = g;
    this.groupWindow?.set(g);
    if (g) this.groupWindow?.hideInvite();
    if (had && !g) this.combatLog('You are no longer in a group.', GROUP_COLOR);
  },

  /** A member's level and health, from the zone's presence (you: your own). */
  groupMemberState(this: any, id: string): MemberState | undefined {
    const cp = this.state?.currentPlayer;
    if (cp && id === cp.character_id) return { level: this.progress?.level ?? cp.level, hp: cp.hp, max_hp: cp.max_hp, dead: !!this.isDead };
    const c = (this.state?.onlineCharacters || []).find((o: any) => o.character_id === id);
    return c ? { level: c.level, hp: c.hp, max_hp: c.max_hp, dead: !!c.dead } : undefined;
  },

  /** True when a character is in my group (nameplates, the target window). */
  inMyGroup(this: any, id: string): boolean {
    return !!this.group?.members?.some((m: any) => m.id === id);
  },

  /** A chat line that is a group command: handled here (returns true). */
  groupCommand(this: any, text: string): boolean {
    const c = parseGroupCommand(text);
    if (!c) return false;
    switch (c.cmd) {
      case 'invite':
        // EverQuest: /invite with an invitation waiting and no one named accepts it
        if (!c.arg && this.groupWindow?.inviting && !this.playerTargetId()) void this.groupAct('group_accept', {});
        else void this.groupInvite(c.arg);
        break;
      case 'say':
        if (!this.group) this.combatLog('You are not in a group.', '#B8B8B8');
        else if (c.arg) void this.groupAct('group_chat', { text: c.arg });
        break;
      case 'disband':
        void this.groupAct(this.group?.leader === this.state?.currentPlayer?.character_id ? 'group_disband' : 'group_leave', {});
        break;
      case 'leave':
        void this.groupAct('group_leave', {});
        break;
      case 'kick':
        void this.groupAct('group_kick', { target: c.arg || this.playerTargetId() || '' });
        break;
      case 'lead':
        void this.groupAct('group_leader', { target: c.arg || this.playerTargetId() || '' });
        break;
      case 'accept':
        void this.groupAct('group_accept', {});
        break;
      case 'decline':
        this.groupWindow?.hideInvite();
        void this.groupAct('group_decline', {});
        break;
    }
    return true;
  },

  /** The targeted player (not a creature or an NPC), if any. */
  playerTargetId(this: any): string | null {
    const id = this.targetId;
    if (!id || id === this.state?.currentPlayer?.character_id) return null;
    return (this.state?.onlineCharacters || []).some((c: any) => c.character_id === id) ? id : null;
  },

  async groupInvite(this: any, name: string) {
    const target = name || this.playerTargetId();
    if (!target) {
      this.combatLog('Target a player, or /invite Name.', '#B8B8B8');
      return;
    }
    const res = await reply(this, 'group_invite', { target });
    if (res.ok) this.combatLog(`You invite ${res.name} to join your group.`, GROUP_COLOR);
    else this.combatLog(res.error || "You can't invite them.", '#FF9B7A');
  },

  async groupAct(this: any, event: string, payload: object) {
    const res = await reply(this, event, payload);
    if (!res.ok && res.error) this.combatLog(res.error, '#FF9B7A');
    if (res.ok && res.group) this.onGroupUpdate(res.group);
    return res;
  },
};

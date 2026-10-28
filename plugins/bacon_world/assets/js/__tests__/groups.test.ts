// Groups (2026-10-28): the chat commands and the group window's health bars. Run with __tests__/run.sh.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { memberHpPct, parseGroupCommand } from '../group-ui';

test('group commands, EverQuest style', () => {
  assert.deepEqual(parseGroupCommand('/invite Tilda'), { cmd: 'invite', arg: 'Tilda' });
  assert.deepEqual(parseGroupCommand('/invite'), { cmd: 'invite', arg: '' });
  assert.deepEqual(parseGroupCommand('/g inc, two goblins'), { cmd: 'say', arg: 'inc, two goblins' });
  assert.deepEqual(parseGroupCommand('/gsay hi'), { cmd: 'say', arg: 'hi' });
  assert.deepEqual(parseGroupCommand('/disband'), { cmd: 'disband', arg: '' });
  // /disband Name removes them
  assert.deepEqual(parseGroupCommand('/disband Bob'), { cmd: 'kick', arg: 'Bob' });
  assert.deepEqual(parseGroupCommand('/makeleader Bob'), { cmd: 'lead', arg: 'Bob' });
  assert.deepEqual(parseGroupCommand('/follow'), { cmd: 'accept', arg: '' });
  assert.equal(parseGroupCommand('/mount'), null);
  assert.equal(parseGroupCommand('hello /g'), null);
  assert.equal(parseGroupCommand('/gnome'), null);
});

test('member health: a share of full, dead is empty, unknown is null', () => {
  assert.equal(memberHpPct({ hp: 50, max_hp: 200 }), 25);
  assert.equal(memberHpPct({ hp: 50, max_hp: 200, dead: true }), 0);
  assert.equal(memberHpPct({ level: 3 }), null);
  assert.equal(memberHpPct(undefined), null);
  assert.equal(memberHpPct({ hp: 300, max_hp: 200 }), 100);
});

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ChatHistory } from '../chat-history.ts';

test('empty history returns null on navigate', () => {
  const ch = new ChatHistory();
  assert.equal(ch.navigate(-1, 'draft'), null);
  assert.equal(ch.navigate(1, 'draft'), null);
});

test('push ignores empty or whitespace-only messages', () => {
  const ch = new ChatHistory();
  ch.push('');
  ch.push('   ');
  assert.equal(ch.entries.length, 0);
});

test('push avoids consecutive duplicates', () => {
  const ch = new ChatHistory();
  ch.push('hello');
  ch.push('hello');
  assert.equal(ch.entries.length, 1);
  ch.push('world');
  assert.equal(ch.entries.length, 2);
  ch.push('hello');
  assert.equal(ch.entries.length, 3);
});

test('history respects maxEntries limit', () => {
  const ch = new ChatHistory(3);
  ch.push('1');
  ch.push('2');
  ch.push('3');
  ch.push('4');
  assert.deepEqual(ch.entries, ['2', '3', '4']);
});

test('recalls older messages with Up (-1) and newer with Down (1)', () => {
  const ch = new ChatHistory();
  ch.push('/say first');
  ch.push('/g second');
  ch.push('third');

  // First press of Up saves the draft and shows most recent message ("third")
  assert.equal(ch.navigate(-1, 'my draft'), 'third');
  assert.equal(ch.currentIndex, 2);

  // Pressing Up again moves to "second"
  assert.equal(ch.navigate(-1, 'third'), '/g second');
  assert.equal(ch.currentIndex, 1);

  // Pressing Up again moves to "first"
  assert.equal(ch.navigate(-1, '/g second'), '/say first');
  assert.equal(ch.currentIndex, 0);

  // Pressing Up at the oldest stays at "first"
  assert.equal(ch.navigate(-1, '/say first'), '/say first');
  assert.equal(ch.currentIndex, 0);

  // Pressing Down moves forward to "second"
  assert.equal(ch.navigate(1, '/say first'), '/g second');
  assert.equal(ch.currentIndex, 1);

  // Pressing Down moves forward to "third"
  assert.equal(ch.navigate(1, '/g second'), 'third');
  assert.equal(ch.currentIndex, 2);

  // Pressing Down past the newest restores the draft!
  assert.equal(ch.navigate(1, 'third'), 'my draft');
  assert.equal(ch.currentIndex, -1);

  // Pressing Down when back at draft returns null
  assert.equal(ch.navigate(1, 'my draft'), null);
});

test('pushing a new message resets navigation state', () => {
  const ch = new ChatHistory();
  ch.push('msg1');
  ch.push('msg2');

  // Start navigating
  ch.navigate(-1, 'draft');
  assert.equal(ch.currentIndex, 1);

  // User sends a new message
  ch.push('msg3');
  assert.equal(ch.currentIndex, -1);
  assert.deepEqual(ch.entries, ['msg1', 'msg2', 'msg3']);
});

test('resetNavigation clears index and draft', () => {
  const ch = new ChatHistory();
  ch.push('msg1');
  ch.navigate(-1, 'some draft');
  assert.equal(ch.currentIndex, 0);

  ch.resetNavigation();
  assert.equal(ch.currentIndex, -1);
  assert.equal(ch.navigate(1, ''), null);
});

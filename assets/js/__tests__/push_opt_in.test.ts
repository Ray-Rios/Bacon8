// Push notifications (Bacon8.Push): the browser-side helpers of the PushOptIn hook.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { urlB64ToBytes, sameKey, deviceInfo } from '../push_opt_in';

const KEY = 'BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4';

test('a VAPID public key decodes to a 65-byte uncompressed point', () => {
  const b = new Uint8Array(urlB64ToBytes(KEY));
  assert.equal(b.length, 65);
  assert.equal(b[0], 4);
  assert.equal(new Uint8Array(urlB64ToBytes('BTBZMqHH6r4Tts7J_aSIgg')).length, 16);
});

test('a subscription made with another key is not ours; one that does not say is', () => {
  const k = urlB64ToBytes(KEY);
  assert.equal(sameKey(k.slice(0), k), true);
  const other = new Uint8Array(k.slice(0));
  other[10] ^= 1;
  assert.equal(sameKey(other.buffer, k), false);
  assert.equal(sameKey(null, k), true);
});

test('iPhones, iPads posing as Macs, and Home Screen apps are told apart', () => {
  const none = { matchMedia: () => ({ matches: false }) };
  const iphone = deviceInfo({ userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) Safari/604.1' }, none);
  assert.deepEqual(iphone, { supported: false, ios: true, standalone: false });

  const ipad = deviceInfo({ userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)', platform: 'MacIntel', maxTouchPoints: 5 }, none);
  assert.equal(ipad.ios, true);

  const app = { PushManager: 1, Notification: 1, matchMedia: () => ({ matches: true }) };
  const installed = deviceInfo({ userAgent: 'Mozilla/5.0 (iPhone)', serviceWorker: {} }, app);
  assert.deepEqual(installed, { supported: true, ios: true, standalone: true });

  const android = deviceInfo({ userAgent: 'Mozilla/5.0 (Linux; Android 15) Chrome/131.0', serviceWorker: {} }, { PushManager: 1, Notification: 1, matchMedia: () => ({ matches: false }) });
  assert.deepEqual(android, { supported: true, ios: false, standalone: false });
});

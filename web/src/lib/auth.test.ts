import { test } from 'node:test';
import assert from 'node:assert/strict';
import { MfaRequiredError, resetPassword, signIn, verifyEmailCode } from './auth';

class MemoryStorage {
  private values = new Map<string, string>();
  getItem(key: string) { return this.values.get(key) ?? null; }
  setItem(key: string, value: string) { this.values.set(key, value); }
  removeItem(key: string) { this.values.delete(key); }
}

test('signIn surfaces MFA challenge without creating a local session', async () => {
  globalThis.localStorage = new MemoryStorage() as Storage;
  globalThis.fetch = (async () => new Response(JSON.stringify({
    ok: true,
    mfa_required: true,
    mfa_challenge: 'challenge-token',
  }), { status: 200, headers: { 'Content-Type': 'application/json' } })) as typeof fetch;

  await assert.rejects(
    () => signIn('me@example.com', 'correct-password'),
    (err) => err instanceof MfaRequiredError && err.challenge === 'challenge-token'
  );
  assert.equal(globalThis.localStorage.getItem('capture.session'), null);
});

test('session-returning email code and reset flows surface MFA challenges', async () => {
  for (const fn of [
    () => verifyEmailCode('me@example.com', '123456'),
    () => resetPassword('me@example.com', '123456', 'new-password'),
  ]) {
    globalThis.localStorage = new MemoryStorage() as Storage;
    globalThis.fetch = (async () => new Response(JSON.stringify({
      ok: true,
      mfa_required: true,
      mfa_challenge: 'step-up-token',
    }), { status: 200, headers: { 'Content-Type': 'application/json' } })) as typeof fetch;

    await assert.rejects(
      fn,
      (err) => err instanceof MfaRequiredError && err.challenge === 'step-up-token'
    );
    assert.equal(globalThis.localStorage.getItem('capture.session'), null);
  }
});

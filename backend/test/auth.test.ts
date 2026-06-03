import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPair, SignJWT, jwtVerify, importJWK, type JWK } from 'jose';
import {
  hashToken,
  newOpaqueToken,
  loadSigningKey,
  hashPassword,
  verifyPassword,
  normalizeEmail,
  isValidEmail,
  isValidPassword,
} from '../src/auth.ts';

test('hashPassword + verifyPassword round-trips, and salts so two hashes differ', async () => {
  const h1 = await hashPassword('correct horse battery staple');
  const h2 = await hashPassword('correct horse battery staple');
  assert.notEqual(h1, h2); // unique salt per hash
  assert.ok(await verifyPassword('correct horse battery staple', h1));
  assert.ok(await verifyPassword('correct horse battery staple', h2));
});

test('verifyPassword rejects the wrong password', async () => {
  const hash = await hashPassword('s3cret-passw0rd');
  assert.equal(await verifyPassword('not-the-password', hash), false);
});

test('stored hash is scheme-tagged (self-describing for future migration) and never plaintext', async () => {
  const hash = await hashPassword('another-good-password');
  assert.ok(hash.startsWith('bcrypt-sha256$'));
  assert.ok(!hash.includes('another-good-password'));
});

test('verifyPassword rejects a hash with an unknown/forged scheme tag', async () => {
  assert.equal(await verifyPassword('whatever', 'plaintext-not-a-hash'), false);
});

test('passwords longer than bcrypt 72-byte limit are fully significant (sha256 pre-hash)', async () => {
  // Two 100-char passwords sharing the first 72 bytes must NOT verify against each other.
  const base = 'a'.repeat(72);
  const hash = await hashPassword(base + 'TAIL-ONE-distinct');
  assert.equal(await verifyPassword(base + 'TAIL-TWO-distinct', hash), false);
  assert.ok(await verifyPassword(base + 'TAIL-ONE-distinct', hash));
});

test('normalizeEmail lowercases and trims (server-authoritative canonical form)', () => {
  assert.equal(normalizeEmail('  Me@Example.COM '), 'me@example.com');
});

test('isValidEmail / isValidPassword enforce basic shape and length', () => {
  assert.ok(isValidEmail('me@example.com'));
  assert.equal(isValidEmail('not-an-email'), false);
  assert.equal(isValidEmail('a@b'), false);
  assert.ok(isValidPassword('12345678'));
  assert.equal(isValidPassword('1234567'), false); // < 8
  assert.equal(isValidPassword('x'.repeat(1025)), false); // > max
});

test('opaque session tokens are random and hash deterministically', () => {
  const a = newOpaqueToken();
  const b = newOpaqueToken();
  assert.notEqual(a, b);
  assert.equal(hashToken(a), hashToken(a));
  assert.notEqual(hashToken(a), hashToken(b));
  assert.notEqual(hashToken(a), a); // never store/expose the raw token
});

test('an opaque session token is NOT a verifiable PowerSync JWT', async () => {
  const { publicJwk } = await loadSigningKey();
  const key = await importJWK(publicJwk as JWK, 'RS256');
  await assert.rejects(() => jwtVerify(newOpaqueToken(), key));
});

test('PowerSync token verifies with the public JWKS and is rejected for the wrong aud', async () => {
  const { privateKey, publicJwk, kid } = await loadSigningKey();
  const token = await new SignJWT({})
    .setProtectedHeader({ alg: 'RS256', kid })
    .setSubject('user-xyz')
    .setIssuer('capture')
    .setAudience('powersync')
    .setIssuedAt()
    .setExpirationTime('5m')
    .sign(privateKey);
  const key = await importJWK(publicJwk as JWK, 'RS256');
  const { payload } = await jwtVerify(token, key, { audience: 'powersync', issuer: 'capture' });
  assert.equal(payload.sub, 'user-xyz');
  await assert.rejects(() => jwtVerify(token, key, { audience: 'capture-api' }));
});

test('public JWK exposes no private key material', async () => {
  const { publicJwk } = await loadSigningKey();
  for (const field of ['d', 'p', 'q', 'dp', 'dq', 'qi']) {
    assert.equal((publicJwk as Record<string, unknown>)[field], undefined);
  }
  assert.equal(publicJwk.kty, 'RSA');
  assert.ok(publicJwk.n && publicJwk.e);
});

// generateKeyPair import retained for parity with prior fixtures; ensures the test toolchain
// resolves jose the same way the app does.
void generateKeyPair;

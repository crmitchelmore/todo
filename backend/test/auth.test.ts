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
  newNumericCode,
  hashCode,
  hashRecoveryCode,
  newRecoveryCodes,
  newTotpSecret,
  totpUri,
  verifyTotpCode,
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

test('newNumericCode returns a fixed-length all-digit string, preserving leading zeros', () => {
  for (let i = 0; i < 500; i++) {
    const code = newNumericCode();
    assert.equal(code.length, 6, `expected 6 digits, got "${code}"`);
    assert.match(code, /^[0-9]{6}$/);
  }
  // custom length honoured
  assert.equal(newNumericCode(4).length, 4);
});

test('hashCode is deterministic, hex-encoded, and never echoes the raw code', () => {
  const a = hashCode('123456');
  const b = hashCode('123456');
  const c = hashCode('123457');
  assert.equal(a, b); // deterministic
  assert.notEqual(a, c); // different inputs differ
  assert.match(a, /^[0-9a-f]{64}$/); // sha256 hex
  assert.ok(!a.includes('123456')); // raw code not present
});

test('TOTP secrets are base32 and otpauth URIs do not include password material', () => {
  const secret = newTotpSecret();
  assert.match(secret, /^[A-Z2-7]+$/);
  const uri = totpUri(' Me@Example.COM ', secret);
  assert.ok(uri.startsWith('otpauth://totp/'));
  assert.ok(uri.includes(encodeURIComponent(secret)));
  assert.ok(uri.includes('issuer=Capture'));
  assert.ok(!uri.includes('password'));
});

test('verifyTotpCode accepts a current code and rejects malformed input', () => {
  const secret = 'JBSWY3DPEHPK3PXP';
  // Known code generated by the implementation for a fixed point in time.
  assert.equal(verifyTotpCode(secret, '324550', 1_700_000_000_000, 0), true);
  assert.equal(verifyTotpCode(secret, '324551', 1_700_000_000_000, 0), false);
  assert.equal(verifyTotpCode(secret, 'not-code', 1_700_000_000_000, 0), false);
});

test('recovery codes are one-time-display safe strings and hash without echoing raw code', () => {
  const codes = newRecoveryCodes();
  assert.equal(codes.length, 10);
  for (const code of codes) assert.match(code, /^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$/);
  const hash = hashRecoveryCode(codes[0]);
  assert.match(hash, /^[0-9a-f]{64}$/);
  assert.ok(!hash.includes(codes[0].replaceAll('-', '')));
});

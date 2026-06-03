import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { generateKeyPair, SignJWT, jwtVerify, importJWK, type JWK } from 'jose';
import {
  verifyAppleIdentityToken,
  hashToken,
  newOpaqueToken,
  loadSigningKey,
} from '../src/auth.ts';

// A stand-in for Apple: a local RSA key whose public half we hand to the verifier as the "JWKS".
const fakeApple = await generateKeyPair('RS256', { extractable: true });
const fakeAppleJwks = async () => fakeApple.publicKey;
const ISSUER = 'https://appleid.apple.com';
const AUD = ['dev.crmitchelmore.capture', 'dev.crmitchelmore.capture.web'];

function appleToken(opts: {
  sub?: string;
  aud?: string;
  email?: string;
  nonce?: string;
  expiresIn?: string;
  iat?: number;
}) {
  const claims = {
    ...(opts.email ? { email: opts.email } : {}),
    ...(opts.nonce ? { nonce: opts.nonce } : {}),
  };
  return new SignJWT(claims)
    .setProtectedHeader({ alg: 'RS256' })
    .setSubject(opts.sub ?? 'apple-user-1')
    .setIssuer(ISSUER)
    .setAudience(opts.aud ?? AUD[0])
    .setIssuedAt(opts.iat)
    .setExpirationTime(opts.expiresIn ?? '5m')
    .sign(fakeApple.privateKey);
}

test('accepts a valid Apple identity token and returns sub + email', async () => {
  const token = await appleToken({ sub: 'abc.123', email: 'me@example.com' });
  const claims = await verifyAppleIdentityToken(token, AUD, undefined, fakeAppleJwks);
  assert.equal(claims.sub, 'abc.123');
  assert.equal(claims.email, 'me@example.com');
});

test('rejects a token minted for a different audience', async () => {
  const token = await appleToken({ aud: 'some.other.app' });
  await assert.rejects(() => verifyAppleIdentityToken(token, AUD, undefined, fakeAppleJwks));
});

test('rejects an expired token', async () => {
  const token = await appleToken({ iat: Math.floor(Date.now() / 1000) - 3600, expiresIn: '-30m' });
  await assert.rejects(() => verifyAppleIdentityToken(token, AUD, undefined, fakeAppleJwks));
});

test('rejects a token too old even if not yet expired (maxTokenAge)', async () => {
  const token = await appleToken({ iat: Math.floor(Date.now() / 1000) - 3600, expiresIn: '10h' });
  await assert.rejects(() => verifyAppleIdentityToken(token, AUD, undefined, fakeAppleJwks));
});

test('verifies the nonce (sha256 of the raw nonce we sent)', async () => {
  const raw = 'random-nonce-value';
  const hashed = createHash('sha256').update(raw).digest('hex');
  const token = await appleToken({ nonce: hashed });
  const claims = await verifyAppleIdentityToken(token, AUD, raw, fakeAppleJwks);
  assert.equal(claims.sub, 'apple-user-1');
});

test('rejects a nonce mismatch (replay with a different nonce)', async () => {
  const token = await appleToken({ nonce: createHash('sha256').update('attacker').digest('hex') });
  await assert.rejects(() => verifyAppleIdentityToken(token, AUD, 'victim', fakeAppleJwks));
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

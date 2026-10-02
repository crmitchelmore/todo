import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash, generateKeyPairSync, randomBytes, sign } from 'node:crypto';
import {
  generateAuthenticationOptions,
  generateRegistrationOptions,
  verifyAuthenticationResponse,
  verifyRegistrationResponse,
} from '@simplewebauthn/server';
import { isoBase64URL, isoCBOR } from '@simplewebauthn/server/helpers';

/**
 * Round-trips a software ES256 passkey through the same @simplewebauthn/server calls the backend
 * makes (register options -> register verify -> login options -> login verify), so a library
 * upgrade that changes the registration/assertion contract or the stored credential shape
 * (credential id, COSE public key bytes, counter, transports) fails here rather than in production.
 */
const RP_ID = 'localhost';
const ORIGIN = 'http://localhost:3030';

const sha256 = (data: Uint8Array) => new Uint8Array(createHash('sha256').update(data).digest());
const concat = (...parts: Uint8Array[]) => {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let offset = 0;
  for (const p of parts) {
    out.set(p, offset);
    offset += p.length;
  }
  return out;
};
const u32 = (n: number) => new Uint8Array([(n >>> 24) & 0xff, (n >>> 16) & 0xff, (n >>> 8) & 0xff, n & 0xff]);

function softwareAuthenticator() {
  const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
  const jwk = publicKey.export({ format: 'jwk' });
  const credentialId = new Uint8Array(randomBytes(32));
  const cosePublicKey = isoCBOR.encode(
    new Map<number, number | Uint8Array>([
      [1, 2], // kty: EC2
      [3, -7], // alg: ES256
      [-1, 1], // crv: P-256
      [-2, isoBase64URL.toBuffer(jwk.x!)],
      [-3, isoBase64URL.toBuffer(jwk.y!)],
    ])
  );
  const rpIdHash = sha256(new TextEncoder().encode(RP_ID));
  const clientData = (type: string, challenge: string) =>
    new TextEncoder().encode(JSON.stringify({ type, challenge, origin: ORIGIN, crossOrigin: false }));

  return {
    id: isoBase64URL.fromBuffer(credentialId),
    register(challenge: string) {
      // flags: UP (0x01) | UV (0x04) | AT (0x40)
      const authData = concat(
        rpIdHash,
        new Uint8Array([0x45]),
        u32(0),
        new Uint8Array(16), // AAGUID
        new Uint8Array([credentialId.length >> 8, credentialId.length & 0xff]),
        credentialId,
        cosePublicKey
      );
      const attestationObject = isoCBOR.encode(
        new Map<string, unknown>([
          ['fmt', 'none'],
          ['attStmt', new Map()],
          ['authData', authData],
        ])
      );
      return {
        id: this.id,
        rawId: this.id,
        type: 'public-key' as const,
        clientExtensionResults: {},
        response: {
          clientDataJSON: isoBase64URL.fromBuffer(clientData('webauthn.create', challenge)),
          attestationObject: isoBase64URL.fromBuffer(attestationObject),
          transports: ['internal', 'hybrid'],
        },
      };
    },
    assert(challenge: string, signCount: number) {
      // flags: UP (0x01) | UV (0x04)
      const authData = concat(rpIdHash, new Uint8Array([0x05]), u32(signCount));
      const clientDataJSON = clientData('webauthn.get', challenge);
      const signature = sign('sha256', concat(authData, sha256(clientDataJSON)), privateKey);
      return {
        id: this.id,
        rawId: this.id,
        type: 'public-key' as const,
        clientExtensionResults: {},
        response: {
          clientDataJSON: isoBase64URL.fromBuffer(clientDataJSON),
          authenticatorData: isoBase64URL.fromBuffer(authData),
          signature: isoBase64URL.fromBuffer(new Uint8Array(signature)),
        },
      };
    },
  };
}

test('a software ES256 passkey registers and then signs in (stored credential shape round-trips)', async () => {
  const authenticator = softwareAuthenticator();

  const regOptions = await generateRegistrationOptions({
    rpName: 'Capture',
    rpID: RP_ID,
    userName: 'passkey@example.com',
    userDisplayName: 'passkey@example.com',
    userID: new Uint8Array(randomBytes(16)),
    attestationType: 'none',
    authenticatorSelection: { residentKey: 'preferred', userVerification: 'required' },
    excludeCredentials: [{ id: isoBase64URL.fromBuffer(new Uint8Array(randomBytes(32))), transports: ['internal'] }],
  });
  assert.ok(
    regOptions.pubKeyCredParams.some((p) => p.alg === -7),
    'ES256 stays an accepted registration algorithm'
  );

  const registration = await verifyRegistrationResponse({
    response: authenticator.register(regOptions.challenge),
    expectedOrigin: ORIGIN,
    expectedRPID: RP_ID,
    requireUserVerification: true,
    expectedChallenge: (c) => c === regOptions.challenge,
  });
  assert.equal(registration.verified, true);
  const { credential } = registration.registrationInfo!;
  assert.equal(credential.id, authenticator.id);
  assert.equal(credential.counter, 0);
  assert.deepEqual(credential.transports, ['internal', 'hybrid']);

  // What the backend persists (auth_webauthn_credentials) and later reads back.
  const stored = {
    credential_id: credential.id,
    public_key: Buffer.from(credential.publicKey),
    counter: String(credential.counter),
    transports: credential.transports ?? [],
  };

  const authOptions = await generateAuthenticationOptions({
    rpID: RP_ID,
    allowCredentials: [{ id: stored.credential_id, transports: stored.transports }],
    userVerification: 'required',
  });
  assert.equal(authOptions.allowCredentials?.[0]?.id, stored.credential_id);

  const authentication = await verifyAuthenticationResponse({
    response: authenticator.assert(authOptions.challenge, 1),
    expectedOrigin: ORIGIN,
    expectedRPID: RP_ID,
    requireUserVerification: true,
    expectedChallenge: (c) => c === authOptions.challenge,
    credential: {
      id: stored.credential_id,
      publicKey: new Uint8Array(stored.public_key),
      counter: Number(stored.counter),
      transports: stored.transports,
    },
  });
  assert.equal(authentication.verified, true);
  assert.equal(authentication.authenticationInfo.newCounter, 1);

  // A different challenge (replay with a stale assertion) must not verify.
  await assert.rejects(() =>
    verifyAuthenticationResponse({
      response: authenticator.assert('c3RhbGUtY2hhbGxlbmdl', 2),
      expectedOrigin: ORIGIN,
      expectedRPID: RP_ID,
      requireUserVerification: true,
      expectedChallenge: (c) => c === authOptions.challenge,
      credential: {
        id: stored.credential_id,
        publicKey: new Uint8Array(stored.public_key),
        counter: 1,
        transports: stored.transports,
      },
    })
  );
});

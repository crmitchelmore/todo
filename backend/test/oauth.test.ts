import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  githubAuthorizeUrl,
  githubOAuthConfig,
  oauthSessionFragment,
  primaryVerifiedGitHubEmail,
  signOAuthState,
  verifyOAuthState,
} from '../src/oauth.ts';

test('githubOAuthConfig is only configured when client id and secret are present', () => {
  assert.equal(githubOAuthConfig({ GITHUB_OAUTH_CLIENT_ID: 'id' }), null);
  assert.deepEqual(
    githubOAuthConfig({ GITHUB_OAUTH_CLIENT_ID: 'id', GITHUB_OAUTH_CLIENT_SECRET: 'secret' }),
    { clientId: 'id', clientSecret: 'secret', stateSecret: 'secret' }
  );
  assert.deepEqual(
    githubOAuthConfig({
      GITHUB_OAUTH_CLIENT_ID: 'id',
      GITHUB_OAUTH_CLIENT_SECRET: 'secret',
      OAUTH_STATE_SECRET: 'state',
    }),
    { clientId: 'id', clientSecret: 'secret', stateSecret: 'state' }
  );
});

test('OAuth state is signed, expiring, and tamper-resistant', () => {
  const state = signOAuthState({ nonce: 'nonce-123456', exp: 2_000 }, 'secret');
  assert.deepEqual(verifyOAuthState(state, 'secret', 1_000), { nonce: 'nonce-123456', exp: 2_000 });
  assert.equal(verifyOAuthState(`${state}x`, 'secret', 1_000), null);
  assert.equal(verifyOAuthState(state, 'wrong', 1_000), null);
  assert.equal(verifyOAuthState(state, 'secret', 3_000), null);
});

test('primaryVerifiedGitHubEmail prefers primary verified email only', () => {
  assert.equal(primaryVerifiedGitHubEmail('bad'), null);
  assert.equal(primaryVerifiedGitHubEmail([{ email: 'nope@example.com', primary: true, verified: false }]), null);
  assert.equal(primaryVerifiedGitHubEmail([
    { email: 'secondary@example.com', primary: false, verified: true },
    { email: 'me@example.com', primary: true, verified: true },
  ]), 'me@example.com');
});

test('githubAuthorizeUrl and oauthSessionFragment keep secrets out of query strings', () => {
  const auth = new URL(githubAuthorizeUrl({
    clientId: 'client-id',
    redirectUri: 'https://backend.example.com/api/auth/oauth/github/callback',
    state: 'state',
  }));
  assert.equal(auth.hostname, 'github.com');
  assert.equal(auth.searchParams.get('client_id'), 'client-id');
  assert.equal(auth.searchParams.get('scope'), 'read:user user:email');
  assert.equal(auth.searchParams.get('client_secret'), null);

  const callback = new URL(oauthSessionFragment({
    origin: 'https://web.example.com',
    sessionToken: 'session-token',
    userId: 'user-id',
  }));
  assert.equal(callback.search, '');
  assert.equal(callback.hash, '#capture_oauth=1&session_token=session-token&user_id=user-id');
});

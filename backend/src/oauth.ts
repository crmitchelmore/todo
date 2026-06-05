import { createHmac, randomBytes, timingSafeEqual } from 'crypto';

export interface OAuthStatePayload {
  nonce: string;
  exp: number;
}

export interface GitHubOAuthConfig {
  clientId: string;
  clientSecret: string;
  stateSecret: string;
}

export interface GitHubEmailRecord {
  email: string;
  primary: boolean;
  verified: boolean;
}

export function randomOAuthNonce(): string {
  return randomBytes(16).toString('base64url');
}

export function githubOAuthConfig(env: NodeJS.ProcessEnv = process.env): GitHubOAuthConfig | null {
  const clientId = env.GITHUB_OAUTH_CLIENT_ID?.trim();
  const clientSecret = env.GITHUB_OAUTH_CLIENT_SECRET?.trim();
  const stateSecret = (env.OAUTH_STATE_SECRET ?? env.GITHUB_OAUTH_CLIENT_SECRET)?.trim();
  if (!clientId || !clientSecret || !stateSecret) return null;
  return { clientId, clientSecret, stateSecret };
}

export function signOAuthState(payload: OAuthStatePayload, secret: string): string {
  const encoded = Buffer.from(JSON.stringify(payload)).toString('base64url');
  const sig = createHmac('sha256', secret).update(encoded).digest('base64url');
  return `${encoded}.${sig}`;
}

export function verifyOAuthState(state: string, secret: string, now = Date.now()): OAuthStatePayload | null {
  const [encoded, sig, extra] = state.split('.');
  if (!encoded || !sig || extra !== undefined) return null;
  const expected = createHmac('sha256', secret).update(encoded).digest('base64url');
  const a = Buffer.from(sig);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !timingSafeEqual(a, b)) return null;
  try {
    const parsed = JSON.parse(Buffer.from(encoded, 'base64url').toString('utf8')) as Partial<OAuthStatePayload>;
    if (typeof parsed.nonce !== 'string' || parsed.nonce.length < 8) return null;
    if (typeof parsed.exp !== 'number' || parsed.exp < now) return null;
    return { nonce: parsed.nonce, exp: parsed.exp };
  } catch {
    return null;
  }
}

export function githubAuthorizeUrl(params: {
  clientId: string;
  redirectUri: string;
  state: string;
}): string {
  const url = new URL('https://github.com/login/oauth/authorize');
  url.searchParams.set('client_id', params.clientId);
  url.searchParams.set('redirect_uri', params.redirectUri);
  url.searchParams.set('scope', 'read:user user:email');
  url.searchParams.set('state', params.state);
  return url.toString();
}

export function primaryVerifiedGitHubEmail(records: unknown): string | null {
  if (!Array.isArray(records)) return null;
  const candidates = records
    .filter((record): record is GitHubEmailRecord => (
      typeof record === 'object' &&
      record !== null &&
      typeof (record as GitHubEmailRecord).email === 'string' &&
      typeof (record as GitHubEmailRecord).primary === 'boolean' &&
      typeof (record as GitHubEmailRecord).verified === 'boolean'
    ));
  const primary = candidates.find((record) => record.primary && record.verified);
  return primary?.email ?? candidates.find((record) => record.verified)?.email ?? null;
}

export function oauthSessionFragment(params: { origin: string; sessionToken: string; userId: string }): string {
  const url = new URL(params.origin);
  const fragment = new URLSearchParams({
    capture_oauth: '1',
    session_token: params.sessionToken,
    user_id: params.userId,
  });
  url.hash = fragment.toString();
  return url.toString();
}

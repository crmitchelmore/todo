/**
 * Capture client configuration.
 *
 * Production endpoints are baked in so a built/shared web app needs no environment setup.
 * `VITE_BACKEND_URL` / `VITE_POWERSYNC_URL` override them (used in CI/preview), and local
 * dev (`vite dev`) falls back to the docker-compose stack on localhost.
 */
const PRODUCTION = {
  backendUrl: 'https://backend-production-de2f.up.railway.app',
  powersyncUrl: 'https://powersync-production-e560.up.railway.app',
} as const;

const LOCAL = {
  backendUrl: 'http://localhost:6060',
  powersyncUrl: 'http://localhost:8080',
} as const;

const env = import.meta.env ?? {};
const defaults = env.DEV ? LOCAL : PRODUCTION;
const backendUrl = env.VITE_BACKEND_URL ?? defaults.backendUrl;

export const config = {
  backendUrl,
  powersyncUrl: env.VITE_POWERSYNC_URL ?? defaults.powersyncUrl,
  githubOAuthProbeEnabled: env.VITE_GITHUB_OAUTH_PROBE === '1' || !/^http:\/\/(localhost|127\.0\.0\.1):/i.test(backendUrl),
} as const;

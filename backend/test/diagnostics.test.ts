import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const source = readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8');

test('sync diagnostics is authenticated and owner scoped', () => {
  const routeStart = source.indexOf("app.get('/api/diagnostics/sync', requireAuth");
  assert.notEqual(routeStart, -1);
  const nextRoute = source.indexOf('\napp.', routeStart + 1);
  const route = source.slice(routeStart, nextRoute);
  assert.match(route, /WHERE owner_id = \$1/);
  assert.match(route, /WHERE user_id = \$1/);
  assert.doesNotMatch(route, /session_token/);
  assert.doesNotMatch(route, /token_hash:/);
});

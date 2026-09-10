import test from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import { apiRateLimiter } from '../src/rateLimit.js';

test('API limiter rejects excess requests before the route runs', async () => {
  const app = express();
  let handled = 0;
  app.use('/api', apiRateLimiter(2));
  app.get('/api/probe', (_req, res) => { handled++; res.json({ ok: true }); });
  const server = app.listen(0, '127.0.0.1');
  await new Promise<void>((resolve) => server.once('listening', resolve));
  try {
    const address = server.address();
    assert.ok(address && typeof address === 'object');
    const url = `http://127.0.0.1:${address.port}/api/probe`;
    assert.equal((await fetch(url)).status, 200);
    assert.equal((await fetch(url)).status, 200);
    const limited = await fetch(url);
    assert.equal(limited.status, 429);
    assert.ok(limited.headers.get('retry-after'));
    assert.equal(handled, 2);
  } finally {
    server.closeAllConnections();
    await new Promise<void>((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
  }
});

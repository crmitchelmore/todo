import assert from 'node:assert/strict';
import test from 'node:test';

import {
  discoverTaskContext,
  discoveryQueryFor,
  locationContextFromEnv,
  shouldDiscoverTask,
} from './discovery.js';

test('detects tasks that need web or location discovery', () => {
  assert.equal(shouldDiscoverTask('Research the best small projector'), true);
  assert.equal(shouldDiscoverTask('Find a dentist near me'), true);
  assert.equal(shouldDiscoverTask('Take bins out'), false);
});

test('builds location context from bounded env coordinates', () => {
  const context = locationContextFromEnv({
    CAPTURE_LOCATION_LABEL: 'Leeds',
    CAPTURE_LOCATION_LATITUDE: '53.8008',
    CAPTURE_LOCATION_LONGITUDE: '-1.5491',
    CAPTURE_TIME_ZONE: 'Europe/London',
  });

  assert.deepEqual(context, {
    source: 'env',
    label: 'Leeds',
    latitude: 53.8008,
    longitude: -1.5491,
    timeZone: 'Europe/London',
  });
});

test('adds location to location-aware queries', () => {
  const query = discoveryQueryFor('Find a pharmacy near me', {
    source: 'env',
    label: 'Headingley',
    latitude: null,
    longitude: null,
    timeZone: 'Europe/London',
  });

  assert.equal(query, 'Find a pharmacy near me Headingley');
});

test('discovers web context through configured endpoint', async () => {
  const calls: string[] = [];
  const response = new Response(JSON.stringify({
    results: [
      { title: 'Top dentist', url: 'https://example.invalid/dentist', snippet: 'Open today' },
    ],
  }), { status: 200, headers: { 'content-type': 'application/json' } });

  const discovery = await discoverTaskContext(
    { id: 'task-1', ownerId: 'owner-1', title: 'Find a dentist near me' },
    {
      env: {
        CAPTURE_LOCATION_LABEL: 'Leeds',
        CAPTURE_WEB_SEARCH_ENDPOINT: 'https://search.example.invalid/api',
      },
      fetchImpl: async (input) => {
        calls.push(String(input));
        return response;
      },
    },
  );

  assert.ok(discovery);
  assert.equal(calls.length, 1);
  assert.match(calls[0], /q=Find\+a\+dentist\+near\+me\+Leeds/);
  assert.equal(discovery.web.source, 'configured_endpoint');
  assert.equal(discovery.web.results[0].title, 'Top dentist');
  assert.ok(discovery.nextActions.some((action) => action.includes('Use current location context')));
  assert.ok(discovery.confidence > 0.7);
});

test('falls back to a search action when web search is not configured', async () => {
  const discovery = await discoverTaskContext(
    { id: 'task-2', ownerId: 'owner-1', title: 'Compare project management tools' },
    { env: {} },
  );

  assert.ok(discovery);
  assert.equal(discovery.web.source, 'not_configured');
  assert.deepEqual(discovery.web.results, []);
  assert.ok(discovery.nextActions[0].includes('Run web search'));
});

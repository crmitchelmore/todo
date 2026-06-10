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

test('explicit handoff forces discovery for ordinary task titles', async () => {
  const discovery = await discoverTaskContext(
    { id: 'task-3', ownerId: 'owner-1', title: 'Prepare board deck' },
    { env: {}, force: true, instructions: 'find the latest metrics to include' },
  );

  assert.ok(discovery);
  assert.equal(discovery.query, 'Prepare board deck find the latest metrics to include');
  assert.equal(discovery.web.source, 'not_configured');
  assert.ok(discovery.nextActions[0].includes('Run web search'));
});

test('agent handoff discovery carries user memory context into shopping research', async () => {
  const discovery = await discoverTaskContext(
    { id: 'task-4', ownerId: 'owner-1', title: 'Need to buy a wok' },
    {
      env: {},
      force: true,
      instructions: 'research options',
      memories: [
        {
          content: 'Prefers buy-it-for-life kitchen tools around £80-£150, fast UK delivery, and avoids non-stick coatings.',
          domain: 'shopping',
          source: 'manual',
          confidence: 0.95,
          tags: ['shopping', 'kitchen'],
          expiresAt: null,
        },
      ],
    },
  );

  assert.ok(discovery);
  assert.match(discovery.query, /buy a wok/);
  assert.match(discovery.query, /£80-£150/);
  assert.equal(discovery.memories.length, 1);
  assert.ok(discovery.nextActions.some((action) => action.includes('Apply user context')));
});

test('agent handoff discovery generalises user memory context across task domains', async () => {
  const cases = [
    {
      title: 'Find childcare cover for next Thursday',
      memory: 'For childcare, prioritise school pickup reliability, safeguarding, and providers near the usual school route.',
      expected: /school pickup reliability/,
    },
    {
      title: 'Plan the half-term holiday',
      memory: 'Holiday planning should balance child-friendly activities, low travel friction, and refundable bookings.',
      expected: /refundable bookings/,
    },
    {
      title: 'Research observability options for the backend',
      memory: 'For work research, prefer production-stable tools with clear OpenTelemetry support and low operational overhead.',
      expected: /OpenTelemetry support/,
    },
    {
      title: 'Prepare implementation plan for sync migration',
      memory: 'Implementation tasks should include rollback, integration tests, and deployment verification before claiming done.',
      expected: /rollback/,
    },
    {
      title: 'Prepare interview loop for staff engineer candidate',
      memory: 'Interviewing should test judgement, collaboration, technical depth, and evidence from past delivery.',
      expected: /technical depth/,
    },
    {
      title: 'Urgently sort broken boiler',
      memory: 'Urgent home tasks should optimise for speed, safety, availability today, and clear call-out costs.',
      expected: /availability today/,
    },
    {
      title: 'Build long-term plan for garden renovation',
      memory: 'Long planning tasks should be broken into phases, budget ranges, dependencies, and decision checkpoints.',
      expected: /decision checkpoints/,
    },
  ];

  for (const item of cases) {
    const discovery = await discoverTaskContext(
      { id: `task-${item.title}`, ownerId: 'owner-1', title: item.title },
      {
        env: {},
        force: true,
        memories: [{
          content: item.memory,
          domain: 'test',
          source: 'manual',
          confidence: 0.9,
          tags: [],
          expiresAt: null,
        }],
      },
    );
    assert.ok(discovery, item.title);
    assert.match(discovery.query, item.expected, item.title);
    assert.ok(discovery.nextActions.some((action) => action.includes('Apply user context')), item.title);
  }
});

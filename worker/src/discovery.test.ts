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

test('fetches a pasted URL directly instead of requiring a search endpoint', async () => {
  const calls: string[] = [];
  const html = `<!doctype html><html><head>
    <title>Write Code, Not Specs</title>
    <meta name="description" content="Why executable code beats speculative specs.">
  </head><body>...</body></html>`;
  const response = new Response(html, { status: 200, headers: { 'content-type': 'text/html' } });

  const discovery = await discoverTaskContext(
    { id: 'task-url', ownerId: 'owner-1', title: 'https://softwaredoug.com/blog/2026/07/04/write-code-not-specs.html' },
    {
      env: {},
      force: true,
      instructions: 'Automatically research this newly captured item and identify the next useful action.',
      fetchImpl: async (input) => {
        calls.push(String(input));
        return response;
      },
    },
  );

  assert.ok(discovery);
  assert.equal(calls.length, 1);
  assert.equal(calls[0], 'https://softwaredoug.com/blog/2026/07/04/write-code-not-specs.html');
  assert.equal(discovery.web.source, 'direct_url');
  assert.equal(discovery.web.results[0].title, 'Write Code, Not Specs');
  assert.equal(discovery.web.results[0].snippet, 'Why executable code beats speculative specs.');
  assert.ok(discovery.nextActions.some((action) => action.includes('Review top result: Write Code, Not Specs')));
});

test('suggests opening the link directly when a pasted URL cannot be fetched', async () => {
  const discovery = await discoverTaskContext(
    { id: 'task-url-err', ownerId: 'owner-1', title: 'https://example.invalid/post' },
    {
      env: {},
      force: true,
      fetchImpl: async () => new Response('nope', { status: 503 }),
    },
  );

  assert.ok(discovery);
  assert.equal(discovery.web.source, 'error');
  assert.deepEqual(discovery.web.results, []);
  assert.ok(discovery.nextActions.some((action) => action.includes('Open the linked page directly: https://example.invalid/post')));
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

test('falls back to a manual search action when built-in search is disabled and unconfigured', async () => {
  const discovery = await discoverTaskContext(
    { id: 'task-2', ownerId: 'owner-1', title: 'Compare project management tools' },
    { env: { CAPTURE_WEB_SEARCH_DISABLE_BUILTIN: '1' } },
  );

  assert.ok(discovery);
  assert.equal(discovery.web.source, 'not_configured');
  assert.deepEqual(discovery.web.results, []);
  assert.ok(discovery.nextActions[0].includes('Run web search'));
});

test('uses built-in DuckDuckGo search when no endpoint is configured', async () => {
  const calls: string[] = [];
  const html = `
    <div class="result result--ad">
      <a class="result__a" rel="nofollow" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fduckduckgo.com%2Fy.js%3Fad_domain%3Dsponsor.example&rut=z">Sponsored: Buy PM Tools</a>
      <a class="result__snippet">A paid advert that should be filtered out.</a>
    </div>
    <div class="result results_links_deep web-result">
      <a class="result__a" rel="nofollow" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Ftools&rut=x">Best PM Tools 2026</a>
      <a class="result__snippet" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Ftools">A hands-on comparison of project management tools.</a>
    </div>
    <div class="result results_links_deep web-result">
      <a class="result__a" rel="nofollow" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.org%2Freview&rut=y">Second Result</a>
      <a class="result__snippet">Another useful overview.</a>
    </div>`;

  const discovery = await discoverTaskContext(
    { id: 'task-builtin', ownerId: 'owner-1', title: 'Compare project management tools' },
    {
      env: {},
      fetchImpl: async (input) => {
        calls.push(String(input));
        return new Response(html, { status: 200, headers: { 'content-type': 'text/html' } });
      },
    },
  );

  assert.ok(discovery);
  assert.equal(calls.length, 1);
  assert.ok(calls[0].startsWith('https://html.duckduckgo.com/html/?q='));
  assert.equal(discovery.web.source, 'builtin');
  assert.equal(discovery.web.results.length, 2);
  assert.ok(discovery.web.results.every((result) => !result.url?.includes('duckduckgo.com')));
  assert.equal(discovery.web.results[0].title, 'Best PM Tools 2026');
  assert.equal(discovery.web.results[0].url, 'https://example.com/tools');
  assert.equal(discovery.web.results[0].snippet, 'A hands-on comparison of project management tools.');
  assert.equal(discovery.web.results[1].url, 'https://example.org/review');
  assert.ok(discovery.nextActions.some((action) => action.includes('Review top result: Best PM Tools 2026')));
});

test('explicit handoff forces discovery for ordinary task titles', async () => {
  const discovery = await discoverTaskContext(
    { id: 'task-3', ownerId: 'owner-1', title: 'Prepare board deck' },
    { env: { CAPTURE_WEB_SEARCH_DISABLE_BUILTIN: '1' }, force: true, instructions: 'find the latest metrics to include' },
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
      env: { CAPTURE_WEB_SEARCH_DISABLE_BUILTIN: '1' },
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

test('memory-enhanced web discovery keeps outgoing search query bounded', async () => {
  const calls: string[] = [];
  const response = new Response(JSON.stringify({ results: [] }), {
    status: 200,
    headers: { 'content-type': 'application/json' },
  });

  const discovery = await discoverTaskContext(
    { id: 'task-long', ownerId: 'owner-1', title: 'Need to buy a wok' },
    {
      env: { CAPTURE_WEB_SEARCH_ENDPOINT: 'https://search.example.invalid/api' },
      force: true,
      memories: Array.from({ length: 12 }, (_, index) => ({
        content: `memory-${index} ` + 'x'.repeat(1000),
        domain: 'shopping',
        source: 'manual',
        confidence: 1,
        tags: [],
        expiresAt: null,
      })),
      fetchImpl: async (input) => {
        calls.push(String(input));
        return response;
      },
    },
  );

  assert.ok(discovery);
  assert.ok(discovery.query.length <= 500);
  assert.equal(new URL(calls[0]).searchParams.get('q')?.length, discovery.query.length);
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
        env: { CAPTURE_WEB_SEARCH_DISABLE_BUILTIN: '1' },
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

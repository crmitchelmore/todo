import assert from 'node:assert/strict';
import test from 'node:test';

import { parseResearchResponse, runAgentResearch } from './handoffResearch.js';

const discovery = {
  taskId: 'task-1',
  title: 'Need to buy a wok',
  query: 'Need to buy a wok buy-it-for-life £80-£150',
  location: { source: 'unavailable' as const, label: null, latitude: null, longitude: null, timeZone: 'Europe/London' },
  web: {
    source: 'configured_endpoint' as const,
    query: 'Need to buy a wok',
    results: [{ title: 'Carbon steel wok guide', url: 'https://example.invalid/wok', snippet: 'Carbon steel is durable.' }],
  },
  memories: [{
    content: 'Prefers buy-it-for-life kitchen tools around £80-£150, fast UK delivery, and avoids non-stick coatings.',
    domain: 'shopping',
    source: 'manual',
    confidence: 0.95,
    tags: ['shopping', 'kitchen'],
    expiresAt: null,
  }],
  nextActions: ['Review top result: Carbon steel wok guide'],
  confidence: 0.75,
};

test('runAgentResearch calls the configured LLM with task, prompt, memories, and web context', async () => {
  const calls: Array<{ input: string | URL; body: any }> = [];
  const response = new Response(JSON.stringify({
    choices: [{
      message: {
        content: JSON.stringify({
          summary: 'A carbon steel wok best fits the user preference for durable cookware.',
          recommendations: ['Prefer flat-bottom carbon steel for home hobs.', 'Avoid non-stick coatings.'],
          next_actions: ['Compare 14-inch flat-bottom options from UK retailers.'],
          confidence: 0.82,
        }),
      },
    }],
  }), { status: 200, headers: { 'content-type': 'application/json' } });

  const brief = await runAgentResearch(
    'Need to buy a wok',
    { requestId: '11111111-1111-5111-8111-111111111111', mode: 'research', instructions: 'find sensible options' },
    discovery,
    {
      env: { OPENAI_API_KEY: 'test-key', OPENAI_BASE_URL: 'https://llm.example.invalid/v1', HANDOFF_LLM_MODEL: 'test-model' },
      fetchImpl: async (input, init) => {
        calls.push({ input, body: JSON.parse(String(init?.body)) });
        return response;
      },
    }
  );

  assert.equal(String(calls[0].input), 'https://llm.example.invalid/v1/chat/completions');
  assert.equal(calls[0].body.model, 'test-model');
  const prompt = calls[0].body.messages[1].content;
  assert.match(prompt, /Need to buy a wok/);
  assert.match(prompt, /buy-it-for-life/);
  assert.match(prompt, /Carbon steel wok guide/);
  assert.equal(brief.source, 'llm');
  assert.match(brief.body, /carbon steel wok/i);
  assert.deepEqual(brief.nextActions, ['Compare 14-inch flat-bottom options from UK retailers.']);
  assert.equal(brief.confidence, 0.82);
});

test('runAgentResearch can use Codex subscription JSONL with GPT-5.6 Sol', async () => {
  const calls: Array<{ file: string; args: readonly string[]; cwd: string; timeout: number }> = [];
  const brief = await runAgentResearch(
    'Need to buy a wok',
    { requestId: '11111111-1111-5111-8111-111111111111', mode: 'research', instructions: 'find sensible options' },
    discovery,
    {
      env: {
        RESEARCH_LLM_PROVIDER: 'codex',
        RESEARCH_LLM_MODEL: 'gpt-5.6-sol',
        CODEX_RESEARCH_COMMAND: 'codex',
        CODEX_RESEARCH_WORKDIR: '/Users/cm/work/todo',
        CODEX_RESEARCH_TIMEOUT_SECONDS: '240',
      },
      execImpl: async (file, args, options) => {
        calls.push({ file, args, cwd: options.cwd, timeout: options.timeout });
        return {
          stdout: [
            JSON.stringify({ type: 'thread.started', thread_id: 'thread-1' }),
            JSON.stringify({ type: 'item.completed', item: { type: 'error', message: 'unstable feature warning' } }),
            JSON.stringify({
              type: 'item.completed',
              item: {
                type: 'agent_message',
                text: JSON.stringify({
                  summary: 'A flat-bottom carbon steel wok is the strongest fit.',
                  recommendations: ['Avoid non-stick coatings.', 'Check handle shape for the hob.'],
                  next_actions: ['Shortlist UK carbon steel options.'],
                  confidence: 0.87,
                }),
              },
            }),
            JSON.stringify({ type: 'turn.completed', usage: { input_tokens: 100, output_tokens: 20 } }),
          ].join('\n'),
          stderr: '',
        };
      },
      now: new Date('2026-07-11T07:00:00Z'),
    }
  );

  assert.equal(calls[0].file, 'codex');
  assert.deepEqual(calls[0].args.slice(0, 6), ['exec', '--json', '--sandbox', 'read-only', '--model', 'gpt-5.6-sol']);
  assert.equal(calls[0].cwd, '/Users/cm/work/todo');
  assert.equal(calls[0].timeout, 240_000);
  assert.equal(brief.model, 'gpt-5.6-sol');
  assert.match(brief.body, /carbon steel wok/i);
  assert.deepEqual(brief.nextActions, ['Shortlist UK carbon steel options.']);
  assert.equal(brief.confidence, 0.87);
});

test('runAgentResearch fails loudly when LLM credentials are missing', async () => {
  await assert.rejects(
    () => runAgentResearch(
      'Need to buy a wok',
      { requestId: '11111111-1111-5111-8111-111111111111', mode: 'research', instructions: null },
      discovery,
      { env: {} }
    ),
    /OPENAI_API_KEY is missing/
  );
});

test('parseResearchResponse rejects template-shaped or invalid LLM output', () => {
  assert.throws(() => parseResearchResponse('not json'), /invalid JSON/);
  assert.throws(() => parseResearchResponse(JSON.stringify({ recommendations: [] })), /missing summary/);
});

test('parseResearchResponse keeps body inside agent proposal limits', () => {
  const brief = parseResearchResponse(JSON.stringify({
    summary: 'A'.repeat(2100),
    recommendations: ['B'.repeat(500)],
    next_actions: ['C'.repeat(500)],
    confidence: 0.9,
  }), 'gpt-5.6-sol');
  assert.equal(brief.body.length, 2000);
});

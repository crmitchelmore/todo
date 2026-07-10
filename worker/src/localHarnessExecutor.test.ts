import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildHarnessPrompt,
  buildLocalHarnessArgs,
  localHarnessConfigFromEnv,
  runLocalHarnessAttempt,
  type LocalHarnessConfig,
} from './localHarnessExecutor.js';

const baseConfig: LocalHarnessConfig = {
  enabled: true,
  kind: 'openclaw',
  command: '/opt/homebrew/bin/openclaw',
  argsTemplate: ['agent', '--agent', 'imessage-agent', '--message', '{prompt}', '--json', '--timeout', '{timeout}'],
  workdir: '/Users/cm/work',
  timeoutSeconds: 120,
  deviceId: 'mac-mini',
  deviceName: 'Mac Mini',
};

const attemptInput = {
  taskId: '11111111-1111-4111-8111-111111111111',
  title: "email Alice about Friday's launch",
  request: {
    requestId: '22222222-2222-4222-8222-222222222222',
    mode: 'attempt' as const,
    instructions: 'Draft first, send only if already approved.',
  },
  actionPayload: {
    request_id: '22222222-2222-4222-8222-222222222222',
    handoff_mode: 'attempt',
    instructions: 'Draft first, send only if already approved.',
    discovery: {
      nextActions: ['Find the latest launch notes', 'Prepare a short reply'],
      web: { results: [{ title: 'Launch notes', url: 'https://example.invalid/launch' }] },
    },
  },
  resumePayload: { approved_by: 'user' },
};

test('local harness config stays disabled until explicitly enabled and configured', () => {
  assert.equal(localHarnessConfigFromEnv({ LOCAL_HARNESS_ENABLED: '0' }), null);
  assert.equal(localHarnessConfigFromEnv({ LOCAL_HARNESS_ENABLED: '1', LOCAL_HARNESS_KIND: 'custom' }), null);
  assert.equal(localHarnessConfigFromEnv({
    LOCAL_HARNESS_ENABLED: '1',
    LOCAL_HARNESS_KIND: 'openclaw',
    LOCAL_HARNESS_COMMAND: '/opt/homebrew/bin/openclaw',
    LOCAL_HARNESS_AGENT: 'imessage-agent',
  })?.argsTemplate.slice(0, 3).join(' '), 'agent --agent imessage-agent');
});

test('known harness adapters build local commands without SSH', () => {
  const prompt = "say 'hello'";
  assert.deepEqual(
    buildLocalHarnessArgs(baseConfig, prompt).slice(0, 5),
    ['agent', '--agent', 'imessage-agent', '--message', prompt]
  );
  assert.deepEqual(
    localHarnessConfigFromEnv({ LOCAL_HARNESS_ENABLED: '1', LOCAL_HARNESS_KIND: 'hermes' })?.argsTemplate,
    ['run', '{prompt}', '--output', 'json']
  );
  assert.deepEqual(
    localHarnessConfigFromEnv({
      LOCAL_HARNESS_ENABLED: '1',
      LOCAL_HARNESS_KIND: 'codex',
      LOCAL_HARNESS_WORKDIR: '/Users/cm/work/todo',
    })?.argsTemplate,
    ['exec', '--json', '--sandbox', 'danger-full-access', '--cd', '{workdir}', '{prompt}']
  );
  assert.deepEqual(
    buildLocalHarnessArgs(localHarnessConfigFromEnv({
      LOCAL_HARNESS_ENABLED: '1',
      LOCAL_HARNESS_KIND: 'codex',
      LOCAL_HARNESS_WORKDIR: '/Users/cm/work/todo',
    })!, prompt).slice(0, 6),
    ['exec', '--json', '--sandbox', 'danger-full-access', '--cd', '/Users/cm/work/todo']
  );
  assert.deepEqual(
    localHarnessConfigFromEnv({ LOCAL_HARNESS_ENABLED: '1', LOCAL_HARNESS_KIND: 'copilot-cli' })?.argsTemplate,
    ['-p', '{prompt}', '--json']
  );
});

test('custom args template can target any local harness', () => {
  const config = localHarnessConfigFromEnv({
    LOCAL_HARNESS_ENABLED: '1',
    LOCAL_HARNESS_KIND: 'custom',
    LOCAL_HARNESS_COMMAND: '/usr/local/bin/my-harness',
    LOCAL_HARNESS_ARGS_JSON: JSON.stringify({ args: ['run', '--prompt', '{prompt}', '--timeout', '{timeout}'] }),
    LOCAL_HARNESS_TIMEOUT_SECONDS: '45',
  });

  assert.ok(config);
  assert.deepEqual(buildLocalHarnessArgs(config, 'hello'), ['run', '--prompt', 'hello', '--timeout', '45']);
});

test('buildHarnessPrompt preserves approval scope and context', () => {
  const prompt = buildHarnessPrompt(attemptInput);
  assert.match(prompt, /approved Capture task handoff/);
  assert.match(prompt, /email Alice/);
  assert.match(prompt, /Draft first/);
  assert.match(prompt, /Launch notes/);
  assert.match(prompt, /spend money, message someone, delete data/);
});

test('runLocalHarnessAttempt parses JSON response from local harnesses', async () => {
  const result = await runLocalHarnessAttempt(baseConfig, attemptInput, async (file, args, options) => {
    assert.equal(file, '/opt/homebrew/bin/openclaw');
    assert.equal(args[0], 'agent');
    assert.equal(options.cwd, '/Users/cm/work');
    assert.equal(options.timeout, 135000);
    return {
      stdout: JSON.stringify({
        runId: 'run-1',
        status: 'ok',
        result: { payloads: [{ text: 'Drafted the reply.' }] },
      }),
      stderr: '',
    };
  });

  assert.equal(result.runId, 'run-1');
  assert.equal(result.status, 'ok');
  assert.equal(result.reply, 'Drafted the reply.');
  assert.equal(result.harnessKind, 'openclaw');
  assert.equal(result.deviceId, 'mac-mini');
});

test('runLocalHarnessAttempt extracts the final Codex JSONL agent message', async () => {
  const config: LocalHarnessConfig = {
    ...baseConfig,
    kind: 'codex',
    command: 'codex',
    argsTemplate: ['exec', '--json', '--sandbox', 'danger-full-access', '--cd', '{workdir}', '{prompt}'],
    workdir: '/Users/cm/work/todo',
  };
  const result = await runLocalHarnessAttempt(config, attemptInput, async (file, args) => {
    assert.equal(file, 'codex');
    assert.deepEqual(args.slice(0, 6), ['exec', '--json', '--sandbox', 'danger-full-access', '--cd', '/Users/cm/work/todo']);
    return {
      stdout: [
        JSON.stringify({ type: 'thread.started', thread_id: 'thread-1' }),
        JSON.stringify({ type: 'item.completed', item: { type: 'agent_message', text: '{"status":"ok","reply":"Codex completed it."}' } }),
        JSON.stringify({ type: 'turn.completed', usage: { input_tokens: 10, output_tokens: 5 } }),
      ].join('\n'),
      stderr: '',
    };
  });

  assert.equal(result.status, 'ok');
  assert.equal(result.reply, 'Codex completed it.');
  assert.equal(result.harnessKind, 'codex');
});

test('runLocalHarnessAttempt reports failures without echoing the full prompt command', async () => {
  await assert.rejects(
    runLocalHarnessAttempt(baseConfig, attemptInput, async () => {
      throw {
        code: 2,
        stderr: 'harness unavailable',
        message: 'Command failed: openclaw ... email Alice about launch',
      };
    }),
    /Local harness openclaw command failed \(exit=2; stderr=harness unavailable\)/
  );
});

import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildOpenClawRemoteCommand,
  buildOpenClawSshArgs,
  openClawConfigFromEnv,
  runOpenClawAttempt,
  type OpenClawConfig,
} from './openclawExecutor.js';

const baseConfig: OpenClawConfig = {
  enabled: true,
  host: 'bravos-mac-mini.taile313a5.ts.net',
  user: 'bravostation',
  port: 22,
  keyPath: '/Users/cm/.ssh/capture_openclaw_ed25519',
  workdir: '/Users/bravostation/clawd',
  cli: '/opt/homebrew/bin/openclaw',
  agent: 'imessage-agent',
  timeoutSeconds: 120,
  thinking: 'medium',
  strictHostKeyChecking: 'accept-new',
  connectTimeoutSeconds: 10,
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

test('OpenClaw config stays disabled until explicitly enabled and configured', () => {
  assert.equal(openClawConfigFromEnv({ OPENCLAW_EXECUTOR_ENABLED: '1' }), null);
  assert.equal(openClawConfigFromEnv({
    OPENCLAW_EXECUTOR_ENABLED: '1',
    OPENCLAW_SSH_HOST: baseConfig.host,
    OPENCLAW_SSH_USER: baseConfig.user,
    OPENCLAW_SSH_KEY_PATH: baseConfig.keyPath,
  })?.agent, 'imessage-agent');
});

test('buildOpenClawRemoteCommand shell-quotes task prompts for the remote shell', () => {
  const command = buildOpenClawRemoteCommand(baseConfig, "say 'hello'");
  assert.match(command, /^cd '\/Users\/bravostation\/clawd' &&/);
  assert.match(command, /'\/opt\/homebrew\/bin\/openclaw' 'agent'/);
  assert.match(command, /--message' 'say '\\''hello'\\'''/);
  assert.match(command, /'--thinking' 'medium'$/);
});

test('buildOpenClawSshArgs uses non-interactive SSH options', () => {
  const args = buildOpenClawSshArgs(baseConfig, 'echo ok');
  assert.deepEqual(args.slice(0, 8), [
    '-i',
    baseConfig.keyPath,
    '-p',
    '22',
    '-o',
    'BatchMode=yes',
    '-o',
    'StrictHostKeyChecking=accept-new',
  ]);
  assert.equal(args.at(-2), `${baseConfig.user}@${baseConfig.host}`);
  assert.equal(args.at(-1), 'echo ok');
});

test('runOpenClawAttempt parses the blessed JSON response', async () => {
  const result = await runOpenClawAttempt(baseConfig, attemptInput, async (file, args, options) => {
    assert.equal(file, 'ssh');
    assert.equal(args[0], '-i');
    assert.equal(options.timeout, 145000);
    return {
      stdout: JSON.stringify({ runId: 'run-1', status: 'ok', reply: 'Drafted the reply.' }),
      stderr: '',
    };
  });

  assert.equal(result.runId, 'run-1');
  assert.equal(result.status, 'ok');
  assert.equal(result.reply, 'Drafted the reply.');
});

test('runOpenClawAttempt reports command failures without echoing the full prompt command', async () => {
  await assert.rejects(
    runOpenClawAttempt(baseConfig, attemptInput, async () => {
      throw {
        code: 255,
        stderr: 'Permission denied (publickey).',
        message: 'Command failed: ssh ... email Alice about launch',
      };
    }),
    /OpenClaw SSH command failed \(exit=255; stderr=Permission denied \(publickey\)\.\)/
  );
});

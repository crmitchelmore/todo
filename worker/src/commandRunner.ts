import { spawn } from 'node:child_process';

export interface CommandRunner {
  (
    file: string,
    args: readonly string[],
    options: { cwd: string; timeout: number; maxBuffer: number }
  ): Promise<{ stdout: string; stderr: string }>;
}

export const runCommand: CommandRunner = (file, args, options) => new Promise((resolve, reject) => {
  const child = spawn(file, [...args], {
    cwd: options.cwd,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let stdout = '';
  let stderr = '';
  let settled = false;
  let timedOut = false;

  const fail = (err: Error) => {
    if (settled) return;
    settled = true;
    clearTimeout(timer);
    reject(Object.assign(err, { stdout, stderr }));
  };

  const append = (target: 'stdout' | 'stderr', chunk: Buffer | string) => {
    const text = String(chunk);
    if (target === 'stdout') {
      stdout += text;
    } else {
      stderr += text;
    }
    if (stdout.length + stderr.length > options.maxBuffer) {
      child.kill('SIGTERM');
      fail(new Error(`Command failed: ${file} output exceeded ${options.maxBuffer} bytes`));
    }
  };

  const timer = setTimeout(() => {
    timedOut = true;
    child.kill('SIGTERM');
  }, options.timeout);

  child.stdout.on('data', (chunk) => append('stdout', chunk));
  child.stderr.on('data', (chunk) => append('stderr', chunk));
  child.on('error', fail);
  child.on('close', (code, signal) => {
    if (settled) return;
    settled = true;
    clearTimeout(timer);
    if (code === 0) {
      resolve({ stdout, stderr });
      return;
    }
    reject(Object.assign(
      new Error(`Command failed: ${file} ${args.join(' ')}${timedOut ? ' (timeout)' : ''}`),
      { code, signal, stdout, stderr },
    ));
  });
});

import { afterEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { configuredMailProvider } from '../src/mailer.ts';

const MAIL_ENV = [
  'MAIL_PROVIDER',
  'SMTP_URL',
  'RESEND_API_KEY',
  'BREVO_API_KEY',
  'SENDGRID_API_KEY',
  'POSTMARK_SERVER_TOKEN',
] as const;

const original = Object.fromEntries(MAIL_ENV.map((key) => [key, process.env[key]]));

afterEach(() => {
  for (const key of MAIL_ENV) {
    const value = original[key];
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
});

function clearMailEnv(): void {
  for (const key of MAIL_ENV) delete process.env[key];
}

test('configuredMailProvider auto-detects supported providers by credential', () => {
  clearMailEnv();
  assert.equal(configuredMailProvider(), null);

  process.env.SENDGRID_API_KEY = 'x';
  assert.equal(configuredMailProvider(), 'sendgrid');

  process.env.SMTP_URL = 'smtp://user:pass@example.com:587';
  assert.equal(configuredMailProvider(), 'smtp'); // SMTP wins when several credentials exist
});

test('configuredMailProvider honours explicit MAIL_PROVIDER', () => {
  clearMailEnv();
  process.env.MAIL_PROVIDER = 'postmark';
  process.env.RESEND_API_KEY = 'x';
  assert.equal(configuredMailProvider(), 'postmark');
});

test('configuredMailProvider rejects unknown provider names', () => {
  clearMailEnv();
  process.env.MAIL_PROVIDER = 'carrier-pigeon';
  assert.throws(() => configuredMailProvider(), /unknown MAIL_PROVIDER/);
});

import nodemailer from 'nodemailer';

/**
 * Transactional mailer for auth flows (passwordless login codes, password reset).
 *
 * Provider selection:
 *   - MAIL_PROVIDER=smtp|resend|brevo|sendgrid|postmark to force one provider, or omit it and the
 *     first configured credential below wins.
 *   - SMTP_URL                  -> any SMTP relay supported by nodemailer.
 *   - RESEND_API_KEY            -> Resend HTTP API.
 *   - BREVO_API_KEY             -> Brevo transactional HTTP API.
 *   - SENDGRID_API_KEY          -> SendGrid HTTP API.
 *   - POSTMARK_SERVER_TOKEN     -> Postmark HTTP API.
 *   - otherwise                 -> log to server console (local dev / CI).
 */

const MAIL_FROM = process.env.MAIL_FROM ?? 'Capture <onboarding@resend.dev>';
const MAIL_FROM_EMAIL = process.env.MAIL_FROM_EMAIL ?? parseEmailAddress(MAIL_FROM);

export interface OutgoingEmail {
  to: string;
  subject: string;
  text: string;
  html?: string;
}

export async function sendEmail({ to, subject, text, html }: OutgoingEmail): Promise<void> {
  const provider = configuredMailProvider();
  if (provider === 'smtp') return sendViaSmtp({ to, subject, text, html });
  if (provider === 'resend') return sendViaResend({ to, subject, text, html });
  if (provider === 'brevo') return sendViaBrevo({ to, subject, text, html });
  if (provider === 'sendgrid') return sendViaSendGrid({ to, subject, text, html });
  if (provider === 'postmark') return sendViaPostmark({ to, subject, text, html });

  // Dev/CI fallback: no provider configured. Never throws so the flow stays usable locally.
  console.log(`[mailer:dev] to=${to} subject=${JSON.stringify(subject)}\n${text}`);
}

export type MailProvider = 'smtp' | 'resend' | 'brevo' | 'sendgrid' | 'postmark';

export function configuredMailProvider(): MailProvider | null {
  const forced = process.env.MAIL_PROVIDER?.trim().toLowerCase();
  if (forced) {
    if (isMailProvider(forced)) return forced;
    throw new Error(`unknown MAIL_PROVIDER "${forced}"`);
  }
  if (process.env.SMTP_URL) return 'smtp';
  if (process.env.RESEND_API_KEY) return 'resend';
  if (process.env.BREVO_API_KEY) return 'brevo';
  if (process.env.SENDGRID_API_KEY) return 'sendgrid';
  if (process.env.POSTMARK_SERVER_TOKEN) return 'postmark';
  return null;
}

function isMailProvider(provider: string): provider is MailProvider {
  return ['smtp', 'resend', 'brevo', 'sendgrid', 'postmark'].includes(provider);
}

async function sendViaSmtp(email: OutgoingEmail): Promise<void> {
  const smtpUrl = process.env.SMTP_URL;
  if (!smtpUrl) throw new Error('SMTP_URL is required for MAIL_PROVIDER=smtp');
  const transporter = nodemailer.createTransport(smtpUrl);
  await transporter.sendMail({
    from: MAIL_FROM,
    to: email.to,
    subject: email.subject,
    text: email.text,
    html: email.html,
  });
}

async function sendViaResend({ to, subject, text, html }: OutgoingEmail): Promise<void> {
  const key = requiredEnv('RESEND_API_KEY');
  await postProvider('resend', 'https://api.resend.com/emails', {
    headers: { Authorization: `Bearer ${key}` },
    body: { from: MAIL_FROM, to, subject, text, html },
  });
}

async function sendViaBrevo({ to, subject, text, html }: OutgoingEmail): Promise<void> {
  const key = requiredEnv('BREVO_API_KEY');
  await postProvider('brevo', 'https://api.brevo.com/v3/smtp/email', {
    headers: { 'api-key': key },
    body: {
      sender: { email: MAIL_FROM_EMAIL, name: parseDisplayName(MAIL_FROM) ?? 'Capture' },
      to: [{ email: to }],
      subject,
      textContent: text,
      htmlContent: html,
    },
  });
}

async function sendViaSendGrid({ to, subject, text, html }: OutgoingEmail): Promise<void> {
  const key = requiredEnv('SENDGRID_API_KEY');
  await postProvider('sendgrid', 'https://api.sendgrid.com/v3/mail/send', {
    headers: { Authorization: `Bearer ${key}` },
    body: {
      personalizations: [{ to: [{ email: to }] }],
      from: { email: MAIL_FROM_EMAIL, name: parseDisplayName(MAIL_FROM) ?? 'Capture' },
      subject,
      content: [
        { type: 'text/plain', value: text },
        ...(html ? [{ type: 'text/html', value: html }] : []),
      ],
    },
    okStatuses: [202],
  });
}

async function sendViaPostmark({ to, subject, text, html }: OutgoingEmail): Promise<void> {
  const token = requiredEnv('POSTMARK_SERVER_TOKEN');
  await postProvider('postmark', 'https://api.postmarkapp.com/email', {
    headers: { 'X-Postmark-Server-Token': token },
    body: {
      From: MAIL_FROM,
      To: to,
      Subject: subject,
      TextBody: text,
      HtmlBody: html,
      MessageStream: process.env.POSTMARK_MESSAGE_STREAM ?? 'outbound',
    },
  });
}

async function postProvider(
  name: string,
  url: string,
  options: {
    headers: Record<string, string>;
    body: Record<string, unknown>;
    okStatuses?: number[];
  }
): Promise<void> {
  const okStatuses = options.okStatuses ?? [200, 201, 202];
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      ...options.headers,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(options.body),
  });
  if (!okStatuses.includes(res.status)) {
    const body = await res.text().catch(() => '');
    throw new Error(`${name} send failed (${res.status}): ${body}`);
  }
}

function requiredEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is required`);
  return value;
}

function parseEmailAddress(value: string): string {
  const match = value.match(/<([^>]+)>/);
  return (match?.[1] ?? value).trim();
}

function parseDisplayName(value: string): string | null {
  const match = value.match(/^([^<]+)</);
  return match?.[1].trim().replace(/^"|"$/g, '') || null;
}

/** Plain wrapper that swallows transport errors after logging — callers must not leak provider
 *  failures into a 500 that reveals whether an address exists (and so an attacker can't probe). */
export async function sendEmailBestEffort(email: OutgoingEmail): Promise<void> {
  try {
    await sendEmail(email);
  } catch (err) {
    console.error('email send failed:', err);
  }
}

// --- Templates --------------------------------------------------------------------------------

export function loginCodeEmail(to: string, code: string, ttlMinutes: number): OutgoingEmail {
  return {
    to,
    subject: `${code} is your Capture sign-in code`,
    text:
      `Your Capture sign-in code is ${code}.\n\n` +
      `It expires in ${ttlMinutes} minutes. If you didn't request this, you can ignore this email.`,
  };
}

export function resetCodeEmail(to: string, code: string, ttlMinutes: number): OutgoingEmail {
  return {
    to,
    subject: `${code} is your Capture password-reset code`,
    text:
      `Use code ${code} to reset your Capture password.\n\n` +
      `It expires in ${ttlMinutes} minutes. If you didn't request a reset, you can ignore this email — ` +
      `your password won't change.`,
  };
}

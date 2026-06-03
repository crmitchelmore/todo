/**
 * Transactional mailer for auth flows (passwordless login codes, password reset). Provider-agnostic
 * so deployment can pick a provider via env without code changes:
 *
 *   - RESEND_API_KEY set -> send via the Resend HTTP API (no extra dependency; uses global fetch).
 *   - otherwise          -> log the email to the server console (local dev / CI). The code/link is
 *                           visible in logs so the flow is fully exercisable without a real inbox.
 *
 * (An SMTP provider can be added here later behind a `SMTP_URL` branch via nodemailer.)
 */

const MAIL_FROM = process.env.MAIL_FROM ?? 'Capture <onboarding@resend.dev>';

export interface OutgoingEmail {
  to: string;
  subject: string;
  text: string;
  html?: string;
}

export async function sendEmail({ to, subject, text, html }: OutgoingEmail): Promise<void> {
  const resendKey = process.env.RESEND_API_KEY;
  if (resendKey) {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${resendKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ from: MAIL_FROM, to, subject, text, html }),
    });
    if (!res.ok) {
      const body = await res.text().catch(() => '');
      throw new Error(`resend send failed (${res.status}): ${body}`);
    }
    return;
  }

  // Dev/CI fallback: no provider configured. Never throws so the flow stays usable locally.
  console.log(`[mailer:dev] to=${to} subject=${JSON.stringify(subject)}\n${text}`);
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

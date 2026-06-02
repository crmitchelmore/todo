import { ImapFlow } from "imapflow";
import { simpleParser } from "mailparser";

import {
  CompletionSignal,
  ExtractedTodo,
  TaskForCompletionDetection,
} from "./types.js";
import { GmailImapConfig, GmailSince, GmailTransport } from "./gmail.js";

/**
 * Real Gmail transport over IMAP using an App Password.
 *
 * Read-only in practice: it only issues SEARCH + FETCH (no STORE/EXPUNGE), opens the mailbox
 * read-only, and never mutates flags. Everything it returns is a *proposal* with provenance
 * (message id, sender, a source quote, confidence) and must pass Capture's human confirmation.
 */
export class ImapGmailTransport implements GmailTransport {
  private readonly mailbox: string;
  private readonly maxMessages: number;

  constructor(options: { mailbox?: string; maxMessages?: number } = {}) {
    this.mailbox = options.mailbox ?? "INBOX";
    this.maxMessages = options.maxMessages ?? 50;
  }

  async extractTodos(config: GmailImapConfig, since: GmailSince): Promise<readonly ExtractedTodo[]> {
    return this.withClient(config, async (client) => {
      const out: ExtractedTodo[] = [];
      const uids = await this.searchSince(client, since.cutoff);
      for (const uid of uids.slice(-this.maxMessages)) {
        const parsed = await this.fetchParsed(client, uid);
        if (!parsed) continue;
        const subject = (parsed.subject ?? "").trim();
        if (subject.length === 0) continue;
        const body = bodyText(parsed.text, parsed.html);
        out.push({
          source: "gmail",
          sourceMessageId: parsed.messageId ?? `uid:${uid}`,
          threadId: parsed.inReplyTo ?? undefined,
          title: subject,
          sourceQuote: firstSentence(body) || subject,
          confidence: 0.5,
          sender: parsed.fromAddress,
          receivedAt: parsed.date?.toISOString(),
          dueHint: detectDueHint(`${subject} ${body}`),
          labels: [this.mailbox],
        });
      }
      return out;
    });
  }

  async detectCompletions(
    config: GmailImapConfig,
    tasks: readonly TaskForCompletionDetection[],
  ): Promise<readonly CompletionSignal[]> {
    if (tasks.length === 0) return [];
    return this.withClient(config, async (client) => {
      const signals: CompletionSignal[] = [];
      // Look at recent messages once; match each against task titles by keyword overlap.
      const recent = await this.searchSince(client, daysAgo(14));
      for (const uid of recent.slice(-this.maxMessages)) {
        const parsed = await this.fetchParsed(client, uid);
        if (!parsed) continue;
        const haystack = `${parsed.subject ?? ""} ${bodyText(parsed.text, parsed.html)}`.toLowerCase();
        if (!DONE_HINTS.some((h) => haystack.includes(h))) continue;
        for (const task of tasks) {
          if (titleMatches(task.title, haystack)) {
            signals.push({
              source: "gmail",
              taskId: task.id,
              messageId: parsed.messageId ?? `uid:${uid}`,
              threadId: parsed.inReplyTo ?? undefined,
              reason: "Recent email mentions this task with a completion phrase.",
              sourceQuote: firstSentence(bodyText(parsed.text, parsed.html)) || (parsed.subject ?? ""),
              confidence: 0.6,
              receivedAt: parsed.date?.toISOString(),
            });
            break;
          }
        }
      }
      return signals;
    });
  }

  private async withClient<T>(
    config: GmailImapConfig,
    fn: (client: ImapFlow) => Promise<T>,
  ): Promise<T> {
    const client = new ImapFlow({
      host: config.host,
      port: config.port,
      secure: true,
      auth: { user: config.user, pass: config.appPassword },
      logger: false,
    });
    await client.connect();
    const lock = await client.getMailboxLock(this.mailbox, { readonly: true } as never);
    try {
      return await fn(client);
    } finally {
      lock.release();
      await client.logout().catch(() => undefined);
    }
  }

  private async searchSince(client: ImapFlow, cutoff: Date): Promise<number[]> {
    const result = await client.search({ since: cutoff }, { uid: true });
    return Array.isArray(result) ? (result as number[]) : [];
  }

  private async fetchParsed(client: ImapFlow, uid: number): Promise<ParsedEmail | null> {
    const msg = await client.fetchOne(String(uid), { source: true }, { uid: true });
    if (!msg || !msg.source) return null;
    const mail = await simpleParser(msg.source as Buffer);
    const from = mail.from?.value?.[0];
    return {
      messageId: mail.messageId,
      inReplyTo: typeof mail.inReplyTo === "string" ? mail.inReplyTo : undefined,
      subject: mail.subject,
      text: mail.text,
      html: typeof mail.html === "string" ? mail.html : undefined,
      date: mail.date,
      fromAddress: from?.address
        ? { name: from.name || undefined, address: from.address }
        : undefined,
    };
  }
}

interface ParsedEmail {
  readonly messageId?: string;
  readonly inReplyTo?: string;
  readonly subject?: string;
  readonly text?: string;
  readonly html?: string;
  readonly date?: Date;
  readonly fromAddress?: { readonly name?: string; readonly address: string };
}

const DONE_HINTS = ["done", "completed", "finished", "shipped", "merged", "resolved", "sent", "paid"];
const DUE_HINTS: ReadonlyArray<[RegExp, string]> = [
  [/\btoday\b/i, "today"],
  [/\btomorrow\b/i, "tomorrow"],
  [/\bend of (the )?week\b/i, "end of week"],
  [/\bnext week\b/i, "next week"],
  [/\bby (mon|tue|wed|thu|fri|sat|sun)/i, "this week"],
];

function detectDueHint(text: string): string | undefined {
  for (const [re, hint] of DUE_HINTS) {
    if (re.test(text)) return hint;
  }
  return undefined;
}

function bodyText(text?: string, html?: string): string {
  if (text && text.trim().length > 0) return text;
  if (html) return html.replace(/<[^>]+>/g, " ");
  return "";
}

function firstSentence(text: string): string {
  const clean = text.replace(/\s+/g, " ").trim();
  if (clean.length === 0) return "";
  const end = clean.search(/[.!?]\s/);
  const slice = end > 0 ? clean.slice(0, end + 1) : clean;
  return slice.length > 200 ? `${slice.slice(0, 197)}...` : slice;
}

function titleMatches(title: string, haystack: string): boolean {
  const tokens = title
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter((t) => t.length > 3);
  if (tokens.length === 0) return false;
  const hits = tokens.filter((t) => haystack.includes(t)).length;
  return hits / tokens.length >= 0.6;
}

function daysAgo(days: number): Date {
  return new Date(Date.now() - days * 86_400_000);
}

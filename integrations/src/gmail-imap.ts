import { ImapFlow } from "imapflow";
import { simpleParser } from "mailparser";

import {
  CompletionSignal,
  ExtractedTodo,
  TaskForCompletionDetection,
} from "./types.js";
import { GmailImapConfig, GmailSince, GmailTransport } from "./gmail.js";
import {
  buildExtractedTodoFromEmail,
  buildCompletionSignalsFromEmail,
  ParsedGmailEmail,
} from "./gmail-action.js";

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
      const uids = await this.searchSince(client, since.cutoff, config.rawSearch);
      for (const uid of uids.slice(-this.maxMessages)) {
        const parsed = await this.fetchParsed(client, uid);
        if (!parsed) continue;
        const todo = buildExtractedTodoFromEmail(parsed, uid, this.mailbox);
        if (todo) out.push(todo);
      }
      return out;
    });
  }

  async fetchThread(
    config: GmailImapConfig,
    threadId: string,
    since: GmailSince,
  ): Promise<readonly ExtractedTodo[]> {
    return this.withClient(config, async (client) => {
      const uids = await client.search({ threadId, since: since.cutoff }, { uid: true });
      const out: ExtractedTodo[] = [];
      for (const uid of (Array.isArray(uids) ? uids as number[] : []).slice(-this.maxMessages)) {
        const parsed = await this.fetchParsed(client, uid);
        const todo = parsed ? buildExtractedTodoFromEmail(parsed, uid, this.mailbox) : null;
        if (todo) out.push(todo);
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
        signals.push(...buildCompletionSignalsFromEmail(parsed, uid, tasks));
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
      auth: {
        user: config.user,
        ...(config.accessToken ? { accessToken: config.accessToken } : { pass: config.appPassword }),
      },
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

  private async searchSince(client: ImapFlow, cutoff: Date, rawSearch?: string): Promise<number[]> {
    const result = await client.search(
      { since: cutoff, ...(rawSearch ? { gmailraw: rawSearch } : {}) },
      { uid: true },
    );
    return Array.isArray(result) ? (result as number[]) : [];
  }

  private async fetchParsed(client: ImapFlow, uid: number): Promise<ParsedGmailEmail | null> {
    const msg = await client.fetchOne(String(uid), { source: true, threadId: true, labels: true }, { uid: true });
    if (!msg || !msg.source) return null;
    const mail = await simpleParser(msg.source as Buffer);
    const from = mail.from?.value?.[0];
    return {
      messageId: mail.messageId,
      threadId: typeof msg.threadId === "string" ? msg.threadId : undefined,
      inReplyTo: typeof mail.inReplyTo === "string" ? mail.inReplyTo : undefined,
      subject: mail.subject,
      text: mail.text,
      html: typeof mail.html === "string" ? mail.html : undefined,
      date: mail.date,
      fromAddress: from?.address
        ? { name: from.name || undefined, address: from.address }
        : undefined,
      labels: msg.labels instanceof Set ? [...msg.labels] : undefined,
    };
  }
}

function daysAgo(days: number): Date {
  return new Date(Date.now() - days * 86_400_000);
}

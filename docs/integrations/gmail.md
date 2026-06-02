# Gmail integration (IMAP + App Password)

Capture reads Gmail over **IMAP using an App Password** — no Google Cloud project, OAuth client,
or refresh-token flow to maintain. This is the most reliable low-friction path for a personal
Gmail account. The connector lives in `integrations/` (`GmailConnector` + `ImapGmailTransport`).

Access is effectively read-only: the transport only issues `SEARCH` + `FETCH`, opens the mailbox
read-only, and never modifies flags or deletes mail.

## Setup

1. Enable **2-Step Verification** on the Google account (required for App Passwords).
2. Create an **App Password**: Google Account → Security → App passwords → app "Mail". Copy the
   16-character password.
3. Ensure **IMAP is enabled**: Gmail → Settings → Forwarding and POP/IMAP → Enable IMAP.
4. Set the environment variables in the worker/agent process:

```sh
GMAIL_IMAP_USER=you@gmail.com
GMAIL_IMAP_APP_PASSWORD=your-16-char-app-password
# optional overrides (defaults shown)
# GMAIL_IMAP_HOST=imap.gmail.com
# GMAIL_IMAP_PORT=993
```

Store the App Password only as an environment secret — never commit it or paste it into docs,
tests, fixtures, or local scripts.

## Connector surface

- `extractTodos(since)` — `since` is a lookback spec: `"7d"`, `"36h"`, or an ISO date. Returns
  typed `ExtractedTodo` proposals (subject as title, sender, a source quote, a due hint when one
  is detected) for recent inbox messages.
- `detectCompletions(tasks)` — scans recent mail for completion phrases ("done", "shipped",
  "merged", …) that match a task's title, returning typed `CompletionSignal` proposals.
- `healthCheck()` — reports `ok` when IMAP credentials are present, `not_configured` otherwise.

The default transport is a stub; construct `new GmailConnector({ transport: new ImapGmailTransport() })`
(or wire it in the worker) to run against real IMAP.

## Security posture

Everything returned is a **proposal** with provenance (`sourceQuote`, message IDs, confidence) and
must pass Capture's human confirmation before saving or changing task state.

# Gmail integration (IMAP + App Password or OAuth2 access token)

Capture reads Gmail over **IMAP**. For a personal account, the lowest-friction path is an App
Password. If a Google OAuth client already exists, the same connector can use a short-lived OAuth2
access token instead. The connector lives in `integrations/` (`GmailConnector` + `ImapGmailTransport`).

Access is effectively read-only: the transport only issues `SEARCH` + `FETCH`, opens the mailbox
read-only, and never modifies flags or deletes mail.

## Setup

1. Enable **2-Step Verification** on the Google account (required for App Passwords).
2. Create an **App Password**: Google Account → Security → App passwords → app "Mail". Copy the
   16-character password. Alternatively provide an OAuth2 access token with Gmail IMAP scope.
3. Ensure **IMAP is enabled**: Gmail → Settings → Forwarding and POP/IMAP → Enable IMAP.
4. Set the environment variables in the worker/agent process:

```sh
GMAIL_IMAP_USER=you@gmail.com
GMAIL_IMAP_APP_PASSWORD=placeholder
# or:
# GMAIL_OAUTH_ACCESS_TOKEN=short-lived-oauth-access-token
# optional overrides (defaults shown)
# GMAIL_IMAP_HOST=imap.gmail.com
# GMAIL_IMAP_PORT=993
# GMAIL_RAW_SEARCH=is:unread newer_than:14d
```

Store the App Password or OAuth token only as an environment secret — never commit it or paste it
into docs, tests, fixtures, or local scripts.

## Connector surface

- `extractTodos(since)` — `since` is a lookback spec: `"7d"`, `"36h"`, or an ISO date. It searches
  recent mail, applies the optional Gmail raw pre-filter, and only returns typed `ExtractedTodo`
  proposals when the subject/body contains action language (`please`, `could you`, `action required`,
  `need to`, and similar). Each proposal includes sender, source quote, confidence, due hint when
  detected, Gmail thread id, and labels.
- `fetchThread(threadId, since)` — fetches a full Gmail thread by `X-GM-THRID`/OBJECTID, so a
  candidate action item can be expanded with surrounding conversation context before proposal.
- `detectCompletions(tasks)` — scans recent mail for completion phrases ("done", "shipped",
  "merged", …) that match a task's title, returning typed `CompletionSignal` proposals.
- `healthCheck()` — reports `ok` when IMAP credentials are present, `not_configured` otherwise.

The default transport is a stub; construct `new GmailConnector({ transport: new ImapGmailTransport() })`
(or wire it in the worker) to run against real IMAP.

## Security posture

Everything returned is a **proposal** with provenance (`sourceQuote`, message IDs, confidence) and
must pass Capture's human confirmation before saving or changing task state.

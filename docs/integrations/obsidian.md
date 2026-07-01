# Obsidian integration

Capture has a typed Obsidian connector boundary in `integrations/` and a worker write-back path for URL-only captures. When a capture contains only one `http(s)` URL, clients mark it as `source='url-summary'`; the worker extracts readable page markdown, asks the configured LLM for a 1-2 sentence overview plus a 3-5 paragraph summary, writes the markdown into the task notes, and optionally creates an Obsidian note through the local `obsidian` CLI.

## Setup

1. Install the community **Local REST API** plugin in Obsidian.
2. Enable the plugin and open **Settings → Local REST API**.
3. Copy the API key.
4. Use the HTTPS server URL shown by the plugin. The common default is `https://127.0.0.1:27124`; the HTTP endpoint is usually `http://127.0.0.1:27123` only if explicitly enabled. Node rejects the plugin's self-signed HTTPS certificate unless the certificate is trusted, so local agent processes can use the loopback HTTP endpoint when it is enabled.
5. Set the integration environment variables in the process that will run the connector:

```sh
OBSIDIAN_API_URL=http://127.0.0.1:27123
OBSIDIAN_API_KEY=<local-rest-api-key>
```

For URL-summary write-back through the Obsidian CLI, configure the worker process on the machine that has vault access:

```sh
OPENAI_API_KEY=<llm-key>
OBSIDIAN_CLI_ENABLED=1
OBSIDIAN_CLI_COMMAND=obsidian
OBSIDIAN_VAULT=<vault-name>
OBSIDIAN_SUMMARY_FOLDER=Capture/Summaries
```

The worker prefers the `defuddle` CLI (`defuddle parse <url> --md`) for clean page extraction when available, then falls back to bounded HTTP extraction. Set `URL_SUMMARY_DEFUDDLE_COMMAND` to a custom binary path or `URL_SUMMARY_DISABLE_DEFUDDLE=1` to skip that step.

## Connector surface

- `searchVault(query)` calls `POST /search/simple/?query=...` with `Authorization: Bearer ...` and returns typed `VaultSearchHit` values.
- `getNote(path)` calls `GET /vault/{path}` with `Authorization: Bearer ...` and returns a typed `VaultNote`.
- `appendTasksToDailyNote(tasks, options)` writes Capture tasks back to a daily note using the
  Obsidian Tasks line format (`- [ ] Title #tag 📅 YYYY-MM-DD`, or `- [x] ... ✅ YYYY-MM-DD` for
  completed tasks). It defaults to `Daily/YYYY-MM-DD.md` and appends under a `## Capture` heading,
  creating the note when it does not exist.
- `buildObsidianSemanticIndex(connector, seedQueries)` uses Local REST search to find candidate notes, fetches each note once, chunks markdown by heading/size, and builds a local deterministic embedding index for task-context retrieval.
- `healthCheck()` calls the Local REST API root endpoint and reports `ok` only when the configured service is reachable.
- Connector calls use an 8 second timeout by default so an agent cannot hang indefinitely on vault operations.
- URL-summary notes use Obsidian-flavoured markdown with frontmatter, a source link, a summary callout, and a `## Summary` section in the same document.

The plugin is currently enabled locally and responds on both `https://127.0.0.1:27124` and `http://127.0.0.1:27123`. The API key is stored only in the session secrets file, not in the repository.

## Security posture

The Obsidian Local REST API token grants access to the local vault API, so store it only as an environment secret on the trusted machine that runs the agent. CLI write-back stores only non-secret vault/folder/command settings in the app settings UI; the worker environment remains the source of truth for actual vault access.

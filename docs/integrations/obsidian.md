# Obsidian integration

Capture has a typed Obsidian connector boundary in `integrations/`, but it is not yet wired into the worker or backend. It is scaffolded up to the credential boundary: when credentials are absent, calls fail with `IntegrationNotConfiguredError`; when credentials are present, the connector uses the Local REST API HTTP shape for vault search and note reads.

## Setup

1. Install the community **Local REST API** plugin in Obsidian.
2. Enable the plugin and open **Settings → Local REST API**.
3. Copy the API key.
4. Use the HTTPS server URL shown by the plugin. The common default is `https://127.0.0.1:27124`; the HTTP endpoint is usually `http://127.0.0.1:27123` only if explicitly enabled.
5. Set the integration environment variables in the process that will run the connector:

```sh
OBSIDIAN_API_URL=https://127.0.0.1:27124
OBSIDIAN_API_KEY=your-obsidian-api-key-here
```

## Connector surface

- `searchVault(query)` calls `POST /search/simple/?query=...` with `Authorization: Bearer ...` and returns typed `VaultSearchHit` values.
- `getNote(path)` calls `GET /vault/{path}` with `Authorization: Bearer ...` and returns a typed `VaultNote`.
- `healthCheck()` currently reports configuration state only; it does not probe the live vault.

## Security posture

The Obsidian Local REST API token grants access to the local vault API, so store it only as an environment secret on the trusted machine that runs the agent. Capture currently scaffolds read/search behaviour only. Write-back to daily notes is intentionally not wired here; future write methods should keep the existing human-confirm-before-save posture before changing notes.

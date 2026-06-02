import assert from "node:assert/strict";
import test from "node:test";

import { createIntegrationRegistry } from "./index.js";

test("registry exposes both connector health checks", async () => {
  const registry = createIntegrationRegistry({});

  assert.equal(registry.connectors.length, 2);
  assert.deepEqual(
    registry.connectors.map((connector) => connector.name).sort(),
    ["gmail", "obsidian"],
  );

  const health = await registry.healthCheck();
  assert.deepEqual(
    health.map((item) => item.status),
    ["not_configured", "not_configured"],
  );
});

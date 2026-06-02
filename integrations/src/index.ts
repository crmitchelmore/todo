import { GmailConnector } from "./gmail.js";
import { ObsidianConnector } from "./obsidian.js";
import { Connector, ConnectorHealth } from "./types.js";

export * from "./types.js";
export * from "./obsidian.js";
export * from "./gmail.js";
export * from "./gmail-imap.js";

export interface IntegrationRegistry {
  readonly obsidian: ObsidianConnector;
  readonly gmail: GmailConnector;
  readonly connectors: readonly Connector[];
  healthCheck(): Promise<readonly ConnectorHealth[]>;
}

export function createIntegrationRegistry(env: NodeJS.ProcessEnv = process.env): IntegrationRegistry {
  const obsidian = ObsidianConnector.fromEnv(env);
  const gmail = GmailConnector.fromEnv(env);
  const connectors: readonly Connector[] = [obsidian, gmail];

  return {
    obsidian,
    gmail,
    connectors,
    healthCheck: () => Promise.all(connectors.map((connector) => connector.healthCheck())),
  };
}

export const registry = createIntegrationRegistry();
export const connectors = registry.connectors;
export const healthCheck = registry.healthCheck;

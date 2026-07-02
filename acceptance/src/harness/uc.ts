import { Computer, MacOSSandbox, IOSSandbox } from "use-computer-sdk";
import { config } from "./env.js";

/** Lazily-created shared client. */
export function client(): Computer {
  return new Computer({ apiKey: config.useComputerApiKey() });
}

interface Keepalive {
  stop(): void;
}

/** Background heartbeat so the ~2 min idle reaper never kills a long-running driven session. */
function startKeepalive(sandbox: { keepalive(): Promise<void> }, intervalMs = 30_000): Keepalive {
  const timer = setInterval(() => {
    sandbox.keepalive().catch(() => {});
  }, intervalMs);
  timer.unref?.();
  return { stop: () => clearInterval(timer) };
}

export interface MacSession {
  mac: MacOSSandbox;
  keepalive: Keepalive;
  close(): Promise<void>;
}

export interface IosSession {
  ios: IOSSandbox;
  keepalive: Keepalive;
  close(): Promise<void>;
}

/** Boot a macOS sandbox with keepalive; caller must await close(). */
export async function macSession(): Promise<MacSession> {
  const mac = await client().create({ type: "macos" });
  const keepalive = startKeepalive(mac);
  return {
    mac,
    keepalive,
    close: async () => {
      keepalive.stop();
      await mac.close().catch(() => {});
    },
  };
}

/** Boot an iOS simulator sandbox with keepalive. */
export async function iosSession(family = "iphone"): Promise<IosSession> {
  const ios = await client().create({ type: "ios", family });
  const keepalive = startKeepalive(ios);
  return {
    ios,
    keepalive,
    close: async () => {
      keepalive.stop();
      await ios.close().catch(() => {});
    },
  };
}

export const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

export type AppearanceMode = 'system' | 'dark' | 'light';

const APPEARANCE_KEY = 'capture.appearanceMode';
const OBSIDIAN_SETTINGS_KEY = 'capture.obsidianSettings';

export interface ObsidianSettings {
  enabled: boolean;
  vault: string;
  summaryFolder: string;
  cliCommand: string;
}

const DEFAULT_OBSIDIAN_SETTINGS: ObsidianSettings = {
  enabled: false,
  vault: '',
  summaryFolder: 'Capture/Summaries',
  cliCommand: 'obsidian',
};

export function getAppearance(): AppearanceMode {
  const raw = localStorage.getItem(APPEARANCE_KEY);
  return raw === 'system' || raw === 'dark' || raw === 'light' ? raw : 'dark';
}

export function applyAppearance(mode: AppearanceMode): void {
  document.documentElement.dataset.appearance = mode;
}

export function setAppearance(mode: AppearanceMode): void {
  localStorage.setItem(APPEARANCE_KEY, mode);
  applyAppearance(mode);
}

export function getObsidianSettings(): ObsidianSettings {
  const raw = localStorage.getItem(OBSIDIAN_SETTINGS_KEY);
  if (!raw) return DEFAULT_OBSIDIAN_SETTINGS;
  try {
    const parsed = JSON.parse(raw) as Partial<ObsidianSettings>;
    return {
      enabled: parsed.enabled === true,
      vault: typeof parsed.vault === 'string' ? parsed.vault : '',
      summaryFolder: typeof parsed.summaryFolder === 'string' && parsed.summaryFolder.trim()
        ? parsed.summaryFolder
        : DEFAULT_OBSIDIAN_SETTINGS.summaryFolder,
      cliCommand: typeof parsed.cliCommand === 'string' && parsed.cliCommand.trim()
        ? parsed.cliCommand
        : DEFAULT_OBSIDIAN_SETTINGS.cliCommand,
    };
  } catch {
    return DEFAULT_OBSIDIAN_SETTINGS;
  }
}

export function setObsidianSettings(settings: ObsidianSettings): void {
  localStorage.setItem(OBSIDIAN_SETTINGS_KEY, JSON.stringify({
    enabled: settings.enabled,
    vault: settings.vault.trim(),
    summaryFolder: settings.summaryFolder.trim() || DEFAULT_OBSIDIAN_SETTINGS.summaryFolder,
    cliCommand: settings.cliCommand.trim() || DEFAULT_OBSIDIAN_SETTINGS.cliCommand,
  }));
}

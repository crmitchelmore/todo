export type AppearanceMode = 'system' | 'dark' | 'light';

const APPEARANCE_KEY = 'capture.appearanceMode';

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

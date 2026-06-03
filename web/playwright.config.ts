import { defineConfig, devices } from '@playwright/test';

const baseURL = process.env.E2E_BASE_URL ?? 'http://127.0.0.1:3030';
const hasExternalBase = Boolean(process.env.E2E_BASE_URL);

export default defineConfig({
  testDir: './e2e',
  timeout: 30_000,
  expect: { timeout: 5_000 },
  outputDir: process.env.UI_ARTIFACT_DIR ?? 'test-results',
  reporter: process.env.CI ? [['github'], ['html', { open: 'never' }]] : [['list']],
  use: {
    baseURL,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  webServer: hasExternalBase
    ? undefined
    : {
        command: 'npm run preview -- --host 127.0.0.1',
        url: baseURL,
        reuseExistingServer: !process.env.CI,
        timeout: 120_000,
      },
  projects: [
    {
      name: 'desktop-chrome',
      use: { channel: 'chrome', viewport: { width: 1440, height: 1000 } },
    },
    {
      name: 'mobile-chrome',
      use: {
        ...devices['Pixel 7'],
        channel: 'chrome',
      },
    },
  ],
});

import { defineConfig } from '@playwright/test';

const configuredBaseURL = process.env.OPENSEEK_DESKTOP_BROWSER_BASE_URL;
const baseURL = configuredBaseURL || 'http://127.0.0.1:5175';
const serverPort = new URL(baseURL).port || '5175';
const isCI = Boolean(process.env.CI);

// Keep loopback traffic away from a configured HTTP proxy. Otherwise
// Playwright can mistake a proxy response for the local fixture server.
const loopback = ['127.0.0.1', 'localhost'];
for (const name of ['NO_PROXY', 'no_proxy']) {
  process.env[name] = [process.env[name], ...loopback].filter(Boolean).join(',');
}

export default defineConfig({
  testDir: 'tests',
  outputDir: 'test-results',
  timeout: 30_000,
  forbidOnly: isCI,
  retries: isCI ? 1 : 0,
  workers: 1,
  reporter: [
    ['list'],
    ['html', { outputFolder: 'playwright-report', open: 'never' }],
  ],
  use: {
    baseURL,
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
    viewport: { width: 1440, height: 900 },
  },
  webServer: {
    // Serve Desktop's own tree so the suite exercises the browser artifacts
    // staged by the real Desktop packager, not a test-only copy of the UI.
    command: `python3 -m http.server ${serverPort} --bind 127.0.0.1 --directory ..`,
    url: `${baseURL}/dist/browser/index.html`,
    reuseExistingServer: Boolean(configuredBaseURL) || !isCI,
    timeout: 60_000,
  },
});

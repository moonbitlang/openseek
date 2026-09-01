import { defineConfig } from '@playwright/test';

const configuredBaseURL = process.env.OPENSEEK_VIZ_BROWSER_BASE_URL;
const baseURL = configuredBaseURL || 'http://127.0.0.1:5176';
const serverPort = new URL(baseURL).port || '5176';
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
    // The shell lives at the repository root because viz_server serves it
    // directly. The test still builds and owns the cmd/viz_app bundle here.
    command: `python3 -m http.server ${serverPort} --bind 127.0.0.1 --directory ../../..`,
    url: `${baseURL}/web/index.html`,
    reuseExistingServer: Boolean(configuredBaseURL) || !isCI,
    timeout: 60_000,
  },
});

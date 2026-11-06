import { defineConfig } from '@playwright/test';

// Specs against the real headless app-server (`real/`), not the fake
// transport. Each worker starts its own server, which serves the built
// browser bundle itself, so there is no web server to configure here.
// Build first: `just test-browser-real-build` in desktop/.
const loopback = ['127.0.0.1', 'localhost'];
for (const name of ['NO_PROXY', 'no_proxy']) {
  process.env[name] = [process.env[name], ...loopback].filter(Boolean).join(',');
}

export default defineConfig({
  testDir: 'real',
  outputDir: 'test-results/real',
  timeout: 30_000,
  forbidOnly: Boolean(process.env.CI),
  retries: 0,
  fullyParallel: true,
  workers: process.env.CI ? 4 : '50%',
  projects: [{ name: 'chromium', use: { browserName: 'chromium' } }],
  reporter: [['list']],
  use: {
    screenshot: 'only-on-failure',
    viewport: { width: 1440, height: 900 },
  },
});

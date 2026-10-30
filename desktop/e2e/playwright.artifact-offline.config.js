import { defineConfig } from '@playwright/test';

// DesktopBrowserHarness fulfills asset and transport requests in the browser.
export default defineConfig({
  testDir: './tests',
  testMatch: ['transcript_artifact_files.spec.js', 'artifact_context.spec.js'],
  timeout: 45_000,
  workers: 1,
  reporter: 'list',
  use: { baseURL: 'http://127.0.0.1:5175', headless: true },
});

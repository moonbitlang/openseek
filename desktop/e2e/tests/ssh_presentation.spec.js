import { test, expect } from '@playwright/test';
import { SshBrowserHarness } from './support/ssh_browser_harness.js';

const warning = [
  '@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@',
  '@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @',
  '@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@',
  'ED25519 fingerprint: SHA256:abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789',
].join('\n');

async function start(page) {
  const app = new SshBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openRemoteProject();
  await expect.poll(() => app.attempt).toBe(1);
  return app;
}

async function expectContained(locator) {
  const fits = await locator.evaluate(el => {
    const rect = el.getBoundingClientRect();
    const parent = el.parentElement.getBoundingClientRect();
    return rect.left >= parent.left && rect.right <= parent.right &&
      rect.left >= 0 && rect.right <= innerWidth;
  });
  expect(fits).toBe(true);
}

test('SSH failure output scrolls without widening the page and narrow retry remains usable', async ({ page }, testInfo) => {
  const app = await start(page);
  await app.sshEvent({ disconnected: warning });
  await expect(page.locator('.onboarding-card')).toContainText('Connection failed');
  const error = page.locator('.onboarding-card .ssh-error');
  await expect(error).toHaveText(warning);
  await expect(error).toHaveCSS('white-space', 'pre');
  await expectContained(error);
  expect(await error.evaluate(el => el.scrollWidth > el.clientWidth)).toBe(true);
  await page.screenshot({ path: testInfo.outputPath('ssh-failure.png') });

  await page.setViewportSize({ width: 900, height: 700 });
  const retry = page.getByRole('button', { name: 'Retry connection', exact: true });
  await expectContained(retry);
  await expect(page.getByRole('status', { name: 'Connection failed', exact: true })).toBeVisible();
  await page.screenshot({ path: testInfo.outputPath('ssh-narrow-retry.png') });
  await retry.click();
  await expect.poll(() => app.attempt).toBe(2);
  await expect(page.locator('.onboarding-card')).toContainText('Connecting…');
  await page.getByRole('button', { name: 'Cancel connection', exact: true }).click();
  await expect(page.locator('.onboarding-card')).toContainText('Disconnected');
  expect(app.pageErrors).toEqual([]);
});

test('SSH host identity keeps fingerprint lines scrollable and confirmation controls reachable', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 900, height: 700 });
  const app = await start(page);
  const prompt = 'The authenticity of host example.test cannot be established.\n' +
    'ED25519 key fingerprint is SHA256:abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.\n' +
    'Are you sure you want to continue connecting (yes/no/[fingerprint])?';
  await app.sshEvent({ authentication: { request_id: 1, kind: 'confirm', prompt, retry: false } });
  const dialog = page.getByRole('dialog');
  const output = dialog.locator('.ssh-output');
  await expect(output).toHaveText(prompt);
  await expect(output).toHaveCSS('white-space', 'pre');
  await expectContained(output);
  expect(await output.evaluate(el => el.scrollWidth > el.clientWidth)).toBe(true);
  const accept = dialog.getByRole('button', { name: 'Accept', exact: true });
  await expectContained(accept);
  await page.screenshot({ path: testInfo.outputPath('ssh-fingerprint.png') });
  await accept.click();
  await expect.poll(() => app.requests.some(r => r.method === 'ssh.auth.respond')).toBe(true);
  expect(app.pageErrors).toEqual([]);
});

test('SSH terminal stops claiming recovery after failure or cancellation in a narrow main pane', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 1200, height: 800 });
  await page.addInitScript(() => localStorage.setItem('openseek.theme', 'dark'));
  const app = await start(page);
  await app.sshEvent({ method: 'agent.connected', params: { protocol: app.hostProtocol } });
  await expect(page.locator('.ssh-status')).toContainText('Connected');
  await page.getByTitle('Show terminal (Ctrl+`)').click();
  await expect(page.locator('.terminal-panel')).toBeVisible();
  // Open the editor to narrow main without crossing the mobile breakpoint.
  await page.getByRole('button', { name: 'Show panel', exact: true }).click();
  await expect.poll(async () => (await page.locator('main').boundingBox()).width).toBeLessThan(700);
  await app.sshEvent({ disconnected: 'Connection lost' });
  await expect.poll(() => app.attempt).toBe(2);
  await expect(page.locator('.terminal-status')).toHaveText('Connecting…');
  await app.sshEvent({ disconnected: 'Connection refused' });
  await expect(page.locator('.terminal-status')).toHaveText('Connection failed');
  const retry = page.getByRole('button', { name: 'Retry connection', exact: true });
  await expectContained(retry);
  await page.screenshot({ path: testInfo.outputPath('ssh-terminal-failed-dark.png') });
  await retry.click();
  await expect.poll(() => app.attempt).toBe(3);
  await page.getByRole('button', { name: 'Cancel connection', exact: true }).click();
  await expect(page.locator('.terminal-status')).toHaveText('Disconnected');
  expect(app.pageErrors).toEqual([]);
});

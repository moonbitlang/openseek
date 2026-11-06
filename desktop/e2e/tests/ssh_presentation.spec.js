import { test, expect } from './support/test.js';
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

test('SSH failure preserves the diagnostic and supports retry and cancellation', async ({ page }) => {
  const app = await start(page);
  await app.sshEvent({ disconnected: warning });
  await expect(page.locator('.onboarding-card')).toContainText('Connection failed');
  const error = page.locator('.onboarding-card .ssh-error');
  await expect(error).toHaveText(warning);

  const retry = page.locator('[data-ssh-connection]:visible');
  await expect(page.locator('.ssh-status:visible')).toBeVisible();
  await retry.click();
  await expect.poll(() => app.attempt).toBe(2);
  await expect(page.locator('.onboarding-card')).toContainText('Connecting…');
  await page.locator('[data-ssh-connection]:visible').click();
  await expect(page.locator('.onboarding-card')).toContainText('Disconnected');
  expect(app.pageErrors).toEqual([]);
});

test('SSH host identity confirmation sends the authentication response', async ({ page }) => {
  const app = await start(page);
  const prompt = 'The authenticity of host example.test cannot be established.\n' +
    'ED25519 key fingerprint is SHA256:abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.\n' +
    'Are you sure you want to continue connecting (yes/no/[fingerprint])?';
  await app.sshEvent({ authentication: { request_id: 1, kind: 'confirm', prompt, retry: false } });
  const dialog = page.getByRole('dialog');
  const output = dialog.locator('.ssh-output');
  await expect(output).toHaveText(prompt);
  const accept = dialog.locator('#ssh-auth-continue');
  await accept.click();
  await expect.poll(() => app.requests.some(r => r.method === 'ssh.auth.respond')).toBe(true);
  expect(app.pageErrors).toEqual([]);
});

test('SSH terminal stops claiming recovery after failure or cancellation', async ({ page }) => {
  await page.addInitScript(() => localStorage.setItem('openseek.theme', 'dark'));
  const app = await start(page);
  await app.sshEvent({ method: 'agent.connected', params: { protocol: app.hostProtocol } });
  await expect(page.locator('.ssh-status.online:visible')).toBeVisible();
  await page.locator('#terminal-toggle').click();
  await expect(page.locator('.terminal-panel')).toBeVisible();
  await app.sshEvent({ disconnected: 'Connection lost' });
  await expect.poll(() => app.attempt).toBe(2);
  await expect(page.locator('.terminal-status')).toHaveText('Connecting…');
  await app.sshEvent({ disconnected: 'Connection refused' });
  await expect(page.locator('.terminal-status')).toHaveText('Connection failed');
  const retry = page.locator('[data-ssh-connection]:visible');
  await retry.click();
  await expect.poll(() => app.attempt).toBe(3);
  await page.locator('[data-ssh-connection]:visible').click();
  await expect(page.locator('.terminal-status')).toHaveText('Disconnected');
  expect(app.pageErrors).toEqual([]);
});

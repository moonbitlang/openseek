import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test.use({ viewport: { width: 393, height: 851 }, isMobile: true, hasTouch: true });

test('one connection notice replaces pending inventory failures and preserves the draft', async ({ page }, info) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await page.locator('.sidebar-toggle').click();
  await app.openSession();
  await page.locator('#task').fill('Keep this unsent draft');
  await page.locator('#task').focus();
  const draft = await page.locator('#task').elementHandle();
  const original = app.replyFor.bind(app);
  const pending = [];
  app.replyFor = request => {
    if (['session.list', 'worktree.list'].includes(request.method)) {
      pending.push(request.method);
      return new Promise(() => {});
    }
    return original(request);
  };
  app.notify('workspace.changed', { workspaces: ['/workspace', ...Array.from({ length: 8 }, (_, i) => `/project-${i}`)] });
  app.notify('session.changed', { change: 'created', session: 'new-session', workspace: '/workspace' });
  await expect.poll(() => pending.filter(m => m === 'worktree.list').length).toBeGreaterThanOrEqual(8);
  await expect.poll(() => pending.includes('session.list')).toBe(true);
  app.connectionAvailable = false;
  app.socket.close({ code: 1001, reason: 'fixture offline' });
  await expect(page.locator('#task')).toHaveValue('Keep this unsent draft');
  await page.waitForTimeout(250);
  await page.screenshot({ path: info.outputPath('disconnected.png') });
  await expect(page.locator('.notification')).toHaveCount(0);
  const banner = page.locator('.composer-banner:visible');
  await expect(banner).toHaveCount(1);
  await expect(banner).toContainText(/reconnecting/i);
  await expect(page.locator('.run-status')).toContainText('Reconnecting');
  await expect(banner).toHaveAttribute('role', 'status');
  await expect(page.locator('#send')).toBeDisabled();
  expect(await draft.evaluate(el => el === document.querySelector('#task'))).toBe(true);
  await expect(page.locator('#task')).toBeFocused();
  const bounds = await banner.boundingBox();
  expect(bounds.height).toBeLessThan(100);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  // A longer outage stays compact; reconnect restores readiness without a send.
  await page.waitForTimeout(2200);
  await expect(banner).toHaveCount(1);
  await expect(page.locator('.notification')).toHaveCount(0);
  app.replyFor = original;
  app.connectionAvailable = true;
  await expect(banner).toHaveCount(0, { timeout: 15000 });
  await expect(page.locator('#send')).toBeEnabled();
  await expect(page.locator('#task')).toHaveValue('Keep this unsent draft');
  expect(app.requests.filter(r => r.method === 'agent.start')).toHaveLength(0);
  expect(app.pageErrors).toEqual([]);
});

test('a host rejection with connection-like wording is still reported', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  // The Cloud-capable shell renders before a device socket is connected.
  await expect.poll(() => app.socket !== null).toBe(true);
  app.rpcErrors.set('worktree.list', 'SeekMoon connection lost');
  app.notify('workspace.changed', { workspaces: ['/workspace', '/rejected-project'] });
  await expect(page.locator('.notification').filter({ hasText: '/rejected-project' })).toContainText('SeekMoon connection lost');
  expect(app.pageErrors).toEqual([]);
});

test('Codex drafts use the same reconnecting notice and cannot send offline', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.codexModels = [{ id: 'gpt-test', displayName: 'Codex offline', isDefault: true }];
  await app.install();
  await app.goto();
  await page.getByRole('button', { name: 'Model', exact: true }).click();
  await page.getByRole('option', { name: 'Codex offline', exact: true }).click();
  await expect(page.locator('#task')).toHaveAttribute('placeholder', /Ask Codex/);
  await page.locator('#task').fill('Keep this Codex draft');
  app.connectionAvailable = false;
  app.socket.close({ code: 1001, reason: 'fixture offline' });
  await expect(page.locator('.composer-banner:visible')).toHaveCount(1);
  await expect(page.locator('#send')).toBeDisabled();
  await expect(page.locator('#task')).toHaveValue('Keep this Codex draft');
  app.connectionAvailable = true;
  await expect(page.locator('.composer-banner:visible')).toHaveCount(0, { timeout: 15000 });
  await expect(page.locator('#send')).toBeEnabled();
  await expect(page.locator('#task')).toHaveValue('Keep this Codex draft');
  expect(app.requests.filter(r => r.method === 'codex.turn.start')).toHaveLength(0);
  expect(app.pageErrors).toEqual([]);
});

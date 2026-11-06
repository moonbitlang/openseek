import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test.use({ viewport: { width: 393, height: 851 }, isMobile: true, hasTouch: true });

test('one connection notice replaces pending inventory failures and preserves the draft', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  // Startup shows "Open a project" until workspace.list answers, then moves
  // to New chat. On a narrow layout that screen change closes the drawer, so
  // open it only once startup has settled.
  await page.locator('#empty-project-trigger').waitFor();
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
  await expect(page.locator('.notification')).toHaveCount(0);
  const banner = page.locator('.composer-banner:visible');
  await expect(banner).toHaveCount(1);
  await expect(banner).toContainText(/reconnecting/i);
  await expect(page.locator('.run-status')).toContainText('Reconnecting');
  await expect(banner).toHaveAttribute('role', 'status');
  await expect(page.locator('#send')).toBeDisabled();
  expect(await draft.evaluate(el => el === document.querySelector('#task'))).toBe(true);
  await expect(page.locator('#task')).toBeFocused();
  // An ongoing outage keeps one notice; reconnect restores readiness without a send.
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
  await expect(page.locator('.notifications > .notification')).toContainText(['/rejected-project: SeekMoon connection lost']);
  expect(app.pageErrors).toEqual([]);
});

test('Codex drafts use the same reconnecting notice and cannot send offline', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.codexModels = [{ id: 'gpt-test', displayName: 'Codex offline', isDefault: true }];
  await app.install();
  await app.goto();
  await page.locator('#openseek-model-picker').click();
  await page.locator('[role="option"][data-value="codex:gpt-test"]').click();
  await expect(page.locator('#codex-model-picker')).toHaveAttribute('data-value', 'codex:gpt-test');
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

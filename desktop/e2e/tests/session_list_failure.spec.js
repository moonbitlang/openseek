import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

for (const failure of ['reply', 'transport']) {
  test(`a workspace list ${failure} failure on startup displays the cause`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    const message = 'the workspace list is malformed: expected a JSON object';
    if (failure === 'reply') {
      app.onRpc('workspace.list', () => ({ error: message }));
    } else {
      app.rpcErrors.set('workspace.list', message);
    }
    await app.install();
    await app.goto();
    await expect(page.getByText(`Workspace error: ${message}`, { exact: true }).first()).toBeVisible();
  });
}

test('a failed project listing reports its cause and keeps previously loaded conversations', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  const conversation = page.locator('.conversation-row[title="session-1"]');
  await expect(conversation).toBeVisible();

  let failed = true;
  app.onRpc('session.list', (_request, next) => failed
    ? { groups: [{ workspace: '/workspace', name: 'workspace', session_root: '/workspace/.openseek', sessions: [], error: 'failed to run engine: file not found' }] }
    : next());
  app.notify('session.changed', { change: 'created', session: 'session-1', workspace: '/workspace' });
  await expect(page.getByText('Session list unavailable: /workspace: failed to run engine: file not found', { exact: true }).first()).toBeVisible();
  await expect(conversation).toBeVisible();

  // A later successful, empty reply really does remove the old inventory.
  failed = false;
  app.liveSessions = [];
  app.notify('session.changed', { change: 'created', session: 'session-1', workspace: '/workspace' });
  await expect(conversation).toHaveCount(0);
});

test('a project listing failure on startup is reported', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.onRpc('session.list', () => ({
    groups: [{ workspace: '/workspace', name: 'workspace', session_root: '/workspace/.openseek', sessions: [], error: 'failed to run engine: file not found' }],
  }));
  await app.install();
  await app.goto();
  await expect(page.getByText('Session list unavailable: /workspace: failed to run engine: file not found', { exact: true }).first()).toBeVisible();
});

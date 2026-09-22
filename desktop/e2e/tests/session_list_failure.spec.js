import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('a failed project listing reports its cause and keeps previously loaded conversations', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  const conversation = page.locator('.conversation-row[title="session-1"]');
  await expect(conversation).toBeVisible();

  const replyFor = app.replyFor.bind(app);
  let failed = true;
  app.replyFor = request => request.method === 'session.list' && failed
    ? { groups: [{ workspace: '/workspace', name: 'workspace', session_root: '/workspace/.openseek', sessions: [], error: 'failed to run engine: file not found' }] }
    : replyFor(request);
  app.notify('session.changed', { change: 'created', session: 'session-1', workspace: '/workspace' });
  await expect(page.getByText('Session list unavailable: /workspace: failed to run engine: file not found', { exact: true }).first()).toBeVisible();
  await expect(conversation).toBeVisible();

  // A later successful, empty reply really does remove the old inventory.
  failed = false;
  app.liveSessions = [];
  app.notify('session.changed', { change: 'created', session: 'session-1', workspace: '/workspace' });
  await expect(conversation).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('a project listing failure on startup is reported', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  const replyFor = app.replyFor.bind(app);
  app.replyFor = request => request.method === 'session.list'
    ? { groups: [{ workspace: '/workspace', name: 'workspace', session_root: '/workspace/.openseek', sessions: [], error: 'failed to run engine: file not found' }] }
    : replyFor(request);
  await app.install();
  await app.goto();
  await expect(page.getByText('Session list unavailable: /workspace: failed to run engine: file not found', { exact: true }).first()).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

async function expectHeader(page, title) {
  const header = page.locator('main > .topbar');
  await expect(header).toHaveCount(1);
  await expect(header.getByRole('heading', { level: 1 })).toHaveText(title);
  await expect(page.locator('.window-titlebar-drag-strip')).toHaveCount(0);
  const bounds = await header.boundingBox();
  expect(bounds.height).toBeGreaterThan(30);
  await expect.poll(() => page.locator('main').evaluate(main => {
    const header = main.querySelector('.topbar');
    const body = header.nextElementSibling;
    return body.getBoundingClientRect().top >= header.getBoundingClientRect().bottom - 1;
  })).toBe(true);
}

test('empty projects and settings pages share one persistent header', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  app.workspaces = [];
  app.liveSessions = [];
  await app.install();
  await app.goto();
  await expectHeader(page, 'SeekMoon');
  const original = await page.locator('main > .topbar').elementHandle();
  for (const [button, title] of [['Settings', 'Settings'], ['Skills', 'Skills'], ['Scheduled', 'Scheduled tasks']]) {
    await page.getByRole('button', { name: button, exact: true }).click();
    await expectHeader(page, title);
    expect(await original.evaluate(node => node === document.querySelector('main > .topbar'))).toBe(true);
    await expect(page.locator('main h1')).toHaveCount(1);
  }
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await page.screenshot({ path: testInfo.outputPath('settings-header.png') });
  await page.setViewportSize({ width: 390, height: 844 });
  await expectHeader(page, 'Settings');
  expect(app.pageErrors).toEqual([]);
});

test('loading and failure retain the selected conversation title', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.liveSessions.push({ id: 'session-2', title: 'Second conversation', updated_at_ms: 2 });
  await app.install();
  await app.goto();
  await page.locator('.conversation-row[title="session-1"]').click();
  await expect(page.getByText('Browser result', { exact: true })).toBeVisible();
  const original = await page.locator('main > .topbar').elementHandle();
  app.rpcDelays.set('session.load', 700);
  app.rpcErrors.set('session.load', 'fixture unavailable');
  await page.locator('.conversation-row[title="session-2"]').click();
  await expect(page.getByText('Loading conversation…', { exact: true })).toBeVisible();
  await expectHeader(page, 'Second conversation');
  await expect(page.getByText('Could not load conversation', { exact: true })).toBeVisible();
  await expectHeader(page, 'Second conversation');
  expect(await original.evaluate(node => node === document.querySelector('main > .topbar'))).toBe(true);
  app.rpcErrors.delete('session.load');
  await page.getByRole('button', { name: 'Retry', exact: true }).click();
  await expect(page.getByText('Browser result', { exact: true })).toBeVisible();
  await expect(page.locator('main > .topbar h1')).not.toHaveText('SeekMoon');
  expect(await original.evaluate(node => node === document.querySelector('main > .topbar'))).toBe(true);
  expect(app.pageErrors).toEqual([]);
});

test('workspace settings dialog preserves the Codex shell header', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.codexModels = [{ id: 'gpt-5.4-codex', displayName: 'GPT-5.4 Codex', isDefault: true,
    defaultReasoningEffort: 'medium', supportedReasoningEfforts: [{ reasoningEffort: 'medium', description: 'Balanced' }] }];
  await app.install();
  await app.goto();
  const original = await page.locator('main > .topbar').elementHandle();
  await page.getByRole('button', { name: 'Model', exact: true }).click();
  await page.getByRole('option', { name: 'GPT-5.4 Codex' }).click();
  await expect(page.locator('main > .codex-topbar')).toBeVisible();
  await expectHeader(page, 'New chat');
  expect(await original.evaluate(node => node === document.querySelector('main > .topbar'))).toBe(true);
  await page.locator('.workspace-row', { hasText: 'workspace' }).hover();
  await page.getByTitle('More actions').click();
  await page.getByRole('menuitem', { name: 'Workspace settings' }).click();
  const dialog = page.getByRole('dialog', { name: 'Workspace settings' });
  await expect(dialog).toBeVisible();
  await expect(dialog).toHaveJSProperty('open', true);
  await expect(dialog.getByRole('heading', { name: 'Workspace settings', level: 2 })).toBeVisible();
  await expect(dialog.locator('.workspace-settings-name')).toHaveText('workspace');
  await expect(dialog.locator('.settings-subtitle')).toHaveText('/workspace');
  await expect(page.locator('main > .codex-topbar h1')).toHaveText('New chat');
  expect(await original.evaluate(node => node === document.querySelector('main > .topbar'))).toBe(true);
  await dialog.getByRole('button', { name: 'Close workspace settings', exact: true }).click();
  await expect(dialog).toBeHidden();
  await expectHeader(page, 'New chat');
  await expect(page.locator('main > .codex-topbar')).toBeVisible();
  expect(await original.evaluate(node => node === document.querySelector('main > .topbar'))).toBe(true);
  expect(app.pageErrors).toEqual([]);
});

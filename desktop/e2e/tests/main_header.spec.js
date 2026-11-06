import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

async function expectHeader(page, title) {
  const header = page.locator('main > .topbar');
  await expect(header).toHaveCount(1);
  await expect(header.getByRole('heading', { level: 1 })).toHaveText(title);
}

test('management dialogs preserve the empty project header', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.workspaces = [];
  app.liveSessions = [];
  await app.install();
  await app.goto();
  await expectHeader(page, 'SeekMoon');
  const original = await page.locator('main > .topbar').elementHandle();
  for (const [button, title] of [['#sidebar-settings', 'Settings'], ['#sidebar-skills', 'Skills'], ['#sidebar-schedules', 'Scheduled tasks']]) {
    await page.locator(button).click();
    await expect(page.getByRole('dialog')).toHaveAccessibleName(title);
    expect(await original.evaluate(node => node === document.querySelector('main > .topbar'))).toBe(true);
    await expect(page.locator('main h1')).toHaveCount(1);
    await page.getByRole('dialog').locator('[data-slot="dialog-close"]').click();
    await expectHeader(page, 'SeekMoon');
  }
  expect(app.pageErrors).toEqual([]);
});

test('loading and failure retain the selected conversation title', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.liveSessions.push({ id: 'session-2', title: 'Second conversation', updated_at_ms: 2 });
  await app.install();
  await app.goto();
  await app.sessionRow('session-1').click();
  await expect(page.locator('#transcript')).toContainText('Browser result');
  const original = await page.locator('main > .topbar').elementHandle();
  app.rpcDelays.set('session.load', 700);
  app.rpcErrors.set('session.load', 'fixture unavailable');
  await app.sessionRow('session-2').click();
  await expect(page.locator('#conversation-loading')).toBeVisible();
  await expectHeader(page, 'Second conversation');
  await expect(page.locator('#conversation-load-error')).toBeVisible();
  await expectHeader(page, 'Second conversation');
  expect(await original.evaluate(node => node === document.querySelector('main > .topbar'))).toBe(true);
  app.rpcErrors.delete('session.load');
  await page.locator('#conversation-load-retry').click();
  await expect(page.locator('#transcript')).toContainText('Browser result');
  await expect(page.locator('main > .topbar h1')).not.toHaveText('SeekMoon');
  expect(await original.evaluate(node => node === document.querySelector('main > .topbar'))).toBe(true);
  const title = await page.locator('main > .topbar h1').textContent();
  const composer = page.locator('#task');
  await composer.fill('Keep my unfinished draft');
  for (const selector of ['#sidebar-settings', '#sidebar-skills', '#sidebar-schedules']) {
    await page.locator(selector).click();
    await expect(page.getByRole('dialog')).toBeVisible();
    await page.keyboard.press('Escape');
    await expect(page.getByRole('dialog')).not.toBeVisible();
  }
  await expectHeader(page, title);
  await expect(composer).toHaveValue('Keep my unfinished draft');
  expect(await original.evaluate(node => node === document.querySelector('main > .topbar'))).toBe(true);
  expect(app.pageErrors).toEqual([]);
});

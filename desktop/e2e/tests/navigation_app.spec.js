import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('dialogs remain reachable in narrow and native titlebars', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install(); await app.goto();
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  const dialog = page.getByRole('dialog', { name: 'Settings', exact: true });
  await expect(dialog).toBeVisible();
  const general = dialog.getByRole('tab', { name: 'General', exact: true });
  const runtime = dialog.getByRole('tabpanel', { name: 'Engine', exact: true });
  for (const width of [1440, 390]) {
    await page.setViewportSize({ width, height: 844 });
    await expect(dialog.getByRole('tablist')).toHaveAttribute('aria-orientation', width === 390 ? 'horizontal' : 'vertical');
    await general.click();
    const next = width === 390 ? 'ArrowRight' : 'ArrowDown';
    await general.press(next);
    const engine = dialog.getByRole('tab', { name: 'Engine', exact: true });
    await expect(engine).toBeFocused();
    await expect(engine).toHaveAttribute('aria-selected', 'true');
    await engine.press(next);
    const account = dialog.getByRole('tab', { name: 'Account', exact: true });
    await expect(account).toBeFocused();
    await expect(account).toHaveAttribute('aria-selected', 'true');
    await account.press(width === 390 ? 'ArrowLeft' : 'ArrowUp');
    await expect(runtime).toBeVisible();
    const key = runtime.getByLabel('API key', { exact: true });
    await key.fill('unfinished-settings-key');
    const field = await key.elementHandle();
    await general.click();
    await expect(runtime).not.toBeVisible();
    await dialog.getByRole('tab', { name: 'Engine', exact: true }).click();
    await expect(key).toHaveValue('unfinished-settings-key');
    expect(await field.evaluate(node => node.isConnected)).toBe(true);
    await expect(dialog.getByRole('button', { name: 'Dismiss', exact: true })).toBeInViewport();
    expect(await dialog.evaluate(node => node.scrollWidth <= node.clientWidth)).toBe(true);
    expect(await runtime.evaluate(node => node.scrollWidth <= node.clientWidth)).toBe(true);
    await runtime.evaluate(node => { node.scrollTop = node.scrollHeight; });
    await expect(dialog.getByRole('tablist')).toBeInViewport();
    expect(await dialog.locator('.dialog-scroll-body').evaluate(node => node.scrollTop)).toBe(0);
  }
  await dialog.getByRole('button', { name: 'Dismiss', exact: true }).click();
  await page.setViewportSize({ width: 1440, height: 844 });
  await expect(page.locator('.sidebar-backdrop')).toHaveCount(0);
  await expect.poll(() => page.locator('.app').evaluate(node => node.getAnimations().length)).toBe(0);
  await page.evaluate(() => {
    document.documentElement.style.setProperty('--native-titlebar-left', '84px');
    document.documentElement.style.setProperty('--native-titlebar-height', '28px');
    document.querySelector('.app').style.setProperty('--sidebar-width', '220px');
  });
  const toggle = await page.locator('.sidebar-toggle').boundingBox();
  const mode = await page.locator('.sidebar-mode').boundingBox();
  expect(toggle.x).toBeGreaterThanOrEqual(84);
  expect(mode.x).toBeGreaterThanOrEqual(toggle.x + toggle.width);
  const sidebar = await page.locator('aside').boundingBox();
  expect(mode.x + mode.width).toBeLessThanOrEqual(sidebar.x + sidebar.width);
  expect(app.pageErrors).toEqual([]);
});

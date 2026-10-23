import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

// Exercise the browser packager's normal HTML, CSS and frontend bundle.
// Only the remote account and host responses contain fixture data.
async function installConsole(page) {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  return app;
}

async function assertFits(page) {
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
}

test.use({ viewport: { width: 393, height: 851 }, isMobile: true, hasTouch: true });

test('a signed-out device page offers login and preserves the page return path', async ({ page }, info) => {
  const app = await installConsole(page);
  await page.route('**/v2/auth/me', route => route.fulfill({ status: 401 }));
  await page.goto('/device/device-a/chat');
  await expect(page.getByRole('link', { name: 'Sign in with GitHub' })).toHaveAttribute('href',
    '/v2/auth/login?prompt=select_account&return_to=%2Fdevice%2Fdevice-a%2Fchat');
  expect(app.socket).toBeNull();
  await assertFits(page);
  await page.screenshot({ path: info.outputPath('login.png') });
  await page.route('**/v2/auth/login?*', route => route.fulfill({ contentType: 'text/html', body: '<h1>OAuth fixture</h1>' }));
  await page.getByRole('link', { name: 'Sign in with GitHub' }).click();
  await expect(page.getByRole('heading', { name: 'OAuth fixture' })).toBeVisible();
  await expect(page).toHaveURL(/\/v2\/auth\/login\?/);
  expect(app.pageErrors).toEqual([]);
});

test('the sidebar selector lists only online devices and switches between them', async ({ page }, info) => {
  const app = await installConsole(page);
  await page.route('**/v2/devices', route => route.fulfill({ json: { devices: [
    { id: 'device-a', name: 'Test Mac', online: true },
    { id: 'offline', name: 'Office computer', online: false },
    { id: 'device-b', name: 'Studio', online: true },
  ] } }));
  // A Cloud page has no device yet; the selector says so and connects nothing.
  await page.goto('/cloud');
  await page.locator('.sidebar-toggle').click();
  const selector = page.getByRole('button', { name: 'Choose a device', exact: true });
  await expect(selector).toContainText('Choose a device');
  expect(app.socket).toBeNull();
  await selector.click();
  await expect(page.getByRole('menuitem', { name: 'Test Mac', exact: true })).toBeEnabled();
  await expect(page.getByRole('menuitem', { name: 'Studio', exact: true })).toBeEnabled();
  await expect(page.getByRole('menuitem', { name: 'Office computer' })).toHaveCount(0);
  await page.getByRole('menuitem', { name: 'Test Mac', exact: true }).click();
  await expect(page).toHaveURL(/\/device\/device-a\/chat(\/new)?$/);
  await expect.poll(() => app.socket !== null).toBe(true);
  // On a device page it names that device and checks it in the menu.
  await page.locator('.sidebar-toggle').click();
  await expect(selector).toContainText('Test Mac');
  await expect.poll(async () => Math.abs((await page.locator('aside').boundingBox()).x)).toBeLessThan(1);
  await page.screenshot({ path: info.outputPath('drawer.png'), animations: 'disabled' });
  await selector.click();
  await expect(page.getByRole('menuitem', { name: 'Test Mac', exact: true })).toBeDisabled();
  await expect(page.getByRole('menuitem', { name: 'Office computer' })).toHaveCount(0);
  await assertFits(page);
  await page.screenshot({ path: info.outputPath('device-selector.png'), animations: 'disabled' });
  await page.getByRole('menuitem', { name: 'Studio', exact: true }).click();
  await expect(page).toHaveURL(/\/device\/device-b\/chat(\/new)?$/);
  expect(app.pageErrors).toEqual([]);
});

test('the device selector opens upward even when its menu would fit below', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  const app = await installConsole(page);
  await page.route('**/v2/devices', route => route.fulfill({ json: { devices: [
    { id: 'device-a', name: 'Test Mac', online: true },
  ] } }));
  await page.goto('/device/device-a/chat');
  const selector = page.getByRole('button', { name: 'Choose a device', exact: true });
  await expect(selector).toContainText('Test Mac');
  await selector.click();
  const menu = page.getByRole('menu');
  await expect(menu).toHaveAttribute('data-positioned', 'true');
  const menuBox = await menu.boundingBox();
  const selectorBox = await selector.boundingBox();
  expect(menuBox.y + menuBox.height).toBeLessThanOrEqual(selectorBox.y);
  expect(app.pageErrors).toEqual([]);
});

test('a device page whose roster failed can retry', async ({ page }) => {
  const app = await installConsole(page);
  let failed = true;
  await page.route('**/v2/devices', route => failed
    ? route.fulfill({ status: 502 })
    : route.fulfill({ json: { devices: [{ id: 'device-a', name: 'Test Mac', online: true }] } }));
  await page.goto('/device/device-a/chat');
  await expect(page.getByRole('main').getByText(/HTTP 502/)).toBeVisible();
  expect(app.socket).toBeNull();
  failed = false;
  await page.getByRole('button', { name: 'Try again' }).click();
  await expect.poll(() => app.socket !== null).toBe(true);
  await expect(page.getByRole('main').getByText(/HTTP 502/)).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('Chat is the signed-out launch page and a saved Work preference cannot replace it', async ({ page }, info) => {
  const app = await installConsole(page);
  await page.addInitScript(() => localStorage.setItem('openseek.sidebar_mode', 'work'));
  await page.route('**/v2/auth/me', route => route.fulfill({ status: 401 }));
  await page.goto('/index.html');
  await expect(page).toHaveURL(/\/cloud$/);
  await expect(page.getByRole('main').getByRole('heading', { name: 'Cloud', level: 2, exact: true })).toBeVisible();
  await expect(page.getByRole('main').getByRole('button', { name: 'Sign in with GitHub' })).toBeEnabled();
  // Device choice lives in the signed-in sidebar, not on the Cloud home.
  await expect(page.getByRole('main').getByRole('link', { name: 'Choose a device' })).toHaveCount(0);
  // The phone drawer starts closed, so query the mode switch by markup.
  await expect(page.locator('.sidebar-mode-option[aria-label="Chat"]')).toHaveAttribute('aria-pressed', 'true');
  expect(app.socket).toBeNull();
  await page.screenshot({ path: info.outputPath('chat-home-signed-out.png') });
  expect(app.pageErrors).toEqual([]);
});

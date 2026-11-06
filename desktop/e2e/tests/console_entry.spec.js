import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

// Exercise the browser packager's normal HTML, CSS and frontend bundle.
// Only the remote account and host responses contain fixture data.
async function installConsole(page) {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  return app;
}

test.use({ viewport: { width: 393, height: 851 }, isMobile: true, hasTouch: true });

test('a signed-out device page offers login and preserves the page return path', async ({ page }) => {
  const app = await installConsole(page);
  await page.route('**/v2/auth/me', route => route.fulfill({ status: 401 }));
  await page.goto('/device/device-a/chat');
  await expect(page.locator('#console-sign-in')).toHaveAttribute('href',
    '/v2/auth/login?prompt=select_account&return_to=%2Fdevice%2Fdevice-a%2Fchat');
  expect(app.socket).toBeNull();
  await page.route('**/v2/auth/login?*', route => route.fulfill({ contentType: 'text/html', body: '<h1>OAuth fixture</h1>' }));
  await page.locator('#console-sign-in').click();
  await expect(page.locator('h1')).toHaveText('OAuth fixture');
  await expect(page).toHaveURL(/\/v2\/auth\/login\?/);
  expect(app.pageErrors).toEqual([]);
});

test('the sidebar selector lists Cloud and online devices and switches between them', async ({ page }) => {
  const app = await installConsole(page);
  await page.route('**/v2/devices', route => route.fulfill({ json: { devices: [
    { id: 'device-a', name: 'Test Mac', online: true },
    { id: 'offline', name: 'Office computer', online: false },
    { id: 'device-b', name: 'Studio', online: true },
  ] } }));
  // A Cloud page has no device; the selector names Cloud and connects nothing.
  await page.goto('/cloud');
  await page.locator('.sidebar-toggle').click();
  const selector = page.locator('[id="sidebar:device-selector:actions-trigger"]');
  await expect(selector).toContainText('Cloud');
  expect(app.socket).toBeNull();
  await selector.click();
  await expect(page.locator('[role="menuitem"][data-action="cloud"]:visible')).toBeDisabled();
  await expect(page.locator('[role="menuitem"][data-action="device:device-a"]:visible')).toBeEnabled();
  await expect(page.locator('[role="menuitem"][data-action="device:device-b"]:visible')).toBeEnabled();
  await expect(page.locator('[role="menuitem"][data-action="device:offline"]:visible')).toHaveCount(0);
  await page.locator('[role="menuitem"][data-action="device:device-a"]:visible').click();
  await expect(page).toHaveURL(/\/device\/device-a\/chat(\/new)?$/);
  await expect.poll(() => app.socket !== null).toBe(true);
  // On a device page it names that device and checks it in the menu.
  await page.locator('.sidebar-toggle').click();
  await expect(selector).toContainText('Test Mac');
  await selector.click();
  await expect(page.locator('[role="menuitem"][data-action="device:device-a"]:visible')).toBeDisabled();
  await expect(page.locator('[role="menuitem"][data-action="device:offline"]:visible')).toHaveCount(0);
  await page.locator('[role="menuitem"][data-action="device:device-b"]:visible').click();
  await expect(page).toHaveURL(/\/device\/device-b\/chat(\/new)?$/);
  // A device page returns to Cloud through the same menu.
  await page.locator('.sidebar-toggle').click();
  await selector.click();
  await expect(page.locator('[role="menuitem"][data-action="device:device-b"]:visible')).toBeDisabled();
  await page.locator('[role="menuitem"][data-action="cloud"]:visible').click();
  await expect(page).toHaveURL(/\/cloud$/);
  await page.locator('.sidebar-toggle').click();
  await expect(selector).toContainText('Cloud');
  expect(app.pageErrors).toEqual([]);
});

test('a device page whose roster failed can retry', async ({ page }) => {
  const app = await installConsole(page);
  let failed = true;
  await page.route('**/v2/devices', route => failed
    ? route.fulfill({ status: 502 })
    : route.fulfill({ json: { devices: [{ id: 'device-a', name: 'Test Mac', online: true }] } }));
  await page.goto('/device/device-a/chat');
  await expect(page.locator('.portal-card')).toContainText('HTTP 502');
  expect(app.socket).toBeNull();
  failed = false;
  await page.locator('#console-retry').click();
  await expect.poll(() => app.socket !== null).toBe(true);
  await expect(page.locator('.portal-card')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('Chat is the signed-out launch page and a saved Work preference cannot replace it', async ({ page }) => {
  const app = await installConsole(page);
  await page.addInitScript(() => localStorage.setItem('openseek.sidebar_mode', 'work'));
  await page.route('**/v2/auth/me', route => route.fulfill({ status: 401 }));
  await page.goto('/index.html');
  await expect(page).toHaveURL(/\/cloud$/);
  await expect(page.locator('.cloud-home')).toBeVisible();
  await expect(page.getByRole('main').locator('#cloud-sign-in')).toBeEnabled();
  // Device choice lives in the signed-in sidebar, not on the Cloud home.
  await expect(page.locator('main [id="sidebar:device-selector:actions-trigger"]')).toHaveCount(0);
  // The phone drawer starts closed, so query the mode switch by markup.
  await expect(page.locator('#sidebar-chat-mode')).toHaveAttribute('aria-pressed', 'true');
  expect(app.socket).toBeNull();
  expect(app.pageErrors).toEqual([]);
});

import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

// Serve the APK's actual entry document and touch stylesheet, with real shared
// frontend assets. Only the remote account/host transport contains demo data.
async function installMobile(page) {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  const assets = new URL('../../../android/app/build/generated/consoleAssets/', import.meta.url);
  await page.route('**/dist/browser/index.html*', route => route.fulfill({
    contentType: 'text/html', body: readFileSync(new URL('index.html', assets)),
  }));
  await page.route('**/dist/browser/mobile.css', route => route.fulfill({
    contentType: 'text/css', body: readFileSync(new URL('mobile.css', assets)),
  }));
  return app;
}

async function assertFits(page) {
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
}

test.use({ viewport: { width: 393, height: 851 }, isMobile: true, hasTouch: true });

test('signed-out entry offers login without a device and preserves the bundled return path', async ({ page }, info) => {
  const app = await installMobile(page);
  await page.route('**/v1/auth/me', route => route.fulfill({ status: 401 }));
  await page.goto('/dist/browser/index.html');
  await expect(page.getByRole('link', { name: 'Sign in with GitHub' })).toHaveAttribute('href',
    '/v1/auth/login?return_to=%2Fdist%2Fbrowser%2Findex.html');
  expect(app.socket).toBeNull();
  await assertFits(page);
  await page.screenshot({ path: info.outputPath('login.png') });
  await page.route('**/v1/auth/login?*', route => route.fulfill({ contentType: 'text/html', body: '<h1>OAuth fixture</h1>' }));
  await page.getByRole('link', { name: 'Sign in with GitHub' }).click();
  await expect(page.getByRole('heading', { name: 'OAuth fixture' })).toBeVisible();
  await expect(page).toHaveURL(/\/v1\/auth\/login\?/);
  expect(app.pageErrors).toEqual([]);
});

test('device selection is explicit, offline devices cannot connect, and switching returns to the picker', async ({ page }, info) => {
  const app = await installMobile(page);
  await page.route('**/v1/devices', route => route.fulfill({ json: { devices: [
    { id: 'device-a', name: 'Test Mac', online: true },
    { id: 'offline', name: 'Office computer', online: false },
  ] } }));
  await page.goto('/dist/browser/index.html');
  await expect(page.getByRole('heading', { name: 'Choose a device' })).toBeVisible();
  await expect(page.locator('.device-choice.offline')).toContainText('Office computer');
  await expect(page.locator('a.device-choice')).toHaveCount(1);
  expect(app.socket).toBeNull();
  await assertFits(page);
  await page.screenshot({ path: info.outputPath('devices.png') });
  await page.getByRole('link', { name: 'Test Mac Online' }).click();
  await expect(page).toHaveURL(/\?device=device-a$/);
  await expect(page.getByRole('main')).toBeVisible();
  await page.locator('.sidebar-toggle').click();
  await expect(page.getByRole('link', { name: 'Choose a device' })).toBeVisible();
  await expect.poll(async () => Math.abs((await page.locator('aside').boundingBox()).x)).toBeLessThan(1);
  const toggle = await page.locator('.sidebar-toggle').boundingBox();
  expect(toggle.width).toBe(24);
  const mode = await page.locator('.sidebar-mode').boundingBox();
  const option = await page.locator('.sidebar-mode-option').first().boundingBox();
  expect(option.y).toBeGreaterThanOrEqual(mode.y);
  expect(option.y + option.height).toBeLessThanOrEqual(mode.y + mode.height);
  await page.screenshot({ path: info.outputPath('drawer.png'), animations: 'disabled' });
  await page.getByRole('link', { name: 'Choose a device' }).click();
  await expect(page.getByRole('heading', { name: 'Choose a device' })).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('phone conversation sends once, stops, reconnects and keeps the composer visible at keyboard height', async ({ page }, info) => {
  const app = await installMobile(page);
  await app.goto();
  await page.locator('.sidebar-toggle').click();
  await app.openSession();
  await expect(page.locator('.app')).toHaveClass(/sidebar-collapsed/);
  await page.locator('#task').fill('Continue from my phone');
  await page.locator('#send').click();
  await expect.poll(() => app.requests.filter(r => r.method === 'agent.start').length).toBe(1);
  await page.locator('#stop').click();
  await expect.poll(() => app.requests.filter(r => r.method === 'agent.cancel').length).toBe(1);
  const oldSocket = app.socket;
  oldSocket.close({ code: 1001, reason: 'fixture network transition' });
  await expect.poll(() => app.socket !== oldSocket, { timeout: 15000 }).toBe(true);
  await expect(page.locator('#task')).toBeEnabled();
  expect(app.requests.filter(r => r.method === 'agent.start')).toHaveLength(1);
  await page.setViewportSize({ width: 393, height: 480 });
  await page.locator('#task').fill('Unsent draft after reconnection');
  await assertFits(page);
  const box = await page.locator('#task').boundingBox();
  expect(box.y + box.height).toBeLessThanOrEqual(480);
  await page.screenshot({ path: info.outputPath('conversation-keyboard-height.png') });
  expect(app.pageErrors).toEqual([]);
});

test('a failed roster can retry, and an empty roster explains desktop setup', async ({ page }) => {
  const app = await installMobile(page);
  let failed = true;
  await page.route('**/v1/devices', route => failed
    ? route.fulfill({ status: 502 })
    : route.fulfill({ json: { devices: [] } }));
  await page.goto('/dist/browser/index.html');
  await expect(page.getByText(/HTTP 502/)).toBeVisible();
  failed = false;
  await page.getByRole('button', { name: 'Try again' }).click();
  await expect(page.getByRole('heading', { name: 'Choose a device' })).toBeVisible();
  await expect(page.locator('a.device-choice')).toHaveCount(0);
  expect(app.socket).toBeNull();
  expect(app.pageErrors).toEqual([]);
});

test('long engine-start failures remain readable within the phone viewport and restore the draft', async ({ page }, info) => {
  const app = await installMobile(page);
  const failure = 'Engine failed to start: invalid option\nUsage: openseek serve [OPTIONS]\n' +
    '--session-root <directory> Directory containing durable sessions.\n'.repeat(65);
  app.rpcErrors.set('agent.start', failure);
  await app.goto();
  await page.locator('.sidebar-toggle').click();
  await app.openSession();
  await page.locator('#task').fill('Retryable draft');
  await page.locator('#send').click();
  const notice = page.locator('.notification').filter({ hasText: 'Engine failed to start' });
  await expect(notice).toBeVisible();
  await expect(page.locator('#task')).toHaveValue('Retryable draft');
  const bounds = await notice.boundingBox();
  expect(bounds.y).toBeGreaterThanOrEqual(0);
  expect(bounds.height).toBeLessThanOrEqual(851 * 0.4);
  await expect(notice).toHaveCSS('overflow-y', 'auto');
  await expect(notice).toHaveCSS('white-space', 'pre-wrap');
  await page.screenshot({ path: info.outputPath('bounded-engine-error.png') });
  await notice.click();
  await expect(notice).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

import { test, expect } from './support/test.js';
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

test('a signed-out device page offers login and preserves the page return path', async ({ page }) => {
  const app = await installConsole(page);
  await page.route('**/v2/auth/me', route => route.fulfill({ status: 401 }));
  await page.goto('/device/device-a/chat');
  await expect(page.getByRole('link', { name: 'Sign in', exact: true })).toHaveAttribute('href',
    '/v2/auth/login?prompt=select_account&return_to=%2Fdevice%2Fdevice-a%2Fchat');
  expect(app.socket).toBeNull();
  await assertFits(page);
  await page.route('**/v2/auth/login?*', route => route.fulfill({ contentType: 'text/html', body: '<h1>OAuth fixture</h1>' }));
  await page.getByRole('link', { name: 'Sign in', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'OAuth fixture' })).toBeVisible();
  await expect(page).toHaveURL(/\/v2\/auth\/login\?/);
  expect(app.pageErrors).toEqual([]);
});

test('device management lists connection states and refreshes the roster', async ({ page }) => {
  const app = await installConsole(page);
  await page.routeWebSocket('**/v2/devices/device-b/ws?*', socket => {
    socket.onMessage(async raw => {
      const request = JSON.parse(raw.toString());
      if (request.id !== undefined) socket.send(JSON.stringify({
        jsonrpc: '2.0', id: request.id, result: await app.replyFor(request),
      }));
    });
    socket.send(JSON.stringify({
      jsonrpc: '2.0', method: 'agent.connected', params: { protocol: app.hostProtocol },
    }));
  });
  let devices = [
    { id: 'device-a', name: 'Test Mac', online: true },
    { id: 'offline', name: 'Office computer', online: false },
    { id: 'device-b', name: 'Studio', online: true },
  ];
  await page.route('**/v2/devices', route => route.fulfill({ json: { devices } }));
  const removed = [];
  let failRemoval = true;
  await page.route('**/v2/devices/*', async route => {
    if (route.request().method() !== 'DELETE') return route.fallback();
    const id = route.request().url().split('/').pop();
    if (failRemoval) return route.fulfill({ status: 500 });
    removed.push(id);
    devices = devices.filter(device => device.id !== id);
    return route.fulfill({ status: 204 });
  });
  async function openDevices() {
    await page.locator('.sidebar-toggle').click();
    await page.getByRole('button', { name: 'Settings', exact: true }).click();
    await page.getByRole('tab', { name: 'Device', exact: true }).click();
  }
  const panel = page.getByRole('tabpanel', { name: 'Device', exact: true });
  const row = name => panel.locator('.form-row').filter({ has: page.getByText(name, { exact: true }) });
  await page.goto('/cloud');
  await openDevices();
  await expect(row('Test Mac').getByRole('status')).toHaveText('Connected');
  await expect(row('Studio').getByRole('status')).toHaveText('Connected');
  await expect(row('Office computer').getByRole('status')).toHaveText('Offline');
  await expect(page).toHaveURL(/\/cloud$/);
  await assertFits(page);
  await row('Office computer').getByRole('button', { name: 'Remove', exact: true }).click();
  await expect(panel.getByRole('alert')).toContainText('500');
  await expect(row('Office computer')).toBeVisible();
  failRemoval = false;
  await row('Office computer').getByRole('button', { name: 'Remove', exact: true }).click();
  await expect(row('Office computer')).toHaveCount(0);
  expect(removed).toEqual(['offline']);
  await row('Studio').getByRole('button', { name: 'Remove', exact: true }).click();
  const confirmation = page.getByRole('dialog', { name: 'Remove', exact: true });
  await expect(confirmation).toContainText('immediately disconnect');
  await confirmation.getByRole('button', { name: 'Cancel', exact: true }).click();
  expect(removed).toEqual(['offline']);
  await row('Studio').getByRole('button', { name: 'Remove', exact: true }).click();
  await confirmation.getByRole('button', { name: 'Remove', exact: true }).click();
  await expect(row('Studio')).toHaveCount(0);
  expect(removed).toEqual(['offline', 'device-b']);
  await panel.getByRole('button', { name: 'Refresh', exact: true }).click();
  await expect(row('Office computer')).toHaveCount(0);
  await expect(row('Test Mac').getByRole('status')).toHaveText('Connected');
  expect(app.pageErrors).toEqual([]);
});

test('a signed-out visitor finds the relay app downloads beside sign-in and in the sidebar', async ({ page }) => {
  const app = await installConsole(page);
  await page.route('**/v2/auth/me', route => route.fulfill({ status: 401 }));
  let manifestRequests = 0;
  await page.route('**/desktop/releases/latest.json', route => {
    manifestRequests += 1;
    return route.fulfill({ json: {
      version: '0.3.1',
      url: 'https://example.com/releases/0.3.1',
      platforms: {
        'macos-arm64': { url: 'https://example.com/mac.tar.gz' },
        'macos-arm64-dmg': { url: 'https://example.com/mac.dmg' },
        'windows-x64': { url: 'https://example.com/win-setup.exe' },
        browser: { url: 'https://example.com/console.tar.gz' },
      },
    } });
  });
  await page.goto('/cloud');
  const inline = page.getByRole('main').getByRole('region', { name: 'Download apps' });
  await expect(inline.getByRole('link', { name: /macOS · Apple Silicon/ }))
    .toHaveAttribute('href', 'https://example.com/mac.dmg');
  await expect(inline.getByRole('link', { name: /Windows · x64/ }))
    .toHaveAttribute('href', 'https://example.com/win-setup.exe');
  await expect(inline.getByRole('link', { name: 'All releases on GitHub' }))
    .toHaveAttribute('href', 'https://example.com/releases/0.3.1');
  await expect(inline.getByRole('link')).toHaveCount(3);
  await assertFits(page);
  // The sidebar's dialog shows the list the page already read.
  await page.locator('.sidebar-toggle').click();
  await page.getByRole('button', { name: 'Download apps' }).click();
  const dialog = page.getByRole('dialog', { name: 'Download apps' });
  await expect(dialog.getByRole('link', { name: /macOS · Apple Silicon/ }))
    .toHaveAttribute('href', 'https://example.com/mac.dmg');
  expect(manifestRequests).toBe(1);
  await page.keyboard.press('Escape');
  await expect(dialog).toBeHidden();
  expect(app.pageErrors).toEqual([]);
});

test('Device settings explain how to add a computer, starting from its installer', async ({ page }, testInfo) => {
  const app = await installConsole(page);
  await page.route('**/v2/devices', route => route.fulfill({ json: { devices: [] } }));
  let manifestRequests = 0;
  await page.route('**/desktop/releases/latest.json', route => {
    manifestRequests += 1;
    return route.fulfill({ json: {
      version: '0.3.1',
      url: 'https://example.com/releases/0.3.1',
      platforms: {
        'macos-arm64-dmg': { url: 'https://example.com/mac.dmg' },
        android: { url: 'https://example.com/seekmoon.apk' },
      },
    } });
  });
  await page.goto('/cloud');
  await page.locator('.sidebar-toggle').click();
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await page.getByRole('tab', { name: 'Device', exact: true }).click();
  await page.getByRole('button', { name: 'Add a device', exact: true }).click();
  const dialog = page.getByRole('dialog', { name: 'Add a device' });
  await expect(dialog.getByRole('link', { name: /macOS · Apple Silicon/ }))
    .toHaveAttribute('href', 'https://example.com/mac.dmg');
  // The Android app wraps this console, so it can never become a device.
  await expect(dialog.getByRole('link', { name: /Android/ })).toHaveCount(0);
  await expect(dialog).toContainText('Turn on Remote control under Settings → Connections → Remote access.');
  const steps = dialog.locator('ol > li');
  await expect(steps).toHaveCount(4);
  await expect(steps.nth(3)).toHaveText('The computer then appears online under Settings → Device whenever SeekMoon is running on it.');
  await assertFits(page);
  await page.screenshot({ path: testInfo.outputPath('add-device-four-steps.png') });
  // The dialog reuses the list the page already read.
  expect(manifestRequests).toBe(1);
  await page.keyboard.press('Escape');
  await expect(dialog).toBeHidden();
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

test('Chat is the signed-out launch page and a saved Work preference cannot replace it', async ({ page }) => {
  const app = await installConsole(page);
  await page.addInitScript(() => localStorage.setItem('openseek.sidebar_mode', 'work'));
  await page.route('**/v2/auth/me', route => route.fulfill({ status: 401 }));
  await page.goto('/index.html');
  await expect(page).toHaveURL(/\/cloud$/);
  await expect(page.getByRole('main').getByRole('heading', { name: 'Sign in to view conversations', level: 2, exact: true })).toBeVisible();
  await expect(page.getByRole('main').getByRole('button', { name: 'Sign in', exact: true })).toBeEnabled();
  // Device choice lives in the signed-in sidebar, not on the Cloud home.
  await expect(page.getByRole('main').getByRole('link', { name: 'Choose a device' })).toHaveCount(0);
  // The phone drawer starts closed, so query the mode switch by markup.
  await expect(page.locator('.sidebar-mode-option[aria-label="Chat"]')).toHaveAttribute('aria-pressed', 'true');
  expect(app.socket).toBeNull();
  expect(app.pageErrors).toEqual([]);
});

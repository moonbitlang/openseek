import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

// The `auth.status` shape (docs/remote-protocol.md): absent fields, never
// null, stand for a signed-out user and device.
const relay = 'https://openseek-api.moonbitlang.cn';
const signedOut = { connected: false, server_url: relay };
const signedIn = {
  connected: true,
  server_url: relay,
  user: { login: 'octocat', avatar_url: '' },
  device: { id: 'd_1', name: 'Test Mac', url: `${relay}/console/?device=d_1` },
};

// Replace only Proton's transport, as close_shortcut.spec.js does. The relay
// sign-in is scripted: `auth.connect` stays pending until the test settles
// it, the way the real host waits for the browser round-trip.
async function installDesktop(page, { managed = false } = {}) {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await page.route('https://cloud.moonbitlang.cn/v1/me/preferences', route =>
    route.fulfill({ json: { allow_content_improvement: false } }));
  const environment = { ...signedIn, managed_by_env: true };
  const auth = { status: managed ? environment : signedOut, account: null, finishConnect: null, requests: app.requests, app };
  await page.exposeFunction('desktopRequest', request => {
    app.requests.push(request);
    switch (request.method) {
      case 'app.system_appearance':
        return { dark: false };
      case 'auth.status':
        return auth.status;
      case 'account.session':
        return auth.account ? { session: auth.account } : {};
      case 'remote.access_set':
        auth.status = request.params.enabled ? signedIn : signedOut;
        return auth.status;
      case 'auth.connect':
        return new Promise(resolve => {
          auth.finishConnect = () => {
            auth.account = { token: 'ts_fixture', user: { user_id: '123', login: 'octocat', avatar_url: '' } };
            resolve(auth.status);
          };
        });
      case 'auth.disconnect':
        auth.account = null;
        auth.status = managed ? environment : signedOut;
        return auth.status;
      default:
        return app.replyFor(request);
    }
  });
  await page.addInitScript(() => {
    const listeners = new Map();
    const events = {
      on(name, callback) {
        const callbacks = listeners.get(name) || new Set();
        listeners.set(name, callbacks);
        callbacks.add(callback);
        return () => callbacks.delete(callback);
      },
    };
    window.desktopEvent = (name, payload) => {
      for (const callback of listeners.get(name) || []) callback({ payload });
    };
    window.__MoonBit__ = {
      getTitlebarArea: async () => null,
      app: events,
      events,
      openseek: new Proxy({}, {
        get: (_, method) => async params => {
          if (method === 'host.connect') {
            window.desktopEvent('openseek.agent.connected', { protocol: 2 });
          }
          return window.desktopRequest({ method, params });
        },
      }),
    };
  });
  await page.goto('/index.html');
  await page.getByRole('main').waitFor();
  return auth;
}

test('account sign-in remains independent of the remote access toggle and signs out cleanly', async ({ page }, testInfo) => {
  const auth = await installDesktop(page);
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  const section = page.locator('.settings-group', { hasText: 'Account · Remote access' });

  const connect = section.getByRole('button', { name: 'Sign in', exact: true });
  await expect(connect).toBeEnabled();
  await connect.click();

  const waiting = section.getByRole('status');
  await expect(waiting).toHaveText('Waiting for the browser…');
  const accountRow = section.locator('.setting-row', { has: page.getByRole('status') });
  await expect(accountRow.locator('.setting-name')).toHaveText('Account');
  await expect(accountRow.getByRole('button', { name: 'Cancel', exact: true })).toBeEnabled();
  await section.screenshot({ path: testInfo.outputPath('account-sign-in-waiting.png') });
  await expect.poll(() => auth.finishConnect !== null).toBe(true);

  auth.finishConnect();
  const signOut = section.getByRole('button', { name: 'Sign out', exact: true });
  await expect(section.getByText('@octocat', { exact: true })).toBeVisible();
  await expect(signOut).toBeEnabled();
  const toggle = section.getByRole('switch', { name: 'Remote control', exact: true });
  await expect(toggle).toHaveAttribute('aria-checked', 'false');
  expect(auth.requests.filter(request => request.method === 'remote.access_set')).toEqual([]);
  await toggle.focus();
  await page.keyboard.press('Space');
  await expect(toggle).toHaveAttribute('aria-checked', 'true');
  await expect(section.getByText('online — reachable from your browser', { exact: true })).toBeVisible();
  await toggle.click();
  await expect(toggle).toHaveAttribute('aria-checked', 'false');
  await expect(signOut).toBeEnabled();
  expect(auth.account.token).toBe('ts_fixture');
  await signOut.click();
  await expect(section.getByRole('button', { name: 'Sign in', exact: true })).toBeEnabled();
  await expect(toggle).toBeDisabled();
  expect(auth.app.pageErrors).toEqual([]);
});

test('FPS overlay switch toggles with the keyboard and restores the saved preference', async ({ page }, testInfo) => {
  const auth = await installDesktop(page);
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  const toggle = page.getByRole('switch', { name: 'FPS overlay', exact: true });
  await expect(toggle).toHaveAttribute('aria-checked', 'false');
  await toggle.focus();
  await page.keyboard.press('Space');
  await expect(toggle).toHaveAttribute('aria-checked', 'true');
  await expect.poll(() => page.evaluate(() => localStorage.getItem('openseek.fps_overlay'))).toBe('true');
  await toggle.scrollIntoViewIfNeeded();
  await page.screenshot({ animations: 'disabled', path: testInfo.outputPath('settings-switches.png') });
  await page.reload();
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await expect(toggle).toHaveAttribute('aria-checked', 'true');
  await toggle.click();
  await expect(toggle).toHaveAttribute('aria-checked', 'false');
  await expect.poll(() => page.evaluate(() => localStorage.getItem('openseek.fps_overlay'))).toBe('false');
  expect(auth.app.pageErrors).toEqual([]);
});

test('environment-managed remote access keeps its connection while the account logs out', async ({ page }) => {
  const auth = await installDesktop(page, { managed: true });
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  const section = page.locator('.settings-group', { hasText: 'Account · Remote access' });
  await expect(section.getByRole('switch')).toHaveCount(0);
  await expect(section).toContainText('Signing out does not close this debug connection.');
  await section.getByRole('button', { name: 'Sign in', exact: true }).click();
  await expect.poll(() => auth.finishConnect !== null).toBe(true);
  auth.finishConnect();
  await section.getByRole('button', { name: 'Sign out', exact: true }).click();
  await expect(section.getByRole('button', { name: 'Sign in', exact: true })).toBeEnabled();
  await expect(section.getByRole('link', { name: 'Open', exact: true })).toHaveAttribute('href', signedIn.device.url);
  expect(auth.status.connected).toBe(true);
  expect(auth.requests.filter(request => request.method === 'remote.access_set')).toEqual([]);
  expect(auth.app.pageErrors).toEqual([]);
});

import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

async function seed(page) {
  await page.addInitScript(() => localStorage.setItem('seekmoon.account.v1', JSON.stringify({ token: 'ts_account-A', user: { user_id: 'A', login: 'alice', avatar_url: '' } })));
}

test('device sockets use the cached account ticket instead of another account cookie', async ({ page, context, baseURL }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await seed(page);
  await context.addCookies([{ name: 'session', value: 'cookie-for-B', url: baseURL }]);
  await page.goto('/dist/browser/index.html?device=device-a');
  await app.openSession();
  expect(app.ticketRequests).toHaveLength(1);
  expect(new URL(app.ticketRequests[0].url).pathname).toBe('/v2/devices/device-a/connect-ticket');
  expect(app.ticketRequests[0].headers.authorization).toBe('Bearer ts_account-A');
  expect(app.ticketRequests[0].headers.cookie).toContain('cookie-for-B');
  expect(new URL(app.socketURLs[0]).pathname).toBe('/v2/devices/device-a/ws');
  expect(app.socketURLs[0]).toContain('?ticket=wst_');
  expect(app.socketURLs[0]).not.toContain('ts_');
  const first = app.socketTickets[0];
  await app.socket.close({ code: 1001, reason: 'Fixture reconnect' });
  await expect.poll(() => app.socketTickets.length).toBe(2);
  expect(app.socketTickets[1]).not.toBe(first);
  expect(app.ticketRequests[1].headers.authorization).toBe('Bearer ts_account-A');
  expect(app.pageErrors).toEqual([]);
});

test('a ticket response arriving after browser logout cannot open a socket', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  let finish;
  app.pauseTicket = new Promise(resolve => finish = resolve);
  await app.install();
  await seed(page);
  await page.route('**/v2/auth/logout', route => route.fulfill({ status: 204 }));
  await page.goto('/dist/browser/index.html?device=device-a');
  await expect.poll(() => app.ticketRequests.length).toBe(1);
  await page.getByRole('button', { name: 'Sign out', exact: true }).click();
  await expect(page.getByRole('link', { name: /Sign in.*GitHub/i })).toBeVisible();
  finish();
  await expect.poll(() => app.issuedTickets.size).toBe(1);
  expect(app.socketURLs).toEqual([]);
  expect(await page.evaluate(() => localStorage.getItem('seekmoon.account.v1'))).toBeNull();
  expect(app.pageErrors).toEqual([]);
});

for (const status of [401, 503]) {
  test(`ticket HTTP ${status} ${status === 401 ? 'expires the account' : 'preserves it and retries'}`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    app.ticketStatus = status;
    await app.install();
    await seed(page);
    await page.goto('/dist/browser/index.html?device=device-a');
    await expect.poll(() => app.ticketRequests.length).toBeGreaterThan(0);
    if (status === 401) {
      await expect(page.getByRole('link', { name: /Sign in.*GitHub/i })).toBeVisible();
      expect(await page.evaluate(() => localStorage.getItem('seekmoon.account.v1'))).toBeNull();
    } else {
      app.ticketStatus = 200;
      await expect.poll(() => app.socketTickets.length).toBe(1);
      expect(await page.evaluate(() => localStorage.getItem('seekmoon.account.v1'))).toContain('ts_account-A');
    }
    expect(app.pageErrors).toEqual([]);
  });
}

test('browser logout 401 retires both its cached account and device state', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await seed(page);
  await page.route('**/v2/auth/logout', route => route.fulfill({ status: 401 }));
  await page.goto('/dist/browser/index.html?device=device-a');
  await app.openSession();
  await page.getByRole('button', { name: 'Sign out', exact: true }).click();
  await expect(page.getByRole('link', { name: /Sign in.*GitHub/i })).toBeVisible();
  expect(await page.evaluate(() => localStorage.getItem('seekmoon.account.v1'))).toBeNull();
  await expect(page.locator('#task')).toBeHidden();
  expect(app.pageErrors).toEqual([]);
});


test('unreadable account storage does not fall through to another browser cookie', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  let cookieChecks = 0;
  await page.route('**/v2/auth/me', route => {
    cookieChecks++;
    return route.fulfill({ status: 200, body: '{"user_id":"B","login":"bob","avatar_url":""}' });
  });
  await page.addInitScript(() => {
    const original = Storage.prototype.getItem;
    Storage.prototype.getItem = function(key) {
      if (key === 'seekmoon.account.v1') throw new Error('Fixture storage unavailable');
      return original.call(this, key);
    };
  });
  await page.goto('/dist/browser/index.html?device=device-a');
  await expect(page.getByText(/Could not read account storage:/)).toBeVisible();
  expect(cookieChecks).toBe(0);
  expect(app.socketURLs).toEqual([]);
  expect(app.pageErrors).toEqual([]);
});

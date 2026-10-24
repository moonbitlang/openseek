import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

// The page registers the real /sw.js and drives the real Push API calls.
// Headless Chromium has no push service behind PushManager and reports
// notifications as denied whatever the context grants, so the permission and
// subscribe/getSubscription are replaced, with a subscription whose toJSON
// matches the browser's.
async function stubPushService(page, { permission = 'default', answer = 'granted' } = {}) {
  await page.addInitScript(({ permission, answer }) => {
    const state = { subscription: null, unsubscribed: 0, options: null, permission, prompts: 0 };
    window.__push = state;
    Object.defineProperty(Notification, 'permission', { get: () => state.permission });
    Notification.requestPermission = async () => {
      state.prompts++;
      state.permission = answer;
      return answer;
    };
    const make = () => ({
      endpoint: 'https://fcm.googleapis.com/fcm/send/fixture',
      toJSON() {
        return { endpoint: this.endpoint, expirationTime: null, keys: { p256dh: 'BPUB', auth: 'AUTH' } };
      },
      async unsubscribe() {
        state.unsubscribed++;
        state.subscription = null;
        return true;
      },
    });
    PushManager.prototype.subscribe = async function (options) {
      state.options = { userVisibleOnly: options.userVisibleOnly, applicationServerKey: options.applicationServerKey };
      state.subscription ??= make();
      return state.subscription;
    };
    PushManager.prototype.getSubscription = async function () {
      return state.subscription;
    };
  }, { permission, answer });
}

async function relayPush(page, { key = 'BKEY' } = {}) {
  const calls = [];
  await page.route('**/v2/push/key', route => key === null
    ? route.fulfill({ status: 404, body: '' })
    : route.fulfill({ contentType: 'application/json', body: JSON.stringify({ public_key: key }) }));
  for (const path of ['subscription', 'test']) {
    await page.route(`**/v2/push/${path}`, async route => {
      const request = route.request();
      calls.push({
        path,
        method: request.method(),
        authorization: (await request.allHeaders()).authorization,
        body: JSON.parse(request.postData() ?? 'null'),
      });
      await route.fulfill({ status: path === 'test' ? 202 : 204 });
    });
  }
  return calls;
}

test('turning notifications on registers the worker and the subscription with the relay', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await stubPushService(page);
  const calls = await relayPush(page);
  await page.goto('/index.html?device=device-a');
  await expect(page.getByText('Notifications off', { exact: true })).toBeVisible();
  // The worker is served at the root, so it controls every page route.
  await expect.poll(() => page.evaluate(async () => {
    const registration = await navigator.serviceWorker.getRegistration('/');
    return registration?.active?.scriptURL ?? null;
  })).toMatch(/\/sw\.js$/);

  await page.getByRole('button', { name: 'Turn on', exact: true }).click();
  await expect(page.getByText('Notifications on', { exact: true })).toBeVisible();
  expect(await page.evaluate(() => window.__push.prompts)).toBe(1);
  expect(await page.evaluate(() => window.__push.options)).toEqual({ userVisibleOnly: true, applicationServerKey: 'BKEY' });
  expect(calls).toEqual([{
    path: 'subscription',
    method: 'PUT',
    authorization: 'Bearer ts_fixture-account',
    body: { endpoint: 'https://fcm.googleapis.com/fcm/send/fixture', keys: { p256dh: 'BPUB', auth: 'AUTH' }, locale: 'en' },
  }]);

  await page.getByRole('button', { name: 'Test', exact: true }).click();
  await expect.poll(() => calls.length).toBe(2);
  expect(calls[1]).toMatchObject({ path: 'test', method: 'POST', body: { endpoint: 'https://fcm.googleapis.com/fcm/send/fixture' } });

  await page.getByRole('button', { name: 'Turn off', exact: true }).click();
  await expect(page.getByText('Notifications off', { exact: true })).toBeVisible();
  expect(calls[2]).toMatchObject({ path: 'subscription', method: 'DELETE', body: { endpoint: 'https://fcm.googleapis.com/fcm/send/fixture' } });
  expect(await page.evaluate(() => window.__push.unsubscribed)).toBe(1);
  expect(app.pageErrors).toEqual([]);
});

test('a relay without push shows no notifications row', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await stubPushService(page);
  await relayPush(page, { key: null });
  await page.goto('/index.html?device=device-a');
  await app.openSession();
  await expect(page.getByRole('button', { name: 'Sign out', exact: true })).toBeVisible();
  await expect(page.getByText(/^Notifications/)).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('a site already denied reads as blocked', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await stubPushService(page, { permission: 'denied' });
  await relayPush(page);
  await page.goto('/index.html?device=device-a');
  await expect(page.getByText('Notifications are blocked in browser settings', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Turn on', exact: true })).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('denying the prompt blocks without subscribing', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await stubPushService(page, { answer: 'denied' });
  const calls = await relayPush(page);
  await page.goto('/index.html?device=device-a');
  await page.getByRole('button', { name: 'Turn on', exact: true }).click();
  await expect(page.getByText('Notifications are blocked in browser settings', { exact: true })).toBeVisible();
  expect(await page.evaluate(() => window.__push.subscription)).toBeNull();
  expect(calls).toEqual([]);
  expect(app.pageErrors).toEqual([]);
});

test('a subscribed browser registers again with the relay when the page loads', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await stubPushService(page, { permission: 'granted' });
  await page.addInitScript(() => {
    window.__push.subscription = {
      endpoint: 'https://fcm.googleapis.com/fcm/send/kept',
      toJSON() { return { endpoint: this.endpoint, keys: { p256dh: 'BPUB', auth: 'AUTH' } }; },
      async unsubscribe() { return true; },
    };
  });
  const calls = await relayPush(page);
  await page.goto('/index.html?device=device-a');
  await expect(page.getByText('Notifications on', { exact: true })).toBeVisible();
  await expect.poll(() => calls.length).toBe(1);
  expect(calls[0]).toMatchObject({ path: 'subscription', method: 'PUT', body: { endpoint: 'https://fcm.googleapis.com/fcm/send/kept' } });
  expect(app.pageErrors).toEqual([]);
});

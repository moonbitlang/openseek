import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

for (const endpoint of ['auth/me', 'devices']) {
  test(`${endpoint} HTTP 401 returns to sign-in`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    await app.install();
    await page.route(`**/v2/${endpoint}`, route => route.fulfill({ status: 401, body: '' }));
    await page.goto('/index.html?device=device-a');
    await expect(page.locator('#console-sign-in')).toBeVisible();
    expect(app.pageErrors).toEqual([]);
  });
}

for (const endpoint of ['auth/me', 'devices']) {
  test(`${endpoint} HTTP 500 remains a retryable failure`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    await app.install();
    let failing = true;
    let attempts = 0;
    await page.route(`**/v2/${endpoint}`, route => {
      attempts++;
      return failing ? route.fulfill({ status: 500, body: 'unavailable' }) : route.fallback();
    });
    await page.goto('/index.html?device=device-a');
    const gate = page.getByRole('main');
    await expect(gate.locator('.portal-card > p')).toBeVisible();
    const retry = gate.locator('#console-retry');
    await expect(retry).toBeVisible();
    const failedAttempts = attempts;
    failing = false;
    await retry.click();
    await expect.poll(() => attempts).toBeGreaterThan(failedAttempts);
    await app.openSession();
    await expect(page.locator('#transcript .msg-content')).toContainText(['Browser result']);
    await expect(retry).toBeHidden();
    expect(app.pageErrors).toEqual([]);
  });
}

test('network failure reaches the retry UI', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await page.route('**/v2/auth/me', route => route.abort('failed'));
  await page.goto('/index.html?device=device-a');
  await expect(page.locator('.portal-card > p')).toBeVisible();
  await expect(page.locator('#console-retry')).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('same-origin cookies and empty logout POST survive HTTP transport replacement', async ({ page, context, baseURL }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await context.addCookies([{ name: 'session', value: 'fixture', url: baseURL }]);
  const meRequest = page.waitForRequest('**/v2/auth/me');
  await page.goto('/index.html?device=device-a');
  await app.openSession();
  expect((await (await meRequest).allHeaders()).cookie).toContain('session=fixture');
  let logout;
  await page.route('**/v2/auth/logout', async route => {
    logout = {
      method: route.request().method(),
      body: route.request().postDataBuffer(),
      headers: await route.request().allHeaders(),
    };
    await route.fulfill({ status: 204 });
  });
  await page.locator('#sidebar-sign-out').click();
  await expect(page.locator('#console-sign-in')).toBeVisible();
  expect(logout.method).toBe('POST');
  expect(logout.body?.length ?? 0).toBe(0);
  expect(logout.headers.cookie).toContain('session=fixture');
  expect(app.pageErrors).toEqual([]);
});

test('logout failure retains the session and decodes the response text', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await page.route('**/v2/auth/logout', route => route.fulfill({
    status: 503, contentType: 'application/json',
    body: Buffer.concat([
      Buffer.from('\uFEFF{"error":"Retry '), Buffer.from([0xff]), Buffer.from('"}'),
    ]),
  }));
  await page.goto('/index.html?device=device-a');
  await app.openSession();
  await page.locator('#sidebar-sign-out').click();
  await expect(page.locator('.console-notice')).toHaveText('Retry �');
  await expect(page.locator('#sidebar-sign-out')).toBeEnabled();
  expect(app.pageErrors).toEqual([]);
});

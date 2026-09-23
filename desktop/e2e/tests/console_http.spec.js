import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

for (const endpoint of ['auth/me', 'devices']) {
  test(`${endpoint} HTTP 401 returns to sign-in`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    await app.install();
    await page.route(`**/v1/${endpoint}`, route => route.fulfill({ status: 401, body: '' }));
    await page.goto('/dist/browser/index.html?device=device-a');
    await expect(page.getByRole('link', { name: /Sign in.*GitHub/i })).toBeVisible();
    expect(app.pageErrors).toEqual([]);
  });
}

for (const endpoint of ['auth/me', 'devices']) {
  test(`${endpoint} HTTP 500 remains a retryable failure`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    await app.install();
    await page.route(`**/v1/${endpoint}`, route => route.fulfill({ status: 500, body: 'unavailable' }));
    await page.goto('/dist/browser/index.html?device=device-a');
    await expect(page.getByText(/answered HTTP 500/)).toBeVisible();
    await expect(page.getByRole('button', { name: 'Try again', exact: true })).toBeVisible();
    expect(app.pageErrors).toEqual([]);
  });
}

test('network failure reaches the retry UI', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await page.route('**/v1/auth/me', route => route.abort('failed'));
  await page.goto('/dist/browser/index.html?device=device-a');
  await expect(page.getByText(/the relay is unreachable:/)).toBeVisible();
  await expect(page.getByRole('button', { name: 'Try again', exact: true })).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('same-origin cookies and empty logout POST survive HTTP transport replacement', async ({ page, context, baseURL }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await context.addCookies([{ name: 'session', value: 'fixture', url: baseURL }]);
  const meRequest = page.waitForRequest('**/v1/auth/me');
  await page.goto('/dist/browser/index.html?device=device-a');
  await app.openSession();
  expect((await (await meRequest).allHeaders()).cookie).toContain('session=fixture');
  let logout;
  await page.route('**/v1/auth/logout', async route => {
    logout = {
      method: route.request().method(),
      body: route.request().postDataBuffer(),
      headers: await route.request().allHeaders(),
    };
    await route.fulfill({ status: 204 });
  });
  await page.getByRole('button', { name: 'Sign out', exact: true }).click();
  await expect(page.getByRole('link', { name: /Sign in.*GitHub/i })).toBeVisible();
  expect(logout.method).toBe('POST');
  expect(logout.body?.length ?? 0).toBe(0);
  expect(logout.headers.cookie).toContain('session=fixture');
  expect(app.pageErrors).toEqual([]);
});

test('logout failure retains the session and decodes the response text', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await page.route('**/v1/auth/logout', route => route.fulfill({
    status: 503, contentType: 'application/json',
    body: Buffer.concat([
      Buffer.from('\uFEFF{"error":"Retry '), Buffer.from([0xff]), Buffer.from('"}'),
    ]),
  }));
  await page.goto('/dist/browser/index.html?device=device-a');
  await app.openSession();
  await page.getByRole('button', { name: 'Sign out', exact: true }).click();
  await expect(page.getByText('Retry �', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Sign out', exact: true })).toBeEnabled();
  expect(app.pageErrors).toEqual([]);
});

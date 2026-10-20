import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('a host built for another protocol revision is reported once and not retried', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.hostProtocol = 0;
  await app.install();
  await app.goto();
  await expect(page.getByText("This computer runs a SeekMoon version this page can't control.", { exact: false }).first()).toBeVisible();
  const tickets = app.ticketRequests.length;
  // A dropped connection would request a new ticket within its backoff.
  await page.waitForTimeout(2000);
  expect(app.ticketRequests.length).toBe(tickets);
  // The handshake decides before the page sends the host any request.
  expect(app.requests.map(request => request.method)).toEqual([]);
  expect(app.pageErrors).toEqual([]);
});

test('a host from before the protocol revision is reported, not left connecting', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.connectedParams = { ready: true };
  await app.install();
  await page.goto('/device/device-a/chat');
  await expect(page.getByRole('main').getByText("This computer runs a SeekMoon version this page can't control.", { exact: false })).toBeVisible();
  expect(app.requests.map(request => request.method)).toEqual([]);
  expect(app.pageErrors).toEqual([]);
});

test('an incompatible host is reported on Settings, not only in a conversation', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.hostProtocol = 0;
  await app.install();
  await page.goto('/device/device-a/settings');
  const gate = page.getByRole('main');
  await expect(gate.getByRole('heading', { name: 'Device unavailable', exact: true })).toBeVisible();
  await expect(gate.getByText("This computer runs a SeekMoon version this page can't control.", { exact: false })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Account · Remote access', exact: true })).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('a host on the current protocol revision stays connected', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  await expect(page.getByText("This computer runs a SeekMoon version this page can't control.", { exact: false })).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

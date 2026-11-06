import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('a host built for another protocol revision is reported once and not retried', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.hostProtocol = 0;
  await app.install();
  await app.goto();
  await expect(page.locator('#console-host-incompatible')).toBeVisible();
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
  await expect(page.locator('#console-host-incompatible')).toBeVisible();
  expect(app.requests.map(request => request.method)).toEqual([]);
  expect(app.pageErrors).toEqual([]);
});

test('a host on the current protocol revision stays connected', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  await expect(page.locator('#console-host-incompatible')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

// A relay page holds every online device of its account, so the Work list
// opens a device conversation in place and the page's history owns that
// device's routes.
test('a Cloud page opens a device conversation in place and owns its history', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.liveSessions = [{ id: 'session-1', title: 'Device work', updated_at_ms: 1 }];
  await app.install();
  await page.goto('/cloud');
  await expect.poll(() => app.socket !== null).toBe(true);
  await page.evaluate(() => { window.sameDocument = true; });
  await page.getByRole('button', { name: 'Work', exact: true }).click();
  await page.locator('aside .conversation-open').filter({ hasText: 'Device work' }).click();
  await expect(page).toHaveURL(/\/device\/device-a\/chat\/session\/session-1$/);
  await page.goBack();
  await expect(page).toHaveURL(/\/cloud$/);
  await page.goForward();
  await expect(page).toHaveURL(/\/device\/device-a\/chat\/session\/session-1$/);
  expect(await page.evaluate(() => window.sameDocument)).toBe(true);
  expect(app.pageErrors).toEqual([]);
});

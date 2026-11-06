import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('the approval mode is chosen per conversation and reaches agent.start', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  // A conversation is auto-reviewed until it chooses to ask.
  const trigger = page.locator('#openseek-approval-picker');
  await expect(trigger).toHaveAttribute('data-value', 'review');
  await trigger.click();
  const menu = page.locator('#openseek-approval-picker-menu');
  const ask = menu.locator('[data-value="ask"]');
  await ask.click();
  await expect(trigger).toHaveAttribute('data-value', 'ask');
  await page.locator('#task').fill('Delete the old notes');
  await page.locator('#send').click();
  await expect
    .poll(() => app.requests.find(r => r.method === 'agent.start')?.params.approval)
    .toBe('ask');
  await expect(trigger).toBeDisabled();
});

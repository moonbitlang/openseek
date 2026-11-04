import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

async function capture(page, testInfo, name) {
  const path = testInfo.outputPath(`${name}.png`);
  await page.screenshot({ path });
  await testInfo.attach(name, { path, contentType: 'image/png' });
}

test('the approval mode is chosen per conversation and reaches agent.start', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  // A conversation is auto-reviewed until it chooses to ask.
  const trigger = page.locator('.composer').getByRole('button', { name: 'Approval mode' });
  await expect(trigger).toHaveText('Auto-review');
  await trigger.click();
  const menu = page.getByRole('listbox', { name: 'Approval mode' });
  await expect(menu).toBeVisible();
  await expect(menu.locator('.custom-select-heading')).toHaveText('Approval mode');
  const ask = menu.getByRole('option', { name: /Request approval/ });
  const review = menu.getByRole('option', { name: /Auto-review/ });
  await expect(review).toHaveAttribute('aria-selected', 'true');
  await expect(ask).toContainText('You answer every permission request yourself');
  await expect(review).toContainText('asks you only when unsure');
  await capture(page, testInfo, 'openseek-approval-menu');
  await ask.click();
  await expect(menu).toHaveCount(0);
  await expect(trigger).toHaveText('Request approval');
  await expect(trigger).toBeFocused();
  await page.locator('#task').fill('Delete the old notes');
  await page.locator('#send').click();
  await expect
    .poll(() => app.requests.find(r => r.method === 'agent.start')?.params.approval)
    .toBe('ask');
  await expect(trigger).toBeDisabled();
});

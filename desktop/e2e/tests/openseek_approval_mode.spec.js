import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

async function capture(page, testInfo, name) {
  const path = testInfo.outputPath(`${name}.png`);
  await page.locator('.composer').screenshot({ path });
  await testInfo.attach(name, { path, contentType: 'image/png' });
}

test('Approve for me is switched on per conversation and reaches agent.start', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  const toggle = page.locator('.composer').getByRole('button', { name: 'Approve for me' });
  await expect(toggle).toHaveAttribute('aria-pressed', 'false');
  await expect(toggle).toContainText('Request approval');
  await capture(page, testInfo, 'openseek-approval-off');
  await toggle.click();
  await expect(toggle).toHaveAttribute('aria-pressed', 'true');
  await expect(toggle).toContainText('Auto-review');
  await capture(page, testInfo, 'openseek-approval-on');
  await page.locator('#task').fill('Delete the old notes');
  await page.locator('#send').click();
  await expect
    .poll(() => app.requests.find(r => r.method === 'agent.start')?.params.approval)
    .toBe('review');
});

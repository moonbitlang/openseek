import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('the Codex approval mode requires confirmation before full access takes effect', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.codexModels = [{ id: 'gpt-test', displayName: 'Codex focus', isDefault: true }];
  await app.install();
  await app.goto();
  await page.locator('#openseek-model-picker, #codex-model-picker, #model').click();
  await page.locator('[role="option"][data-value="codex:gpt-test"]').click();
  const trigger = page.locator('#codex-permission-picker');
  await expect(trigger).toHaveAttribute('data-value', 'autoReview');
  await trigger.click();
  const menu = page.locator('#codex-permission-picker-menu');
  await menu.locator('[data-value="requestApproval"]').click();
  await expect(trigger).toHaveAttribute('data-value', 'requestApproval');
  // Full access only takes effect after the confirmation dialog.
  await trigger.click();
  await menu.locator('[data-value="fullAccess"]').click();
  const dialog = page.locator('#codex-permission-dialog');
  await expect(dialog).toBeVisible();
  await expect(trigger).toHaveAttribute('data-value', 'requestApproval');
  await dialog.locator('#codex-permission-confirm').click();
  await expect(trigger).toHaveAttribute('data-value', 'fullAccess');
  await expect(page.locator('.codex-permission-control')).toHaveClass(/danger/);
  expect(app.pageErrors).toEqual([]);
});

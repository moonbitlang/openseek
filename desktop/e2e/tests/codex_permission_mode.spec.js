import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('the Codex approval mode uses the headed select and confirms full access', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  app.codexModels = [{ id: 'gpt-test', displayName: 'Codex focus', isDefault: true }];
  await app.install();
  await app.goto();
  await page.getByRole('button', { name: 'Model', exact: true }).click();
  await page.getByRole('option', { name: 'Codex focus', exact: true }).click();
  await expect(page.locator('#task')).toHaveAttribute('placeholder', /Ask Codex/);
  const trigger = page.locator('.composer').getByRole('button', { name: 'Approval mode' });
  await expect(trigger).toHaveText('Approve for me');
  await trigger.click();
  const menu = page.getByRole('listbox', { name: 'Approval mode' });
  await expect(menu).toBeVisible();
  await expect(menu.locator('.custom-select-heading')).toHaveText('How should Codex approve operations?');
  await expect(menu.getByRole('option', { name: /Approve for me/ })).toHaveAttribute('aria-selected', 'true');
  await expect(menu.getByRole('option', { name: /Full access/ })).toContainText('Unrestricted internet access');
  const path = testInfo.outputPath('codex-permission-menu.png');
  await page.screenshot({ path });
  await testInfo.attach('codex-permission-menu', { path, contentType: 'image/png' });
  await page.keyboard.press('1');
  await expect(menu).toHaveCount(0);
  // Safari does not focus a clicked button, so the trigger's blur never
  // fires; a click elsewhere must still close the menu.
  await page.locator('#task').focus();
  await trigger.dispatchEvent('click');
  await expect(menu).toBeVisible();
  await expect(trigger).not.toBeFocused();
  await page.mouse.click(1000, 450);
  await expect(menu).toHaveCount(0);
  await expect(trigger).toHaveText('Request approval');
  // Full access only takes effect after the confirmation dialog.
  await trigger.click();
  await expect(menu).toBeVisible();
  await page.keyboard.press('3');
  const dialog = page.getByRole('dialog', { name: 'Enable full Codex access' });
  await expect(dialog).toBeVisible();
  await expect(trigger).toHaveText('Request approval');
  await dialog.getByRole('button', { name: 'Enable full access' }).click();
  await expect(trigger).toHaveText('Full access');
  await expect(page.locator('.codex-permission-control')).toHaveClass(/danger/);
  expect(app.pageErrors).toEqual([]);
});

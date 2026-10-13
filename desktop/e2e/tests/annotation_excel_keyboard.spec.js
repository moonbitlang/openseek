import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('Excel selection owns annotation shortcuts without stealing them from other inputs', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.searchFiles = ['docs/book1.xlsx'];
  await app.install();
  await app.goto();
  await app.openSession();
  await page.getByRole('button', { name: 'Hide sidebar', exact: true }).click();
  await app.openReview({ waitForHistory: false });
  await page.getByRole('tab', { name: 'Files', exact: true }).click();
  await app.openQuickOpen();
  await page.locator('#quick-open-input').fill('book1.xlsx');
  await page.getByRole('option', { name: /book1\.xlsx/ }).click();
  const cell = page.locator('.sheet-document:visible td[data-cell]').first();
  const input = page.locator('#office-feedback-input textarea');
  const task = page.locator('#task');
  for (const shortcut of ['Control+i', 'Meta+i']) {
    // Excel prevents the pointer default, so the old focus may be BODY or
    // an unrelated input. Selecting a cell must establish document focus.
    await task.fill('Keep the conversation draft');
    await cell.click();
    await expect(input).toBeVisible();
    await page.keyboard.press(shortcut);
    await expect(input).toBeFocused();
    await input.fill('Cell annotation');
    await task.click();
    await page.keyboard.press(shortcut);
    await expect(task).toBeFocused();
    await expect(task).toHaveValue('Keep the conversation draft');
    await expect(input).toHaveValue('Cell annotation');
    await input.press('Escape');
    await expect(input).toBeHidden();
  }
  expect(app.pageErrors).toEqual([]);
});

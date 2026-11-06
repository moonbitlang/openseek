import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('dock selection and deliberate scroll survive opening, typing and closing tabs', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.searchFiles = Array.from({ length: 8 }, (_, i) => `src/document_${i}_long_name.mbt`);
  for (const path of app.searchFiles) app.workingFiles[path] = 'fn main {}\n';
  await app.install();
  await app.goto();
  await app.openSession();
  const openFile = async i => {
    await app.openQuickOpen();
    await page.locator('#quick-open-input').fill(`document_${i}`);
    await page.locator(`#quick-open-list [data-path="${app.searchFiles[i]}"]`).click();
    await expect(page.locator('.editor-tab.active')).toContainText(`document_${i}`);
  };
  for (let i = 0; i < 8; i++) await openFile(i);
  await openFile(0);
  await openFile(7);
  const strip = page.locator('.editor-tabs');
  await strip.evaluate(el => { el.scrollLeft = 0; });
  await page.locator('#task').fill('keep browsing the earlier tabs');
  await expect.poll(() => strip.evaluate(el => el.scrollLeft)).toBe(0);
  await openFile(7);
  await page.locator('.editor-tab.active .tab-close').click();
  await expect(page.locator('.editor-tab')).toHaveCount(7);
  expect(app.pageErrors).toEqual([]);
});

import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

// Geometry assertions must not click the tab first: Playwright would scroll
// the target into view and conceal the product bug.
async function expectActiveVisible(page) {
  await expect.poll(() => page.locator('.editor-tabs').evaluate(strip => {
    const active = strip.querySelector('.editor-tab.active');
    if (!active) return false;
    const bounds = strip.getBoundingClientRect();
    const tab = active.getBoundingClientRect();
    const close = active.querySelector('.tab-close').getBoundingClientRect();
    return tab.left >= bounds.left - 1 && tab.right <= bounds.right + 1 &&
      close.left >= bounds.left - 1 && close.right <= bounds.right + 1;
  })).toBe(true);
}

test('active dock tab stays visible when opening, switching, closing and resizing', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.searchFiles = Array.from({ length: 8 }, (_, i) => `src/document_${i}_long_name.mbt`);
  for (const path of app.searchFiles) app.workingFiles[path] = 'fn main {}\n';
  await app.install();
  await app.goto();
  await app.openSession();
  const openFile = async i => {
    await app.openQuickOpen();
    await page.locator('#quick-open-input').fill(`document_${i}`);
    await page.getByRole('option', { name: new RegExp(`document_${i}`) }).click();
    await expect(page.locator('.editor-tab.active')).toContainText(`document_${i}`);
  };
  for (let i = 0; i < 8; i++) await openFile(i);
  await expect.poll(() => page.locator('.editor-tabs').evaluate(el => el.scrollWidth > el.clientWidth)).toBe(true);
  await expectActiveVisible(page);
  await openFile(0);
  await expectActiveVisible(page);
  await openFile(7);
  await expectActiveVisible(page);
  await page.getByRole('button', { name: 'Expand panel', exact: true }).click();
  await expectActiveVisible(page);
  await page.getByRole('button', { name: 'Restore panel', exact: true }).click();
  await page.setViewportSize({ width: 1100, height: 900 });
  await expectActiveVisible(page);
  // A drag changes CSS geometry without a model message. Also exercise a
  // strip narrower than the normal 200px chip cap.
  const strip = page.locator('.editor-tabs');
  await strip.evaluate(el => { el.style.flex = '0 1 120px'; });
  await expect.poll(() => strip.evaluate(el => el.clientWidth)).toBeLessThan(200);
  await expectActiveVisible(page);
  await strip.evaluate(el => { el.style.removeProperty('flex'); });
  await expectActiveVisible(page);
  // Ordinary typing must not undo a user's deliberate horizontal scroll.
  await strip.evaluate(el => { el.scrollLeft = 0; });
  await page.locator('#task').fill('keep browsing the earlier tabs');
  await expect.poll(() => strip.evaluate(el => el.scrollLeft)).toBe(0);
  // Re-opening even the same active file is an explicit reveal request.
  await openFile(7);
  await expectActiveVisible(page);
  await page.locator('.editor-tab.active .tab-close').click();
  await expect(page.locator('.editor-tab')).toHaveCount(7);
  await expectActiveVisible(page);
  expect(app.pageErrors).toEqual([]);
});

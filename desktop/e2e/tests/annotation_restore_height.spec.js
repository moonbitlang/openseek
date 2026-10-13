import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('a multiline PDF annotation retains its height and position after scrolling back', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.searchFiles = ['docs/report.pdf'];
  await app.install();
  await app.goto();
  await app.openSession();
  await page.getByRole('button', { name: 'Hide sidebar', exact: true }).click();
  await app.openReview({ waitForHistory: false });
  await page.getByRole('tab', { name: 'Files', exact: true }).click();
  await app.openQuickOpen();
  await page.locator('#quick-open-input').fill('report.pdf');
  await page.getByRole('option', { name: /report\.pdf/ }).click();
  await expect(page.locator('#openseek-office-surface')).toHaveAttribute('data-pdf-painted', 'true');
  const source = page.locator('.page[data-page-number="1"] [data-pdf-item]').filter({ hasText: 'OpenSeek PDF preview' }).first();
  await source.evaluate(element => {
    const range = document.createRange();
    range.selectNodeContents(element);
    const selection = getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
    document.dispatchEvent(new Event('selectionchange'));
  });
  const input = page.locator('#office-feedback-input textarea');
  await expect(input).toBeVisible();
  const draft = Array.from({ length: 10 }, (_, i) => `Draft line ${i}`).join('\n');
  await input.fill(draft);
  const height = await input.evaluate(element => element.clientHeight);
  expect(height).toBeGreaterThan(100);
  for (let iteration = 0; iteration < 2; iteration++) {
    await source.evaluate(element => {
      let viewport = element.parentElement;
      while (viewport && !(viewport.scrollHeight > viewport.clientHeight && /auto|scroll/.test(getComputedStyle(viewport).overflowY))) {
        viewport = viewport.parentElement;
      }
      if (!viewport) throw new Error('PDF scroll viewport is missing');
      window.annotationScroll = { viewport, top: viewport.scrollTop };
      viewport.scrollTop = viewport.scrollHeight;
    });
    await expect(input).toBeHidden();
    await page.evaluate(() => {
      const { viewport, top } = window.annotationScroll;
      viewport.scrollTop = top;
    });
    await expect(input).toBeVisible();
    await expect(input).toHaveValue(draft);
    await expect.poll(() => input.evaluate(element => element.clientHeight)).toBe(height);
    const geometry = await input.evaluate(element => {
      const box = element.closest('.agent-feedback-input-widget').getBoundingClientRect();
      const viewport = document.getElementById('office-feedback-input').getBoundingClientRect();
      return { top: box.top, bottom: box.bottom, min: viewport.top, max: viewport.bottom };
    });
    expect(geometry.top).toBeGreaterThanOrEqual(geometry.min - 1);
    expect(geometry.bottom).toBeLessThanOrEqual(geometry.max + 1);
  }
  expect(app.pageErrors).toEqual([]);
});

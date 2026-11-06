import { test, expect } from './support/test.js';
import { readFileSync } from 'node:fs';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

async function openWorkbook(page) {
  const app = new DesktopBrowserHarness(page);
  app.officeFiles['docs/large-workbook.xlsx'] = {
    data_base64: readFileSync(new URL('../fixtures/office/large-workbook.xlsx', import.meta.url)).toString('base64'),
    media_type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    sig: 'office:large',
  };
  app.directoryEntries['/workspace'] = [{ name: 'docs', is_dir: true }];
  app.directoryEntries['/workspace/docs'] = [{ name: 'large-workbook.xlsx', is_dir: false }];
  app.searchFiles = ['docs/large-workbook.xlsx'];
  await app.install(); await app.goto(); await app.openSession();
  await page.getByRole('button', { name: 'Hide sidebar', exact: true }).click();
  await app.openReview({ waitForHistory: false });
  await page.getByRole('tab', { name: 'Files', exact: true }).click();
  await app.openQuickOpen();
  await page.locator('#quick-open-input').fill('large-workbook.xlsx');
  await page.getByRole('option', { name: /large-workbook\.xlsx/ }).click();
  await expect(page.locator('td[data-cell="A1"]')).toHaveText('START');
  return app;
}

// Reaching the last cell with bounded nodes is the viewer's own test
// (office-viewer tools/excel-virtual.test.mjs). Desktop sizes the viewport
// with its own CSS, so the search case below keeps the node bound.
test('Excel search and feedback retain source addresses beyond the old preview window', async ({ page }) => {
  const app = await openWorkbook(page);
  const search = page.locator('.office-viewer-find input');
  await search.fill('BEYOND_1000');
  await expect(page.locator('td.office-search-hit')).toHaveText('BEYOND_1000');
  await expect(page.locator('td[data-cell="B1200"]')).toHaveAttribute('data-formula', '21*2');
  await page.locator('td[data-cell="A1200"]').click();
  await expect(page.locator('.office-selection-preview')).toHaveAttribute('title', /Sparse!A1200/);
  await page.locator('td[data-cell="B1200"]').click();
  await expect(page.locator('.office-selection-preview')).toHaveAttribute('title', /Sparse!B1200/);
  await search.click();
  await search.fill('COLUMN_TAIL');
  await expect(page.locator('td.office-search-hit')).toHaveAttribute('data-cell', 'IW1201');
  await expect.poll(() => page.locator('td[data-cell]').count()).toBeLessThan(3000);
  await page.locator('td[data-cell="IW1201"]').click();
  await expect(page.locator('.office-selection-preview')).toHaveAttribute('title', /Sparse!IW1201/);
  expect(app.pageErrors).toEqual([]);
});

test('typed Excel feedback resolves its source again when virtual rows return', async ({ page }) => {
  const app = await openWorkbook(page);
  const search = page.locator('.office-viewer-find input');
  await search.fill('BEYOND_1000');
  await page.locator('td[data-cell="A1200"]').click();
  const feedback = page.locator('.office-selection-preview');
  await expect(feedback).toHaveAttribute('title', /Sparse!A1200/);
  await feedback.locator('textarea').fill('Inspect this sparse row');
  await search.click();
  await search.fill('LAST_CELL');
  await expect(page.locator('td[data-cell="XFD1048576"]')).toBeInViewport();
  await search.click();
  await search.fill('BEYOND_1000');
  await expect(feedback.locator('textarea')).toBeVisible();
  await expect(feedback.locator('textarea')).toHaveValue('Inspect this sparse row');
  await expect(feedback).toHaveAttribute('title', /Sparse!A1200/);
  expect(app.pageErrors).toEqual([]);
});

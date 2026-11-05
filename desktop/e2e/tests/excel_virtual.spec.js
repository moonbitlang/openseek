import { test, expect } from './support/test.js';
import { readFileSync, mkdirSync } from 'node:fs';
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

test('Excel scrolls to its final row and column without a dense cell DOM', async ({ page }) => {
  await page.addInitScript(() => {
    window.maxVirtualCells = 0;
    new MutationObserver(() => {
      window.maxVirtualCells = Math.max(window.maxVirtualCells, document.querySelectorAll('.office-virtual-table td[data-cell]').length);
    }).observe(document, { childList: true, subtree: true });
  });
  const app = await openWorkbook(page);
  const viewport = page.locator('section[data-sheet="Sparse"] .office-sheet-viewport');
  await expect.poll(() => page.locator('td[data-cell]').count()).toBeLessThan(3000);
  await viewport.evaluate(node => { node.scrollTop = node.scrollHeight; node.scrollLeft = node.scrollWidth; });
  await expect(page.locator('td[data-cell="XFD1048576"]')).toBeInViewport();
  await expect(page.locator('td[data-cell="XFD1048576"]')).toHaveText('LAST_CELL');
  await expect.poll(() => page.locator('td[data-cell]').count()).toBeLessThan(3000);
  await page.locator('td[data-cell="XFD1048576"]').click();
  await expect(page.locator('.office-selection-preview')).toHaveAttribute('title', /Sparse!XFD1048576/);
  mkdirSync('/tmp/openseek-large-workbook-audit', { recursive: true });
  const toolbar = await page.locator('.viewer-breadcrumb').boundingBox();
  const size = page.viewportSize();
  await page.screenshot({path:'/tmp/openseek-large-workbook-audit/excel-full-range.png',clip:{x:Math.floor(toolbar.x),y:0,width:size.width-Math.floor(toolbar.x),height:Math.min(size.height,720)}});
  await expect(page.locator('.truncated')).toHaveCount(0);
  expect(await page.evaluate(() => window.maxVirtualCells)).toBeLessThan(3000);
  expect(app.pageErrors).toEqual([]);
});

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

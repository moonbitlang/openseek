import { test, expect } from '@playwright/test';
import { readFileSync, mkdirSync } from 'node:fs';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

async function openWorkbook(page) {
  const app = new DesktopBrowserHarness(page);
  app.officeFiles['docs/clipboard.xlsx'] = {
    data_base64: readFileSync(new URL('../fixtures/office/clipboard.xlsx', import.meta.url)).toString('base64'),
    media_type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    sig: 'office:clipboard',
  };
  app.directoryEntries['/workspace'] = [{ name: 'docs', is_dir: true }];
  app.directoryEntries['/workspace/docs'] = [{ name: 'clipboard.xlsx', is_dir: false }];
  app.searchFiles = ['docs/clipboard.xlsx'];
  await app.install();
  await app.goto();
  await app.openSession();
  await page.getByRole('button', { name: 'Hide sidebar', exact: true }).click();
  await app.openReview({ waitForHistory: false });
  await page.getByRole('tab', { name: 'Files', exact: true }).click();
  await app.openQuickOpen();
  await page.locator('#quick-open-input').fill('clipboard.xlsx');
  await page.getByRole('option', { name: /clipboard\.xlsx/ }).click();
  await expect(page.locator('section[data-sheet="Clipboard"]')).toBeVisible();
  return app;
}

async function selectRange(page, start, end, sheet = 'Clipboard') {
  const section = page.locator(`section[data-sheet="${sheet}"]`);
  const first = await section.locator(`td[data-cell="${start}"]`).boundingBox();
  const last = await section.locator(`td[data-cell="${end}"]`).boundingBox();
  await page.mouse.move(first.x + first.width / 2, first.y + first.height / 2);
  await page.mouse.down();
  await page.mouse.move(last.x + last.width / 2, last.y + last.height / 2);
  await page.mouse.up();
  await expect(page.getByRole('button', { name: 'Copy table', exact: true })).toBeVisible();
}

async function captureCopyPane(page, filename) {
  mkdirSync('/tmp/openseek-excel-copy', { recursive: true });
  const toolbar = await page.locator('.viewer-breadcrumb').boundingBox();
  const viewport = page.viewportSize();
  const left = Math.floor(toolbar.x);
  await page.screenshot({
    path: `/tmp/openseek-excel-copy/${filename}`,
    clip: { x: left, y: 0, width: viewport.width - left, height: Math.min(370, viewport.height) },
  });
}

test('Excel copies real selected values as TSV and literal Markdown without attaching context', async ({ page, context }) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  const app = await openWorkbook(page);
  await expect(page.locator('.excel-copy-controls')).toHaveCount(0);
  await selectRange(page, 'A1', 'C2');
  await page.getByRole('button', { name: 'Copy table', exact: true }).click();
  await expect(page.locator('.excel-copy-feedback')).toHaveText('Copied');
  const tsv = '商品\t说明\t金额\r\n月光杯 🌙\t"管道|反斜\\\n""引号""\t<文字>"\t123';
  await expect.poll(() => page.evaluate(() => navigator.clipboard.readText()).then(text => text.replaceAll('\r\n', '\n')))
    .toBe(tsv.replaceAll('\r\n', '\n'));
  await page.getByRole('button', { name: 'Copy as Markdown table', exact: true }).click();
  await expect.poll(() => page.evaluate(() => navigator.clipboard.readText()))
    .toBe('| 商品 | 说明 | 金额 |\n| --- | --- | --- |\n| 月光杯 🌙 | 管道\\|反斜\\\\<br>"引号"\t&lt;文字&gt; | 123 |');
  await expect(page.locator('.mention-chip')).toHaveCount(0);
  await expect(page.locator('.office-selection-preview textarea')).toHaveValue('');
  await captureCopyPane(page, 'selection-copy.png');
  await expect(page.locator('.excel-copy-controls')).toBeVisible();
  await page.getByRole('tab', { name: 'Long', exact: true }).click();
  await expect(page.locator('.excel-copy-controls')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('Excel table copy retains merged coverage and a trailing empty row', async ({ page, context }) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  const app = await openWorkbook(page);
  await selectRange(page, 'A3', 'C4');
  await page.getByRole('button', { name: 'Copy table', exact: true }).click();
  await expect.poll(() => page.evaluate(() => navigator.clipboard.readText()).then(text => text.replaceAll('\r\n', '\n')))
    .toBe('合并\t\tEND\n\t\t');
  // Clipboard bytes can be visible before the asynchronous completion enables the button.
  await expect(page.getByRole('button', { name: 'Copy table', exact: true })).toBeEnabled();
  await page.getByRole('button', { name: 'Copy table', exact: true }).press('Escape');
  await expect(page.locator('.excel-copy-controls')).toHaveCount(0);
  await expect(page.locator('.office-cell-selected')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('Excel copy controls remain usable in a narrow pane', async ({ page }) => {
  const app = await openWorkbook(page);
  await selectRange(page, 'A1', 'C2');
  await page.setViewportSize({ width: 1000, height: 800 });
  for (const label of ['Copy table', 'Copy as Markdown table', 'Zoom in', 'Document fonts']) {
    const button = page.getByRole('button', { name: label, exact: true });
    await expect(button).toBeVisible();
    const rect = await button.boundingBox();
    expect(rect.x).toBeGreaterThanOrEqual(0);
    expect(rect.x + rect.width).toBeLessThanOrEqual(1000);
  }
  await captureCopyPane(page, 'selection-copy-narrow.png');
  expect(app.pageErrors).toEqual([]);
});

test('Excel copy reports clipboard failure and can retry', async ({ page }) => {
  const app = await openWorkbook(page);
  await page.evaluate(() => {
    window.failExcelCopy = true;
    window.excelCopies = [];
    Object.defineProperty(navigator.clipboard, 'writeText', {
      configurable: true,
      value: text => {
        if (window.failExcelCopy) return Promise.reject(new Error('denied'));
        window.excelCopies.push(text);
        return Promise.resolve();
      },
    });
  });
  await selectRange(page, 'A1', 'A1');
  const button = page.getByRole('button', { name: 'Copy table', exact: true });
  await button.click();
  await expect(page.locator('.excel-copy-feedback')).toHaveText('Copy failed. Try again.');
  await expect(button).toBeEnabled();
  await page.evaluate(() => { window.failExcelCopy = false; });
  await button.click();
  await expect(page.locator('.excel-copy-feedback')).toHaveText('Copied');
  expect(await page.evaluate(() => window.excelCopies)).toEqual(['商品']);
  expect(app.pageErrors).toEqual([]);
});

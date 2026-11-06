import { test, expect } from './support/test.js';
import { readFileSync } from 'node:fs';
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
  await page.locator("#sidebar-toggle[aria-expanded=\"true\"]").click();
  await app.openReview({ waitForHistory: false });
  await page.locator('#explorer-files-tab').click();
  await app.openQuickOpen();
  await page.locator('#quick-open-input').fill('clipboard.xlsx');
  await page.locator('[role=option][data-path="docs/clipboard.xlsx"]').click();
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
  await expect(page.locator('.excel-copy-table')).toBeVisible();
}

test('Excel copies real selected values as TSV and literal Markdown without attaching context', async ({ page, context }) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  const app = await openWorkbook(page);
  await expect(page.locator('.excel-copy-controls')).toHaveCount(0);
  await selectRange(page, 'A1', 'C2');
  await page.locator('.excel-copy-table').click();
  await expect(page.locator('.excel-copy-feedback')).toHaveText('Copied');
  const tsv = '商品\t说明\t金额\r\n月光杯 🌙\t"管道|反斜\\\n""引号""\t<文字>"\t123';
  await expect.poll(() => page.evaluate(() => navigator.clipboard.readText()).then(text => text.replaceAll('\r\n', '\n')))
    .toBe(tsv.replaceAll('\r\n', '\n'));
  await page.locator('.excel-copy-markdown').click();
  await expect.poll(() => page.evaluate(() => navigator.clipboard.readText()))
    .toBe('| 商品 | 说明 | 金额 |\n| --- | --- | --- |\n| 月光杯 🌙 | 管道\\|反斜\\\\<br>"引号"\t&lt;文字&gt; | 123 |');
  await expect(page.locator('.mention-chip')).toHaveCount(0);
  await expect(page.locator('.office-selection-preview textarea')).toHaveValue('');
  await expect(page.locator('.excel-copy-controls')).toBeVisible();
  await page.locator('[role=tab][data-excel-sheet-tab="Long"]').click();
  await expect(page.locator('.excel-copy-controls')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('Excel table copy retains merged coverage and a trailing empty row', async ({ page, context }) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  const app = await openWorkbook(page);
  await selectRange(page, 'A3', 'C4');
  await page.locator('.excel-copy-table').click();
  await expect.poll(() => page.evaluate(() => navigator.clipboard.readText()).then(text => text.replaceAll('\r\n', '\n')))
    .toBe('合并\t\tEND\n\t\t');
  // Clipboard bytes can be visible before the asynchronous completion enables the button.
  await expect(page.locator('.excel-copy-table')).toBeEnabled();
  await page.locator('.excel-copy-table').press('Escape');
  await expect(page.locator('.excel-copy-controls')).toHaveCount(0);
  await expect(page.locator('.office-cell-selected')).toHaveCount(0);
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
  const button = page.locator('.excel-copy-table');
  await button.click();
  await expect(page.locator('.excel-copy-feedback')).toHaveText('Copy failed. Try again.');
  await expect(button).toBeEnabled();
  await page.evaluate(() => { window.failExcelCopy = false; });
  await button.click();
  await expect(page.locator('.excel-copy-feedback')).toHaveText('Copied');
  expect(await page.evaluate(() => window.excelCopies)).toEqual(['商品']);
  expect(app.pageErrors).toEqual([]);
});

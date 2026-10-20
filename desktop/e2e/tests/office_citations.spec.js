import { test, expect } from '@playwright/test';
import { readFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

async function openAnswer(page, answer) {
  const app = new DesktopBrowserHarness(page);
  app.officeFiles['docs/review.docx'] = {
    data_base64: readFileSync(new URL('../fixtures/office/review-comments.docx', import.meta.url)).toString('base64'),
    media_type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', sig: 'demo:review',
  };
  app.officeFiles['docs/sales.xlsx'] = {
    data_base64: readFileSync(new URL('../fixtures/office/quarter-sales.xlsx', import.meta.url)).toString('base64'),
    media_type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', sig: 'demo:sales',
  };
  app.sessionEvents = [
    { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture citations；核对这些文档中的来源。' } } },
    { sequence: 2, item: { kind: 'assistant', payload: { content: answer } } },
  ];
  await page.setViewportSize({ width: 1700, height: 1000 });
  await app.install();
  await app.goto();
  await app.openSession();
  return app;
}

async function capture(page, name) {
  if (process.env.OPENSEEK_UI_CAPTURE_DIR) {
    mkdirSync(process.env.OPENSEEK_UI_CAPTURE_DIR, { recursive: true });
    await page.screenshot({ path: join(process.env.OPENSEEK_UI_CAPTURE_DIR, name) });
  }
}

test('PDF citations open the exact physical page from inline badges, cards and saved page labels', async ({ page }) => {
  const app = await openAnswer(page, [
    '第二页支持此结论。[^1] 第一页给出口径。[^2] 已保存的引用。[^3] 缺失页。[^4]',
    '[^1]: [演示报告](/workspace/docs/report.pdf#page=2) — 第 2 页。',
    '[^2]: [演示报告](/workspace/docs/report.pdf#page=1) — 第 1 页。',
    '[^3]: [演示报告](/workspace/docs/report.pdf) — 第 2 页。',
    '[^4]: [演示报告](/workspace/docs/report.pdf#page=99) — 第 99 页。',
  ].join('\n\n'));
  const citation = number => page.locator(`.citation[data-citation="${number}"] button`);
  await citation(1).click();
  const second = page.locator('.page[data-page-number="2"]');
  await expect(second).toHaveClass(/office-citation-target/);
  await expect(second).toBeInViewport();
  await expect(second).toHaveCSS('outline-width', '3px');
  await expect(page.getByRole('spinbutton', { name: 'PDF page number', exact: true })).toHaveValue('2');
  await expect(page.locator('.office-selection-preview')).toBeHidden();
  await capture(page, 'office-citation-pdf.png');
  await page.locator('.citation-sources summary').click();
  await page.locator('.citation-source[data-source="2"]').click();
  await expect(page.locator('.page[data-page-number="1"]')).toHaveClass(/office-citation-target/);
  await expect(page.locator('.office-citation-target')).toHaveCount(1);
  await citation(3).click();
  await expect(second).toHaveClass(/office-citation-target/);
  await citation(4).click();
  await expect(page.locator('.file-panel-error')).toContainText('cited location');
  await expect(page.locator('#openseek-office-surface')).toBeVisible();
  expect(app.requests.filter(r => r.method === 'host.open_path').every(r => !r.params.path.includes('#'))).toBe(true);
  expect(app.pageErrors).toEqual([]);
});

test('Word citations highlight a proven source paragraph and a unique heading without selecting text', async ({ page }) => {
  const heading = encodeURIComponent('01  阅读与引用');
  const app = await openAnswer(page, [
    '正文介绍文档评审。[^1] 阅读与引用见章节。[^2] 无法找到的章节。[^3]',
    '[^1]: [示例段落](/workspace/docs/report.docx#paragraph=%2Fdocx%2Fbody%2Fp%5B1%5D) — 第一段。',
    `[^2]: [评审演示](/workspace/docs/review.docx#heading=${heading}) — 阅读与引用。`,
    '[^3]: [评审演示](/workspace/docs/review.docx#heading=Missing%20heading) — 未找到。',
  ].join('\n\n'));
  await page.locator('.citation[data-citation="1"] button').click();
  await expect(page.locator('text.office-citation-target')).toContainText(['Walking on imported air']);
  await expect(page.locator('.office-citation-highlight')).toHaveCount(1);
  await page.locator('.citation-sources summary').click();
  await page.locator('.citation-source[data-source="2"]').click();
  await expect(page.locator('text.office-citation-target')).toContainText(['01  阅读与引用']);
  await expect(page.locator('text.office-citation-target')).toBeInViewport();
  await expect(page.locator('.office-selection-preview')).toBeHidden();
  await expect(page.locator('.mention-chip')).toHaveCount(0);
  await capture(page, 'office-citation-word.png');
  await page.locator('.citation[data-citation="3"] button').click();
  await expect(page.locator('.file-panel-error')).toContainText('cited location');
  await expect(page.locator('.office-citation-target')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('Excel citation cards switch worksheets and highlight only the exact cited range', async ({ page }) => {
  const app = await openAnswer(page, [
    '季度汇总支持此结论。[^1] 明细在另一个工作表。[^2] 预览外的位置。[^3] 合并单元格标题。[^4]',
    `[^1]: [销售演示](/workspace/docs/sales.xlsx#sheet=${encodeURIComponent('季度汇总')}&range=C5:C8) — 季度汇总，C5:C8。`,
    `[^2]: [销售演示](/workspace/docs/sales.xlsx#sheet=${encodeURIComponent('销售明细')}&range=A5:B6) — 销售明细，A5:B6。`,
    `[^3]: [销售演示](/workspace/docs/sales.xlsx#sheet=${encodeURIComponent('季度汇总')}&range=C9000) — 预览外。`,
    `[^4]: [销售演示](/workspace/docs/sales.xlsx#sheet=${encodeURIComponent('销售明细')}&range=A1:B1) — 合并标题。`,
  ].join('\n\n'));
  await page.locator('.citation[data-citation="1"] button').click();
  const summary = page.locator('section[data-sheet="季度汇总"]');
  await expect(summary).toBeVisible();
  await expect(summary.locator('td.office-citation-target')).toHaveCount(4);
  await expect(summary.locator('[data-cell="C5"]')).toBeInViewport();
  await expect(page.getByRole('tab', { name: '季度汇总', exact: true })).toHaveAttribute('aria-selected', 'true');
  await capture(page, 'office-citation-excel.png');
  await page.locator('.citation-sources summary').click();
  await page.locator('.citation-source[data-source="2"]').click();
  const detail = page.locator('section[data-sheet="销售明细"]');
  await expect(detail).toBeVisible();
  await expect(summary).toBeHidden();
  await expect(detail.locator('td.office-citation-target')).toHaveCount(4);
  await expect(page.locator('.office-selection-preview')).toBeHidden();
  await expect(page.locator('.mention-chip')).toHaveCount(0);
  await page.locator('.citation[data-citation="3"] button').click();
  await expect(page.locator('.file-panel-error')).toContainText('cited location');
  await expect(page.locator('.office-citation-target')).toHaveCount(0);
  await page.locator('.citation[data-citation="4"] button').click();
  await expect(detail.locator('td.office-citation-target')).toHaveCount(1);
  await expect(detail.locator('[data-cell="A1"]')).toHaveClass(/office-citation-target/);
  expect(app.pageErrors).toEqual([]);
});

test('Excel citations prepare a lazy viewer range before querying cells and preserve its scroll position', async ({ page }) => {
  const sheet = encodeURIComponent('季度汇总');
  const app = await openAnswer(page, [
    '初始位置。[^1] 延迟加载的范围。[^2]',
    `[^1]: [销售演示](/workspace/docs/sales.xlsx#sheet=${sheet}&range=C5:C8)`,
    `[^2]: [销售演示](/workspace/docs/sales.xlsx#sheet=${sheet}&range=A5000:C9000)`,
  ].join('\n\n'));
  await page.locator('.citation[data-citation="1"] button').click();
  await expect(page.locator('td.office-citation-target')).toHaveCount(4);
  // Exercise the optional viewer-provider contract independently of the
  // installed viewer version. The real full-sheet provider has its own tests.
  await page.evaluate(() => {
    window.lazyCitationCalls = []; window.lazyCitationScrolls = 0;
    const host = document.getElementById('openseek-office-surface');
    host.__officeRevealExcelCell = (sheet, row, column) => {
      const section = [...host.querySelectorAll('section[data-sheet]')].find(node => node.dataset.sheet === '季度汇总');
      const table = section.querySelector('table');
      table.classList.add('office-virtual-table');
      window.lazyCitationCalls.push({sheet, row, column});
      if (sheet !== '季度汇总' || row > 9000 || column > 3) return false;
      const address = String.fromCharCode(64 + column) + row;
      table.querySelector('tbody').innerHTML = `<tr><td data-cell="${address}" data-row="${row}" data-col="${column}">Lazy source</td></tr>`;
      table.querySelector('td').scrollIntoView = () => { window.lazyCitationScrolls++; };
      return true;
    };
  });
  await page.locator('.citation[data-citation="2"] button').click();
  await expect(page.locator('td[data-cell="A5000"]')).toHaveClass(/office-citation-target/);
  expect(await page.evaluate(() => window.lazyCitationCalls)).toEqual([
    {sheet:'季度汇总', row:9000, column:3}, {sheet:'季度汇总', row:5000, column:1},
  ]);
  expect(await page.evaluate(() => window.lazyCitationScrolls)).toBe(0);
  await page.evaluate(() => {
    document.querySelector('table.office-virtual-table tbody').innerHTML = '<tr><td data-cell="A7000" data-row="7000" data-col="1">Recycled source</td></tr>';
  });
  await expect(page.locator('td[data-cell="A7000"]')).toHaveClass(/office-citation-target/);
  await expect(page.locator('.office-selection-preview')).toBeHidden();
  expect(app.pageErrors).toEqual([]);
});

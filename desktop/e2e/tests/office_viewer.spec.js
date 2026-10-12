import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';
import { pinchZoom } from './support/office_zoom.js';

async function annotateSelection(preview) {
  await expect(preview.locator('textarea')).toBeVisible();
  await expect(preview).not.toHaveAttribute('title', '');
  const source = await preview.getAttribute('title');
  await preview.locator('textarea').fill(source.slice(source.indexOf('\n') + 1).trim() || 'Inspect selected cells');
  await preview.getByRole('checkbox').check();
  await preview.locator('textarea').press('Enter');
}

async function applicationStyles(page) {
  return page.evaluate(() => {
    let probe = document.getElementById('xlsx-style-probe');
    if (!probe) {
      probe = document.createElement('div');
      probe.id = 'xlsx-style-probe';
      probe.style.display = 'none';
      probe.innerHTML = '<h2>Outside heading</h2><table><tbody><tr><td class="s1">Outside cell</td></tr></tbody></table>';
      document.body.append(probe);
    }
    const snapshot = (element) => {
      const style = getComputedStyle(element);
      return Object.fromEntries([
        'font-family', 'font-size', 'font-weight', 'color', 'margin',
        'padding', 'border', 'border-collapse',
      ].map(property => [property, style.getPropertyValue(property)]));
    };
    return {
      body: snapshot(document.body),
      heading: snapshot(probe.querySelector('h2')),
      table: snapshot(probe.querySelector('table')),
      cell: snapshot(probe.querySelector('td')),
    };
  });
}

test('the sales demonstration workbook opens both sheets and quotes calculated cells', async ({ page }) => {
  await page.setViewportSize({ width: 1600, height: 1000 });
  const app = new DesktopBrowserHarness(page);
  app.officeFiles['docs/季度销售演示.xlsx'] = {
    data_base64: readFileSync(new URL('../fixtures/office/quarter-sales.xlsx', import.meta.url)).toString('base64'),
    media_type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    sig: 'office:quarter-sales',
  };
  app.directoryEntries['/workspace'] = [{ name: 'docs', is_dir: true }];
  app.directoryEntries['/workspace/docs'] = [{ name: '季度销售演示.xlsx', is_dir: false }];
  app.searchFiles = ['docs/季度销售演示.xlsx'];
  await app.install();
  await app.goto();
  await app.openSession();
  await page.getByRole('button', { name: 'Hide sidebar', exact: true }).click();
  await app.openReview({ waitForHistory: false });
  await page.getByRole('tab', { name: 'Files', exact: true }).click();
  const outsideStyles = await applicationStyles(page);
  await app.openQuickOpen();
  await page.locator('#quick-open-input').fill('季度销售演示.xlsx');
  await page.getByRole('option', { name: /季度销售演示\.xlsx/ }).click();

  const detail = page.locator('section[data-sheet="销售明细"]');
  const summary = page.locator('section[data-sheet="季度汇总"]');
  await expect(detail).toBeVisible();
  await expect(summary).toBeHidden();
  await expect(detail.locator('td[data-cell="E11"]')).toHaveText('¥195,855.00');
  await expect(detail.locator('td[data-cell="A1"]')).toHaveCSS('font-weight', '700');
  await pinchZoom(page, detail.locator('td[data-cell="A1"]'));
  await expect(page.locator('.sheet-document')).toHaveCSS('zoom', '1.11');
  expect(await applicationStyles(page)).toEqual(outsideStyles);
  await expect(page.locator('td[data-formula]')).toHaveCount(20);
  await expect(page.locator('td.formula-pending')).toHaveCount(0);
  await page.getByRole('tab', { name: '季度汇总', exact: true }).click();
  await expect(summary).toBeVisible();
  await expect(detail).toBeHidden();
  await expect(summary.locator('td[data-cell="C8"]')).toHaveText('¥195,855.00');
  await summary.locator('td[data-cell="C5"]').click();
  const preview = page.locator('.office-selection-preview');
  await expect(preview).toBeVisible();
  await expect.poll(() => preview.getAttribute('title')).toContain('季度汇总!C5');
  await expect.poll(() => preview.getAttribute('title')).toContain('¥53,820.00');
  await expect(page.locator('.mention-chip')).toHaveCount(0);
  await annotateSelection(preview);
  await expect(page.locator('.mention-chip')).toContainText('季度汇总!C5');
  await page.getByRole('tab', { name: '销售明细', exact: true }).click();
  await expect(detail).toBeVisible();
  await expect(detail.locator('td[data-cell="E5"]')).toHaveText('¥23,880.00');
  expect(await applicationStyles(page)).toEqual(outsideStyles);
  expect(app.pageErrors).toEqual([]);
});

test('file tabs render real DOCX and XLSX packages through the Office surface', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.directoryEntries['/workspace'] = [{ name: 'docs', is_dir: true }];
  app.directoryEntries['/workspace/docs'] = [
    { name: 'report.docx', is_dir: false },
    { name: 'book1.xlsx', is_dir: false },
  ];
  app.searchFiles = ['docs/report.docx', 'docs/book1.xlsx'];
  await app.install();
  await app.goto();
  await app.openSession();

  await page.getByRole('button', { name: 'Hide sidebar', exact: true }).click();
  await app.openReview({ waitForHistory: false });
  await page.getByRole('tab', { name: 'Files', exact: true }).click();

  await app.openQuickOpen();
  await page.locator('#quick-open-input').fill('report.docx');
  await page.getByRole('option', { name: /report\.docx/ }).click();
  await expect(page.locator('.office-viewer-surface.word-surface')).toBeVisible();
  await expect(page.locator('.word-page')).toContainText('Walking on imported air');
  await expect(page.locator('.viewer-notice')).toHaveClass(/hidden/);
  await expect(page.locator('.office-viewer-toolbar')).toBeVisible();
  await expect(page.locator('.office-viewer-zoom-value')).toHaveText('100%');
  await page.getByRole('button', { name: 'Zoom in', exact: true }).click();
  await expect(page.locator('.office-viewer-zoom-value')).toHaveText('110%');
  await expect(page.locator('#openseek-office-surface')).toHaveCSS('--office-zoom', '1.1');
  await expect(page.locator('.word-page').first()).toHaveCSS('zoom', '1.1');
  await pinchZoom(page, page.locator('.word-page svg text').first());
  await expect(page.locator('.word-page').first()).toHaveCSS('zoom', '1.22');
  await page.getByRole('searchbox', { name: 'Find in document', exact: true }).fill('Walking');
  await expect(page.locator('.word-page svg text.office-search-hit')).toHaveCount(1);
  await page.getByRole('button', { name: 'Document fonts', exact: true }).click();
  await expect(page.locator('#openseek-office-surface')).toHaveClass(/prefer-system-fonts/);

  await app.openQuickOpen();
  await page.locator('#quick-open-input').fill('book1.xlsx');
  await page.getByRole('option', { name: /book1\.xlsx/ }).click();
  await expect(page.locator('.office-viewer-surface.sheet-surface')).toBeVisible();
  await expect(page.locator('.sheet-document table').first()).toBeVisible();
  // E11 is an uncached formula in the fixture (B2+B3). The Office surface
  // must show the calculated result instead of exposing formula-pending text.
  await expect(page.locator('td[data-cell="E11"]')).toHaveText('43');
  await expect(page.locator('td.formula-pending')).toHaveCount(0);
  await expect(page.locator('.word-page')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('Word selections preview, cancel and accumulate only after confirmation', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.directoryEntries['/workspace'] = [{ name: 'docs', is_dir: true }];
  app.directoryEntries['/workspace/docs'] = [{ name: 'report.docx', is_dir: false }];
  app.searchFiles = ['docs/report.docx'];
  await app.install();
  await app.goto();
  await app.openSession();
  await page.getByRole('button', { name: 'Hide sidebar', exact: true }).click();
  await app.openReview({ waitForHistory: false });
  await page.getByRole('tab', { name: 'Files', exact: true }).click();
  await app.openQuickOpen();
  await page.locator('#quick-open-input').fill('report.docx');
  await page.getByRole('option', { name: /report\.docx/ }).click();
  await expect(page.locator('.word-page svg text').first()).toBeVisible();
  await pinchZoom(page, page.locator('.word-page svg text').first());

  // Exercise the browser's native SVG Range path used by office-viewer. The
  // viewer's document-level selectionchange listener then emits its JSON
  // envelope through the real Rabbita command bridge.
  const wordText = page.locator('.word-page svg text').first();
  const selectWord = async (end) => wordText.evaluate((element, end) => {
    const range = document.createRange();
    if (end) {
      range.setStart(element.firstChild, 0);
      range.setEnd(element.firstChild, end);
    } else range.selectNodeContents(element);
    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
    document.dispatchEvent(new Event('selectionchange'));
  }, end);
  const preview = page.locator('.office-selection-preview');
  await wordText.dispatchEvent('pointerdown', { button: 0, isPrimary: true });
  await selectWord();
  // Let the host render while the user holds the mouse: no card mid-drag.
  await page.waitForTimeout(150);
  await expect(preview).toBeHidden();
  await wordText.dispatchEvent('pointerup', { button: 0, isPrimary: true });
  await expect(preview).toBeVisible();
  await expect.poll(() => preview.getAttribute('title')).toContain('report.docx');
  await expect.poll(() => preview.getAttribute('title')).toContain('Walking on imported air');
  await expect(page.locator('.mention-chip')).toHaveCount(0);
  await preview.locator('textarea').fill('Inspect this paragraph');
  await expect(preview.locator('.feedback-source-selection').first()).toBeVisible();
  await preview.locator('textarea').press('Escape');
  await expect(preview.locator('.feedback-source-selection')).toHaveCount(0);
  await expect(preview).toBeHidden();
  await expect(page.locator('.mention-chip')).toHaveCount(0);
  await selectWord();
  await expect(preview).toBeVisible();
  await annotateSelection(preview);
  await expect(preview).toBeHidden();
  await expect(page.locator('.mention-chip')).toContainText('report.docx');
  await expect(page.locator('.mention-chip')).toContainText('Walking on imported air');
  await expect(page.locator('.mention-chip .mention-body')).toHaveAttribute('title', /Walking on imported air/);
  await selectWord(7);
  await expect.poll(() => preview.getAttribute('title')).toContain('Walking');
  await expect(page.locator('.mention-chip')).toHaveCount(1);
  await annotateSelection(preview);
  await expect(page.locator('.mention-chip')).toHaveCount(2);
  // Reaccepting the same passage keeps a single copy of that quotation.
  await selectWord(7);
  await expect(preview).toBeVisible();
  await annotateSelection(preview);
  await expect(page.locator('.mention-chip')).toHaveCount(2);

  await page.locator('#task').fill('Explain the selected Office text');
  await page.getByTitle('Send', { exact: true }).click();
  await expect.poll(() => app.requests.find(request => request.method === 'agent.start')?.params.task)
    .toContain('<office_selection>');
  const task = app.requests.find(request => request.method === 'agent.start').params.task;
  expect(task).toContain('office.selection.materialized.v1');
  expect(task).toContain('Walking on imported air');
  expect(task).toContain('/workspace/docs/report.docx');
  expect(task).toContain('Explain the selected Office text');
  expect([...task.matchAll(/<office_selection>([\s\S]*?)<\/office_selection>/g)]).toHaveLength(2);
  expect(app.pageErrors).toEqual([]);
});

test('Excel ranges preview cell contents and retain separately confirmed context', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.directoryEntries['/workspace'] = [{ name: 'docs', is_dir: true }];
  app.directoryEntries['/workspace/docs'] = [{ name: 'book1.xlsx', is_dir: false }];
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
  const cells = page.locator('.sheet-document td[data-cell]');
  await expect(cells.first()).toBeVisible();
  await pinchZoom(page, cells.first());
  const first = await cells.first().boundingBox();
  const second = await cells.nth(Math.min(1, await cells.count() - 1)).boundingBox();
  const selectRange = async () => {
    await page.mouse.move(first.x + first.width / 2, first.y + first.height / 2);
    await page.mouse.down();
    await page.mouse.move(second.x + second.width / 2, second.y + second.height / 2);
    await page.mouse.up();
  };
  const preview = page.locator('.office-selection-preview');
  await selectRange();
  await expect(preview).toBeVisible();
  await expect.poll(() => preview.getAttribute('title')).toContain('A1:B1');
  await expect.poll(() => preview.getAttribute('title')).toContain(await cells.first().innerText());
  await expect(page.locator('.mention-chip')).toHaveCount(0);
  await preview.locator('textarea').press('Escape');
  await expect(preview).toBeHidden();
  await expect(page.locator('.mention-chip')).toHaveCount(0);
  await selectRange();
  await expect(preview).toBeVisible();
  await annotateSelection(preview);
  await expect(preview).toBeHidden();
  await expect(page.locator('.mention-chip')).toContainText('book1.xlsx');
  await expect(page.locator('.mention-chip')).toContainText('A1:B1');
  await cells.first().click();
  await expect.poll(() => preview.getAttribute('title')).toContain('!A1');
  await expect(page.locator('.mention-chip')).toHaveCount(1);
  await annotateSelection(preview);
  await expect(page.locator('.mention-chip')).toHaveCount(2);

  await page.locator('#task').fill('Inspect the selected cells');
  await page.getByTitle('Send', { exact: true }).click();
  await expect.poll(() => app.requests.find(request => request.method === 'agent.start')?.params.task)
    .toContain('<office_selection>');
  const task = app.requests.find(request => request.method === 'agent.start').params.task;
  expect(task).toContain('office.selection.materialized.v1');
  expect(task).toContain('/workspace/docs/book1.xlsx');
  const selectedCells = JSON.parse(task.match(/<office_selection>([\s\S]*?)<\/office_selection>/)[1]);
  expect(selectedCells.selection.kind).toBe('excel');
  expect(selectedCells.selection.range).toBe('A1:B1');
  expect(task).toContain('Inspect the selected cells');
  expect([...task.matchAll(/<office_selection>([\s\S]*?)<\/office_selection>/g)]).toHaveLength(2);
  expect(app.pageErrors).toEqual([]);
});


test('Word comments stay beside their source paragraphs and quote only after confirmation', async ({ page }) => {
  await page.setViewportSize({ width: 1600, height: 1000 });
  const app = new DesktopBrowserHarness(page);
  app.officeFiles['docs/comments.docx'] = {
    data_base64: readFileSync(new URL('../fixtures/office/review-comments.docx', import.meta.url)).toString('base64'),
    media_type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    sig: 'office:comments',
  };
  app.directoryEntries['/workspace'] = [{ name: 'docs', is_dir: true }];
  app.directoryEntries['/workspace/docs'] = [{ name: 'comments.docx', is_dir: false }];
  app.searchFiles = ['docs/comments.docx'];
  await app.install();
  await app.goto();
  await app.openSession();
  await page.getByRole('button', { name: 'Hide sidebar', exact: true }).click();
  await app.openReview({ waitForHistory: false });
  await page.getByRole('tab', { name: 'Files', exact: true }).click();
  await app.openQuickOpen();
  await page.locator('#quick-open-input').fill('comments.docx');
  await page.getByRole('option', { name: /comments\.docx/ }).click();

  const rail = page.locator('.office-context-rail');
  await expect(rail).toBeVisible();
  if (!await rail.evaluate(element => element.open)) await rail.locator('summary').click();
  const cards = rail.locator('.office-context-placed > .office-context-card');
  await expect(cards).toHaveCount(3);
  await expect(rail.locator('.office-context-unplaced > .office-context-card')).toHaveCount(0);
  await expect(page.locator('.office-context-layout')).toHaveCSS('display', 'flex');
  await expect(cards.first()).toHaveCSS('background-color', 'rgb(255, 255, 255)');
  await expect(cards.first()).toHaveCSS('display', 'block');
  await expect(cards.first().locator('.office-context-location')).toHaveText('Page 1');
  await expect(cards.first().locator('.office-context-quote')).toContainText('打开文档后');
  expect(await cards.allTextContents()).not.toEqual(expect.arrayContaining([
    expect.stringMatching(/docx\.comment:|p\[\d+\]|Resolution unknown|context only/),
  ]));
  const documentColumn = await page.locator('.office-context-document').boundingBox();
  const sidebar = await rail.boundingBox();
  expect(sidebar.x).toBeGreaterThanOrEqual(documentColumn.x + documentColumn.width);

  await cards.nth(1).getByRole('button', { name: 'Show source', exact: true }).click();
  await expect(page.locator('svg text[data-comment-path="p[5]"].office-annotation-focus')).toHaveCount(4);
  await expect(page.locator('.office-selection-preview')).toBeHidden();
  await cards.first().getByRole('button', { name: 'Quote comment', exact: true }).click();
  const preview = page.locator('.office-selection-preview');
  await expect(preview).toBeVisible();
  await expect.poll(() => preview.getAttribute('title')).toContain('建议保留明确的');
  await expect(page.locator('.mention-chip')).toHaveCount(0);
  await preview.locator('textarea').press('Escape');
  await expect(page.locator('.mention-chip')).toHaveCount(0);
  await cards.first().getByRole('button', { name: 'Quote comment', exact: true }).click();
  await annotateSelection(preview);
  await expect(page.locator('.mention-chip')).toHaveCount(1);
  await expect(page.locator('.mention-chip')).toContainText('建议保留明确的');

  await rail.locator('summary').click();
  await expect(rail).not.toHaveAttribute('open');
  await expect(rail).toHaveCSS('flex-basis', '36px');
  await expect(cards.first()).toBeHidden();
  expect(app.pageErrors).toEqual([]);
});

test('Excel annotation hides outside either horizontal edge and restores its draft', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.directoryEntries['/workspace'] = [{ name: 'docs', is_dir: true }];
  app.directoryEntries['/workspace/docs'] = [{ name: 'book1.xlsx', is_dir: false }];
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
  const table = page.locator('.sheet-document:visible table').first();
  await expect(table).toBeVisible();
  // Exercise native horizontal scrolling without a large binary fixture.
  await table.evaluate(element => { element.style.minWidth = '3000px'; });
  const row = table.locator('tr').filter({ has: page.locator('td[data-cell]') }).first();
  const cells = row.locator('td[data-cell]');
  const scroll = async edge => table.evaluate((element, edge) => {
    let viewport = element.parentElement;
    while (viewport && !(viewport.scrollWidth > viewport.clientWidth &&
      /auto|scroll/.test(getComputedStyle(viewport).overflowX))) {
      viewport = viewport.parentElement;
    }
    if (!viewport) throw new Error('Expected a horizontally scrollable sheet');
    viewport.scrollLeft = edge === 'right' ? viewport.scrollWidth : 0;
  }, edge);
  const input = page.locator('#office-feedback-input textarea');
  for (const [cell, home, away] of [
    [cells.first(), 'left', 'right'],
    [cells.last(), 'right', 'left'],
  ]) {
    await scroll(home);
    // Select at the visible portion of a cell wider than the viewport.
    const point = await cell.evaluate(element => {
      const bounds = element.getBoundingClientRect();
      let left = bounds.left, right = bounds.right;
      for (let parent = element.parentElement; parent; parent = parent.parentElement) {
        if (/auto|scroll|hidden/.test(getComputedStyle(parent).overflowX)) {
          const clip = parent.getBoundingClientRect();
          left = Math.max(left, clip.left);
          right = Math.min(right, clip.right);
        }
      }
      if (right <= left) throw new Error('Selected cell must intersect the viewport');
      return { x: (left + right) / 2, y: bounds.top + bounds.height / 2 };
    });
    await page.mouse.click(point.x, point.y);
    await expect(input).toBeVisible();
    await input.fill(`Retain ${home} draft`);
    await scroll(away);
    await expect(input).toBeHidden();
    await scroll(home);
    await expect(input).toBeVisible();
    await expect(input).toHaveValue(`Retain ${home} draft`);
    await input.press('Escape');
    await expect(input).toBeHidden();
  }
  expect(app.pageErrors).toEqual([]);
});

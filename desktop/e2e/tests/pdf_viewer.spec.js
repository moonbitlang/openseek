import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';
import { pinchZoom } from './support/office_zoom.js';
import { annotationPdf, formPdf, markupPdf } from './support/pdf_annotation_fixture.js';

async function annotateSelection(preview) {
  await expect(preview.locator('textarea')).toBeVisible();
  await expect(preview).not.toHaveAttribute('title', '');
  const source = await preview.getAttribute('title');
  await preview.locator('textarea').fill(source.slice(source.indexOf('\n') + 1).trim() || 'Inspect selected cells');
  await preview.getByRole('checkbox').check();
  await preview.locator('textarea').press('Enter');
}

async function openFile(app, name) {
  await app.openQuickOpen();
  await app.page.locator('#quick-open-input').fill(name);
  await app.page.getByRole('option', { name: new RegExp(name.replaceAll('.', '\\.')) }).click();
}

async function setup(page, { codex = false, openTree = true } = {}) {
  const app = new DesktopBrowserHarness(page);
  app.officeFiles['docs/broken.pdf'] = {
    data_base64: Buffer.from('invalid PDF data').toString('base64'),
    media_type: 'application/pdf', sig: 'pdf:broken',
  };
  app.searchFiles = ['docs/report.pdf', 'docs/encrypted.pdf', 'docs/broken.pdf', 'docs/report.docx'];
  app.officeFiles['docs/extensionless'] = app.officeFiles['docs/report.pdf'];
  app.searchFiles.push('docs/extensionless');
  app.directoryEntries['/workspace'] = [{ name: 'docs', is_dir: true }];
  app.directoryEntries['/workspace/docs'] = app.searchFiles.map(path => ({ name: path.split('/').at(-1), is_dir: false }));
  if (codex) app.codexModels = [{ id: 'gpt-test', displayName: 'Codex images', isDefault: true }];
  await app.install();
  await app.goto();
  if (!codex) await app.openSession();
  if (codex) {
    await page.getByRole('button', { name: 'Model', exact: true }).click();
    await page.getByRole('option', { name: 'Codex images', exact: true }).click();
    await expect(page.locator('#task')).toHaveAttribute('placeholder', 'Ask Codex to inspect, edit, or explain this workspace.');
  }
  await page.getByRole('button', { name: 'Hide sidebar', exact: true }).click();
  if (openTree) {
    await app.openReview({ waitForHistory: false });
    await page.getByRole('tab', { name: 'Files', exact: true }).click();
  }
  return app;
}

async function expectPdf(page) {
  await expect(page.locator('#openseek-office-surface')).toHaveAttribute('data-pdf-painted', 'true');
  await expect(page.locator('.pdfViewer .page')).toHaveCount(2);
  await expect(page.getByRole('spinbutton', { name: 'PDF page number', exact: true })).toBeEnabled();
  await expect(page.locator('.viewer-notice')).toHaveClass(/hidden/);
  await expect(page.getByRole('dialog', { name: 'Unlock PDF', exact: true })).toBeHidden();
}

test('opening a PDF defaults to a hidden tree and preserves manual reopening across files', async ({ page }) => {
  const app = await setup(page, { openTree: false });
  await expect(page.locator('.file-tree-pane')).toBeHidden();
  app.rpcDelays.set('fs.read_file', 1200);
  await page.evaluate(() => {
    window.pdfTreeFrames = [];
    window.recordPdfTree = true;
    const record = () => {
      if (!window.recordPdfTree) return;
      const active = document.querySelector('.editor-tab.active .tab-name');
      if (active?.textContent === 'report.pdf') {
        const tree = document.querySelector('.file-tree-pane');
        window.pdfTreeFrames.push({
          visible: tree.getClientRects().length > 0 && getComputedStyle(tree).visibility !== 'hidden',
          animations: tree.getAnimations().length,
        });
      }
      requestAnimationFrame(record);
    };
    requestAnimationFrame(record);
  });
  await openFile(app, 'report.pdf');
  await expectPdf(page);
  const frames = await page.evaluate(() => {
    window.recordPdfTree = false;
    return window.pdfTreeFrames;
  });
  expect(frames.length).toBeGreaterThan(0);
  expect(frames.every(frame => !frame.visible && frame.animations === 0)).toBe(true);
  app.rpcDelays.delete('fs.read_file');
  await expect(page.locator('.file-tree-pane')).toBeHidden();
  await page.getByTitle('Show file tree', { exact: true }).click();
  await expect(page.locator('.file-tree-pane')).toBeVisible();
  await page.getByRole('button', { name: 'Next page', exact: true }).click();
  await expect(page.getByRole('spinbutton', { name: 'PDF page number', exact: true })).toHaveValue('2');
  await expect(page.locator('.file-tree-pane')).toBeVisible();
  await openFile(app, 'report.docx');
  await expect(page.locator('.word-page').first()).toBeVisible();
  await expect(page.locator('.file-tree-pane')).toBeVisible();
  await openFile(app, 'report.pdf');
  await expectPdf(page);
  await expect(page.locator('.file-tree-pane')).toBeVisible();
  await page.locator('.editor-tab').filter({ hasText: 'report.docx' }).click();
  await expect(page.locator('.word-page').first()).toBeVisible();
  await page.locator('.editor-tab').filter({ hasText: 'report.pdf' }).click();
  await expectPdf(page);
  await expect(page.locator('.file-tree-pane')).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('opening an extensionless PDF from a hidden panel keeps the default tree closed', async ({ page }) => {
  const app = await setup(page, { openTree: false });
  await openFile(app, 'report.docx');
  await expect(page.locator('.word-page').first()).toBeVisible();
  await page.getByRole('button', { name: 'Hide panel', exact: true }).click();
  await expect(page.locator('.file-tree-pane')).toBeHidden();
  app.rpcDelays.set('fs.read_file', 1200);
  await page.evaluate(() => {
    window.extensionlessTreeFrames = [];
    window.recordExtensionlessTree = true;
    const record = () => {
      if (!window.recordExtensionlessTree) return;
      if (document.querySelector('.editor-tab.active .tab-name')?.textContent === 'extensionless') {
        const tree = document.querySelector('.file-tree-pane');
        window.extensionlessTreeFrames.push(
          (tree.getClientRects().length === 0 || getComputedStyle(tree).visibility === 'hidden') && tree.getAnimations().length === 0,
        );
      }
      requestAnimationFrame(record);
    };
    requestAnimationFrame(record);
  });
  await openFile(app, 'extensionless');
  await expectPdf(page);
  const frames = await page.evaluate(() => {
    window.recordExtensionlessTree = false;
    return window.extensionlessTreeFrames;
  });
  expect(frames.length).toBeGreaterThan(0);
  expect(frames.every(hidden => hidden)).toBe(true);
  expect(app.pageErrors).toEqual([]);
});

test('PDF controls and confirmed text selections retain structured context', async ({ page }) => {
  const app = await setup(page);
  await openFile(app, 'report.pdf');
  await expectPdf(page);
  await expect(page.locator('.textLayer').first()).toContainText('OpenSeek PDF preview');
  await expect(page.locator('.pdfViewer canvas').first()).toBeVisible();
  const zoom = Number((await page.locator('.office-viewer-zoom-value').innerText()).replace('%', ''));
  await page.getByRole('button', { name: 'Zoom in', exact: true }).click();
  await expect(page.locator('.office-viewer-zoom-value')).toHaveText(`${Math.min(400, Math.max(25, zoom + 10))}%`);
  await page.getByRole('button', { name: 'Fit page width', exact: true }).click();
  await expect.poll(() => page.locator('#openseek-office-surface').evaluate(host => host.__officeViewerPdf.viewer.currentScaleValue))
    .toBe('page-width');
  await page.getByRole('button', { name: 'Rotate clockwise', exact: true }).click();
  await expect.poll(() => page.locator('#openseek-office-surface').evaluate(host => host.__officeViewerPdf.viewer.pagesRotation)).toBe(90);
  await page.getByRole('searchbox', { name: 'Find in document', exact: true }).fill('Second');
  await expect(page.locator('.pdf-search-count')).toHaveText('1 / 1');
  await expect(page.getByRole('spinbutton', { name: 'PDF page number', exact: true })).toHaveValue('2');
  await page.getByRole('searchbox', { name: 'Find in document', exact: true }).fill('');
  // PDF.js removes match highlights asynchronously; until then the item's
  // text is split around a highlight span and has no single text node.
  await expect(page.locator('.textLayer .highlight')).toHaveCount(0);
  const second = page.locator('.page[data-page-number="2"] [data-pdf-item]').filter({ hasText: 'Second page selection' }).first();
  await expect(second).toBeVisible();
  await pinchZoom(page, second);
  await expect(second).toBeVisible();
  const selectSecond = async (end = 6) => second.evaluate((element, end) => {
    const range = document.createRange();
    range.setStart(element.firstChild, 0);
    range.setEnd(element.firstChild, end);
    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
    document.dispatchEvent(new Event('selectionchange'));
  }, end);
  const preview = page.locator('.office-selection-preview');
  await second.dispatchEvent('pointerdown', { button: 0, isPrimary: true, pointerId: 7 });
  await selectSecond();
  // Wait beyond the capture debounce while still holding the pointer.
  await page.waitForTimeout(150);
  await expect(preview).toBeHidden();
  await second.dispatchEvent('pointerup', { button: 0, isPrimary: true, pointerId: 7 });
  await expect(preview).toBeVisible();
  await expect.poll(() => preview.getAttribute('title')).toContain('report.pdf · p. 2');
  await expect.poll(() => preview.getAttribute('title')).toContain('Second');
  await expect(page.locator('.mention-chip')).toHaveCount(0);
  await preview.locator('textarea').press('Escape');
  await expect(preview).toBeHidden();
  await expect(page.locator('.mention-chip')).toHaveCount(0);
  await selectSecond();
  await expect(preview).toBeVisible();
  await annotateSelection(preview);
  await expect(preview).toBeHidden();
  await expect(page.locator('.mention-chip')).toContainText('report.pdf · p. 2');
  await expect(page.locator('.mention-chip')).toContainText('Second');
  await selectSecond(11);
  await expect.poll(() => preview.getAttribute('title')).toContain('Second page');
  await expect(page.locator('.mention-chip')).toHaveCount(1);
  await annotateSelection(preview);
  await expect(page.locator('.mention-chip')).toHaveCount(2);
  await page.locator('#task').fill('Explain this PDF passage');
  await page.getByTitle('Send', { exact: true }).click();
  await expect.poll(() => app.requests.find(request => request.method === 'agent.start')?.params.task).toContain('<office_selection>');
  const task = app.requests.find(request => request.method === 'agent.start').params.task;
  const selection = JSON.parse(task.match(/<office_selection>([\s\S]*?)<\/office_selection>/)[1]);
  expect(selection.schema).toBe('office.selection.materialized.v1');
  expect(selection.selection.text).toBe('Second');
  expect(selection.source.readable).toBe(true);
  expect(selection.source.reference.schema).toBe('office.pdf.text-range.v1');
  expect(selection.source.reference.file).toBe('/workspace/docs/report.pdf');
  expect(selection.source.reference.start.page).toBe(2);
  expect(selection.source.reference.end.offset_utf16).toBe(6);
  expect(selection.source.reference.document.sha256).toMatch(/^[0-9a-f]{64}$/);
  expect(selection.source.reference.document.parser).toEqual({ name: 'pdfjs', version: '6.4.299' });
  expect(task).toContain('Explain this PDF passage');
  expect([...task.matchAll(/<office_selection>([\s\S]*?)<\/office_selection>/g)]).toHaveLength(2);
  expect(app.pageErrors).toEqual([]);
});

test('PDF fit width follows panel animations while manual zoom stays fixed', async ({ page }) => {
  const app = await setup(page);
  await openFile(app, 'report.pdf');
  await expectPdf(page);
  await page.getByRole('button', { name: 'Fit page width', exact: true }).click();
  const surface = page.locator('#openseek-office-surface');
  const expectFits = async () => {
    await expect.poll(() => surface.evaluate(host => {
      const viewer = host.__officeViewerPdf.viewer;
      return Math.abs(viewer.getPageView(0).width - (viewer.container.clientWidth - 40));
    })).toBeLessThanOrEqual(2);
  };
  for (const name of ['Expand panel', 'Restore panel']) {
    await page.getByRole('button', { name, exact: true }).click();
    await expect.poll(() => page.locator('.content').evaluate(element => element.getAnimations().length)).toBe(0);
    await expectFits();
  }
  await page.getByRole('button', { name: 'Zoom in', exact: true }).click();
  // The zoom reaches PDF.js after the next render; reading the scale before
  // then would record the fitted value as the manual one.
  await expect.poll(() => surface.evaluate(host => host.__officeViewerPdf.viewer.currentScaleValue))
    .not.toBe('page-width');
  const scale = () => surface.evaluate(host => host.__officeViewerPdf.viewer.currentScale);
  const manualScale = await scale();
  await page.getByRole('button', { name: 'Expand panel', exact: true }).click();
  await expect.poll(() => page.locator('.content').evaluate(element => element.getAnimations().length)).toBe(0);
  expect(await scale()).toBe(manualScale);
  expect(app.pageErrors).toEqual([]);
});

test('PDF tab switches retain the reading position and discard retired runtime callbacks', async ({ page }) => {
  const app = await setup(page);
  await openFile(app, 'report.pdf');
  await expectPdf(page);
  await page.getByRole('button', { name: 'Next page', exact: true }).click();
  await expect(page.getByRole('spinbutton', { name: 'PDF page number', exact: true })).toHaveValue('2');
  await page.locator('#openseek-office-surface').evaluate(host => { window.retiredPdf = host.__officeViewerPdf; });
  await openFile(app, 'report.docx');
  await expect(page.locator('.word-page')).toContainText('Walking on imported air');
  await expect(page.locator('.pdf-container')).toHaveCount(0);
  expect(await page.evaluate(() => window.retiredPdf.alive)).toBe(false);
  await openFile(app, 'report.pdf');
  await expectPdf(page);
  await expect(page.getByRole('spinbutton', { name: 'PDF page number', exact: true })).toHaveValue('2');
  await page.evaluate(() => {
    window.retiredPdf.options.onState(JSON.stringify({ status: 'error', message: 'Stale PDF failure' }));
    window.retiredPdf.options.onSelection('invalid retired selection');
  });
  await expectPdf(page);
  await expect(page.locator('.mention-chip')).toHaveCount(0);
  await expect(page.locator('.pdf-container')).toHaveCount(1);
  expect(app.pageErrors).toEqual([]);
});

test('a malformed PDF reports failure and the next PDF loads normally', async ({ page }) => {
  const app = await setup(page);
  await openFile(app, 'broken.pdf');
  await expect(page.locator('.viewer-notice')).toBeVisible();
  await expect(page.locator('.viewer-notice')).toContainText('Could not preview this PDF. Try reopening the file.');
  await expect(page.locator('.viewer-notice')).not.toContainText(/Invalid PDF|base64|Error:|stack/i);
  await openFile(app, 'report.pdf');
  await expectPdf(page);
  await expect(page.locator('.textLayer').first()).toContainText('OpenSeek PDF preview');
  expect(app.pageErrors).toEqual([]);
});

test('PDF controls and failures follow live language changes without parser details', async ({ page }) => {
  const app = await setup(page);
  await openFile(app, 'report.pdf');
  await expectPdf(page);
  await page.evaluate(() => {
    Object.defineProperty(navigator, 'languages', { configurable: true, value: ['zh-CN'] });
    window.dispatchEvent(new Event('languagechange'));
  });
  await expect(page.locator('html')).toHaveAttribute('lang', 'zh-Hans');
  await expect(page.getByRole('searchbox', { name: '在文档中查找', exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: '适应页宽', exact: true })).toBeVisible();
  await expect(page.getByRole('spinbutton', { name: 'PDF 页码', exact: true })).toBeEnabled();
  await openFile(app, 'broken.pdf');
  await expect(page.locator('.viewer-notice')).toContainText('无法预览此 PDF。请重新打开文件。');
  await expect(page.locator('.viewer-notice')).not.toContainText(/Invalid PDF|base64|Error:|stack/i);
  await openFile(app, 'encrypted.pdf');
  const dialog = page.getByRole('dialog', { name: '解锁 PDF', exact: true });
  await expect(dialog).toBeVisible();
  await dialog.getByLabel('PDF 密码', { exact: true }).fill('wrong-password');
  await dialog.getByRole('button', { name: '解锁', exact: true }).click();
  await expect(dialog.getByRole('alert')).toHaveText('密码错误。');
  await dialog.getByRole('button', { name: '取消', exact: true }).click();
  await expect(dialog).toBeHidden();
  await expect(page.locator('.viewer-notice')).toContainText('已取消 PDF 预览。重新打开文件即可重试。');
  expect(app.pageErrors).toEqual([]);
});

test('encrypted PDFs retry incorrect passwords and release a cancelled session', async ({ page }) => {
  const app = await setup(page);
  await openFile(app, 'encrypted.pdf');
  const dialog = page.getByRole('dialog', { name: 'Unlock PDF', exact: true });
  const input = page.getByLabel('PDF password', { exact: true });
  await expect(dialog).toBeVisible();
  await expect(dialog.getByRole('alert')).toBeHidden();
  await input.fill('incorrect');
  await dialog.getByRole('button', { name: 'Unlock', exact: true }).click();
  await expect(dialog.getByRole('alert')).toHaveText('Incorrect password.');
  await expect(dialog.getByRole('alert')).toBeVisible();
  await expect(input).toHaveValue('');
  await input.fill('open-seek');
  await dialog.getByRole('button', { name: 'Unlock', exact: true }).click();
  await expectPdf(page);
  await expect(dialog).toBeHidden();
  await expect(input).toHaveValue('');
  await openFile(app, 'report.docx');
  await openFile(app, 'encrypted.pdf');
  await expect(dialog).toBeVisible();
  await page.locator('#openseek-office-surface').evaluate(host => { window.cancelledPdf = host.__officeViewerPdf; });
  await dialog.getByRole('button', { name: 'Cancel', exact: true }).click();
  await expect(dialog).toBeHidden();
  await expect(page.locator('.viewer-notice')).toHaveText('PDF preview cancelled. Reopen the file to try again.');
  expect(await page.evaluate(() => window.cancelledPdf.alive)).toBe(false);
  await openFile(app, 'report.pdf');
  await expectPdf(page);
  expect(app.pageErrors).toEqual([]);
});

test('PDF uses the shared annotation composer with pinned drafts, Batch, and apply', async ({ page }, testInfo) => {
  const app = await setup(page);
  await openFile(app, 'report.pdf');
  await expectPdf(page);
  const text = page.locator('.page[data-page-number="1"] [data-pdf-item]').filter({ hasText: 'OpenSeek PDF preview' }).first();
  const select = async (end) => text.evaluate((element, end) => {
    const range = document.createRange();
    range.setStart(element.firstChild, 0);
    range.setEnd(element.firstChild, end);
    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
    document.dispatchEvent(new Event('selectionchange'));
  }, end);
  const preview = page.locator('.office-selection-preview');
  const input = preview.locator('textarea[data-agent-feedback-input]');
  await select(8);
  await expect(input).toBeVisible();
  await expect(input).not.toBeFocused();
  await input.fill('Explain this');
  await input.press('Shift+Enter');
  await input.press('End');
  await input.press('x');
  await expect(input).toHaveValue('Explain this\nx');
  await select(12);
  await expect.poll(() => preview.getAttribute('title')).toContain('OpenSeek');
  await expect(input).toHaveValue('Explain this\nx');
  await preview.getByRole('checkbox').check();
  await input.press('Enter');
  await expect(preview).toBeHidden();
  await expect(page.locator('.mention-chip')).toContainText('Explain this');
  expect(app.requests.filter(request => request.method === 'agent.start')).toHaveLength(0);
  await select(12);
  await expect(input).toBeVisible();
  await expect(preview.getByRole('checkbox')).toBeChecked();
  await input.fill('Second annotation');
  await input.press('Escape');
  await expect(preview).toBeHidden();
  await expect(page.locator('.mention-chip')).toHaveCount(1);
  await select(12);
  await input.fill('Apply both');
  await page.screenshot({ path: testInfo.outputPath('pdf-annotation.png'), animations: 'disabled' });
  await page.evaluate(() => {
    Object.defineProperty(navigator, 'languages', { configurable: true, value: ['zh-CN'] });
    window.dispatchEvent(new Event('languagechange'));
  });
  await expect(input).toHaveAttribute('placeholder', '添加反馈');
  await expect(input).toHaveValue('Apply both');
  await input.press('Alt+Enter');
  await expect.poll(() => app.requests.find(request => request.method === 'agent.start')?.params.task).toContain('<office_selection>');
  const task = app.requests.find(request => request.method === 'agent.start').params.task;
  const selections = [...task.matchAll(/<office_selection>([\s\S]*?)<\/office_selection>/g)].map(match => JSON.parse(match[1]));
  expect(selections).toHaveLength(2);
  expect(selections[0].comment).toBe('Explain this\nx');
  expect(selections[0].selection.text).toBe('OpenSeek');
  expect(selections[0].source.reference.start.page).toBe(1);
  expect(selections[1].comment).toBe('Apply both');
  expect(app.pageErrors).toEqual([]);
});

test('PDF annotation retains a visible source selection while typing', async ({ page }, testInfo) => {
  const app = await setup(page);
  await openFile(app, 'report.pdf');
  await expectPdf(page);
  const source = page.locator('.page[data-page-number="1"] [data-pdf-item]').filter({ hasText: 'Selectable first page text' }).first();
  await source.evaluate(element => {
    const range = document.createRange(); range.selectNodeContents(element);
    const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
    document.dispatchEvent(new Event('selectionchange'));
  });
  const input = page.locator('#office-feedback-input textarea');
  await expect(input).toBeVisible();
  await input.fill('Explain this passage');
  const highlight = page.locator('#office-feedback-input .feedback-source-selection');
  const expectHighlight = async () => {
    await expect(highlight).toHaveCount(1);
    await expect(highlight).toBeVisible();
    const actual = await highlight.boundingBox();
    const expected = await source.evaluate(element => {
      const range = document.createRange(); range.selectNodeContents(element);
      const rect = range.getBoundingClientRect();
      return { x: rect.x, y: rect.y, width: rect.width, height: rect.height };
    });
    expect(Math.abs(actual.x - expected.x)).toBeLessThan(2);
    expect(Math.abs(actual.y - expected.y)).toBeLessThan(2);
    expect(Math.abs(actual.width - expected.width)).toBeLessThan(2);
    const paint = await highlight.evaluate(element => {
      const style = getComputedStyle(element);
      return { background: style.backgroundColor, opacity: style.opacity, pointerEvents: style.pointerEvents };
    });
    expect(paint.background).not.toBe('rgba(0, 0, 0, 0)');
    expect(Number(paint.opacity)).toBeGreaterThan(0);
    expect(paint.pointerEvents).toBe('none');
  };
  // Focusing the textarea replaces the native selection. The draft owns its
  // own painted source fragments instead of trying to steal focus back.
  expect(await page.evaluate(() => window.getSelection().toString())).not.toContain('Selectable first page text');
  await expectHighlight();
  await page.screenshot({ path: testInfo.outputPath('pdf-retained-selection.png') });
  const scale = await page.locator('#openseek-office-surface').evaluate(host => host.__officeViewerPdf.viewer.currentScale);
  await page.getByRole('button', { name: 'Zoom in', exact: true }).click();
  await expect.poll(() => page.locator('#openseek-office-surface').evaluate(host => host.__officeViewerPdf.viewer.currentScale)).toBeGreaterThan(scale + 0.05);
  await expect(async () => expectHighlight()).toPass();
  await page.locator('.pdf-container').evaluate(element => { element.scrollTop += 30; });
  await expect(async () => expectHighlight()).toPass();
  await input.press('Escape');
  await expect(highlight).toHaveCount(0);
  // A subsequent selection replaces the previous highlight; submitting it
  // clears the decoration as well as the draft.
  await source.evaluate(element => {
    const range = document.createRange(); range.setStart(element.firstChild, 0); range.setEnd(element.firstChild, 10);
    const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
    document.dispatchEvent(new Event('selectionchange'));
  });
  await input.fill('Partial selection');
  await expect(highlight).toHaveCount(1);
  expect((await highlight.boundingBox()).width).toBeLessThan((await source.boundingBox()).width);
  await page.locator('#office-feedback-input').getByRole('checkbox').check();
  await input.press('Enter');
  await expect(highlight).toHaveCount(0);
  const secondPage = page.locator('.page[data-page-number="2"] [data-pdf-item]').filter({ hasText: 'Second page selection' }).first();
  await secondPage.scrollIntoViewIfNeeded();
  await page.evaluate(() => {
    const items = [...document.querySelectorAll('[data-pdf-item]')];
    const start = items.find(element => element.textContent.includes('Selectable first page text'));
    const end = items.find(element => element.textContent.includes('Second page selection'));
    const range = document.createRange(); range.setStart(start.firstChild, 0); range.setEnd(end.firstChild, 6);
    const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
    document.dispatchEvent(new Event('selectionchange'));
  });
  await expect(input).toBeVisible();
  await input.fill('Across pages');
  const boxes = await highlight.evaluateAll(elements => elements.map(element => ({
    width: element.getBoundingClientRect().width,
    height: element.getBoundingClientRect().height,
  })));
  expect(boxes.length).toBeGreaterThan(0);
  // Cross-page DOM Ranges include canvas/page rectangles. Only text should
  // be painted, never the large whitespace between the selected fragments.
  for (const box of boxes) {
    expect(box.height).toBeLessThan(40);
    expect(box.width).toBeLessThan(400);
  }
  await input.press('Escape');
  await expect(highlight).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('PDF annotation closes on an outside click before the input is focused', async ({ page }) => {
  const app = await setup(page);
  await openFile(app, 'report.pdf');
  await expectPdf(page);
  const source = page.locator('.page[data-page-number="1"] [data-pdf-item]').filter({ hasText: 'Selectable first page text' }).first();
  const select = async () => {
    await source.evaluate(element => {
      const range = document.createRange(); range.selectNodeContents(element);
      const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
      document.dispatchEvent(new Event('selectionchange'));
    });
    await expect(page.locator('#office-feedback-input textarea')).toBeVisible();
  };
  await select();
  await expect(page.locator('#office-feedback-input textarea')).not.toBeFocused();
  const paper = page.locator('.page[data-page-number="1"]');
  await paper.click({ position: { x: 25, y: 200 } });
  await expect(page.locator('#office-feedback-input textarea')).toBeHidden();
  await expect(page.locator('.feedback-source-selection')).toHaveCount(0);
  await select();
  const input = page.locator('#office-feedback-input textarea');
  const batch = page.locator('#office-feedback-input').getByRole('checkbox');
  await batch.check();
  await expect(input).toBeVisible();
  await input.click();
  await expect(input).toBeVisible();
  await page.locator('#task').click();
  await expect(page.locator('#office-feedback-input textarea')).toBeHidden();
  await expect(page.locator('.feedback-source-selection')).toHaveCount(0);
  await select();
  await input.fill('Keep this draft');
  await paper.click({ position: { x: 25, y: 200 } });
  await expect(input).toBeVisible();
  await expect(input).toHaveValue('Keep this draft');
  await input.press('Escape');
  await expect(input).toBeHidden();
  expect(app.pageErrors).toEqual([]);
});

async function enableImages(page) {
  await page.getByRole('button', { name: 'Model', exact: true }).click();
  await page.getByRole('option', { name: /^DS Flash(?: ✓)?$/ }).click();
}

async function captureRegion(page, rect, { reverse = false, screenshotPath, confirm = true } = {}) {
  await page.getByRole('button', { name: 'Capture region', exact: true }).click();
  await expect(page.locator('.pdf-region-capture')).toBeVisible();
  const a = { x: rect.x, y: rect.y }, b = { x: rect.x + rect.width, y: rect.y + rect.height };
  await page.mouse.move(...Object.values(reverse ? b : a));
  await page.mouse.down();
  await page.mouse.move(...Object.values(reverse ? a : b), { steps: 8 });
  if (screenshotPath) await page.screenshot({ path: screenshotPath });
  await page.mouse.up();
  await expect(page.locator('.pdf-region-capture')).toHaveCount(0);
  if (confirm && rect.width >= 4 && rect.height >= 4) {
    const feedback = page.locator('.pdf-capture-feedback');
    await expect(feedback.locator('textarea')).toBeVisible();
    await feedback.getByRole('checkbox').check();
    await feedback.locator('.agent-feedback-input-action').click();
    await expect(feedback).toBeHidden();
  }
}

test.describe('PDF region screenshots', () => {
  test.use({ deviceScaleFactor: 2 });

  test('crops real page pixels at display resolution and sends an image without losing typed text', async ({ page }, testInfo) => {
    const app = await setup(page);
    await enableImages(page);
    await openFile(app, 'report.pdf');
    await expectPdf(page);
    await page.locator('#task').fill('Explain this figure');
    const source = page.locator('.pdfViewer canvas').first();
    const bounds = await source.boundingBox();
    const rect = { x: Math.ceil(bounds.x + 30), y: Math.ceil(bounds.y + 25), width: 250, height: 120 };
    // An independently cropped page bitmap is the expected attachment, including DPI.
    const expected = await source.evaluate((canvas, rect) => {
      const b = canvas.getBoundingClientRect(), scale = canvas.width / b.width;
      const image = document.createElement('canvas');
      image.width = Math.ceil(rect.width * scale); image.height = Math.ceil(rect.height * scale);
      image.getContext('2d').drawImage(canvas, (rect.x-b.left)*scale, (rect.y-b.top)*scale,
        rect.width*scale, rect.height*scale, 0, 0, rect.width*scale, rect.height*scale);
      return { url: image.toDataURL(), width: image.width, height: image.height };
    }, rect);
    await captureRegion(page, rect, { screenshotPath: testInfo.outputPath('pdf-region-selection.png') });
    const attachment = page.locator('.composer-image img');
    await expect(attachment).toHaveAttribute('src', expected.url);
    expect(await attachment.evaluate(img => [img.naturalWidth, img.naturalHeight])).toEqual([expected.width, expected.height]);
    expect(expected.width).toBeGreaterThan(rect.width);
    await expect(page.locator('#task')).toHaveValue('Explain this figure');
    expect((await page.locator('.mention-chip').boundingBox()).height).toBeLessThan(40);
    expect(app.requests.filter(r => r.method === 'agent.start')).toHaveLength(0);
    await page.screenshot({ path: testInfo.outputPath('pdf-region-attachment.png') });
    await page.locator('#send').click();
    await expect.poll(() => app.requests.filter(r => r.method === 'agent.start').length).toBe(1);
    const request = app.requests.find(r => r.method === 'agent.start');
    expect(JSON.stringify(request.params)).toContain(expected.url);
    expect(JSON.stringify(request.params)).toContain('Explain this figure');
    await expect(page.locator('.composer-image')).toHaveCount(0);
    expect(app.pageErrors).toEqual([]);
  });

  test('reverse drag works after zoom, rotation and scrolling', async ({ page }) => {
    const app = await setup(page);
    await enableImages(page);
    await openFile(app, 'report.pdf');
    await expectPdf(page);
    await page.getByRole('button', { name: 'Zoom in', exact: true }).click();
    await page.getByRole('button', { name: 'Rotate clockwise', exact: true }).click();
    await page.getByRole('button', { name: 'Next page', exact: true }).click();
    await expect.poll(() => page.locator('#openseek-office-surface').evaluate(host =>
      host.__officeViewerPdf.viewer.getPageView(1).renderingState)).toBe(3);
    const source = page.locator('.page[data-page-number="2"] canvas');
    await source.scrollIntoViewIfNeeded();
    const bounds = await source.boundingBox();
    const viewport = await page.locator('.pdf-container').boundingBox();
    const rect = { x: Math.ceil(Math.max(bounds.x, viewport.x) + 30), y: Math.ceil(Math.max(bounds.y, viewport.y) + 40), width: 150, height: 100 };
    await captureRegion(page, rect, { reverse: true });
    await expect(page.locator('.composer-image img')).toHaveAttribute('src', /^data:image\/png;base64,/);
    await page.getByRole('button', { name: 'Remove report.pdf-capture.png', exact: true }).click();
    await expect(page.locator('.composer-image')).toHaveCount(0);
    expect(app.pageErrors).toEqual([]);
  });

  test('Escape and document switches retire capture while blank clicks keep it active', async ({ page }) => {
    const app = await setup(page);
    await enableImages(page);
    await openFile(app, 'report.pdf');
    await expectPdf(page);
    const button = page.getByRole('button', { name: 'Capture region', exact: true });
    await button.click();
    await expect(page.locator('.pdf-region-capture')).toBeVisible();
    await page.keyboard.press('Escape');
    await expect(page.locator('.pdf-region-capture')).toHaveCount(0);
    const bounds = await page.locator('.pdfViewer canvas').first().boundingBox();
    await button.click();
    await page.mouse.click(bounds.x + 50, bounds.y + 50);
    await expect(page.locator('.pdf-capture-feedback')).toBeHidden();
    await page.locator('.pdf-container').evaluate(el => { el.scrollTop += 100; });
    await expect(page.locator('.pdf-region-capture')).toBeVisible();
    await openFile(app, 'report.docx');
    await expect(page.locator('.word-page')).toBeVisible();
    await expect(page.locator('.pdf-region-capture')).toHaveCount(0);
    await expect(page.locator('.composer-image')).toHaveCount(0);
    expect(app.pageErrors).toEqual([]);
  });

  test('a visible region spanning two pages becomes one image', async ({ page }) => {
    const app = await setup(page);
    await enableImages(page);
    await openFile(app, 'report.pdf');
    await expectPdf(page);
    // Keep the page boundary visible regardless of tree visibility or PDF scale.
    await page.locator('.pdf-container').evaluate(el => {
      const next = el.querySelector('.page[data-page-number="2"]').getBoundingClientRect();
      el.scrollTop += next.top - el.getBoundingClientRect().top - el.clientHeight / 2;
    });
    await expect.poll(() => page.locator('#openseek-office-surface').evaluate(host =>
      host.__officeViewerPdf.viewer.getPageView(1).renderingState)).toBe(3);
    const a = await page.locator('.pdfViewer canvas').first().boundingBox();
    const b = await page.locator('.pdfViewer canvas').nth(1).boundingBox();
    const rect = { x: Math.ceil(b.x + 20), y: Math.floor(a.y + a.height - 40), width: 260,
      height: Math.ceil(b.y + 100) - Math.floor(a.y + a.height - 40) };
    await captureRegion(page, rect);
    const pixels = await page.locator('.composer-image img').evaluate(img => {
      const canvas = document.createElement('canvas');
      canvas.width = img.naturalWidth; canvas.height = img.naturalHeight;
      const ctx = canvas.getContext('2d'); ctx.drawImage(img, 0, 0);
      const data = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
      let dark = 0;
      for (let i = 0; i < data.length; i += 4) if (data[i] < 100 && data[i+1] < 100 && data[i+2] < 100) dark++;
      return { width: canvas.width, height: canvas.height, dark };
    });
    expect(pixels.width).toBeGreaterThanOrEqual(rect.width * 2);
    expect(pixels.height).toBeGreaterThanOrEqual(rect.height * 2);
    expect(pixels.dark).toBeGreaterThan(100);
    expect(app.pageErrors).toEqual([]);
  });

  test('a PDF screenshot reaches a Codex turn as an image attachment', async ({ page }) => {
    const app = await setup(page, { codex: true });
    await openFile(app, 'report.pdf');
    await expectPdf(page);
    const b = await page.locator('.pdfViewer canvas').first().boundingBox();
    await captureRegion(page, { x: Math.ceil(b.x + 20), y: Math.ceil(b.y + 20), width: 180, height: 100 });
    const url = await page.locator('.composer-image img').getAttribute('src');
    await page.locator('#send').click();
    await expect.poll(() => app.requests.filter(r => r.method === 'codex.turn.start').length).toBe(1);
    expect(app.requests.find(r => r.method === 'codex.turn.start').params.input).toContainEqual({ type: 'image', url });
    expect(app.pageErrors).toEqual([]);
  });

});

for (const { rotation, partial = false, noRotate = false, hidden = false, note = false } of [
  { rotation: 0 },
  { rotation: 270, partial: true },
  { rotation: 90, noRotate: true },
  { rotation: 0, hidden: true },
  { rotation: 0, note: true },
  { rotation: 0, note: 'attachment' },
]) {
test(`PDF screenshots include form appearances (${rotation}, partial ${partial}, noRotate ${noRotate}, hidden ${hidden}, note ${note})`, async ({ page }) => {
  const app = await setup(page);
  app.officeFiles['docs/report.pdf'] = formPdf({ noRotate, note });
  await enableImages(page);
  await openFile(app, 'report.pdf');
  await expectPdf(page);
  const annotation = page.locator(note === 'attachment' ? '.annotationLayer .fileAttachmentAnnotation'
    : note ? '.annotationLayer .textAnnotation' : '.annotationLayer .textWidgetAnnotation');
  await expect(annotation).toBeVisible();
  for (let angle = 0; angle < rotation; angle += 90) {
    await page.getByRole('button', { name: 'Rotate clockwise', exact: true }).click();
  }
  if (note) await annotation.locator('img').evaluate(img => img.decode());
  else await expect(annotation.locator('canvas')).toBeVisible();
  if (note === 'attachment') await expect(annotation.locator('img')).toHaveCSS('filter', 'opacity(0.5)');
  await annotation.scrollIntoViewIfNeeded();
  const bounds = await annotation.boundingBox();
  const rect = { x: Math.ceil(bounds.x + 2), y: Math.ceil(bounds.y + 2),
    width: Math.floor(bounds.width * (partial ? 0.6 : 1) - 4), height: Math.floor(bounds.height - 4) };
  if (hidden) await annotation.evaluate(el => { el.style.visibility = 'hidden'; });
  const expected = await page.screenshot({ clip: rect, scale: 'css' });
  await captureRegion(page, rect);
  const pixels = await page.locator('.composer-image img').evaluate(async (img, expected) => {
    const reference = new Image(); reference.src = `data:image/png;base64,${expected}`;
    await reference.decode();
    const canvas = document.createElement('canvas');
    canvas.width = reference.naturalWidth; canvas.height = reference.naturalHeight;
    const ctx = canvas.getContext('2d'); ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
    const data = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
    ctx.clearRect(0, 0, canvas.width, canvas.height); ctx.drawImage(reference, 0, 0);
    const expectedData = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
    let difference = 0, dark = 0;
    for (let i = 0; i < data.length; i += 4) {
      if (data[i] < 100 && data[i + 1] < 100 && data[i + 2] < 100) dark++;
      for (let channel = 0; channel < 3; channel++) difference += Math.abs(data[i + channel] - expectedData[i + channel]);
    }
    return { difference: difference / (canvas.width * canvas.height * 3), dark };
  }, expected.toString('base64'));
  if (hidden || note === 'attachment') expect(pixels.dark).toBe(0);
  else expect(pixels.dark).toBeGreaterThan(20);
  // SVG icons rasterize at different resolutions in CSS and the page bitmap.
  expect(pixels.difference).toBeLessThan(note ? 8 : 5);
  expect(app.pageErrors).toEqual([]);
});
}

test('PDF capture rejects HTML-only form text without producing an incomplete image', async ({ page }) => {
  const app = await setup(page);
  app.officeFiles['docs/report.pdf'] = formPdf({ readOnly: false, appearance: false });
  await enableImages(page);
  await openFile(app, 'report.pdf');
  await expectPdf(page);
  const field = page.locator('.annotationLayer .textWidgetAnnotation');
  await expect(field).toHaveText('Stored field value');
  const bounds = await field.boundingBox();
  await captureRegion(page, bounds, { confirm: false });
  await expect(page.getByText('This form or annotation cannot be captured. Select another region.', { exact: true })).toBeVisible();
  await expect(page.locator('.composer-image')).toHaveCount(0);
  await expect(page.locator('.pdf-capture-feedback')).toBeHidden();
  const pageBounds = await page.locator('.pdfViewer canvas').first().boundingBox();
  await captureRegion(page, { x: pageBounds.x + 20, y: pageBounds.y + 20, width: 60, height: 40 });
  await expect(page.locator('.composer-image')).toHaveCount(1);
  expect(app.pageErrors).toEqual([]);
});

test.describe('PDF touch capture', () => {
  test.use({ hasTouch: true });

  test('PDF touch drags capture a region and restore panning afterward', async ({ page }) => {
    const app = await setup(page);
    await enableImages(page);
    await openFile(app, 'report.pdf');
    await expectPdf(page);
    const container = page.locator('.pdf-container');
    const before = await container.evaluate(el => el.scrollTop);
    const bounds = await page.locator('.pdfViewer canvas').first().boundingBox();
    const cdp = await page.context().newCDPSession(page);
    const drag = async () => {
      const x = Math.ceil(bounds.x + 100), y = Math.ceil(bounds.y + 250);
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y }] });
      for (let step = 1; step <= 8; step++) {
        await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: x + step * 10, y: y - step * 15 }] });
      }
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    };
    const button = page.getByRole('button', { name: 'Capture region', exact: true });
    await button.click();
    await expect(page.locator('.pdf-region-capture')).toBeVisible();
    await drag();
    const input = page.locator('.pdf-capture-feedback textarea');
    await expect(input).toBeVisible();
    expect(await container.evaluate(el => el.scrollTop)).toBe(before);
    await expect(container).toHaveCSS('touch-action', 'auto');
    await input.press('Escape');
    await button.click();
    await expect(container).toHaveCSS('touch-action', 'none');
    await page.keyboard.press('Escape');
    await expect(container).toHaveCSS('touch-action', 'auto');
    await drag();
    await expect.poll(() => container.evaluate(el => el.scrollTop)).toBeGreaterThan(before + 50);
    await cdp.detach();
    expect(app.pageErrors).toEqual([]);
  });
});

test('PDF capture mode keeps native scrolling and opens the shared feedback composer', async ({ page }) => {
  const app = await setup(page);
  await enableImages(page);
  await openFile(app, 'report.pdf');
  await expectPdf(page);
  const button = page.getByRole('button', { name: 'Capture region', exact: true });
  await button.click();
  const container = page.locator('.pdf-container');
  const before = await container.evaluate(el => el.scrollTop);
  const bounds = await container.boundingBox();
  await page.mouse.move(bounds.x + 150, bounds.y + 150);
  await page.mouse.wheel(0, 140);
  await expect.poll(() => container.evaluate(el => el.scrollTop)).toBeGreaterThan(before + 50);
  await expect(page.locator('.pdf-region-capture')).toBeVisible();
  const x = bounds.x + 70, y = bounds.y + 80;
  await page.mouse.move(x, y); await page.mouse.down();
  await page.mouse.move(x + 200, y + 100, { steps: 5 }); await page.mouse.up();
  await expect(page.locator('.pdf-capture-feedback textarea')).toBeVisible();
  await expect(page.locator('.composer-image')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

for (const codex of [false, true]) {
  test(`PDF capture feedback sends the image and instruction with existing ${codex ? 'Codex' : 'OpenSeek'} typing`, async ({ page }, testInfo) => {
    const app = await setup(page, { codex });
    if (!codex) await enableImages(page);
    await openFile(app, 'report.pdf');
    await expectPdf(page);
    await page.locator('#task').fill('Keep my existing draft');
    const b = await page.locator('.pdfViewer canvas').first().boundingBox();
    await captureRegion(page, { x: Math.ceil(b.x + 35), y: Math.ceil(b.y + 30), width: 240, height: 120 }, { confirm: false });
    const feedback = page.locator('.pdf-capture-feedback');
    const input = feedback.locator('textarea');
    await expect(input).toBeVisible();
    await input.fill('把这部分改成中文，并加上标题');
    // Scrolling hides an offscreen anchor without discarding the comment.
    const scroll = page.locator('.pdf-container');
    const before = await scroll.evaluate(el => el.scrollTop);
    await scroll.evaluate(el => { el.scrollTop += 400; });
    await expect(input).toBeHidden();
    await scroll.evaluate((el, top) => { el.scrollTop = top; }, before);
    await expect(input).toHaveValue('把这部分改成中文，并加上标题');
    await expect(input).toBeVisible();
    await page.screenshot({ path: testInfo.outputPath('pdf-capture-feedback.png'), animations: 'disabled' });
    await input.press('Alt+Enter');
    const method = codex ? 'codex.turn.start' : 'agent.start';
    await expect.poll(() => app.requests.filter(r => r.method === method).length).toBe(1);
    const request = JSON.stringify(app.requests.find(r => r.method === method).params);
    expect(request).toContain('data:image/png;base64,');
    expect(request).toContain('Keep my existing draft');
    expect(request).toContain('把这部分改成中文，并加上标题');
    const params = app.requests.find(r => r.method === method).params;
    const prompt = codex ? params.input.filter(item => item.type === 'text').map(item => item.text).join('\n') : params.task;
    const selections = [...prompt.matchAll(/<office_selection>([\s\S]*?)<\/office_selection>/g)].map(match => JSON.parse(match[1]));
    expect(selections).toHaveLength(1);
    const selection = selections[0];
    expect(selection.schema).toBe('office.selection.materialized.v1');
    expect(selection.comment).toBe('把这部分改成中文，并加上标题');
    expect(selection.selection).toEqual({ format: 'pdf', kind: 'pdf-region', pages: [1] });
    expect(selection.source.file).toBe('/workspace/docs/report.pdf');
    expect(selection.source.capture.document.sha256).toMatch(/^[0-9a-f]{64}$/);
    expect(selection.source.capture.regions).toHaveLength(1);
    const { page: number, geometry } = selection.source.capture.regions[0];
    expect(number).toBe(1);
    expect(geometry.space).toBe('pdf-page-user-space');
    expect(geometry.bbox).toHaveLength(4);
    expect(geometry.bbox.every(Number.isFinite)).toBe(true);
    expect(geometry.bbox[2]).toBeGreaterThan(geometry.bbox[0]);
    expect(geometry.bbox[3]).toBeGreaterThan(geometry.bbox[1]);
    await expect(feedback).toBeHidden();
    expect(app.pageErrors).toEqual([]);
  });
}

test('PDF capture feedback can be batched with text or cancelled without adding an attachment', async ({ page }) => {
  const app = await setup(page);
  await enableImages(page);
  await openFile(app, 'report.pdf');
  await expectPdf(page);
  await page.getByRole('button', { name: 'Zoom in', exact: true }).click();
  await expect.poll(() => page.locator('#openseek-office-surface').evaluate(host =>
    host.__officeViewerPdf.viewer.currentScaleValue)).not.toBe('page-width');
  await page.locator('#task').fill('Existing draft');
  const captureRect = async () => {
    // Zoom/rotation updates precede painting and replace the old canvas. Read
    // geometry only after the first page has finished that replacement.
    await expect.poll(() => page.locator('#openseek-office-surface').evaluate(host =>
      host.__officeViewerPdf.viewer.getPageView(0).renderingState)).toBe(3);
    await expect(page.locator('.pdfViewer canvas').first()).toBeVisible();
    const b = await page.locator('.pdfViewer canvas').first().boundingBox();
    return { x: Math.ceil(b.x + 30), y: Math.ceil(b.y + 35), width: 200, height: 90 };
  };
  const feedback = page.locator('.pdf-capture-feedback');
  await captureRegion(page, await captureRect(), { confirm: false });
  await feedback.locator('textarea').fill('Make the heading larger');
  await page.getByRole('button', { name: 'Rotate clockwise', exact: true }).click();
  await expect(feedback.locator('textarea')).toHaveValue('Make the heading larger');
  // Rotation can move this region beyond the right edge at manual zoom.
  // Offscreen selection fragments are clipped, so reveal it before checking.
  await expect.poll(() => page.locator('#openseek-office-surface').evaluate(host =>
    host.__officeViewerPdf.viewer.pagesRotation)).toBe(90);
  await page.locator('.pdf-container').evaluate(el => { el.scrollLeft = el.scrollWidth; });
  await expect(feedback.locator('textarea')).toBeVisible();
  await expect(feedback.locator('.feedback-source-selection')).toHaveCount(1);
  await feedback.getByRole('checkbox').check();
  await feedback.locator('textarea').press('Enter');
  await expect(page.locator('#task')).toHaveValue('Existing draft');
  await expect(page.locator('.mention-chip')).toContainText('Make the heading larger');
  await expect(page.locator('.composer-image')).toHaveCount(1);
  expect(app.requests.filter(r => r.method === 'agent.start')).toHaveLength(0);
  for (const rotation of [180, 270, 0]) {
    await page.getByRole('button', { name: 'Rotate clockwise', exact: true }).click();
    await expect.poll(() => page.locator('#openseek-office-surface').evaluate(host =>
      host.__officeViewerPdf.viewer.pagesRotation)).toBe(rotation);
  }
  await page.locator('.pdf-container').evaluate(el => { el.scrollLeft = 0; el.scrollTop = 0; });
  await captureRegion(page, await captureRect(), { confirm: false });
  await feedback.locator('textarea').fill('Discard this comment');
  await feedback.locator('textarea').press('Escape');
  await expect(feedback).toBeHidden();
  await expect(page.locator('.composer-image')).toHaveCount(1);
  await expect(page.locator('#task')).not.toHaveValue(/Discard/);
  await captureRegion(page, await captureRect(), { confirm: false });
  await feedback.locator('textarea').fill('Wrong file must not receive this');
  await openFile(app, 'report.docx');
  await expect(feedback).toBeHidden();
  await expect(page.locator('.composer-image')).toHaveCount(1);
  expect(app.pageErrors).toEqual([]);
});

{
  const [comment, action] = ['Keep this screenshot', 'cancel'];

  test(`PDF screenshot drafts survive outside pointer and focus changes until ${action}`, async ({ page }) => {
    const app = await setup(page);
    await enableImages(page);
    await openFile(app, 'report.pdf');
    await expectPdf(page);
    const b = await page.locator('.pdfViewer canvas').first().boundingBox();
    const rect = { x: Math.ceil(b.x + 30), y: Math.ceil(b.y + 30), width: 160, height: 90 };
    await captureRegion(page, rect, { confirm: false });
    const feedback = page.locator('.pdf-capture-feedback');
    const input = feedback.locator('textarea');
    const camera = page.getByRole('button', { name: 'Capture region', exact: true });
    if (comment) await input.fill(comment);
    // The unfocused, attachment-backed draft must survive a real outside click.
    await page.locator('#task').click();
    await page.locator('#task').fill('Existing composer text');
    await expect(input).toBeVisible();
    await expect(input).toHaveValue(comment);
    // Focus leaving the feedback uses a separate handler from pointerdown.
    await input.focus();
    await page.locator('#task').focus();
    await expect(input).toBeVisible();
    await expect(input).toHaveValue(comment);
    await expect(camera).toBeDisabled();
    await expect(feedback.locator('.feedback-source-selection')).toHaveCount(1);
    await expect(page.locator('.composer-image')).toHaveCount(0);
    if (action === 'batch') {
      await feedback.getByRole('checkbox').check();
      await feedback.locator('.agent-feedback-input-action').click();
      await expect(page.locator('.composer-image img')).toHaveAttribute('src', /^data:image\/png;base64,/);
    } else {
      await input.press('Escape');
      await expect(page.locator('.composer-image')).toHaveCount(0);
    }
    await expect(feedback).toBeHidden();
    await expect(camera).toBeEnabled();
    await expect(page.locator('#task')).toHaveValue('Existing composer text');
    await captureRegion(page, rect, { confirm: false });
    await expect(input).toHaveValue('');
    await input.press('Escape');
    expect(app.pageErrors).toEqual([]);
  });
}

async function hoverPdfText(page, text) {
  const span = page.locator('.textLayer span[data-pdf-item]').filter({ hasText: text }).first();
  await expect(span).toBeVisible();
  await span.hover();
  const b = await span.boundingBox();
  await expect(page.locator('.pdf-region-capture-box')).toBeVisible();
  return b;
}

test('PDF element hover and a slightly moving click attach text, page and screenshot', async ({ page }, testInfo) => {
  const app = await setup(page);
  await enableImages(page);
  await openFile(app, 'report.pdf');
  await expectPdf(page);
  await page.getByRole('button', { name: 'Capture region', exact: true }).click();
  const b = await hoverPdfText(page, 'OpenSeek PDF preview');
  const box = await page.locator('.pdf-region-capture-box').boundingBox();
  expect(Math.abs(box.x - b.x)).toBeLessThanOrEqual(3);
  expect(Math.abs(box.width - b.width)).toBeLessThanOrEqual(5);
  await page.screenshot({ path: testInfo.outputPath('pdf-element-hover.png') });
  await page.mouse.down();
  await page.mouse.move(b.x + b.width / 2 + 2, b.y + b.height / 2 + 1);
  await page.mouse.up();
  const feedback = page.locator('.pdf-capture-feedback');
  await expect(feedback.locator('textarea')).toBeVisible();
  await feedback.locator('textarea').fill('Rename this heading');
  await feedback.getByRole('checkbox').check();
  await feedback.locator('textarea').press('Enter');
  await expect(page.locator('#task')).toHaveValue('');
  await expect(page.locator('.mention-chip')).toContainText('report.pdf · p. 1');
  await expect(page.locator('.mention-chip [title]').first()).toHaveAttribute('title', /OpenSeek PDF preview[\s\S]*Rename this heading/);
  await page.locator('#send').click();
  await expect.poll(() => app.requests.filter(r => r.method === 'agent.start').length).toBe(1);
  const params = app.requests.find(r => r.method === 'agent.start').params;
  const selection = JSON.parse(params.task.match(/<office_selection>([\s\S]*?)<\/office_selection>/)[1]);
  expect(selection.selection.text).toBe('OpenSeek PDF preview');
  expect(selection.comment).toBe('Rename this heading');
  expect(selection.source.file).toBe('/workspace/docs/report.pdf');
  expect(JSON.stringify(params)).toContain('data:image/png;base64,');
  const event = {
    sequence: app.sessionEvents.at(-1).sequence + 1,
    item: { kind: 'user', payload: { content: params.task } },
  };
  app.sessionEvents.push(event);
  app.notify('session.event', {
    session: 'session-1', session_root: '/workspace/.openseek', sequence: event.sequence, event,
  });
  const sent = page.locator('.msg.user').last();
  await expect(sent.locator('.mention-chip')).toContainText('report.pdf · p. 1');
  await expect(sent.locator('.msg-content')).toHaveText('Rename this heading');
  await page.reload();
  await app.openSession();
  await expect(sent.locator('.mention-chip')).toContainText('report.pdf · p. 1');
  await expect(sent.locator('.msg-content')).toHaveText('Rename this heading');
  expect(app.pageErrors).toEqual([]);
});

for (const tagged of [false, true]) {
  test(`PDF element targets group ${tagged ? 'tagged paragraphs' : 'untagged lines'} without merging columns`, async ({ page }) => {
    const app = await setup(page);
    app.officeFiles['docs/report.pdf'] = annotationPdf(tagged);
    await enableImages(page);
    await openFile(app, 'report.pdf');
    await expectPdf(page);
    const button = page.getByRole('button', { name: 'Capture region', exact: true });
    await button.click();
    const first = await hoverPdfText(page, 'Hello');
    const last = await page.locator('.textLayer span[data-pdf-item]').filter({ hasText: 'world' }).first().boundingBox();
    const box = await page.locator('.pdf-region-capture-box').boundingBox();
    expect(box.x).toBeLessThanOrEqual(first.x);
    expect(box.x + box.width).toBeGreaterThanOrEqual(last.x + last.width - 1);
    const other = await page.locator('.textLayer span[data-pdf-item]').filter({ hasText: 'Other column' }).first().boundingBox();
    expect(box.x + box.width).toBeLessThan(other.x);
    await hoverPdfText(page, 'First paragraph line');
    const paragraph = await page.locator('.pdf-region-capture-box').boundingBox();
    const second = await page.locator('.textLayer span[data-pdf-item]').filter({ hasText: 'Second paragraph line' }).first().boundingBox();
    if (tagged) expect(paragraph.y + paragraph.height).toBeGreaterThanOrEqual(second.y + second.height - 1);
    else expect(paragraph.y + paragraph.height).toBeLessThan(second.y);
    await page.mouse.down(); await page.mouse.up();
    const feedback = page.locator('.pdf-capture-feedback');
    await feedback.getByRole('checkbox').check();
    await feedback.locator('.agent-feedback-input-action').click();
    await expect(page.locator('.mention-chip [title]').first()).toHaveAttribute('title', /First paragraph line/);
    if (tagged) await expect(page.locator('.mention-chip [title]').first()).toHaveAttribute('title', /Second paragraph line/);
    else await expect(page.locator('.mention-chip [title]').first()).not.toHaveAttribute('title', /Second paragraph line/);
    expect(app.pageErrors).toEqual([]);
  });
}

test('PDF element mode ignores blank clicks and dragging overrides a hovered target', async ({ page }) => {
  const app = await setup(page);
  await enableImages(page);
  await openFile(app, 'report.pdf');
  await expectPdf(page);
  await page.getByRole('button', { name: 'Capture region', exact: true }).click();
  const b = await hoverPdfText(page, 'OpenSeek PDF preview');
  await page.mouse.click(b.x, b.y + 150);
  await expect(page.locator('.pdf-region-capture')).toBeVisible();
  await expect(page.locator('.pdf-region-capture-box')).toBeHidden();
  await expect(page.locator('.pdf-capture-feedback')).toBeHidden();
  await hoverPdfText(page, 'OpenSeek PDF preview');
  await page.mouse.down();
  await page.mouse.move(b.x + b.width / 2 + 140, b.y + b.height / 2 + 100, { steps: 8 });
  await expect(page.locator('.pdf-region-capture-box')).toHaveAttribute('data-selection-kind', 'region');
  await page.mouse.up();
  const feedback = page.locator('.pdf-capture-feedback');
  await feedback.getByRole('checkbox').check();
  await feedback.locator('.agent-feedback-input-action').click();
  await expect(page.locator('#task')).toHaveValue('');
  await expect(page.locator('.composer-image')).toHaveCount(1);
  expect(app.pageErrors).toEqual([]);
});

test('PDF element hover follows scroll and works on a rotated zoomed second page', async ({ page }) => {
  const app = await setup(page);
  await enableImages(page);
  await openFile(app, 'report.pdf');
  await expectPdf(page);
  const button = page.getByRole('button', { name: 'Capture region', exact: true });
  await button.click();
  await hoverPdfText(page, 'OpenSeek PDF preview');
  await page.mouse.wheel(0, 200);
  await expect(page.locator('.pdf-region-capture-box')).toBeHidden();
  await page.getByRole('button', { name: 'Rotate clockwise', exact: true }).click();
  await expect(page.locator('.pdf-region-capture')).toHaveCount(0);
  await page.getByRole('button', { name: 'Next page', exact: true }).click();
  await page.getByRole('button', { name: 'Fit page width', exact: true }).click();
  await expect.poll(() => page.locator('#openseek-office-surface').evaluate(host =>
    host.__officeViewerPdf.viewer.getPageView(1).renderingState)).toBe(3);
  const text = page.locator('.textLayer span[data-pdf-item]').filter({ hasText: 'Second page selection' }).first();
  await text.scrollIntoViewIfNeeded();
  await button.click();
  await hoverPdfText(page, 'Second page selection');
  await page.mouse.down(); await page.mouse.up();
  const feedback = page.locator('.pdf-capture-feedback');
  await feedback.getByRole('checkbox').check();
  await feedback.locator('.agent-feedback-input-action').click();
  await expect(page.locator('.mention-chip')).toContainText('report.pdf · p. 2');
  await expect(page.locator('.mention-chip')).toContainText('Second page selection');
  await expect(page.locator('.composer-image')).toHaveCount(1);
  await page.locator('#send').click();
  await expect.poll(() => app.requests.filter(r => r.method === 'agent.start').length).toBe(1);
  const params = app.requests.find(r => r.method === 'agent.start').params;
  const selection = JSON.parse(params.task.match(/<office_selection>([\s\S]*?)<\/office_selection>/)[1]);
  const region = selection.source.capture.regions[0];
  expect(region.page).toBe(2);
  // PDF text is placed at (72, 710) at 20pt; rotation must not swap its axes.
  const [x0, y0, x1, y1] = region.geometry.bbox;
  expect(x0).toBeGreaterThan(68); expect(x0).toBeLessThan(74);
  expect(y0).toBeGreaterThan(702); expect(y0).toBeLessThan(712);
  expect(x1).toBeGreaterThan(240); expect(x1).toBeLessThan(320);
  expect(y1).toBeGreaterThan(720); expect(y1).toBeLessThan(738);
  expect(app.pageErrors).toEqual([]);
});

// Selection geometry is unit-tested; keep tagged/viewer and untagged/composed rotation browser seams.
for (const [tagged, intrinsic, rotation] of [[true, 0, 90], [false, 90, 180]]) {
    test(`PDF split heading preserves grouping and spaces (${tagged ? 'tagged' : 'untagged'}, intrinsic ${intrinsic}, viewer ${rotation})`, async ({ page }) => {
      const app = await setup(page);
      app.officeFiles['docs/report.pdf'] = annotationPdf(tagged, intrinsic);
      await enableImages(page);
      await openFile(app, 'report.pdf');
      await expectPdf(page);
      for (let turn = 0; turn < rotation / 90; turn++) {
        await page.getByRole('button', { name: 'Rotate clockwise', exact: true }).click();
      }
      const hello = page.locator('.textLayer span[data-pdf-item]').filter({ hasText: 'Hello' }).first();
      await hello.scrollIntoViewIfNeeded();
      await expect.poll(() => page.locator('#openseek-office-surface').evaluate(host =>
        host.__officeViewerPdf.viewer.getPageView(0).renderingState)).toBe(3);
      await page.getByRole('button', { name: 'Capture region', exact: true }).click();
      await hoverPdfText(page, 'Hello');
      const world = await page.locator('.textLayer span[data-pdf-item]').filter({ hasText: 'world' }).first().boundingBox();
      const box = await page.locator('.pdf-region-capture-box').boundingBox();
      expect(box.x).toBeLessThanOrEqual(world.x);
      expect(box.y).toBeLessThanOrEqual(world.y);
      expect(box.x + box.width).toBeGreaterThanOrEqual(world.x + world.width - 1);
      expect(box.y + box.height).toBeGreaterThanOrEqual(world.y + world.height - 1);
      await page.mouse.down(); await page.mouse.up();
      const feedback = page.locator('.pdf-capture-feedback');
      await feedback.getByRole('checkbox').check();
      await feedback.locator('.agent-feedback-input-action').click();
      await expect(page.locator('.mention-chip [title]').first()).toHaveAttribute('title', '/workspace/docs/report.pdf · p. 1\nHello world');
      expect(app.pageErrors).toEqual([]);
    });
}

for (const restart of [false, true]) {
  test(`PDF element cache ignores retired async results after ${restart ? 'capture restart' : 'text rerender'}`, async ({ page }) => {
    const app = await setup(page);
    await enableImages(page);
    await openFile(app, 'report.pdf');
    await expectPdf(page);
    // Hold the first index's structure request. A subsequent index must become
    // usable before this older request resolves, even for the same DOM page.
    await page.locator('#openseek-office-surface').evaluate(async host => {
      const pdfPage = host.__officeViewerPdf.viewer.getPageView(0).pdfPage;
      const original = pdfPage.getStructTree.bind(pdfPage);
      let first = true;
      window.pdfIndexPending = false;
      pdfPage.getStructTree = () => {
        if (!first) return original();
        first = false;
        window.pdfIndexPending = true;
        return new Promise(resolve => { window.releasePdfIndex = () => resolve(null); });
      };
    });
    const camera = page.getByRole('button', { name: 'Capture region', exact: true });
    await camera.click();
    await expect.poll(() => page.evaluate(() => window.pdfIndexPending)).toBe(true);
    if (restart) {
      await page.keyboard.press('Escape');
      await expect(page.locator('.pdf-region-capture')).toHaveCount(0);
      await camera.click();
    } else {
      await page.locator('#openseek-office-surface').evaluate(host => {
        host.__officeViewerPdf.bus.dispatch('textlayerrendered', { pageNumber: 1 });
      });
    }
    const bounds = await hoverPdfText(page, 'OpenSeek PDF preview');
    await page.evaluate(() => window.releasePdfIndex());
    // Drain the native promise continuations and render observers without sleeps.
    await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
    await expect(page.locator('.pdf-region-capture')).toHaveCount(1);
    await expect(page.locator('.pdf-region-capture-box')).toBeVisible();
    await page.mouse.click(bounds.x + bounds.width / 2, bounds.y + bounds.height / 2);
    const feedback = page.locator('.pdf-capture-feedback');
    await expect(feedback.locator('textarea')).toBeVisible();
    await feedback.getByRole('checkbox').check();
    await feedback.locator('.agent-feedback-input-action').click();
    await expect(page.locator('.mention-chip [title]').first()).toHaveAttribute('title', /OpenSeek PDF preview/);
    await expect(page.locator('.composer-image img')).toHaveAttribute('src', /^data:image\/png;base64,/);
    expect(app.pageErrors).toEqual([]);
  });
}

test('PDF capture rejects a DOM-only push button border', async ({ page }) => {
  const app = await setup(page);
  app.officeFiles['docs/report.pdf'] = formPdf({ kind: 'pushButton', appearance: false });
  await enableImages(page);
  await openFile(app, 'report.pdf');
  await expectPdf(page);
  const field = page.locator('.annotationLayer .buttonWidgetAnnotation.pushButton');
  await expect(field).toBeVisible();
  await expect(field).toHaveCSS('border-top-style', 'solid');
  await expect(field).toHaveCSS('border-top-color', 'rgb(255, 0, 0)');
  expect(await page.locator('.page[data-page-number="1"] canvas').evaluateAll(canvases => {
    return canvases.reduce((count, canvas) => {
      const pixels = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data;
      for (let i = 0; i < pixels.length; i += 4) {
        if (pixels[i] > 200 && pixels[i + 1] < 80 && pixels[i + 2] < 80 && pixels[i + 3] > 0) count++;
      }
      return count;
    }, 0);
  })).toBe(0);
  const bounds = await field.boundingBox();
  await captureRegion(page, bounds, { confirm: false });
  await expect(page.getByText('This form or annotation cannot be captured. Select another region.', { exact: true })).toBeVisible();
  await expect(page.locator('.composer-image')).toHaveCount(0);
  await expect(page.locator('.pdf-capture-feedback')).toBeHidden();
  const pageBounds = await page.locator('.pdfViewer .canvasWrapper canvas').first().boundingBox();
  await captureRegion(page, { x: pageBounds.x + 20, y: pageBounds.y + 20, width: 60, height: 40 });
  await expect(page.locator('.composer-image')).toHaveCount(1);
  expect(app.pageErrors).toEqual([]);
});

for (const state of ['hidden', 'transparent', 'unpainted']) {
  test(`PDF capture allows a ${state} DOM-only button`, async ({ page }) => {
    const app = await setup(page);
    app.officeFiles['docs/report.pdf'] = formPdf({ kind: 'pushButton', appearance: false });
    await enableImages(page);
    await openFile(app, 'report.pdf');
    await expectPdf(page);
    const field = page.locator('.annotationLayer .buttonWidgetAnnotation.pushButton');
    await expect(field).toBeVisible();
    const bounds = await field.boundingBox();
    await field.evaluate((element, state) => {
      if (state === 'hidden') element.style.visibility = 'hidden';
      if (state === 'transparent') element.style.opacity = '0';
      if (state === 'unpainted') element.style.borderColor = 'transparent';
    }, state);
    await captureRegion(page, bounds);
    await expect(page.locator('.composer-image')).toHaveCount(1);
    expect(app.pageErrors).toEqual([]);
  });
}

{
  const kind = 'pushButton';

  test(`PDF capture retains ${kind} bitmap appearances with interactive forms disabled`, async ({ page }) => {
    const app = await setup(page);
    app.officeFiles['docs/report.pdf'] = formPdf({ kind });
    await enableImages(page);
    await openFile(app, 'report.pdf');
    await expectPdf(page);
    await expect(page.locator('.annotationLayer input, .annotationLayer select')).toHaveCount(0);
    expect(await page.locator('#openseek-office-surface').evaluate(host => host.__officeViewerPdf.viewer.renderForms)).toBe(false);
    const b = await page.locator('.pdfViewer .canvasWrapper canvas').first().boundingBox();
    const scale = b.width / 612;
    await captureRegion(page, { x: b.x + 70 * scale, y: b.y + (792 - 695) * scale, width: 245 * scale, height: 50 * scale });
    const red = await page.locator('.composer-image img').evaluate(img => {
      const canvas = document.createElement('canvas');
      canvas.width = img.naturalWidth; canvas.height = img.naturalHeight;
      const ctx = canvas.getContext('2d'); ctx.drawImage(img, 0, 0);
      const pixels = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
      let red = 0;
      for (let i = 0; i < pixels.length; i += 4) {
        if (pixels[i] > 200 && pixels[i + 1] < 80 && pixels[i + 2] < 80) red++;
      }
      return red;
    });
    expect(red).toBeGreaterThan(100);
    expect(app.pageErrors).toEqual([]);
  });
}

{
  const kind = 'Square';

  test(`PDF capture preserves ${kind} markup beneath transparent SVG hit areas`, async ({ page }) => {
    const app = await setup(page);
    app.officeFiles['docs/report.pdf'] = markupPdf(kind);
    await enableImages(page);
    await openFile(app, 'report.pdf');
    await expectPdf(page);
    const svg = page.locator('.annotationLayer svg');
    await expect(svg).toHaveCount(1);
    const shapes = svg.locator('line, rect, ellipse, polyline, polygon');
    await expect(shapes).toHaveCount(1);
    await expect(shapes).toHaveCSS('stroke', 'rgba(0, 0, 0, 0)');
    await expect(shapes).toHaveCSS('fill', 'rgba(0, 0, 0, 0)');
    const painted = await page.locator('.page[data-page-number="1"] canvas').evaluateAll(canvases => {
      let red = 0;
      for (const canvas of canvases) {
        const pixels = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data;
        for (let i = 0; i < pixels.length; i += 4) {
          if (pixels[i] > 200 && pixels[i + 1] < 80 && pixels[i + 2] < 80 && pixels[i + 3] > 0) red++;
        }
      }
      return red;
    });
    expect(painted).toBeGreaterThan(100);
    const b = await page.locator('.pdfViewer .canvasWrapper canvas').first().boundingBox();
    const scale = b.width / 612;
    await captureRegion(page, { x: b.x + 65 * scale, y: b.y + (792 - 737) * scale, width: 255 * scale, height: 100 * scale });
    const captured = await page.locator('.composer-image img').evaluate(img => {
      const canvas = document.createElement('canvas');
      canvas.width = img.naturalWidth; canvas.height = img.naturalHeight;
      const ctx = canvas.getContext('2d'); ctx.drawImage(img, 0, 0);
      const pixels = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
      let red = 0;
      for (let i = 0; i < pixels.length; i += 4) {
        if (pixels[i] > 200 && pixels[i + 1] < 80 && pixels[i + 2] < 80 && pixels[i + 3] > 0) red++;
      }
      return red;
    });
    expect(captured).toBeGreaterThan(100);
    expect(app.pageErrors).toEqual([]);
  });
}

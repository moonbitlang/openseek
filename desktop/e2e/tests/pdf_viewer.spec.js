import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';
import { pinchZoom } from './support/office_zoom.js';

async function openFile(app, name) {
  await app.openQuickOpen();
  await app.page.locator('#quick-open-input').fill(name);
  await app.page.getByRole('option', { name: new RegExp(name.replaceAll('.', '\\.')) }).click();
}

async function setup(page) {
  const app = new DesktopBrowserHarness(page);
  app.officeFiles['docs/broken.pdf'] = {
    data_base64: Buffer.from('invalid PDF data').toString('base64'),
    media_type: 'application/pdf', sig: 'pdf:broken',
  };
  app.searchFiles = ['docs/report.pdf', 'docs/encrypted.pdf', 'docs/broken.pdf', 'docs/report.docx'];
  app.directoryEntries['/workspace'] = [{ name: 'docs', is_dir: true }];
  app.directoryEntries['/workspace/docs'] = app.searchFiles.map(path => ({ name: path.split('/').at(-1), is_dir: false }));
  await app.install();
  await app.goto();
  await app.openSession();
  await page.getByRole('button', { name: 'Hide sidebar', exact: true }).click();
  await app.openReview({ waitForHistory: false });
  await page.getByRole('tab', { name: 'Files', exact: true }).click();
  return app;
}

async function expectPdf(page) {
  await expect(page.locator('#openseek-office-surface')).toHaveAttribute('data-pdf-painted', 'true');
  await expect(page.locator('.pdfViewer .page')).toHaveCount(2);
  await expect(page.getByRole('spinbutton', { name: 'PDF page number', exact: true })).toBeEnabled();
  await expect(page.locator('.viewer-notice')).toHaveClass(/hidden/);
  await expect(page.getByRole('dialog', { name: 'Unlock PDF', exact: true })).toBeHidden();
}

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
  await expect(preview.locator('.office-selection-source')).toHaveText('report.pdf · p. 2');
  await expect(preview.locator('.office-selection-excerpt')).toHaveText('Second');
  await expect(page.locator('.mention-chip')).toHaveCount(0);
  await preview.getByRole('button', { name: 'Cancel', exact: true }).click();
  await expect(preview).toBeHidden();
  await expect(page.locator('.mention-chip')).toHaveCount(0);
  await selectSecond();
  await expect(preview).toBeVisible();
  await preview.getByRole('button', { name: 'Add to context', exact: true }).click();
  await expect(preview).toBeHidden();
  await expect(page.locator('.mention-chip')).toContainText('report.pdf · p. 2');
  await expect(page.locator('.mention-chip')).toContainText('Second');
  await selectSecond(11);
  await expect(preview.locator('.office-selection-excerpt')).toHaveText('Second page');
  await expect(page.locator('.mention-chip')).toHaveCount(1);
  await preview.getByRole('button', { name: 'Add to context', exact: true }).click();
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
  await expect(preview.locator('.office-selection-excerpt')).toHaveText('OpenSeek');
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

import { test, expect } from './support/test.js';
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

async function openFile(app, name) {
  await app.openQuickOpen();
  await app.page.locator('#quick-open-input').fill(name);
  await app.page.getByRole('option', { name: new RegExp(name.replaceAll('.', '\\.')) }).click();
}

async function setup(page, { openTree = true } = {}) {
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

test('PDF uses the shared annotation composer with pinned drafts, Batch, and apply', async ({ page }) => {
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

async function enableImages(page) {
  await page.getByRole('button', { name: 'Model', exact: true }).click();
  await page.getByRole('option', { name: /^DS Flash(?: ✓)?$/ }).click();
}

async function captureRegion(page, rect, { confirm = true } = {}) {
  await page.getByRole('button', { name: 'Capture region', exact: true }).click();
  await expect(page.locator('.pdf-region-capture')).toBeVisible();
  const a = { x: rect.x, y: rect.y }, b = { x: rect.x + rect.width, y: rect.y + rect.height };
  await page.mouse.move(...Object.values(a));
  await page.mouse.down();
  await page.mouse.move(...Object.values(b), { steps: 8 });
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

  test('crops real page pixels at display resolution and sends an image without losing typed text', async ({ page }) => {
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
    await captureRegion(page, rect);
    const attachment = page.locator('.composer-image img');
    await expect(attachment).toHaveAttribute('src', expected.url);
    expect(await attachment.evaluate(img => [img.naturalWidth, img.naturalHeight])).toEqual([expected.width, expected.height]);
    expect(expected.width).toBeGreaterThan(rect.width);
    await expect(page.locator('#task')).toHaveValue('Explain this figure');
    expect(app.requests.filter(r => r.method === 'agent.start')).toHaveLength(0);
    await page.locator('#send').click();
    await expect.poll(() => app.requests.filter(r => r.method === 'agent.start').length).toBe(1);
    const request = app.requests.find(r => r.method === 'agent.start');
    expect(JSON.stringify(request.params)).toContain(expected.url);
    expect(JSON.stringify(request.params)).toContain('Explain this figure');
    await expect(page.locator('.composer-image')).toHaveCount(0);
    expect(app.pageErrors).toEqual([]);
  });
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

test('PDF capture feedback sends the image and instruction with existing typing', async ({ page }) => {
    const app = await setup(page);
    await enableImages(page);
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
    await input.press('Alt+Enter');
    const method = 'agent.start';
    await expect.poll(() => app.requests.filter(r => r.method === method).length).toBe(1);
    const request = JSON.stringify(app.requests.find(r => r.method === method).params);
    expect(request).toContain('data:image/png;base64,');
    expect(request).toContain('Keep my existing draft');
    expect(request).toContain('把这部分改成中文，并加上标题');
    const params = app.requests.find(r => r.method === method).params;
    const prompt = params.task;
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

async function hoverPdfText(page, text) {
  const span = page.locator('.textLayer span[data-pdf-item]').filter({ hasText: text }).first();
  await expect(span).toBeVisible();
  await span.hover();
  const b = await span.boundingBox();
  await expect(page.locator('.pdf-region-capture-box')).toBeVisible();
  return b;
}

test('PDF element hover and a slightly moving click attach text, page and screenshot', async ({ page }) => {
  const app = await setup(page);
  await enableImages(page);
  await openFile(app, 'report.pdf');
  await expectPdf(page);
  await page.getByRole('button', { name: 'Capture region', exact: true }).click();
  const b = await hoverPdfText(page, 'OpenSeek PDF preview');
  const box = await page.locator('.pdf-region-capture-box').boundingBox();
  expect(Math.abs(box.x - b.x)).toBeLessThanOrEqual(3);
  expect(Math.abs(box.width - b.width)).toBeLessThanOrEqual(5);
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

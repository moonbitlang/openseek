import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

const pdf = {
  name: '下载-5-1.pdf', mimeType: 'application/pdf',
  buffer: readFileSync(new URL('../fixtures/office/two-pages.pdf', import.meta.url)),
};

async function open(page) {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  return app;
}

async function select(page, files = pdf) {
  const chooser = page.waitForEvent('filechooser');
  await page.getByRole('button', { name: 'Attach files', exact: true }).click();
  await (await chooser).setFiles(files);
  await expect(page.locator('.composer-attachment-confirm')).toBeVisible();
}

function imports(app) {
  return app.requests.filter(r => r.method === 'fs.import_attachment');
}

test('PDF upload waits for confirmation then opens from its existing file mention for manual quotation', async ({ page }) => {
  const app = await open(page);
  await page.locator('#task').fill('Explain this passage');
  await select(page);
  await expect(page.locator('#send')).toBeDisabled();
  await page.locator('#task').press('Enter');
  expect(imports(app)).toHaveLength(0);
  expect(app.requests.some(r => r.method === 'fs.prepare_attachment')).toBe(false);
  expect(app.requests.some(r => r.method === 'agent.start')).toBe(false);
  await page.getByRole('button', { name: 'Upload to workspace', exact: true }).click();
  await expect(page.locator('.composer-attachment-confirm')).toHaveCount(0);
  const chip = page.locator('.mention-chip').filter({ hasText: pdf.name });
  await expect(chip).toBeVisible();
  expect(imports(app)).toHaveLength(1);
  expect(imports(app)[0].params.source.data_base64).toBe(pdf.buffer.toString('base64'));
  await chip.locator('.mention-jump').click();
  await expect(page.locator('#openseek-office-surface')).toHaveAttribute('data-pdf-painted', 'true');
  const text = page.locator('.page[data-page-number="1"] [data-pdf-item]').filter({ hasText: 'OpenSeek PDF preview' }).first();
  await expect(text).toBeVisible();
  await text.evaluate(element => {
    const range = document.createRange();
    range.setStart(element.firstChild, 0);
    range.setEnd(element.firstChild, 8);
    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
    document.dispatchEvent(new Event('selectionchange'));
  });
  const preview = page.locator('.office-selection-preview');
  await expect(preview).toBeVisible();
  await expect(preview).toHaveAttribute('title', /OpenSeek/);
  await expect(page.locator('.mention-chip')).toHaveCount(1);
  await preview.locator('textarea').fill('Explain the selected passage');
  await preview.getByRole('checkbox').check();
  await preview.getByRole('button', { name: 'Add feedback', exact: true }).click();
  await expect(preview).toBeHidden();
  await expect(page.locator('.mention-chip')).toHaveCount(2);
  await expect(page.locator('.mention-chip').filter({ hasText: 'Explain the selected passage' })).toBeVisible();
  expect(app.requests.some(r => r.method === 'agent.start')).toBe(false);
  await page.locator('#send').click();
  await expect.poll(() => app.requests.find(r => r.method === 'agent.start')?.params.task).toContain('<office_selection>');
  const request = app.requests.find(r => r.method === 'agent.start');
  const quotation = JSON.parse(request.params.task.match(/<office_selection>([\s\S]*?)<\/office_selection>/)[1]);
  expect(quotation.source.reference.file).toBe('/workspace/.openseek/attachments/upload-1/下载-5-1.pdf');
  expect(quotation.selection.text).toBe('OpenSeek');
  expect(quotation.comment).toBe('Explain the selected passage');
  expect(request.params.images).toEqual([]);
  expect(app.requests.find(r => r.method === 'fs.stage_attachments').params.paths).toEqual([
    '.openseek/attachments/upload-1/下载-5-1.pdf',
  ]);
  expect(app.pageErrors).toEqual([]);
});

test('cancelling or failing a document import keeps the editable draft', async ({ page }, testInfo) => {
  const app = await open(page);
  await page.locator('#task').fill('Keep this draft');
  await select(page);
  await page.getByRole('button', { name: 'Cancel', exact: true }).click();
  await expect(page.locator('.composer-attachment-confirm')).toHaveCount(0);
  await expect(page.locator('#task')).toHaveValue('Keep this draft');
  expect(imports(app)).toHaveLength(0);
  app.rpcErrors.set('fs.import_attachment', 'Attachment upload failed');
  await select(page);
  await page.getByRole('button', { name: 'Upload to workspace', exact: true }).click();
  await expect(page.getByRole('alert')).toContainText('Attachment upload failed');
  await expect(page.getByRole('alert')).toHaveCSS('border-radius', '14px');
  await page.locator('.composer').screenshot({ path: testInfo.outputPath('attachment-error.png') });
  await expect(page.locator('#task')).toHaveValue('Keep this draft');
  await expect(page.locator('.mention-chip')).toHaveCount(0);
  await expect(page.locator('#send')).toBeEnabled();
  app.rpcErrors.delete('fs.import_attachment');
  await select(page);
  await page.getByRole('button', { name: 'Upload to workspace', exact: true }).click();
  await expect(page.locator('.mention-chip')).toContainText(pdf.name);
  expect(app.pageErrors).toEqual([]);
});

test('DOCX and XLSX drops with empty MIME types use original-file previews', async ({ page }) => {
  const app = await open(page);
  const documents = [
    { name: 'Report.DOCX', bytes: app.officeFiles['docs/report.docx'].data_base64 },
    { name: 'table.xlsx', bytes: app.officeFiles['docs/book1.xlsx'].data_base64 },
  ];
  const prevented = await page.locator('#task').evaluate((target, documents) => {
    const transfer = new DataTransfer();
    for (const document of documents) {
      transfer.items.add(new File([Uint8Array.from(atob(document.bytes), c => c.charCodeAt(0))], document.name));
    }
    const event = new DragEvent('drop', { dataTransfer: transfer, bubbles: true, cancelable: true });
    target.dispatchEvent(event);
    return event.defaultPrevented;
  }, documents);
  expect(prevented).toBe(true);
  await expect(page.locator('.composer-attachment-confirm')).toHaveCount(2);
  for (const document of documents) {
    await page.locator('.composer-attachment-confirm').filter({ hasText: document.name })
      .getByRole('button', { name: 'Upload to workspace', exact: true }).click();
  }
  await expect(page.locator('.mention-chip')).toHaveCount(2);
  await page.locator('.mention-chip').filter({ hasText: 'Report.DOCX' }).locator('.mention-jump').click();
  await expect(page.locator('.word-page')).toContainText('Walking on imported air');
  await page.locator('.mention-chip').filter({ hasText: 'table.xlsx' }).locator('.mention-jump').click();
  await expect(page.locator('.sheet-document table').first()).toBeVisible();
  for (const document of documents) {
    expect(imports(app).find(r => r.params.source.name === document.name).params.source.data_base64).toBe(document.bytes);
  }
  expect(app.pageErrors).toEqual([]);
});

test('a staging failure keeps the document reference and rejects the prompt before starting an agent', async ({ page }) => {
  const app = await open(page);
  await select(page);
  await page.getByRole('button', { name: 'Upload to workspace', exact: true }).click();
  await expect(page.locator('.mention-chip')).toContainText(pdf.name);
  await page.locator('#task').fill('Read this document');
  app.rpcErrors.set('fs.stage_attachments', 'Could not stage attachment');
  await page.locator('#send').click();
  await expect(page.getByText('Could not stage attachment', { exact: false }).first()).toBeVisible();
  expect(app.requests.some(r => r.method === 'agent.start')).toBe(false);
  await expect(page.locator('#task')).toHaveValue('Read this document');
  await expect(page.locator('.mention-chip')).toContainText(pdf.name);
  app.rpcErrors.delete('fs.stage_attachments');
  await page.locator('#send').click();
  await expect.poll(() => app.requests.filter(r => r.method === 'agent.start').length).toBe(1);
  expect(imports(app)).toHaveLength(1);
  expect(app.pageErrors).toEqual([]);
});

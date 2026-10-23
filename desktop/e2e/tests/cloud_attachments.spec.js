import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { CloudHarness, authOrigin, sessionA, sessionC } from './support/cloud_harness.js';

const bytes = readFileSync(new URL('../../../deepseek/client/testdata/two-colors.png', import.meta.url));
const png = bytes.toString('base64');
const imageURL = `data:image/png;base64,${png}`;
const image = { name: 'two-colors.png', mimeType: 'image/png', buffer: bytes };
const document = { name: 'report.pdf', mimeType: 'application/pdf', buffer: Buffer.from('%PDF-1.7\nfixture') };

class AttachmentHarness extends CloudHarness {
  constructor(page) {
    super(page);
    this.imports = [];
    this.prepares = [];
    this.importStatus = 200;
    this.pauseImport = null;
  }

  async cloudRequest(route) {
    const request = route.request();
    const path = new URL(request.url()).pathname;
    const match = path.match(/^\/v1\/sessions\/([^/]+)\/files\/(prepare|import)$/);
    if (!match) return super.cloudRequest(route);
    const headers = { 'Access-Control-Allow-Origin': authOrigin, 'Access-Control-Allow-Headers': 'Authorization, Content-Type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
    if (request.method() === 'OPTIONS') return route.fulfill({ status: 204, headers });
    const body = request.postDataJSON();
    expect(Object.keys(body)).toEqual(['source']);
    expect(body.source.kind).toBe('bytes');
    const record = { session: match[1], source: body.source, headers: await request.allHeaders() };
    this.requests.push({ side: 'cloud', method: request.method(), path, body: request.postData() });
    const json = (body, status = 200) => route.fulfill({ status, headers, contentType: 'application/json', body: JSON.stringify(body) });
    if (match[2] === 'prepare') {
      this.prepares.push(record);
      return json({ kind: 'upload_required', name: body.source.name });
    }
    this.imports.push(record);
    if (this.pauseImport) await this.pauseImport;
    if (this.importStatus !== 200) return json({}, this.importStatus);
    return json({ path: `.openseek/attachments/fixture-${this.imports.length}/${body.source.name}` });
  }
}

async function select(page, files) {
  const chooser = page.waitForEvent('filechooser');
  await page.getByRole('button', { name: 'Attach files', exact: true }).click();
  await (await chooser).setFiles(files);
}

const creations = cloud => cloud.requests.filter(request => request.path === '/v1/sessions' && request.method === 'POST');
const messages = cloud => cloud.requests.filter(request => request.path.endsWith('/commands') && request.method === 'POST');

test('blank Cloud keeps confirmed files and image bytes in memory until first Send, then restores immutable history', async ({ page }, testInfo) => {
  const cloud = new AttachmentHarness(page);
  await cloud.install(); await cloud.goto(); await cloud.create();
  await select(page, [document, image]);
  await expect(page.locator('.composer-image img')).toHaveAttribute('src', imageURL);
  await page.getByRole('button', { name: 'Upload to workspace', exact: true }).click();
  await expect(page.locator('.composer .mention-chip')).toContainText('report.pdf');
  expect(creations(cloud)).toHaveLength(0);
  expect(cloud.imports).toEqual([]);
  expect(cloud.prepares).toEqual([]);
  await page.screenshot({ path: testInfo.outputPath('cloud-attachments-draft.png'), fullPage: true });
  await page.locator('#task').fill('Inspect the attachments');
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect.poll(() => messages(cloud).length).toBe(1);
  await expect(page.locator('#task')).toHaveValue('');
  expect(creations(cloud)).toHaveLength(1);
  expect(cloud.imports.map(upload => upload.session)).toEqual([sessionC, sessionC]);
  expect(cloud.imports.map(upload => upload.source.name)).toEqual(['report.pdf', 'two-colors.png']);
  expect(cloud.imports[1].source.data_base64).toBe(png);
  const content = JSON.parse(messages(cloud)[0].body).command.content;
  expect(content[0]).toMatchObject({ type: 'text' });
  expect(content[0].text).toContain('.openseek/attachments/fixture-1/report.pdf');
  expect(content[0].text).toContain('Inspect the attachments');
  expect(content[1]).toEqual({ type: 'image', media_type: 'image/png', data: png });
  await expect(page.locator('.composer-image')).toHaveCount(0);
  await expect(page.locator('.composer .mention-chip')).toHaveCount(0);
  await expect(page.locator('#transcript .user-image')).toHaveAttribute('src', imageURL);
  await page.reload(); await cloud.open(sessionC);
  await expect(page.locator('#transcript .user-image')).toHaveAttribute('src', imageURL);
  expect(cloud.imports.every(upload => /^Bearer ts_fixture-/.test(upload.headers.authorization))).toBe(true);
  expect(cloud.imports.every(upload => upload.headers.cookie === undefined)).toBe(true);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('a failed first image send preserves the draft and known session, and explicit retry reuses its completed import', async ({ page }) => {
  const cloud = new AttachmentHarness(page);
  cloud.sendStatus = 503;
  cloud.sendErrorBody = 'server model credentials are not configured';
  await cloud.install(); await cloud.goto(); await cloud.create();
  await select(page, image);
  await page.locator('#task').fill('Keep these pixels');
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect(page.getByRole('main')).toContainText('Cloud model credentials are not configured');
  await expect(page.locator('#task')).toHaveValue('Keep these pixels');
  await expect(page.locator('.composer-image img')).toHaveAttribute('src', imageURL);
  expect(creations(cloud)).toHaveLength(1);
  expect(cloud.imports).toHaveLength(1);
  expect(messages(cloud)).toHaveLength(1);
  cloud.sendStatus = 202;
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect(page.locator('#task')).toHaveValue('');
  expect(creations(cloud)).toHaveLength(1);
  expect(cloud.imports).toHaveLength(1);
  expect(messages(cloud)).toHaveLength(2);
  expect(JSON.parse(messages(cloud)[1].body).command.content[1].data).toBe(png);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('existing Cloud documents use Upload confirmation and retain bytes after a failed import', async ({ page }) => {
  const cloud = new AttachmentHarness(page);
  cloud.importStatus = 503;
  await cloud.install(); await cloud.goto(); await cloud.open(sessionA);
  await select(page, document);
  expect(creations(cloud)).toHaveLength(0);
  expect(cloud.imports).toHaveLength(0);
  await page.getByRole('button', { name: 'Upload to workspace', exact: true }).click();
  await expect(page.locator('.composer-image-notice.error')).toContainText('Cloud answered HTTP 503');
  await expect(page.getByRole('button', { name: 'Upload to workspace', exact: true })).toBeVisible();
  expect(cloud.imports).toHaveLength(1);
  cloud.importStatus = 200;
  await page.getByRole('button', { name: 'Upload to workspace', exact: true }).click();
  await expect(page.locator('.composer .mention-chip')).toContainText('report.pdf');
  expect(cloud.imports).toHaveLength(2);
  expect(cloud.imports[0].source).toEqual(cloud.imports[1].source);
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect.poll(() => messages(cloud).length).toBe(1);
  expect(JSON.parse(messages(cloud)[0].body).command.content).toContain('.openseek/attachments/fixture-2/report.pdf');
  expect(creations(cloud)).toHaveLength(0);
  expect(cloud.device.pageErrors).toEqual([]);
});

// composer/component_wbtest.mbt covers the full acknowledgement/text-edit state matrix.
// Keep one browser flow per input event and acknowledgement outcome here.
for (const [method, editText] of [['picker', false], ['paste', true]]) {
  test(`Cloud keeps a new ${method} image ${editText ? 'with newer text' : 'without editing text'} through admission without resending the submitted copy`, async ({ page }) => {
    const cloud = new AttachmentHarness(page);
    let admit, finish;
    cloud.pauseSend = new Promise(resolve => admit = resolve);
    cloud.pauseStream = new Promise(resolve => finish = resolve);
    try {
      await cloud.install(); await cloud.goto(); await cloud.open();
      await select(page, image);
      await page.locator('#task').fill('Submitted content');
      await page.getByRole('button', { name: 'Send', exact: true }).click();
      await expect.poll(() => messages(cloud).length).toBe(1);
      if (method === 'picker') {
        await select(page, image);
      } else {
        await page.locator('#task').evaluate((input, { png, name }) => {
          const transfer = new DataTransfer();
          transfer.items.add(new File([Uint8Array.from(atob(png), c => c.charCodeAt(0))], name, { type: 'image/png' }));
          input.dispatchEvent(new ClipboardEvent('paste', { clipboardData: transfer, bubbles: true, cancelable: true }));
        }, { png, name: image.name });
      }
      await expect(page.locator('.composer-image')).toHaveCount(2);
      if (editText) await page.locator('#task').fill('Next draft');
      admit();
      await expect(page.locator('#task')).toHaveValue(editText ? 'Next draft' : '');
      await expect(page.locator('.composer-image')).toHaveCount(1);
      await expect(page.locator('#transcript .user-image')).toHaveCount(1);
      finish();
      await expect(page.getByRole('button', { name: 'Send', exact: true })).toBeEnabled();
      await expect(page.locator('.composer-image img')).toHaveAttribute('src', imageURL);
      await page.getByRole('button', { name: 'Send', exact: true }).click();
      await expect.poll(() => messages(cloud).length).toBe(2);
      expect(JSON.parse(messages(cloud)[1].body).command.content).toEqual([
        { type: 'text', text: editText ? 'Next draft' : '' },
        { type: 'image', media_type: 'image/png', data: png },
      ]);
      expect(cloud.device.pageErrors).toEqual([]);
    } finally {
      admit(); finish();
    }
  });
}

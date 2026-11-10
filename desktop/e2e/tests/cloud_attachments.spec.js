import { test, expect } from './support/test.js';
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

test('blank Cloud keeps confirmed files and image bytes in memory until first Send, then restores immutable history', async ({ page }) => {
  const cloud = new AttachmentHarness(page);
  await cloud.install(); await cloud.goto(); await cloud.create();
  await select(page, [document, image]);
  await expect(page.locator('.composer-image img')).toHaveAttribute('src', imageURL);
  await page.getByRole('button', { name: 'Upload to workspace', exact: true }).click();
  await expect(page.locator('.composer .mention-chip')).toContainText('report.pdf');
  expect(creations(cloud)).toHaveLength(0);
  expect(cloud.imports).toEqual([]);
  expect(cloud.prepares).toEqual([]);
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


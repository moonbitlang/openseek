import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';
import { CloudHarness, authOrigin, cloudOrigin, sessionA, sessionB } from './support/cloud_harness.js';

class CloudFilesHarness extends CloudHarness {
  constructor(page, options) {
    super(page, options);
    this.fileRequests = [];
    this.directories = new Map();
    this.indexes = new Map();
    this.contents = new Map();
    this.largePreviews = new Map();
    this.fileStatus = 200;
    this.holdRead = null;
    this.holdHead = null;
    this.downloads = new Map();
    this.downloadStatus = 200;
    this.holdDownload = null;
    this.holdFileShare = null;
    for (const session of [sessionA, sessionB]) {
      this.indexes.set(session, ['src/hello #.mbt']);
      this.directories.set(`${session}:`, [{ name: 'src', is_dir: true }]);
      this.directories.set(`${session}:src`, [{ name: 'hello #.mbt', is_dir: false }]);
      this.contents.set(`${session}:src/hello #.mbt`, {
        kind: 'content', content: `// ${session}\nfn hello() -> String { "Cloud text" }`,
        sig: `sig-${session}`, absolute: '/src/hello #.mbt',
      });
    }
  }

  async cloudRequest(route) {
    const url = new URL(route.request().url());
    const match = url.pathname.match(/^\/v1\/sessions\/([^/]+)\/files(\/content|\/index|\/download|\/share)?$/);
    if (!match) return super.cloudRequest(route);
    const headers = { 'Access-Control-Allow-Origin': authOrigin, 'Access-Control-Allow-Headers': 'Authorization, Content-Type, If-None-Match', 'Access-Control-Allow-Methods': 'GET, HEAD, POST, OPTIONS', 'Access-Control-Expose-Headers': 'ETag', 'Cache-Control': 'no-store' };
    const method = route.request().method();
    if (method === 'OPTIONS') return route.fulfill({ status: 204, headers });
    if (match[2] === '/share' && method === 'POST') {
      const body = route.request().postDataJSON();
      this.fileRequests.push({ share: true, body, method, headers: await route.request().allHeaders() });
      if (this.holdFileShare) await this.holdFileShare;
      return route.fulfill({ status: this.shareStatus, headers, contentType: 'application/json', body: JSON.stringify({ url: `${authOrigin}/v1/shares/file-fixture` }) });
    }
    const session = decodeURIComponent(match[1]);
    const path = url.searchParams.get('path') || '';
    const contentPath = match[2] === '/content';
    const head = contentPath && method === 'HEAD';
    const content = contentPath && method === 'GET';
    const index = match[2] === '/index';
    const download = match[2] === '/download';
    const allowLarge = url.searchParams.get('allow_large');
    const request = { session, path, method, content, head, index, download, allowLarge, headers: await route.request().allHeaders() };
    this.fileRequests.push(request);
    if (download) {
      if (this.holdDownload) await this.holdDownload;
      request.status = this.downloadStatus;
      return route.fulfill({ status: this.downloadStatus, headers, contentType: 'application/octet-stream', body: this.downloads.get(`${session}:${path}`) || Buffer.from('raw original') });
    }
    let body;
    if (index) {
      body = { files: this.indexes.get(session) || [] };
    } else if (contentPath) {
      body = allowLarge === 'true' && this.largePreviews.has(`${session}:${path}`)
        ? this.largePreviews.get(`${session}:${path}`) : this.contents.get(`${session}:${path}`);
    } else {
      body = { entries: this.directories.get(`${session}:${path}`) || [] };
    }
    let status = this.fileStatus;
    if (contentPath && status === 200 && ['content', 'binary_content'].includes(body?.kind)) {
      headers.ETag = `W/"content-v1-${createHash('sha256').update(JSON.stringify(body)).digest('hex')}"`;
      if (head && request.headers['if-none-match'] === headers.ETag) status = 304;
    }
    if (this.fileOffline) return route.abort('failed');
    if (head && this.holdHead) await this.holdHead;
    if (content && this.holdRead) await this.holdRead;
    request.status = status;
    return route.fulfill({ status, headers, contentType: 'application/json', ...(head ? {} : { body: JSON.stringify(body) }) });
  }
}

const tree = page => page.getByRole('tree', { name: 'Workspace files', exact: true });
const file = (page, name) => tree(page).getByRole('treeitem', { name, exact: true });
const source = page => page.locator('#viewer-host');

async function openFiles(page, cloud) {
  await cloud.open();
  await page.getByRole('button', { name: 'Show panel', exact: true }).click();
  const launcher = page.locator('.dock-launcher');
  await expect(launcher.getByRole('button')).toHaveText([/Search/, /Files/]);
  await launcher.getByRole('button', { name: /^Files / }).click();
  await expect(tree(page).getByRole('treeitem').first()).toBeVisible();
}

async function openText(page) {
  await file(page, 'src').click();
  await file(page, 'hello #.mbt').click();
  await expect(source(page)).toContainText('Cloud text');
}

async function showTree(page) {
  const toggle = page.getByRole('button', { name: 'Show file tree', exact: true });
  if (await toggle.isVisible()) await toggle.click();
}

function fileHostRequests(cloud) {
  return [...cloud.hostRequests, ...cloud.device.requests].filter(request =>
    /^(fs\.|lsp\.|git\.|moon\.|file\.|host\.open_path$)/.test(request.method));
}

async function expectFileValidation(page, session, path, action, status = 304) {
  const reply = page.waitForResponse(response => {
    const url = new URL(response.url());
    return response.request().method() === 'HEAD'
      && url.pathname === `/v1/sessions/${session}/files/content`
      && url.searchParams.get('path') === path;
  });
  await action();
  const response = await reply;
  // HEAD is complete when its headers arrive; there is no response body.
  expect(response.status()).toBe(status);
  expect(new URL(response.url()).searchParams.get('allow_large')).toBe('true');
  const validator = response.request().headers()['if-none-match'];
  expect(validator).toMatch(/^W\/"content-v1-[a-f0-9]{64}"$/);
  if (status === 304) expect(response.headers().etag).toBe(validator);
}

for (const entry of ['empty panel', 'new-tab menu']) {
  test(`Cloud Search opens from the ${entry} using the shared search action`, async ({ page }, testInfo) => {
    const cloud = new CloudFilesHarness(page);
    await cloud.install(); await cloud.goto();
    let row;
    if (entry === 'empty panel') {
      await cloud.open();
      await page.getByRole('button', { name: 'Show panel', exact: true }).click();
      row = page.locator('.dock-launcher').getByRole('button', { name: /^Search / });
    } else {
      await openFiles(page, cloud);
      await page.getByRole('button', { name: 'New tab', exact: true }).click();
      const menu = page.locator('.dock-menu');
      await expect(menu.getByRole('menuitem')).toHaveText([/Search/, /Files/]);
      row = menu.getByRole('menuitem', { name: 'Search', exact: true });
    }
    await expect(row).toBeVisible();
    await page.screenshot({ path: testInfo.outputPath(`cloud-search-${entry.replaceAll(' ', '-')}.png`), animations: 'disabled' });
    await row.click();
    await expect(page.locator('.dock-menu')).toHaveCount(0);
    await expect(page.locator('.dock-launcher')).toBeHidden();
    await expect(page.locator('.editor-tab.active .tab-name')).toHaveText('Search');
    await expect(page.getByRole('tab', { name: 'Search', exact: true })).toHaveAttribute('aria-selected', 'true');
    await expect(page.locator('.workspace-search').getByRole('textbox', { name: 'Search', exact: true })).toBeVisible();
    expect(fileHostRequests(cloud)).toEqual([]);
    expect(cloud.device.pageErrors).toEqual([]);
  });
}

test('Cloud raster files reuse the file panel and restore the cached image after a text tab', async ({ page }, testInfo) => {
  const cloud = new CloudFilesHarness(page);
  const png = readFileSync(new URL('../../../deepseek/client/testdata/two-colors.png', import.meta.url)).toString('base64');
  cloud.directories.set(`${sessionA}:`, [{ name: 'picture.png', is_dir: false }, { name: 'src', is_dir: true }]);
  cloud.contents.set(`${sessionA}:picture.png`, { kind: 'binary_content', data_base64: png, media_type: 'image/png', sig: 'image:1' });
  await cloud.install(); await cloud.goto(); await openFiles(page, cloud);
  await file(page, 'picture.png').click();
  const image = page.locator('.file-image-preview img');
  await expect(image).toBeVisible();
  await expect(image).toHaveAttribute('src', `data:image/png;base64,${png}`);
  await expect(image).toHaveAttribute('alt', 'picture.png');
  await expect.poll(() => image.evaluate(image => image.naturalWidth)).toBeGreaterThan(0);
  await page.screenshot({ path: testInfo.outputPath('cloud-image-preview.png'), fullPage: true });
  await showTree(page);
  await openText(page);
  await expect(image).toHaveCount(0);
  const reads = cloud.fileRequests.filter(request => request.content && request.path === 'picture.png').length;
  await showTree(page); await file(page, 'picture.png').click();
  await expect(image).toBeVisible();
  const renderedImage = await image.elementHandle();
  await expectFileValidation(page, sessionA, 'picture.png', () => page.evaluate(session => window.cloudInvalidateFiles(session), sessionA));
  expect(await renderedImage.evaluate(element => element.isConnected)).toBe(true);
  await cloud.open(sessionB);
  await expectFileValidation(page, sessionA, 'picture.png', () => cloud.open(sessionA));
  await expect(image).toHaveAttribute('src', `data:image/png;base64,${png}`);
  expect(cloud.fileRequests.filter(request => request.content && request.path === 'picture.png')).toHaveLength(reads);
  expect(fileHostRequests(cloud)).toEqual([]);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('Cloud Office selections reuse the existing feedback composer and send relative file references', async ({ page }) => {
  const cloud = new CloudFilesHarness(page);
  cloud.directories.set(`${sessionA}:`, [{ name: 'book1.xlsx', is_dir: false }]);
  cloud.contents.set(`${sessionA}:book1.xlsx`, { kind: 'binary_content', ...cloud.device.officeFiles['docs/book1.xlsx'] });
  await cloud.install(); await cloud.goto(); await openFiles(page, cloud);
  await file(page, 'book1.xlsx').click();
  const cells = page.locator('.sheet-document td[data-cell]');
  await expect(cells.first()).toBeVisible();
  await expectFileValidation(page, sessionA, 'book1.xlsx', () => page.evaluate(session => window.cloudInvalidateFiles(session), sessionA));
  await cells.first().click();
  const feedback = page.locator('.office-selection-preview');
  await expect(feedback.locator('textarea')).toBeVisible();
  await page.locator('#task').fill('Existing Cloud draft');
  await feedback.locator('textarea').fill('Explain this cell');
  await feedback.getByRole('checkbox').check();
  await feedback.locator('textarea').press('Enter');
  await expect(feedback).toBeHidden();
  await expect(page.locator('.composer .mention-chip')).toContainText('book1.xlsx');
  await expect(page.locator('#task')).toHaveValue('Existing Cloud draft');
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect.poll(() => cloud.postCount).toBe(1);
  const send = cloud.requests.find(request => request.method === 'POST' && request.path.endsWith('/commands'));
  const content = JSON.parse(send.body).command.content;
  const selection = JSON.parse(content.match(/<office_selection>([\s\S]*?)<\/office_selection>/)[1]);
  expect(selection.source.file).toBe('book1.xlsx');
  if (selection.source.reference?.file) expect(selection.source.reference.file).toBe('book1.xlsx');
  expect(selection.comment).toBe('Explain this cell');
  expect(content).toContain('Existing Cloud draft');
  expect(fileHostRequests(cloud)).toEqual([]);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('Cloud PDF text and region feedback reuse the current PDF surface, capture and image input', async ({ page }, testInfo) => {
  const cloud = new CloudFilesHarness(page);
  cloud.directories.set(`${sessionA}:`, [{ name: 'report.pdf', is_dir: false }]);
  cloud.contents.set(`${sessionA}:report.pdf`, { kind: 'binary_content', ...cloud.device.officeFiles['docs/report.pdf'] });
  await cloud.install();
  await page.route(`${cloudOrigin}/v1/sessions/${sessionA}/files/import`, async route => {
    const headers = { 'Access-Control-Allow-Origin': authOrigin, 'Access-Control-Allow-Headers': 'Authorization, Content-Type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
    if (route.request().method() === 'OPTIONS') return route.fulfill({ status: 204, headers });
    return route.fulfill({ headers, contentType: 'application/json', body: JSON.stringify({ path: '.openseek/attachments/fixture/capture.png' }) });
  });
  await cloud.goto(); await openFiles(page, cloud); await file(page, 'report.pdf').click();
  await expect(page.locator('#openseek-office-surface')).toHaveAttribute('data-pdf-painted', 'true');
  await expectFileValidation(page, sessionA, 'report.pdf', () => page.evaluate(session => window.cloudInvalidateFiles(session), sessionA));
  const text = page.locator('.textLayer [data-pdf-item]').first();
  await text.evaluate(element => {
    const range = document.createRange(); range.selectNodeContents(element);
    const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
    document.dispatchEvent(new Event('selectionchange'));
  });
  const feedback = page.locator('.office-selection-preview');
  await expect(feedback.locator('textarea')).toBeVisible();
  await feedback.locator('textarea').fill('Explain this passage');
  await feedback.getByRole('checkbox').check();
  await feedback.locator('textarea').press('Enter');
  await expect(feedback).toBeHidden();
  const bounds = await page.locator('.pdfViewer canvas').first().boundingBox();
  await page.getByRole('button', { name: 'Capture region', exact: true }).click();
  await expect(page.locator('.pdf-region-capture')).toBeVisible();
  await page.mouse.move(bounds.x + 30, bounds.y + 30); await page.mouse.down();
  await page.mouse.move(bounds.x + 210, bounds.y + 120, { steps: 8 }); await page.mouse.up();
  const capture = page.locator('.pdf-capture-feedback');
  await expect(capture.locator('textarea')).toBeVisible();
  await capture.locator('textarea').fill('Explain this region');
  await capture.getByRole('checkbox').check();
  await capture.locator('.agent-feedback-input-action').click();
  await expect(capture).toBeHidden();
  await expect(page.locator('.composer-image')).toHaveCount(1);
  await page.locator('#task').fill('Keep the PDF context');
  await page.screenshot({ path: testInfo.outputPath('cloud-pdf-capture.png'), fullPage: true });
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect.poll(() => cloud.postCount).toBe(1);
  const send = cloud.requests.find(request => request.method === 'POST' && request.path.endsWith('/commands'));
  const content = JSON.parse(send.body).command.content;
  expect(content[1]).toMatchObject({ type: 'image', media_type: 'image/png' });
  const selections = [...content[0].text.matchAll(/<office_selection>([\s\S]*?)<\/office_selection>/g)].map(match => JSON.parse(match[1]));
  expect(selections).toHaveLength(2);
  expect(selections.every(selection => selection.source.file === 'report.pdf')).toBe(true);
  const selectedText = selections.find(selection => selection.source.readable);
  expect(selectedText.source.reference.file).toBe('report.pdf');
  expect(content[0].text).toContain('Keep the PDF context');
  expect(fileHostRequests(cloud)).toEqual([]);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('Cloud file links and mentions reuse source previews and the composer envelope', async ({ page }) => {
  const cloud = new CloudFilesHarness(page);
  cloud.indexes.set(sessionA, ['src/index.html']);
  cloud.directories.set(`${sessionA}:`, [{ name: 'src', is_dir: true }, { name: '.git', is_dir: true }]);
  cloud.directories.set(`${sessionA}:src`, [{ name: 'index.html', is_dir: false }]);
  cloud.contents.set(`${sessionA}:src/index.html`, {
    kind: 'content', content: '<h1>Cloud source</h1>', sig: 'html', absolute: '/src/index.html',
  });
  cloud.histories.set(sessionA, { messages: [{
    task_id: 'initial', kind: 'assistant_message', created_at: 100,
    data: { content: '[Open HTML](src/index.html)\n\n```openseek-file\nsrc/index.html\n```' },
  }], generating: false });
  await cloud.install(); await cloud.goto(); await cloud.open();
  expect(cloud.fileRequests).toEqual([]);
  await page.getByRole('button', { name: 'Open HTML', exact: true }).click();
  await expect(source(page)).toContainText('<h1>Cloud source</h1>');
  await expect(source(page).locator('h1')).toHaveCount(0);
  await page.locator('.workspace-file-card').click();
  await expect(source(page)).toContainText('<h1>Cloud source</h1>');
  await expect(page.getByRole('button', { name: 'Attach files', exact: true })).toBeVisible();
  const input = page.locator('#task');
  const directories = () => cloud.fileRequests.filter(request => !request.content && !request.head && !request.index);
  const indexes = () => cloud.fileRequests.filter(request => request.index);
  const directoryReads = directories().length;
  await input.fill('@index');
  await expect(page.locator('.completion-item .completion-label')).toHaveText(['index.html']);
  await expect.poll(() => indexes().length).toBe(1);
  expect(directories()).toHaveLength(directoryReads);
  await input.fill('@src/index');
  await expect(page.locator('.completion-item .completion-label')).toHaveText(['index.html']);
  expect(indexes()).toHaveLength(1);
  await input.press('Enter');
  const chip = page.locator('.composer .mention-chip');
  await expect(chip).toContainText('index.html');
  await chip.locator('.mention-jump').click();
  await expect(source(page)).toContainText('<h1>Cloud source</h1>');
  await showTree(page);
  const directory = file(page, 'src');
  await expect(directory).toBeVisible();
  if (await directory.getAttribute('aria-expanded') !== 'true') await directory.click();
  await expect(file(page, 'index.html')).toBeVisible();
  expect(directories().map(request => request.path)).toEqual(expect.arrayContaining(['', 'src']));
  expect(indexes()).toHaveLength(1);
  await input.fill('Update the heading');
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect.poll(() => cloud.postCount).toBe(1);
  const request = cloud.requests.find(request => request.method === 'POST' && request.path.endsWith('/commands'));
  expect(JSON.parse(request.body).command.content).toBe('Update the heading\n\n<user_mentions>\n<file path="src/index.html"/>\n</user_mentions>');
  await expect(page.getByRole('button', { name: 'Send', exact: true })).toBeVisible();
  await input.press('ArrowUp');
  await expect(input).toHaveValue('Update the heading');
  await expect(chip).toContainText('index.html');
  await expect.poll(() => indexes().length).toBe(2);
  expect(fileHostRequests(cloud)).toEqual([]);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('Cloud browses nested text files through the existing read-only Files pane', async ({ page }, testInfo) => {
  const cloud = new CloudFilesHarness(page);
  await cloud.install(); await cloud.goto(); await openFiles(page, cloud);
  await expect(page.getByRole('tab', { name: 'Changes', exact: true })).toHaveCount(0);
  await expect(page.getByRole('tab', { name: 'Search', exact: true })).toHaveCount(1);
  await openText(page);
  expect(cloud.fileRequests.at(-1)).toMatchObject({ session: sessionA, path: 'src/hello #.mbt', content: true });
  expect(cloud.fileRequests.at(-1).headers.authorization).toBe('Bearer ts_fixture-123');
  await page.screenshot({ path: testInfo.outputPath('cloud-files.png'), fullPage: true });
  await showTree(page);
  cloud.contents.set(`${sessionA}:src/hello #.mbt`, { kind: 'content', content: '// Refreshed text', sig: 'new-sig', absolute: '/src/hello #.mbt' });
  let finishRefresh;
  cloud.holdRead = new Promise(resolve => { finishRefresh = resolve; });
  const previousReads = cloud.fileRequests.filter(request => request.content).length;
  await page.getByRole('tab', { name: 'Files', exact: true }).click();
  await expect.poll(() => cloud.fileRequests.filter(request => request.content).length).toBe(previousReads + 1);
  await expect(source(page)).toContainText('Cloud text');
  await expect(page.locator('.viewer-notice')).toBeHidden();
  finishRefresh(); cloud.holdRead = null;
  await expect(source(page)).toContainText('Refreshed text');
  expect(fileHostRequests(cloud)).toEqual([]);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('Search from Settings preserves the Cloud dock without importing Host tabs', async ({ page }) => {
  const cloud = new CloudFilesHarness(page);
  await cloud.install(); await cloud.goto();
  await page.getByRole('button', { name: 'Work', exact: true }).click();
  await cloud.device.openSession();
  await cloud.device.openQuickOpen();
  await page.locator('#quick-open-input').fill('main');
  await page.getByRole('option', { name: /main\.mbt/ }).click();
  await expect(page.locator('.editor-tab .tab-name')).toHaveText(['main.mbt']);
  await page.getByRole('button', { name: 'Hide panel', exact: true }).click();
  await page.getByRole('button', { name: 'Chat', exact: true }).click();
  await openFiles(page, cloud); await openText(page);
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Settings', exact: true })).toBeVisible();
  const shortcut = await page.evaluate(() =>
    navigator.platform.includes('Mac') ? 'Meta+Shift+F' : 'Control+Shift+F');
  await page.keyboard.press(shortcut);
  await cloud.open();
  const cloudTab = page.locator('.editor-tab').filter({ hasText: 'hello #.mbt' });
  await expect(cloudTab).toHaveCount(1);
  await expect(page.locator('.editor-tab').filter({ hasText: 'main.mbt' })).toHaveCount(0);
  await cloudTab.click();
  await expect(source(page)).toContainText('Cloud text');
  expect(cloud.device.pageErrors).toEqual([]);
});

test('Cloud keeps Office and PDF previews in existing tabs and unsupported binaries explicit', async ({ page }) => {
  const cloud = new CloudFilesHarness(page);
  const office = cloud.device.officeFiles;
  const names = ['report.docx', 'book1.xlsx', 'report.pdf', 'image.png', 'large.txt'];
  cloud.directories.set(`${sessionA}:`, names.map(name => ({ name, is_dir: false })));
  for (const name of names.slice(0, 3)) cloud.contents.set(`${sessionA}:${name}`, { kind: 'binary_content', ...office[`docs/${name}`] });
  cloud.contents.set(`${sessionA}:image.png`, { kind: 'binary_content', data_base64: 'AA==', media_type: 'image/png', sig: 'image' });
  cloud.contents.set(`${sessionA}:large.txt`, { kind: 'oversized' });
  await cloud.install(); await cloud.goto(); await cloud.open();
  await page.getByRole('button', { name: 'Show panel', exact: true }).click();
  await page.locator('.dock-launcher').getByRole('button', { name: /^Files / }).click();
  await file(page, 'report.docx').click();
  await expect(page.locator('.word-page')).toBeVisible();
  const wordPage = await page.locator('.word-page').elementHandle();
  const wordReads = cloud.fileRequests.filter(request => request.content && request.path === 'report.docx').length;
  await expectFileValidation(page, sessionA, 'report.docx', () => page.evaluate(session => window.cloudInvalidateFiles(session), sessionA));
  expect(await wordPage.evaluate(element => element.isConnected)).toBe(true);
  await cloud.open(sessionB);
  await expectFileValidation(page, sessionA, 'report.docx', () => cloud.open(sessionA));
  await expect(page.locator('.word-page')).toBeVisible();
  expect(cloud.fileRequests.filter(request => request.content && request.path === 'report.docx')).toHaveLength(wordReads);
  await expect(page.getByRole('button', { name: 'Annotate region', exact: true })).toBeDisabled();
  await showTree(page); await file(page, 'book1.xlsx').click();
  await expect(page.locator('.sheet-document table').first()).toBeVisible();
  await showTree(page); await file(page, 'report.pdf').click();
  await expect(page.locator('#openseek-office-surface')).toHaveAttribute('data-pdf-painted', 'true');
  const pdfCanvas = await page.locator('.pdfViewer canvas').first().elementHandle();
  const pdfReads = cloud.fileRequests.filter(request => request.content && request.path === 'report.pdf').length;
  await expectFileValidation(page, sessionA, 'report.pdf', () => page.evaluate(session => window.cloudInvalidateFiles(session), sessionA));
  expect(await pdfCanvas.evaluate(element => element.isConnected)).toBe(true);
  await cloud.open(sessionB);
  await expectFileValidation(page, sessionA, 'report.pdf', () => cloud.open(sessionA));
  await expect(page.locator('#openseek-office-surface')).toHaveAttribute('data-pdf-painted', 'true');
  expect(cloud.fileRequests.filter(request => request.content && request.path === 'report.pdf')).toHaveLength(pdfReads);
  await expect(page.getByRole('button', { name: 'Capture region', exact: true })).toBeEnabled();
  const bounds = await page.locator('.pdfViewer canvas').first().boundingBox();
  await page.getByRole('button', { name: 'Capture region', exact: true }).click();
  await expect(page.locator('.pdf-region-capture')).toBeVisible();
  await page.mouse.move(bounds.x + 30, bounds.y + 30); await page.mouse.down();
  await page.mouse.move(bounds.x + 210, bounds.y + 120, { steps: 8 }); await page.mouse.up();
  const capture = page.locator('.pdf-capture-feedback');
  await expect(capture.locator('textarea')).toBeVisible();
  await capture.locator('textarea').press('Escape');
  await expect(capture).toBeHidden();
  await showTree(page); await file(page, 'image.png').click();
  await expect(page.locator('.viewer-notice')).toBeVisible();
  await expect(page.locator('.viewer-notice')).toContainText(/binary/i);
  await file(page, 'large.txt').click();
  await expect(page.locator('.viewer-notice')).toContainText(/large/i);
  expect(fileHostRequests(cloud)).toEqual([]);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('a delayed Cloud read cannot replace a restored session after A to B to A navigation', async ({ page }) => {
  const cloud = new CloudFilesHarness(page);
  await cloud.install(); await cloud.goto(); await openFiles(page, cloud);
  let release;
  cloud.holdRead = new Promise(resolve => { release = resolve; });
  await file(page, 'src').click(); await file(page, 'hello #.mbt').click();
  await expect.poll(() => cloud.fileRequests.filter(request => request.content).length).toBe(1);
  await cloud.open(sessionB);
  cloud.holdRead = null;
  cloud.contents.set(`${sessionA}:src/hello #.mbt`, { kind: 'content', content: '// Current A text', sig: 'current', absolute: '/src/hello #.mbt' });
  await cloud.open(sessionA);
  await expect(source(page)).toContainText('Current A text');
  const oldResponse = page.waitForResponse(response => response.url().includes(`/v1/sessions/${sessionA}/files/content`));
  release();
  await (await oldResponse).finished();
  await expect(source(page)).not.toContainText('Cloud text');
  await expect(source(page)).toContainText('Current A text');
  expect(fileHostRequests(cloud)).toEqual([]);
});

test('generation completion refreshes Cloud directories and an open text preview', async ({ page }) => {
  const cloud = new CloudFilesHarness(page);
  await cloud.install(); await cloud.goto(); await openFiles(page, cloud); await openText(page);
  const previousReads = cloud.fileRequests.filter(request => request.content).length;
  cloud.contents.set(`${sessionA}:src/hello #.mbt`, { kind: 'content', content: '// Generated text', sig: 'generated', absolute: '/src/hello #.mbt' });
  cloud.directories.get(`${sessionA}:src`).push({ name: 'new.txt', is_dir: false });
  await page.locator('#task').fill('Update the example');
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect(source(page)).toContainText('Generated text');
  expect(cloud.fileRequests.filter(request => request.content).length).toBeGreaterThan(previousReads);
  await showTree(page); await expect(file(page, 'new.txt')).toBeVisible();
  expect(fileHostRequests(cloud)).toEqual([]);
});

test('blank Cloud drafts do not create sessions or expose files, while archived sessions remain readable', async ({ page }) => {
  const cloud = new CloudFilesHarness(page);
  cloud.archived.add(sessionB);
  await cloud.install(); await cloud.goto(); await cloud.create();
  await expect(page.getByRole('button', { name: 'Show panel', exact: true })).toHaveCount(0);
  expect(cloud.requests.filter(request => request.method === 'POST' && request.path === '/v1/sessions')).toEqual([]);
  expect(cloud.fileRequests).toEqual([]);
  const archived = page.getByRole('button', { name: /^Archived chats \(/ });
  if (await archived.getAttribute('aria-expanded') === 'false') await archived.click();
  await cloud.row(sessionB).click();
  await page.getByRole('button', { name: 'Show panel', exact: true }).click();
  await page.locator('.dock-launcher').getByRole('button', { name: /^Files / }).click();
  await openText(page);
  expect(cloud.fileRequests.at(-1).session).toBe(sessionB);
  await expect(page.locator('.archived-read-only')).toContainText('Read only');
  expect(fileHostRequests(cloud)).toEqual([]);
});


test('Cloud directory and file errors are visible and retry without Host fallback', async ({ page }) => {
  const cloud = new CloudFilesHarness(page);
  cloud.fileStatus = 403;
  await cloud.install(); await cloud.goto(); await cloud.open();
  await page.getByRole('button', { name: 'Show panel', exact: true }).click();
  await page.locator('.dock-launcher').getByRole('button', { name: /^Files / }).click();
  await expect(page.locator('.file-panel-error')).toContainText('HTTP 403');
  cloud.fileStatus = 200;
  await page.getByRole('tab', { name: 'Files', exact: true }).click();
  await file(page, 'src').click();
  await expect(file(page, 'hello #.mbt')).toBeVisible();
  cloud.fileStatus = 404;
  await file(page, 'hello #.mbt').click();
  await expect(page.locator('.viewer-notice')).toContainText('HTTP 404');
  await showTree(page);
  cloud.fileOffline = true;
  await file(page, 'hello #.mbt').click();
  await expect(page.locator('.viewer-notice')).toContainText('Cloud is unreachable');
  await showTree(page);
  cloud.fileOffline = false; cloud.fileStatus = 200;
  await file(page, 'hello #.mbt').click();
  await expect(source(page)).toContainText('Cloud text');
  expect(fileHostRequests(cloud)).toEqual([]);
});


test('changed Cloud oversized previews require a fresh explicit click for each unrestricted read', async ({ page }, testInfo) => {
  const cloud = new CloudFilesHarness(page);
  cloud.directories.set(`${sessionA}:`, [{ name: 'large.txt', is_dir: false }]);
  cloud.contents.set(`${sessionA}:large.txt`, { kind: 'oversized' });
  cloud.largePreviews.set(`${sessionA}:large.txt`, {
    kind: 'content', content: 'Explicitly requested large preview.', sig: 'large', absolute: '/large.txt',
  });
  await cloud.install(); await cloud.goto(); await cloud.open();
  await page.getByRole('button', { name: 'Show panel', exact: true }).click();
  await page.locator('.dock-launcher').getByRole('button', { name: /^Files / }).click();
  await file(page, 'large.txt').click();
  const preview = page.getByRole('button', { name: 'Preview anyway', exact: true });
  const reads = () => cloud.fileRequests.filter(request => request.content);
  await expect(page.locator('.viewer-notice')).toContainText('too large to preview');
  await expect(preview).toBeVisible();
  expect(reads().map(request => request.allowLarge)).toEqual([null]);
  await page.screenshot({ path: testInfo.outputPath('cloud-large-file.png'), fullPage: true });
  await preview.click();
  await expect(source(page)).toContainText('Explicitly requested large preview.');
  await expect(preview).toHaveCount(0);
  expect(reads().map(request => request.allowLarge)).toEqual([null, 'true']);
  await showTree(page);
  cloud.largePreviews.set(`${sessionA}:large.txt`, {
    kind: 'content', content: 'Explicitly requested changed large preview.', sig: 'large:2', absolute: '/large.txt',
  });
  await expectFileValidation(page, sessionA, 'large.txt', () => page.getByRole('tab', { name: 'Files', exact: true }).click(), 200);
  await expect(preview).toBeVisible();
  expect(reads().at(-1).allowLarge).toBeNull();
  await preview.click();
  await expect(source(page)).toContainText('Explicitly requested changed large preview.');
  cloud.largePreviews.set(`${sessionA}:large.txt`, {
    kind: 'content', content: 'Explicitly requested generated large preview.', sig: 'large:3', absolute: '/large.txt',
  });
  await page.locator('#task').fill('Update the file');
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect(preview).toBeVisible();
  expect(reads().at(-1).allowLarge).toBeNull();
  await preview.click();
  await expect(source(page)).toContainText('Explicitly requested generated large preview.');
  await page.locator('.editor-tab.active').getByRole('button', { name: 'Close', exact: true }).click();
  await page.getByRole('button', { name: 'Show panel', exact: true }).click();
  await page.locator('.dock-launcher').getByRole('button', { name: /^Files / }).click();
  await file(page, 'large.txt').click();
  await expect(preview).toBeVisible();
  expect(reads().at(-1).allowLarge).toBeNull();
  expect(fileHostRequests(cloud)).toEqual([]);
});

test('Host oversized notices keep their existing behavior without the Cloud override', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.directoryEntries['/workspace'] = [{ name: 'large.txt', is_dir: false }];
  const original = app.replyFor.bind(app);
  app.replyFor = request => request.method === 'fs.read_file'
    ? { kind: 'oversized' } : original(request);
  await app.install(); await app.goto(); await app.openSession();
  await app.openReview({ waitForHistory: false });
  await page.getByRole('tab', { name: 'Files', exact: true }).click();
  await file(page, 'large.txt').click();
  await expect(page.locator('.viewer-notice')).toContainText('too large to preview');
  await expect(page.getByRole('button', { name: 'Preview anyway', exact: true })).toHaveCount(0);
});


test('Cloud file reads show loading instead of the unselected placeholder', async ({ page }, testInfo) => {
  const cloud = new CloudFilesHarness(page);
  cloud.directories.set(`${sessionA}:`, [{ name: 'large.txt', is_dir: false }]);
  cloud.contents.set(`${sessionA}:large.txt`, { kind: 'oversized' });
  cloud.largePreviews.set(`${sessionA}:large.txt`, { kind: 'content', content: 'Large preview ready.', sig: 'large', absolute: '/large.txt' });
  await cloud.install(); await cloud.goto(); await cloud.open();
  await page.getByRole('button', { name: 'Show panel', exact: true }).click();
  await page.locator('.dock-launcher').getByRole('button', { name: /^Files / }).click();
  let release;
  cloud.holdRead = new Promise(resolve => { release = resolve; });
  await file(page, 'large.txt').click();
  await expect(page.locator('.viewer-notice')).toHaveText('Loading file…');
  await page.locator('.editor').screenshot({ path: testInfo.outputPath('cloud-file-loading.png') });
  release(); cloud.holdRead = null;
  const preview = page.getByRole('button', { name: 'Preview anyway', exact: true });
  await expect(preview).toBeVisible();
  cloud.holdRead = new Promise(resolve => { release = resolve; });
  await showTree(page); await file(page, 'large.txt').click();
  await expect(page.locator('.viewer-notice')).toHaveText('Loading file…');
  release(); cloud.holdRead = null;
  await expect(preview).toBeVisible();
  cloud.holdRead = new Promise(resolve => { release = resolve; });
  await page.getByRole('tab', { name: 'Files', exact: true }).click();
  await expect(page.locator('.viewer-notice')).toHaveText('Loading file…');
  release(); cloud.holdRead = null;
  await expect(preview).toBeVisible();
  cloud.holdRead = new Promise(resolve => { release = resolve; });
  await preview.click();
  await expect(page.locator('.viewer-notice')).toHaveText('Loading file…');
  await expect(preview).toHaveCount(0);
  release(); cloud.holdRead = null;
  await expect(source(page)).toContainText('Large preview ready.');
  expect(cloud.device.pageErrors).toEqual([]);
});

test('Cloud open text and explicitly allowed large previews survive session switches with reading position', async ({ page }, testInfo) => {
  const cloud = new CloudFilesHarness(page);
  cloud.directories.set(`${sessionA}:`, [{ name: 'saved.txt', is_dir: false }, { name: 'large.txt', is_dir: false }]);
  const text = Array.from({ length: 300 }, (_, i) => `Cloud cache line ${i}`).join('\n') + '\nCLOUD_CACHE_END';
  cloud.contents.set(`${sessionA}:saved.txt`, { kind: 'content', content: text, sig: 'saved', absolute: '/saved.txt' });
  cloud.contents.set(`${sessionA}:large.txt`, { kind: 'oversized' });
  cloud.largePreviews.set(`${sessionA}:large.txt`, { kind: 'content', content: text, sig: 'large', absolute: '/large.txt' });
  await cloud.install(); await cloud.goto(); await cloud.open();
  await page.getByRole('button', { name: 'Show panel', exact: true }).click();
  await page.locator('.dock-launcher').getByRole('button', { name: /^Files / }).click();
  for (const name of ['saved.txt', 'large.txt']) {
    await showTree(page);
    await file(page, name).click();
    if (name === 'large.txt') await page.getByRole('button', { name: 'Preview anyway', exact: true }).click();
    await expect(source(page)).toContainText('Cloud cache line 0');
    await source(page).getByRole('region').hover();
    await page.mouse.wheel(0, 100000);
    await expect(source(page).getByText('CLOUD_CACHE_END', { exact: true })).toBeVisible();
    const reads = cloud.fileRequests.filter(request => request.content).length;
    await cloud.open(sessionB);
    await expectFileValidation(page, sessionA, name, () => cloud.open(sessionA));
    await expect(source(page).getByText('CLOUD_CACHE_END', { exact: true })).toBeVisible();
    expect(cloud.fileRequests.filter(request => request.content)).toHaveLength(reads);
    await expectFileValidation(page, sessionA, name, () => page.evaluate(session => window.cloudInvalidateFiles(session), sessionA));
    await expect(source(page).getByText('CLOUD_CACHE_END', { exact: true })).toBeVisible();
    expect(cloud.fileRequests.filter(request => request.content)).toHaveLength(reads);
  }
  await page.locator('.editor').screenshot({ path: testInfo.outputPath('cloud-cached-large-restored.png') });
  await page.locator('.editor-tab.active').getByRole('button', { name: 'Close', exact: true }).click();
  await showTree(page);
  await file(page, 'large.txt').click();
  await expect(page.getByRole('button', { name: 'Preview anyway', exact: true })).toBeVisible();
  expect(cloud.fileRequests.filter(request => request.content).at(-1).allowLarge).toBeNull();
  expect(fileHostRequests(cloud)).toEqual([]);
});

test('changed oversized Cloud caches return to the size limit after a session switch', async ({ page }) => {
  const cloud = new CloudFilesHarness(page);
  cloud.directories.set(`${sessionA}:`, [{ name: 'large.txt', is_dir: false }]);
  cloud.contents.set(`${sessionA}:large.txt`, { kind: 'oversized' });
  cloud.largePreviews.set(`${sessionA}:large.txt`, { kind: 'content', content: 'Previously approved large body.', sig: 'large:1', absolute: '/large.txt' });
  await cloud.install(); await cloud.goto(); await openFiles(page, cloud);
  await file(page, 'large.txt').click();
  const preview = page.getByRole('button', { name: 'Preview anyway', exact: true });
  await preview.click();
  await expect(source(page)).toContainText('Previously approved large body.');
  await cloud.open(sessionB);
  cloud.largePreviews.set(`${sessionA}:large.txt`, { kind: 'content', content: 'Changed large body needs new approval.', sig: 'large:2', absolute: '/large.txt' });
  await expectFileValidation(page, sessionA, 'large.txt', () => cloud.open(sessionA), 200);
  await expect(preview).toBeVisible();
  await expect(source(page)).not.toContainText('Changed large body needs new approval.');
  const reads = () => cloud.fileRequests.filter(request => request.content && request.path === 'large.txt');
  expect(reads().map(request => request.allowLarge)).toEqual([null, 'true', null]);
  await preview.click();
  await expect(source(page)).toContainText('Changed large body needs new approval.');
  expect(reads().map(request => request.allowLarge)).toEqual([null, 'true', null, 'true']);
  expect(fileHostRequests(cloud)).toEqual([]);
});

test('a delayed Cloud validator cannot reload a restored session after a newer read', async ({ page }) => {
  const cloud = new CloudFilesHarness(page);
  await cloud.install(); await cloud.goto(); await openFiles(page, cloud); await openText(page);
  const path = 'src/hello #.mbt';
  cloud.contents.set(`${sessionA}:${path}`, { kind: 'content', content: '// Superseded A text', sig: 'superseded', absolute: `/${path}` });
  let release;
  cloud.holdHead = new Promise(resolve => { release = resolve; });
  await page.evaluate(session => window.cloudInvalidateFiles(session), sessionA);
  await expect.poll(() => cloud.fileRequests.filter(request => request.head).length).toBe(1);
  await cloud.open(sessionB);
  cloud.holdHead = null;
  await page.locator('.dock-launcher').getByRole('button', { name: /^Files / }).click();
  await openText(page);
  await expect(source(page)).toContainText(`// ${sessionB}`);
  cloud.contents.set(`${sessionA}:${path}`, { kind: 'content', content: '// Current A text', sig: 'current', absolute: `/${path}` });
  await expectFileValidation(page, sessionA, path, () => cloud.open(sessionA), 200);
  await expect(source(page)).toContainText('Current A text');
  const reads = cloud.fileRequests.filter(request => request.content).length;
  const oldResponse = page.waitForResponse(response => response.request().method() === 'HEAD' && response.url().includes(`/v1/sessions/${sessionA}/files/content`));
  release();
  await oldResponse;
  await expect(source(page)).toContainText('Current A text');
  await expect(source(page)).not.toContainText('Superseded A text');
  expect(cloud.fileRequests.filter(request => request.content)).toHaveLength(reads);
  expect(fileHostRequests(cloud)).toEqual([]);
});

test('a Cloud generation finishing off screen invalidates only its parked file content', async ({ page }) => {
  const cloud = new CloudFilesHarness(page);
  await cloud.install(); await cloud.goto(); await openFiles(page, cloud); await openText(page);
  let finish;
  cloud.pauseStream = new Promise(resolve => { finish = resolve; });
  await page.locator('#task').fill('Update this file in the background');
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect(page.locator('#transcript').getByText('Update this file in the background', { exact: true })).toBeVisible();
  await cloud.open(sessionB);
  cloud.contents.set(`${sessionA}:src/hello #.mbt`, { kind: 'content', content: '// Background generation finished', sig: 'finished', absolute: '/src/hello #.mbt' });
  const before = cloud.fileRequests.filter(request => request.content).length;
  finish();
  await expect.poll(() => cloud.requests.filter(request => request.method === 'GET' && request.path === `/v1/sessions/${sessionA}/messages`).length).toBeGreaterThan(1);
  expect(cloud.fileRequests.filter(request => request.content)).toHaveLength(before);
  await cloud.open(sessionA);
  await expect(source(page)).toContainText('Background generation finished');
  expect(cloud.fileRequests.filter(request => request.content).at(-1).allowLarge).toBeNull();
});

test('Cloud text search reuses options, results, keyboard tabs and positioned file opens', async ({ page }, testInfo) => {
  const cloud = new CloudFilesHarness(page);
  cloud.contents.set(`${sessionA}:src/hello #.mbt`, { kind: 'content', content: 'fn hello {\n  // moon moon\n}', sig: 'search', absolute: '/src/hello #.mbt' });
  const searches = [];
  await cloud.install();
  await page.route(`${cloudOrigin}/v1/sessions/*/files/search`, async route => {
    const headers = { 'Access-Control-Allow-Origin': authOrigin, 'Access-Control-Allow-Headers': 'Authorization, Content-Type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
    if (route.request().method() === 'OPTIONS') return route.fulfill({ status: 204, headers });
    const body = route.request().postDataJSON(); searches.push(body);
    if (body.query === '[') return route.fulfill({ headers, contentType: 'application/json', body: JSON.stringify({ generation: body.generation, matches: [], match_count: 0, file_count: 0, limit_hit: false, cancelled: false, error_code: 'invalid_regex', error_message: 'regex parse error: unclosed character class' }) });
    return route.fulfill({ headers, contentType: 'application/json', body: JSON.stringify({ generation: body.generation, matches: [{ path: 'src/hello #.mbt', line_number: 2, preview: '  // moon moon', preview_start_column: 1, ranges: [{ start_column: 6, end_column: 10 }, { start_column: 11, end_column: 15 }] }], match_count: 2, file_count: 1, limit_hit: false, cancelled: false }) });
  });
  await cloud.goto(); await openFiles(page, cloud);
  const filesTab = page.getByRole('tab', { name: 'Files', exact: true });
  await filesTab.focus(); await page.keyboard.press('ArrowRight');
  const searchTab = page.getByRole('tab', { name: 'Search', exact: true });
  await expect(searchTab).toHaveAttribute('aria-selected', 'true');
  await expect(page.getByRole('tab', { name: 'Changes', exact: true })).toHaveCount(0);
  const search = page.locator('.workspace-search');
  await expect(search.getByRole('button', { name: 'Code search', exact: true })).toHaveCount(1);
  await search.getByTitle('Match Case', { exact: true }).click();
  await search.getByTitle('Match Whole Word', { exact: true }).click();
  await search.getByTitle('Use Regular Expression', { exact: true }).click();
  await search.getByTitle('Toggle Search Details', { exact: true }).click();
  await search.getByRole('textbox', { name: 'files to include', exact: true }).fill('src/**/*.mbt');
  await search.getByRole('textbox', { name: 'files to exclude', exact: true }).fill('**/*_test.mbt');
  const query = search.getByRole('textbox', { name: 'Search', exact: true });
  await query.fill('['); await query.press('Enter');
  await expect(search.getByRole('alert')).toContainText('regex parse error: unclosed character class');
  await query.fill('moon'); await query.press('Enter');
  await expect(search.locator('.search-summary')).toHaveText('2 matches in 1 file');
  await expect(search.getByRole('alert')).toHaveCount(0);
  expect(searches.at(-1)).toMatchObject({ query: 'moon', case_sensitive: true, whole_word: true, regex: true, include_glob: 'src/**/*.mbt', exclude_glob: '**/*_test.mbt' });
  expect(Object.keys(searches.at(-1)).sort()).toEqual(['query', 'case_sensitive', 'whole_word', 'regex', 'include_glob', 'exclude_glob', 'generation', 'max_results'].sort());
  await expect(search.locator('.search-match-highlight')).toHaveText(['moon', 'moon']);
  await page.screenshot({ path: testInfo.outputPath('cloud-search.png'), fullPage: true });
  await search.locator('.search-result-row').getByRole('button', { name: /moon moon/ }).click();
  await expect(source(page)).toContainText('moon moon');
  expect(cloud.fileRequests.some(request => request.content && request.path === 'src/hello #.mbt')).toBe(true);
  expect(fileHostRequests(cloud)).toEqual([]);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('Cloud file events refresh the visible preview, keep other tabs lazy, and reconnect without read-epoch churn', async ({ page }) => {
  const cloud = new CloudFilesHarness(page);
  cloud.directories.get(`${sessionA}:`).push({ name: 'background.txt', is_dir: false });
  cloud.contents.set(`${sessionA}:background.txt`, { kind: 'content', content: 'Old background', sig: 'old', absolute: '/background.txt' });
  await cloud.install(); await cloud.goto(); await openFiles(page, cloud); await openText(page);
  await showTree(page); await file(page, 'background.txt').click();
  await expect(source(page)).toContainText('Old background');
  await showTree(page); await file(page, 'hello #.mbt').click();
  await expect(source(page)).toContainText('Cloud text');
  const connections = () => cloud.requests.filter(request => request.path.endsWith('/files/events'));
  await expect.poll(() => connections().length).toBe(1);
  const backgroundReads = cloud.fileRequests.filter(request => request.content && request.path === 'background.txt').length;
  cloud.contents.set(`${sessionA}:src/hello #.mbt`, { kind: 'content', content: 'Changed visible', sig: 'new', absolute: '/src/hello #.mbt' });
  cloud.contents.set(`${sessionA}:background.txt`, { kind: 'content', content: 'Changed background', sig: 'new', absolute: '/background.txt' });
  await page.evaluate(session => window.cloudInvalidateFiles(session), sessionA);
  await expect(source(page)).toContainText('Changed visible');
  expect(cloud.fileRequests.filter(request => request.content && request.path === 'background.txt')).toHaveLength(backgroundReads);
  expect(connections()).toHaveLength(1);
  await showTree(page); await file(page, 'background.txt').click();
  await expect(source(page)).toContainText('Changed background');
  expect(cloud.fileRequests.filter(request => request.content && request.path === 'background.txt')).toHaveLength(backgroundReads + 1);
  await page.evaluate(session => window.cloudCloseFileEvents(session), sessionA);
  await expect.poll(() => connections().length).toBe(2);
  await expect(source(page)).toContainText('Changed background');
  await cloud.open(sessionB);
  await expect.poll(() => cloud.fileStreamCancellations).toBe(1);
  const reads = cloud.fileRequests.length;
  await page.evaluate(session => window.cloudInvalidateFiles(session), sessionA);
  expect(cloud.fileRequests).toHaveLength(reads);
  expect(fileHostRequests(cloud)).toEqual([]);
  expect(cloud.device.pageErrors).toEqual([]);
});

for (const [status, message] of [[401, 'Your account sign-in expired'], [404, 'HTTP 404']]) {
  test(`Cloud cached preview validation shows HTTP ${status} without reading another body`, async ({ page }) => {
    const cloud = new CloudFilesHarness(page);
    await cloud.install(); await cloud.goto(); await openFiles(page, cloud); await openText(page);
    const reads = cloud.fileRequests.filter(request => request.content).length;
    cloud.fileStatus = status;
    await expectFileValidation(page, sessionA, 'src/hello #.mbt', () => page.evaluate(session => window.cloudInvalidateFiles(session), sessionA), status);
    await showTree(page);
    await expect(page.locator('.file-panel-error')).toContainText(message);
    expect(cloud.fileRequests.filter(request => request.content)).toHaveLength(reads);
    expect(fileHostRequests(cloud)).toEqual([]);
    expect(cloud.device.pageErrors).toEqual([]);
  });
}

test('Cloud validation handles bodyless browser HEAD responses for changed and unchanged content', async ({ page }) => {
  const cloud = new CloudFilesHarness(page);
  await cloud.install();
  await page.addInitScript(() => {
    const original = window.fetch;
    window.fetch = async (...args) => {
      const response = await original(...args);
      // Route interception can supply a stream for HEAD. Browser fetch uses
      // null for its body; exercise that contract without adding any content.
      return args[1]?.method === 'HEAD'
        ? new Response(null, { status: response.status, headers: response.headers })
        : response;
    };
  });
  await cloud.goto(); await openFiles(page, cloud); await openText(page);
  const reads = cloud.fileRequests.filter(request => request.content).length;
  cloud.contents.set(`${sessionA}:src/hello #.mbt`, { kind: 'content', content: 'Bodyless HEAD changed', sig: 'changed', absolute: '/src/hello #.mbt' });
  await expectFileValidation(page, sessionA, 'src/hello #.mbt', () => page.evaluate(session => window.cloudInvalidateFiles(session), sessionA), 200);
  await expect(source(page)).toContainText('Bodyless HEAD changed');
  await expectFileValidation(page, sessionA, 'src/hello #.mbt', () => page.evaluate(session => window.cloudInvalidateFiles(session), sessionA));
  await expect(source(page)).toContainText('Bodyless HEAD changed');
  expect(cloud.fileRequests.filter(request => request.content)).toHaveLength(reads + 1);
  expect(cloud.device.pageErrors).toEqual([]);
  expect(await page.evaluate(() => window.cloudUnhandledRejections)).toEqual([]);
});


test('Cloud code search streams shared results, navigates ranges, and cancels an obsolete query', async ({ page }, testInfo) => {
  const cloud = new CloudFilesHarness(page);
  cloud.contents.set(`${sessionA}:src/hello #.mbt`, { kind: 'content', content: 'fn hello {\n  inspect(1)\n}', sig: 'semantic', absolute: '/src/hello #.mbt' });
  const requests = [];
  let resume;
  cloud.eventPauses = new Map([[0, new Promise(resolve => { resume = resolve; })]]);
  await cloud.install();
  await page.route(`${cloudOrigin}/v1/sessions/*/files/search/semantic`, async route => {
    const headers = { 'Access-Control-Allow-Origin': authOrigin, 'Access-Control-Allow-Headers': 'Authorization, Content-Type', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Access-Control-Expose-Headers': 'x-fixture-event-boundaries' };
    if (route.request().method() === 'OPTIONS') return route.fulfill({ status: 204, headers });
    const request = route.request();
    const body = request.postDataJSON();
    requests.push({ body, headers: await request.allHeaders() });
    const hit = { path: 'src/hello #.mbt', rule_id: body.patterns[0], start_line: 2, start_column: 3, end_line: 2, end_column: 13, matched_source: body.patterns[0] === 'inspect($_)' ? 'inspect(1)' : 'inspect(2)', source_context: [] };
    const progress = `event: progress\ndata: ${JSON.stringify({ generation: body.generation, matches: [hit], match_count: 1, file_count: 1 })}\n\n`;
    const result = `event: result\ndata: ${JSON.stringify({ generation: body.generation, matches: [hit], match_count: 1, file_count: 1, limit_hit: false, cancelled: false, partial: false })}\n\n`;
    return route.fulfill({ headers: { ...headers, 'x-fixture-event-boundaries': JSON.stringify([Buffer.byteLength(progress)]) }, contentType: 'text/event-stream', body: progress + result });
  });
  try {
    await cloud.goto(); await openFiles(page, cloud);
    await page.getByRole('tab', { name: 'Search', exact: true }).click();
    const search = page.locator('.workspace-search');
    await search.getByRole('button', { name: 'Code search', exact: true }).click();
    const pattern = search.getByRole('textbox', { name: 'pattern', exact: true });
    await pattern.fill('inspect($_)'); await pattern.press('Enter');
    await expect(search.locator('.search-result-row')).toContainText('inspect(1)');
    await expect(search.locator('.search-summary')).toHaveText('1 match in 1 file so far…');
    expect(requests.at(-1).headers.authorization).toBe('Bearer ts_fixture-123');
    expect(Object.keys(requests.at(-1).body).sort()).toEqual(['patterns', 'include_glob', 'exclude_glob', 'generation', 'max_results'].sort());
    const cancelled = cloud.streamCancellations;
    await pattern.fill('inspect(2)'); await pattern.press('Enter');
    await expect.poll(() => cloud.streamCancellations).toBeGreaterThan(cancelled);
    await expect(search.locator('.search-result-row')).toContainText('inspect(2)');
    resume();
    await expect(search.locator('.search-result-row')).not.toContainText('inspect(1)');
    await expect(search.locator('.search-summary')).toHaveText('1 match in 1 file');
    await page.screenshot({ path: testInfo.outputPath('cloud-code-search.png'), animations: 'disabled' });
    await search.locator('.search-result-row').getByRole('button').click();
    await expect(source(page)).toContainText('inspect(1)');
    expect(fileHostRequests(cloud)).toEqual([]);
    expect(cloud.device.pageErrors).toEqual([]);
    expect(await page.evaluate(() => window.cloudUnhandledRejections)).toEqual([]);
  } finally { resume(); }
});

const semanticHeaders = { 'Access-Control-Allow-Origin': authOrigin, 'Access-Control-Allow-Headers': 'Authorization, Content-Type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const semanticHit = (index = 0, pattern = 'inspect($_)') => ({
  path: 'src/hello #.mbt', rule_id: pattern, start_line: index + 1, start_column: 1,
  end_line: index + 1, end_column: 11, matched_source: 'inspect(1)', source_context: [],
});

async function openCloudCodeSearch(page, cloud, pattern = 'inspect($_)') {
  await cloud.goto(); await openFiles(page, cloud);
  await page.getByRole('tab', { name: 'Search', exact: true }).click();
  await page.getByRole('button', { name: 'Code search', exact: true }).click();
  const input = page.getByRole('textbox', { name: 'pattern', exact: true });
  await input.fill(pattern); await input.press('Enter');
  return input;
}

test('Cloud cancels a search waiting for response headers without cancelling its replacement', async ({ page }) => {
  const cloud = new CloudFilesHarness(page);
  let release;
  const held = new Promise(resolve => { release = resolve; });
  const searches = [];
  const failed = [];
  page.on('requestfailed', request => { if (request.url().endsWith('/files/search/semantic')) failed.push(request); });
  await cloud.install();
  await page.route(`${cloudOrigin}/v1/sessions/*/files/search/semantic`, async route => {
    if (route.request().method() === 'OPTIONS') return route.fulfill({ status: 204, headers: semanticHeaders });
    const body = route.request().postDataJSON();
    searches.push(body);
    if (body.patterns[0] === 'held') await held;
    const reply = { generation: body.generation, matches: [semanticHit(0, body.patterns[0])], match_count: 1, file_count: 1, limit_hit: false, cancelled: false, partial: false };
    return route.fulfill({ headers: semanticHeaders, contentType: 'text/event-stream', body: `event: result\ndata: ${JSON.stringify(reply)}\n\n` });
  });
  try {
    const pattern = await openCloudCodeSearch(page, cloud, 'held');
    await expect.poll(() => searches.length).toBeGreaterThan(0);
    await pattern.fill('replacement'); await pattern.press('Enter');
    await expect.poll(() => failed.length).toBeGreaterThan(0);
    await expect(page.locator('.search-semantic-pattern')).toHaveText('replacement');
    release();
    await expect(page.locator('.search-summary')).toHaveText('1 match in 1 file');
    expect(cloud.device.pageErrors).toEqual([]);
    expect(await page.evaluate(() => window.cloudUnhandledRejections)).toEqual([]);
  } finally { release(); }
});

test('Cloud preserves partial semantic results and reports an unfinished stream as a failure', async ({ page }) => {
  const cloud = new CloudFilesHarness(page);
  await cloud.install();
  await page.route(`${cloudOrigin}/v1/sessions/*/files/search/semantic`, async route => {
    if (route.request().method() === 'OPTIONS') return route.fulfill({ status: 204, headers: semanticHeaders });
    const body = route.request().postDataJSON();
    const data = { generation: body.generation, matches: [semanticHit()], match_count: 1, file_count: 1 };
    const result = { ...data, limit_hit: true, cancelled: false, partial: true, error_code: 'tool_failed', error_message: 'Fixture scan stopped early' };
    return route.fulfill({ headers: semanticHeaders, contentType: 'text/event-stream', body: body.patterns[0] === 'unfinished'
      ? `event: progress\ndata: ${JSON.stringify(data)}\n\n`
      : `event: result\ndata: ${JSON.stringify(result)}\n\n` });
  });
  const pattern = await openCloudCodeSearch(page, cloud, 'partial');
  await expect(page.getByRole('alert')).toContainText('Fixture scan stopped early');
  await expect(page.locator('.search-result-row')).toContainText('inspect(1)');
  await expect(page.locator('.search-truncated')).toHaveCount(2);
  await pattern.fill('unfinished'); await pattern.press('Enter');
  await expect(page.getByRole('alert')).toContainText('Cloud returned an invalid response. Try again.');
  await expect(page.locator('.search-result-row')).toHaveCount(0);
  expect(cloud.device.pageErrors).toEqual([]);
});

for (const count of [1, 101]) {
  test(`Cloud sends a ${count}-match selection through the shared composer and materializes only large selections`, async ({ page }) => {
    const cloud = new CloudFilesHarness(page);
    const materializations = [];
    cloud.streamChunkSize = 512;
    let fail = count > 100;
    await cloud.install();
    await page.route(`${cloudOrigin}/v1/sessions/*/files/search/semantic`, async route => {
      if (route.request().method() === 'OPTIONS') return route.fulfill({ status: 204, headers: semanticHeaders });
      const body = route.request().postDataJSON();
      const result = { generation: body.generation, matches: Array.from({ length: count }, (_, index) => semanticHit(index)), match_count: count, file_count: 1, limit_hit: false, cancelled: false, partial: false };
      return route.fulfill({ headers: semanticHeaders, contentType: 'text/event-stream', body: `event: result\ndata: ${JSON.stringify(result)}\n\n` });
    });
    await page.route(`${cloudOrigin}/v1/sessions/*/files/search/semantic/selection`, async route => {
      if (route.request().method() === 'OPTIONS') return route.fulfill({ status: 204, headers: semanticHeaders });
      materializations.push({ body: route.request().postDataJSON(), headers: await route.request().allHeaders() });
      return route.fulfill({ status: fail ? 500 : 200, headers: semanticHeaders, contentType: 'application/json', body: JSON.stringify({ path: '.openseek/agent-context/semantic-search/selection.jsonl', match_count: count, file_count: 1 }) });
    });
    await openCloudCodeSearch(page, cloud);
    await page.getByLabel('Select pattern', { exact: true }).click();
    const chip = page.locator('.composer .mention-chip');
    await expect(chip).toContainText(`${count} matches`);
    expect(materializations).toHaveLength(0);
    await chip.getByTitle(`Open semantic search with ${count} matches`, { exact: true }).click();
    await expect(page.getByRole('button', { name: 'Show all', exact: true })).toBeVisible();
    await page.locator('#task').fill('Explain these matches');
    await page.getByRole('button', { name: 'Send', exact: true }).click();
    if (fail) {
      await expect(page.getByText('Cloud answered HTTP 500. Try again.', { exact: true })).toBeVisible();
      await expect(page.locator('#task')).toHaveValue('Explain these matches');
      expect(cloud.postCount).toBe(0);
      fail = false;
      await expect(page.getByRole('button', { name: 'Send', exact: true })).toBeEnabled();
      await page.getByRole('button', { name: 'Send', exact: true }).click();
    }
    await expect.poll(() => cloud.postCount).toBe(1);
    const sent = JSON.parse(cloud.requests.find(request => request.method === 'POST' && request.path.endsWith('/commands')).body).command.content;
    expect(sent).toContain('Explain these matches');
    if (count > 100) {
      expect(materializations).toHaveLength(2);
      expect(materializations[1].body).toEqual(materializations[0].body);
      expect(materializations[0].headers.authorization).toBe('Bearer ts_fixture-123');
      expect(Object.keys(materializations[0].body).sort()).toEqual(['artifact_id', 'patterns', 'include_glob', 'exclude_glob', 'matches'].sort());
      expect(materializations[0].body.matches).toHaveLength(count);
      expect(sent).toContain('<semantic_search_file path=".openseek/agent-context/semantic-search/selection.jsonl"');
      expect(sent).not.toContain('matched_source');
    } else {
      expect(materializations).toHaveLength(0);
      expect(sent).toContain('<semantic_search');
      expect(sent).toContain('root="."');
      expect(sent).not.toContain('root="/"');
      expect(sent).toContain('inspect(1)');
    }
    expect(fileHostRequests(cloud)).toEqual([]);
    expect(cloud.device.pageErrors).toEqual([]);
    expect(await page.evaluate(() => window.cloudUnhandledRejections)).toEqual([]);
  });
}

test('Cloud pattern repair uses server defaults and applies only a validated candidate', async ({ page }, testInfo) => {
  const cloud = new CloudFilesHarness(page);
  const repairs = [];
  let passed = false;
  await cloud.install();
  await page.route(`${cloudOrigin}/v1/sessions/*/files/search/semantic`, async route => {
    if (route.request().method() === 'OPTIONS') return route.fulfill({ status: 204, headers: semanticHeaders });
    const body = route.request().postDataJSON();
    const result = { generation: body.generation, matches: [], match_count: 0, file_count: 0, limit_hit: false, cancelled: false, partial: false, ...(body.patterns[0] === 'broken' ? { error_code: 'invalid_pattern', error_message: 'Invalid pattern' } : {}) };
    return route.fulfill({ headers: semanticHeaders, contentType: 'text/event-stream', body: `event: result\ndata: ${JSON.stringify(result)}\n\n` });
  });
  await page.route(`${cloudOrigin}/v1/sessions/*/files/search/semantic/repair`, async route => {
    if (route.request().method() === 'OPTIONS') return route.fulfill({ status: 204, headers: semanticHeaders });
    const body = route.request().postDataJSON();
    repairs.push({ body, headers: await route.request().allHeaders() });
    return route.fulfill({ headers: semanticHeaders, contentType: 'application/json', body: JSON.stringify({ generation: body.generation, validation_status: passed ? 'passed' : 'failed', candidate_pattern: 'inspect($_)', message: passed ? 'Validated candidate' : 'Candidate rejected by syntax validation', trace: ['Fixture repair trace'] }) });
  });
  const pattern = await openCloudCodeSearch(page, cloud, 'broken');
  const fix = page.locator('.pattern-repair-button');
  await fix.click();
  await expect(page.locator('.search-pattern-repair-candidate-value')).toHaveText('inspect($_)');
  await expect(pattern).toHaveValue('broken');
  await expect(page.locator('.search-pattern-repair-trace')).toContainText('Fixture repair trace');
  expect(Object.keys(repairs[0].body).sort()).toEqual(['generation', 'pattern']);
  expect(repairs[0].headers.authorization).toBe('Bearer ts_fixture-123');
  await page.getByText('Show repair details', { exact: true }).click();
  await page.screenshot({ path: testInfo.outputPath('cloud-pattern-repair.png'), animations: 'disabled' });
  passed = true;
  await fix.click();
  await expect(pattern).toHaveValue('inspect($_)');
  await expect(page.locator('.search-pattern-repair-candidate-value')).toHaveCount(0);
  expect(fileHostRequests(cloud)).toEqual([]);
  expect(cloud.device.pageErrors).toEqual([]);
  expect(await page.evaluate(() => window.cloudUnhandledRejections)).toEqual([]);
});


for (const unchanged of [true, false]) {
  test(`Cloud download ${unchanged ? 'reuses unchanged original text bytes' : 'fetches changed original bytes'}`, async ({ page }) => {
    const cloud = new CloudFilesHarness(page);
    const original = '\uFEFFfirst\r\n月\r\n';
    const raw = Buffer.from([0xff, 0, 0x80, 13, 10]);
    const key = `${sessionA}:src/hello #.mbt`;
    cloud.contents.set(key, { kind: 'content', content: original, sig: 'v1', absolute: '/src/hello #.mbt' });
    cloud.downloads.set(key, raw);
    await cloud.install(); await cloud.goto(); await openFiles(page, cloud);
    await file(page, 'src').click(); await file(page, 'hello #.mbt').click();
    await expect(source(page)).toContainText('first');
    if (!unchanged) cloud.contents.set(key, { kind: 'content', content: 'changed', sig: 'v2', absolute: '/src/hello #.mbt' });
    const before = cloud.fileRequests.length;
    const transfer = page.waitForEvent('download');
    await page.getByRole('button', { name: 'Download to local', exact: true }).click();
    const download = await transfer;
    expect(download.suggestedFilename()).toBe('hello #.mbt');
    expect(readFileSync(await download.path())).toEqual(unchanged ? Buffer.from(original) : raw);
    const requests = cloud.fileRequests.slice(before);
    expect(requests.filter(r => r.head)).toHaveLength(1);
    expect(requests.find(r => r.head).status).toBe(unchanged ? 304 : 200);
    expect(requests.filter(r => r.download)).toHaveLength(unchanged ? 0 : 1);
    expect(requests.filter(r => r.content)).toHaveLength(0);
    expect(requests.every(r => r.headers.authorization === 'Bearer ts_fixture-123')).toBe(true);
    await expect(page.getByRole('button', { name: 'Download to local', exact: true })).toBeEnabled();
    expect(fileHostRequests(cloud)).toEqual([]);
  });
}

for (const preview of ['oversized', 'binary', 'office', 'pending']) {
  test(`Cloud files download when the preview is ${preview} without saving the preview result`, async ({ page }) => {
    const cloud = new CloudFilesHarness(page);
    const name = preview === 'office' ? 'report.docx' : 'unsupported.bin';
    const key = `${sessionA}:${name}`;
    const raw = Buffer.from([0, 0xff, 0xfe, 13, 10, 0x80]);
    cloud.directories.set(`${sessionA}:`, [{ name, is_dir: false }]);
    cloud.contents.set(key, preview === 'office'
      ? { kind: 'binary_content', ...cloud.device.officeFiles['docs/report.docx'] }
      : { kind: preview === 'pending' ? 'content' : preview, content: 'preview source', sig: 'v1', absolute: `/${name}` });
    cloud.downloads.set(key, raw);
    let release;
    if (preview === 'pending') cloud.holdRead = new Promise(resolve => { release = resolve; });
    await cloud.install(); await cloud.goto(); await openFiles(page, cloud);
    await file(page, name).click();
    if (preview === 'office') await expect(page.locator('.word-page')).toBeVisible();
    else await expect(page.locator('.viewer-notice')).toContainText(preview === 'pending' ? 'Loading file' : preview === 'oversized' ? 'too large' : 'binary file');
    const before = cloud.fileRequests.length;
    const transfer = page.waitForEvent('download');
    await page.getByRole('button', { name: 'Download to local', exact: true }).click();
    const download = await transfer;
    expect(readFileSync(await download.path())).toEqual(raw);
    expect(download.suggestedFilename()).toBe(name);
    expect(cloud.fileRequests.slice(before).filter(r => r.head || r.content)).toEqual([]);
    expect(cloud.fileRequests.slice(before).filter(r => r.download)).toHaveLength(1);
    if (release) release();
  });
}

test('Cloud download failure shows progress, reports the error and permits retry', async ({ page }, testInfo) => {
  const cloud = new CloudFilesHarness(page);
  cloud.contents.set(`${sessionA}:src/hello #.mbt`, { kind: 'oversized' });
  cloud.downloadStatus = 503;
  let release;
  cloud.holdDownload = new Promise(resolve => { release = resolve; });
  await cloud.install(); await cloud.goto(); await openFiles(page, cloud);
  await file(page, 'src').click(); await file(page, 'hello #.mbt').click();
  await expect(page.locator('.viewer-notice')).toContainText('too large');
  await page.getByRole('button', { name: 'Download to local', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Downloading…', exact: true })).toBeDisabled();
  release();
  await expect(page.locator('.notification')).toContainText('503');
  await expect(page.getByRole('button', { name: 'Download to local', exact: true })).toBeEnabled();
  await page.screenshot({ path: testInfo.outputPath('cloud-download-failure.png'), animations: 'disabled' });
  await page.locator('.notification').click();
  cloud.downloadStatus = 200; cloud.holdDownload = null;
  const transfer = page.waitForEvent('download');
  await page.getByRole('button', { name: 'Download to local', exact: true }).click();
  await transfer;
  await expect(page.locator('.notification')).toHaveCount(0);
});

test('a retired Cloud account cannot hand its delayed download to the browser', async ({ page }) => {
  const cloud = new CloudFilesHarness(page);
  cloud.contents.set(`${sessionA}:src/hello #.mbt`, { kind: 'oversized' });
  let release;
  cloud.holdDownload = new Promise(resolve => { release = resolve; });
  await cloud.install(); await cloud.goto(); await openFiles(page, cloud);
  await file(page, 'src').click(); await file(page, 'hello #.mbt').click();
  await expect(page.locator('.viewer-notice')).toContainText('too large');
  const downloads = []; page.on('download', d => downloads.push(d));
  await page.getByRole('button', { name: 'Download to local', exact: true }).click();
  await expect.poll(() => cloud.fileRequests.filter(r => r.download).length).toBe(1);
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  const account = page.locator('.settings-group', { has: page.getByRole('heading', { name: 'Account · Remote access', exact: true }) });
  await account.getByRole('button', { name: 'Sign out', exact: true }).click();
  const response = page.waitForResponse(r => new URL(r.url()).pathname.endsWith('/files/download'));
  release(); await (await response).finished();
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  await expect(account.getByRole('button', { name: 'Sign in', exact: true })).toBeVisible();
  expect(downloads).toEqual([]);
});

test('Desktop Cloud downloads use the window command with the original cache and report native failures', async ({ page }) => {
  const cloud = new CloudFilesHarness(page, { desktop: true });
  const reply = cloud.device.replyFor.bind(cloud.device);
  let failure = false;
  cloud.device.replyFor = request => request.method === 'cloud.file_download'
    ? failure ? { kind: 'failed', message: 'Downloads is not writable' } : { kind: 'saved', path: '/Downloads/hello #.mbt', revealed: true }
    : reply(request);
  await cloud.install(); await cloud.goto(); await openFiles(page, cloud); await openText(page);
  const before = cloud.fileRequests.length;
  await page.getByRole('button', { name: 'Download to local', exact: true }).click();
  await expect.poll(() => cloud.hostRequests.filter(r => r.method === 'cloud.file_download').length).toBe(1);
  const payload = cloud.hostRequests.find(r => r.method === 'cloud.file_download').params;
  expect(payload).toMatchObject({ account: '123', session: sessionA, path: 'src/hello #.mbt' });
  expect(Buffer.from(payload.cached.data_base64, 'base64').toString()).toContain('Cloud text');
  expect(payload.cached.etag).toMatch(/^W\/"content-v1-/);
  expect(cloud.fileRequests.slice(before)).toEqual([]);
  await expect(page.getByRole('button', { name: 'Download to local', exact: true })).toBeEnabled();
  failure = true;
  await page.getByRole('button', { name: 'Download to local', exact: true }).click();
  await expect(page.locator('.notification')).toHaveText('Downloads is not writable');
});


for (const kind of ['image', 'pdf']) {
  test(`Cloud download reuses unchanged ${kind} source bytes`, async ({ page }) => {
    const cloud = new CloudFilesHarness(page);
    const name = kind === 'image' ? 'picture.png' : 'report.pdf';
    const original = kind === 'image'
      ? readFileSync(new URL('../../../deepseek/client/testdata/two-colors.png', import.meta.url))
      : Buffer.from(cloud.device.officeFiles['docs/report.pdf'].data_base64, 'base64');
    cloud.directories.set(`${sessionA}:`, [{ name, is_dir: false }]);
    cloud.contents.set(`${sessionA}:${name}`, { kind: 'binary_content', data_base64: original.toString('base64'), media_type: kind === 'image' ? 'image/png' : 'application/pdf', sig: 'v1' });
    await cloud.install(); await cloud.goto(); await openFiles(page, cloud);
    await file(page, name).click();
    if (kind === 'image') await expect(page.locator('.file-image-preview img')).toBeVisible();
    else await expect(page.locator('#openseek-office-surface')).toHaveAttribute('data-pdf-painted', 'true');
    const before = cloud.fileRequests.length;
    const transfer = page.waitForEvent('download');
    await page.getByRole('button', { name: 'Download to local', exact: true }).click();
    const download = await transfer;
    expect(readFileSync(await download.path())).toEqual(original);
    expect(cloud.fileRequests.slice(before).filter(r => r.head)).toHaveLength(1);
    expect(cloud.fileRequests.slice(before).filter(r => r.download || r.content)).toEqual([]);
  });
}



for (const status of [200, 503]) {
  test(`a Cloud browser download ${status === 200 ? 'continues' : 'reports failure'} after navigating away from its file`, async ({ page }) => {
    const cloud = new CloudFilesHarness(page);
    cloud.contents.set(`${sessionA}:src/hello #.mbt`, { kind: 'oversized' });
    cloud.downloadStatus = status;
    let release;
    cloud.holdDownload = new Promise(resolve => { release = resolve; });
    await cloud.install(); await cloud.goto(); await openFiles(page, cloud);
    await file(page, 'src').click(); await file(page, 'hello #.mbt').click();
    await expect(page.locator('.viewer-notice')).toContainText('too large');
    await page.getByRole('button', { name: 'Download to local', exact: true }).click();
    await expect.poll(() => cloud.fileRequests.filter(r => r.download).length).toBe(1);
    await page.getByRole('button', { name: 'Settings', exact: true }).click();
    const transfer = status === 200 ? page.waitForEvent('download') : null;
    release();
    if (transfer) {
      const download = await transfer;
      expect(readFileSync(await download.path())).toEqual(Buffer.from('raw original'));
    } else {
      await expect(page.locator('.notification')).toContainText('503');
    }
  });
}

test('an older Cloud download cannot clear a newer download of the same file', async ({ page }) => {
  const cloud = new CloudFilesHarness(page, { desktop: true });
  const reply = cloud.device.replyFor.bind(cloud.device);
  let first, second, completed = 0, requested = 0;
  const waits = [new Promise(resolve => { first = resolve; }), new Promise(resolve => { second = resolve; })];
  cloud.device.replyFor = async request => {
    if (request.method !== 'cloud.file_download') return reply(request);
    await waits[requested++];
    completed++;
    return { kind: 'saved', path: '/Downloads/hello #.mbt', revealed: true };
  };
  await cloud.install(); await cloud.goto(); await openFiles(page, cloud); await openText(page);
  await page.getByRole('button', { name: 'Download to local', exact: true }).click();
  await expect.poll(() => requested).toBe(1);
  await cloud.open(sessionB); await cloud.open(sessionA);
  await expect(source(page)).toContainText('Cloud text');
  await page.getByRole('button', { name: 'Download to local', exact: true }).click();
  await expect.poll(() => requested).toBe(2);
  first();
  await expect.poll(() => completed).toBe(1);
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  await expect(page.getByRole('button', { name: 'Downloading…', exact: true })).toBeDisabled();
  second();
  await expect(page.getByRole('button', { name: 'Download to local', exact: true })).toBeEnabled();
});

async function selectCloudCode(page) {
  const line = source(page).locator('.view-lines .view-line').nth(1);
  await line.click();
  await page.keyboard.press('Home');
  await page.keyboard.press('Shift+End');
  const input = source(page).locator('.agent-feedback-input-widget textarea');
  await expect(input).toBeVisible();
  return input;
}

test('Cloud code feedback preserves the owning draft, sends Annotation and reopens the selected lines', async ({ page }, testInfo) => {
  const cloud = new CloudFilesHarness(page);
  await cloud.install(); await cloud.goto(); await openFiles(page, cloud); await openText(page);
  await page.locator('#task').fill('Existing Cloud draft');
  const feedback = await selectCloudCode(page);
  await feedback.fill('Explain this function');
  await page.getByRole('checkbox', { name: 'Batch', exact: true }).check();
  await feedback.press('Enter');
  const chip = page.locator('.composer .mention-chip');
  await expect(chip).toContainText('hello #.mbt');
  await expect(page.locator('#task')).toHaveValue('Existing Cloud draft');
  expect(cloud.postCount).toBe(0);
  await cloud.row(sessionB).click();
  await expect(chip).toHaveCount(0);
  await page.locator('#task').fill('Other draft');
  await cloud.row(sessionA).click();
  await expect(page.locator('#task')).toHaveValue('Existing Cloud draft');
  await expect(chip).toContainText('hello #.mbt');
  await chip.locator('button').first().click();
  await expect(source(page)).toContainText('Cloud text');
  await expect(source(page).locator('.agent-feedback-widget')).toContainText('Explain this function');
  await page.screenshot({ path: testInfo.outputPath('cloud-code-annotation.png') });
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect.poll(() => cloud.postCount).toBe(1);
  const send = cloud.requests.find(request => request.method === 'POST' && request.path.endsWith('/commands'));
  expect(send.path).toContain(sessionA);
  const content = JSON.parse(send.body).command.content;
  expect(content).toContain('Existing Cloud draft');
  expect(content).toContain('<annotation file="src/hello #.mbt" lines="2-2">');
  expect(content).toContain('fn hello() -> String { "Cloud text" }');
  expect(content).toContain('Explain this function');
  expect(fileHostRequests(cloud)).toEqual([]);
  expect(cloud.device.pageErrors).toEqual([]);
});

for (const batch of [true, false]) {
  test(`Cloud code feedback ${batch ? 'batches into the draft' : 'steers the active task'} and keeps archived files read only`, async ({ page }) => {
    const cloud = new CloudFilesHarness(page);
    const task = 'cloud-feedback-task';
    cloud.generating.add(sessionA);
    cloud.histories.set(sessionA, { messages: [], generating: true });
    cloud.controlSnapshots.set(sessionA, {
      session_id: sessionA, task_id: task, seq: 1,
      data: { active_task_id: task, status: 'running', paused: false, queue: [], steers: [] },
    });
    cloud.archived.add(sessionB);
    const submissions = () => cloud.requests.filter(request => request.method === 'POST' && /\/(commands|queue)$/.test(request.path));
    await cloud.install(); await cloud.goto(); await openFiles(page, cloud); await openText(page);
    await expect(page.locator('#stop')).toBeEnabled();
    await page.locator('#task').fill('Existing Cloud draft');
    if (!batch) {
      await page.getByRole('button', { name: 'Follow-up action', exact: true }).click();
      await page.getByRole('option', { name: /^Steer now/ }).click();
    }
    const feedback = await selectCloudCode(page);
    await feedback.fill('Keep this in my draft');
    await page.getByRole('checkbox', { name: 'Batch', exact: true }).setChecked(batch);
    const accepted = batch ? null : page.waitForResponse(response => response.request().method() === 'POST' && new URL(response.url()).pathname === `/v1/sessions/${sessionA}/commands`);
    await feedback.press('Enter');
    if (batch) {
      await expect(page.locator('.composer .mention-chip')).toContainText('hello #.mbt');
      await expect(page.locator('#task')).toHaveValue('Existing Cloud draft');
      expect(submissions()).toHaveLength(0);
    } else {
      expect((await accepted).status()).toBe(202);
      await expect(page.locator('#task')).toHaveValue('');
      await expect(page.locator('.pending-steer-row')).toContainText('Keep this in my draft');
      const requests = submissions();
      expect(requests).toHaveLength(1);
      expect(requests[0].path).toBe(`/v1/sessions/${sessionA}/commands`);
      const request = JSON.parse(requests[0].body);
      expect(request.task_id).toBe(task);
      expect(request.command.submission_id).toBeTruthy();
      expect(request.command.content).toContain('Existing Cloud draft');
      expect(request.command.content).toContain('<annotation file="src/hello #.mbt" lines="2-2">');
      expect(request.command.content).toContain('fn hello() -> String { "Cloud text" }');
      expect(request.command.content).toContain('Keep this in my draft');
    }
    expect(cloud.postCount).toBe(0);
    const archived = page.getByRole('button', { name: /^Archived chats \(/ });
    if (await archived.getAttribute('aria-expanded') === 'false') await archived.click();
    await cloud.row(sessionB).click();
    await page.locator('.dock-launcher').getByRole('button', { name: /^Files / }).click();
    await openText(page);
    const line = source(page).locator('.view-lines .view-line').nth(1);
    await line.click(); await page.keyboard.press('Home'); await page.keyboard.press('Shift+End');
    await expect(source(page).locator('.agent-feedback-input-widget')).toBeHidden();
    await line.hover();
    await expect(source(page).locator('.agent-feedback-glyph.line-hover')).toHaveCount(0);
    expect(cloud.postCount).toBe(0);
    expect(submissions()).toHaveLength(batch ? 0 : 1);
    expect(fileHostRequests(cloud)).toEqual([]);
    expect(cloud.device.pageErrors).toEqual([]);
  });
}

test('Cloud code feedback applies through the existing submit action when idle', async ({ page }) => {
  const cloud = new CloudFilesHarness(page);
  await cloud.install(); await cloud.goto(); await openFiles(page, cloud); await openText(page);
  await page.locator('#task').fill('Explain the selection');
  const feedback = await selectCloudCode(page);
  await feedback.fill('Why does this return a string?');
  await feedback.press('Enter');
  await expect.poll(() => cloud.postCount).toBe(1);
  const request = cloud.requests.find(request => request.method === 'POST' && request.path.endsWith('/commands'));
  const content = JSON.parse(request.body).command.content;
  expect(content).toContain('Explain the selection');
  expect(content).toContain('<annotation file="src/hello #.mbt" lines="2-2">');
  expect(content).toContain('Why does this return a string?');
  expect(cloud.device.pageErrors).toEqual([]);
});


test('Cloud file sharing works before preview and from an unpreviewable file path bar', async ({ page, context }, testInfo) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  const cloud = new CloudFilesHarness(page);
  cloud.contents.set(`${sessionA}:src/hello #.mbt`, { kind: 'oversized' });
  await cloud.install(); await cloud.goto(); await openFiles(page, cloud);
  await file(page, 'src').click({ button: 'right' });
  await expect(page.getByRole('menu', { name: 'Context menu', exact: true })).toBeVisible();
  await expect(page.getByRole('menuitem', { name: 'Share', exact: true })).toHaveCount(0);
  await page.getByRole('menu', { name: 'Context menu', exact: true }).press('Escape');
  await file(page, 'src').click();
  let finish;
  cloud.holdFileShare = new Promise(resolve => { finish = resolve; });
  await file(page, 'hello #.mbt').click({ button: 'right' });
  await page.getByRole('menuitem', { name: 'Share', exact: true }).click();
  const dialog = page.getByRole('dialog', { name: 'Share file', exact: true });
  await expect(dialog).toBeVisible();
  const shares = () => cloud.fileRequests.filter(request => request.share);
  await expect.poll(() => shares().length).toBe(1);
  expect(shares()[0]).toMatchObject({ method: 'POST', headers: { authorization: 'Bearer ts_fixture-123' }, body: { path: 'src/hello #.mbt', idempotency_key: expect.any(String) } });
  expect(cloud.fileRequests.filter(request => request.content || request.download || request.head)).toEqual([]);
  await page.keyboard.press('Escape');
  await expect(dialog).toBeHidden();
  finish(); cloud.holdFileShare = null;
  await file(page, 'hello #.mbt').click({ button: 'right' });
  await page.getByRole('menuitem', { name: 'Share', exact: true }).click();
  await expect(dialog.getByRole('textbox', { name: 'Share link' })).toHaveValue(`${authOrigin}/v1/shares/file-fixture`);
  expect(shares()).toHaveLength(1);
  await dialog.getByRole('button', { name: 'Copy share link' }).click();
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(`${authOrigin}/v1/shares/file-fixture`);
  await expect(dialog.getByRole('link', { name: 'Open link', exact: true })).toHaveAttribute('href', `${authOrigin}/v1/shares/file-fixture`);
  await context.route(`${authOrigin}/v1/shares/file-fixture`, route => route.fulfill({ contentType: 'text/html', body: '<title>Shared file</title>Public share page' }));
  const [publicPage] = await Promise.all([page.waitForEvent('popup'), dialog.getByRole('link', { name: 'Open link', exact: true }).click()]);
  await expect(publicPage).toHaveURL(`${authOrigin}/v1/shares/file-fixture`);
  await publicPage.close();
  await page.screenshot({ path: testInfo.outputPath('cloud-file-share.png') });
  await page.keyboard.press('Escape');
  await file(page, 'hello #.mbt').click();
  await expect(page.locator('.viewer-notice')).toContainText('too large');
  const reads = cloud.fileRequests.filter(request => request.content || request.head || request.download).length;
  await page.locator('.viewer-breadcrumb').getByRole('button', { name: 'Share', exact: true }).click();
  await expect.poll(() => shares().length).toBe(2);
  expect(shares()[1].body.idempotency_key).not.toBe(shares()[0].body.idempotency_key);
  expect(cloud.fileRequests.filter(request => request.content || request.head || request.download)).toHaveLength(reads);
  expect(fileHostRequests(cloud)).toEqual([]);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('Cloud file share failure permits explicit retry without an automatic resend', async ({ page }) => {
  const cloud = new CloudFilesHarness(page);
  await cloud.install(); await cloud.goto(); await openFiles(page, cloud); await openText(page);
  cloud.shareStatus = 503;
  await page.locator('.viewer-breadcrumb').getByRole('button', { name: 'Share', exact: true }).click();
  const dialog = page.getByRole('dialog', { name: 'Share file', exact: true });
  await expect(dialog).toContainText('HTTP 503');
  const shares = () => cloud.fileRequests.filter(request => request.share);
  expect(shares()).toHaveLength(1);
  await expect(dialog.getByRole('button', { name: 'Share', exact: true })).toBeEnabled();
  cloud.shareStatus = 201;
  await dialog.getByRole('button', { name: 'Share', exact: true }).click();
  await expect(dialog.getByRole('textbox', { name: 'Share link' })).toBeVisible();
  expect(shares()).toHaveLength(2);
  expect(shares()[1].body.idempotency_key).not.toBe(shares()[0].body.idempotency_key);
  expect(cloud.device.pageErrors).toEqual([]);
});

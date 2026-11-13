import { test, expect } from './support/test.js';
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
    this.fileStatus = 200;
    this.holdRead = null;
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
      return route.fulfill({ status: this.downloadStatus, headers, contentType: 'application/octet-stream', body: Buffer.from('raw original') });
    }
    let body;
    if (index) {
      body = { files: this.indexes.get(session) || [] };
    } else if (contentPath) {
      body = this.contents.get(`${session}:${path}`);
    } else {
      body = { entries: this.directories.get(`${session}:${path}`) || [] };
    }
    let status = this.fileStatus;
    if (contentPath && status === 200 && ['content', 'binary_content'].includes(body?.kind)) {
      headers.ETag = `W/"content-v1-${createHash('sha256').update(JSON.stringify(body)).digest('hex')}"`;
      if (head && request.headers['if-none-match'] === headers.ETag) status = 304;
    }
    if (this.fileOffline) return route.abort('failed');
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
  await expect(launcher.getByRole('button')).toHaveText([...(cloud.desktop ? [/Browse/] : []), /Search/, /Files/, /Review/]);
  await launcher.getByRole('button', { name: /^Files / }).click();
  await expect(tree(page).getByRole('treeitem').first()).toBeVisible();
}

async function openText(page) {
  await file(page, 'src').click();
  await file(page, 'hello #.mbt').click();
  await expect(source(page)).toContainText('Cloud text');
}

for (const desktop of [false, true]) {
  test(`Cloud HTML Preview uses account HTTP from both entry points on ${desktop ? 'Desktop' : 'Web'}`, async ({ page, context }, testInfo) => {
    const cloud = new CloudFilesHarness(page, { desktop });
    const name = desktop ? 'demo #.HTM' : 'demo #.HTML';
    const path = `pages/${name}`;
    cloud.directories.set(`${sessionA}:`, [{ name: 'pages', is_dir: true }]);
    cloud.directories.set(`${sessionA}:pages`, [{ name, is_dir: false }]);
    cloud.contents.set(`${sessionA}:${path}`, { kind: 'content', content: '<h1>Cloud HTML</h1>', sig: 'html-v1', absolute: `/${path}` });
    await cloud.install();
    const requests = [];
    let status = 500;
    let preview = 0;
    await page.route(`${cloudOrigin}/v1/sessions/*/previews`, async route => {
      const headers = { 'Access-Control-Allow-Origin': authOrigin, 'Access-Control-Allow-Headers': 'Authorization, Content-Type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
      if (route.request().method() === 'OPTIONS') return route.fulfill({ status: 204, headers });
      requests.push({ method: route.request().method(), url: route.request().url(), body: route.request().postDataJSON(), headers: await route.request().allHeaders() });
      const url = `https://preview.example.test/token-${++preview}/pages/${encodeURIComponent(name)}`;
      return route.fulfill({ status, headers, json: status === 201 ? { url } : { error: 'preview failed' } });
    });
    await context.route('https://preview.example.test/**', route => {
      const url = new URL(route.request().url());
      if (url.pathname.endsWith('/style.css')) return route.fulfill({ contentType: 'text/css', body: 'h1 { color: rgb(30, 64, 175) }' });
      if (url.pathname.endsWith('/data.json')) return route.fulfill({ json: { value: 'Relative JSON loaded' } });
      if (url.pathname.includes('/token-2/')) return route.fulfill({ status: 410, contentType: 'text/html', body: 'Preview expired' });
      return route.fulfill({ contentType: 'text/html', body: '<link rel="stylesheet" href="../style.css"><h1>Cloud HTML</h1><button onclick="fetch(\'../data.json\').then(r=>r.json()).then(data=>document.querySelector(\'output\').textContent=data.value)">Load JSON</button><output></output>' });
    });
    await cloud.goto(); await openFiles(page, cloud);
    await file(page, 'pages').click();
    await file(page, name).click({ button: 'right' });
    await page.getByRole('menuitem', { name: 'Preview', exact: true }).click();
    await expect(page.locator('.notification')).toContainText('Cloud answered HTTP 500');
    status = 201;
    await page.locator('.notification').click();
    await file(page, name).click({ button: 'right' });
    const menuScreenshot = testInfo.outputPath('cloud-html-preview-menu.png');
    await page.screenshot({ path: menuScreenshot });
    await testInfo.attach('Cloud HTML Preview context menu', { path: menuScreenshot, contentType: 'image/png' });
    const popup = desktop ? null : page.waitForEvent('popup');
    await page.getByRole('menuitem', { name: 'Preview', exact: true }).click();
    if (desktop) {
      await expect(page.locator('#browser-address-input')).toHaveValue(/\/token-2\//);
      await page.locator('.editor-tab.active .tab-close').click();
    } else {
      const expired = await popup;
      await expect(expired.getByText('Preview expired', { exact: true })).toBeVisible();
      await expired.close();
    }
    await file(page, name).click();
    await expect(source(page)).toContainText('<h1>Cloud HTML</h1>');
    const toolbar = page.locator('.viewer-breadcrumb');
    await expect(toolbar.getByRole('button', { name: 'Preview', exact: true })).toBeVisible();
    const toolbarScreenshot = testInfo.outputPath('cloud-html-preview-toolbar.png');
    await page.screenshot({ path: toolbarScreenshot });
    await testInfo.attach('Cloud HTML editor Preview action', { path: toolbarScreenshot, contentType: 'image/png' });
    const nextPopup = desktop ? null : page.waitForEvent('popup');
    await toolbar.getByRole('button', { name: 'Preview', exact: true }).click();
    if (desktop) {
      await expect(page.locator('#browser-address-input')).toHaveValue(/\/token-3\//);
      expect(cloud.hostRequests.filter(request => request.method === 'browser.open')).toHaveLength(2);
      expect(cloud.hostRequests.some(request => request.method === 'browser.preview')).toBe(false);
      const id = cloud.hostRequests.filter(request => request.method === 'browser.open').at(-1).params.id;
      const last = method => cloud.hostRequests.findLast(request => request.method === method && request.params.id === id);
      const visible = () => last('browser.set_visible')?.params.visible;
      await expect.poll(visible).toBe(true);
      const pane = await page.locator('#browser-pane').boundingBox();
      const bounds = last('browser.set_bounds');
      expect(bounds.params).toEqual({
        id, x: Math.trunc(pane.x), y: Math.trunc(pane.y),
        width: Math.trunc(pane.width), height: Math.trunc(pane.height),
      });
      expect(cloud.hostRequests.indexOf(bounds)).toBeLessThan(cloud.hostRequests.indexOf(last('browser.set_visible')));
      const tab = page.locator('.editor-tab.active');
      await tab.click({ button: 'right' });
      await expect(page.getByRole('menu', { name: 'Tab actions' })).toBeVisible();
      await expect.poll(visible).toBe(false);
      await page.keyboard.press('Escape');
      await expect.poll(visible).toBe(true);
      await cloud.open(sessionB);
      await expect.poll(visible).toBe(false);
      await cloud.open(sessionA);
      await expect.poll(visible).toBe(true);
      await tab.locator('.tab-close').click();
      await expect.poll(() => last('browser.close')?.params.id).toBe(id);
    } else {
      const opened = await nextPopup;
      await expect(opened.getByRole('heading', { name: 'Cloud HTML', exact: true })).toHaveCSS('color', 'rgb(30, 64, 175)');
      await opened.getByRole('button', { name: 'Load JSON', exact: true }).click();
      await expect(opened.locator('output')).toHaveText('Relative JSON loaded');
      await opened.close();
    }
    expect(requests).toHaveLength(3);
    for (const request of requests) {
      expect(request.method).toBe('POST');
      expect(request.url).toBe(`${cloudOrigin}/v1/sessions/${sessionA}/previews`);
      expect(request.headers.authorization).toBe('Bearer ts_fixture-123');
      expect(request.body).toEqual({ path });
    }
    expect(fileHostRequests(cloud)).toEqual([]);
    expect(cloud.device.pageErrors).toEqual([]);
  });
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
  await expect(page.locator('main .run-status')).toHaveText('Finished');
  await expect(input).toHaveValue('');
  // Wait for the post-send history record before recalling its prompt.
  await expect(page.locator('#transcript').getByText('Update the heading', { exact: true })).toBeVisible();
  await input.press('ArrowUp');
  await expect(input).toHaveValue('Update the heading');
  await expect(chip).toContainText('index.html');
  await expect.poll(() => indexes().length).toBe(2);
  expect(fileHostRequests(cloud)).toEqual([]);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('Cloud browses nested text files through the existing read-only Files pane', async ({ page }) => {
  const cloud = new CloudFilesHarness(page);
  await cloud.install(); await cloud.goto(); await openFiles(page, cloud);
  await expect(page.getByRole('tab', { name: 'Changes', exact: true })).toHaveCount(1);
  await expect(page.getByRole('tab', { name: 'Search', exact: true })).toHaveCount(1);
  await openText(page);
  expect(cloud.fileRequests.at(-1)).toMatchObject({ session: sessionA, path: 'src/hello #.mbt', content: true });
  expect(cloud.fileRequests.at(-1).headers.authorization).toBe('Bearer ts_fixture-123');
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

test('Cloud text search reuses options, results, keyboard tabs and positioned file opens', async ({ page }) => {
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
  await filesTab.focus(); await page.keyboard.press('End');
  const searchTab = page.getByRole('tab', { name: 'Search', exact: true });
  await expect(searchTab).toHaveAttribute('aria-selected', 'true');
  await expect(page.getByRole('tab', { name: 'Changes', exact: true })).toHaveCount(1);
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
  await search.locator('.search-result-row').getByRole('button', { name: /moon moon/ }).click();
  await expect(source(page)).toContainText('moon moon');
  expect(cloud.fileRequests.some(request => request.content && request.path === 'src/hello #.mbt')).toBe(true);
  expect(fileHostRequests(cloud)).toEqual([]);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('Cloud code search streams shared results, navigates ranges, and cancels an obsolete query', async ({ page }) => {
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
    await search.locator('.search-result-row').getByRole('button').click();
    await expect(source(page)).toContainText('inspect(1)');
    expect(fileHostRequests(cloud)).toEqual([]);
    expect(cloud.device.pageErrors).toEqual([]);
    expect(await page.evaluate(() => window.cloudUnhandledRejections)).toEqual([]);
  } finally { resume(); }
});

test('Cloud download failure shows progress, reports the error and permits retry', async ({ page }) => {
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
  await page.locator('.notification').click();
  cloud.downloadStatus = 200; cloud.holdDownload = null;
  const transfer = page.waitForEvent('download');
  await page.getByRole('button', { name: 'Download to local', exact: true }).click();
  await transfer;
  await expect(page.locator('.notification')).toHaveCount(0);
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

async function selectCloudCode(page) {
  const line = source(page).locator('.view-lines .view-line').nth(1);
  await line.click();
  await page.keyboard.press('Home');
  await page.keyboard.press('Shift+End');
  const input = source(page).locator('.agent-feedback-input-widget textarea');
  await expect(input).toBeVisible();
  return input;
}

test('Cloud code feedback preserves the owning draft, sends Annotation and reopens the selected lines', async ({ page }) => {
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

test('Cloud file sharing works before preview and from an unpreviewable file path bar', async ({ page, context }) => {
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

test('Cloud Quick Open finds and opens files without a host', async ({ page }) => {
  const cloud = new CloudFilesHarness(page);
  await cloud.install(); await page.goto(`${authOrigin}/cloud`);
  await expect(page.locator('#task')).toBeEnabled();
  await cloud.open();
  const palette = page.getByRole('dialog', { name: 'Search workspace files', exact: true });
  await page.keyboard.press('ControlOrMeta+p');
  const query = palette.getByRole('combobox');
  await expect(query).toBeFocused();
  await expect(query).toHaveAttribute('aria-keyshortcuts', 'Meta+P Control+P');
  await query.fill('hello');
  await expect(palette.getByRole('option')).toContainText(['hello #.mbt']);
  await query.press('Enter');
  await expect(palette).toHaveCount(0);
  await expect(source(page)).toContainText('"Cloud text"');
  // The pick opened the panel; reconciling it must not read the file again.
  expect(cloud.fileRequests.filter(request => request.content && request.path === 'src/hello #.mbt')).toHaveLength(1);
  expect(cloud.fileRequests.some(request => request.index && request.session === sessionA)).toBe(true);
  expect(fileHostRequests(cloud)).toEqual([]);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('Host Quick Open retains both file and workspace-symbol shortcuts', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  const reply = app.replyFor.bind(app);
  app.replyFor = request => request.method === 'lsp.workspace_symbols'
    ? { symbols: [{ name: 'fixture_symbol', path: 'src/main.mbt', kind: 12, container: null, range: { start: { line: 1, col: 0 }, end: { line: 1, col: 14 } } }] }
    : reply(request);
  await app.install(); await app.goto(); await app.openSession();
  await page.keyboard.press('ControlOrMeta+p');
  await expect(page.getByRole('dialog', { name: 'Search workspace files', exact: true })).toBeVisible();
  await page.locator('#quick-open-input').press('Escape');
  await page.keyboard.press('ControlOrMeta+t');
  const palette = page.getByRole('dialog', { name: 'Search workspace symbols', exact: true });
  await expect(palette).toBeVisible();
  await expect(palette.getByRole('option')).toContainText(['fixture_symbol']);
  expect(app.requests.some(request => request.method === 'fs.search_files')).toBe(true);
  expect(app.requests.some(request => request.method === 'lsp.workspace_symbols')).toBe(true);
  expect(app.pageErrors).toEqual([]);
});

test('preview_open reuses Cloud viewers and parks another session without stealing focus', async ({ page }, testInfo) => {
  const cloud = new CloudFilesHarness(page, { desktop: true });
  const names = ['report.docx', 'report.pdf', 'image.png', 'src/main.mbt', 'notes.txt'];
  for (const name of names.slice(0, 2)) cloud.contents.set(`${sessionA}:${name}`, { kind: 'binary_content', ...cloud.device.officeFiles[`docs/${name}`] });
  cloud.contents.set(`${sessionA}:image.png`, { kind: 'binary_content', data_base64: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jBfkAAAAASUVORK5CYII=', media_type: 'image/png', sig: 'image' });
  for (const name of names.slice(3)) cloud.contents.set(`${sessionA}:${name}`, { kind: 'content', content: `// Tool preview ${name}`, sig: name, absolute: `/${name}` });
  cloud.contents.set(`${sessionB}:notes.txt`, { kind: 'content', content: 'Session B tool preview', sig: 'b', absolute: '/notes.txt' });
  const native = [];
  const reply = cloud.device.replyFor.bind(cloud.device);
  cloud.device.replyFor = request => {
    if (request.method.startsWith('browser.')) { native.push(request); return {}; }
    return reply(request);
  };
  await cloud.install(); await cloud.goto(); await cloud.open();
  const preview = (session, path) => page.evaluate(payload => window.desktopEvent('openseek.preview.open_requested', payload), { kind: 'cloud', account: cloud.userId, session, path });
  await preview(sessionA, 'src/main.mbt');
  await expect(source(page)).toContainText('Tool preview src/main.mbt');
  expect(cloud.fileRequests.filter(r => r.content && r.path === 'src/main.mbt')).toHaveLength(1);
  await preview(sessionB, 'notes.txt');
  await expect(page.locator('main .topbar-title')).toHaveText(cloud.titles.get(sessionA));
  await expect(source(page)).toContainText('Tool preview src/main.mbt');
  expect(cloud.fileRequests.some(r => r.content && r.session === sessionB)).toBe(false);
  await cloud.open(sessionB);
  await expect(source(page)).toContainText('Session B tool preview');
  expect(cloud.fileRequests.filter(r => r.content && r.session === sessionB)).toHaveLength(1);
  await cloud.open(sessionA);
  await preview(sessionA, 'report.docx');
  await expect(page.locator('.word-page')).toBeVisible();
  await preview(sessionA, 'report.pdf');
  await expect(page.locator('#openseek-office-surface')).toHaveAttribute('data-pdf-painted', 'true');
  await preview(sessionA, 'image.png');
  await expect(page.locator('.file-image-preview img')).toBeVisible();
  await preview(sessionA, 'notes.txt');
  await expect(source(page)).toContainText('Tool preview notes.txt');
  await page.screenshot({ path: testInfo.outputPath('mcp-cloud-file-preview.png') });
  await page.route(`${cloudOrigin}/v1/sessions/*/previews`, route => route.fulfill({ status: 201, headers: { 'Access-Control-Allow-Origin': authOrigin }, json: { url: 'https://preview.example.test/index.html' } }));
  await preview(sessionA, 'index.html');
  await expect(page.locator('.browser-address')).toHaveValue('https://preview.example.test/index.html');
  await expect.poll(() => native.some(r => r.method === 'browser.set_visible' && r.params.visible)).toBe(true);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('preview_open reuses Local file reads and the existing HTML preview command', async ({ page }) => {
  const cloud = new CloudHarness(page, { desktop: true });
  const native = [];
  const reply = cloud.device.replyFor.bind(cloud.device);
  cloud.device.replyFor = request => {
    if (request.method.startsWith('browser.')) { native.push(request); return {}; }
    return reply(request);
  };
  await cloud.install(); await cloud.goto();
  await page.getByRole('button', { name: 'Work', exact: true }).click();
  await cloud.device.openSession();
  const preview = path => page.evaluate(path => window.desktopEvent('openseek.preview.open_requested', { kind: 'local', session: 'session-1', workspace: '/workspace', path }), path);
  await preview('src/main.mbt');
  await expect(source(page)).toContainText(/fn\s+main/);
  expect(cloud.hostRequests.filter(r => r.method === 'fs.read_file' && r.params.path === '/workspace/src/main.mbt')).toHaveLength(1);
  await preview('docs/report.pdf');
  await expect(page.locator('#openseek-office-surface')).toHaveAttribute('data-pdf-painted', 'true');
  await preview('docs/report.docx');
  await expect(page.locator('.word-page')).toBeVisible();
  await preview('index.htm');
  await expect.poll(() => native.some(r => r.method === 'browser.preview' && r.params.path === '/workspace/index.htm' && r.params.root === '/workspace' && r.params.session === 'session-1')).toBe(true);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('Cloud AI pattern repair sends no client configuration overrides', async ({ page }) => {
  const cloud = new CloudFilesHarness(page);
  const repairs = [];
  await cloud.install(); await cloud.goto(); await cloud.open();
  await page.route(`${cloudOrigin}/v1/sessions/*/files/search/semantic**`, async route => {
    const headers = { 'Access-Control-Allow-Origin': authOrigin, 'Access-Control-Allow-Headers': 'Authorization, Content-Type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
    if (route.request().method() === 'OPTIONS') return route.fulfill({ status: 204, headers });
    const body = route.request().postDataJSON();
    if (new URL(route.request().url()).pathname.endsWith('/repair')) {
      repairs.push(body);
      return route.fulfill({ headers, contentType: 'application/json', body: JSON.stringify({ generation: body.generation, validation_status: 'passed', candidate_pattern: 'inspect($_)', message: '', trace: [] }) });
    }
    const result = { generation: body.generation, matches: [], match_count: 0, file_count: 0, limit_hit: false, cancelled: false, partial: false };
    return route.fulfill({ headers, contentType: 'text/event-stream', body: `event: result\ndata: ${JSON.stringify(result)}\n\n` });
  });
  await openFiles(page, cloud);
  await page.getByRole('tab', { name: 'Search', exact: true }).click();
  const search = page.locator('.workspace-search');
  await search.getByRole('button', { name: 'Code search', exact: true }).click();
  await search.getByRole('textbox', { name: 'pattern', exact: true }).fill('broken');
  await search.locator('.pattern-repair-button').click();
  await expect.poll(() => repairs.length).toBe(1);
  expect(repairs[0]).toEqual({ pattern: 'broken', generation: expect.any(Number) });
  await expect(search.getByRole('textbox', { name: 'pattern', exact: true })).toHaveValue('inspect($_)');
  expect(cloud.device.pageErrors).toEqual([]);
});

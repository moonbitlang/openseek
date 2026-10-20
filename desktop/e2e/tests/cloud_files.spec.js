import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';
import { CloudHarness, authOrigin, sessionA, sessionB } from './support/cloud_harness.js';

class CloudFilesHarness extends CloudHarness {
  constructor(page, options) {
    super(page, options);
    this.fileRequests = [];
    this.directories = new Map();
    this.contents = new Map();
    this.largePreviews = new Map();
    this.fileStatus = 200;
    this.holdRead = null;
    for (const session of [sessionA, sessionB]) {
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
    const match = url.pathname.match(/^\/v1\/sessions\/([^/]+)\/files(\/content)?$/);
    if (!match) return super.cloudRequest(route);
    const headers = { 'Access-Control-Allow-Origin': authOrigin, 'Access-Control-Allow-Headers': 'Authorization, Content-Type', 'Access-Control-Allow-Methods': 'GET, OPTIONS' };
    if (route.request().method() === 'OPTIONS') return route.fulfill({ status: 204, headers });
    const session = decodeURIComponent(match[1]);
    const path = url.searchParams.get('path') || '';
    const content = Boolean(match[2]);
    const allowLarge = url.searchParams.get('allow_large');
    this.fileRequests.push({ session, path, content, allowLarge, headers: await route.request().allHeaders() });
    const body = content ? (allowLarge === 'true' && this.largePreviews.has(`${session}:${path}`)
      ? this.largePreviews.get(`${session}:${path}`) : this.contents.get(`${session}:${path}`)) : { entries: this.directories.get(`${session}:${path}`) || [] };
    const status = this.fileStatus;
    if (this.fileOffline) return route.abort('failed');
    if (content && this.holdRead) await this.holdRead;
    return route.fulfill({ status, headers, contentType: 'application/json', body: JSON.stringify(body) });
  }
}

const tree = page => page.getByRole('tree', { name: 'Workspace files', exact: true });
const file = (page, name) => tree(page).getByRole('treeitem', { name, exact: true });
const source = page => page.locator('#viewer-host');

async function openFiles(page, cloud) {
  await cloud.open();
  await page.getByRole('button', { name: 'Show panel', exact: true }).click();
  const launcher = page.locator('.dock-launcher');
  await expect(launcher.getByRole('button')).toHaveCount(1);
  await launcher.getByRole('button', { name: /^Files / }).click();
  await expect(file(page, 'src')).toBeVisible();
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

test('Cloud file links and mentions reuse source previews and the composer envelope', async ({ page }) => {
  const cloud = new CloudFilesHarness(page);
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
  await expect(page.locator('.composer-attach')).toHaveCount(0);
  const input = page.locator('#task');
  await input.fill('@index');
  await expect(page.locator('.completion-item .completion-label')).toHaveText(['index.html']);
  await input.press('Enter');
  expect(cloud.fileRequests.filter(request => !request.content).map(request => request.path)).not.toContain('.git');
  const chip = page.locator('.composer .mention-chip');
  await expect(chip).toContainText('index.html');
  await chip.locator('.mention-jump').click();
  await expect(source(page)).toContainText('<h1>Cloud source</h1>');
  await input.fill('Update the heading');
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect.poll(() => cloud.postCount).toBe(1);
  const request = cloud.requests.find(request => request.method === 'POST' && request.path.endsWith('/messages'));
  expect(JSON.parse(request.body).content).toBe('Update the heading\n\n<user_mentions>\n<file path="src/index.html"/>\n</user_mentions>');
  await expect(page.getByRole('button', { name: 'Send', exact: true })).toBeVisible();
  await input.press('ArrowUp');
  await expect(input).toHaveValue('Update the heading');
  await expect(chip).toContainText('index.html');
  expect(fileHostRequests(cloud)).toEqual([]);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('Cloud browses nested text files through the existing read-only Files pane', async ({ page }, testInfo) => {
  const cloud = new CloudFilesHarness(page);
  await cloud.install(); await cloud.goto(); await openFiles(page, cloud);
  await expect(page.getByRole('tab', { name: 'Changes', exact: true })).toHaveCount(0);
  await expect(page.getByRole('tab', { name: 'Search', exact: true })).toHaveCount(0);
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
  await expect(page.getByRole('button', { name: 'Annotate region', exact: true })).toBeDisabled();
  await showTree(page); await file(page, 'book1.xlsx').click();
  await expect(page.locator('.sheet-document table').first()).toBeVisible();
  await showTree(page); await file(page, 'report.pdf').click();
  await expect(page.locator('#openseek-office-surface')).toHaveAttribute('data-pdf-painted', 'true');
  await expect(page.getByRole('button', { name: 'Capture region', exact: true })).toBeDisabled();
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


test('Cloud oversized previews require a fresh explicit click for each unrestricted read', async ({ page }, testInfo) => {
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
  await page.getByRole('tab', { name: 'Files', exact: true }).click();
  await expect(preview).toBeVisible();
  expect(reads().at(-1).allowLarge).toBeNull();
  await preview.click();
  await expect(source(page)).toContainText('Explicitly requested large preview.');
  await page.locator('#task').fill('Update the file');
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect(preview).toBeVisible();
  expect(reads().at(-1).allowLarge).toBeNull();
  await preview.click();
  await expect(source(page)).toContainText('Explicitly requested large preview.');
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
    await cloud.open(sessionB); await cloud.open(sessionA);
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

import { test, expect } from '@playwright/test';
import { CloudHarness, authOrigin, sessionA, sessionB } from './support/cloud_harness.js';

class CloudFilesHarness extends CloudHarness {
  constructor(page, options) {
    super(page, options);
    this.fileRequests = [];
    this.directories = new Map();
    this.contents = new Map();
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
    this.fileRequests.push({ session, path, content, headers: await route.request().allHeaders() });
    const body = content ? this.contents.get(`${session}:${path}`) : { entries: this.directories.get(`${session}:${path}`) || [] };
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
  await page.getByRole('tab', { name: 'Files', exact: true }).click();
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

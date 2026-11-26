import { test, expect } from './support/test.js';
import { CloudHarness, authOrigin, sessionA, sessionB } from './support/cloud_harness.js';

class CloudReviewHarness extends CloudHarness {
  constructor(page) {
    super(page);
    this.reviewRequests = [];
    this.repository = true;
    this.branch = 'codex/browser-fixture';
    this.reviewStatus = 200;
    this.reviewError = '';
    this.fileRevision = 1;
    this.holdOriginal = null;
  }

  async cloudRequest(route) {
    const request = route.request();
    const url = new URL(request.url());
    const review = url.pathname.match(/^\/v1\/sessions\/([^/]+)\/review\/([^/]+)$/);
    const file = url.pathname.match(/^\/v1\/sessions\/([^/]+)\/files(?:\/(content|index))?$/);
    if (!review && !file) return super.cloudRequest(route);
    const headers = { 'Access-Control-Allow-Origin': authOrigin, 'Access-Control-Allow-Headers': 'Authorization, Content-Type, If-None-Match', 'Access-Control-Allow-Methods': 'GET, POST, OPTIONS', 'Access-Control-Expose-Headers': 'ETag', ETag: '"review-file-v1"' };
    if (request.method() === 'OPTIONS') return route.fulfill({ status: 204, headers });
    const json = (body, status = 200) => route.fulfill({ status, headers, contentType: 'application/json', body: JSON.stringify(body) });
    if (review) {
      const [, session, operation] = review;
      const body = request.postDataJSON();
      this.reviewRequests.push({ session, operation, body, method: request.method(), headers: await request.allHeaders() });
      if (operation === 'original-file' && this.holdOriginal) await this.holdOriginal;
      if (this.reviewStatus !== 200) return route.fulfill({ status: this.reviewStatus, headers, contentType: 'text/plain', body: this.reviewError });
      const method = { changes: 'git.changes', 'original-file': 'git.original_file', history: 'git.history', 'commit-changes': 'git.commit_changes' }[operation];
      const reply = this.device.replyFor({ method, params: { ...body, session, workspace: '/workspace' } });
      if (operation === 'changes' || operation === 'history') reply.repository = this.repository;
      if (operation === 'changes' && !this.repository) reply.changes = [];
      if (operation === 'history') {
        reply.snapshot.branch = this.branch;
        if (!this.repository || !this.device.gitHead) {
          reply.commits = [];
          reply.has_more = false;
          reply.snapshot = { refs: [], tips: [], branch: this.repository ? this.branch : null };
        }
      }
      return json(reply);
    }
    const path = url.searchParams.get('path') || '';
    if (file[2] === 'content') {
      headers.ETag = `"review-file-v${this.fileRevision}"`;
      if (request.method() === 'HEAD' && request.headers()['if-none-match'] === headers.ETag) return route.fulfill({ status: 304, headers });
      return json(this.device.readWorkingFile({ path }));
    }
    if (file[2] === 'index') return json({ files: Object.keys(this.device.workingFiles) });
    return json({ entries: path === '' ? [{ name: 'src', is_dir: true }] : [{ name: 'main.mbt', is_dir: false }, { name: 'lib.mbt', is_dir: false }] });
  }

  async openReview(session = sessionA) {
    await this.open(session);
    const shortcut = await this.page.evaluate(() =>
      navigator.platform.includes('Mac') ? 'Meta+Shift+F' : 'Control+Shift+F');
    await this.page.keyboard.press(shortcut);
    await this.page.getByRole('tablist', { name: 'Explorer views' })
      .getByRole('tab', { name: /Changes/ }).click();
  }

}

const changedMain = page => page.locator('#review-changes-body').getByRole('treeitem', { name: /View diff: src\/main\.mbt/ });
const diff = page => page.locator('#diff-editor-host');

test('Cloud review shares diff, selected-change context and feedback with the owning composer', async ({ page }, testInfo) => {
  const cloud = new CloudReviewHarness(page);
  await cloud.install(); await cloud.goto(); await cloud.openReview();
  await expect(page.getByRole('tree', { name: 'Git commit history' })).toBeVisible();
  await page.screenshot({ path: testInfo.outputPath('cloud-review-list.png') });
  await changedMain(page).click();
  await page.getByRole('button', { name: 'Line diff', exact: true }).click();
  await expect(diff(page)).toContainText('working tree');
  cloud.device.workingFiles['src/main.mbt'] = cloud.device.workingFiles['src/main.mbt'].replace('working tree', 'working tree refreshed');
  cloud.fileRevision++;
  await page.evaluate(session => window.cloudInvalidateFiles(session), sessionA);
  await expect(diff(page)).toContainText('working tree refreshed');
  const context = page.locator('.review-hunk-context-button:visible').first();
  await expect(context).toHaveText('Add to context');
  const bounds = await context.evaluate(node => node.closest('.moonbit-diff-hunk-action').getBoundingClientRect().toJSON());
  await page.mouse.move(bounds.x + bounds.width * 0.7, bounds.y + 4);
  await context.click();
  await expect(page.locator('.composer-changes')).toContainText('1 file');
  await expect(context).toHaveText('In context');
  await page.locator('#task').fill('Review these changes');
  await cloud.row(sessionB).click();
  await expect(page.locator('.composer-changes .changes-chip')).toHaveCount(0);
  await cloud.row(sessionA).click();
  await expect(page.locator('.composer-changes')).toContainText('1 file');
  await expect(page.locator('#task')).toHaveValue('Review these changes');
  await page.locator('.composer-changes .mention-remove').click();
  await expect(context).toHaveText('Add to context');
  const restoredBounds = await context.evaluate(node => node.closest('.moonbit-diff-hunk-action').getBoundingClientRect().toJSON());
  await page.mouse.move(restoredBounds.x + restoredBounds.width * 0.7, restoredBounds.y + 4);
  await context.click();
  await expect(context).toHaveText('In context');
  const modified = diff(page).locator('.moonbit-diff-editor-modified');
  await modified.locator('.view-line').filter({ hasText: 'working tree' }).first().hover();
  await modified.locator('.agent-feedback-glyph.line-hover').click();
  const feedback = modified.getByRole('textbox', { name: 'Feedback', exact: true });
  await feedback.fill('Explain this change');
  await page.getByRole('checkbox', { name: 'Batch', exact: true }).check();
  await feedback.press('Enter');
  await expect(page.locator('.composer .mention-chip:not(.changes-chip)')).toContainText('main.mbt');
  const original = diff(page).locator('.moonbit-diff-editor-original');
  await original.locator('.view-line').filter({ hasText: 'baseline' }).first().hover();
  await original.locator('.agent-feedback-glyph.line-hover').click();
  const originalFeedback = original.getByRole('textbox', { name: 'Feedback', exact: true });
  await originalFeedback.fill('Keep the original intent');
  await page.getByRole('checkbox', { name: 'Batch', exact: true }).check();
  await originalFeedback.press('Enter');
  await expect(page.locator('.composer .mention-chip:not(.changes-chip)')).toHaveCount(2);
  await page.screenshot({ path: testInfo.outputPath('cloud-review-diff.png') });
  await page.locator('#send').click();
  await expect.poll(() => cloud.postCount).toBe(1);
  const content = JSON.parse(cloud.requests.find(r => r.method === 'POST' && r.path.endsWith('/commands')).body).command.content;
  expect(content).toContain('<review_changes workspace="."');
  expect(content).toContain('<file path="src/main.mbt"');
  expect(content).toContain('working tree');
  expect(content).toContain('Explain this change');
  expect(content).toContain('Keep the original intent');
  expect(content).toContain('side="original"');
  for (const request of cloud.reviewRequests) {
    expect(request.method).toBe('POST');
    expect(request.headers.authorization).toBe('Bearer ts_fixture-123');
    expect(request.body).not.toHaveProperty('workspace');
    expect(request.body).not.toHaveProperty('session');
  }
  expect(cloud.device.requests.filter(r => /^git\.(changes|original_file|history|commit_changes)$/.test(r.method))).toEqual([]);
});

test('Cloud commit history opens an immutable diff and ignores a previous session baseline', async ({ page }, testInfo) => {
  const cloud = new CloudReviewHarness(page);
  await cloud.install(); await cloud.goto(); await cloud.openReview();
  let release;
  cloud.holdOriginal = new Promise(resolve => { release = resolve; });
  await changedMain(page).click();
  await expect.poll(() => cloud.reviewRequests.filter(r => r.operation === 'original-file').length).toBe(1);
  await cloud.row(sessionB).click();
  release(); cloud.holdOriginal = null;
  await cloud.row(sessionA).click();
  await cloud.openReview();
  const history = page.getByRole('tree', { name: 'Git commit history' });
  await history.getByRole('treeitem', { name: /Cover Desktop Git flows/ }).click();
  await history.getByRole('treeitem', { name: /src\/main\.mbt/ }).click();
  await expect(page.locator('.editor-tab.active')).toContainText('main.mbt (cccccccc)');
  await page.getByRole('button', { name: 'Line diff', exact: true }).click();
  await expect(diff(page)).toContainText('history commit');
  await expect.poll(() => cloud.reviewRequests.filter(r => r.operation === 'original-file' && [cloud.device.gitMerge, cloud.device.gitHead].includes(r.body.revision)).length).toBe(2);
  await page.screenshot({ path: testInfo.outputPath('cloud-review-history.png') });
});

test('Cloud review reuses the non-Git notice and allows retry after an unavailable endpoint', async ({ page }) => {
  const cloud = new CloudReviewHarness(page);
  cloud.reviewStatus = 404;
  await cloud.install(); await cloud.goto(); await cloud.openReview();
  await expect(page.locator('#review-changes-body')).toContainText('Cloud answered HTTP 404');
  cloud.reviewStatus = 200; cloud.repository = false;
  await page.getByRole('tab', { name: /Changes/ }).click();
  await expect(page.locator('#review-changes-body')).toContainText('Git is unavailable or this workspace is not a Git repository.');
});

test('Cloud review preserves Git rejection reasons and retries without treating checkout conflicts as generation', async ({ page }, testInfo) => {
  const cloud = new CloudReviewHarness(page);
  cloud.reviewStatus = 409;
  cloud.reviewError = 'Git checkout kept changing while changes were read';
  await cloud.install(); await cloud.goto(); await cloud.openReview();
  const body = page.locator('#review-changes-body');
  await expect(body).toContainText(cloud.reviewError);
  await expect(body).not.toContainText('already generating');
  await page.screenshot({ path: testInfo.outputPath('cloud-review-checkout-conflict.png') });
  for (const [status, reason] of [
    [400, 'custom Git clean/process filters are not supported by Cloud review'],
    [403, 'Git metadata must remain inside the workspace'],
    [409, ''],
  ]) {
    cloud.reviewStatus = status; cloud.reviewError = reason;
    await page.getByRole('tab', { name: /Changes/ }).click();
    await expect(body).toContainText(reason || `HTTP ${status}`);
    await expect(body).not.toContainText('already generating');
  }
  cloud.reviewStatus = 200;
  await page.getByRole('tab', { name: /Changes/ }).click();
  await expect(changedMain(page)).toBeVisible();
  cloud.reviewStatus = 409;
  cloud.reviewError = 'Git checkout kept changing while changes were read';
  const before = cloud.reviewRequests.filter(request => request.operation === 'changes').length;
  await page.evaluate(session => window.cloudInvalidateFiles(session), sessionA);
  await expect.poll(() => cloud.reviewRequests.filter(request => request.operation === 'changes').length).toBeGreaterThan(before);
  await expect(changedMain(page)).toBeVisible();
});

test('Cloud overview shows the current checkout and changed files with the dock closed', async ({ page }) => {
  const cloud = new CloudReviewHarness(page);
  await cloud.install(); await cloud.goto(); await cloud.open();
  expect(cloud.reviewRequests).toEqual([]);
  await page.getByRole('button', { name: 'Show overview', exact: true }).click();
  const overview = page.locator('.conv-overview');
  await expect(overview).toContainText(cloud.branch);
  await expect(overview.getByTitle(cloud.device.gitHead)).toHaveText('HEADcccccccc');
  await expect(overview).not.toContainText(cloud.device.gitBaseline.slice(0, 8));
  await expect(overview.getByTitle('src/main.mbt')).toHaveText('Msrc/main.mbt');
  await expect(overview.getByTitle('src/lib.mbt')).toBeVisible();

  // Switching between two branches at the same commit still changes the overview.
  cloud.branch = 'feature/another-branch';
  cloud.device.gitChanges = [];
  await page.evaluate(session => window.cloudInvalidateFiles(session), sessionA);
  await expect(overview).toContainText(cloud.branch);
  await expect(overview).toContainText('No changed files.');
  await expect(overview).not.toContainText('src/main.mbt');

  cloud.branch = null;
  cloud.device.gitHead = cloud.device.gitParent;
  await cloud.open(sessionB);
  await expect(overview.getByTitle(cloud.device.gitHead)).toHaveText('HEADbbbbbbbb');
  await expect(overview).not.toContainText('feature/another-branch');
  expect(cloud.reviewRequests.some(r => r.session === sessionB && r.operation === 'history')).toBe(true);
  await expect(page.getByRole('button', { name: 'Show panel', exact: true })).toBeVisible();
});

test('a Cloud overview refresh keeps the selected review commit open after an ordinary edit', async ({ page }) => {
  const cloud = new CloudReviewHarness(page);
  await cloud.install(); await cloud.goto(); await cloud.openReview();
  await page.getByRole('button', { name: 'Show overview', exact: true }).click();
  const history = page.getByRole('tree', { name: 'Git commit history' });
  await history.getByRole('treeitem', { name: /Cover Desktop Git flows/ }).click();
  const commitFile = history.getByRole('treeitem', { name: /src\/main\.mbt/ });
  await expect(commitFile).toBeVisible();
  cloud.device.gitChanges = [];
  await page.evaluate(session => window.cloudInvalidateFiles(session), sessionA);
  await expect(page.locator('.conv-overview')).toContainText('No changed files.');
  await expect(commitFile).toBeVisible();
});

test('Cloud overview distinguishes an unborn branch, a non-repository and a failed read', async ({ page }) => {
  const cloud = new CloudReviewHarness(page);
  cloud.branch = 'main';
  cloud.device.gitHead = null;
  cloud.device.gitChanges = [];
  await cloud.install(); await cloud.goto(); await cloud.open();
  await page.getByRole('button', { name: 'Show overview', exact: true }).click();
  const overview = page.locator('.conv-overview');
  await expect(overview.getByTitle('main')).toBeVisible();
  await expect(overview).toContainText('No commits');
  await expect(overview).toContainText('No changed files.');

  cloud.repository = false;
  await page.evaluate(session => window.cloudInvalidateFiles(session), sessionA);
  await expect(overview).toContainText('not a Git repository');
  await expect(overview.getByTitle('main')).toHaveCount(0);

  cloud.reviewStatus = 403;
  await cloud.open(sessionB);
  await expect(overview).toContainText('HTTP 403');
  cloud.reviewStatus = 200; cloud.repository = true;
  await page.getByRole('button', { name: 'Hide overview', exact: true }).click();
  await page.getByRole('button', { name: 'Show overview', exact: true }).click();
  await expect(overview.getByTitle('main')).toBeVisible();
  await expect(overview).toContainText('No changed files.');
  await expect(overview).not.toContainText('HTTP 403');
});

import { test, expect } from './support/test.js';
import { CloudHarness, authOrigin, sessionA, sessionB } from './support/cloud_harness.js';

class CloudReviewHarness extends CloudHarness {
  constructor(page) {
    super(page);
    this.reviewRequests = [];
    this.repository = true;
    this.reviewStatus = 200;
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
      if (this.reviewStatus !== 200) return json({}, this.reviewStatus);
      const method = { changes: 'git.changes', 'original-file': 'git.original_file', history: 'git.history', 'commit-changes': 'git.commit_changes' }[operation];
      const reply = this.device.replyFor({ method, params: { ...body, session, workspace: '/workspace' } });
      if (operation === 'changes' || operation === 'history') reply.repository = this.repository;
      if (operation === 'changes' && !this.repository) reply.changes = [];
      if (operation === 'history' && !this.repository) reply.commits = [];
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
  expect(cloud.device.pageErrors).toEqual([]);
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
  expect(cloud.device.pageErrors).toEqual([]);
});

test('Cloud review reuses the non-Git notice and allows retry after an unavailable endpoint', async ({ page }) => {
  const cloud = new CloudReviewHarness(page);
  cloud.reviewStatus = 404;
  await cloud.install(); await cloud.goto(); await cloud.openReview();
  await expect(page.locator('#review-changes-body')).toContainText('Cloud answered HTTP 404');
  cloud.reviewStatus = 200; cloud.repository = false;
  await page.getByRole('tab', { name: /Changes/ }).click();
  await expect(page.locator('#review-changes-body')).toContainText('Git is unavailable or this workspace is not a Git repository.');
  expect(cloud.device.pageErrors).toEqual([]);
});

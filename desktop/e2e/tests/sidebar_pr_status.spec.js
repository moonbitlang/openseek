import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

const repo = 'https://github.com/moonbitlang/openseek';

function summary(number, state, { draft = false } = {}) {
  return {
    number,
    title: `Pull request ${number}`,
    state,
    draft,
    url: `${repo}/pull/${number}`,
    base: 'main',
    additions: 12,
    deletions: 4,
    changed_files: 2,
  };
}

function sidebarRow(page, title) {
  return page.locator('aside .conversation-row', {
    has: page.getByRole('button', { name: title, exact: true }),
  });
}

test('sidebar conversation rows render PR status badges with state colors and counts', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.liveSessions = [
    { id: 's-open', title: 'Open PR chat', updated_at_ms: 5000 },
    { id: 's-merged', title: 'Merged PR chat', updated_at_ms: 4000 },
    { id: 's-closed', title: 'Closed PR chat', updated_at_ms: 3000 },
    { id: 's-draft-multi', title: 'Draft multi chat', updated_at_ms: 2000 },
    { id: 's-merged-3', title: 'Three merged chat', updated_at_ms: 1000 },
    { id: 's-none', title: 'No PR chat', updated_at_ms: 500 },
  ];
  app.sessionArtifacts = {
    's-open': [{ type: 'pull_request', url: `${repo}/pull/10` }],
    's-merged': [{ type: 'pull_request', url: `${repo}/pull/11` }],
    's-closed': [{ type: 'pull_request', url: `${repo}/pull/12` }],
    's-draft-multi': [
      { type: 'pull_request', url: `${repo}/pull/13` },
      { type: 'pull_request', url: `${repo}/pull/14` },
      { type: 'branch', url: `${repo}/tree/ignored-branch` },
    ],
    's-merged-3': [
      { type: 'pull_request', url: `${repo}/pull/15` },
      { type: 'pull_request', url: `${repo}/pull/16` },
      { type: 'pull_request', url: `${repo}/pull/17` },
    ],
  };
  app.githubPullRequestSummaries = {
    [`${repo}/pull/10`]: summary(10, 'open'),
    [`${repo}/pull/11`]: summary(11, 'merged'),
    [`${repo}/pull/12`]: summary(12, 'closed'),
    [`${repo}/pull/13`]: summary(13, 'open', { draft: true }),
    [`${repo}/pull/14`]: summary(14, 'merged'),
    [`${repo}/pull/15`]: summary(15, 'merged'),
    [`${repo}/pull/16`]: summary(16, 'merged'),
    [`${repo}/pull/17`]: summary(17, 'merged'),
  };

  await app.install();
  await app.goto();

  // Single PR rows show colored icons with no numeric count.
  const openRow = sidebarRow(page, 'Open PR chat');
  await expect(openRow.locator('.row-pr-icon')).toHaveClass(/\bopen\b/);
  await expect(openRow.locator('.row-pr-count')).toHaveCount(0);

  const mergedRow = sidebarRow(page, 'Merged PR chat');
  await expect(mergedRow.locator('.row-pr-icon')).toHaveClass(/\bmerged\b/);
  await expect(mergedRow.locator('.row-pr-count')).toHaveCount(0);

  const closedRow = sidebarRow(page, 'Closed PR chat');
  await expect(closedRow.locator('.row-pr-icon')).toHaveClass(/\bclosed\b/);
  await expect(closedRow.locator('.row-pr-count')).toHaveCount(0);

  // Multi-PR rows show aggregate state and count (ignoring attached branches).
  const draftRow = sidebarRow(page, 'Draft multi chat');
  await expect(draftRow.locator('.row-pr-icon')).toHaveClass(/\bdraft\b/);
  await expect(draftRow.locator('.row-pr-count')).toHaveText('2');

  const merged3Row = sidebarRow(page, 'Three merged chat');
  await expect(merged3Row.locator('.row-pr-icon')).toHaveClass(/\bmerged\b/);
  await expect(merged3Row.locator('.row-pr-count')).toHaveText('3');

  // Expand past the 5-row project preview limit so the 6th session is visible.
  await page.getByRole('button', { name: 'Show more', exact: true }).click();

  // Sessions without attached PRs render no PR badge.
  const noneRow = sidebarRow(page, 'No PR chat');
  await expect(noneRow).toBeVisible();
  await expect(noneRow.locator('.row-pr-status')).toHaveCount(0);

  // Hovering reveals the overlaid overflow menu without shifting the title,
  // and cleanly swaps out the status badge.
  const idleTitleWidth = await mergedRow
    .locator('.conversation-open')
    .evaluate(el => el.getBoundingClientRect().width);
  await mergedRow.hover();
  await expect(mergedRow.locator('.row-menu-button')).toBeVisible();
  await expect(mergedRow.locator('.row-pr-status')).toBeHidden();
  const hoverTitleWidth = await mergedRow
    .locator('.conversation-open')
    .evaluate(el => el.getBoundingClientRect().width);
  expect(Math.abs(hoverTitleWidth - idleTitleWidth)).toBeLessThanOrEqual(0.5);

  // Live MCP attachment updates the sidebar badge immediately.
  app.sessionArtifacts['s-none'] = [{ type: 'pull_request', url: `${repo}/pull/99` }];
  app.githubPullRequestSummaries[`${repo}/pull/99`] = summary(99, 'open');
  app.notify('session.artifacts_changed', { session: 's-none' });
  await expect(noneRow.locator('.row-pr-icon')).toHaveClass(/\bopen\b/);

  // Batch endpoint was used rather than one request per PR.
  expect(app.requests.filter(r => r.method === 'github.pull_request_summaries').length).toBeGreaterThanOrEqual(1);
  expect(app.requests.filter(r => r.method === 'github.pull_request_summary')).toHaveLength(0);
  expect(app.pageErrors).toEqual([]);
});

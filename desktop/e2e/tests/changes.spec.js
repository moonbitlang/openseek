import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

const repo = 'https://github.com/moonbitlang/openseek';

function overview(page) {
  return page.locator('.conv-overview');
}

function changesCard(panel) {
  return panel.locator('[data-section="changes"]');
}

function requests(app, method) {
  return app.requests.filter(request => request.method === method);
}

async function showOverview(page) {
  await page.locator('.conv-overview-toggle').click();
  const panel = overview(page);
  await expect(panel).toBeVisible();
  return panel;
}

test('the changes card lists the checkout and what the agent attached, and removes an attachment', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await page.setViewportSize({ width: 1440, height: 900 });
  app.gitBranch = {
    branch: 'haoxiang/overview-changes',
    diffstat: { added: 120, removed: 8, files: 6, partial: false },
  };
  app.gitPullRequest = {
    branch: 'haoxiang/overview-changes',
    pull_request: {
      number: 2130,
      title: 'Add a changes card to the conversation overview',
      state: 'open',
      draft: false,
      url: `${repo}/pull/2130`,
      base: 'main',
      additions: 120,
      deletions: 8,
      changed_files: 6,
    },
  };
  app.sessionArtifacts['session-1'] = [
    // The checkout's own pull request, attached as well, is listed once.
    { type: 'pull_request', url: `${repo}/pull/2130` },
    { type: 'pull_request', url: `${repo}/pull/2119` },
    { type: 'branch', url: `${repo}/tree/codex/session-artifacts-ui` },
  ];
  // The host keeps only an attached pull request's address; GitHub has the
  // rest.
  app.githubPullRequestSummaries[`${repo}/pull/2119`] = {
    number: 2119,
    title: 'Show session artifacts with the current checkout',
    state: 'closed',
    draft: false,
    url: `${repo}/pull/2119`,
    base: 'main',
    additions: 1726,
    deletions: 358,
    changed_files: 33,
  };
  await app.install();
  await app.goto();
  await app.openSession();
  const panel = await showOverview(page);
  const card = changesCard(panel);
  const rows = card.locator('.conv-changes-row');

  // The checkout comes first, as its pull request; then the attachments in
  // the order the agent attached them. Each opens its page.
  await expect(rows).toHaveCount(3);
  const current = rows.nth(0);
  await expect(current.locator('.conv-changes-number')).toBeVisible();
  await expect(current.locator('.conv-changes-number')).toHaveText("#2130");
  await expect(current.locator('.conv-changes-name')).toBeVisible();
  await expect(current.locator('.conv-changes-name')).toHaveText("Add a changes card to the conversation overview");
  await expect(current.locator('.conv-overview-tag')).toBeVisible();
  await expect(current.locator('.conv-overview-tag')).toHaveText("Current");
  await expect(current.getByRole('link')).toHaveAttribute('href', `${repo}/pull/2130`);
  await expect(current.locator('.conv-changes-remove')).toHaveCount(0);
  await expect(rows.nth(1).locator('.conv-changes-number')).toBeVisible();
  await expect(rows.nth(1).locator('.conv-changes-number')).toHaveText("#2119");
  await expect(rows.nth(1).locator('.conv-changes-name')).toBeVisible();
  await expect(rows.nth(1).locator('.conv-changes-name')).toHaveText("Show session artifacts with the current checkout");
  await expect(rows.nth(1).getByRole('link')).toHaveAttribute('href', `${repo}/pull/2119`);
  await expect(rows.nth(1).locator('.conv-changes-icon')).toHaveClass(/\bclosed\b/);
  await expect(current.locator('.conv-changes-icon')).toHaveClass(/\bopen\b/);
  await expect(rows.nth(2).locator('.conv-changes-name')).toBeVisible();
  await expect(rows.nth(2).locator('.conv-changes-name')).toHaveText("codex/session-artifacts-ui");
  await expect(rows.nth(2).getByRole('link')).toHaveAttribute('href', `${repo}/tree/codex/session-artifacts-ui`);
  expect(requests(app, 'session.artifacts_list').map(request => request.params)).toEqual([{ session: 'session-1' }]);
  // Every attached pull request is looked up, the checkout's own included;
  // branches are not.
  expect(requests(app, 'github.pull_request_summary').map(request => request.params.url).sort()).toEqual([
    `${repo}/pull/2119`,
    `${repo}/pull/2130`,
  ]);

  // Folded, the card is its summary.
  await card.locator('.conv-overview-card-title').click();
  await expect(card.locator('.conv-overview-summary')).toBeVisible();
  await expect(card.locator('.conv-overview-summary')).toHaveText("2 PRs \u00b7 1 branch");
  await card.locator('.conv-overview-card-title').click();

  // Removing an attachment takes it off the conversation's list only.
  await rows.nth(1).hover();
  await rows.nth(1).locator('.conv-changes-remove').click();
  await expect(rows).toHaveCount(2);
  await expect(card.locator(`a[href="${repo}/pull/2119"]`)).toBeHidden();
  expect(requests(app, 'session.artifacts_remove').map(request => request.params)).toEqual([
    { session: 'session-1', artifact: { type: 'pull_request', url: `${repo}/pull/2119` } },
  ]);
  expect(app.pageErrors).toEqual([]);
});

test('the changes card appears when the agent attaches something to a conversation outside a repository', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  const panel = await showOverview(page);
  // No checkout to describe and nothing attached: no card.
  await expect.poll(() => requests(app, 'session.artifacts_list').length).toBe(1);
  await expect(panel.locator('[data-section="changes"] .conv-overview-card-title')).toHaveCount(0);

  // The host announces a saved change; the page reads the list again.
  app.sessionArtifacts['session-1'] = [{ type: 'pull_request', url: `${repo}/pull/2030` }];
  app.notify('session.artifacts_changed', { session: 'session-1' });
  const card = changesCard(panel);
  // GitHub has nothing to say about it, so it reads as its address.
  await expect(card.locator('.conv-changes-number')).toBeVisible();
  await expect(card.locator('.conv-changes-number')).toHaveText("#2030");
  await expect(card.locator('.conv-changes-name')).toBeVisible();
  await expect(card.locator('.conv-changes-name')).toHaveText("moonbitlang/openseek");
  expect(requests(app, 'session.artifacts_list')).toHaveLength(2);

  // Another session's change is not this card's business.
  app.notify('session.artifacts_changed', { session: 'another-session' });
  await page.waitForTimeout(200);
  expect(requests(app, 'session.artifacts_list')).toHaveLength(2);
  expect(app.pageErrors).toEqual([]);
});

test('a checkout without a pull request reads as its branch and local diff, marked when the count stopped short', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await page.setViewportSize({ width: 1440, height: 900 });
  app.gitBranch = {
    branch: 'haoxiang/unpublished',
    diffstat: { added: 42, removed: 3, files: 4, partial: true },
  };
  await app.install();
  await app.goto();
  await app.openSession();
  const panel = await showOverview(page);
  const current = changesCard(panel).locator('.conv-changes-row').first();
  await expect(current.locator('.conv-changes-name')).toBeVisible();
  await expect(current.locator('.conv-changes-name')).toHaveText("haoxiang/unpublished");
  await expect(current.locator('.conv-changes-diff .added')).toBeVisible();
  await expect(current.locator('.conv-changes-diff .added')).toHaveText("+42");
  await expect(current.locator('.conv-changes-diff .removed')).toBeVisible();
  await expect(current.locator('.conv-changes-diff .removed')).toHaveText("\u22123");
  // Untracked files past the host's limits were not counted: the totals are a
  // floor, and the row says so instead of presenting them as the whole size.
  await expect(current.locator('.conv-changes-diff')).toHaveAttribute('title', 'Some untracked files were not counted');
  await expect(current.getByRole('link')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('merged attached pull requests fold into one row that unfolds them', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await page.setViewportSize({ width: 1440, height: 900 });
  app.sessionArtifacts['session-1'] = [
    { type: 'pull_request', url: `${repo}/pull/2201` },
    { type: 'pull_request', url: `${repo}/pull/2202` },
    { type: 'pull_request', url: `${repo}/pull/2203` },
  ];
  const summary = (number, state) => ({
    number,
    title: `Pull request ${number}`,
    state,
    draft: false,
    url: `${repo}/pull/${number}`,
    base: 'main',
    additions: 1,
    deletions: 0,
    changed_files: 1,
  });
  app.githubPullRequestSummaries[`${repo}/pull/2201`] = summary(2201, 'open');
  app.githubPullRequestSummaries[`${repo}/pull/2202`] = summary(2202, 'merged');
  app.githubPullRequestSummaries[`${repo}/pull/2203`] = summary(2203, 'merged');
  await app.install();
  await app.goto();
  await app.openSession();
  const panel = await showOverview(page);
  const card = changesCard(panel);
  const rows = card.locator('.conv-changes-row');
  const fold = card.locator('.conv-changes-fold');

  // The open pull request keeps its row; the merged ones are one row.
  await expect(fold).toBeVisible();
  await expect(fold).toHaveAttribute('aria-expanded', 'false');
  await expect(rows).toHaveCount(2);
  await expect(card.locator(`a[href="${repo}/pull/2201"] .conv-changes-name`)).toBeVisible();
  await expect(card.locator(`a[href="${repo}/pull/2201"] .conv-changes-name`)).toHaveText('Pull request 2201');
  await expect(card.locator(`a[href="${repo}/pull/2202"] .conv-changes-name`)).toHaveCount(0);

  await fold.click();
  await expect(fold).toHaveAttribute('aria-expanded', 'true');
  await expect(rows).toHaveCount(4);
  await expect(card.locator(`a[href="${repo}/pull/2202"] .conv-changes-name`)).toBeVisible();
  await expect(card.locator(`a[href="${repo}/pull/2202"] .conv-changes-name`)).toHaveText('Pull request 2202');
  await expect(card.locator(`a[href="${repo}/pull/2203"] .conv-changes-name`)).toBeVisible();
  await expect(card.locator(`a[href="${repo}/pull/2203"] .conv-changes-name`)).toHaveText('Pull request 2203');

  await fold.click();
  await expect(rows).toHaveCount(2);

  // One button takes every merged pull request off the conversation's list.
  const foldRow = rows.filter({ has: page.locator('.conv-changes-fold') });
  await foldRow.hover();
  await foldRow.locator('.conv-changes-remove').click();
  await expect(fold).toHaveCount(0);
  await expect(rows).toHaveCount(1);
  await expect(card.locator(`a[href="${repo}/pull/2201"] .conv-changes-name`)).toBeVisible();
  await expect(card.locator(`a[href="${repo}/pull/2201"] .conv-changes-name`)).toHaveText('Pull request 2201');
  expect(requests(app, 'session.artifacts_remove').map(request => request.params.artifact.url).sort()).toEqual([
    `${repo}/pull/2202`,
    `${repo}/pull/2203`,
  ]);
  expect(app.pageErrors).toEqual([]);
});

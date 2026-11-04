import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

const repo = 'https://github.com/moonbitlang/openseek';

function overview(page) {
  return page.getByRole('complementary', { name: 'Overview' });
}

function changesCard(panel) {
  return panel.locator('.conv-overview-card', {
    has: panel.page().getByRole('button', { name: 'Changes', exact: true }),
  });
}

function requests(app, method) {
  return app.requests.filter(request => request.method === method);
}

async function showOverview(page) {
  await page.getByRole('button', { name: 'Show overview', exact: true }).click();
  const panel = overview(page);
  await expect(panel).toBeVisible();
  return panel;
}

test('the changes card lists the checkout and what the agent attached, and removes an attachment', async ({ page }, testInfo) => {
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
      checks: { passed: 8, failed: 1, pending: 0 },
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

  // The checkout comes first, as its pull request: its title over its
  // repository, number and GitHub's line totals, with its checks. Then the
  // attachments in the order the agent attached them. Each opens its page.
  await expect(rows).toHaveCount(3);
  const current = rows.nth(0);
  await expect(current.getByText('Add a changes card to the conversation overview')).toBeVisible();
  await expect(current.getByText('#2130', { exact: true })).toBeVisible();
  await expect(current.getByText('+120', { exact: true })).toBeVisible();
  await expect(current.getByText('−8', { exact: true })).toBeVisible();
  await expect(current.getByText('Current', { exact: true })).toBeVisible();
  await expect(current.locator('.conv-changes-link')).toHaveAttribute('href', `${repo}/pull/2130`);
  const checks = current.getByRole('link', { name: 'CI · 1 failed · 8 passed' });
  await expect(checks).toHaveText('1 failing');
  await expect(checks).toHaveAttribute('href', `${repo}/pull/2130/checks`);
  await expect(rows.nth(1).getByText('Show session artifacts with the current checkout', { exact: true })).toBeVisible();
  await expect(rows.nth(1).getByText('#2119', { exact: true })).toBeVisible();
  await expect(rows.nth(1).getByText('+1726', { exact: true })).toBeVisible();
  await expect(rows.nth(1).locator('.conv-changes-link')).toHaveAttribute('href', `${repo}/pull/2119`);
  await expect(rows.nth(1).locator('.conv-changes-icon')).toHaveClass(/\bclosed\b/);
  await expect(current.locator('.conv-changes-icon')).toHaveClass(/\bopen\b/);
  await expect(rows.nth(2).getByText('codex/session-artifacts-ui', { exact: true })).toBeVisible();
  await expect(rows.nth(2).getByText('moonbitlang/openseek', { exact: true })).toBeVisible();
  await expect(rows.nth(2).locator('.conv-changes-link')).toHaveAttribute('href', `${repo}/tree/codex/session-artifacts-ui`);
  await page.screenshot({ path: testInfo.outputPath('changes.png') });
  expect(requests(app, 'session.artifacts_list').map(request => request.params)).toEqual([{ session: 'session-1' }]);
  // Every attached pull request is looked up, the checkout's own included;
  // branches are not.
  expect(requests(app, 'github.pull_request_summary').map(request => request.params.url).sort()).toEqual([
    `${repo}/pull/2119`,
    `${repo}/pull/2130`,
  ]);

  // Folded, the card is its summary.
  await card.getByRole('button', { name: 'Changes', exact: true }).click();
  await expect(card.getByText('2 PRs · 1 branch', { exact: true })).toBeVisible();
  await card.getByRole('button', { name: 'Changes', exact: true }).click();

  // The checkout's menu opens and copies its pull request; it cannot be
  // removed.
  await current.getByRole('button', { name: 'More actions' }).click();
  await expect(page.getByRole('menuitem', { name: 'Open on GitHub', exact: true })).toBeVisible();
  await expect(page.getByRole('menuitem', { name: 'Copy link', exact: true })).toBeVisible();
  await expect(page.getByRole('menuitem', { name: 'Remove from this conversation' })).toHaveCount(0);
  await page.keyboard.press('Escape');

  // Removing an attachment takes it off the conversation's list only.
  await rows.nth(1).getByRole('button', { name: 'More actions' }).click();
  await page.getByRole('menuitem', { name: 'Remove from this conversation' }).click();
  await expect(rows).toHaveCount(2);
  await expect(card.getByText('#2119', { exact: true })).toBeHidden();
  expect(requests(app, 'session.artifacts_remove').map(request => request.params)).toEqual([
    { session: 'session-1', artifact: { type: 'pull_request', url: `${repo}/pull/2119` } },
  ]);
  expect(app.pageErrors).toEqual([]);
});

test('the changes card appears when the agent attaches something to a conversation outside a repository', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  const panel = await showOverview(page);
  // No checkout to describe and nothing attached: no card.
  await expect.poll(() => requests(app, 'session.artifacts_list').length).toBe(1);
  await expect(panel.getByRole('button', { name: 'Changes', exact: true })).toHaveCount(0);

  // The host announces a saved change; the page reads the list again.
  app.sessionArtifacts['session-1'] = [{ type: 'pull_request', url: `${repo}/pull/2030` }];
  app.notify('session.artifacts_changed', { session: 'session-1' });
  const card = changesCard(panel);
  // GitHub has nothing to say about it, so it reads as its address.
  await expect(card.getByText('#2030', { exact: true })).toBeVisible();
  await expect(card.locator('.conv-changes-checks')).toHaveCount(0);
  await expect(card.getByText('moonbitlang/openseek', { exact: true })).toBeVisible();
  expect(requests(app, 'session.artifacts_list')).toHaveLength(2);
  await page.screenshot({ path: testInfo.outputPath('changes-attached.png') });

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
  await expect(current.getByText('haoxiang/unpublished', { exact: true })).toBeVisible();
  await expect(current.getByText('+42', { exact: true })).toBeVisible();
  await expect(current.getByText('−3', { exact: true })).toBeVisible();
  // Untracked files past the host's limits were not counted: the totals are a
  // floor, and the row says so instead of presenting them as the whole size.
  await expect(current.locator('.conv-changes-meta .partial')).toHaveAttribute('title', 'Some untracked files were not counted');
  await expect(current.locator('.conv-changes-link')).not.toHaveAttribute('href', /./);
  await expect(current.getByRole('button', { name: 'More actions' })).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('a published branch without a pull request offers to create one', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.gitBranch = {
    branch: 'haoxiang/ready',
    diffstat: { added: 258, removed: 97, files: 9, partial: false },
  };
  app.gitPullRequest = {
    branch: 'haoxiang/ready',
    compare_url: `${repo}/compare/haoxiang/ready?expand=1`,
  };
  await app.install();
  await app.goto();
  await app.openSession();
  const panel = await showOverview(page);
  const current = changesCard(panel).locator('.conv-changes-row').first();
  await expect(current.getByText('+258', { exact: true })).toBeVisible();
  await expect(current.getByRole('link', { name: 'Create PR' })).toHaveAttribute(
    'href',
    `${repo}/compare/haoxiang/ready?expand=1`,
  );
  expect(app.pageErrors).toEqual([]);
});

test('past five rows the rest of the changes wait behind show more', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.sessionArtifacts['session-1'] = [1, 2, 3, 4, 5, 6, 7].map(number => ({
    type: 'pull_request',
    url: `${repo}/pull/${number}`,
  }));
  await app.install();
  await app.goto();
  await app.openSession();
  const panel = await showOverview(page);
  const card = changesCard(panel);
  const rows = card.locator('.conv-changes-row');
  await expect(rows).toHaveCount(5);
  await card.getByRole('button', { name: 'Show 2 more' }).click();
  await expect(rows).toHaveCount(7);
  await card.getByRole('button', { name: 'Show less' }).click();
  await expect(rows).toHaveCount(5);
  expect(app.pageErrors).toEqual([]);
});

test('a row menu closes when the overview scrolls its row away', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await page.setViewportSize({ width: 1440, height: 420 });
  app.sessionArtifacts['session-1'] = [1, 2, 3, 4, 5, 6, 7].map(number => ({
    type: 'pull_request',
    url: `${repo}/pull/${number}`,
  }));
  await app.install();
  await app.goto();
  await app.openSession();
  const panel = await showOverview(page);
  const card = changesCard(panel);
  await card.getByRole('button', { name: 'Show 2 more' }).click();
  const rows = card.locator('.conv-changes-row');
  await rows.nth(1).getByRole('button', { name: 'More actions' }).click();
  const remove = page.getByRole('menuitem', { name: 'Remove from this conversation' });
  await expect(remove).toBeVisible();
  await panel.evaluate(element => {
    element.scrollTop += 120;
  });
  await expect(remove).toHaveCount(0);

  // Switching straight to another row's menu binds the dismissal to that row,
  // even once the first row is gone.
  await panel.evaluate(element => {
    element.scrollTop = 0;
  });
  await rows.nth(1).getByRole('button', { name: 'More actions' }).click();
  await expect(remove).toBeVisible();
  await rows.nth(0).getByRole('button', { name: 'More actions' }).click();
  await expect(page.getByRole('menu')).toHaveCount(1);
  await expect(remove).toBeVisible();
  // Another client replaces the second row's item; the list keeps its
  // height, so nothing scrolls.
  const [first, , ...rest] = app.sessionArtifacts['session-1'];
  app.sessionArtifacts['session-1'] = [
    first,
    { type: 'pull_request', url: `${repo}/pull/99` },
    ...rest,
  ];
  app.notify('session.artifacts_changed', { session: 'session-1' });
  await expect(rows.nth(1).getByText('#99', { exact: true })).toBeVisible();
  await expect(remove).toBeVisible();
  await panel.evaluate(element => {
    element.scrollTop += 120;
  });
  await expect(remove).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

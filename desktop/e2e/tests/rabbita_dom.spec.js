import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('desktop browser shell opens the active conversation controls', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();

  await app.openSession();
  await expect(page.locator('.transcript')).toBeVisible();
  await expect(page.locator('.composer-input')).toBeVisible();
  await expect(page.locator('#task')).toBeEditable();
  expect(app.pageErrors).toEqual([]);
});

test('workspace search mounts its real tablist, focus target, and option controls', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();

  const shortcut = await page.evaluate(() =>
    navigator.platform.includes('Mac') ? 'Meta+Shift+F' : 'Control+Shift+F');
  await page.keyboard.press(shortcut);

  const tabs = page.getByRole('tablist', { name: 'Explorer views' });
  await expect(tabs.getByRole('tab')).toHaveCount(3);
  const filesTab = tabs.locator('#explorer-files-tab');
  const searchTab = tabs.locator('#explorer-search-tab');
  await expect(searchTab).toHaveAttribute('aria-selected', 'true');

  const query = page.getByRole('textbox', { name: 'Search' });
  await expect(query).toBeFocused();
  await expect(query).toHaveAttribute('data-focus-owner', '');

  const wholeWord = page.getByRole('button', { name: 'Match Whole Word' });
  await expect(wholeWord.locator('svg')).toBeVisible();
  await expect(wholeWord).toHaveAttribute('aria-pressed', 'false');
  await wholeWord.click();
  await expect(wholeWord).toHaveAttribute('aria-pressed', 'true');

  await searchTab.focus();
  await page.keyboard.press('ArrowRight');
  await expect(filesTab).toBeFocused();
  await expect(filesTab).toHaveAttribute('aria-selected', 'true');
  await page.keyboard.press('End');
  await expect(searchTab).toHaveAttribute('aria-selected', 'true');
  await expect(query).toBeFocused();
  expect(app.pageErrors).toEqual([]);
});

test('workspace search groups UTF-16 matches and reveals a large reply incrementally', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.textSearchMatches = Array.from({ length: 501 }, (_, index) => ({
    path: 'src/main.mbt',
    line_number: index + 1,
    preview: index === 0 ? '😀 moon' : `moon result ${index + 1}`,
    preview_start_column: 1,
    // Search columns are one-based UTF-16 offsets. The emoji occupies two
    // code units, so "moon" starts at column four rather than three.
    ranges: [{ start_column: index === 0 ? 4 : 1, end_column: index === 0 ? 8 : 5 }],
  }));
  app.textSearchLimitHit = true;
  await app.install();
  await app.goto();

  const shortcut = await page.evaluate(() =>
    navigator.platform.includes('Mac') ? 'Meta+Shift+F' : 'Control+Shift+F');
  await page.keyboard.press(shortcut);
  const query = page.getByRole('textbox', { name: 'Search' });
  await query.fill('moon');
  await query.press('Enter');

  await expect.poll(() => app.requests.find(request => request.method === 'fs.search_text'))
    .toMatchObject({
      params: {
        root: '/workspace',
        query: 'moon',
      },
    });
  const results = page.locator('.search-results');
  await expect(results.locator('.search-summary')).toHaveText('501 results in 1 files');
  await expect(results.locator('.search-file-name')).toHaveText('main.mbt');
  await expect(results.locator('.search-file-parent')).toHaveText('src');
  await expect(results.locator('.search-match-highlight').first()).toHaveText('moon');
  await expect(results.getByRole('status')).toContainText('first 20,000 matches');
  await expect(results.locator('.search-result-row')).toHaveCount(500);
  await expect(results.locator('.search-show-more-detail')).toHaveText(
    '500 of 501 matching lines rendered',
  );

  await results.getByRole('button', { name: 'Show 1 more matching lines' }).click();
  await expect(results.locator('.search-result-row')).toHaveCount(501);
  await expect(results.locator('.search-show-more')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('Review loads changed files and preserves its interactive diff workflow', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openReview();

  await expect.poll(() => app.requests.find(request => request.method === 'git.changes'))
    .toMatchObject({
      params: {
        session: 'session-1',
        workspace: '/workspace',
      },
    });
  const changes = page.locator('#review-changes-body');
  await expect(changes.locator('.review-progress-summary')).toHaveText(
    '0 of 2 reviewable files reviewed',
  );
  const main = changes.getByRole('button', { name: /View diff: src\/main\.mbt/ });
  const library = changes.getByRole('button', { name: /View diff: src\/lib\.mbt/ });
  await expect(main).toHaveAttribute('aria-current', 'false');
  await main.click();

  await expect.poll(() => app.requests.find(request =>
    request.method === 'fs.read_file' && request.params?.path === '/workspace/src/main.mbt'))
    .toBeTruthy();
  await expect.poll(() => app.requests.find(request =>
    request.method === 'git.original_file' &&
    request.params?.path === 'src/main.mbt' &&
    request.params?.revision === app.gitBaseline))
    .toBeTruthy();
  const reviewToolbar = page.getByRole('toolbar', { name: 'Review mode' });
  await expect(reviewToolbar.getByRole('button', { name: 'Line diff' })).toHaveAttribute(
    'aria-pressed',
    'true',
  );
  await expect(page.locator('#viewer-host')).toHaveClass(/moonbit-viewer-surface-hidden/);
  await expect(page.locator('#diff-editor-host')).not.toHaveClass(/moonbit-viewer-surface-hidden/);
  await expect(page.locator('#semantic-review-host')).toHaveClass(
    /moonbit-viewer-surface-hidden/,
  );

  // Line diff keeps semantic-only filters inert. Token and Tree switch to the
  // real semantic surface without replacing any of the stable editor hosts.
  const ignoreComments = page.getByRole('button', { name: 'Ignore comments' });
  const ignoreTests = page.getByRole('button', { name: 'Ignore tests' });
  await expect(ignoreComments).toBeDisabled();
  await expect(ignoreTests).toBeDisabled();

  await reviewToolbar.getByRole('button', { name: 'File view' }).click();
  await expect(reviewToolbar.getByRole('button', { name: 'File view' })).toHaveAttribute(
    'aria-pressed',
    'true',
  );
  await expect(page.locator('#viewer-host')).not.toHaveClass(/moonbit-viewer-surface-hidden/);
  await reviewToolbar.getByRole('button', { name: 'Line diff' }).click();

  await reviewToolbar.getByRole('button', { name: 'Token diff' }).click();
  await expect(reviewToolbar.getByRole('button', { name: 'Token diff' })).toHaveAttribute(
    'aria-pressed',
    'true',
  );
  await expect(page.locator('#diff-editor-host')).toHaveClass(/moonbit-viewer-surface-hidden/);
  const semanticReview = page.locator('#semantic-review-host');
  await expect(semanticReview).not.toHaveClass(/moonbit-viewer-surface-hidden/);
  await expect(semanticReview.locator('.semantic-review')).toHaveAttribute('data-mode', 'token');
  await expect(ignoreComments).toHaveAttribute('aria-pressed', 'true');
  await expect(ignoreTests).toHaveAttribute('aria-pressed', 'true');
  await ignoreComments.click();
  await ignoreTests.click();
  await expect(ignoreComments).toHaveAttribute('aria-pressed', 'false');
  await expect(ignoreTests).toHaveAttribute('aria-pressed', 'false');

  await reviewToolbar.getByRole('button', { name: 'Tree diff' }).click();
  await expect(reviewToolbar.getByRole('button', { name: 'Tree diff' })).toHaveAttribute(
    'aria-pressed',
    'true',
  );
  await expect(semanticReview.locator('.semantic-review')).toHaveAttribute('data-mode', 'tree');

  await reviewToolbar.getByRole('button', { name: 'Line diff' }).click();
  await expect(page.locator('#diff-editor-host')).not.toHaveClass(/moonbit-viewer-surface-hidden/);
  await expect(semanticReview).toHaveClass(/moonbit-viewer-surface-hidden/);
  const layout = page.getByRole('group', { name: 'Diff layout' });
  await layout.getByRole('button', { name: 'Unified diff layout' }).click();
  await expect(layout.getByRole('button', { name: 'Unified diff layout' })).toHaveAttribute(
    'aria-pressed',
    'true',
  );

  const progress = page.getByRole('button', { name: 'Mark file reviewed' });
  await progress.click();
  await expect(progress).toHaveAttribute('aria-pressed', 'true');
  await expect(changes.locator('.review-progress-summary')).toHaveText(
    '1 of 2 reviewable files reviewed',
  );
  await page.getByRole('button', { name: 'Next changed file' }).click();
  await expect(library).toHaveAttribute('aria-current', 'page');
  await expect(page.locator('.review-nav-position')).toHaveText('2 of 2');
  await expect.poll(() => app.requests.find(request =>
    request.method === 'git.original_file' &&
    request.params?.path === 'src/lib.mbt' &&
    request.params?.revision === app.gitBaseline))
    .toBeTruthy();
  expect(app.pageErrors).toEqual([]);
});

test('Review routes Markdown source and keeps non-MoonBit comparisons on Line diff', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  const path = 'docs/Guide.MD';
  app.gitChanges = [{
    path,
    index_status: ' ',
    worktree_status: 'M',
    kind: 'modified',
  }];
  app.workingFiles[path] = '# Guide\n\nWorking tree documentation.\n';
  app.gitFilesByRevision[app.gitBaseline][path] = '# Guide\n\nBaseline documentation.\n';

  await app.install();
  await app.goto();
  await app.openSession();
  await app.openReview();

  await page.getByRole('button', { name: /View diff: docs\/Guide\.MD/ }).click();
  const toolbar = page.getByRole('toolbar', { name: 'Review mode' });
  await expect(toolbar.getByRole('button')).toHaveText(['File', 'Line']);
  await expect(toolbar.getByRole('button', { name: 'Line diff' })).toHaveAttribute(
    'aria-pressed',
    'true',
  );
  await expect(page.locator('#diff-editor-host')).not.toHaveClass(
    /moonbit-viewer-surface-hidden/,
  );
  await expect(page.locator('#semantic-review-host')).toHaveClass(
    /moonbit-viewer-surface-hidden/,
  );
  await expect(page.getByRole('button', { name: 'Ignore comments' })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Ignore tests' })).toHaveCount(0);

  await toolbar.getByRole('button', { name: 'File view' }).click();
  await expect(page.locator('#viewer-host')).toHaveClass(/moonbit-viewer-surface-hidden/);
  await expect(page.locator('#markdown-viewer-host')).not.toHaveClass(
    /moonbit-viewer-surface-hidden/,
  );
  await expect(page.locator('#markdown-viewer-host')).toContainText(
    'Working tree documentation.',
  );

  await toolbar.getByRole('button', { name: 'Line diff' }).click();
  await expect(page.locator('#markdown-viewer-host')).toHaveClass(
    /moonbit-viewer-surface-hidden/,
  );
  await expect(page.locator('#diff-editor-host')).not.toHaveClass(
    /moonbit-viewer-surface-hidden/,
  );
  expect(app.pageErrors).toEqual([]);
});

test('Review shields a pending diff before showing its delayed loading notice', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.rpcDelays.set('git.original_file', 1_200);
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openReview();

  await page.getByRole('button', { name: /View diff: src\/main\.mbt/ }).click();
  await expect(page.locator('#viewer-host')).toHaveClass(/moonbit-viewer-surface-hidden/);
  await expect(page.locator('#diff-editor-host')).not.toHaveClass(
    /moonbit-viewer-surface-hidden/,
  );
  const notice = page.locator('.viewer-notice');
  await expect(notice).toHaveClass(/diff-transition-shield/);
  expect(await notice.textContent()).toBe('');
  await expect(notice).toHaveText('Loading diff for main.mbt…', { timeout: 1_000 });
  await expect(notice).toHaveClass(/hidden/, { timeout: 3_000 });
  expect(app.pageErrors).toEqual([]);
});

test('semantic Review renders sectioned, fallback, and empty states in the browser', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  const semanticSources = {
    'src/sections.mbt': {
      baseline: [
        'fn kept() { println("KEPT_OLD_BODY") }',
        'fn removed() { println("DELETED_SOURCE_BODY") }',
      ].join('\n'),
      working: [
        'fn inserted() { println("INSERTED_SOURCE_BODY") }',
        'fn kept() { println("KEPT_NEW_BODY") }',
      ].join('\n'),
    },
    'src/reordered.mbt': {
      baseline: 'fn first() {}\nfn second() {}',
      working: 'fn second() {}\nfn first() {}',
    },
    'src/fallback.mbt': {
      baseline: 'fn broken( {',
      working: 'fn okay() {}',
    },
    'src/ignored.mbt': {
      baseline: '/// old documentation\nfn value() -> Int { 1 }',
      working: '/// new documentation\nfn value() -> Int { 1 }',
    },
    'src/structural.mbt': {
      baseline: 'fn value() { 1 }',
      working: 'fn value() {\n  1\n}',
    },
    // A host can briefly report a stale changed row after contents converge.
    // The browser must render a safe empty state instead of allocating editors.
    'src/identical.mbt': {
      baseline: 'fn same() {}',
      working: 'fn same() {}',
    },
  };
  app.gitChanges = [];
  for (const [path, sources] of Object.entries(semanticSources)) {
    app.workingFiles[path] = sources.working;
    app.gitFilesByRevision[app.gitBaseline][path] = sources.baseline;
    app.gitChanges.push({
      path,
      index_status: ' ',
      worktree_status: 'M',
      kind: 'modified',
    });
  }

  await app.install();
  await app.goto();
  await app.openSession();
  await app.openReview();

  const changes = page.locator('#review-changes-body');
  await expect(changes.locator('.review-progress-summary')).toHaveText(
    '0 of 6 reviewable files reviewed',
  );
  const reviewToolbar = page.getByRole('toolbar', { name: 'Review mode' });
  const tokenDiff = reviewToolbar.getByRole('button', { name: 'Token diff' });
  const treeDiff = reviewToolbar.getByRole('button', { name: 'Tree diff' });
  const semanticHost = page.locator('#semantic-review-host');
  const semanticReview = semanticHost.locator('.semantic-review');

  const sectionsChange = changes.getByRole('button', {
    name: /View diff: src\/sections\.mbt/,
  });
  await sectionsChange.click();
  await tokenDiff.click();
  await expect(semanticHost).not.toHaveClass(/moonbit-viewer-surface-hidden/);
  await expect(semanticReview).toHaveAttribute('data-mode', 'token');
  const entries = semanticReview.locator('.semantic-diff-entry');
  await expect(entries).toHaveCount(3);
  await expect(entries.locator('.semantic-entry-status')).toHaveText(['A', 'D']);
  const editorHosts = semanticReview.locator('.semantic-diff-editor-host');
  await expect(editorHosts).toHaveCount(3);
  await expect.poll(() => editorHosts.evaluateAll(nodes =>
    nodes.every(node => node.childElementCount > 0))).toBe(true);
  const hostIds = await editorHosts.evaluateAll(nodes => nodes.map(node => node.id));
  expect(hostIds.every(id => id.startsWith('semantic-diff-editor-'))).toBe(true);
  expect(new Set(hostIds).size).toBe(hostIds.length);
  await expect(semanticReview.locator('table')).toHaveCount(0);
  await expect(semanticReview.locator('.diff-scroll')).toHaveCount(0);
  await expect(semanticReview.locator('#semantic-review-scroll-width')).toHaveCount(1);

  const layout = page.getByRole('group', { name: 'Diff layout' });
  await layout.getByRole('button', { name: 'Unified diff layout' }).click();
  await expect(semanticReview).toHaveAttribute('data-layout', 'unified');
  const firstEntry = entries.first();
  const collapse = firstEntry.getByRole('button', { name: /Collapse/ });
  await expect(collapse).toHaveAttribute('aria-expanded', 'true');
  await collapse.click();
  await expect(firstEntry.getByRole('button', { name: /Expand/ })).toHaveAttribute(
    'aria-expanded',
    'false',
  );
  await expect(firstEntry).toHaveClass(/collapsed/);

  await changes.getByRole('button', { name: /View diff: src\/ignored\.mbt/ }).click();
  await expect(semanticReview.locator('.semantic-empty')).toHaveText(
    'No changes besides ignored comments, blank lines, or test blocks were found. Turn off the relevant Ignore filter to view them.',
  );
  await expect(semanticReview.locator('.semantic-diff-editor-host')).toHaveCount(0);
  await sectionsChange.click();
  await expect(semanticReview).toHaveAttribute('data-layout', 'unified');

  await changes.getByRole('button', { name: /View diff: src\/reordered\.mbt/ }).click();
  await treeDiff.click();
  await expect(semanticReview).toHaveAttribute('data-mode', 'tree');
  await expect(semanticReview.locator('.semantic-reorder')).toHaveText(
    'Top-level declarations are reordered; each declaration keeps its own DiffEditor.',
  );
  await expect(semanticReview.locator('.semantic-diff-editor-host')).toHaveCount(0);

  await changes.getByRole('button', { name: /View diff: src\/fallback\.mbt/ }).click();
  const fallback = semanticReview.locator('.diff-notice.fallback');
  await expect(fallback.locator('strong')).toHaveText('Lexical fallback');
  await expect(fallback.locator('span')).toHaveText(/.+/);
  await expect(semanticReview.getByText('Whole file', { exact: true })).toBeVisible();
  await expect(semanticReview.locator('#semantic-diff-editor-whole')).toHaveCount(1);
  await expect.poll(() => semanticReview.locator('#semantic-diff-editor-whole').evaluate(
    node => node.childElementCount,
  )).toBeGreaterThan(0);

  await changes.getByRole('button', { name: /View diff: src\/structural\.mbt/ }).click();
  await expect(semanticReview.locator('.semantic-empty')).toHaveText(
    'No structural changes found. Switch to Token to view text changes.',
  );
  await expect(semanticReview.locator('.semantic-diff-editor-host')).toHaveCount(0);

  await changes.getByRole('button', { name: /View diff: src\/identical\.mbt/ }).click();
  await tokenDiff.click();
  await expect(semanticReview.locator('.semantic-empty')).toHaveText('No token changes found.');
  await expect(semanticReview.locator('.semantic-diff-editor-host')).toHaveCount(0);
  await expect(page.getByText(/Malformed reply from/)).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('Git history expands commits and opens an immutable historical diff', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openReview();

  await expect.poll(() => app.requests.find(request => request.method === 'git.history'))
    .toMatchObject({
      params: {
        session: 'session-1',
        workspace: '/workspace',
        skip: 0,
        limit: 50,
      },
    });
  await expect(page.locator('.git-graph-branch')).toContainText('codex/browser-fixture');
  const history = page.getByRole('tree', { name: 'Git commit history' });
  const head = history.getByRole('treeitem', { name: /Cover Desktop Git flows/ });
  const merge = history.getByRole('treeitem', { name: /Merge fixture lanes/ });
  const parent = history.getByRole('treeitem', { name: /Add Review surface/ });
  await expect(merge.locator('.git-graph-node-merge-outer')).toHaveCount(1);
  await expect(merge.locator('.git-graph-node-merge-inner')).toHaveCount(1);
  expect(await merge.locator('.git-graph-cell path').count()).toBeGreaterThan(0);
  await head.focus();
  await page.keyboard.press('ArrowDown');
  await expect(merge).toBeFocused();
  await page.keyboard.press('ArrowDown');
  await expect(parent).toBeFocused();
  await page.keyboard.press('Home');
  await expect(head).toBeFocused();
  await page.keyboard.press('Enter');

  await expect.poll(() => app.requests.find(request =>
    request.method === 'git.commit_changes' && request.params?.commit === app.gitHead))
    .toMatchObject({
      params: {
        session: 'session-1',
        workspace: '/workspace',
        commit: app.gitHead,
      },
    });
  await expect(head).toHaveAttribute('aria-expanded', 'true');
  const historicalMain = history.getByRole('treeitem', { name: /src\/main\.mbt/ });
  await expect(historicalMain).toContainText('M');
  await historicalMain.click();
  await expect(historicalMain).toHaveClass(/selected/);
  await expect(historicalMain).toHaveAttribute('aria-current', 'page');

  await expect.poll(() => app.requests.filter(request =>
    request.method === 'git.original_file' &&
    request.params?.path === 'src/main.mbt' &&
    [app.gitMerge, app.gitHead].includes(request.params?.revision)).length)
    .toBe(2);
  await expect(page.locator('.editor-tab.active')).toContainText('main.mbt (cccccccc)');
  const breadcrumb = page.locator('.history-breadcrumb');
  await expect(breadcrumb.locator('.history-commit-crumb')).toHaveText('cccccccc');
  await expect(breadcrumb.locator('.crumb-file')).toHaveText('src/main.mbt');
  const algorithms = page.getByRole('toolbar', { name: 'Comparison algorithm' });
  await expect(algorithms.getByRole('button', { name: 'Line diff' })).toHaveAttribute(
    'aria-pressed',
    'true',
  );
  await expect(algorithms.getByRole('button')).toHaveText(['Line', 'Token', 'Tree']);
  await expect(page.getByRole('button', { name: 'Ignore comments' })).toBeDisabled();
  await expect(page.getByRole('button', { name: 'Ignore tests' })).toBeDisabled();
  await expect(page.locator('#diff-editor-host')).not.toHaveClass(/moonbit-viewer-surface-hidden/);
  await expect(page.locator('#semantic-review-host')).toHaveClass(
    /moonbit-viewer-surface-hidden/,
  );
  expect(app.pageErrors).toEqual([]);
});

test('Git history and commit failures retry through the browser transport', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.rpcErrors.set('git.history', 'unknown command');
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openReview({ waitForHistory: false });

  await expect(page.getByText(/Could not load Git history:.*unknown command/)).toBeVisible();
  app.rpcErrors.delete('git.history');
  await page.getByRole('button', { name: 'Retry' }).click();
  const history = page.getByRole('tree', { name: 'Git commit history' });
  const head = history.getByRole('treeitem', { name: /Cover Desktop Git flows/ });
  await expect(head).toBeVisible();
  await expect.poll(() => app.requests.filter(request =>
    request.method === 'git.history').length).toBe(2);

  app.rpcErrors.set('git.commit_changes', 'object unavailable');
  await head.click();
  const commitFailure = page.locator('.git-commit-files-message.error');
  await expect(commitFailure).toContainText(
    'Could not load this commit: object unavailable.',
  );
  app.rpcErrors.delete('git.commit_changes');
  await commitFailure.getByRole('button', { name: 'Retry' }).click();
  await expect(
    history.getByRole('treeitem', { name: /src\/main\.mbt/ }),
  ).toBeVisible();
  await expect.poll(() => app.requests.filter(request =>
    request.method === 'git.commit_changes').length).toBe(2);
  expect(app.pageErrors).toEqual([]);
});

test('project picker and quick open use browser focus and keyboard events', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();

  await page.getByRole('button', { name: 'Add a project' }).click();
  const picker = page.getByRole('dialog', { name: 'Add a project' });
  await expect(picker).toBeVisible();
  await expect(picker.locator('.picker-list')).toContainText('Projects');
  await expect(picker.locator('.picker-list')).toContainText('Workspace');
  await page.getByRole('button', { name: 'Close project picker' }).click();
  await expect(picker).toBeHidden();

  await app.openSession();
  await app.openQuickOpen();
  const input = page.locator('#quick-open-input');
  await expect(input).toBeFocused();
  await input.fill('main');
  const mainResult = page.getByRole('option', { name: /main\.mbt/ });
  await expect(mainResult).toBeVisible();
  await expect(mainResult).toHaveAttribute('aria-selected', 'true');
  await page.keyboard.press('Escape');
  await expect(input).toBeHidden();
  expect(app.pageErrors).toEqual([]);
});

test('file breadcrumbs browse cached directories with keyboard navigation', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.directoryEntries['/workspace/src'] = [
    { name: 'docs', is_dir: true },
    { name: 'main.mbt', is_dir: false },
  ];
  app.directoryEntries['/workspace/src/docs'] = [];
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openQuickOpen();
  await page.locator('#quick-open-input').fill('main');
  await page.getByRole('option', { name: /main\.mbt/ }).click();

  const breadcrumb = page.locator('.viewer-breadcrumb');
  const sourceDirectory = breadcrumb.getByTitle('Show files in src');
  await sourceDirectory.click();
  await expect.poll(() => app.requests.find(request =>
    request.method === 'fs.read_directory' && request.params?.path === '/workspace/src'))
    .toBeTruthy();
  const menu = page.getByRole('menu', { name: 'Files in src' });
  await expect(menu.getByRole('menuitem')).toHaveCount(2);
  await expect(menu.getByRole('menuitem').first()).toHaveAttribute(
    'data-path',
    'src/docs',
  );
  await expect(menu.getByRole('menuitem').last()).toHaveClass(/selected/);
  await expect(menu.getByRole('menuitem').last()).toHaveAttribute('aria-current', 'page');
  await expect(menu.getByRole('menuitem').first()).toBeFocused();
  await page.keyboard.press('ArrowDown');
  await expect(menu.getByRole('menuitem').last()).toBeFocused();
  await page.keyboard.press('Home');
  await expect(menu.getByRole('menuitem').first()).toBeFocused();
  await page.keyboard.press('ArrowRight');

  await expect.poll(() => app.requests.find(request =>
    request.method === 'fs.read_directory' &&
    request.params?.path === '/workspace/src/docs'))
    .toBeTruthy();
  const nested = page.getByRole('menu', { name: 'Files in docs' });
  await expect(nested).toContainText('This folder is empty.');
  expect(app.pageErrors).toEqual([]);
});

test('transcript renders edit and bounded multi_edit changes beside their results', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  const longEdits = Array.from({ length: 53 }, (_, index) => ({
    file: `src/file_${index}.mbt`,
    start_line: index + 1,
    old_string: `old ${index}`,
    new_string: `new ${index}`,
  }));
  app.sessionEvents = [
    {
      sequence: 1,
      item: {
        kind: 'user',
        payload: { content: 'Show the browser fixture edit transcript' },
      },
    },
    {
      sequence: 2,
      item: {
        kind: 'assistant',
        payload: {
          content: '',
          tool_calls: [
            {
              id: 'edit-one',
              name: 'edit',
              arguments: JSON.stringify({
                path: 'lib/parser.mbt',
                start_line: 12,
                old_string: 'args.length()',
                new_string: 'args.len()',
              }),
            },
            {
              id: 'edit-many',
              name: 'multi_edit',
              arguments: JSON.stringify({
                edits: longEdits,
                revert_when_errors_above: 0,
              }),
            },
            {
              id: 'edit-partial',
              name: 'multi_edit',
              arguments: JSON.stringify({
                edits: [
                  {
                    file: 'src/readable.mbt',
                    old_string: 'before',
                    new_string: 'after',
                  },
                  { note: 'not an edit' },
                ],
              }),
            },
          ],
        },
      },
    },
    {
      sequence: 3,
      item: {
        kind: 'tool_result',
        payload: {
          tool_call_id: 'edit-one',
          tool_name: 'edit',
          content: 'edited 1 occurrence',
          is_error: false,
          brief: 'edit parser',
        },
      },
    },
    {
      sequence: 4,
      item: {
        kind: 'tool_result',
        payload: {
          tool_call_id: 'edit-many',
          tool_name: 'multi_edit',
          content: 'applied 53 edits',
          is_error: false,
          brief: 'multi_edit 53 edits',
        },
      },
    },
    {
      sequence: 5,
      item: {
        kind: 'tool_result',
        payload: {
          tool_call_id: 'edit-partial',
          tool_name: 'multi_edit',
          content: 'applied readable edit',
          is_error: false,
          brief: 'multi_edit partial',
        },
      },
    },
  ];
  await app.install();
  await app.goto();
  await app.openSession();

  const transcript = page.locator('.transcript');
  const edit = transcript.locator('.tool-call').filter({ hasText: 'edit parser' });
  await edit.locator('.tool-call-summary').click();
  await expect(edit.locator('.tool-call-tab-label')).toHaveText(['Change', 'Original JSON']);
  await expect(edit.locator('.tool-card-chip')).toHaveText([
    'path: lib/parser.mbt',
    'start_line: 12',
  ]);
  await expect(edit.locator('.diff-del')).toHaveText('- args.length()');
  await expect(edit.locator('.diff-add')).toHaveText('+ args.len()');

  const longBatch = transcript.locator('.tool-call').filter({ hasText: 'multi_edit 53 edits' });
  await longBatch.locator('.tool-call-summary').click();
  await expect(longBatch.locator('.tool-call-tab-label')).toHaveText([
    'Changes',
    'Original JSON',
  ]);
  await expect(longBatch.locator('.edit-entry')).toHaveCount(50);
  await expect(longBatch.locator('.edit-omitted')).toHaveText(
    '⋯ 3 more edits, in the original ⋯',
  );
  await expect(longBatch.locator('.tool-card-chip').first()).toHaveText(
    'revert_when_errors_above: 0',
  );
  await expect(longBatch.locator('.tool-card-chip').filter({
    hasText: 'file: src/file_50.mbt',
  })).toHaveCount(0);

  const partial = transcript.locator('.tool-call').filter({ hasText: 'multi_edit partial' });
  await partial.locator('.tool-call-summary').click();
  await expect(partial.locator('.edit-entry')).toHaveCount(1);
  await expect(partial.locator('.tool-card-chip')).toContainText('file: src/readable.mbt');
  await expect(partial.locator('.edit-omitted')).toHaveText(
    '⋯ 1 more edits, in the original ⋯',
  );
  await expect(transcript.locator('.tool-result')).toHaveCount(3);
  await expect(transcript.locator('.tool-result').filter({
    hasText: 'applied 53 edits',
  })).toHaveCount(1);
  expect(app.pageErrors).toEqual([]);
});

test('transcript overview previews failed turns and jumps among mounted messages', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  const events = [
    {
      sequence: 1,
      ts: 1_781_144_351_123,
      item: {
        kind: 'user',
        payload: { content: 'Show the browser fixture: first question' },
      },
    },
    {
      sequence: 2,
      ts: 1_781_144_352_123,
      item: {
        kind: 'assistant',
        payload: { content: 'First answer recovered after the tool failed.' },
      },
    },
    {
      sequence: 3,
      ts: 1_781_144_353_123,
      item: {
        kind: 'tool_result',
        payload: {
          tool_call_id: 'failed-after-answer',
          tool_name: 'shell',
          content: 'fixture failure',
          is_error: true,
          brief: 'failed after answer',
        },
      },
    },
  ];
  let sequence = 4;
  for (let turn = 2; turn <= 100; turn += 1) {
    events.push({
      sequence,
      ts: 1_781_144_350_123 + sequence * 1_000,
      item: {
        kind: 'user',
        payload: { content: `Question ${turn} keeps the overview rail scrollable` },
      },
    });
    sequence += 1;
    events.push({
      sequence,
      ts: 1_781_144_350_123 + sequence * 1_000,
      item: {
        kind: 'assistant',
        payload: { content: `Answer ${turn}` },
      },
    });
    sequence += 1;
  }
  app.sessionEvents = events;
  await app.install();
  await app.goto();
  await app.openSession();

  const overview = page.getByRole('navigation', { name: 'Conversation overview' });
  const ticks = overview.locator('.overview-tick-button');
  await expect(ticks).toHaveCount(100);
  const failed = ticks.first();
  await expect(failed).toBeVisible();
  await expect(failed).toHaveAccessibleName(
    'Show the browser fixture: first question (had errors)',
  );
  await failed.hover();
  const preview = overview.getByRole('tooltip');
  await expect(preview.locator('.overview-preview-prompt')).toContainText('first question');
  await expect(preview.locator('.overview-preview-reply')).toContainText('First answer');
  await expect(preview.locator('.overview-preview-failed')).toHaveText('had errors');
  const transcript = page.locator('#transcript');
  const scrollTopBeforeJump = await transcript.evaluate(node => node.scrollTop);
  await failed.click();
  await expect.poll(() => transcript.evaluate(node => node.scrollTop))
    .toBeLessThan(scrollTopBeforeJump);
  await expect.poll(async () => {
    const transcriptBox = await transcript.boundingBox();
    const firstTurnBox = await page.locator('#turn-s1').boundingBox();
    return firstTurnBox.y - transcriptBox.y;
  }).toBeLessThan(24);

  await overview.dispatchEvent('mouseleave');
  await expect(overview.getByRole('tooltip')).toHaveCount(0);
  await ticks.last().hover();
  await expect(overview.getByRole('tooltip')).toContainText('Question 100');
  await expect(overview.locator('.overview-preview')).toHaveClass(/flip/);
  expect(app.pageErrors).toEqual([]);
});

test('transcript preserves link boundaries, structured arguments, MoonBit reads, and sub-run links', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();

  const transcript = page.locator('.transcript');
  const userMessage = transcript.locator('.msg.user');
  await expect(userMessage.locator('a[href="https://example.test/docs"]')).toBeVisible();
  await expect(userMessage.locator('code')).toHaveText('https://inside.example.test');
  await expect(userMessage.locator('code a')).toHaveCount(0);

  const shellCall = transcript.locator('.tool-call').filter({ hasText: 'tests passed' });
  await shellCall.locator('.tool-call-summary').click();
  await expect(shellCall.locator('.tool-argument-key')).toContainText([
    'cmd',
    'options',
    'cwd',
    'targets',
  ]);
  await expect(shellCall.locator('.tool-argument-array')).toContainText('js');
  await expect(shellCall.locator('.tool-argument-array')).toContainText('native');

  const readResult = transcript.locator('.tool-result').filter({ hasText: 'read' });
  await readResult.locator('.tool-result-summary').click();
  await expect(readResult.locator('.read-moonbit-output')).toBeVisible();
  await expect(readResult.locator('.read-moonbit-gutter')).toHaveText(['9', '10', '11']);
  await expect(readResult.locator('.mtk3').first()).toHaveText('fn');
  await expect(readResult.locator('.read-moonbit-status')).toContainText('start_line=9');
  await expect(readResult.locator('.read-moonbit-status .mtk3')).toHaveCount(0);

  const exploreResult = transcript.locator('.tool-result').filter({ hasText: 'explore' });
  await exploreResult.locator('.tool-result-summary').click();
  await expect(transcript.locator('.subrun-chip')).toHaveAttribute(
    'title',
    'Open this subagent\'s own transcript (session-1-sr-2)',
  );
  expect(app.pageErrors).toEqual([]);
});

test('transcript Markdown keeps links safe and loads local raster bytes through the host', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.binaryFiles['diagram.png'] = {
    data_base64: 'iVBORw0KGgo=',
    media_type: 'image/png',
  };
  app.sessionEvents = [
    {
      sequence: 1,
      item: {
        kind: 'user',
        payload: { content: 'Show the browser fixture Markdown policy' },
      },
    },
    {
      sequence: 2,
      item: {
        kind: 'assistant',
        payload: {
          content: [
            '[External docs](https://example.test/docs)',
            '[Source](src/main.mbt:12)',
            '[Local URI](file:///Users/me/My%20Project/main.mbt#L7)',
            '[Unsafe](javascript:alert(1))',
            '![Fixture image](diagram.png)',
            '```uml',
            '@startuml',
            'participant Alice',
            'Alice -> Bob : hello',
            '@enduml',
            '```',
            '```uml',
            '@startuml',
            '@enduml',
            '```',
            '```mermaid',
            'A --> B',
            '```',
          ].join('\n\n'),
        },
      },
    },
  ];
  await app.install();
  await app.goto();
  await app.openSession();

  const markdown = page.locator('.transcript .msg-content.markdown');
  const diagram = markdown.locator('[data-diagram-language="uml"]');
  await expect(diagram).toHaveCount(1);
  await expect(diagram).toHaveAttribute(
    'data-diagram-language',
    'uml',
  );
  await expect(diagram).toHaveClass(/moonbit-viewer-markdown-diagram-viewport/);
  await expect(diagram.locator('svg')).toBeVisible();
  await expect(markdown.locator('code.language-uml')).toHaveCount(1);
  await expect(markdown.locator('code.language-mermaid')).toHaveCount(1);
  await expect(markdown.locator('a[href^="javascript:"]')).toHaveCount(0);
  await expect(markdown.getByText('Unsafe', { exact: true })).toBeVisible();

  const image = markdown.locator('img[alt="Fixture image"]');
  await expect.poll(() => app.requests.find(request =>
    request.method === 'fs.read_file' && request.params?.path === 'diagram.png'))
    .toMatchObject({ params: { root: '/workspace' } });
  await expect(image).toHaveAttribute('src', 'data:image/png;base64,iVBORw0KGgo=');
  await expect(image).not.toHaveClass(/pending/);
  await expect(image).not.toHaveAttribute('data-transcript-image', 'diagram.png');

  const external = markdown.getByRole('link', { name: 'External docs' });
  await expect(external).toHaveAttribute('target', '_blank');
  await expect(external).toHaveAttribute('rel', 'noopener noreferrer');
  await markdown.getByTitle('Open src/main.mbt:12').click();
  await expect.poll(() => app.requests.find(request =>
    request.method === 'host.open_path' && request.params?.path === 'src/main.mbt:12'))
    .toBeTruthy();
  const localUri = markdown.getByTitle('Open /Users/me/My Project/main.mbt#L7');
  await expect(localUri).toBeVisible();
  await localUri.click();
  await expect.poll(() => app.requests.find(request =>
    request.method === 'host.open_path' &&
    request.params?.path === '/Users/me/My Project/main.mbt#L7'))
    .toBeTruthy();
  expect(app.pageErrors).toEqual([]);
});

test('transcript names mbtx build and runtime failures without mislabeling JS failures', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();

  const transcript = page.locator('.transcript');
  const buildCall = transcript.locator('.tool-call.error').filter({ hasText: 'compile_error' });
  const runtimeCall = transcript.locator('.tool-call.error').filter({ hasText: 'abort("runtime")' });
  const singleShotCall = transcript.locator('.tool-call.error').filter({ hasText: 'single shot' });
  await expect(buildCall).toHaveClass(/stage-build/);
  await expect(buildCall.locator('.tool-call-failed')).toHaveCount(0);
  await expect(buildCall.locator('.tool-stage-build')).toHaveCount(0);
  await expect(runtimeCall.locator('.tool-call-failed.tool-stage-run')).toHaveCount(1);
  await expect(singleShotCall.locator('.tool-stage-build, .tool-stage-run')).toHaveCount(0);
  await expect(singleShotCall.locator('.tool-call-failed')).toHaveCount(1);

  const buildResult = transcript.locator('.tool-result.error').filter({ hasText: 'type mismatch' });
  const runtimeResult = transcript.locator('.tool-result.error').filter({ hasText: 'runtime trap' });
  const singleShotResult = transcript.locator('.tool-result.error').filter({
    hasText: 'single-shot diagnostic',
  });
  await expect(buildResult).toHaveClass(/stage-build/);
  await expect(buildResult.locator('.tool-call-failed.tool-stage-build')).toHaveCount(1);
  await expect(runtimeResult.locator('.tool-call-failed.tool-stage-run')).toHaveCount(1);
  await expect(singleShotResult.locator('.tool-stage-build, .tool-stage-run')).toHaveCount(0);
  await expect(singleShotResult.locator('.tool-call-failed')).toHaveCount(1);

  await buildCall.locator('.tool-call-summary').click();
  await expect(buildCall.locator('.mbtx-args')).toContainText('fn main { compile_error }');
  await expect(buildCall.locator('.moonbit-gutter')).toHaveText(['1']);
  await expect(buildCall.locator('.mtk3').first()).toHaveText('fn');
  await expect(buildCall.getByText('Program', { exact: true })).toBeVisible();
  await expect(buildCall.getByText('Original JSON', { exact: true })).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('transcript keeps every line of a long mbtx program in the mounted card', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  const source = Array.from({ length: 120 }, (_, index) => `let x${index} = ${index}`)
    .join('\n');
  app.sessionEvents = [
    {
      sequence: 1,
      item: {
        kind: 'user',
        payload: { content: 'Show the browser fixture' },
      },
    },
    {
      sequence: 2,
      item: {
        kind: 'assistant',
        payload: {
          content: '',
          tool_calls: [{
            id: 'mbtx-long',
            name: 'mbtx',
            arguments: JSON.stringify({ source, target: 'js' }),
          }],
        },
      },
    },
    {
      sequence: 3,
      item: {
        kind: 'tool_result',
        payload: {
          tool_call_id: 'mbtx-long',
          tool_name: 'mbtx',
          content: 'ok',
          is_error: false,
          brief: 'mbtx (exit=0)',
        },
      },
    },
  ];

  await app.install();
  await app.goto();
  await app.openSession();
  const call = page.locator('.tool-call').filter({ hasText: 'let x119 = 119' });
  await call.locator('.tool-call-summary').click();
  await expect(call.locator('.moonbit-gutter')).toHaveCount(120);
  await expect(call.locator('.moonbit-gutter').last()).toHaveText('120');
  await expect(call).not.toContainText('skipped');
  expect(app.pageErrors).toEqual([]);
});

test('transcript elides only the middle of enormous numbered MoonBit source', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  const source = [
    'let greeting = "<hello>"',
    ...Array.from({ length: 599 }, (_, index) => `let x${index + 2} = ${index + 2}`),
  ].join('\n');
  app.sessionEvents = [
    {
      sequence: 1,
      item: {
        kind: 'user',
        payload: { content: 'Show the browser fixture enormous source' },
      },
    },
    {
      sequence: 2,
      item: {
        kind: 'assistant',
        payload: {
          content: '',
          tool_calls: [{
            id: 'mbtx-enormous',
            name: 'mbtx',
            arguments: JSON.stringify({ source, target: 'js' }),
          }],
        },
      },
    },
    {
      sequence: 3,
      item: {
        kind: 'tool_result',
        payload: {
          tool_call_id: 'mbtx-enormous',
          tool_name: 'mbtx',
          content: 'ok',
          is_error: false,
          brief: 'mbtx enormous source',
        },
      },
    },
  ];
  await app.install();
  await app.goto();
  await app.openSession();

  const call = page.locator('.tool-call').filter({ hasText: 'mbtx enormous source' });
  await call.locator('.tool-call-summary').click();
  const rows = call.locator('.moonbit-line');
  const gutters = call.locator('.moonbit-gutter');
  await expect(rows).toHaveCount(501);
  await expect(call.locator('.moonbit-skip')).toContainText('⋯ 100 lines skipped ⋯');
  expect(await gutters.nth(399).textContent()).toBe('400');
  expect(await gutters.nth(400).textContent()).toBe('   ');
  expect(await gutters.nth(401).textContent()).toBe('501');
  expect(await gutters.last().textContent()).toBe('600');
  await expect(gutters.filter({ hasText: /^401$/ })).toHaveCount(0);
  await expect(call.locator('.mtk5').filter({ hasText: '"<hello>"' })).toHaveCount(1);
  await expect(call.locator('hello')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('approval card sends its decision through the browser transport', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();

  app.notify('agent.started', {
    run_id: 'run-1',
    session: 'session-1',
    session_root: '/workspace/.openseek',
    model: 'deepseek-v4-pro',
    max_steps: 1000,
  });
  app.notify('agent.event', {
    run_id: 'run-1',
    session: 'session-1',
    event: {
      event: 'approval_requested',
      id: 'approval-1',
      tool_name: 'mbtx',
      detail: 'run this snippet with no sandbox policy',
      body: 'fn main { @myshell.Cmd("npm", ["ci"]) }',
    },
  });

  const approval = page.locator('.composer-approval');
  await expect(approval).toBeVisible();
  await expect(approval.locator('.composer-approval-tool')).toContainText('mbtx');
  await expect(approval.locator('.composer-approval-body')).toContainText('@myshell.Cmd');
  await expect(approval.getByRole('button', { name: 'Deny' })).toBeVisible();
  await approval.getByRole('button', { name: 'Allow once' }).click();
  await expect.poll(() => app.requests.some(request =>
    request.method === 'agent.approval' &&
    request.params?.id === 'approval-1' &&
    request.params?.allow === true)).toBe(true);
  await expect(approval).toContainText('Sending…');
  await expect(approval.getByRole('button', { name: 'Allow once' })).toHaveCount(0);
  await expect(approval.getByRole('button', { name: 'Deny' })).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('composer sends a turn and stops the accepted run', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();

  const composer = page.locator('#task');
  await composer.fill('Run the browser E2E turn');
  await page.getByTitle('Send', { exact: true }).click();
  await expect.poll(() => app.requests.find(request =>
    request.method === 'agent.start'))
    .toMatchObject({
      params: {
        task: 'Run the browser E2E turn',
        session: 'session-1',
      },
    });

  await page.getByTitle('Stop', { exact: true }).click();
  await expect.poll(() => app.requests.find(request =>
    request.method === 'agent.cancel'))
    .toMatchObject({ params: { run_id: 'run-e2e' } });
  expect(app.pageErrors).toEqual([]);
});

test('new chat, archive, and restore update the conversation sidebar', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();

  await page.locator('.workspace-row', { hasText: 'workspace' }).hover();
  await page.getByTitle('New conversation in this project').click();
  await expect(page.locator('.conversation-row', { hasText: 'New chat' })).toBeVisible();
  await expect(page.locator('#task')).toHaveValue('');

  await page.getByText('Rabbita browser fixture', { exact: true }).first().click();
  const liveRow = page.locator('.conversation-row[title="session-1"]');
  await liveRow.hover();
  await liveRow.getByTitle(/Archive —/).click();
  await expect.poll(() => app.requests.some(request =>
    request.method === 'session.archive' &&
    request.params?.session === 'session-1')).toBe(true);

  const archivedHeading = page.locator('.section-heading', {
    hasText: 'Archived chats (1)',
  });
  await archivedHeading.click();
  const archivedRow = page.locator('.conversation-row[title="session-1"]');
  await expect(archivedRow).toBeVisible();
  await archivedRow.click();
  await expect(page.getByText('Archived conversation · Read only')).toBeVisible();
  await expect(page.locator('#task')).toHaveCount(0);
  await expect(page.locator('#send')).toHaveCount(0);
  await expect(page.locator('#stop')).toHaveCount(0);
  await archivedRow.hover();
  await archivedRow.getByTitle('Restore this conversation to the sidebar').click();
  await expect.poll(() => app.requests.some(request =>
    request.method === 'session.unarchive' &&
    request.params?.session === 'session-1')).toBe(true);
  await expect(page.getByText('Rabbita browser fixture', { exact: true }).first()).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('composer, quick open, settings, and skills keep explicit focus ownership', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();

  await expect(page.locator('.composer-inner')).toHaveAttribute('data-focus-owner', '');
  await expect(page.locator('#task')).toHaveAttribute('data-focus-target', '');

  await app.openQuickOpen();
  await expect(page.locator('#quick-open-input')).toHaveAttribute('data-focus-owner', '');
  await expect(page.locator('#quick-open-input')).not.toHaveAttribute('data-focus-target', '');
  await page.keyboard.press('Escape');

  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await expect(page.locator('select')).toHaveCount(0);
  await expect(page.locator('.custom-select.setting-select button').first()).toHaveAttribute(
    'aria-haspopup',
    'listbox',
  );
  for (const field of await page.locator('input, textarea').all()) {
    const owner = await field.getAttribute('data-focus-owner');
    const target = await field.getAttribute('data-focus-target');
    expect(owner === '' || target === '').toBe(true);
  }

  await page.getByRole('button', { name: 'Skills', exact: true }).click();
  await expect(page.locator('.skills-search')).toHaveAttribute('data-focus-owner', '');
  await expect(page.locator('.skills-search input')).toHaveAttribute('data-focus-target', '');
  expect(app.pageErrors).toEqual([]);
});

test('settings persist host API changes through settings.set', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();

  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Settings' })).toBeVisible();
  await page.getByRole('button', { name: 'API endpoint' }).click();
  await page.getByRole('option', { name: 'Custom URL' }).click();
  await expect.poll(() => app.requests.some(request =>
    request.method === 'settings.set' &&
    request.params?.provider === 'custom')).toBe(true);

  await page.getByRole('textbox', { name: 'Endpoint URL' }).fill(
    'https://example.test/chat/completions',
  );
  await expect.poll(() => app.requests.some(request =>
    request.method === 'settings.set' &&
    request.params?.custom_api_url === 'https://example.test/chat/completions'))
    .toBe(true);
  await expect(page.getByRole('textbox', { name: 'Endpoint URL' })).toHaveValue(
    'https://example.test/chat/completions',
  );
  expect(app.pageErrors).toEqual([]);
});

test('skills installs a catalog entry and refreshes the installed library', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();

  await page.getByRole('button', { name: 'Skills', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Skills' })).toBeVisible();
  const registry = page.locator('.settings-group').filter({
    has: page.getByRole('heading', { name: 'Mooncakes registry' }),
  });
  const rabbita = registry.locator('.skill-row').filter({ hasText: /Rabbita/i });
  await rabbita.getByRole('button', { name: 'Install' }).click();
  await expect.poll(() => app.requests.some(request =>
    request.method === 'skills.install' &&
    request.params?.module_name === 'rabbita')).toBe(true);

  const installed = page.locator('.settings-group').filter({
    has: page.getByRole('heading', { name: 'Installed' }),
  });
  await expect(installed.locator('.skill-row').filter({ hasText: 'Rabbita' })).toBeVisible();
  await expect(rabbita).toContainText('Installed');
  expect(app.pageErrors).toEqual([]);
});

test('skills search, detail navigation, and hand-written protections use the mounted page', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await page.getByRole('button', { name: 'Skills', exact: true }).click();

  const search = page.locator('.skills-search input');
  await search.fill('rabbita');
  const installed = page.locator('.settings-group').filter({
    has: page.getByRole('heading', { name: 'Installed' }),
  });
  const registry = page.locator('.settings-group').filter({
    has: page.getByRole('heading', { name: 'Mooncakes registry' }),
  });
  await expect(installed).toContainText('No installed skill matches the search.');
  await expect(registry.locator('.skill-row')).toContainText('rabbita');
  await expect(registry.locator('.skill-row')).toHaveCount(1);

  await search.fill('');
  const moonbit = installed.locator('.skill-row').filter({ hasText: 'MoonBit' });
  await expect(moonbit).toContainText('hand-written');
  await expect(moonbit.getByRole('button', { name: 'Uninstall' })).toHaveCount(0);

  const rabbita = registry.locator('.skill-row').filter({ hasText: 'rabbita' });
  await rabbita.locator('.skill-summary').click();
  await expect(page.getByRole('button', { name: '← Back to skills' })).toBeVisible();
  await expect(page.locator('.skill-file-name')).toHaveText('SKILL.md');
  await expect(page.getByRole('heading', { name: 'rabbita', exact: true })).toBeVisible();
  await expect(page.locator('.skill-preview-markdown')).toContainText('Browser UI guidance.');
  await page.getByRole('button', { name: '← Back to skills' }).click();

  await installed.locator('.skill-row').filter({ hasText: 'MoonBit' })
    .locator('.skill-summary').click();
  await expect(page.locator('.skill-detail-meta')).toHaveText('hand-written');
  await expect(page.getByRole('button', { name: 'Uninstall' })).toHaveCount(0);
  await expect(page.locator('.skill-preview-markdown')).toContainText(
    'Authoritative MoonBit guidance.',
  );
  expect(app.pageErrors).toEqual([]);
});

test('Codex account login can be started and cancelled from Settings', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.codexRequiresAuth = true;
  await app.install();
  await app.goto();

  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await page.getByRole('button', { name: 'Sign in with ChatGPT' }).click();
  await expect.poll(() => app.requests.some(request =>
    request.method === 'codex.account.login.start')).toBe(true);
  await expect(page.getByRole('link', { name: 'Open' })).toHaveAttribute(
    'href',
    'https://example.test/codex-login',
  );

  await page.getByRole('button', { name: 'Cancel sign-in' }).click();
  await expect.poll(() => app.requests.some(request =>
    request.method === 'codex.account.login.cancel' &&
    request.params?.loginId === 'login-e2e')).toBe(true);
  await expect(page.getByRole('button', { name: 'Sign in with ChatGPT' })).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('Codex creates a thread, sends its first turn, and stops it', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.codexModels = [
    {
      id: 'gpt-5.4-codex',
      displayName: 'GPT-5.4 Codex',
      isDefault: true,
      defaultReasoningEffort: 'medium',
      supportedReasoningEfforts: [
        { reasoningEffort: 'medium', description: 'Balanced' },
      ],
    },
  ];
  await app.install();
  await app.goto();

  // A model pick is the product's hand-off from a fresh OpenSeek draft to a
  // Codex draft. The rest of the test exercises the ordinary composer path.
  await page.getByRole('button', { name: 'Model', exact: true }).click();
  await page.getByRole('option', { name: 'GPT-5.4 Codex' }).click();
  await expect.poll(() => app.requests.find(request =>
    request.method === 'codex.draft.open'))
    .toMatchObject({ params: { cwd: '/workspace' } });

  await page.locator('#task').fill('Run the Codex browser E2E turn');
  await page.getByTitle('Send', { exact: true }).click();
  await expect.poll(() => app.requests.find(request =>
    request.method === 'codex.thread.start'))
    .toMatchObject({
      params: {
        cwd: '/workspace',
        model: 'gpt-5.4-codex',
      },
    });
  await expect.poll(() => app.requests.find(request =>
    request.method === 'codex.turn.start'))
    .toMatchObject({
      params: {
        threadId: 'codex-thread-e2e',
        input: [{ type: 'text', text: 'Run the Codex browser E2E turn' }],
      },
    });

  await page.getByTitle('Stop', { exact: true }).click();
  await expect.poll(() => app.requests.find(request =>
    request.method === 'codex.turn.interrupt'))
    .toMatchObject({
      params: {
        threadId: 'codex-thread-e2e',
        turnId: 'codex-turn-e2e',
      },
    });
  expect(app.pageErrors).toEqual([]);
});

test('Codex command and network approvals render the facts and advertised decisions', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.codexModels = [
    {
      id: 'gpt-5.4-codex',
      displayName: 'GPT-5.4 Codex',
      isDefault: true,
      defaultReasoningEffort: 'medium',
      supportedReasoningEfforts: [
        { reasoningEffort: 'medium', description: 'Balanced' },
      ],
    },
  ];
  await app.install();
  await app.goto();

  await page.getByRole('button', { name: 'Model', exact: true }).click();
  await page.getByRole('option', { name: 'GPT-5.4 Codex' }).click();
  // Opening the Codex draft is asynchronous. Wait for the host round-trip so
  // the composer cannot race its still-disabled Send button on a loaded suite.
  await expect.poll(() => app.requests.find(request =>
    request.method === 'codex.draft.open'))
    .toMatchObject({ params: { cwd: '/workspace' } });
  await page.locator('#task').fill('Start a Codex turn for approval testing');
  const send = page.getByTitle('Send', { exact: true });
  await expect(send).toBeEnabled();
  await send.click();
  await expect.poll(() => app.requests.some(request =>
    request.method === 'codex.turn.start')).toBe(true);

  app.notify('codex.server_request', {
    request_id: 'approval-command',
    method: 'item/commandExecution/requestApproval',
    params: {
      threadId: 'codex-thread-e2e',
      turnId: 'codex-turn-e2e',
      itemId: 'command-1',
      reason: 'Generate package interface metadata',
      command: '/bin/zsh -lc "moon info"',
      cwd: '/workspace',
      proposedExecpolicyAmendment: ['moon', 'info'],
      availableDecisions: [
        'accept',
        {
          acceptWithExecpolicyAmendment: {
            execpolicy_amendment: ['moon', 'info'],
          },
        },
        'cancel',
      ],
    },
    generation: 2,
  });

  const commandApproval = page.locator('.codex-request').filter({
    hasText: 'Command approval',
  });
  await expect(commandApproval).toContainText('Generate package interface metadata');
  await expect(commandApproval.locator('.codex-request-command')).toContainText('moon info');
  await expect(commandApproval).toContainText('/workspace');
  await expect(commandApproval).toContainText('Requested rule');
  await expect(commandApproval.getByRole('button', { name: 'Allow by rule: moon info' })).toBeVisible();
  await expect(commandApproval.getByRole('button', { name: 'Approve once' })).toBeVisible();
  await expect(commandApproval.getByRole('button', { name: 'Cancel' })).toBeVisible();
  await expect(commandApproval.locator('.codex-request-raw-summary')).toHaveText('Show details');

  app.notify('codex.server_request', {
    request_id: 'approval-network',
    method: 'item/commandExecution/requestApproval',
    params: {
      threadId: 'codex-thread-e2e',
      turnId: 'codex-turn-e2e',
      itemId: 'command-2',
      command: 'internal network request',
      cwd: '/workspace',
      networkApprovalContext: {
        host: 'api.example.test',
        protocol: 'https',
        port: 443,
      },
      availableDecisions: ['accept', 'cancel'],
    },
    generation: 3,
  });

  const networkApproval = page.locator('.codex-request').filter({
    hasText: 'Network access approval',
  });
  await expect(networkApproval).toContainText('Network destination');
  await expect(networkApproval).toContainText('https://api.example.test:443');
  await expect(networkApproval.locator('.codex-request-command')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('desktop shell and modal stay inside a narrow browser viewport', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();

  await page.getByRole('button', { name: 'Show sidebar' }).click();
  await page.getByRole('button', { name: 'Add a project' }).click();
  const bounds = await page.locator('.picker-modal').boundingBox();
  expect(bounds).not.toBeNull();
  expect(bounds.x).toBeGreaterThanOrEqual(0);
  expect(bounds.y).toBeGreaterThanOrEqual(0);
  expect(bounds.x + bounds.width).toBeLessThanOrEqual(390);
  expect(bounds.y + bounds.height).toBeLessThanOrEqual(844);
  await expect.poll(() => page.evaluate(() =>
    document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true);
  expect(app.pageErrors).toEqual([]);
});

import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('desktop browser shell renders host and conversation DOM', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();

  await expect(page.getByText('@octocat', { exact: true })).toBeVisible();
  await expect(page.getByText('Ready', { exact: true })).toBeVisible();
  await expect(page.getByText('Rabbita browser fixture', { exact: true }).first()).toBeVisible();
  await app.openSession();
  await expect(page.locator('.transcript')).toBeVisible();
  await expect(page.locator('.composer-input')).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('remote panel launcher and toolbar preserve their visible actions and order', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();

  const launcher = page.locator('.dock-launcher');
  await expect(launcher.getByRole('button')).toHaveText([
    'SearchSearch text across the workspace',
    'FilesOpen a file from the workspace',
    'ReviewReview changed files and diffs',
  ]);
  await expect(launcher.getByRole('button', { name: /Browse/ })).toHaveCount(0);

  const expand = page.getByTitle('Expand panel');
  const hide = page.getByTitle('Hide panel');
  await expect(expand).toHaveAttribute('aria-pressed', 'false');
  expect(await expand.evaluate((node, other) =>
    Boolean(node.compareDocumentPosition(other) & Node.DOCUMENT_POSITION_FOLLOWING),
  await hide.elementHandle())).toBe(true);
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
  await expect(tabs.getByRole('tab')).toHaveText(['Files', 'Changes', 'Search']);
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

test('transcript mounts markdown, plan, goal, and MoonBit tool DOM', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();

  const transcript = page.locator('.transcript');
  await expect(transcript.getByRole('heading', { name: 'Browser result' })).toBeVisible();
  await expect(transcript.locator('strong')).toHaveText('successfully');
  await expect(transcript.locator('code').filter({ hasText: 'Rabbita 0.15' }).first()).toBeVisible();
  await expect(transcript.locator('.plan-step.completed')).toContainText('Inspect DOM');
  await expect(transcript.locator('.plan-step.in_progress')).toContainText('Run Playwright');
  await expect(transcript.locator('.plan-step.pending')).toContainText('Review layout');
  await expect(page.locator('.composer-goal')).toContainText('Ship Rabbita 0.15 browser tests');
  const mbtxCall = transcript.locator('.tool-call').filter({ hasText: 'println(42)' });
  await mbtxCall.locator('.tool-call-summary').click();
  await expect(mbtxCall.locator('.mbtx-args')).toContainText('fn main { println(42) }');
  const mbtxResult = transcript.locator('.tool-result').filter({ hasText: '42' });
  await mbtxResult.locator('.tool-result-summary').click();
  await expect(mbtxResult.locator('.tool-call-output')).toContainText('42');
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
  await expect(buildCall.locator('.tool-call-summary')).toContainText(
    'mbtx (build failed, exit=1)',
  );
  await expect(buildCall.locator('.tool-call-failed')).toHaveCount(0);
  await expect(buildCall.locator('.tool-stage-build')).toHaveCount(0);
  await expect(runtimeCall.locator('.tool-call-failed.tool-stage-run')).toHaveText('runtime error');
  await expect(singleShotCall.locator('.tool-call-failed')).toHaveText('failed');
  await expect(singleShotCall.locator('.tool-stage-build, .tool-stage-run')).toHaveCount(0);

  const buildResult = transcript.locator('.tool-result.error').filter({ hasText: 'type mismatch' });
  const runtimeResult = transcript.locator('.tool-result.error').filter({ hasText: 'runtime trap' });
  const singleShotResult = transcript.locator('.tool-result.error').filter({
    hasText: 'single-shot diagnostic',
  });
  await expect(buildResult).toHaveClass(/stage-build/);
  await expect(buildResult.locator('.tool-call-failed.tool-stage-build')).toHaveText(
    'build error',
  );
  await expect(runtimeResult.locator('.tool-call-failed.tool-stage-run')).toHaveText('runtime error');
  await expect(singleShotResult.locator('.tool-call-failed')).toHaveText('failed');
  await expect(singleShotResult.locator('.tool-stage-build, .tool-stage-run')).toHaveCount(0);

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

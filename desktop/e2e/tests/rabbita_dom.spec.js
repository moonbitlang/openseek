import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

// `goto()` returns once the shell is mounted, which can be before the host's
// project list arrives. Until then the main pane shows an onboarding card with
// its own "Add a project" button, so wait for the fixture project and address
// the sidebar's button through its landmark.
async function sidebarAddProject(page) {
  const sidebar = page.getByRole('complementary');
  await expect(sidebar.locator('[id="project:openseek.projects:remote.device-a:/workspace:disclosure"]')).toBeVisible();
  return sidebar.locator('[id="section:openseek.projects:remote.device-a:action"]');
}

test('workspace search supports toggles and keyboard navigation', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  // The query field is rendered once the project's checkout is known, and the
  // shortcut focuses it only once. Pressed earlier, the panel keeps the focus
  // and the field that appears later is left unfocused. The composer offers a
  // retry for the worktree list for as long as the checkout is unknown.
  await expect(page.locator('[id="project:openseek.projects:remote.device-a:/workspace:disclosure"]')).toBeVisible();
  await expect(page.locator('.composer-notice-btn')).toBeHidden();

  const shortcut = await page.evaluate(() =>
    navigator.platform.includes('Mac') ? 'Meta+Shift+F' : 'Control+Shift+F');
  await page.keyboard.press(shortcut);

  const tabs = page.locator('#explorer-views');
  const filesTab = tabs.locator('#explorer-files-tab');
  const searchTab = tabs.locator('#explorer-search-tab');
  await expect(searchTab).toHaveAttribute('aria-selected', 'true');
  // Icon-only tabs keep their existing accessible names and native tooltips.
  for (const [key, name, title] of [
    ['files', 'Files', 'Workspace files'],
    ['changes', 'Changes', 'Changed files (click again to refresh)'],
    ['search', 'Search', 'Search across the workspace'],
  ]) {
    const tab = tabs.locator(`#explorer-${key}-tab`);
    await expect(tab).toHaveAttribute('title', title);
    await expect(tab.locator('.visually-hidden')).toHaveText(name);
  }

  const query = page.locator('#workspace-search-input');
  await expect(query).toBeFocused();

  const wholeWord = page.locator('#search-whole-word');
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

  await expect(page.locator('#explorer-changes-tab'))
    .toHaveAttribute('aria-selected', 'true');
  await expect.poll(() => app.requests.find(request => request.method === 'git.changes'))
    .toMatchObject({
      params: {
        session: 'session-1',
        workspace: '/workspace',
      },
    });
  const changes = page.locator('#review-changes-body');
  await expect(changes.locator('.review-progress-summary')).toHaveText(
    '0 / 2 reviewed',
  );
  const main = changes.locator('[role="treeitem"][data-path="src/main.mbt"]');
  const library = changes.locator('[role="treeitem"][data-path="src/lib.mbt"]');
  await expect(main).toHaveAttribute('aria-current', 'false');
  await main.click();
  await page.locator('#file-tree-toggle').click();

  await expect.poll(() => app.requests.find(request =>
    request.method === 'fs.read_file' && request.params?.path === '/workspace/src/main.mbt'))
    .toBeTruthy();
  await expect.poll(() => app.requests.find(request =>
    request.method === 'git.original_file' &&
    request.params?.path === 'src/main.mbt' &&
    request.params?.revision === app.gitBaseline))
    .toBeTruthy();
  const reviewToolbar = page.locator('#review-mode-toolbar');
  await expect(reviewToolbar.locator('[data-diff-mode="token"]')).toHaveAttribute(
    'aria-pressed',
    'true',
  );
  await expect(page.locator('.semantic-review[data-mode="token"]')).toBeVisible();

  // Line diff keeps semantic-only filters inert. Token and Tree make those
  // user controls available.
  await reviewToolbar.locator('[data-diff-mode="line"]').click();
  const ignoreComments = page.locator('button.review-comments-control');
  const ignoreTests = page.locator('button.review-tests-control');
  await expect(ignoreComments).toBeDisabled();
  await expect(ignoreTests).toBeDisabled();

  await reviewToolbar.locator('[data-review-mode="file"]').click();
  await expect(reviewToolbar.locator('[data-review-mode="file"]')).toHaveAttribute(
    'aria-pressed',
    'true',
  );
  await reviewToolbar.locator('[data-diff-mode="line"]').click();

  await reviewToolbar.locator('[data-diff-mode="token"]').click();
  await expect(reviewToolbar.locator('[data-diff-mode="token"]')).toHaveAttribute(
    'aria-pressed',
    'true',
  );
  await expect(ignoreComments).toHaveAttribute('aria-pressed', 'true');
  await expect(ignoreTests).toHaveAttribute('aria-pressed', 'true');
  await ignoreComments.click();
  await ignoreTests.click();
  await expect(ignoreComments).toHaveAttribute('aria-pressed', 'false');
  await expect(ignoreTests).toHaveAttribute('aria-pressed', 'false');

  await reviewToolbar.locator('[data-diff-mode="tree"]').click();
  await expect(reviewToolbar.locator('[data-diff-mode="tree"]')).toHaveAttribute(
    'aria-pressed',
    'true',
  );

  const layout = page.locator('.review-layout-control[role="group"]');
  await layout.locator('[data-layout="inline"]').click();
  await expect(layout.locator('[data-layout="inline"]')).toHaveAttribute(
    'aria-pressed',
    'true',
  );
  const semantic = page.locator(
    '.semantic-review[data-mode="tree"][data-layout="unified"]',
  );
  await expect(semantic).toBeVisible();
  const semanticDiffCandidate = semantic.locator('.semantic-diff-editor-host').filter({
    has: page.locator(
      '.moonbit-diff-editor-modified '
        + '.view-lines[data-view-part="view-lines"] > .view-line[data-line="2"]',
    ),
  }).first();
  await expect(semanticDiffCandidate).toBeVisible();
  const semanticDiffId = await semanticDiffCandidate.getAttribute('id');
  expect(semanticDiffId).not.toBeNull();
  const semanticDiff = semantic.locator(`[id=${JSON.stringify(semanticDiffId)}]`);
  const semanticModified = semanticDiff.locator('.moonbit-diff-editor-modified');
  await expect(semanticDiff).toBeVisible();
  await expect(semanticDiff.locator('.moonbit-diff-editor').first())
    .toHaveAttribute('data-render-mode', 'inline');
  const feedbackLine = semanticModified.locator(
    '.view-lines[data-view-part="view-lines"] > .view-line[data-line="2"]',
  );
  await expect(feedbackLine).toBeVisible();
  const feedbackLineBox = await feedbackLine.boundingBox();
  const modifiedBox = await semanticModified.boundingBox();
  expect(feedbackLineBox).not.toBeNull();
  expect(modifiedBox).not.toBeNull();
  await page.mouse.move(
    Math.min(
      feedbackLineBox.x + 20,
      modifiedBox.x + modifiedBox.width - 10,
    ),
    feedbackLineBox.y + feedbackLineBox.height / 2,
  );
  const feedbackGlyph = semanticModified.locator(
    '.agent-feedback-glyph.line-hover',
  );
  await expect(feedbackGlyph).toBeVisible();
  const feedbackGlyphBox = await feedbackGlyph.boundingBox();
  expect(feedbackGlyphBox).not.toBeNull();
  await page.mouse.click(
    feedbackGlyphBox.x + feedbackGlyphBox.width / 2,
    feedbackGlyphBox.y + feedbackGlyphBox.height / 2,
  );
  const feedbackInput = semanticDiff.locator(
    '.agent-feedback-input-widget textarea',
  );
  await expect(feedbackInput).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(feedbackInput).toBeHidden();

  await reviewToolbar.locator('[data-diff-mode="line"]').click();
  await expect(reviewToolbar.locator('[data-diff-mode="line"]')).toHaveAttribute(
    'aria-pressed',
    'true',
  );
  await expect(layout.locator('[data-layout="inline"]')).toHaveAttribute(
    'aria-pressed',
    'true',
  );

  const progress = page.locator('#review-file-toggle');
  await progress.click();
  await expect(page.locator('#review-file-toggle'))
    .toHaveAttribute('aria-pressed', 'true');
  await expect(changes.locator('.review-progress-summary')).toHaveText(
    '1 / 2 reviewed',
  );
  await page.locator('[data-action="next-diff-change"]').click();
  await expect(library).toHaveAttribute('aria-current', 'page');
  await expect(page.locator('.review-nav-position')).toHaveText('File 2 of 2');
  await expect.poll(() => app.requests.find(request =>
    request.method === 'git.original_file' &&
    request.params?.path === 'src/lib.mbt' &&
    request.params?.revision === app.gitBaseline))
    .toBeTruthy();
  expect(app.pageErrors).toEqual([]);
});

for (const pendingMethod of ['git.original_file', 'fs.read_file']) {
  test(`Review navigation remains visible while ${pendingMethod} and diff computation finish`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    const baseline = Array.from({ length: 15 }, (_, i) => [
      `fn changed_${i}() -> Int { 0 }`,
      ...Array.from({ length: 8 }, (_, j) => `fn same_${i}_${j}() -> Int { ${j} }`),
    ].join('\n')).join('\n');
    const contents = pendingMethod === 'fs.read_file' ? baseline.replaceAll('\n', '\r\n') : baseline;
    app.gitFilesByRevision[app.gitBaseline]['src/lib.mbt'] = contents;
    app.workingFiles['src/lib.mbt'] = contents.replaceAll('-> Int { 0 }', '-> Int { 10 }');
    const { promise: pending, resolve: release } = Promise.withResolvers();
    const replyFor = app.replyFor.bind(app);
    app.replyFor = async (request) => {
      if (request.method === pendingMethod && request.params?.path?.endsWith('/lib.mbt')) {
        await pending;
      }
      return replyFor(request);
    };
    await app.install();
    await app.goto();
    await app.openSession();
    await app.openReview();
    const changes = page.locator('#review-changes-body');
    await changes.locator('[role="treeitem"][data-path="src/main.mbt"]').click();
    await page.locator('#file-tree-toggle').click();
    const mode = page.locator('#review-mode-toolbar');
    const line = mode.locator('[data-diff-mode="line"]');
    const layout = page.locator('.review-layout-control[role="group"]');
    const split = layout.locator('[data-layout="side-by-side"]');
    await expect(line).toBeEnabled();
    await line.click();
    await changes.hover();
    await expect(split).toBeEnabled();
    await expect(page.locator('.review-hunk-position')).toHaveText('Change 1 of 1');

    // Sample rendered frames, including the gap after reads finish but before
    // the editor publishes its computed hunks. Never expose partial navigation.
    await page.evaluate(() => {
      window.reviewNavigationFrames = [];
      window.sampleReviewNavigation = true;
      const sample = () => {
        const group = document.querySelector('.review-navigation-controls');
        window.reviewNavigationFrames.push({
          visible: !!group?.getClientRects().length,
          breadcrumbFile: document.querySelector('.viewer-breadcrumb .crumb-file')?.textContent,
          file: group?.querySelector('.review-nav-position')?.textContent,
          change: group?.querySelector('.review-hunk-position')?.textContent,
          buttons: Array.from(group?.querySelectorAll('button') ?? []).map(button => button.getAttribute('data-action') || button.id),
        });
        if (window.sampleReviewNavigation) requestAnimationFrame(sample);
      };
      requestAnimationFrame(sample);
    });
    try {
      await changes.locator('[role="treeitem"][data-path="src/lib.mbt"]').click();
      await expect(page.locator('.crumb-file')).toHaveText('lib.mbt');
      await expect.poll(() => app.requests.some(request =>
        request.method === pendingMethod && request.params?.path?.endsWith('/lib.mbt')))
        .toBe(true);
      await expect(line).toBeDisabled();
      await expect(split).toBeDisabled();
      await expect(mode.locator('[data-diff-mode="token"]')).toBeVisible();
      await expect(page.locator('button.review-comments-control')).toBeVisible();
      await expect(page.locator('button.review-tests-control')).toBeVisible();
      await expect(page.locator('.review-navigation-controls')).toBeVisible();
      await expect(page.locator('.review-navigation-controls')).toHaveAttribute('aria-busy', 'true');
      await expect(page.locator('.review-nav-position')).toHaveText('File 1 of 2');
      await expect(page.locator('.review-hunk-position')).toHaveText('Change 1 of 1');
      await expect(page.locator('.review-navigation-controls')).toHaveAttribute('inert', '');
      await expect(page.locator('.viewer-breadcrumb .crumb-file')).toHaveText('lib.mbt');
      // A deliberately held read eventually shows the delayed overlay. Its
      // timing is independent of whether navigation retains a complete display.
      await expect(page.locator('.viewer-notice')).toBeVisible();
      await expect(page.locator('.review-navigation-controls')).toContainText('File 1 of 2');
    } finally {
      release();
    }
    await expect(line).toBeEnabled();
    await expect(split).toBeEnabled();
    await expect(page.locator('.review-hunk-position')).toHaveText('Change 1 of 15');
    await expect(page.locator('#review-hunk-toggle')).toBeEnabled();
    await expect(page.locator('.review-nav-position')).toHaveText('File 2 of 2');
    await expect(page.locator('.review-navigation-controls')).toHaveAttribute('aria-busy', 'false');
    await expect(page.locator('.viewer-notice')).toBeHidden();
    const frames = await page.evaluate(() => {
      window.sampleReviewNavigation = false;
      return window.reviewNavigationFrames;
    });
    for (const frame of frames) {
      expect(frame.visible).toBe(true);
      expect(['main.mbt', 'lib.mbt']).toContain(frame.breadcrumbFile);
      expect(frame.change).toBe(frame.file === 'File 1 of 2' ? 'Change 1 of 1' : 'Change 1 of 15');
      expect(frame.buttons).toEqual(['previous-diff-change', 'next-diff-change', 'review-hunk-toggle']);
    }
    expect(frames.length).toBeGreaterThan(0);
    expect(app.pageErrors).toEqual([]);
  });
}

test('ordinary MBTI files default to source, render UML on demand, and reviews keep source surfaces', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  const path = 'api/pkg.generated.mbti';
  const working = [
    'package "fixture/api"',
    '',
    'pub struct Point {',
    '  x : Double',
    '  y : Double',
    '}',
    '',
    'pub trait Shape {',
    '  area(Self) -> Double',
    '}',
    '',
    'impl Shape for Point',
  ].join('\n');
  const baseline = working.replace('  y : Double\n', '');
  app.searchFiles = [path];
  app.workingFiles[path] = working;
  app.gitChanges = [{
    path,
    index_status: ' ',
    worktree_status: 'M',
    kind: 'modified',
  }];
  app.gitFilesByRevision[app.gitBaseline][path] = baseline;

  await app.install();
  await app.goto();
  await app.openSession();
  await app.openQuickOpen();
  await page.locator('#quick-open-list [data-path="api/pkg.generated.mbti"]').click();

  const diagram = page.locator('#mbti-diagram-host');
  const view = page.locator('.mbti-view-toolbar');
  await expect(page.locator('#viewer-host')).toBeVisible();
  await expect(page.locator('#viewer-host')).toContainText('Point');
  await expect(view.locator('[id$="-view-source"]')).toHaveAttribute(
    'aria-pressed',
    'true',
  );
  await expect(diagram).toBeHidden();
  await view.locator('#mbti-view-diagram').click();

  await expect(diagram).toBeVisible();
  await expect(page.locator('#viewer-host')).toBeHidden();
  await expect(diagram.locator('svg')).toBeVisible();
  await expect(diagram.locator('svg')).toContainText('Point');
  await expect(
    diagram.locator('.moonbit-viewer-markdown-diagram-controls'),
  ).toBeVisible();
  await expect(
    diagram.locator('.moonbit-viewer-markdown-diagram-zoom-in'),
  ).toBeVisible();
  await expect(view.getByRole('button')).toHaveText(['Diagram', 'Source']);
  await expect(view.locator('#mbti-view-diagram')).toHaveAttribute(
    'aria-pressed',
    'true',
  );

  await view.locator('[id$="-view-source"]').click();
  await expect(diagram).toBeHidden();
  await expect(page.locator('#viewer-host')).toBeVisible();
  await expect(page.locator('#viewer-host')).toContainText('Point');
  await expect(view.locator('[id$="-view-source"]')).toHaveAttribute(
    'aria-pressed',
    'true',
  );
  await view.locator('#mbti-view-diagram').click();
  await expect(diagram.locator('svg')).toBeVisible();

  await app.openReview();
  await page.locator('[role="treeitem"][data-path="api/pkg.generated.mbti"]').click();
  await expect(page.locator('.mbti-view-toolbar')).toHaveCount(0);
  await expect(diagram).toBeHidden();
  const review = page.locator('#review-mode-toolbar');
  await expect(review.locator('[data-diff-mode="line"]')).toHaveAttribute(
    'aria-pressed',
    'true',
  );
  await review.locator('[data-review-mode="file"]').click();
  await expect(page.locator('#viewer-host')).toBeVisible();
  await expect(page.locator('#viewer-host')).toContainText('Point');
  await expect(diagram).toBeHidden();
  expect(app.pageErrors).toEqual([]);
});

test('ordinary moon.mod defaults to source and loads its package graph on demand', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  const path = 'moon.mod';
  const working = [
    'name = "example/app"',
    'version = "0.1.0"',
    '',
  ].join('\n');
  app.searchFiles = [path];
  app.workingFiles[path] = working;

  await app.install();
  await app.goto();
  await app.openSession();
  await app.openQuickOpen();
  await page.locator('#quick-open-list [data-path="moon.mod"]').click();

  const diagram = page.locator('#package-diagram-host');
  const view = page.locator('.moon-mod-view-toolbar');
  await expect(page.locator('#viewer-host')).toBeVisible();
  await expect(page.locator('#viewer-host')).toContainText('example/app');
  await expect(view.locator('[id$="-view-source"]')).toHaveAttribute(
    'aria-pressed',
    'true',
  );
  await expect(diagram).toBeHidden();
  expect(app.requests.filter(
    request => request.method === 'moon.package_graph',
  )).toHaveLength(0);
  await view.locator('#moon-mod-view-dependencies').click();

  await expect.poll(() => app.requests.find(
    request => request.method === 'moon.package_graph',
  )).toMatchObject({
    params: {
      session: 'session-1',
      root: '/workspace',
      path: 'moon.mod',
    },
  });
  await expect(diagram).toBeVisible();
  await expect(diagram.locator('svg')).toBeVisible();
  await expect(diagram.locator('svg')).toContainText('main');
  await expect(diagram.locator('svg')).toContainText('core');
  await expect(diagram.locator('svg')).toContainText('util');
  await expect(
    diagram.locator('.moonbit-viewer-markdown-diagram-controls'),
  ).toBeVisible();
  await expect(
    diagram.locator('.moonbit-viewer-markdown-diagram-fit'),
  ).toBeVisible();

  await expect(view.getByRole('button')).toHaveText(['Dependency graph', 'Source']);
  await expect(
    view.locator('#moon-mod-view-dependencies'),
  ).toHaveAttribute('aria-pressed', 'true');

  await view.locator('[id$="-view-source"]').click();
  await expect(diagram).toBeHidden();
  await expect(page.locator('#viewer-host')).toBeVisible();
  await expect(page.locator('#viewer-host')).toContainText('example/app');
  await expect(view.locator('[id$="-view-source"]')).toHaveAttribute(
    'aria-pressed',
    'true',
  );

  await view.locator('#moon-mod-view-dependencies').click();
  await expect(diagram.locator('svg')).toBeVisible();
  expect(app.requests.filter(
    request => request.method === 'moon.package_graph',
  )).toHaveLength(1);
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
      },
    });
  const history = page.locator('#git-commit-history');
  const head = history.locator(`[data-commit="${app.gitHead}"]`);
  const merge = history.locator(`[data-commit="${app.gitMerge}"]`);
  const parent = history.locator(`[data-commit="${app.gitParent}"]`);
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
  const historicalMain = history.locator('.git-history-file[data-path="src/main.mbt"]');
  await historicalMain.click();
  await expect(history).toBeHidden();
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
  const algorithms = page.locator('.review-history-mode-toolbar');
  await expect(algorithms.locator('[data-diff-mode="token"]')).toHaveAttribute(
    'aria-pressed',
    'true',
  );
  await expect(algorithms.getByRole('button')).toHaveText(['Line', 'Token', 'Tree']);
  await expect(page.locator('button.review-comments-control')).toBeEnabled();
  await expect(page.locator('button.review-tests-control')).toBeEnabled();
  expect(app.pageErrors).toEqual([]);
});

test('Git history and commit failures retry through the browser transport', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.rpcErrors.set('git.history', 'unknown command');
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openReview({ waitForHistory: false });

  await expect(page.locator('.git-graph-message')).toBeVisible();
  await expect(page.locator('.git-graph-message')).toContainText('unknown command');
  app.rpcErrors.delete('git.history');
  await page.locator('.git-graph-message button').click();
  const history = page.locator('#git-commit-history');
  const head = history.locator(`[data-commit="${app.gitHead}"]`);
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
  await commitFailure.getByRole('button').click();
  await expect(
    history.locator('.git-history-file[data-path="src/main.mbt"]'),
  ).toBeVisible();
  await expect.poll(() => app.requests.filter(request =>
    request.method === 'git.commit_changes').length).toBe(2);
  expect(app.pageErrors).toEqual([]);
});

test('quick open moves its keyboard selection and opens the chosen file', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openQuickOpen();
  const input = page.locator('#quick-open-input');
  await expect(input).toBeFocused();
  const mainResult = page.locator('#quick-open-list [data-path="src/main.mbt"]');
  const readmeResult = page.locator('#quick-open-list [data-path="README.md"]');
  await expect(mainResult).toBeVisible();
  await expect(readmeResult).toBeVisible();
  await expect(mainResult).toHaveAttribute('aria-selected', 'true');
  await input.press('ArrowDown');
  await expect(readmeResult).toHaveAttribute('aria-selected', 'true');
  await input.press('ArrowUp');
  await expect(mainResult).toHaveAttribute('aria-selected', 'true');
  await input.press('Enter');

  await expect(input).toBeHidden();
  await expect.poll(() => app.requests.find(request =>
    request.method === 'fs.read_file' &&
    request.params?.path === '/workspace/src/main.mbt')).toBeTruthy();
  expect(app.pageErrors).toEqual([]);
});

test('tab strip closes every tab type into the New Tab launcher', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();

  await app.openQuickOpen();
  await page.locator('#quick-open-list [data-path="src/main.mbt"]').click();
  await app.openQuickOpen();
  await page.locator('#quick-open-input').fill('README');
  await page.locator('#quick-open-list [data-path="README.md"]').click();

  const fileTabs = page.locator('.editor-tab');
  await expect(fileTabs).toHaveCount(2);
  await page.locator('.editor-tab[data-path="/workspace/src/main.mbt"]').click();
  await expect(page.locator('.editor-tab[data-path="/workspace/src/main.mbt"]')).toHaveClass(/active/);
  await app.openReview();
  await expect(fileTabs).toHaveCount(3);
  const closeAll = page.locator('#dock-close-all');
  await expect(closeAll).toBeEnabled();
  await closeAll.click();
  await expect(fileTabs).toHaveCount(0);
  await expect(page.locator('.dock-launcher')).toBeVisible();
  await expect(closeAll).toBeDisabled();
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
  await page.locator('#quick-open-list [data-path="src/main.mbt"]').click();

  const breadcrumb = page.locator('.viewer-breadcrumb');
  const sourceDirectory = breadcrumb.locator('.crumb-directory[data-path="src"]');
  await sourceDirectory.click();
  await expect.poll(() => app.requests.find(request =>
    request.method === 'fs.read_directory' && request.params?.path === '/workspace/src'))
    .toBeTruthy();
  const menu = page.locator('#breadcrumb-directory-picker');
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
  const nested = page.locator('#breadcrumb-directory-picker');
  await expect(nested).toContainText('This folder is empty.');
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
        payload: {
          content: 'First answer recovered after the tool failed.',
          tool_calls: [{ id: 'failed-after-answer', name: 'shell', arguments: '{}' }],
        },
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

  const overview = page.locator('.transcript-overview');
  const ticks = overview.locator('.overview-tick-button');
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

  await overview.dispatchEvent('mouseleave');
  await expect(overview.getByRole('tooltip')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('tool-call tabs keep focus-driven scrolling inside the transcript', async ({ page }) => {
  await page.addInitScript(() => localStorage.setItem('openseek.minimal_transcript', 'false'));
  const app = new DesktopBrowserHarness(page);
  const events = [
    {
      sequence: 1,
      item: {
        kind: 'user',
        payload: { content: 'Show the browser fixture with a long transcript' },
      },
    },
  ];
  let sequence = 2;
  for (let row = 1; row <= 100; row += 1) {
    events.push({
      sequence,
      item: {
        kind: 'assistant',
        payload: { content: `Transcript filler row ${row}` },
      },
    });
    sequence += 1;
  }
  events.push({
    sequence,
    item: {
      kind: 'assistant',
      payload: {
        content: '',
        tool_calls: [
          {
            id: 'deep-tabbed-call',
            name: 'mbtx',
            arguments: JSON.stringify({
              source: 'fn main { println("browser fixture") }',
              description: 'Print <browser> fixture',
            }),
          },
        ],
      },
    },
  });
  app.sessionEvents = events;
  await app.install();
  await app.goto();
  // Proton's current CEF does not use the size container as the absolute
  // positioning root. Neutralize Chromium's newer behavior so this browser
  // test exercises the same geometry as the shipping desktop host.
  await page.addStyleTag({ content: '#transcript { container-type: normal; }' });
  await app.openSession();

  const transcript = page.locator('#transcript');
  await expect(transcript.locator('.tool-call-summary')).toContainText('Print <browser> fixture');
  const tabs = transcript.locator('.tool-call-tabs');
  const originalJson = tabs.locator('[data-tool-tab="original-json"]');
  await transcript.locator('.tool-call-summary').click();
  // Revealing a contained row must not scroll the fixed shell either; the
  // document can remain at zero while #app shifts its entire grid by 1–2px.
  expect(await page.locator('#app').evaluate(node =>
    ({ top: node.scrollTop, left: node.scrollLeft }))).toEqual({ top: 0, left: 0 });
  await transcript.evaluate(node => {
    node.scrollTop = node.scrollHeight;
  });
  await expect(originalJson).toBeVisible();
  expect(await transcript.evaluate(node => node.scrollTop)).toBeGreaterThan(0);
  expect(await page.evaluate(() => document.scrollingElement.scrollTop)).toBe(0);

  await originalJson.click();

  const originalJsonInput = tabs.locator('[data-tool-tab-input="original-json"]');
  await expect(originalJsonInput).toBeChecked();
  await originalJsonInput.focus();
  await expect(originalJsonInput).toBeFocused();
  expect(await page.evaluate(() => document.scrollingElement.scrollTop)).toBe(0);
  expect(await page.locator('#app').evaluate(node =>
    ({ top: node.scrollTop, left: node.scrollLeft }))).toEqual({ top: 0, left: 0 });
  expect(app.pageErrors).toEqual([]);
});

test('selected transcript text can be quoted in a floating reply', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  const filler = Array.from({ length: 40 }, (_, index) => `Filler paragraph ${index + 1}.`);
  app.sessionEvents = [
    {
      sequence: 1,
      item: { kind: 'user', payload: { content: 'Show the browser fixture quote reply' } },
    },
    {
      sequence: 2,
      item: {
        kind: 'assistant',
        payload: {
          content: [...filler, 'First answer paragraph.', 'Second answer paragraph.']
            .join('\n\n'),
        },
      },
    },
  ];
  await app.install();
  await app.goto();
  await app.openSession();

  const transcript = page.locator('#transcript');
  const markdown = page.locator('.transcript .msg-content.markdown');
  // The fixture places its two answer paragraphs after the filler block.
  const first = markdown.locator('p').nth(filler.length);
  const second = markdown.locator('p').nth(filler.length + 1);
  const bar = page.locator('[data-selection-actions][role="toolbar"]');
  const reply = page.locator('[data-selection-actions][role="dialog"]');
  const comment = reply.locator('#selection-reply-input');
  const batch = reply.locator('.selection-reply-batch input');
  const task = page.locator('#task');
  const pinned = () => page.evaluate(() => CSS.highlights.has('quote-reply'));
  const selectWord = paragraph => paragraph.dblclick({ position: { x: 8, y: 8 } });
  const openReply = async paragraph => {
    await selectWord(paragraph);
    await bar.locator('#selection-reply').click();
    await expect(comment).toBeFocused();
  };
  const scrollTranscript = async delta => {
    const box = await transcript.boundingBox();
    await page.mouse.move(box.x + box.width / 2, box.y + 40);
    await page.mouse.wheel(0, delta);
  };

  // Selecting text offers Reply, which keeps the quote pinned while typing.
  await selectWord(first);
  await expect(bar.getByRole('button')).toHaveText(['Copy', 'Reply']);
  await bar.locator('#selection-reply').click();
  await expect(reply.locator('blockquote')).toHaveText('First');
  await expect(comment).toBeFocused();
  expect(await pinned()).toBe(true);
  await expect(reply.locator('.selection-reply-submit')).toBeDisabled();

  // Batched, the reply joins the message being written, which is where the
  // reader lands; nothing is sent.
  await batch.check();
  await expect(comment).toBeFocused();
  await expect(reply.locator('.selection-reply-submit')).toBeEnabled();
  await page.keyboard.type('Why first?');
  await page.keyboard.press('Enter');
  await expect(reply).toHaveCount(0);
  await expect(task).toHaveValue('> First\n\nWhy first?\n\n');
  await expect(task).toBeFocused();
  expect(await pinned()).toBe(false);
  expect(app.requests.some(request => request.method === 'agent.start')).toBe(false);

  // An offer follows its selection: it goes on Escape, when the selection
  // goes, and when a scroll moves the text from under it.
  await selectWord(first);
  await expect(bar).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(bar).toHaveCount(0);
  await selectWord(first);
  await expect(bar).toBeVisible();
  await page.evaluate(() => document.getSelection().removeAllRanges());
  await expect(bar).toHaveCount(0);
  await selectWord(first);
  await expect(bar).toBeVisible();
  await scrollTranscript(-60);
  await expect(bar).toHaveCount(0);
  await scrollTranscript(60);

  // A reply being typed survives a scroll, and closes on Escape or a press
  // elsewhere.
  await openReply(first);
  await page.keyboard.type('Keep me');
  await scrollTranscript(-60);
  await expect(comment).toHaveValue('Keep me');
  await scrollTranscript(60);
  await page.keyboard.press('Escape');
  await expect(reply).toHaveCount(0);
  await openReply(first);
  await page.locator('main .topbar-title').click();
  await expect(reply).toHaveCount(0);
  await expect(task).toHaveValue('> First\n\nWhy first?\n\n');

  // Text selected outside the transcript gets no offer, and neither does a
  // transcript selection left from earlier when the mouse is pressed and
  // released somewhere else.
  const press = (locator, selected) => locator.evaluate((element, selected) => {
    const event = type => new MouseEvent(type, { bubbles: true, button: 0 });
    element.dispatchEvent(event('mousedown'));
    const range = document.createRange();
    range.selectNodeContents(selected ?? element);
    const selection = document.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
    element.dispatchEvent(event('mouseup'));
  }, selected);
  const settled = () => page.evaluate(() => new Promise(resolve => {
    setTimeout(() => requestAnimationFrame(() => requestAnimationFrame(resolve)), 0);
  }));
  const title = page.locator('main .topbar-title');
  await press(title);
  await settled();
  await expect(bar).toHaveCount(0);
  await press(title, await first.elementHandle());
  await settled();
  await expect(bar).toHaveCount(0);
  await press(first);
  await expect(bar).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(bar).toHaveCount(0);

  // Escape meant for another overlay leaves the reply and its text alone.
  await openReply(first);
  await page.keyboard.type('Still here');
  await page.keyboard.press(await page.evaluate(() =>
    navigator.platform.includes('Mac') ? 'Meta+KeyP' : 'Control+KeyP'));
  const quickOpen = page.locator('#quick-open-dialog');
  await expect(quickOpen).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(quickOpen).toHaveCount(0);
  await expect(comment).toHaveValue('Still here');
  await comment.focus();
  await page.keyboard.press('Escape');
  await expect(reply).toHaveCount(0);

  // A composer holding a shell command is not editing a message: it declines
  // the reply, which says so and keeps what was typed until it is taken.
  const batched = '> First\n\nWhy first?\n\n';
  await task.fill('!echo hello');
  await expect(page.locator('.composer-mode-chip')).toBeVisible();
  await openReply(first);
  await page.keyboard.type('Not a command');
  await page.keyboard.press('Enter');
  await expect(reply.getByRole('status')).toHaveText(
    "The message box can't take a reply right now.");
  await expect(comment).toHaveValue('Not a command');
  await expect(task).toHaveValue('!echo hello');
  expect(app.requests.some(request => request.method === 'terminal.open')).toBe(false);
  await task.fill(batched);
  await comment.focus();
  await page.keyboard.press('Enter');
  await expect(reply).toHaveCount(0);
  await expect(task).toHaveValue(`${batched}> First\n\nNot a command\n\n`);
  await task.fill(batched);

  // A reply belongs to the conversation it quotes: leaving that conversation
  // from the keyboard takes the reply off screen instead of retargeting it.
  await openReply(second);
  await page.keyboard.type('Wrong place');
  await page.keyboard.press(await page.evaluate(() =>
    navigator.platform.includes('Mac') ? 'Meta+KeyN' : 'Control+KeyN'));
  await expect(page.locator('.empty-title')).toBeVisible();
  await expect(reply).toHaveCount(0);
  await expect(task).toHaveValue('');
  await app.openSession();
  await expect(second).toBeVisible();
  await expect(reply).toHaveCount(0);
  await expect(task).toHaveValue('> First\n\nWhy first?\n\n');

  // Unbatched, the reply is sent at once with what was already batched.
  await openReply(second);
  await expect(batch).toBeChecked();
  await batch.uncheck();
  await expect(comment).toBeFocused();
  await page.keyboard.type('And this?');
  await page.keyboard.press('Enter');
  await expect(reply).toHaveCount(0);
  await expect.poll(() => app.requests.find(request =>
    request.method === 'agent.start')?.params.task)
    .toBe('> First\n\nWhy first?\n\n> Second\n\nAnd this?');
  await expect(task).toHaveValue('');
  expect(app.pageErrors).toEqual([]);
});

test('a floating reply takes a comment of several lines', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  const filler = Array.from({ length: 40 }, (_, index) => `Filler paragraph ${index + 1}.`);
  app.sessionEvents = [
    {
      sequence: 1,
      item: { kind: 'user', payload: { content: 'Show the browser fixture quote reply' } },
    },
    {
      sequence: 2,
      item: {
        kind: 'assistant',
        payload: { content: [...filler, 'First answer paragraph.'].join('\n\n') },
      },
    },
  ];
  await app.install();
  await app.goto();
  await app.openSession();

  const markdown = page.locator('.transcript .msg-content.markdown');
  const reply = page.locator('[data-selection-actions][role="dialog"]');
  const comment = reply.locator('#selection-reply-input');
  const task = page.locator('#task');
  const openReply = async paragraph => {
    await paragraph.dblclick({ position: { x: 8, y: 8 } });
    await page.locator('[data-selection-actions][role="toolbar"]')
      .locator('#selection-reply').click();
    await expect(comment).toBeFocused();
  };
  const lines = 'Line one\nLine two\nLine three\nLine four';

  // The answer is the paragraph immediately after the fixture's filler block.
  await openReply(markdown.locator('p').nth(filler.length));
  await reply.locator('.selection-reply-batch input').check();
  await expect(comment).toBeFocused();

  // Shift+Enter starts a new line without submitting the comment.
  await page.keyboard.type('Line one');
  await page.keyboard.press('Shift+Enter');
  await page.keyboard.type('Line two');
  await expect(comment).toHaveValue('Line one\nLine two');

  // Text put in whole, as a paste is, keeps its line breaks.
  await page.keyboard.insertText('\nLine three\nLine four');
  await expect(comment).toHaveValue(lines);

  // Enter still delivers, with the lines intact.
  await page.keyboard.press('Enter');
  await expect(reply).toHaveCount(0);
  await expect(task).toHaveValue(`> First\n\n${lines}\n\n`);

  expect(app.pageErrors).toEqual([]);
});

test('approval card mirrors host claims and sends an unclaimed decision', async ({ page }) => {
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
  const pending = {
    run_id: 'run-1', session: 'session-1', answered: false,
    id: 'approval-1', tool_name: 'mbtx',
    detail: 'run this snippet with no sandbox policy',
    body: 'fn main { @myshell.Cmd("npm", ["ci"]) }',
  };
  app.notify('agent.approvals', { generation: 1, approvals: [pending] });

  const approval = page.locator('.composer-approval');
  await expect(approval).toBeVisible();
  // A different client answered: this page must stop offering either decision.
  app.notify('agent.approvals', { generation: 2, approvals: [{ ...pending, answered: true }] });
  await expect(approval.locator('.composer-approval-state')).toBeVisible();
  await expect(approval.getByRole('button')).toHaveCount(0);
  app.notify('agent.approvals', { generation: 3, approvals: [] });
  await expect(approval).toHaveCount(0);

  // A subsequent, unclaimed question is still answerable through the bridge.
  app.notify('agent.approvals', { generation: 4, approvals: [{ ...pending, id: 'approval-2' }] });
  await approval.getByTestId('approval-allow').click();
  await expect.poll(() => app.requests.some(request =>
    request.method === 'agent.approval' &&
    request.params?.run_id === 'run-1' &&
    request.params?.id === 'approval-2' &&
    request.params?.allow === true)).toBe(true);
  await expect(approval.locator('.composer-approval-state')).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('composer sends a turn and stops the accepted run', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();

  const composer = page.locator('#task');
  await composer.fill('Run the browser E2E turn');
  await page.locator('#send').click();
  await expect.poll(() => app.requests.find(request =>
    request.method === 'agent.start'))
    .toMatchObject({
      params: {
        task: 'Run the browser E2E turn',
        session: 'session-1',
      },
    });

  await composer.fill('Steer without losing the interrupt control');
  await expect(page.locator('#stop')).toBeVisible();
  await expect(page.locator('#send')).toBeVisible();
  await page.locator('#stop').click();
  await expect.poll(() => app.requests.find(request =>
    request.method === 'agent.cancel'))
    .toMatchObject({ params: { run_id: 'run-e2e' } });
  expect(app.pageErrors).toEqual([]);
});

test('deleting a live chat asks the host what goes with it and confirms once', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();

  const sent = method => app.requests
    .filter(request => request.method === method)
    .map(request => request.params);
  const stored = page.locator('.conversation-row[title="session-1"]');
  await stored.click();
  await expect(page.locator('#transcript .msg-content.markdown')).toBeVisible();
  const askToDelete = async () => {
    await stored.hover();
    await stored.locator('[id$=":actions-trigger"]').click();
    await page.locator('[id="conversation:openseek.live:remote.device-a:session-1:/workspace:actions-content"] [data-action="delete"]').click();
  };
  const body = page.locator('#delete-chat-dialog');

  // A chat without a worktree: the dialog is the plain one, and Cancel
  // deletes nothing.
  await askToDelete();
  await expect(body.locator('#delete-chat-title')).toBeVisible();
  await expect(body).toContainText('“Rabbita browser fixture” and all of its subagent history');
  await expect(body).toContainText('Project files and Git branches will remain.');
  await expect(body).not.toContainText('worktree');
  expect(sent('session.delete_check')).toEqual([
    { session: 'session-1', workspace: '/workspace' },
  ]);
  await body.locator('.button.secondary').click();
  await expect(body).toBeHidden();
  expect(sent('session.delete')).toEqual([]);
  await expect(stored).toBeVisible();

  // The host is asked again on every click, and the delete removes only
  // what its dialog showed. Here another window repairs the chat's worktree
  // while the plain dialog is open: the confirm names no checkout, so the
  // host stops and the same dialog comes back naming it.
  await askToDelete();
  await expect(body).not.toContainText('worktree');
  expect(sent('session.delete_check')).toHaveLength(2);
  app.sessionCheckout = { worktree: 'wt-1', dirty_paths: [], dirty_path_count: 0 };
  await page.locator('#delete-chat-dialog .button.danger').click();
  await expect(body).toContainText('its worktree checkout wt-1 is removed along with any ignored files in it');
  await expect(body).not.toContainText('uncommitted changes');
  await expect(stored).toBeVisible();

  // Then the checkout turns dirty before the next confirm. That request
  // agreed to remove a clean checkout, so the dialog comes back once more,
  // now with the changed paths, instead of quietly closing.
  app.sessionCheckout = {
    worktree: 'wt-1',
    dirty_paths: ['notes.txt'],
    dirty_path_count: 1,
  };
  await page.locator('#delete-chat-dialog .button.danger').click();
  await expect(body).toContainText('That checkout has uncommitted changes. Changed paths: notes.txt.');
  await expect(stored).toBeVisible();

  // Confirming now agrees to discard what the dialog listed, and there is
  // no further question.
  await page.locator('#delete-chat-dialog .button.danger').click();
  await expect.poll(() => sent('session.delete')).toEqual([
    { session: 'session-1', workspace: '/workspace' },
    { session: 'session-1', workspace: '/workspace', worktree: 'wt-1' },
    { session: 'session-1', workspace: '/workspace', worktree: 'wt-1', force: true },
  ]);
  await expect(body).toBeHidden();

  // Deleting the chat on screen replaces its entry with a fresh draft
  // instead of leaving an unavailable target behind.
  await expect(stored).toHaveCount(0);
  await expect(page.locator('#transcript .msg-content.markdown')).toHaveCount(0);
  await expect(page.locator('.conversation-load-state.failed')).toHaveCount(0);
  await expect(page).toHaveURL(/\/chat\/new$/);
  expect(sent('session.archive')).toEqual([]);
  expect(app.pageErrors).toEqual([]);
});

test('pending conversation selection follows the clicked row', { tag: '@motion' }, async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.liveSessions.push({
    id: 'session-2',
    title: 'Second browser fixture',
    updated_at_ms: 2,
  });
  await app.install();
  await app.goto();

  const first = page.locator('.conversation-row[title="session-1"]');
  await first.locator('.conversation-content').click();
  await expect(first).toHaveClass(/active/);
  await expect(page.locator('#transcript .msg-content.markdown')).toBeVisible();

  app.rpcDelays.set('session.load', 10000);
  const second = page.locator('.conversation-row[title="session-2"]');
  await second.click();
  await expect(second).toHaveClass(/active/);
  await expect(first).not.toHaveClass(/active/);
  await expect(second.locator('.conversation-load-spinner')).toBeVisible();
  await expect(page.locator('.conversation-load-state:not(.failed)')).toBeVisible();
  const loading = second.locator('.conversation-load-spinner');
  const moving = () => loading.evaluate(node => node.getAnimations({ subtree: true })
    .some(animation => animation.playState === 'running'));
  await expect.poll(moving).toBe(true);
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await expect.poll(moving).toBe(false);
  await expect(page.locator('#transcript .msg-content.markdown')).toHaveCount(0);
  await expect.poll(() => app.requests.some(request =>
    request.method === 'session.load' && request.params?.session === 'session-2'))
    .toBe(true);
  expect(app.pageErrors).toEqual([]);
});

test('archiving a pending selection resolves the same destination as read only', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.liveSessions.push({
    id: 'session-2',
    title: 'Second browser fixture',
    updated_at_ms: 2,
  });
  await app.install();
  await app.goto();

  app.rpcDelays.set('session.load', 10000);
  const pending = page.locator('.conversation-row[title="session-2"]');
  await pending.click();
  await expect(pending).toHaveClass(/active/);
  await expect(page.locator('.conversation-load-state:not(.failed)')).toBeVisible();

  app.liveSessions = app.liveSessions.filter(session => session.id !== 'session-2');
  app.archivedSessions.push({
    id: 'session-2',
    title: 'Second browser fixture',
    updated_at_ms: 2,
  });
  app.notify('session.changed', {
    change: 'archived',
    session: 'session-2',
    workspace: '/workspace',
  });

  await expect(page.locator('.archived-read-only-text')).toBeVisible();
  await expect(page).toHaveURL(/\/chat\/session\/session-2$/);
  await expect(page.locator('#task')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('a failed first conversation load keeps selection and can retry', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.rpcErrors.set('session.load', 'fixture unavailable');
  await app.install();
  await app.goto();

  const row = page.locator('.conversation-row[title="session-1"]');
  await row.click();
  await expect(row).toHaveClass(/active/);
  await expect(page.locator('.conversation-load-state.failed')).toBeVisible();
  await expect(page.locator('.conversation-load-state-message')).toBeVisible();
  await expect(page.locator('.conversation-load-state-message')).toContainText('fixture unavailable');
  await expect(row).toHaveClass(/load-failed/);

  app.rpcErrors.delete('session.load');
  await page.locator('.conversation-load-state.failed button').click();
  await expect(page.locator('#transcript .msg-content.markdown')).toBeVisible();
  await expect(row).toHaveClass(/active/);
  await expect(row).not.toHaveClass(/load-failed/);
  expect(app.pageErrors).toEqual([]);
});

test('settings persist host API changes through settings.set', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();

  await page.locator('#sidebar-settings').click();
  await expect(page.locator('#management-dialog [data-slot="dialog-title"]')).toBeVisible();
  await page.locator('#settings-api-provider-select:visible, #setup-api-provider-select:visible').click();
  await page.locator('#settings-api-provider-select-menu [data-value="custom"]').click();
  await expect.poll(() => app.requests.some(request =>
    request.method === 'settings.set' &&
    request.params?.provider === 'custom')).toBe(true);

  await page.locator('#settings-api-url').fill(
    'https://example.test/chat/completions',
  );
  await expect.poll(() => app.requests.some(request =>
    request.method === 'settings.set' &&
    request.params?.custom_api_url === 'https://example.test/chat/completions'))
    .toBe(true);
  await expect(page.locator('#settings-api-url')).toHaveValue(
    'https://example.test/chat/completions',
  );
  expect(app.pageErrors).toEqual([]);
});

test('initial OpenRouter setup only needs an API key', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.hostSettings.has_deepseek_key = false;
  await app.install();
  await app.goto();

  await expect(page.locator('#api-setup-dialog')).toBeVisible();
  await page.locator('#settings-api-provider-select:visible, #setup-api-provider-select:visible').click();
  await page.locator('#setup-api-provider-select-menu [data-value="openrouter"]').click();
  await page.locator('#setup-api-key').fill('sk-openrouter-test');
  await page.locator('#setup-api-save-key').click();

  await expect.poll(() => app.requests.some(request =>
    request.method === 'settings.set' &&
    request.params?.provider === 'custom' &&
    request.params?.custom_api_url === 'https://openrouter.ai/api/v1/chat/completions')).toBe(true);
  await expect.poll(() => app.requests.some(request =>
    request.method === 'settings.set' &&
    request.params?.provider === 'custom' &&
    request.params?.custom_api_key === 'sk-openrouter-test')).toBe(true);
  await expect(page.locator('#api-setup-dialog')).toBeHidden();
  expect(app.requests.some(request => request.method === 'settings.set' && request.params?.deepseek_api_key !== undefined)).toBe(false);

  // OpenRouter uses the ordinary chat model selector and persisted preference.
  await app.openSession();
  await page.locator('#openseek-model-picker, #codex-model-picker').click();
  await page.locator('#openseek-model-picker-menu [data-value="openseek:deepseek-v4-pro"]').click();
  await expect.poll(() => page.evaluate(() => localStorage.getItem('openseek.model')))
    .toBe('deepseek-v4-pro');
  await page.locator('#openseek-model-picker, #codex-model-picker').click();
  await page.locator('#openseek-model-picker-menu [data-value="openseek:deepseek-flash"]').click();
  await expect.poll(() => page.evaluate(() => localStorage.getItem('openseek.model')))
    .toBe('deepseek-flash');
  await page.locator('#sidebar-settings').click();
  expect(app.pageErrors).toEqual([]);
});

test('Codex account login can be started and cancelled from Settings', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.codexRequiresAuth = true;
  await app.install();
  await app.goto();

  await page.locator('#sidebar-settings').click();
  await page.locator('#codex-login').click();
  await expect.poll(() => app.requests.some(request =>
    request.method === 'codex.account.login.start')).toBe(true);
  await expect(page.locator('#codex-login-open')).toHaveAttribute(
    'href',
    'https://example.test/codex-login',
  );

  await page.locator('#codex-login-cancel').click();
  await expect.poll(() => app.requests.some(request =>
    request.method === 'codex.account.login.cancel' &&
    request.params?.loginId === 'login-e2e')).toBe(true);
  await expect(page.locator('#codex-login')).toBeVisible();
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
  await page.locator('#openseek-model-picker, #codex-model-picker').click();
  await page.locator('#openseek-model-picker-menu [data-value="codex:gpt-5.4-codex"]').click();
  await expect.poll(() => app.requests.find(request =>
    request.method === 'codex.draft.open'))
    .toMatchObject({ params: { cwd: '/workspace' } });

  // The request leaves in the same update that selects the Codex draft, a
  // frame before the Codex composer replaces SeekMoon's in the shared #task.
  // Wait for the destination textbox rather than filling the old one.
  await expect(page.locator('#codex-model-picker')).toBeVisible();
  await page.locator('#task').fill('Run the Codex browser E2E turn');
  await page.locator('#send').click();
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

  await page.locator('#stop').click();
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

test('workspace settings dialog opens and persists per-workspace choices', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();

  // The project row's "⋮" menu opens its workspace settings dialog.
  await app.projectRow('/workspace').hover();
  await page.locator('[id="project:openseek.projects:remote.device-a:/workspace:actions-trigger"]').click();
  await page.locator('[id="project:openseek.projects:remote.device-a:/workspace:actions-content"] [data-action="settings"]').click();
  const workspaceSettings = page.locator('#workspace-settings-dialog');
  await expect(workspaceSettings).toBeVisible();
  await expect(workspaceSettings.locator('.settings-subtitle')).toHaveText('/workspace');

  // The dialog reads the host's authoritative snapshot before enabling the
  // selects.
  await expect.poll(() => app.requests.find(request =>
    request.method === 'workspace.settings_get')).toMatchObject({
    params: { workspace: '/workspace' },
  });

  const launchMode = page.locator('#workspace-default-mode-select');
  await expect(launchMode).toBeEnabled();
  await launchMode.click();
  await page.locator('#workspace-default-mode-select-menu [data-value="worktree"]').click();
  await expect.poll(() => app.requests.find(request =>
    request.method === 'workspace.settings_set' &&
    request.params?.worktree_mode === true)).toBeTruthy();
  // Wait for the harness store to settle before replaying the commit
  // broadcast, so the optimistic mirror is never rolled back by a
  // pre-mutation payload.
  await expect.poll(() => app.workspaceSettingsFor('/workspace').worktree_mode).toBe(true);
  app.notify(
    'workspace.settings_changed',
    { ...app.workspaceSettingsFor('/workspace') },
  );
  await launchMode.click();
  await expect(page.locator('#workspace-default-mode-select-menu [data-value="worktree"]')).toHaveAttribute('aria-selected', 'true');
  await page.keyboard.press('Escape');

  const submodules = page.locator('#workspace-submodules-select');
  await submodules.click();
  await page.locator('#workspace-submodules-select-menu [data-value="checkout"]').click();
  await expect.poll(() => app.requests.find(request =>
    request.method === 'workspace.settings_set' &&
    request.params?.checkout_submodules === true)).toBeTruthy();
  await expect.poll(() => app.workspaceSettingsFor('/workspace').checkout_submodules).toBe(true);
  app.notify(
    'workspace.settings_changed',
    { ...app.workspaceSettingsFor('/workspace') },
  );

  const timeout = page.locator('#workspace-submodule-timeout-select');
  await timeout.click();
  await page.locator('#workspace-submodule-timeout-select-menu [data-value="60"]').click();
  await expect.poll(() => app.requests.find(request =>
    request.method === 'workspace.settings_set' &&
    request.params?.submodule_checkout_timeout_seconds === 60)).toBeTruthy();
  await expect.poll(() =>
    app.workspaceSettingsFor('/workspace').submodule_checkout_timeout_seconds,
  ).toBe(60);
  app.notify(
    'workspace.settings_changed',
    { ...app.workspaceSettingsFor('/workspace') },
  );

  // Close and re-enter: the dialog keeps the committed values.
  await page.locator('#workspace-settings-dialog [data-slot="dialog-close"]').click();
  await app.projectRow('/workspace').hover();
  await page.locator('[id="project:openseek.projects:remote.device-a:/workspace:actions-trigger"]').click();
  await page.locator('[id="project:openseek.projects:remote.device-a:/workspace:actions-content"] [data-action="settings"]').click();
  for (const [control, value] of [
    ['workspace-default-mode-select', 'worktree'],
    ['workspace-submodules-select', 'checkout'],
    ['workspace-submodule-timeout-select', '60'],
  ]) {
    await page.locator(`#${control}`).click();
    await expect(page.locator(`#${control}-menu [data-value="${value}"]`)).toHaveAttribute('aria-selected', 'true');
    await page.keyboard.press('Escape');
  }
  // Settings are stored per workspace: committing this workspace's values
  // never writes to a sibling project.
  expect(app.requests.filter(request => request.method === 'workspace.settings_set' && request.params?.workspace === '/other')).toEqual([]);

  // A detached project must no longer expose editable workspace settings.
  app.notify('workspace.changed', { workspaces: [] });
  await expect(workspaceSettings).toBeHidden();

  expect(app.pageErrors).toEqual([]);
});

test('composer can steer a turn without changing its queue default', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.hostSettings.followup_behavior = 'queue';
  await app.install();
  await app.goto();
  await app.openSession();
  const composer = page.locator('#task');
  await composer.fill('Start a turn');
  await page.locator('#send').click();
  const choice = page.locator('#composer-followup-select');
  await choice.click();
  await expect(page.locator('#composer-followup-select-menu [data-value="queue"]')).toHaveAttribute('aria-selected', 'true');
  await page.keyboard.press('Escape');
  await composer.fill('Correct the current turn');
  await choice.click();
  await page.locator('#composer-followup-select-menu [data-value="steer"]').click();
  await composer.press('Enter');
  await expect.poll(() => app.requests.find(r => r.method === 'agent.steer'))
    .toMatchObject({ params: { text: 'Correct the current turn' } });
  await choice.click();
  await expect(page.locator('#composer-followup-select-menu [data-value="queue"]')).toHaveAttribute('aria-selected', 'true');
  expect(app.requests.filter(r => r.method === 'settings.set')).toEqual([]);
  expect(app.pageErrors).toEqual([]);
});

for (const mode of ['Line', 'Tree']) {
  test(`${mode} hunk actions and navigation follow manual scrolling`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    const block = (name) => [`fn ${name} {`, ...Array.from({ length: 70 }, (_, i) => `  println("${name} ${i}")`), '}', ''];
    const baseline = [...block('first'), ...block('second')].join('\n');
    app.gitFilesByRevision[app.gitBaseline]['src/main.mbt'] = baseline;
    app.workingFiles['src/main.mbt'] = baseline.replace('first 5', 'first changed').replace('second 60', 'second changed');
    await app.install();
    await app.goto();
    await app.openSession();
    await app.openReview();
    await page.locator('#review-changes-body').locator('[role="treeitem"][data-path="src/main.mbt"]').click();
    const toolbar = page.locator('#review-mode-toolbar');
    await toolbar.locator(`[data-diff-mode="${mode.toLowerCase()}"]`).click();
    const position = page.locator('.review-hunk-position');
    await expect(position).toHaveText('Change 1 of 2');
    // Wheel input must update the counter without moving the cursor or marking
    // coverage. The last hunk's action must then affect exactly that hunk.
    const visibleEditor = page.locator('.moonbit-diff-editor:visible').last();
    await visibleEditor.hover();
    await page.mouse.wheel(0, 10000);
    await expect(position).toHaveText('Change 2 of 2');
    await expect(page.locator('#review-hunk-toggle')).toHaveAttribute('aria-pressed', 'false');
    const localAction = page.locator('.moonbit-diff-hunk-action:visible .review-hunk-marker').last();
    await localAction.click();
    await expect(localAction).toBeFocused();
    await expect(page.locator('#review-hunk-toggle')).toHaveAttribute('aria-pressed', 'true');
    await expect(page.locator('#review-file-toggle')).toHaveAttribute('aria-pressed', 'mixed');
    await page.mouse.wheel(0, -10000);
    await expect(position).toHaveText('Change 1 of 2');
    await expect(page.locator('#review-hunk-toggle')).toHaveAttribute('aria-pressed', 'false');
    await visibleEditor.hover();
    await page.mouse.wheel(0, 10000);
    await expect(position).toHaveText('Change 2 of 2');
    await expect(page.locator('#review-hunk-toggle')).toHaveAttribute('aria-pressed', 'true');
    await page.locator('.moonbit-diff-hunk-action:visible .review-hunk-marker').last().click();
    await expect(page.locator('#review-file-toggle')).toHaveAttribute('aria-pressed', 'false');
    await visibleEditor.hover();
    await page.mouse.wheel(0, -10000);
    await expect(position).toHaveText('Change 1 of 2');
    await page.locator('[data-action="next-diff-change"]').click();
    await expect(position).toHaveText('Change 2 of 2');
    await expect(page.locator('#review-hunk-toggle')).toHaveAttribute('aria-pressed', 'false');
    expect(app.pageErrors).toEqual([]);
  });
}

{
  const mode = 'Tree';

  test(`${mode} navigation enters the boundary after every section is collapsed`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    const baseline = ['fn first() -> Int { 1 }', '', 'fn second() -> Int { 2 }', ''].join('\n');
    app.gitFilesByRevision[app.gitBaseline]['src/main.mbt'] = baseline;
    app.workingFiles['src/main.mbt'] = baseline.replace('{ 1 }', '{ 10 }').replace('{ 2 }', '{ 20 }');
    await app.install();
    await app.goto();
    await app.openSession();
    await app.openReview();
    await page.locator('#review-changes-body').locator('[role="treeitem"][data-path="src/main.mbt"]').click();
    await page.locator('#review-mode-toolbar').locator(`[data-diff-mode="${mode.toLowerCase()}"]`).click();
    const sections = page.locator('.semantic-diff-entry');
    const headers = sections.locator('.semantic-entry-header-content');
    await expect(sections).toHaveCount(2);
    for (const header of await headers.all()) {
      await header.click();
      await expect(header).toHaveAttribute('aria-expanded', 'false');
    }
    const position = page.locator('.review-hunk-position');
    for (const next of ['button', 'F7']) {
      if (next === 'button') {
        await page.locator('[data-action="next-diff-change"]').click();
      } else {
        await page.keyboard.press('F7');
      }
      await expect(headers.nth(0)).toHaveAttribute('aria-expanded', 'true');
      await expect(headers.nth(1)).toHaveAttribute('aria-expanded', 'false');
      await expect(position).toHaveText('Change 1 of 2');
      await headers.nth(0).click();
      await expect(headers.nth(0)).toHaveAttribute('aria-expanded', 'false');
    }
    await page.keyboard.press('Shift+F7');
    await expect(headers.nth(0)).toHaveAttribute('aria-expanded', 'false');
    await expect(headers.nth(1)).toHaveAttribute('aria-expanded', 'true');
    await expect(position).toHaveText('Change 2 of 2');
    expect(app.pageErrors).toEqual([]);
  });
}

for (const layout of ['Split', 'Unified']) {
  test(`${layout} pure deletion can be marked reviewed from its hunk action`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    const before = ['fn main {', '  println("keep")', '  println("delete me")', '  println("keep too")', '}', ''].join('\n');
    app.gitFilesByRevision[app.gitBaseline]['src/main.mbt'] = before;
    app.workingFiles['src/main.mbt'] = before.replace('  println("delete me")\n', '');
    await app.install();
    await app.goto();
    await app.openSession();
    await app.openReview();
    await page.locator('#review-changes-body').locator('[role="treeitem"][data-path="src/main.mbt"]').click();
    await page.locator('[data-diff-mode="line"]').click();
    await page.locator(`[data-layout="${layout === 'Split' ? 'side-by-side' : 'inline'}"]`).click();
    const action = page.locator('.moonbit-diff-hunk-action:visible .review-hunk-marker');
    await expect(action).toBeVisible();
    await action.click();
    await expect(action).toHaveText('✓');
    await expect(page.locator('#review-file-toggle')).toHaveAttribute('aria-pressed', 'true');
    await action.click();
    await expect(page.locator('#review-file-toggle')).toHaveAttribute('aria-pressed', 'false');
    expect(app.pageErrors).toEqual([]);
  });
}

test('project picker capture preserves focused controls and is removed on close', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  const open = await sidebarAddProject(page);
  const picker = page.locator('#project-picker-dialog');
  for (let i = 0; i < 2; i++) {
    await open.click();
    await expect(picker).toBeVisible();
    await page.keyboard.press('Control+l');
    const path = page.locator('#project-picker-path-input');
    await expect(path).toBeFocused();
    // Escape belongs to the focused editor first, not to the modal capture.
    await path.press('Escape');
    await expect(path).toBeHidden();
    await expect(picker).toBeVisible();
    // Enter on Cancel must activate that button, not register the directory.
    const cancel = picker.locator('[data-slot="dialog-footer"] .button.secondary');
    await cancel.focus();
    await cancel.press('Enter');
    await expect(picker).toBeHidden();
  }
  expect(app.requests.filter(request => request.method === 'workspace.add')).toHaveLength(0);
  // A removed capture listener must not consume later key or paste events.
  const handled = await page.evaluate(() => {
    const key = new KeyboardEvent('keydown', { key: 'l', ctrlKey: true, bubbles: true, cancelable: true });
    const paste = new ClipboardEvent('paste', { bubbles: true, cancelable: true });
    document.dispatchEvent(key);
    document.dispatchEvent(paste);
    return [key.defaultPrevented, paste.defaultPrevented];
  });
  expect(handled).toEqual([false, false]);
  expect(app.pageErrors).toEqual([]);
});

for (const [platform, modifier] of [['MacIntel', 'Meta'], ['Win32', 'Control']]) {
  test(`font size shortcuts clamp and persist on ${platform}`, async ({ page }) => {
    await page.addInitScript(platform => {
      Object.defineProperty(navigator, 'platform', { get: () => platform });
      Object.defineProperty(navigator, 'userAgentData', { get: () => undefined });
    }, platform);
    const app = new DesktopBrowserHarness(page);
    await app.install();
    await app.goto();
    await page.locator('#sidebar-settings').click();
    const slider = page.locator('#font-size-slider');
    await slider.focus();
    await page.keyboard.press(`${modifier}+Equal`);
    await expect(slider).toHaveValue('15');
    await page.keyboard.press(`${modifier}+Shift+Equal`);
    await expect(slider).toHaveValue('16');
    await page.keyboard.press(`${modifier}+Minus`);
    await expect(slider).toHaveValue('15');
    await page.keyboard.press(`${modifier}+Alt+Equal`);
    await expect(slider).toHaveValue('15');
    // Capture must prevent the browser's zoom even for held-key repeats.
    const prevented = await slider.evaluate((element, modifier) => {
      const event = new KeyboardEvent('keydown', {
        key: '+', code: 'Equal', shiftKey: true,
        metaKey: modifier === 'Meta', ctrlKey: modifier === 'Control',
        repeat: true, bubbles: true, cancelable: true,
      });
      element.dispatchEvent(event);
      return event.defaultPrevented;
    }, modifier);
    expect(prevented).toBe(true);
    await expect(slider).toHaveValue('16');
    for (let i = 0; i < 5; i++) await page.keyboard.press(`${modifier}+Equal`);
    await expect(slider).toHaveValue('18');
    for (let i = 0; i < 9; i++) await page.keyboard.press(`${modifier}+Minus`);
    await expect(slider).toHaveValue('12');
    await page.reload();
    await page.locator('#sidebar-settings').click();
    await expect(slider).toHaveValue('12');
    expect(app.pageErrors).toEqual([]);
  });
}

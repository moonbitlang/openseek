import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('workspace search supports toggles and keyboard navigation', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();

  const shortcut = await page.evaluate(() =>
    navigator.platform.includes('Mac') ? 'Meta+Shift+F' : 'Control+Shift+F');
  await page.keyboard.press(shortcut);

  const tabs = page.getByRole('tablist', { name: 'Explorer views' });
  const filesTab = tabs.getByRole('tab', { name: 'Files' });
  const searchTab = tabs.getByRole('tab', { name: 'Search' });
  await expect(searchTab).toHaveAttribute('aria-selected', 'true');

  const query = page.getByRole('textbox', { name: 'Search' });
  await expect(query).toBeFocused();

  const wholeWord = page.getByRole('button', { name: 'Match Whole Word' });
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

  // Line diff keeps semantic-only filters inert. Token and Tree make those
  // user controls available.
  const ignoreComments = page.getByRole('button', { name: 'Ignore comments' });
  const ignoreTests = page.getByRole('button', { name: 'Ignore tests' });
  await expect(ignoreComments).toBeDisabled();
  await expect(ignoreTests).toBeDisabled();

  await reviewToolbar.getByRole('button', { name: 'File view' }).click();
  await expect(reviewToolbar.getByRole('button', { name: 'File view' })).toHaveAttribute(
    'aria-pressed',
    'true',
  );
  await reviewToolbar.getByRole('button', { name: 'Line diff' }).click();

  await reviewToolbar.getByRole('button', { name: 'Token diff' }).click();
  await expect(reviewToolbar.getByRole('button', { name: 'Token diff' })).toHaveAttribute(
    'aria-pressed',
    'true',
  );
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

  const layout = page.getByRole('group', { name: 'Diff layout' });
  await layout.getByRole('button', { name: 'Unified diff layout' }).click();
  await expect(layout.getByRole('button', { name: 'Unified diff layout' })).toHaveAttribute(
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
        + '.view-lines[data-view-part="view-lines"] > .view-line',
      { hasText: 'working tree' },
    ),
  }).first();
  await expect(semanticDiffCandidate).toBeVisible();
  const semanticDiffId = await semanticDiffCandidate.getAttribute('id');
  expect(semanticDiffId).not.toBeNull();
  const semanticDiff = semantic.locator(`[id=${JSON.stringify(semanticDiffId)}]`);
  const semanticOriginal = semanticDiff.locator('.moonbit-diff-editor-original');
  const semanticModified = semanticDiff.locator('.moonbit-diff-editor-modified');
  await expect(semanticDiff).toBeVisible();
  await expect(semanticDiff.locator('.moonbit-diff-editor').first())
    .toHaveAttribute('data-render-mode', 'inline');
  await expect(semanticOriginal.locator('.line-numbers:visible').first())
    .toBeVisible();
  await expect.poll(() => semanticOriginal.evaluate((node) => {
    const host = node.getBoundingClientRect();
    const margin = node.querySelector('.margin');
    const lineNumber = Array.from(node.querySelectorAll('.line-numbers'))
      .map((element) => element.getBoundingClientRect())
      .find((rect) => rect.width > 0);
    if (!margin || !lineNumber) return null;
    const marginRect = margin.getBoundingClientRect();
    return {
      lineNumberAligned:
        Math.abs(host.width - (lineNumber.right - host.left)) <= 0.5,
      decorationsClipped: host.width < marginRect.width,
    };
  })).toEqual({ lineNumberAligned: true, decorationsClipped: true });

  const feedbackLine = semanticModified.locator(
    '.view-lines[data-view-part="view-lines"] > .view-line',
  ).filter({ hasText: 'working tree' }).first();
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

  await reviewToolbar.getByRole('button', { name: 'Line diff' }).click();
  await expect(reviewToolbar.getByRole('button', { name: 'Line diff' })).toHaveAttribute(
    'aria-pressed',
    'true',
  );
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
  await expect(page.getByRole('button', { name: 'Ignore comments' })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Ignore tests' })).toHaveCount(0);

  await toolbar.getByRole('button', { name: 'File view' }).click();
  await expect(
    page.getByLabel('Readonly Markdown viewer')
      .getByText('Working tree documentation.', { exact: true }),
  ).toBeVisible();

  await toolbar.getByRole('button', { name: 'Line diff' }).click();
  await expect(toolbar.getByRole('button', { name: 'Line diff' })).toHaveAttribute(
    'aria-pressed',
    'true',
  );
  expect(app.pageErrors).toEqual([]);
});

test('ordinary MBTI files render as UML and reviews keep source surfaces', async ({ page }) => {
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
  await page.getByRole('option', { name: /pkg\.generated\.mbti/ }).click();

  const diagram = page.locator('#mbti-diagram-host');
  await expect(diagram).toBeVisible();
  await expect(diagram.locator('svg')).toBeVisible();
  await expect(diagram.locator('svg')).toContainText('Point');
  const view = page.getByRole('group', { name: 'MBTI view' });
  await expect(view.getByRole('button')).toHaveText(['Diagram', 'Source']);
  await expect(view.getByRole('button', { name: 'Diagram' })).toHaveAttribute(
    'aria-pressed',
    'true',
  );

  await view.getByRole('button', { name: 'Source' }).click();
  await expect(diagram).toBeHidden();
  await expect(page.locator('#viewer-host')).toBeVisible();
  await expect(page.locator('#viewer-host')).toContainText('Point');
  await expect(view.getByRole('button', { name: 'Source' })).toHaveAttribute(
    'aria-pressed',
    'true',
  );
  await view.getByRole('button', { name: 'Diagram' }).click();
  await expect(diagram.locator('svg')).toBeVisible();

  await app.openReview();
  await page.getByRole('button', { name: /View diff: api\/pkg\.generated\.mbti/ }).click();
  await expect(page.getByRole('group', { name: 'MBTI view' })).toHaveCount(0);
  await expect(diagram).toBeHidden();
  const review = page.getByRole('toolbar', { name: 'Review mode' });
  await expect(review.getByRole('button', { name: 'Line diff' })).toHaveAttribute(
    'aria-pressed',
    'true',
  );
  await review.getByRole('button', { name: 'File view' }).click();
  await expect(page.locator('#viewer-host')).toBeVisible();
  await expect(page.locator('#viewer-host')).toContainText('Point');
  await expect(diagram).toBeHidden();
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
  const history = page.getByRole('tree', { name: 'Git commit history' });
  const head = history.getByRole('treeitem', { name: /Cover Desktop Git flows/ });
  const merge = history.getByRole('treeitem', { name: /Merge fixture lanes/ });
  const parent = history.getByRole('treeitem', { name: /Add Review surface/ });
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
  await historicalMain.click();
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

test('project picker adds the browsed folder with Enter', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();

  await page.getByRole('button', { name: 'Add a project' }).click();
  const picker = page.getByRole('dialog', { name: 'Add a project' });
  await expect(picker).toBeVisible();
  await expect(
    picker.getByRole('button', { name: 'Add project', exact: true }),
  ).toBeEnabled();
  await page.keyboard.press('Enter');

  await expect.poll(() => app.requests.find(request =>
    request.method === 'workspace.add')).toMatchObject({
    params: { path: '/Users/test' },
  });
  await expect(picker).toBeHidden();
  app.notify('workspace.changed', { workspaces: app.workspaces });
  await expect(page.getByRole('button', { name: 'test', exact: true })).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('quick open moves its keyboard selection and opens the chosen file', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openQuickOpen();
  const input = page.getByRole('combobox', { name: 'Search workspace files' });
  await expect(input).toBeFocused();
  const mainResult = page.getByRole('option', { name: /main\.mbt/ });
  const readmeResult = page.getByRole('option', { name: /README\.md/ });
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
  await page.getByRole('option', { name: /main\.mbt/ }).click();
  await app.openQuickOpen();
  await page.locator('#quick-open-input').fill('README');
  await page.getByRole('option', { name: /README\.md/ }).click();

  const fileTabs = page.locator('.editor-tab');
  await expect(fileTabs).toHaveCount(2);
  await fileTabs.filter({ hasText: 'main.mbt' }).click();
  await expect(fileTabs.filter({ hasText: 'main.mbt' })).toHaveClass(/active/);
  await app.openReview();
  await expect(fileTabs).toHaveCount(3);
  const closeAll = page.getByRole('button', { name: 'Close all tabs' });
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
  await page.getByRole('option', { name: /main\.mbt/ }).click();

  const breadcrumb = page.locator('.viewer-breadcrumb');
  const sourceDirectory = breadcrumb.getByTitle('Show files in src');
  await sourceDirectory.click();
  await expect.poll(() => app.requests.find(request =>
    request.method === 'fs.read_directory' && request.params?.path === '/workspace/src'))
    .toBeTruthy();
  const menu = page.getByRole('menu', { name: 'Files in src' });
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

  const overview = page.getByRole('navigation', { name: 'Conversation overview' });
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
  const tabs = transcript.locator('.tool-call-tabs');
  const originalJson = tabs.getByText('Original JSON', { exact: true });
  await transcript.locator('.tool-call-summary').click();
  await transcript.evaluate(node => {
    node.scrollTop = node.scrollHeight;
  });
  await expect(originalJson).toBeVisible();
  expect(await transcript.evaluate(node => node.scrollTop)).toBeGreaterThan(0);
  expect(await page.evaluate(() => document.scrollingElement.scrollTop)).toBe(0);

  await originalJson.click();

  const originalJsonInput = tabs.locator('.tool-call-tab-input').nth(1);
  await expect(originalJsonInput).toBeChecked();
  await originalJsonInput.focus();
  await expect(originalJsonInput).toBeFocused();
  expect(await transcript.evaluate(node => getComputedStyle(node).position))
    .toBe('relative');
  expect(await originalJsonInput.evaluate(node =>
    Boolean(node.offsetParent?.closest('#transcript')))).toBe(true);
  expect(await page.evaluate(() => document.scrollingElement.scrollTop)).toBe(0);
  expect(await page.locator('.app').evaluate(node =>
    node.getBoundingClientRect().top)).toBe(0);
  expect(app.pageErrors).toEqual([]);
});

test('runtime notices keep the compact result-row presentation', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.sessionEvents = [
    {
      sequence: 1,
      item: {
        kind: 'user',
        payload: { content: 'Show the browser fixture runtime notice' },
      },
    },
    {
      sequence: 2,
      item: {
        kind: 'runtime_notice',
        payload: {
          content: 'background job bg-1 finished (exit=0): `moon test`',
        },
      },
    },
  ];
  await app.install();
  await app.goto();
  await app.openSession();

  const notice = page.locator('.activity-row', { hasText: 'runtime notice' });
  const result = notice.locator('details.tool-result');
  await expect(notice.locator('.summary-card')).toHaveCount(0);
  await expect(result.locator('.tool-result-text')).toHaveText('runtime notice');
  await expect(result).not.toHaveAttribute('open', '');
  await result.locator('.tool-result-summary').click();
  await expect(result).toContainText('background job bg-1 finished (exit=0)');
  expect(app.pageErrors).toEqual([]);
});

test('a model step shows its thought, then its prose, then its tool rows', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.sessionEvents = [
    {
      sequence: 1,
      item: {
        kind: 'user',
        payload: { content: 'Show the browser fixture model step' },
      },
    },
    {
      sequence: 2,
      item: {
        kind: 'assistant',
        payload: {
          content: 'I will inspect the project.',
          reasoning_content: 'first thought',
          tool_calls: [{ id: 'c1', name: 'read', arguments: '{"path":"moon.mod"}' }],
        },
      },
    },
    {
      sequence: 3,
      item: {
        kind: 'tool_result',
        payload: {
          tool_call_id: 'c1',
          tool_name: 'read',
          content: 'module contents',
          is_error: false,
          brief: 'read moon.mod',
        },
      },
    },
  ];
  await app.install();
  await app.goto();
  await app.openSession();

  // One durable response is one step, whose parts keep the model's order:
  // the thought it had, the prose it said, then the calls that prose announced.
  const step = page.locator('.step');
  await expect(step).toHaveCount(1);
  await expect(step.locator(':scope > *')).toHaveClass(['activity-row', 'msg', 'activity-row']);
  await expect(step.locator('.activity-row').first().locator('.activity-text')).toHaveText('#1 · Thought');
  await expect(step.locator('.msg .msg-content.markdown')).toContainText('I will inspect the project.');
  await expect(step.locator('.activity-row').last().locator('.tool-call-text')).toHaveText('read moon.mod');
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
          ].join('\n\n'),
        },
      },
    },
  ];
  await app.install();
  await app.goto();
  await app.openSession();

  const markdown = page.locator('.transcript .msg-content.markdown');
  await expect(markdown.locator('a[href^="javascript:"]')).toHaveCount(0);
  await expect(markdown.getByText('Unsafe', { exact: true })).toBeVisible();

  const image = markdown.locator('img[alt="Fixture image"]');
  await expect.poll(() => app.requests.find(request =>
    request.method === 'fs.read_file' && request.params?.path === 'diagram.png'))
    .toMatchObject({ params: { root: '/workspace' } });
  await expect(image).toHaveAttribute('src', 'data:image/png;base64,iVBORw0KGgo=');

  const external = markdown.getByRole('link', { name: 'External docs' });
  await expect(external).toHaveAttribute('target', '_blank');
  await expect(external).toHaveAttribute('rel', 'noopener noreferrer');
  await external.focus();
  await external.evaluate(element => {
    element.dispatchEvent(new MouseEvent('contextmenu', {
      bubbles: true,
      cancelable: true,
      clientX: 0,
      clientY: 0,
    }));
  });
  let contextMenu = page.getByRole('menu', { name: 'Context menu' });
  await expect(contextMenu).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(external).toBeFocused();

  await external.click({ button: 'right' });
  contextMenu = page.getByRole('menu', { name: 'Context menu' });
  await expect(contextMenu.getByRole('menuitem')).toHaveText([
    'Open in New Tab',
    'Copy Link',
  ]);
  const popupPromise = page.waitForEvent('popup');
  const navigationPromise = page.context().waitForEvent('request', {
    predicate: request => request.url() === 'https://example.test/docs',
  });
  await contextMenu.getByRole('menuitem', { name: 'Open in New Tab' }).click();
  const popup = await popupPromise;
  await navigationPromise;
  await popup.close();

  const source = markdown.getByTitle('Open src/main.mbt:12');
  await source.click({ button: 'right' });
  contextMenu = page.getByRole('menu', { name: 'Context menu' });
  await expect(contextMenu.getByRole('menuitem')).toHaveText([
    'Open',
    'Copy Path',
  ]);
  await page.keyboard.press('Escape');

  const unsafe = markdown.getByText('Unsafe', { exact: true });
  await unsafe.evaluate(element => {
    const range = document.createRange();
    range.selectNodeContents(element);
    const selection = document.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
    const rect = range.getBoundingClientRect();
    element.dispatchEvent(new MouseEvent('contextmenu', {
      bubbles: true,
      cancelable: true,
      clientX: rect.left + Math.max(1, rect.width / 2),
      clientY: rect.top + Math.max(1, rect.height / 2),
    }));
  });
  contextMenu = page.getByRole('menu', { name: 'Context menu' });
  await expect(contextMenu.getByRole('menuitem')).toHaveText(['Copy']);
  await page.keyboard.press('Escape');

  const ordinaryEventAllowed = await page.getByRole('main').evaluate(element => {
    document.getSelection()?.removeAllRanges();
    return element.dispatchEvent(new MouseEvent('contextmenu', {
      bubbles: true,
      cancelable: true,
      clientX: 4,
      clientY: 4,
    }));
  });
  expect(ordinaryEventAllowed).toBe(false);
  await expect(page.getByRole('menu', { name: 'Context menu' })).toHaveCount(0);

  await source.click();
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
  await approval.getByRole('button', { name: 'Allow once' }).click();
  await expect.poll(() => app.requests.some(request =>
    request.method === 'agent.approval' &&
    request.params?.id === 'approval-1' &&
    request.params?.allow === true)).toBe(true);
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

  await composer.fill('Steer without losing the interrupt control');
  await expect(page.getByTitle('Stop', { exact: true })).toBeVisible();
  await expect(page.getByTitle('Steer the running task', { exact: true })).toBeVisible();
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
  await archivedRow.hover();
  await archivedRow.getByTitle('Restore this conversation to the sidebar').click();
  await expect.poll(() => app.requests.some(request =>
    request.method === 'session.unarchive' &&
    request.params?.session === 'session-1')).toBe(true);
  await expect(page.getByText('Rabbita browser fixture', { exact: true }).first()).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('archiving a selected chat reuses an existing New chat draft', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();

  await page.locator('.workspace-row', { hasText: 'workspace' }).hover();
  await page.getByTitle('New conversation in this project').click();
  const newChat = page.locator('.conversation-row', { hasText: 'New chat' });
  await expect(newChat).toHaveCount(1);
  await page.locator('#task').fill('Keep this draft');

  const stored = page.locator('.conversation-row[title="session-1"]');
  await stored.click();
  await expect(page.getByText('Browser result', { exact: true })).toBeVisible();
  await page.locator('#task').fill('Discard this archived draft');
  await stored.click({ button: 'right', position: { x: 18, y: 18 } });
  await page.getByRole('menuitem', { name: 'Archive' }).click();

  await expect.poll(() => app.requests.some(request =>
    request.method === 'session.archive' &&
    request.params?.session === 'session-1')).toBe(true);
  await expect(newChat).toHaveCount(1);
  await expect(newChat).toHaveClass(/active/);
  await expect(page.locator('#task')).toHaveValue('Keep this draft');
  expect(app.pageErrors).toEqual([]);
});

test('shared WebView action menu supports context position, keyboard, and rename', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.workspaces.push('/other');
  await app.install();
  await app.goto();

  const firstWorkspace = page.locator('.workspace-row[title="/workspace"]');
  const secondWorkspace = page.locator('.workspace-row[title="/other"]');
  const firstWorkspaceMenu = firstWorkspace.getByTitle('More actions');
  const secondWorkspaceMenu = secondWorkspace.getByTitle('More actions');
  await firstWorkspace.hover();
  await firstWorkspaceMenu.click();
  await expect(firstWorkspaceMenu).toHaveAttribute('aria-expanded', 'true');
  let menu = page.getByRole('menu', { name: 'Workspace actions' });
  await expect(menu).toBeFocused();
  await expect(menu.getByRole('menuitem').first()).not.toBeFocused();
  await secondWorkspace.hover();
  await secondWorkspaceMenu.click();
  await expect(firstWorkspaceMenu).toHaveAttribute('aria-expanded', 'false');
  await expect(secondWorkspaceMenu).toHaveAttribute('aria-expanded', 'true');
  menu = page.getByRole('menu', { name: 'Workspace actions' });
  await expect(menu).toBeFocused();
  await secondWorkspaceMenu.click();
  await expect(page.getByRole('menu')).toHaveCount(0);

  await secondWorkspaceMenu.focus();
  await page.keyboard.press('Enter');
  menu = page.getByRole('menu', { name: 'Workspace actions' });
  await expect(menu).toBeFocused();
  await expect(menu.getByRole('menuitem').first()).not.toBeFocused();
  await page.keyboard.press('ArrowDown');
  await expect(menu.getByRole('menuitem').first()).toBeFocused();
  await page.keyboard.press('Escape');
  await expect(menu).toHaveCount(0);
  await expect(secondWorkspaceMenu).toBeFocused();

  const liveRow = page.locator('.conversation-row[title="session-1"]');
  const archiveButton = liveRow.getByTitle(/Archive —/);
  await liveRow.hover();
  await archiveButton.focus();
  await liveRow.click({ button: 'right', position: { x: 18, y: 18 } });
  menu = page.getByRole('menu', { name: 'Conversation actions' });
  await expect(menu).toBeVisible();
  const rename = menu.getByRole('menuitem', { name: 'Rename…' });
  const archive = menu.getByRole('menuitem', { name: 'Archive' });
  await expect(menu).toBeFocused();
  await expect(rename).not.toBeFocused();
  await expect(rename).toHaveCSS('background-color', 'rgba(0, 0, 0, 0)');

  await page.keyboard.press('ArrowDown');
  await expect(rename).toBeFocused();

  const bounds = await menu.boundingBox();
  const viewport = page.viewportSize();
  expect(bounds).not.toBeNull();
  expect(bounds.x).toBeGreaterThanOrEqual(0);
  expect(bounds.y).toBeGreaterThanOrEqual(0);
  expect(bounds.x + bounds.width).toBeLessThanOrEqual(viewport.width);
  expect(bounds.y + bounds.height).toBeLessThanOrEqual(viewport.height);

  await page.keyboard.press('ArrowDown');
  await expect(archive).toBeFocused();
  await page.keyboard.press('Home');
  await expect(rename).toBeFocused();
  await page.keyboard.press('Escape');
  await expect(menu).toHaveCount(0);
  await expect(archiveButton).toBeFocused();
  await expect(liveRow.getByRole('button', { name: 'Conversation actions' })).toHaveCount(0);

  await liveRow.click({ button: 'right', position: { x: 18, y: 18 } });
  await page.getByRole('menuitem', { name: 'Rename…' }).click({ button: 'right' });
  const input = page.getByRole('textbox', { name: 'Rename conversation' });
  await expect(input).toBeFocused();
  await expect.poll(() => input.evaluate(element => ({
    start: element.selectionStart,
    end: element.selectionEnd,
    length: element.value.length,
  }))).toEqual({ start: 0, end: 23, length: 23 });
  await input.fill('Renamed in WebView');
  await input.click({ button: 'right' });
  await expect(menu).toHaveCount(0);
  await page.getByRole('button', { name: 'Save' }).click();
  await expect.poll(() => app.requests.find(request =>
    request.method === 'session.rename')).toMatchObject({
      params: {
        session: 'session-1',
        workspace: '/workspace',
        title: 'Renamed in WebView',
      },
    });

  app.rpcErrors.set('session.rename', 'fixture rename unavailable');
  await liveRow.click({ button: 'right', position: { x: 18, y: 18 } });
  await page.getByRole('menuitem', { name: 'Rename…' }).click();
  await input.fill('Rename that will fail');
  await page.getByRole('button', { name: 'Save' }).click();
  await expect(page.getByRole('alert')).toContainText(
    'Rename failed: fixture rename unavailable',
  );
  await expect(input).toHaveValue('Rename that will fail');
  await expect(input).toBeEnabled();
  expect(app.pageErrors).toEqual([]);
});

test('sidebar menu dismissal and pending selection follow the clicked row', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.liveSessions.push({
    id: 'session-2',
    title: 'Second browser fixture',
    updated_at_ms: 2,
  });
  await app.install();
  await app.goto();

  const workspace = page.locator('.workspace-row', { hasText: 'workspace' });
  await workspace.click({ button: 'right', position: { x: 24, y: 16 } });
  await expect(page.getByRole('menu', { name: 'Workspace actions' })).toBeVisible();

  const first = page.locator('.conversation-row[title="session-1"]');
  // Click the title, not a fixed offset: the row's right end is the
  // hover-revealed archive button, and the row's width is platform-dependent.
  await first.locator('.sidebar-label').click();
  await expect(page.getByRole('menu')).toHaveCount(0);
  await expect(first).toHaveClass(/active/);
  await expect(page.getByText('Browser result', { exact: true })).toBeVisible();

  app.rpcDelays.set('session.load', 10000);
  await first.click({ button: 'right', position: { x: 18, y: 18 } });
  await expect(page.getByRole('menu', { name: 'Conversation actions' })).toBeVisible();
  const second = page.locator('.conversation-row[title="session-2"]');
  await second.click();
  await expect(page.getByRole('menu')).toHaveCount(0);
  await expect(second).toHaveClass(/active/);
  await expect(first).not.toHaveClass(/active/);
  await expect(second.getByRole('status', { name: 'Loading conversation' })).toBeVisible();
  await expect(page.getByText('Loading conversation…', { exact: true })).toBeVisible();
  const rowSpinner = second.locator('.conversation-load-spinner');
  const panelSpinner = page.locator('.conversation-load-state-spinner');
  await expect(rowSpinner).toHaveCSS('animation-name', 'conversation-load-spin');
  await expect(panelSpinner).toHaveCount(0);
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await expect(rowSpinner).toHaveCSS('animation-name', 'none');
  await expect(page.getByText('Browser result', { exact: true })).toHaveCount(0);
  await expect.poll(() => app.requests.some(request =>
    request.method === 'session.load' && request.params?.session === 'session-2'))
    .toBe(true);
  expect(app.pageErrors).toEqual([]);
});

test('removing a pending selection exits its loading state', async ({ page }) => {
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
  await expect(page.getByText('Loading conversation…', { exact: true })).toBeVisible();
  await pending.click({ button: 'right', position: { x: 18, y: 18 } });
  await expect(page.getByRole('menu', { name: 'Conversation actions' })).toBeVisible();

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

  await expect(page.getByRole('menu')).toHaveCount(0);
  await expect(page.getByText('Loading conversation…', { exact: true })).toHaveCount(0);
  await expect(page.locator('#task')).toBeVisible();
  await expect(page.locator('.conversation-row', { hasText: 'New chat' })).toBeVisible();
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
  await expect(page.getByText('Could not load conversation', { exact: true })).toBeVisible();
  await expect(page.getByText(/fixture unavailable/).last()).toBeVisible();
  await expect(row).toHaveClass(/load-failed/);

  app.rpcErrors.delete('session.load');
  await page.getByRole('button', { name: 'Retry' }).click();
  await expect(page.getByText('Browser result', { exact: true })).toBeVisible();
  await expect(row).toHaveClass(/active/);
  await expect(row).not.toHaveClass(/load-failed/);
  expect(app.pageErrors).toEqual([]);
});

test('settings change and preserve the visible font size', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();

  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  const fontSize = page.getByRole('button', { name: 'Font size' });
  await fontSize.click();
  await page.getByRole('option', { name: '12px' }).click();
  await expect.poll(() => page.evaluate(() =>
    getComputedStyle(document.body).fontSize))
    .toBe('12px');

  await fontSize.click();
  await page.getByRole('option', { name: '18px' }).click();
  await expect.poll(() => page.evaluate(() =>
    getComputedStyle(document.body).fontSize))
    .toBe('18px');
  await page.reload();
  await page.getByRole('main').waitFor();
  await expect.poll(() => page.evaluate(() =>
    getComputedStyle(document.body).fontSize))
    .toBe('18px');
  expect(app.pageErrors).toEqual([]);
});

test('a covering modal dismisses an open custom select', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();

  const model = page.getByRole('button', { name: 'Model', exact: true });
  await model.click();
  await expect(page.getByRole('listbox', { name: 'Model' })).toBeVisible();
  app.notify('settings.changed', {
    ...app.hostSettings,
    revision: app.hostSettings.revision + 1,
    has_deepseek_key: false,
  });
  await expect(page.getByText('Set up your DeepSeek API key')).toBeVisible();
  await expect(page.getByRole('listbox', { name: 'Model' })).toHaveCount(0);
  await expect(model).toHaveAttribute('aria-expanded', 'false');
  expect(app.pageErrors).toEqual([]);
});

test('a bottom select flips above and yields to the narrow sidebar', async ({ page }) => {
  await page.setViewportSize({ width: 500, height: 320 });
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();

  const trigger = page.getByRole('button', { name: 'Model', exact: true });
  await trigger.click();
  const menu = page.getByRole('listbox', { name: 'Model' });
  await expect(menu).toBeVisible();
  const geometry = await page.evaluate(() => {
    const triggerRect = document.querySelector('#openseek-model-picker').getBoundingClientRect();
    const menu = document.querySelector('#openseek-model-picker-menu');
    const menuRect = menu.getBoundingClientRect();
    return {
      above: menuRect.bottom <= triggerRect.top,
      insideViewport: menuRect.top >= 0 && menuRect.bottom <= innerHeight,
      fullyExpanded: menu.clientHeight === menu.scrollHeight,
    };
  });
  expect(geometry).toEqual({
    above: true,
    insideViewport: true,
    fullyExpanded: true,
  });

  const shortcut = await page.evaluate(() =>
    navigator.platform.includes('Mac') ? 'Meta+B' : 'Control+B');
  await page.keyboard.press(shortcut);
  await expect(page.getByRole('button', { name: 'Hide sidebar' })).toBeVisible();
  await expect(menu).toHaveCount(0);
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
  await expect(moonbit.getByRole('button', { name: 'Uninstall' })).toHaveCount(0);

  const rabbita = registry.locator('.skill-row').filter({ hasText: 'rabbita' });
  await rabbita.locator('.skill-summary').click();
  await expect(page.getByRole('button', { name: '← Back to skills' })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'rabbita', exact: true })).toBeVisible();
  await page.getByRole('button', { name: '← Back to skills' }).click();

  await installed.locator('.skill-row').filter({ hasText: 'MoonBit' })
    .locator('.skill-summary').click();
  await expect(page.getByRole('button', { name: 'Uninstall' })).toHaveCount(0);
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

test('workspace settings open and persist per-workspace choices', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();

  // The project row's "…" menu is the way into a workspace's settings page.
  await page.locator('.workspace-row', { hasText: 'workspace' }).hover();
  await page.getByTitle('More actions').click();
  await page.getByRole('menuitem', { name: 'Workspace settings' }).click();
  await expect(page.getByRole('heading', { name: 'workspace' })).toBeVisible();
  await expect(page.locator('.settings-subtitle')).toHaveText('/workspace');

  // The page reads the host's authoritative snapshot before enabling the
  // selects.
  await expect.poll(() => app.requests.find(request =>
    request.method === 'workspace.settings_get')).toMatchObject({
    params: { workspace: '/workspace' },
  });

  const launchMode = page.getByRole('button', { name: 'New chats' });
  await expect(launchMode).toBeEnabled();
  await launchMode.click();
  await page.getByRole('option', { name: 'Worktree' }).click();
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
  await expect(launchMode).toHaveText('Worktree');

  const submodules = page.getByRole('button', { name: 'Submodules in worktrees' });
  await submodules.click();
  await page.getByRole('option', { name: 'Initialize', exact: true }).click();
  await expect.poll(() => app.requests.find(request =>
    request.method === 'workspace.settings_set' &&
    request.params?.checkout_submodules === true)).toBeTruthy();
  await expect.poll(() => app.workspaceSettingsFor('/workspace').checkout_submodules).toBe(true);
  app.notify(
    'workspace.settings_changed',
    { ...app.workspaceSettingsFor('/workspace') },
  );

  const timeout = page.getByRole('button', { name: 'Submodule checkout timeout' });
  await timeout.click();
  await page.getByRole('option', { name: '60 seconds' }).click();
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

  // Leave and re-enter: the page keeps the committed values.
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Settings' })).toBeVisible();
  await page.locator('.workspace-row', { hasText: 'workspace' }).hover();
  await page.getByTitle('More actions').click();
  await page.getByRole('menuitem', { name: 'Workspace settings' }).click();
  await expect(page.getByRole('button', { name: 'New chats' })).toHaveText('Worktree');
  await expect(page.getByRole('button', { name: 'Submodules in worktrees' })).toHaveText('Initialize');
  await expect(page.getByRole('button', { name: 'Submodule checkout timeout' })).toHaveText('60 seconds');
  // Settings are stored per workspace: a sibling project keeps its own
  // defaults, never inheriting this workspace's committed values.
  expect(app.workspaceSettingsFor('/other')).toEqual({
    workspace: '/other',
    worktree_mode: false,
    checkout_submodules: false,
    submodule_checkout_timeout_seconds: 30,
  });

  // A detach takes the page away with no click anywhere, so nothing
  // click-away dismisses the open menu. Removing its trigger blurs it
  // instead, and the shared select dismisses on blur, so the round trip
  // leaves nothing open: re-entering renders closed, and the first click on
  // the trigger opens the menu rather than closing one nobody can see.
  const reentered = page.getByRole('button', { name: 'New chats' });
  await reentered.click();
  await expect(reentered).toHaveAttribute('aria-expanded', 'true');
  app.notify('workspace.changed', { workspaces: [] });
  await expect(page.getByRole('button', { name: 'New chats' })).toHaveCount(0);
  app.notify('workspace.changed', { workspaces: ['/workspace'] });
  await page.locator('.workspace-row', { hasText: 'workspace' }).hover();
  await page.getByTitle('More actions').click();
  await page.getByRole('menuitem', { name: 'Workspace settings' }).click();
  const reopened = page.getByRole('button', { name: 'New chats' });
  await expect(reopened).toHaveAttribute('aria-expanded', 'false');
  await reopened.click();
  await expect(reopened).toHaveAttribute('aria-expanded', 'true');

  expect(app.pageErrors).toEqual([]);
});

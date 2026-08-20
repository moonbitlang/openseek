import { expect, test } from '../support/test.js';
import { workspaceItem as workspaceSelector } from '../support/app.js';

const sourceEditor =
  '.viewer-host:not(.diff-viewer-host) > .monaco-editor.readonly-editor';

// Proves the library boundary: the embedded page runs the viewer and the
// file-tree widget against in-memory providers, with no websocket opened.
test('runs the viewer and tree from in-memory providers without a server', async ({ page }) => {
  const websockets = [];
  page.on('websocket', (ws) => websockets.push(ws.url()));

  await page.goto('/embed.html');

  // The embedding host auto-opens src/main.mbt; auto-reveal expands src.
  await expect(page.locator('.editor-shell')).toHaveAttribute('data-status', 'ready');
  await expect(page.locator(sourceEditor)).toContainText('fn main');
  await expect
    .poll(async () => (await page.locator('.embedded-viewer-stack').boundingBox())?.width ?? 0)
    .toBeGreaterThan(400);

  // Real language highlighting with no server: the MoonBit lexer is
  // registered by the embedding host, not fetched from anywhere.
  await expect(page.locator('.mtk3', { hasText: 'fn' }).first()).toBeVisible();
  await expect(page.locator(workspaceItem('src'))).toHaveAttribute('aria-expanded', 'true');
  await expect(page.locator(workspaceItem('src/main.mbt'))).toHaveAttribute(
    'aria-selected',
    'true',
  );

  // The same public facade exposes the side-by-side DiffViewer. The host
  // toggles sibling surfaces, preserving the ordinary source Viewer's model
  // and scroll while the comparison owns two ordinary Viewer panes.
  const diffToggle = page.locator('[data-action=\"toggle-diff\"]');
  const layoutToggle = page.locator('[data-action="toggle-diff-layout"]');
  await expect(layoutToggle).toBeDisabled();
  await expect(layoutToggle).toHaveAccessibleName('Unified diff layout');
  await expect(diffToggle).toHaveAccessibleName('Full diff');
  await diffToggle.click();
  await expect(diffToggle).toHaveAttribute('aria-pressed', 'true');
  await expect(diffToggle).toHaveAccessibleName('Full diff');
  const diff = page.locator('.diff-viewer-host > .moonbit-diff-editor');
  await expect(diff).toBeVisible();
  await expect
    .poll(async () => (await diff.boundingBox())?.width ?? 0)
    .toBeGreaterThan(400);
  const originalPane = diff.locator('.moonbit-diff-editor-original');
  const modifiedPane = diff.locator('.moonbit-diff-editor-modified');
  await expect(originalPane.locator('.monaco-editor')).toContainText(
    'println(\"hello\")',
  );
  await expect(modifiedPane.locator('.monaco-editor')).toContainText(
    'println(greeting())',
  );
  await expect(originalPane.locator('.diff-editor-line-delete')).toHaveCount(1);
  await expect(modifiedPane.locator('.diff-editor-line-insert')).toHaveCount(1);

  // Render-mode switching keeps the same model pair. Unified mode hides only
  // the original child presentation and interleaves its deleted line as a
  // tokenized ViewZone in the still-interactive modified Viewer.
  await expect(layoutToggle).toBeEnabled();
  await expect(layoutToggle).toHaveAttribute('aria-pressed', 'false');
  await layoutToggle.click();
  await expect(layoutToggle).toHaveAttribute('aria-pressed', 'true');
  await expect(diff).toHaveAttribute('data-render-mode', 'unified');
  await expect(originalPane).toBeHidden();
  await expect(modifiedPane).toBeVisible();
  const deletedBlock = modifiedPane.locator(
    '.diff-editor-unified-deleted-block',
  );
  await expect(deletedBlock).toContainText('println("hello")');
  await expect(
    modifiedPane.locator('.diff-editor-unified-deleted-line-number'),
  ).toContainText('3');
  await expect(modifiedPane.locator('.diff-editor-line-insert')).toHaveCount(1);
  await layoutToggle.click();
  await expect(layoutToggle).toHaveAttribute('aria-pressed', 'false');
  await expect(diff).toHaveAttribute('data-render-mode', 'side-by-side');
  await expect(originalPane).toBeVisible();

  // Desktop can place the changed-file tree beside this surface. Both panes
  // must remain within a substantially narrower caller-owned host.
  const viewerStack = page.locator('.embedded-viewer-stack');
  await viewerStack.evaluate((element) => {
    element.style.width = '300px';
    element.style.flex = '0 0 300px';
  });
  const [narrowDiffBox, originalPaneBox, modifiedPaneBox] = await Promise.all([
    diff.boundingBox(),
    originalPane.boundingBox(),
    modifiedPane.boundingBox(),
  ]);
  expect(narrowDiffBox).not.toBeNull();
  expect(originalPaneBox).not.toBeNull();
  expect(modifiedPaneBox).not.toBeNull();
  expect(originalPaneBox.x).toBeGreaterThanOrEqual(narrowDiffBox.x);
  expect(modifiedPaneBox.x + modifiedPaneBox.width).toBeLessThanOrEqual(
    narrowDiffBox.x + narrowDiffBox.width + 1,
  );
  await expect(
    originalPane.locator('.view-line').filter({ hasText: 'println("hello")' }),
  ).toBeVisible();
  await expect(
    modifiedPane.locator('.view-line').filter({ hasText: 'println(greeting())' }),
  ).toBeVisible();
  await viewerStack.evaluate((element) => {
    element.style.width = '';
    element.style.flex = '';
  });
  const viewportFit = await page.evaluate(() => ({
    innerWidth: window.innerWidth,
    innerHeight: window.innerHeight,
    scrollWidth: document.documentElement.scrollWidth,
    scrollHeight: document.documentElement.scrollHeight,
  }));
  expect(viewportFit.scrollWidth).toBeLessThanOrEqual(viewportFit.innerWidth);
  expect(viewportFit.scrollHeight).toBeLessThanOrEqual(viewportFit.innerHeight);
  await expect(page.locator(sourceEditor)).not.toBeVisible();

  await diffToggle.click();
  await expect(diffToggle).toHaveAttribute('aria-pressed', 'false');
  await expect(diffToggle).toHaveAccessibleName('Full diff');
  await expect(diff).not.toBeVisible();
  await expect(page.locator(sourceEditor)).toContainText('fn main');

  // Nested folders resolve lazily on expand.
  await expect(page.locator(workspaceItem('src/lib/util.mbt'))).toHaveCount(0);
  await page.locator(workspaceItem('src/lib')).click();
  await expect(page.locator(workspaceItem('src/lib'))).toHaveAttribute('aria-expanded', 'true');

  // Navigating between files goes through the in-memory document source.
  await page.locator(workspaceItem('src/lib/util.mbt')).click();
  await expect(page.locator(sourceEditor)).toContainText('util_answer');
  await expect(page.locator(workspaceItem('src/lib/util.mbt'))).toHaveAttribute(
    'aria-selected',
    'true',
  );

  // The same public Viewer instance selects its Markdown presentation from an
  // ordinary URI-backed in-memory model. No workbench or host-side Markdown
  // parsing/presentation branch participates.
  await page.locator(workspaceItem('README.md')).click();
  await expect(page.locator('.editor-shell')).toHaveAttribute('data-status', 'ready');
  await expect(page.locator(workspaceItem('README.md'))).toHaveAttribute(
    'aria-selected',
    'true',
  );
  const markdown = page.locator(
    '.viewer-host > .moonbit-viewer-markdown-document',
  );
  await expect(markdown).toBeVisible();
  await expect(markdown).toHaveAttribute(
    'data-source-uri',
    'memory://workspace/README.md',
  );
  await expect(markdown.locator('h1')).toHaveText('Embedded Markdown document');
  await expect(markdown.locator('strong')).toHaveText('Viewer');
  await expect(page.locator('.viewer-host > .monaco-editor')).toHaveCount(0);

  expect(websockets).toEqual([]);
});

test('virtualizes a legal-size large diff through ordinary Viewer panes', async ({ page }) => {
  await page.goto('/embed.html');
  await expect(page.locator('.editor-shell')).toHaveAttribute('data-status', 'ready');

  // Both sides contain thousands of changed lines. The two Viewer panes keep
  // only a viewport-sized set of line DOM instead of eager diff rows.
  await page.locator(workspaceItem('large.mbt')).click();
  await expect(page.locator('.editor-shell')).toHaveAttribute('data-status', 'ready');
  await page.locator('[data-action="toggle-diff"]').click();
  const diff = page.locator('.diff-viewer-host > .moonbit-diff-editor');
  await expect(diff).toBeVisible();
  await expect(
    diff.locator('.moonbit-diff-editor-pane > .monaco-editor'),
  ).toHaveCount(2);
  await expect(diff.locator('.view-line').first()).toBeVisible();
  expect(await diff.locator('.view-line').count()).toBeLessThan(200);

  // ViewZone insertion/removal changes content-space scroll offsets. Switching
  // layouts must retain the same modified model line at the same viewport
  // pixel instead of keeping a now-displaced numeric scrollTop.
  const modifiedPane = diff.locator('.moonbit-diff-editor-modified');
  const modifiedScrollable = modifiedPane.locator(
    '.monaco-scrollable-element.editor-scrollable',
  );
  await modifiedScrollable.hover();
  await page.mouse.wheel(0, 18_000);
  await expect
    .poll(async () => (await firstFullyVisibleModelLine(modifiedPane))?.text ?? '')
    .toContain('modified_');
  const splitAnchor = await firstFullyVisibleModelLine(modifiedPane);
  expect(splitAnchor).not.toBeNull();

  const layoutToggle = page.locator('[data-action="toggle-diff-layout"]');
  await layoutToggle.click();
  await expect(diff).toHaveAttribute('data-render-mode', 'unified');
  await expect
    .poll(async () => firstFullyVisibleModelLine(modifiedPane))
    .toEqual(splitAnchor);

  await layoutToggle.click();
  await expect(diff).toHaveAttribute('data-render-mode', 'side-by-side');
  await expect
    .poll(async () => firstFullyVisibleModelLine(modifiedPane))
    .toEqual(splitAnchor);
});

test('keeps tab-expanded unified deletions inside the horizontal scroll extent', async ({
  page,
}) => {
  await page.goto('/embed.html');
  await expect(page.locator('.editor-shell')).toHaveAttribute('data-status', 'ready');

  await page.locator(workspaceItem('tabbed-deletion.mbt')).click();
  await page.locator('[data-action="toggle-diff"]').click();
  await page.locator('[data-action="toggle-diff-layout"]').click();

  const modifiedPane = page.locator(
    '.diff-viewer-host .moonbit-diff-editor-modified',
  );
  const deletedLine = modifiedPane.locator(
    '.diff-editor-unified-deleted-line',
  );
  await expect(deletedLine).toContainText('deleted_tail');
  const widths = await modifiedPane.evaluate((pane) => {
    const rail = pane.querySelector('.view-zones');
    const line = pane.querySelector('.diff-editor-unified-deleted-line');
    const viewport = pane.querySelector(
      '.monaco-scrollable-element.editor-scrollable',
    );
    return {
      rail: Number.parseFloat(rail.style.width),
      deleted: line.scrollWidth,
      viewport: viewport.clientWidth,
    };
  });
  expect(widths.deleted).toBeGreaterThan(widths.viewport + 500);
  expect(widths.rail + 1).toBeGreaterThanOrEqual(widths.deleted);
});

test('renders character changes inside the line-level diff', async ({ page }) => {
  await page.goto('/embed.html');
  await expect(page.locator('.editor-shell')).toHaveAttribute('data-status', 'ready');

  await page.locator(workspaceItem('src/lib')).click();
  await page.locator(workspaceItem('src/lib/util.mbt')).click();
  await expect(page.locator(sourceEditor)).toContainText('42');
  await page.locator('[data-action="toggle-diff"]').click();
  await page.locator('[data-action="toggle-diff-layout"]').click();

  const diff = page.locator('.diff-viewer-host > .moonbit-diff-editor');
  const originalPane = diff.locator('.moonbit-diff-editor-original');
  const modifiedPane = diff.locator('.moonbit-diff-editor-modified');
  await expect(diff).toHaveAttribute('data-render-mode', 'unified');
  await expect(originalPane).toBeHidden();
  await expect(
    modifiedPane.locator(
      '.diff-editor-unified-deleted-line .diff-editor-char-delete',
    ),
  ).toHaveText('1');
  await expect(modifiedPane.locator('.diff-editor-char-insert')).toHaveText('2');
  await expect(
    modifiedPane.locator('.diff-editor-unified-deleted-line'),
  ).toHaveCount(1);
  await expect(modifiedPane.locator('.diff-editor-line-insert')).toHaveCount(1);
});

test('switches standard token and tree diff only for mbt comparisons', async ({ page }) => {
  await page.goto('/embed.html');
  await expect(page.locator('.editor-shell')).toHaveAttribute('data-status', 'ready');
  await page.locator('[data-action="toggle-diff"]').click();

  const diff = page.locator('.diff-viewer-host > .moonbit-diff-editor');
  const toolbar = diff.locator('.moonbit-diff-editor-toolbar');
  const standard = toolbar.getByRole('button', { name: 'Standard diff' });
  const token = toolbar.getByRole('button', { name: 'Token diff' });
  const tree = toolbar.getByRole('button', { name: 'Tree diff' });
  const ignoreComments = toolbar.getByRole('button', {
    name: 'Ignore comments',
  });
  await expect(toolbar).toBeVisible();
  await expect(standard).toHaveAttribute('aria-pressed', 'true');
  await expect(ignoreComments).toHaveAttribute('aria-pressed', 'true');
  await expect(ignoreComments).toBeDisabled();
  await expect(diff).toHaveAttribute('data-ignore-comments', 'true');
  await expect(diff).toHaveAttribute('data-diff-renderer', 'standard');

  await token.click();
  await expect(token).toHaveAttribute('aria-pressed', 'true');
  await expect(ignoreComments).toBeEnabled();
  await expect(diff).toHaveAttribute('data-diff-mode', 'token');
  await expect(diff).toHaveAttribute('data-diff-renderer', 'token');
  await expect(diff).not.toHaveAttribute('data-diff-fallback', 'true');

  await tree.click();
  await expect(tree).toHaveAttribute('aria-pressed', 'true');
  await expect(diff).toHaveAttribute('data-diff-mode', 'tree');
  await expect(diff).toHaveAttribute('data-diff-renderer', 'tree');
  await expect(diff).not.toHaveAttribute('data-diff-fallback', 'true');

  await standard.click();
  await expect(standard).toHaveAttribute('aria-pressed', 'true');
  await expect(ignoreComments).toBeDisabled();
  await expect(diff).toHaveAttribute('data-diff-renderer', 'standard');

  // Manifests and other non-.mbt files continue to use the existing diff and
  // do not expose language-specific choices.
  await page.locator('[data-action="toggle-diff"]').click();
  await page.locator(workspaceItem('moon.mod')).click();
  await page.locator('[data-action="toggle-diff"]').click();
  await expect(diff).toBeVisible();
  await expect(toolbar).toBeHidden();
  await expect(diff).not.toHaveAttribute('data-moondiff-available', 'true');
  await expect(diff).toHaveAttribute('data-diff-renderer', 'standard');
});

test('toggles comment filtering for token and tree review diffs', async ({ page }) => {
  await page.goto('/embed.html');
  await expect(page.locator('.editor-shell')).toHaveAttribute('data-status', 'ready');
  await page.locator(workspaceItem('comments.mbt')).click();
  await expect(page.locator(sourceEditor)).toContainText('new_value');
  await page.locator('[data-action="toggle-diff"]').click();

  const diff = page.locator('.diff-viewer-host > .moonbit-diff-editor');
  const toolbar = diff.locator('.moonbit-diff-editor-toolbar');
  const token = toolbar.getByRole('button', { name: 'Token diff' });
  const tree = toolbar.getByRole('button', { name: 'Tree diff' });
  const ignoreComments = toolbar.getByRole('button', {
    name: 'Ignore comments',
  });
  const ignoreLabel = ignoreComments.locator(
    '.moonbit-diff-editor-ignore-comments-label',
  );
  const originalPane = diff.locator('.moonbit-diff-editor-original');

  // The standalone label collapses inside the actual diff container rather
  // than relying on the whole browser viewport width.
  const viewerStack = page.locator('.embedded-viewer-stack');
  await viewerStack.evaluate((element) => {
    element.style.width = '300px';
    element.style.flex = '0 0 300px';
  });
  await expect(ignoreComments).toBeVisible();
  await expect(ignoreLabel).toBeHidden();
  const toolbarWidth = await toolbar.evaluate((element) => ({
    client: element.clientWidth,
    scroll: element.scrollWidth,
  }));
  expect(toolbarWidth.scroll).toBeLessThanOrEqual(toolbarWidth.client);
  await viewerStack.evaluate((element) => {
    element.style.width = '';
    element.style.flex = '';
  });

  await token.click();
  await expect(ignoreComments).toBeEnabled();
  await expect(ignoreComments).toHaveAttribute('aria-pressed', 'true');
  await expect(diff).toHaveAttribute('data-diff-renderer', 'token');
  const ignoredTokenText = (
    await originalPane.locator('.diff-editor-char-delete').allTextContents()
  ).join(' ');
  expect(ignoredTokenText).toContain('old');
  expect(ignoredTokenText).not.toContain('obsolete');

  await ignoreComments.click();
  await expect(ignoreComments).toHaveAttribute('aria-pressed', 'false');
  await expect(diff).toHaveAttribute('data-ignore-comments', 'false');
  const visibleTokenText = (
    await originalPane.locator('.diff-editor-char-delete').allTextContents()
  ).join(' ');
  expect(visibleTokenText).toContain('obsolete');

  await tree.click();
  await expect(tree).toHaveAttribute('aria-pressed', 'true');
  await expect(ignoreComments).toHaveAttribute('aria-pressed', 'false');
  await expect(diff).toHaveAttribute('data-diff-renderer', 'tree');
  await ignoreComments.click();
  await expect(ignoreComments).toHaveAttribute('aria-pressed', 'true');
  await expect(diff).toHaveAttribute('data-ignore-comments', 'true');
  const ignoredTreeText = (
    await originalPane.locator('.diff-editor-char-delete').allTextContents()
  ).join(' ');
  expect(ignoredTreeText).not.toContain('obsolete');

  // A fully filtered comparison is still a specialized result. Its inserted
  // blank line aligns later source without painting either ignored line.
  await page.locator('[data-action="toggle-diff"]').click();
  await page.locator(workspaceItem('comments-only.mbt')).click();
  await page.locator('[data-action="toggle-diff"]').click();
  await expect(tree).toHaveAttribute('aria-pressed', 'true');
  await expect(ignoreComments).toHaveAttribute('aria-pressed', 'true');
  await expect(diff).toHaveAttribute('data-diff-renderer', 'tree');
  await expect(
    originalPane.locator('.diff-editor-line-delete, .diff-editor-char-delete'),
  ).toHaveCount(0);
  await expect(
    diff.locator('.moonbit-diff-editor-modified').locator(
      '.diff-editor-line-insert, .diff-editor-char-insert',
    ),
  ).toHaveCount(0);
  await expect(originalPane.locator('.diff-editor-alignment-zone')).toHaveCount(1);

  await page.locator('[data-action="toggle-diff"]').click();
  await page.locator(workspaceItem('comments.mbt')).click();
  await page.locator('[data-action="toggle-diff"]').click();
  await expect(tree).toHaveAttribute('aria-pressed', 'true');
  await expect(ignoreComments).toHaveAttribute('aria-pressed', 'true');

  await page.locator('[data-action="toggle-diff-layout"]').click();
  await expect(diff).toHaveAttribute('data-render-mode', 'unified');
  await expect(
    diff.locator('.diff-editor-unified-deleted-line'),
  ).not.toContainText('obsolete explanation');

  // The component keeps the preference and selected algorithm when its model
  // pair changes within the mounted review surface.
  await page.locator('[data-action="toggle-diff"]').click();
  await page.locator(workspaceItem('src/lib')).click();
  await page.locator(workspaceItem('src/lib/util.mbt')).click();
  await page.locator('[data-action="toggle-diff"]').click();
  await expect(tree).toHaveAttribute('aria-pressed', 'true');
  await expect(ignoreComments).toHaveAttribute('aria-pressed', 'true');
  await expect(ignoreComments).toBeEnabled();
});

test('uses moondiff token fallback when tree diff cannot parse a model', async ({ page }) => {
  await page.goto('/embed.html');
  await expect(page.locator('.editor-shell')).toHaveAttribute('data-status', 'ready');
  await page.locator(workspaceItem('broken.mbt')).click();
  await expect(page.locator(sourceEditor)).toContainText('fn okay');
  await page.locator('[data-action="toggle-diff"]').click();

  const diff = page.locator('.diff-viewer-host > .moonbit-diff-editor');
  const toolbar = diff.locator('.moonbit-diff-editor-toolbar');
  const standard = toolbar.getByRole('button', { name: 'Standard diff' });
  const token = toolbar.getByRole('button', { name: 'Token diff' });
  const tree = toolbar.getByRole('button', { name: 'Tree diff' });
  await tree.click();
  await expect(tree).toHaveAttribute('aria-pressed', 'true');
  await expect(diff).toHaveAttribute('data-diff-mode', 'tree');
  await expect(diff).toHaveAttribute('data-diff-renderer', 'token');
  await expect(diff).toHaveAttribute('data-diff-fallback', 'true');
  await expect(toolbar.locator('.moonbit-diff-editor-mode-status')).toHaveText(
    'Tree diff unavailable — showing token diff',
  );

  // Token mode does not require a parseable tree, and leaving the failed
  // mode clears the fallback notice.
  await token.click();
  await expect(diff).toHaveAttribute('data-diff-renderer', 'token');
  await expect(diff).not.toHaveAttribute('data-diff-fallback', 'true');
  await expect(toolbar.locator('.moonbit-diff-editor-mode-status')).toBeHidden();
  await standard.click();
  await expect(diff).toHaveAttribute('data-diff-renderer', 'standard');
});

test('renders a wide single-line comparison without eager row expansion', async ({ page }) => {
  await page.goto('/embed.html');
  await expect(page.locator('.editor-shell')).toHaveAttribute('data-status', 'ready');

  await page.locator(workspaceItem('oversized-line.mbt')).click();
  await expect(page.locator('.editor-shell')).toHaveAttribute('data-status', 'ready');
  await page.locator('[data-action="toggle-diff"]').click();
  const diff = page.locator('.diff-viewer-host > .moonbit-diff-editor');
  await expect(diff).toBeVisible();
  await expect(
    diff.locator('.moonbit-diff-editor-pane > .monaco-editor'),
  ).toHaveCount(2);
  await expect(diff.locator('.view-line')).toHaveCount(2);
  await expect(diff.locator('.diff-editor-char-delete')).toHaveCount(0);
  await expect(diff.locator('.diff-editor-char-insert')).toHaveCount(0);
});

test('drops a stale host-ready rAF after a rapid model swap', async ({ page }) => {
  await page.addInitScript(() => {
    const queue = [];
    globalThis.__embeddedReadyAnimationFrame = (callback) => {
      queue.push(callback);
    };
    globalThis.__embeddedReadyQueueLength = () => queue.length;
    globalThis.__flushEmbeddedReadyFrame = () => {
      const callback = queue.shift();
      if (callback) callback();
    };
  });

  await page.goto('/embed.html');
  await expect
    .poll(() => page.evaluate(() => globalThis.__embeddedReadyQueueLength()))
    .toBe(1);
  await page.evaluate(() => globalThis.__flushEmbeddedReadyFrame());
  await expect(page.locator('.editor-shell')).toHaveAttribute('data-status', 'ready');
  await expect(page.locator(workspaceItem('src/main.mbt'))).toHaveAttribute(
    'aria-selected',
    'true',
  );

  await page.locator(workspaceItem('src/lib')).click();
  await expect(page.locator(workspaceItem('src/lib/util.mbt'))).toBeVisible();

  // Hold the host-ready callbacks while the Viewer itself continues to render
  // on the browser's native rAF queue. The first callback captures moon.mod;
  // the second captures util.mbt, which is the current model by flush time.
  await page.locator(workspaceItem('moon.mod')).click();
  await expect
    .poll(() => page.evaluate(() => globalThis.__embeddedReadyQueueLength()))
    .toBe(1);
  await page.locator(workspaceItem('src/lib/util.mbt')).click();
  await expect
    .poll(() => page.evaluate(() => globalThis.__embeddedReadyQueueLength()))
    .toBe(2);
  await expect(page.locator('.editor-shell')).toHaveAttribute('data-status', 'loading');

  await page.evaluate(() => globalThis.__flushEmbeddedReadyFrame());
  await expect(page.locator('.editor-shell')).toHaveAttribute('data-status', 'loading');

  await page.evaluate(() => globalThis.__flushEmbeddedReadyFrame());
  await expect(page.locator('.editor-shell')).toHaveAttribute('data-status', 'ready');
  await expect(page.locator(workspaceItem('src/lib/util.mbt'))).toHaveAttribute(
    'aria-selected',
    'true',
  );
  await expect(page.locator('.monaco-editor.readonly-editor')).toContainText(
    'util_answer',
  );
});

function workspaceItem(path) {
  return workspaceSelector(path, { root: 'memory://workspace' });
}

async function firstFullyVisibleModelLine(pane) {
  return pane.evaluate((root) => {
    const viewport = root.querySelector(
      '.monaco-scrollable-element.editor-scrollable',
    );
    if (!viewport) return null;
    const viewportRect = viewport.getBoundingClientRect();
    const line = Array.from(root.querySelectorAll('.view-line')).find((row) => {
      const rect = row.getBoundingClientRect();
      return (
        rect.top >= viewportRect.top - 0.5 &&
        rect.bottom <= viewportRect.bottom + 0.5
      );
    });
    if (!line) return null;
    const rect = line.getBoundingClientRect();
    return {
      text: line.textContent,
      offset: Math.round((rect.top - viewportRect.top) * 10) / 10,
    };
  });
}

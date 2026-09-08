import { promises as fs } from 'node:fs';
import { expect, test } from '../support/test.js';
import {
  openMainFixture,
  openWorkspaceFile,
  workspaceItem,
} from '../support/app.js';

const mainFixture = 'tests/fixtures/workspace/src/main.mbt';
const eventsFixture = 'tests/fixtures/workspace/src/events.mbt';

async function waitForSourceText(page, needle) {
  await expect
    .poll(
      () =>
        page.evaluate(
          (text) => globalThis.__readonlyEditorSource?.includes(text) ?? false,
          needle,
        ),
      { timeout: 7_000 },
    )
    .toBeTruthy();
}

async function settleBrowserFrame(page) {
  await page.evaluate(
    () => new Promise((resolve) => requestAnimationFrame(() => resolve())),
  );
}

async function moveFromMarkdownProseToTextRange(
  page,
  articleSelector,
  text,
  utf16Delta,
) {
  const article = page.locator(articleSelector);
  const prosePoint = await article.evaluate((article) => {
    const prose = article.querySelector('h1');
    if (!prose) throw new Error('Markdown prose heading not found');
    prose.scrollIntoView({ block: 'center', inline: 'nearest' });
    const rect = prose.getBoundingClientRect();
    return {
      x: rect.left + Math.max(Math.min(rect.width / 2, 8), 1),
      y: rect.top + Math.max(rect.height / 2, 1),
    };
  });
  await page.mouse.move(prosePoint.x, prosePoint.y);
  await settleBrowserFrame(page);
  const targetPoint = await article.evaluate(
    (article, { text, utf16Delta }) => {
      const walker = document.createTreeWalker(
        article,
        NodeFilter.SHOW_TEXT,
      );
      let node;
      while ((node = walker.nextNode())) {
        const index = String(node.textContent || '').indexOf(text);
        if (index < 0) continue;
        node.parentElement?.scrollIntoView({
          block: 'center',
          inline: 'nearest',
        });
        const boundary = Math.min(
          String(node.textContent || '').length,
          index + utf16Delta,
        );
        const range = document.createRange();
        range.setStart(node, boundary);
        range.setEnd(node, Math.min(boundary + 1, node.textContent.length));
        const rect = range.getBoundingClientRect();
        return {
          x: rect.left + Math.max(rect.width / 2, 1),
          y: rect.top + Math.max(rect.height / 2, 1),
        };
      }
      throw new Error(`Markdown text node not found: ${text}`);
    },
    { text, utf16Delta },
  );
  await settleBrowserFrame(page);
  await page.mouse.move(targetPoint.x, targetPoint.y);
}

test('starts from native-served static assets', async ({ page }) => {
  const requestedPaths = [];
  page.on('request', (request) => {
    requestedPaths.push(new URL(request.url()).pathname);
  });

  await page.goto('/');
  await expect(page.locator('.editor-shell')).toBeVisible();

  const styleResponse = await page.request.get(
    new URL('/style.css', page.url()).href,
  );
  expect(styleResponse.ok()).toBeTruthy();
  const style = await styleResponse.text();
  expect(style).toContain(
    'src: url("./codicon.ttf") format("truetype")',
  );
  expect(style).not.toContain('url("/codicon.ttf")');

  expect(requestedPaths).toContain('/style.css');
  expect(requestedPaths).toContain('/editor.mjs');
  expect(requestedPaths.some((path) => path.endsWith('/src/bootstrap.js'))).toBeFalsy();
  expect(requestedPaths.some((path) => path.includes('/web/generated/'))).toBeFalsy();
  expect(requestedPaths.some((path) => path.includes('/@vite/'))).toBeFalsy();
});

test('opens MoonBit models as a top-level outline without enforcing later folds', async ({
  page,
}) => {
  await page.goto('/');
  await openWorkspaceFile(page, 'src/events.mbt');

  const editor = page.locator('.monaco-editor.readonly-editor');
  const collapsed = page.locator(
    '.margin-view-overlays .cldr.codicon-folding-collapsed',
  );
  await expect(editor).toContainText('pub struct StartupEvent');
  await expect(editor).toContainText('pub fn startup_event');
  await expect(editor).not.toContainText('message : String');
  await expect(editor).not.toContainText('readonly fixture ready');
  await expect(collapsed).toHaveCount(2);

  const functionLine = editor.locator('.view-line', {
    hasText: 'pub fn startup_event',
  });
  await expect(functionLine.locator('.inline-folded')).toHaveCount(0);
  await expect(functionLine.locator('.inline-folded-body')).toHaveCount(1);
  expect((await functionLine.innerText()).replaceAll('\u00a0', ' ').trim()).toBe(
    'pub fn startup_event() -> StartupEvent {',
  );
  // The struct remains an ordinary fold with Monaco's trailing ellipsis.
  await expect(editor.locator('.inline-folded')).toHaveCount(1);

  // The policy is initial, not enforced: an ordinary chevron click leaves the
  // selected top-level declaration expanded for the rest of this model.
  await collapsed.first().hover();
  await collapsed.first().click();
  await expect(editor).toContainText('message : String');
  await expect(collapsed).toHaveCount(1);

  await collapsed.first().hover();
  await collapsed.first().click();
  await expect(editor).toContainText('readonly fixture ready');
  await expect(collapsed).toHaveCount(0);
});

test('renders MoonBit documentation comments through the real workbench', async ({
  page,
}) => {
  await page.goto('/');
  await openMainFixture(page);

  const markdown = page.locator(
    '.moonbit-viewer-markdown-comment[data-start-line="1"][data-end-line="5"]',
  );
  await expect(markdown).toBeVisible();
  await expect(markdown).toHaveAttribute('data-documentation-foldable', 'true');
  await expect(markdown).toHaveAttribute('data-documentation-expanded', 'false');
  const preview = markdown.locator('.moonbit-viewer-markdown-comment-preview');
  const full = markdown.locator('.moonbit-viewer-markdown-comment-full');
  const toggle = markdown.getByRole('button', {
    name: 'Expand API documentation',
  });
  await expect(preview).toBeVisible();
  await expect(preview.locator('hr + h1')).toHaveText('Fixture entry point');
  await expect(preview).not.toContainText('native shell');
  await expect(full).toBeHidden();
  await expect(toggle).toHaveAttribute('aria-expanded', 'false');
  const showSource = markdown.getByRole('button', {
    name: 'Original source',
  });
  await expect(showSource).toHaveAttribute('title', 'Show original source');
  await showSource.click();
  await expect(markdown).toHaveAttribute('data-source-visible', 'true');
  await expect(
    markdown.locator('.moonbit-viewer-markdown-comment-source'),
  ).toContainText('/// # Fixture entry point');
  await expect(preview).toBeHidden();
  await expect(showSource).toHaveAttribute(
    'title',
    'Show rendered documentation',
  );
  await showSource.click();
  await expect(markdown).toHaveAttribute('data-source-visible', 'false');
  // Source inspection is orthogonal to API-doc folding.
  await expect(markdown).toHaveAttribute('data-documentation-expanded', 'false');
  await expect(preview).toBeVisible();
  await expect(full).toBeHidden();
  // Source/body swaps resize the ViewZone on the next animation frame. Wait
  // for the outer node before using its collapsed height as a baseline.
  await expect
    .poll(() =>
      markdown.evaluate((outer) => {
        const content = outer.querySelector(
          '.moonbit-viewer-markdown-comment-content',
        );
        return (
          Math.round(outer.getBoundingClientRect().height) - content.offsetHeight
        );
      }),
    )
    .toBe(0);
  const collapsedBox = await markdown.boundingBox();
  const toggleBox = await toggle.boundingBox();
  expect(collapsedBox).not.toBeNull();
  expect(toggleBox).not.toBeNull();
  expect(toggleBox.y + toggleBox.height).toBeLessThanOrEqual(
    collapsedBox.y + collapsedBox.height + 1,
  );

  await toggle.click();
  await expect(markdown).toHaveAttribute('data-documentation-expanded', 'true');
  await expect(preview).toBeHidden();
  await expect(full).toBeVisible();
  await expect(full.locator('strong')).toHaveText('native shell');
  await expect
    .poll(async () => (await markdown.boundingBox())?.height ?? 0)
    .toBeGreaterThan(collapsedBox?.height ?? 0);
  const expandedHeight = (await markdown.boundingBox())?.height ?? 0;

  const collapse = markdown.getByRole('button', {
    name: 'Collapse API documentation',
  });
  await collapse.focus();
  await collapse.press('Enter');
  await expect(markdown).toHaveAttribute('data-documentation-expanded', 'false');
  await expect(preview).toBeVisible();
  await expect(full).toBeHidden();
  await expect
    .poll(async () => (await markdown.boundingBox())?.height ?? 0)
    .toBeLessThan(expandedHeight);
  await expect(preview).not.toContainText('|');

  // The gutter chevron shares the code-folding column: same codicon family,
  // horizontally centered on the collapsed `fn main` chevron, and it drives
  // the same fold state with the mouse.
  const gutterToggle = page.locator(
    '.moonbit-viewer-markdown-comment-margin-toggle',
  );
  await expect(gutterToggle).toHaveClass(/codicon-folding-collapsed/);
  const codeChevron = page.locator(
    '.margin-view-overlays .cldr.codicon-folding-collapsed',
  );
  const gutterBox = await gutterToggle.boundingBox();
  const codeBox = await codeChevron.boundingBox();
  expect(gutterBox).not.toBeNull();
  expect(codeBox).not.toBeNull();
  expect(
    Math.abs(gutterBox.x + gutterBox.width / 2 - (codeBox.x + codeBox.width / 2)),
  ).toBeLessThanOrEqual(1);

  await gutterToggle.click();
  await expect(markdown).toHaveAttribute('data-documentation-expanded', 'true');
  await expect(gutterToggle).toHaveClass(/codicon-folding-expanded/);
  await gutterToggle.click();
  await expect(markdown).toHaveAttribute('data-documentation-expanded', 'false');
  await expect(gutterToggle).toHaveClass(/codicon-folding-collapsed/);
  await expect(page.locator('.view-lines')).not.toContainText('Fixture entry point');
  expect(await page.evaluate(() => globalThis.__readonlyEditorSource)).toContain(
    '///|\n/// # Fixture entry point',
  );
});

test('renders undocumented MoonBit item anchors as horizontal separators', async ({
  page,
}) => {
  await page.goto('/');
  await openWorkspaceFile(page, 'src/events.mbt');

  const first = page.locator(
    '.moonbit-viewer-markdown-comment[data-start-line="1"][data-end-line="2"]',
  );
  const second = page.locator(
    '.moonbit-viewer-markdown-comment[data-start-line="6"][data-end-line="7"]',
  );
  await expect(first.locator('hr')).toBeVisible();
  await expect(second.locator('hr')).toBeVisible();
  await expect(first).toHaveAttribute('data-documentation-foldable', 'false');
  await expect(second).toHaveAttribute('data-documentation-foldable', 'false');
  await expect(first.locator('.moonbit-viewer-markdown-comment-toggle')).toBeHidden();
  await expect(second.locator('.moonbit-viewer-markdown-comment-toggle')).toBeHidden();
  const marginToggles = page.locator(
    '.moonbit-viewer-markdown-comment-margin-toggle',
  );
  await expect(marginToggles).toHaveCount(2);
  await expect(marginToggles.nth(0)).toBeHidden();
  await expect(marginToggles.nth(1)).toBeHidden();
  const firstBox = await first.boundingBox();
  const firstSourceToggle = first.getByRole('button', {
    name: 'Original source',
  });
  const firstSourceToggleBox = await firstSourceToggle.boundingBox();
  expect(firstSourceToggleBox).not.toBeNull();
  expect(firstSourceToggleBox.y).toBeGreaterThanOrEqual(firstBox.y - 1);
  expect(firstSourceToggleBox.y + firstSourceToggleBox.height).toBeLessThanOrEqual(
    firstBox.y + firstBox.height + 1,
  );
  expect(
    await first.locator('.moonbit-viewer-markdown-comment-content').evaluate(
      (element) => Number.parseFloat(getComputedStyle(element).paddingRight),
    ),
  ).toBeGreaterThanOrEqual(40);
  const firstCodeLineBox = await page
    .locator('.view-line[data-line="2"]')
    .boundingBox();
  expect(firstBox?.height).toBe(firstCodeLineBox?.height);
  await expect(page.locator('.view-lines')).not.toContainText('///|');
  expect(await page.evaluate(() => globalThis.__readonlyEditorSource)).toContain(
    '///|\npub struct StartupEvent',
  );
});

test('opens Markdown documents through the native protocol and hovers literate MoonBit', async ({
  page,
}) => {
  test.slow();
  await page.goto('/');
  await openMainFixture(page);

  // The workbench supplies the untouched URI-backed model and explicitly
  // selects its MarkdownViewer sibling. The code-only Viewer remains mounted
  // so switching back preserves its DOM lifetime, but it must be hidden.
  await openWorkspaceFile(page, 'README.md');
  await expect(page.locator('.editor-shell')).toHaveAttribute(
    'data-source-uri',
    'readonly-remote://workspace/README.md',
  );
  expect(
    await page.evaluate(() => globalThis.__readonlyEditorModel),
  ).toMatchObject({
    uri: 'readonly-remote://workspace/README.md',
    displayName: 'README.md',
    languageId: 'markdown',
  });
  expect(await page.evaluate(() => globalThis.__readonlyEditorSource)).toContain(
    '# Fixture workspace',
  );
  const markdown = page.locator(
    '.viewer-host > .moonbit-viewer-markdown-document',
  );
  await expect(markdown).toBeVisible();
  await expect(markdown).toHaveAttribute(
    'data-source-uri',
    'readonly-remote://workspace/README.md',
  );
  await expect(markdown.locator('h1')).toHaveText('Fixture workspace');
  await expect(markdown).toContainText('reusable public Viewer');
  const parkedCodeViewer = page.locator('.viewer-host > .monaco-editor');
  await expect(parkedCodeViewer).toHaveCount(1);
  await expect(parkedCodeViewer).toBeHidden();

  // `.mbt.md` keeps the original MoonBit model identity. A real pointer over
  // the compiler-recognized fence symbol reaches the native `moon ide hover`
  // adapter and returns the compiler's original source range.
  await openWorkspaceFile(page, 'src/literate.mbt.md');
  await expect(page.locator('.editor-shell')).toHaveAttribute(
    'data-source-uri',
    'readonly-remote://workspace/src/literate.mbt.md',
  );
  const literateModel = await page.evaluate(
    () => globalThis.__readonlyEditorModel,
  );
  expect(literateModel).toMatchObject({
    uri: 'readonly-remote://workspace/src/literate.mbt.md',
    displayName: 'src/literate.mbt.md',
    languageId: 'moonbit',
  });
  await expect(markdown).toHaveAttribute(
    'data-source-uri',
    'readonly-remote://workspace/src/literate.mbt.md',
  );
  await expect(
    markdown.locator('[data-markdown-code-block="0"]'),
  ).toHaveAttribute('data-markdown-semantic', 'moonbit-check');
  const phraseDivider = markdown.locator(
    '[data-markdown-phrase-divider="true"]',
  );
  await expect(phraseDivider).toHaveCount(1);
  await expect(phraseDivider).toHaveText('///|');
  await expect(phraseDivider).toHaveAttribute('role', 'separator');
  expect(await page.evaluate(() => globalThis.__readonlyEditorSource)).toContain(
    '///|',
  );
  const symbol = markdown
    .locator('[data-markdown-code-line]', { hasText: 'literate_answer' })
    .locator('span', { hasText: 'literate_answer' })
    .first();
  await expect(symbol).toBeVisible();
  const hover = page.locator(
    '.moonbit-viewer-markdown-hover-widget[data-markdown-hover-visible="true"]',
  );
  await moveFromMarkdownProseToTextRange(
    page,
    '.viewer-host > .moonbit-viewer-markdown-document ' +
      '.moonbit-viewer-markdown-document-article',
    'literate_answer',
    6,
  );
  await expect(hover).toBeVisible({ timeout: 60_000 });
  await expect(hover).toContainText('fn literate_answer() -> Int', {
    timeout: 60_000,
  });
  await expect(hover).toHaveAttribute(
    'data-markdown-hover-returned-range',
    '5:4-5:19',
  );
});

test('lazily expands explorer folders and auto-reveals the active file', async ({ page }) => {
  await page.goto('/');
  const initialHref = await page.evaluate(() => window.location.href);

  // Startup auto-opens the first MoonBit file; auto-reveal expands its
  // ancestor chain and selects its row.
  await expect(page.locator('.editor-shell')).toHaveAttribute('data-status', 'ready');
  await expect(page.locator(workspaceItem('moon.mod'))).toHaveAttribute(
    'data-workspace-kind',
    'file',
  );
  await expect(page.locator(workspaceItem('src'))).toHaveAttribute('aria-expanded', 'true');
  await expect(page.locator(workspaceItem('src/main.mbt'))).toHaveAttribute(
    'aria-selected',
    'true',
  );
  await expect(page.locator(workspaceItem('src/errors.mbt'))).toHaveAttribute(
    'data-workspace-kind',
    'file',
  );

  // Collapsing hides children without forgetting the resolved level.
  await page.locator(workspaceItem('src')).click();
  await expect(page.locator(workspaceItem('src'))).toHaveAttribute('aria-expanded', 'false');
  await expect(page.locator(workspaceItem('src/main.mbt'))).toHaveCount(0);

  await page.locator(workspaceItem('src')).click();
  await page.locator(workspaceItem('src/events.mbt')).click();
  await expect(page.locator(workspaceItem('src/events.mbt'))).toHaveAttribute(
    'aria-selected',
    'true',
  );
  await expect(page.locator(workspaceItem('src/main.mbt'))).toHaveAttribute(
    'aria-selected',
    'false',
  );
  expect(await page.evaluate(() => window.location.href)).toBe(initialHref);
});

test('highlights MoonBit sources through the registered language tokenizer', async ({ page }) => {
  await page.goto('/');
  await openWorkspaceFile(page, 'src/errors.mbt');

  // The type color (mtk9) only comes from the MoonBit lexer (capitalized
  // identifier); the plain fallback never emits it.
  await expect(page.locator('.mtk9', { hasText: 'FixtureError' }).first()).toBeVisible();
  await expect(page.locator('.mtk3', { hasText: 'suberror' }).first()).toBeVisible();
});

test('highlights MoonBit manifests through the registered config tokenizer', async ({ page }) => {
  await page.goto('/');
  await openWorkspaceFile(page, 'moon.mod');

  // Property and string colors come from lang_moon_config; the registry-miss
  // fallback would render the complete line with default-foreground spans.
  await expect(page.locator('.mtk4', { hasText: 'name' }).first()).toBeVisible();
  await expect(
    page.locator('.mtk5', { hasText: '"readonly/fixture"' }).first(),
  ).toBeVisible();
});

test('renders unregistered languages with default/plain spans', async ({ page }) => {
  await page.goto('/');
  await openWorkspaceFile(page, 'notes.txt');

  await expect(page.locator('.monaco-editor.readonly-editor')).toContainText('Fixture notes');
  await expect(page.locator('.mtk1', { hasText: 'value' }).first()).toBeVisible();
  // Registry misses intentionally do not run the generic fallback lexer; the
  // line renderer fills the content with default-foreground (mtk1) spans, never
  // the variable/type/punctuation colors.
  await expect(page.locator('.view-line span.mtk4')).toHaveCount(0);
  await expect(page.locator('.view-line span.mtk9')).toHaveCount(0);
  await expect(page.locator('.view-line span.mtk8')).toHaveCount(0);
});

test('preserves mixed folding state across watched disk changes', async ({ page }) => {
  const original = await fs.readFile(eventsFixture, 'utf8');

  try {
    await page.goto('/');
    await openWorkspaceFile(page, 'src/events.mbt');

    const editor = page.locator('.monaco-editor.readonly-editor');
    const collapsed = page.locator(
      '.margin-view-overlays .cldr.codicon-folding-collapsed',
    );
    await expect(collapsed).toHaveCount(2);
    await collapsed.first().hover();
    await collapsed.first().click();
    await expect(editor).toContainText('message : String');
    await expect(editor).not.toContainText('readonly fixture ready');
    await expect(collapsed).toHaveCount(1);

    await fs.writeFile(eventsFixture, `${original}\n// watched refresh\n`, 'utf8');
    await waitForSourceText(page, '// watched refresh');

    await expect(editor).toContainText('message : String');
    await expect(editor).not.toContainText('readonly fixture ready');
    await expect(collapsed).toHaveCount(1);
  } finally {
    await fs.writeFile(eventsFixture, original, 'utf8');
  }
});

test('keeps one tab watch active after another tab disconnects', async ({
  context,
  page,
}) => {
  const original = await fs.readFile(mainFixture, 'utf8');
  const remainingPage = await context.newPage();

  try {
    await Promise.all([page.goto('/'), remainingPage.goto('/')]);
    await Promise.all([openMainFixture(page), openMainFixture(remainingPage)]);
    await page.close();

    await fs.writeFile(
      mainFixture,
      original.replace(
        'println(event.message)',
        'println("remaining tab still watched")',
      ),
      'utf8',
    );
    await waitForSourceText(
      remainingPage,
      'println("remaining tab still watched")',
    );
    // The watch/session contract ends at source synchronization. Folding and
    // token CSS are covered independently and are not evidence about whether
    // closing the first tab disposed the second tab's watch.
  } finally {
    await fs.writeFile(mainFixture, original, 'utf8');
  }
});

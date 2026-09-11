import { expect, gotoBrowserScenario, test } from '../support/test.js';

const rootSelector =
  '.diff-markdown-comments-host > .moonbit-diff-editor';
const commentSelector = '.moonbit-viewer-markdown-comment';

async function openFixture(page) {
  await gotoBrowserScenario(page, 'diff-markdown-comments');
  await page.waitForFunction(() =>
    Boolean(globalThis.__diffMarkdownCommentsControls),
  );
  const root = page.locator(rootSelector);
  await expect(root).toHaveCount(1);
  return root;
}

async function control(page, method, value) {
  await page.evaluate(({ method: name, value: argument }) => {
    globalThis.__diffMarkdownCommentsControls[name](argument);
  }, { method, value });
}

async function waitForFrames(page, count = 4) {
  await page.evaluate((frameCount) => new Promise((resolve) => {
    let remaining = frameCount;
    const advance = () => {
      remaining -= 1;
      if (remaining <= 0) resolve();
      else requestAnimationFrame(advance);
    };
    requestAnimationFrame(advance);
  }), count);
}

async function expectTailAlignment(root) {
  await expect.poll(() => root.evaluate((node) => {
    const tailTop = (paneClass) => {
      const pane = node.querySelector(paneClass);
      const lines = Array.from(pane.querySelectorAll(
        '.view-lines[data-view-part="view-lines"] > .view-line',
      ));
      const line = lines.at(-1);
      return line?.getBoundingClientRect().top ?? null;
    };
    const original = tailTop('.moonbit-diff-editor-original');
    const modified = tailTop('.moonbit-diff-editor-modified');
    if (original == null || modified == null) return null;
    return Math.abs(original - modified);
  })).not.toBeNull();
  await expect.poll(() => root.evaluate((node) => {
    const top = (paneClass) => Array.from(
      node.querySelector(paneClass).querySelectorAll(
        '.view-lines[data-view-part="view-lines"] > .view-line',
      ),
    ).at(-1)?.getBoundingClientRect().top;
    const original = top('.moonbit-diff-editor-original');
    const modified = top('.moonbit-diff-editor-modified');
    return original == null || modified == null
      ? Number.POSITIVE_INFINITY
      : Math.abs(original - modified);
  })).toBeLessThanOrEqual(1);
}

async function expectOriginalLineNumbers(original, expected) {
  await expect.poll(() => original.evaluate((node) =>
    Array.from(node.querySelectorAll('.line-numbers'), (line) =>
      line.textContent.trim(),
    ),
  )).toEqual(expect.arrayContaining(expected));
}

async function contentHeightState(page) {
  return page.evaluate(() => {
    const controls = globalThis.__diffMarkdownCommentsControls;
    const host = document.querySelector('.diff-markdown-comments-host');
    return {
      eventCount: controls.content_height_event_count(),
      contentHeight: controls.content_height(),
      hostHeight: host.getBoundingClientRect().height,
    };
  });
}

async function expectDecorationsLane(pane, expectedWidth) {
  await expect.poll(() => pane.evaluate((node) => {
    const margin = node.querySelector('.margin');
    const lineNumber = node.querySelector('.line-numbers');
    const toggle = node.querySelector(
      '.moonbit-viewer-markdown-comment-margin-toggle',
    );
    if (!margin || !lineNumber || !toggle) return null;
    const marginRect = margin.getBoundingClientRect();
    const lineNumberRect = lineNumber.getBoundingClientRect();
    const toggleRect = toggle.getBoundingClientRect();
    return {
      lane: marginRect.right - lineNumberRect.right,
      toggle: toggleRect.width,
      toggleRightInset: marginRect.right - toggleRect.right,
    };
  })).toEqual({ lane: expectedWidth, toggle: 16, toggleRightInset: 8 });
}

test('keeps normal editor gutter room for comment and feedback controls', async ({ page }) => {
  const root = await openFixture(page);
  const original = root.locator('.moonbit-diff-editor-original');
  const modified = root.locator('.moonbit-diff-editor-modified');

  // Diff panes do not install the folding controller, but their shared
  // comment/feedback lane still starts with the host's 10px base plus an
  // explicit 16px diff-control reserve.
  await expectDecorationsLane(modified, 26);

  await control(page, 'set_feedback_enabled', true);
  await expectDecorationsLane(modified, 44);

  // DiffEditor reapplies its host options on every layout. Those updates must
  // preserve the live 18px feedback reservation instead of shrinking the
  // lane back to the host base.
  await control(page, 'resize', 620);
  await waitForFrames(page);
  await expectDecorationsLane(modified, 44);

  await control(page, 'set_layout', 'split');
  await expectDecorationsLane(original, 44);
  await expectDecorationsLane(modified, 44);

  await control(page, 'set_layout', 'inline');
  await expectDecorationsLane(modified, 44);
  const inlineOriginalGeometry = await original.evaluate((node) => {
    const host = node.getBoundingClientRect();
    const margin = node.querySelector('.margin').getBoundingClientRect();
    const lineNumber = Array.from(node.querySelectorAll('.line-numbers'))
      .map((element) => element.getBoundingClientRect())
      .find((rect) => rect.width > 0);
    return {
      hostWidth: host.width,
      marginWidth: margin.width,
      lineNumberWidth: lineNumber.right - host.left,
    };
  });
  expect(Math.abs(
    inlineOriginalGeometry.hostWidth - inlineOriginalGeometry.lineNumberWidth,
  )).toBeLessThanOrEqual(0.5);
  expect(inlineOriginalGeometry.hostWidth).toBeLessThan(
    inlineOriginalGeometry.marginWidth,
  );

  const quietLine = modified.locator('.view-line', {
    hasText: 'let before = 1',
  });
  await quietLine.hover();
  const glyph = modified.locator(
    '.margin-view-overlays .cldr.agent-feedback-glyph.line-hover',
  );
  await expect(glyph).toHaveCount(1);
  const glyphGeometry = await glyph.evaluate((element) => {
    const margin = element.closest('.margin').getBoundingClientRect();
    const glyphRect = element.getBoundingClientRect();
    const before = getComputedStyle(element, '::before');
    const visibleLeft = glyphRect.left + Number.parseFloat(before.left);
    const visibleRight = visibleLeft + Number.parseFloat(before.width);
    return {
      marginLeft: margin.left,
      marginRight: margin.right,
      visibleLeft,
      visibleRight,
    };
  });
  expect(glyphGeometry.visibleLeft).toBeGreaterThanOrEqual(
    glyphGeometry.marginLeft - 0.5,
  );
  expect(glyphGeometry.visibleRight).toBeLessThanOrEqual(
    glyphGeometry.marginRight + 0.5,
  );

  const glyphBox = await glyph.boundingBox();
  expect(glyphBox).not.toBeNull();
  await page.mouse.click(
    glyphBox.x + glyphBox.width / 2,
    glyphBox.y + glyphBox.height / 2,
  );
  await expect(
    modified.locator('.agent-feedback-input-widget textarea'),
  ).toBeVisible();
  await page.keyboard.press('Escape');

  const comment = modified.locator(commentSelector);
  const commentToggle = modified.locator(
    '.moonbit-viewer-markdown-comment-margin-toggle',
  );
  await expect(commentToggle).toBeVisible();
  await expect(comment).toHaveAttribute('data-documentation-expanded', 'false');
  await commentToggle.click();
  await expect(comment).toHaveAttribute('data-documentation-expanded', 'true');
  await commentToggle.click();
  await expect(comment).toHaveAttribute('data-documentation-expanded', 'false');
});

test('keeps diff controls independent of host folding settings', async ({ page }) => {
  const root = await openFixture(page);
  const modified = root.locator('.moonbit-diff-editor-modified');

  await control(page, 'set_folding_mode', 'disabled');
  await expectDecorationsLane(modified, 26);
  await control(page, 'set_feedback_enabled', true);
  await expectDecorationsLane(modified, 44);

  await control(page, 'set_feedback_enabled', false);
  await control(page, 'set_folding_mode', 'never');
  await expectDecorationsLane(modified, 26);
  await control(page, 'set_feedback_enabled', true);
  await expectDecorationsLane(modified, 44);
});

test('reclaims the Markdown gutter in source mode while keeping feedback usable', async ({ page }) => {
  const root = await openFixture(page);
  const original = root.locator('.moonbit-diff-editor-original');
  const modified = root.locator('.moonbit-diff-editor-modified');
  const expectSourceLane = async (pane, width) => {
    await expect(pane.locator(commentSelector)).toHaveCount(0);
    await expect.poll(() => pane.evaluate((node) => {
      const margin = node.querySelector('.margin');
      const lineNumber = node.querySelector('.line-numbers');
      return margin && lineNumber
        ? margin.getBoundingClientRect().right - lineNumber.getBoundingClientRect().right
        : null;
    })).toBe(width);
  };

  await control(page, 'set_render_markdown_comments', false);
  await expectSourceLane(modified, 10);
  await control(page, 'set_feedback_enabled', true);
  await expectSourceLane(modified, 28);

  // Layout and host-option replay must not restore the obsolete 16px reserve
  // or lose the live feedback reservation.
  await control(page, 'resize', 620);
  await control(page, 'set_folding_mode', 'disabled');
  await control(page, 'set_layout', 'split');
  await expectSourceLane(original, 28);
  await expectSourceLane(modified, 28);
  await control(page, 'set_layout', 'inline');
  await expectSourceLane(modified, 28);

  await modified.locator('.view-line', { hasText: 'let before = 1' }).hover();
  const glyph = modified.locator('.margin-view-overlays .cldr.agent-feedback-glyph.line-hover');
  await expect(glyph).toBeVisible();
  const geometry = await glyph.evaluate((element) => {
    const margin = element.closest('.margin').getBoundingClientRect();
    const rect = element.getBoundingClientRect();
    const before = getComputedStyle(element, '::before');
    const left = rect.left + Number.parseFloat(before.left);
    return { left, right: left + Number.parseFloat(before.width), marginLeft: margin.left, marginRight: margin.right };
  });
  expect(geometry.left).toBeGreaterThanOrEqual(geometry.marginLeft);
  expect(geometry.right).toBeLessThanOrEqual(geometry.marginRight);
  await glyph.click();
  await expect(modified.locator('.agent-feedback-input-widget textarea')).toBeVisible();
  await page.keyboard.press('Escape');

  await control(page, 'set_render_markdown_comments', true);
  await expectDecorationsLane(modified, 44);
  await control(page, 'set_render_markdown_comments', false);
  await control(page, 'set_feedback_enabled', false);
  await expectSourceLane(modified, 10);
});

test('keeps rich comments in both split panes and only the modified inline pane', async ({ page }) => {
  const root = await openFixture(page);
  const original = root.locator('.moonbit-diff-editor-original');
  const modified = root.locator('.moonbit-diff-editor-modified');

  await expect(root).toHaveAttribute('data-render-mode', 'inline');
  await expect(original.locator(commentSelector)).toHaveCount(0);
  await expect(modified.locator(commentSelector)).toHaveCount(1);
  await expectOriginalLineNumbers(original, ['2', '3', '4', '5', '6']);
  await expectTailAlignment(root);

  await control(page, 'set_layout', 'split');
  await expect(root).toHaveAttribute('data-render-mode', 'side-by-side');
  await expect(original.locator(commentSelector)).toHaveCount(1);
  await expect(modified.locator(commentSelector)).toHaveCount(1);
  await expectTailAlignment(root);

  await control(page, 'resize', 620);
  await waitForFrames(page);
  await expect(original.locator(commentSelector)).toHaveCount(1);
  await expect(modified.locator(commentSelector)).toHaveCount(1);
  await expectTailAlignment(root);

  await control(page, 'set_layout', 'inline');
  await expect(root).toHaveAttribute('data-render-mode', 'inline');
  await expect(original.locator(commentSelector)).toHaveCount(0);
  await expect(modified.locator(commentSelector)).toHaveCount(1);
  await expectOriginalLineNumbers(original, ['2', '3', '4', '5', '6']);
  await expectTailAlignment(root);

  await control(page, 'set_layout', 'split');
  await expect(root).toHaveAttribute('data-render-mode', 'side-by-side');
  await expect(original.locator(commentSelector)).toHaveCount(1);
  await expect(modified.locator(commentSelector)).toHaveCount(1);
  await expectTailAlignment(root);
});

test('aligns replacement comments through resize and layout round trips', async ({ page }) => {
  const root = await openFixture(page);
  const original = root.locator('.moonbit-diff-editor-original');
  const modified = root.locator('.moonbit-diff-editor-modified');

  await control(page, 'set_fixture', 'replacement');
  await expect(original.locator(commentSelector)).toHaveCount(0);
  await expect(modified.locator(commentSelector)).toHaveCount(1);
  await expect(
    modified.locator('.diff-editor-inline-deleted-block'),
  ).toHaveCount(1);
  await expectOriginalLineNumbers(original, ['2', '3', '4', '5']);
  await expectTailAlignment(root);

  await control(page, 'set_layout', 'split');
  await expect(original.locator(commentSelector)).toHaveCount(1);
  await expect(modified.locator(commentSelector)).toHaveCount(1);
  await expectTailAlignment(root);

  await control(page, 'resize', 540);
  await waitForFrames(page);
  await expectTailAlignment(root);

  await control(page, 'set_layout', 'inline');
  await expect(original.locator(commentSelector)).toHaveCount(0);
  await expect(modified.locator(commentSelector)).toHaveCount(1);
  await expect(
    modified.locator('.diff-editor-inline-deleted-block'),
  ).toHaveCount(1);
  await expectOriginalLineNumbers(original, ['2', '3', '4', '5']);
  await expectTailAlignment(root);

  await control(page, 'resize', 760);
  await waitForFrames(page);
  await expectTailAlignment(root);

  await control(page, 'set_layout', 'split');
  await expect(original.locator(commentSelector)).toHaveCount(1);
  await expect(modified.locator(commentSelector)).toHaveCount(1);
  await expectTailAlignment(root);
});

test('balances a final-line change inside a compact multi-line comment', async ({ page }) => {
  const root = await openFixture(page);
  const original = root.locator('.moonbit-diff-editor-original');
  const modified = root.locator('.moonbit-diff-editor-modified');
  const modifiedCompensation = modified.locator(
    '.moonbit-diff-editor-inline-modified-companion-spacer',
  );

  await control(page, 'set_fixture', 'partial');
  await expect(root).toHaveAttribute('data-render-mode', 'inline');
  await expect(original.locator(commentSelector)).toHaveCount(0);
  await expect(modified.locator(commentSelector)).toHaveCount(1);
  await expect(
    modified.locator('.diff-editor-inline-deleted-block'),
  ).toHaveCount(1);
  await expect(modifiedCompensation).toHaveCount(1);
  await expect.poll(() => modifiedCompensation.evaluate((node) =>
    node.getBoundingClientRect().height,
  )).toBeGreaterThan(0);
  await expectOriginalLineNumbers(
    original,
    ['2', '3', '4', '5', '6', '7', '8'],
  );
  await expectTailAlignment(root);

  await control(page, 'set_layout', 'split');
  await expect(root).toHaveAttribute('data-render-mode', 'side-by-side');
  await expect(original.locator(commentSelector)).toHaveCount(1);
  await expect(modified.locator(commentSelector)).toHaveCount(1);
  await expect(modifiedCompensation).toHaveCount(0);
  await expectTailAlignment(root);

  await control(page, 'set_layout', 'inline');
  await expect(root).toHaveAttribute('data-render-mode', 'inline');
  await expect(original.locator(commentSelector)).toHaveCount(0);
  await expect(modified.locator(commentSelector)).toHaveCount(1);
  await expect(modifiedCompensation).toHaveCount(1);
  await expectTailAlignment(root);
});

test('publishes one final paired height for a Markdown comment fold change', async ({ page }) => {
  const root = await openFixture(page);
  const original = root.locator('.moonbit-diff-editor-original');
  const modified = root.locator('.moonbit-diff-editor-modified');

  await control(page, 'set_layout', 'split');
  await expect(original.locator(commentSelector)).toHaveCount(1);
  await expect(modified.locator(commentSelector)).toHaveCount(1);
  await waitForFrames(page, 6);
  await page.evaluate(() => {
    globalThis.__diffMarkdownCommentsControls.enable_auto_height();
  });
  await waitForFrames(page, 4);

  const folded = await contentHeightState(page);
  expect(Math.abs(
    folded.hostHeight - Math.max(40, Math.ceil(folded.contentHeight) + 2),
  )).toBeLessThanOrEqual(1);

  await modified.locator(
    '.moonbit-viewer-markdown-comment-toggle[aria-label="Expand API documentation"]',
  ).click();
  await expect.poll(async () =>
    (await contentHeightState(page)).eventCount,
  ).toBe(folded.eventCount + 1);

  const expanded = await contentHeightState(page);
  expect(expanded.hostHeight).toBeGreaterThan(folded.hostHeight);
  expect(Math.abs(
    expanded.hostHeight - Math.max(40, Math.ceil(expanded.contentHeight) + 2),
  )).toBeLessThanOrEqual(1);
  await expect.poll(() => modified.locator(commentSelector).evaluate((node) => {
    const content = node.querySelector(
      '.moonbit-viewer-markdown-comment-content',
    );
    return Math.abs(
      node.getBoundingClientRect().height - content.offsetHeight,
    );
  })).toBeLessThanOrEqual(1);
  await expectTailAlignment(root);

  await waitForFrames(page, 6);
  const stableExpanded = await contentHeightState(page);
  expect(stableExpanded.eventCount).toBe(expanded.eventCount);
  expect(Math.abs(stableExpanded.hostHeight - expanded.hostHeight))
    .toBeLessThanOrEqual(1);

  await modified.locator(
    '.moonbit-viewer-markdown-comment-toggle[aria-label="Collapse API documentation"]',
  ).click();
  await expect.poll(async () =>
    (await contentHeightState(page)).eventCount,
  ).toBe(expanded.eventCount + 1);
  const collapsed = await contentHeightState(page);
  expect(collapsed.hostHeight).toBeLessThan(expanded.hostHeight);
  expect(Math.abs(
    collapsed.hostHeight - Math.max(40, Math.ceil(collapsed.contentHeight) + 2),
  )).toBeLessThanOrEqual(1);
  expect(Math.abs(collapsed.hostHeight - folded.hostHeight))
    .toBeLessThanOrEqual(1);
  await expectTailAlignment(root);

  await waitForFrames(page, 6);
  const stableCollapsed = await contentHeightState(page);
  expect(stableCollapsed.eventCount).toBe(collapsed.eventCount);
  expect(Math.abs(stableCollapsed.hostHeight - collapsed.hostHeight))
    .toBeLessThanOrEqual(1);
});

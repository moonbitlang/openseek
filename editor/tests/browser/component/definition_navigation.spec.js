import { expect, gotoBrowserScenario, test } from '../support/test.js';
import {
  expectMoonBitReportPassed,
  installMoonBitReporter,
} from '../support/moonbit_reporter.js';

const outerEditor =
  '.definition-host > .monaco-editor.readonly-editor';
const definitionLink = `${outerEditor} .moonbit-viewer-definition-link`;
const peek = `${outerEditor} .moonbit-viewer-references-peek`;
const preview =
  `${peek} .moonbit-viewer-references-peek-preview > ` +
  '.monaco-editor.readonly-editor';
const markdownEditor =
  '.definition-markdown-host > .moonbit-viewer-markdown-document';
const markdownArticle =
  `${markdownEditor} .moonbit-viewer-markdown-document-article`;
const markdownPeek =
  `${markdownEditor} > .moonbit-viewer-markdown-document-overlays > ` +
  '.moonbit-viewer-references-peek-overlay';
const markdownPreview =
  `${markdownPeek} .moonbit-viewer-references-peek-preview > ` +
  '.monaco-editor.readonly-editor';
const markdownDefinitionLink =
  `${markdownEditor} .moonbit-viewer-markdown-definition-link`;
const contextMenu =
  'body > .moonbit-context-menu:not(.moonbit-context-submenu)';
const goToDefinitionAction =
  `${contextMenu} ` +
  '[data-context-menu-command="editor.action.revealDefinition"]';
const peekDefinitionAction =
  `${contextMenu} ` +
  '[data-context-menu-command="editor.action.peekDefinition"]';
const goToReferencesAction =
  `${contextMenu} ` +
  '[data-context-menu-command="editor.action.goToReferences"]';
const peekReferencesAction =
  `${contextMenu} ` +
  '[data-context-menu-command="editor.action.referenceSearch.trigger"]';
const platformModifier = process.platform === 'darwin' ? 'Meta' : 'Control';

async function settle(page) {
  await page.evaluate(
    () =>
      new Promise((resolve) =>
        requestAnimationFrame(() => requestAnimationFrame(resolve)),
      ),
  );
}

async function mountDefinitionFixture(page, testInfo) {
  const reporter = await installMoonBitReporter(page);
  await gotoBrowserScenario(page, 'definition-navigation');
  await page.waitForFunction(() => Boolean(globalThis.__definitionControls));
  const report = await reporter.waitForReport(testInfo, {
    suite: 'definition',
    timeout: 10_000,
  });
  expectMoonBitReportPassed(report, { suite: 'definition' });
  await expect(page.locator(outerEditor)).toContainText('definition_alpha');
  await settle(page);
  return reporter;
}

async function state(page) {
  return page.evaluate(() => globalThis.__definitionControls.state());
}

async function control(page, method) {
  await page.evaluate(
    (name) => globalThis.__definitionControls[name](),
    method,
  );
}

async function resetScroll(page) {
  await page.evaluate(() => globalThis.__definitionControls.reset_scroll());
  await settle(page);
}

async function contextMenuDefaultPrevented(page, probeSelector, gesture) {
  await page.evaluate((selector) => {
    globalThis.__definitionContextMenuDefaultPrevented = null;
    document.querySelector(selector).addEventListener(
      'contextmenu',
      (event) => {
        globalThis.__definitionContextMenuDefaultPrevented =
          event.defaultPrevented;
      },
      { once: true },
    );
  }, probeSelector);
  await gesture();
  await expect
    .poll(() =>
      page.evaluate(
        () => globalThis.__definitionContextMenuDefaultPrevented,
      ),
    )
    .not.toBeNull();
  return page.evaluate(
    () => globalThis.__definitionContextMenuDefaultPrevented,
  );
}

async function textRange(page, rootSelector, line, needle) {
  const result = await page.locator(rootSelector).evaluate(
    (root, request) => {
      const viewLine = root.querySelector(
        `.view-line[data-line="${request.line}"]`,
      );
      if (!viewLine) return null;
      const walker = document.createTreeWalker(
        viewLine,
        NodeFilter.SHOW_TEXT,
      );
      for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        const index = node.textContent.indexOf(request.needle);
        if (index < 0) continue;
        const range = document.createRange();
        range.setStart(node, index);
        range.setEnd(node, index + request.needle.length);
        const rect = range.getBoundingClientRect();
        return {
          x: rect.x + rect.width / 2,
          y: rect.y + rect.height / 2,
          left: rect.left,
          top: rect.top,
          width: rect.width,
          height: rect.height,
        };
      }
      return null;
    },
    { line, needle },
  );
  expect(result).not.toBeNull();
  return result;
}

async function referencePoint(page) {
  return textRange(page, outerEditor, 2, 'definition_alpha');
}

async function markdownTextRange(page, needle, semantic, occurrence = 0) {
  const result = await page.locator(markdownEditor).evaluate(
    (root, request) => {
      const candidates = request.semantic
        ? root.querySelectorAll('.moonbit-viewer-markdown-code-line')
        : root.querySelectorAll(
            '.moonbit-viewer-markdown-code-block:not([data-markdown-semantic])',
          );
      let seen = 0;
      for (const candidate of candidates) {
        const walker = document.createTreeWalker(
          candidate,
          NodeFilter.SHOW_TEXT,
        );
        const nodes = [];
        let text = '';
        for (let node = walker.nextNode(); node; node = walker.nextNode()) {
          nodes.push({ node, start: text.length });
          text += node.textContent;
        }
        for (
          let index = text.indexOf(request.needle);
          index >= 0;
          index = text.indexOf(request.needle, index + 1)
        ) {
          if (seen++ !== request.occurrence) continue;
          const start = nodes.findLast((entry) => entry.start <= index);
          const endOffset = index + request.needle.length;
          const end = nodes.findLast(
            (entry) => entry.start <= endOffset,
          );
          const range = document.createRange();
          range.setStart(start.node, index - start.start);
          range.setEnd(end.node, endOffset - end.start);
          const rect = range.getBoundingClientRect();
          return {
            x: rect.x + rect.width / 2,
            y: rect.y + rect.height / 2,
            left: rect.left,
            top: rect.top,
            width: rect.width,
            height: rect.height,
          };
        }
      }
      return null;
    },
    { needle, semantic, occurrence },
  );
  expect(result).not.toBeNull();
  return result;
}

async function armDefinitionLink(page) {
  const point = await referencePoint(page);
  await page.mouse.move(2, 2);
  await page.keyboard.down(platformModifier);
  await page.mouse.move(point.x, point.y);
  await expect(page.locator(definitionLink)).toHaveCount(1);
  return point;
}

test('HTML context menu preserves an enclosing selection and runs Go to Definition after closing', async ({
  page,
}, testInfo) => {
  const reporter = await mountDefinitionFixture(page, testInfo);
  try {
    await page.evaluate(
      () => globalThis.__definitionControls.select_reference(),
    );
    const point = await referencePoint(page);
    expect(
      await contextMenuDefaultPrevented(page, outerEditor, () =>
        page.mouse.click(point.x, point.y, { button: 'right' }),
      ),
    ).toBe(true);
    await expect(page.locator(contextMenu)).toHaveCount(1);
    await expect(page.locator(`${contextMenu} [role="menu"]`)).toHaveCount(1);
    await expect(page.locator(`${contextMenu} [role="menuitem"]`)).toHaveCount(
      4,
    );
    await expect(page.locator(goToDefinitionAction)).toContainText(
      'Go to Definition',
    );
    await expect(page.locator(peekDefinitionAction)).toContainText(
      'Peek Definition',
    );
    await expect(page.locator(goToReferencesAction)).toContainText(
      'Go to References',
    );
    await expect(page.locator(peekReferencesAction)).toContainText(
      'Peek References',
    );
    const menuState = await page.locator(contextMenu).evaluate((root) => {
      const item = root.querySelector('.action-menu-item');
      const menu = root.querySelector('.monaco-menu');
      const keybinding = root.querySelector('.keybinding');
      const style = getComputedStyle(menu);
      return {
        activeInside: root.contains(document.activeElement),
        itemHeight: item.getBoundingClientRect().height,
        background: style.backgroundColor,
        fontSize: style.fontSize,
        keybindingFontSize: getComputedStyle(keybinding).fontSize,
        position: getComputedStyle(root).position,
      };
    });
    expect(menuState.activeInside).toBe(true);
    expect(menuState.itemHeight).toBe(24);
    expect(menuState.background).not.toBe('rgba(0, 0, 0, 0)');
    expect(menuState.keybindingFontSize).toBe(menuState.fontSize);
    expect(menuState.position).toBe('fixed');
    const selection = (await state(page)).selection;
    expect(selection).toEqual({
      anchorLine: 2,
      anchorColumn: 11,
      activeLine: 2,
      activeColumn: 27,
    });

    await page.keyboard.press('Escape');
    await expect(page.locator(contextMenu)).toHaveCount(0);
    await expect
      .poll(() =>
        page.evaluate(
          () =>
            document.activeElement ===
            globalThis.__definitionControls.outerRoot,
        ),
      )
      .toBe(true);

    await page.mouse.click(point.x, point.y, { button: 'right' });
    await expect(page.locator(contextMenu)).toHaveCount(1);
    await page.keyboard.press('Tab');
    await expect(page.locator(contextMenu)).toHaveCount(0);

    await page.mouse.click(point.x, point.y, { button: 'right' });
    await expect(page.locator(contextMenu)).toHaveCount(1);
    await page.locator('.definition-markdown-host').click({
      position: { x: 4, y: 4 },
    });
    await expect(page.locator(contextMenu)).toHaveCount(0);

    await page.mouse.click(point.x, point.y, { button: 'right' });
    await expect(page.locator(contextMenu)).toHaveCount(1);
    await page.evaluate(() => window.dispatchEvent(new Event('blur')));
    await expect(page.locator(contextMenu)).toHaveCount(0);

    const callsBefore = (await state(page)).providerCalls;
    await page.mouse.click(point.x, point.y, { button: 'right' });
    await page.locator(goToDefinitionAction).click();
    await expect(page.locator(contextMenu)).toHaveCount(0);
    await expect
      .poll(async () => (await state(page)).position)
      .toEqual({ line: 1, column: 5 });
    expect((await state(page)).providerCalls).toBe(callsBefore + 1);
  } finally {
    reporter.dispose();
  }
});

test('definition link preserves plain selection, paints only while armed, and navigates on an exact modifier click', async ({
  page,
}, testInfo) => {
  const reporter = await mountDefinitionFixture(page, testInfo);
  try {
    const plainPoint = await referencePoint(page);
    await page.mouse.click(plainPoint.x, plainPoint.y);
    const plain = await state(page);
    expect(plain.position.line).toBe(2);
    expect(plain.selection.anchorLine).toBe(2);
    expect(plain.selection.activeLine).toBe(2);
    expect(plain.selection.anchorColumn).toBe(plain.selection.activeColumn);
    expect(plain.providerCalls).toBe(0);
    await expect(page.locator(definitionLink)).toHaveCount(0);

    await armDefinitionLink(page);
    const linkStyle = await page.locator(definitionLink).evaluate((node) => {
      const style = getComputedStyle(node);
      return {
        cursor: style.cursor,
        textDecorationLine: style.textDecorationLine,
      };
    });
    expect(linkStyle.cursor).toBe('pointer');
    expect(linkStyle.textDecorationLine).toContain('underline');

    await page.keyboard.up(platformModifier);
    await expect(page.locator(definitionLink)).toHaveCount(0);
    expect((await state(page)).position.line).toBe(2);

    const emptyTarget = await textRange(page, outerEditor, 2, 'use');
    await page.keyboard.down(platformModifier);
    await page.mouse.move(emptyTarget.x, emptyTarget.y);
    await settle(page);
    await expect(page.locator(definitionLink)).toHaveCount(0);
    await expect(
      page.locator(`${outerEditor} .moonbit-viewer-definition-message`),
    ).toBeHidden();
    await page.keyboard.up(platformModifier);

    const scrollPoint = await armDefinitionLink(page);
    await page.mouse.move(scrollPoint.x, scrollPoint.y);
    await page.mouse.wheel(0, 240);
    await expect.poll(async () => (await state(page)).scrollTop).toBeGreaterThan(0);
    await expect(page.locator(definitionLink)).toHaveCount(0);
    await page.keyboard.up(platformModifier);

    await resetScroll(page);
    const lateModifierPoint = await referencePoint(page);
    await page.mouse.move(lateModifierPoint.x, lateModifierPoint.y);
    await page.mouse.down();
    await page.keyboard.down(platformModifier);
    await page.mouse.up();
    await settle(page);
    const afterLateModifier = await state(page);
    expect(afterLateModifier.position.line).toBe(2);
    expect(afterLateModifier.selection.anchorLine).toBe(2);
    expect(afterLateModifier.selection.activeLine).toBe(2);
    await page.keyboard.up(platformModifier);
    await expect(page.locator(definitionLink)).toHaveCount(0);

    const splitGesturePoint = await armDefinitionLink(page);
    const beforeSplitGesture = await state(page);
    const otherTarget = await textRange(page, outerEditor, 2, 'use');
    await page.mouse.move(splitGesturePoint.x, splitGesturePoint.y);
    await page.mouse.down();
    await page.mouse.move(otherTarget.x, otherTarget.y, { steps: 3 });
    await expect(page.locator(definitionLink)).toHaveCount(0);
    await page.mouse.up();
    await settle(page);
    const afterSplitGesture = await state(page);
    expect(afterSplitGesture.position).toEqual(beforeSplitGesture.position);
    expect(afterSplitGesture.selection).toEqual(beforeSplitGesture.selection);
    await page.keyboard.up(platformModifier);
    await expect(page.locator(definitionLink)).toHaveCount(0);

    const gotoPoint = await armDefinitionLink(page);
    const callsBeforeSameWordMove = (await state(page)).providerCalls;
    await page.mouse.move(gotoPoint.left + 2, gotoPoint.y);
    await settle(page);
    expect((await state(page)).providerCalls).toBe(callsBeforeSameWordMove);
    const callsBeforeClick = (await state(page)).providerCalls;
    await page.mouse.down();
    await page.mouse.up();
    await expect
      .poll(async () => (await state(page)).position)
      .toEqual({ line: 1, column: 5 });
    expect((await state(page)).providerCalls).toBe(callsBeforeClick + 1);
    await expect(page.locator(definitionLink)).toHaveCount(0);
    await page.keyboard.up(platformModifier);
    await expect(page.locator(definitionLink)).toHaveCount(0);
  } finally {
    await page.keyboard.up(platformModifier).catch(() => {});
    reporter.dispose();
  }
});

for (const dismiss of ['close button', 'Escape']) {
  // Real pointer/keyboard input verifies that moving the outer editor's cursor
  // leaves the mounted Peek dismissible through both native event paths.
  test(`Definitions ${dismiss} still closes after the source cursor moves`, async ({
    page,
  }, testInfo) => {
    const reporter = await mountDefinitionFixture(page, testInfo);
    try {
      const anchor = await referencePoint(page);
      await page.mouse.click(anchor.x, anchor.y);
      const originalPosition = (await state(page)).position;
      await page.keyboard.press('Alt+F12');
      await expect(page.locator(preview)).toContainText('definition_alpha');

      const source = await textRange(page, outerEditor, 1, 'definition_alpha');
      await page.mouse.click(source.x, source.y);
      const movedPosition = (await state(page)).position;
      expect(movedPosition).not.toEqual(originalPosition);
      await expect(page.locator(peek)).toBeVisible();

      if (dismiss === 'close button') {
        await page.locator(`${peek} .moonbit-viewer-references-peek-close`).click();
      } else {
        const target = await textRange(page, preview, 1, 'definition_alpha');
        await page.mouse.click(target.x, target.y);
        await page.keyboard.press('Escape');
      }

      await expect(page.locator(peek)).toHaveCount(0);
      expect((await state(page)).position).toEqual(movedPosition);
    } finally {
      reporter.dispose();
    }
  });
}

test('F4 replaces a multi-definition preview without losing preview focus', async ({
  page,
}, testInfo) => {
  const reporter = await mountDefinitionFixture(page, testInfo);
  try {
    await page.evaluate(() =>
      globalThis.__definitionControls.enable_multiple_definitions(),
    );
    const point = await referencePoint(page);
    await page.mouse.click(point.x, point.y);
    await page.keyboard.press('Alt+F12');
    await expect(page.locator(peek)).toHaveCount(1);
    await expect(page.locator(`${peek} [role="treeitem"]`)).toHaveCount(2);
    await expect(page.locator(preview)).toHaveCount(1);
    const providerCalls = (await state(page)).providerCalls;

    await page.locator(preview).focus();
    await page.keyboard.press('F4');
    await expect(
      page.locator(`${preview} .view-line[data-line="3"]`),
    ).toContainText('filler_line_3');
    const nextTarget = await textRange(page, preview, 3, 'filler_line_3');
    await expect
      .poll(async () => page.locator(`${preview} .cursor`).first().boundingBox())
      .not.toBeNull();
    const nextCursor = await page
      .locator(`${preview} .cursor`)
      .first()
      .boundingBox();
    expect(Math.abs(nextCursor.x - nextTarget.left)).toBeLessThan(3);
    await expect
      .poll(() =>
        page.evaluate(
          (selector) => document.activeElement?.matches(selector) ?? false,
          preview,
        ),
      )
      .toBe(true);
    expect((await state(page)).providerCalls).toBe(providerCalls);

    await page.keyboard.press('Shift+F4');
    await expect(
      page.locator(`${preview} .view-line[data-line="1"]`),
    ).toContainText('definition_alpha');
    const previousTarget = await textRange(
      page,
      preview,
      1,
      'definition_alpha',
    );
    const previousCursor = await page
      .locator(`${preview} .cursor`)
      .first()
      .boundingBox();
    expect(Math.abs(previousCursor.x - previousTarget.left)).toBeLessThan(3);
    await expect
      .poll(() =>
        page.evaluate(
          (selector) => document.activeElement?.matches(selector) ?? false,
          preview,
        ),
      )
      .toBe(true);

    await page.keyboard.press('Escape');
    await expect(page.locator(peek)).toHaveCount(0);
  } finally {
    reporter.dispose();
  }
});

test('F12 from semantic Markdown navigates the original source model', async ({
  page,
}, testInfo) => {
  const reporter = await mountDefinitionFixture(page, testInfo);
  try {
    const beforeCalls = (await state(page)).markdownProviderCalls;
    const point = await markdownTextRange(
      page,
      'definition_alpha',
      true,
      0,
    );
    await page.mouse.click(point.x, point.y);
    await page.keyboard.press('F12');
    await expect
      .poll(async () => (await state(page)).markdownProviderCalls)
      .toBe(beforeCalls + 1);
    await expect(page.locator(markdownPeek)).toHaveCount(0);
    await expect(page.locator(markdownPreview)).toHaveCount(0);
    await expect
      .poll(() =>
        page.locator(markdownEditor).evaluate((root) =>
          root.querySelector(
            '.moonbit-viewer-markdown-document-viewport',
          ).scrollTop,
        ),
      )
      .toBeGreaterThan(0);

  } finally {
    reporter.dispose();
  }
});

test('Alt+F12 mounts a Markdown overlay with an injected CodeEditor preview and restores focus', async ({
  page,
}, testInfo) => {
  const reporter = await mountDefinitionFixture(page, testInfo);
  try {
    const point = await markdownTextRange(
      page,
      'definition_alpha',
      true,
      0,
    );
    await page.mouse.click(point.x, point.y);
    await page.keyboard.press('Alt+F12');
    await expect(page.locator(markdownPeek)).toHaveCount(1);
    await expect(page.locator(markdownPeek)).toHaveAttribute(
      'aria-label',
      'Peek Definition',
    );
    await expect(page.locator(markdownPreview)).toHaveCount(1);
    await expect(page.locator(markdownPreview)).toContainText(
      'definition_alpha',
    );

    await page.locator('.definition-markdown-host').evaluate((host) => {
      host.style.width = '640px';
    });
    await settle(page);
    const geometry = await page.locator(markdownPeek).evaluate((root) => {
      const editor = root.closest('.moonbit-viewer-markdown-document');
      const rootRect = root.getBoundingClientRect();
      const editorRect = editor.getBoundingClientRect();
      return {
        width: rootRect.width,
        height: rootRect.height,
        left: rootRect.left,
        right: rootRect.right,
        top: rootRect.top,
        bottom: rootRect.bottom,
        editorLeft: editorRect.left,
        editorRight: editorRect.right,
        editorTop: editorRect.top,
        editorBottom: editorRect.bottom,
      };
    });
    expect(geometry.width).toBeGreaterThan(300);
    expect(geometry.height).toBeGreaterThan(200);
    expect(geometry.left).toBeGreaterThanOrEqual(geometry.editorLeft);
    expect(geometry.right).toBeLessThanOrEqual(geometry.editorRight);
    expect(geometry.top).toBeGreaterThanOrEqual(geometry.editorTop);
    expect(geometry.bottom).toBeLessThanOrEqual(geometry.editorBottom);

    await page.keyboard.press('Escape');
    await expect(page.locator(markdownPeek)).toHaveCount(0);
    await expect
      .poll(() =>
        page.evaluate(
          () =>
            document.activeElement ===
            globalThis.__definitionControls.markdownRoot,
        ),
      )
      .toBe(true);

    const freshPoint = await markdownTextRange(
      page,
      'definition_alpha',
      true,
      0,
    );
    await page.mouse.click(freshPoint.x, freshPoint.y);
    await page.keyboard.press('Alt+F12');
    await expect(page.locator(markdownPeek)).toHaveCount(1);
    await page.locator(markdownEditor).evaluate((root) => {
      globalThis.__definitionRetainedMarkdownRoot = root;
    });
    await control(page, 'replace_markdown_source');
    await expect(page.locator(markdownEditor)).toHaveCount(1);
    expect(
      await page.evaluate(
        (selector) =>
          document.querySelector(selector) ===
          globalThis.__definitionRetainedMarkdownRoot,
        markdownEditor,
      ),
    ).toBe(true);
    await expect(page.locator(markdownPeek)).toHaveCount(0);

    const replacementPoint = await markdownTextRange(
      page,
      'definition_alpha',
      true,
      0,
    );
    await page.mouse.click(replacementPoint.x, replacementPoint.y);
    await page.keyboard.press('Alt+F12');
    await expect(page.locator(markdownPeek)).toHaveCount(1);
    await control(page, 'replace_markdown_model');
    await expect(page.locator(markdownPeek)).toHaveCount(0);
    await expect(page.locator(markdownEditor)).toHaveCount(1);
  } finally {
    reporter.dispose();
  }
});

test('Shift+F12 uses Go to References and keeps the Markdown controller local', async ({
  page,
}, testInfo) => {
  const reporter = await mountDefinitionFixture(page, testInfo);
  try {
    const before = await state(page);
    const point = await markdownTextRange(
      page,
      'definition_alpha',
      true,
      0,
    );
    await page.mouse.click(point.x, point.y);
    await page.keyboard.press('Shift+F12');
    await expect(page.locator(markdownPeek)).toHaveCount(1);
    await expect(page.locator(markdownPeek)).toHaveAttribute(
      'aria-label',
      'Peek References',
    );
    await expect(page.locator(markdownPreview)).toHaveCount(1);
    await expect
      .poll(async () => (await state(page)).referencesProviderCalls)
      .toBe(before.referencesProviderCalls + 1);
    expect((await state(page)).markdownProviderCalls).toBe(
      before.markdownProviderCalls,
    );
    await expect(page.locator(peek)).toHaveCount(0);
    await page.keyboard.press('Escape');
    await expect(page.locator(markdownPeek)).toHaveCount(0);
  } finally {
    reporter.dispose();
  }
});

test('Markdown right-click commands and modifier-click use the shared actions', async ({
  page,
}, testInfo) => {
  const reporter = await mountDefinitionFixture(page, testInfo);
  try {
    let point = await markdownTextRange(
      page,
      'definition_alpha',
      true,
      0,
    );
    expect(
      await contextMenuDefaultPrevented(page, markdownArticle, () =>
        page.mouse.click(point.x, point.y, { button: 'right' }),
      ),
    ).toBe(true);
    await expect(page.locator(`${contextMenu} [role="menuitem"]`)).toHaveCount(
      4,
    );
    await expect(page.locator(goToDefinitionAction)).toContainText(
      'Go to Definition',
    );
    await expect(page.locator(peekDefinitionAction)).toContainText(
      'Peek Definition',
    );
    await expect(page.locator(goToReferencesAction)).toContainText(
      'Go to References',
    );
    await expect(page.locator(peekReferencesAction)).toContainText(
      'Peek References',
    );
    const referenceCalls = (await state(page)).referencesProviderCalls;
    await page.locator(goToReferencesAction).click();
    await expect(page.locator(markdownPeek)).toHaveAttribute(
      'aria-label',
      'Peek References',
    );
    expect((await state(page)).referencesProviderCalls).toBe(
      referenceCalls + 1,
    );
    await page.keyboard.press('Escape');

    point = await markdownTextRange(page, 'definition_alpha', true, 0);
    await page.mouse.move(2, 2);
    await page.keyboard.down(platformModifier);
    await page.mouse.move(point.x, point.y);
    await expect(page.locator(markdownDefinitionLink)).not.toHaveCount(0);
    const definitionCalls = (await state(page)).markdownProviderCalls;
    await page.mouse.down();
    await page.mouse.up();
    await expect
      .poll(async () => (await state(page)).markdownProviderCalls)
      .toBe(definitionCalls + 1);
    await expect(page.locator(markdownDefinitionLink)).toHaveCount(0);
    await page.keyboard.up(platformModifier);
  } finally {
    await page.keyboard.up(platformModifier).catch(() => {});
    reporter.dispose();
  }
});

test('projection replacement cancels a pending Markdown provider', async ({
  page,
}, testInfo) => {
  const reporter = await mountDefinitionFixture(page, testInfo);
  try {
    await control(page, 'delay_markdown_provider');
    const point = await markdownTextRange(
      page,
      'definition_alpha',
      true,
      0,
    );
    await page.mouse.click(point.x, point.y);
    await page.keyboard.press('F12');
    await expect
      .poll(async () => (await state(page)).markdownProviderPending)
      .toBe(true);
    await control(page, 'replace_markdown_source');
    await expect(page.locator(markdownPeek)).toHaveCount(0);
    await control(page, 'release_markdown_provider');
    await expect
      .poll(async () => (await state(page)).markdownProviderPending)
      .toBe(false);
    await settle(page);
    expect((await state(page)).openedUris).toEqual([]);
    await expect(page.locator(markdownPeek)).toHaveCount(0);
  } finally {
    reporter.dispose();
  }
});

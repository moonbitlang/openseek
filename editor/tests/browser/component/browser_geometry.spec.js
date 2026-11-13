import { expect, gotoBrowserScenario, test } from '../support/test.js';
import {
  expectMoonBitReportPassed,
  installMoonBitReporter,
} from '../support/moonbit_reporter.js';

const fonts = ['monospace', 'proportional'];
const lineHeight = 20;
const verticalScrollbarWidth = 14;
const horizontalScrollbarHeight = 12;

const hostSelector = (font) =>
  `.browser-geometry-host[data-geometry-font="${font}"]`;

async function mountGeometry(page, testInfo) {
  const reporter = await installMoonBitReporter(page);
  await gotoBrowserScenario(page, 'browser-geometry');
  await page.waitForFunction(() => Boolean(globalThis.__browserGeometryControls));
  const report = await reporter.waitForReport(testInfo, {
    suite: 'browser_geometry',
    timeout: 10_000,
  });
  expectMoonBitReportPassed(report, { suite: 'browser_geometry' });
  expect(report.metrics).toMatchObject({ devicePixelRatio: 1, fontFaces: 1 });
  await expect(page.locator('.browser-geometry-host .geometry-injected')).toHaveCount(2);
  await settle(page);
  return reporter;
}

async function settle(page) {
  await page.evaluate(
    () =>
      new Promise((resolve) =>
        requestAnimationFrame(() =>
          requestAnimationFrame(() =>
            requestAnimationFrame(() => requestAnimationFrame(resolve)),
          ),
        ),
      ),
  );
}

async function state(page, font, line = 3, column = 6) {
  return page.evaluate(
    ({ fixture, lineNumber, columnNumber }) =>
      globalThis.__browserGeometryControls.state(
        fixture,
        lineNumber,
        columnNumber,
      ),
    { fixture: font, lineNumber: line, columnNumber: column },
  );
}

async function control(page, method, ...args) {
  await page.evaluate(
    ({ controlMethod, controlArgs }) =>
      globalThis.__browserGeometryControls[controlMethod](...controlArgs),
    { controlMethod: method, controlArgs: args },
  );
}

async function textRange(
  page,
  font,
  line,
  needle,
  startOffset = 0,
  endOffset = needle.length,
) {
  return page.locator(hostSelector(font)).evaluate(
    (host, request) => {
      const content = host.querySelector(
        `.view-line[data-line="${request.line}"] .view-line-content`,
      );
      if (!content) return null;
      const walker = document.createTreeWalker(content, NodeFilter.SHOW_TEXT);
      for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        const index = node.textContent.indexOf(request.needle);
        if (index < 0) continue;
        const range = document.createRange();
        range.setStart(node, index + request.startOffset);
        range.setEnd(node, index + request.endOffset);
        const rect = range.getBoundingClientRect();
        const contentRect = content.getBoundingClientRect();
        const rootRect = host
          .querySelector('.monaco-editor.readonly-editor')
          .getBoundingClientRect();
        return {
          left: rect.left,
          top: rect.top,
          width: rect.width,
          height: rect.height,
          contentLeft: contentRect.left,
          rootLeft: rootRect.left,
        };
      }
      return null;
    },
    { line, needle, startOffset, endOffset },
  );
}

async function renderedLines(page, font) {
  return page.locator(hostSelector(font)).evaluate((host) =>
    Array.from(host.querySelectorAll('.view-line-content')).map((content) => ({
      line: Number(content.parentElement.dataset.line),
      text: content.textContent,
      width: content.offsetWidth,
      rect: content.getBoundingClientRect().toJSON(),
    })),
  );
}

async function injectedGeometry(page, font) {
  return page.locator(`${hostSelector(font)} .geometry-injected`).evaluate((node) => {
    const content = node.closest('.view-line-content');
    const root = node.closest('.monaco-editor.readonly-editor');
    return {
      text: node.textContent,
      rect: node.getBoundingClientRect().toJSON(),
      contentRect: content.getBoundingClientRect().toJSON(),
      rootRect: root.getBoundingClientRect().toJSON(),
    };
  });
}

async function firstGlyphGeometry(lineContent) {
  return lineContent.evaluate((content) => {
    const text = content.textContent || '';
    const index = text.search(/\S/u);
    if (index < 0) return null;

    const walker = document.createTreeWalker(content, NodeFilter.SHOW_TEXT);
    let remaining = index;
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      if (remaining >= node.textContent.length) {
        remaining -= node.textContent.length;
        continue;
      }
      const range = document.createRange();
      range.setStart(node, remaining);
      range.setEnd(node, remaining + 1);
      const rect = range.getBoundingClientRect();
      const contentRect = content.getBoundingClientRect();
      return {
        text,
        left: rect.left - contentRect.left,
        width: rect.width,
      };
    }
    return null;
  });
}

function expectNear(actual, expected, tolerance = 1) {
  expect(Math.abs(actual - expected)).toBeLessThanOrEqual(tolerance);
}

test('embedded mono and proportional fonts give fixed tabs fullwidth and combining geometry', async ({
  page,
}, testInfo) => {
  const reporter = await mountGeometry(page, testInfo);
  try {
    expect(
      await page.evaluate(() => globalThis.__browserGeometryControls.font_status()),
    ).toEqual({ mono: true, proportional: true, pixelRatio: 1 });

    const monoI = await textRange(page, 'monospace', 1, 'iiii');
    const monoW = await textRange(page, 'monospace', 1, 'WWWW');
    const proportionalI = await textRange(page, 'proportional', 1, 'iiii');
    const proportionalW = await textRange(page, 'proportional', 1, 'WWWW');
    expectNear(monoI.width, 38.4, 0.15);
    expectNear(monoW.width, 38.4, 0.15);
    expectNear(proportionalI.width, 19.2, 0.15);
    expectNear(proportionalW.width, 57.6, 0.15);
    expectNear(monoI.width, monoW.width, 0.05);
    expect(proportionalW.width).toBeGreaterThan(proportionalI.width * 2.9);

    for (const font of fonts) {
      const fullwidth = await textRange(page, font, 2, 'ｍ');
      const combining = await textRange(page, font, 2, 'é');
      const base = await textRange(page, font, 2, 'e');
      expectNear(fullwidth.width, 19.2, 0.15);
      expectNear(combining.width, base.width, 0.05);

      // The two tabs land at separate four-column stops. Compare the public
      // visible-range query with collapsed DOM Ranges at the following glyphs.
      const beforeB = await textRange(page, font, 2, 'b', 0, 0);
      const beforeC = await textRange(page, font, 2, 'c', 0, 0);
      const atB = await state(page, font, 2, 3);
      const atC = await state(page, font, 2, 5);
      expectNear(atB.offset, beforeB.left - beforeB.contentLeft);
      expectNear(atC.offset, beforeC.left - beforeC.contentLeft);
    }

    expectNear((await state(page, 'monospace', 2, 3)).offset, 38.4, 1);
    expectNear((await state(page, 'monospace', 2, 5)).offset, 76.8, 1);
    expectNear((await state(page, 'proportional', 2, 3)).offset, 22.72, 1);
    expectNear((await state(page, 'proportional', 2, 5)).offset, 45.44, 1);
  } finally {
    reporter.dispose();
  }
});

test('wrapped continuations render Same indentation at exactly two fixed-font columns', async ({
  page,
}, testInfo) => {
  const reporter = await mountGeometry(page, testInfo);
  try {
    await page.evaluate(() => document.fonts.ready);
    const unwrapped = await state(page, 'monospace', 5, 3);
    expect(unwrapped.softWrap).toBe(false);

    await control(page, 'set_wrap', 'monospace', true);
    await expect
      .poll(async () => (await state(page, 'monospace', 5, 3)).viewLines)
      .toBeGreaterThan(unwrapped.viewLines);
    await settle(page);

    const wrappedSegments = page
      .locator(`${hostSelector('monospace')} .view-line-content`)
      .filter({ hasText: /q{4}/u });
    await expect(wrappedSegments).toHaveCount(2);
    const continuation = wrappedSegments.nth(1);
    await expect(continuation).toBeVisible();

    const glyph = await firstGlyphGeometry(continuation);
    expect(glyph).not.toBeNull();
    expect(glyph.text).toMatch(/^\u00a0\u00a0q/u);
    expectNear(glyph.width, 9.6, 0.15);
    expectNear(glyph.left, glyph.width * 2, 0.15);
  } finally {
    reporter.dispose();
  }
});

test('content widgets use their real iframe owner window for overflow modes and 15/22px boundaries', async ({
  page,
}, testInfo) => {
  const reporter = await mountGeometry(page, testInfo);
  try {
    const environment = await page
      .locator('#browser-geometry-owner-frame')
      .evaluate((frame) => ({
        ownerWidth: frame.contentWindow.innerWidth,
        ownerHeight: frame.contentWindow.innerHeight,
        ownerScrollX: frame.contentWindow.scrollX,
        ownerScrollY: frame.contentWindow.scrollY,
        globalWidth: window.innerWidth,
        globalScrollX: window.scrollX,
        globalScrollY: window.scrollY,
        distinctWindow: frame.contentWindow !== window,
      }));
    expect(environment).toMatchObject({
      ownerWidth: 500,
      ownerHeight: 360,
      ownerScrollX: 31,
      ownerScrollY: 47,
      distinctWindow: true,
    });
    expect(environment.ownerWidth).not.toBe(environment.globalWidth);
    expect(environment.ownerScrollX).not.toBe(environment.globalScrollX);
    expect(environment.ownerScrollY).not.toBe(environment.globalScrollY);

    const matrix = await page.evaluate(() =>
      globalThis.__browserGeometryControls.iframe_geometry(),
    );
    expect(matrix.normalExact).toMatchObject({
      position: 'exact',
      top: 50,
      left: 20,
      rectLeft: 29,
      rectTop: 83,
    });

    // Each input begins one pixel outside the horizontal page limit. The
    // owner scroll subtraction and source clamp leave exactly 15 CSS px.
    expect(matrix.leftClamp).toMatchObject({
      position: 'below',
      left: 6,
      rectLeft: 15,
    });
    expect(matrix.rightClamp).toMatchObject({
      position: 'below',
      left: 396,
      rectRight: environment.ownerWidth - 15,
    });

    // Equality at 22px fits. One pixel outside flips to the other ordered
    // preference, proving both the top and bottom fit predicates.
    expect(matrix.topEqual).toMatchObject({
      position: 'above',
      top: -11,
      rectTop: 22,
    });
    expect(matrix.topOutside).toMatchObject({
      position: 'below',
      top: 38,
    });
    expect(matrix.bottomEqual).toMatchObject({
      position: 'below',
      top: 275,
      rectBottom: environment.ownerHeight - 22,
    });
    expect(matrix.bottomOutside).toMatchObject({
      position: 'above',
      top: 226,
    });

    const ownerFrame = page.frameLocator('#browser-geometry-owner-frame');
    const normal = ownerFrame.locator(
      '[data-geometry-owner-widget="normal"]',
    );
    const overflow = ownerFrame.locator(
      '[data-geometry-owner-widget="overflow"]',
    );
    await expect(normal).toHaveAttribute('data-geometry-owner-overflow', 'false');
    await expect(overflow).toHaveAttribute('data-geometry-owner-overflow', 'true');
    expect(
      await normal.evaluate((node) => ({
        ownerIsCurrentWindow: node.ownerDocument.defaultView === window,
        ownerIsTopWindow: node.ownerDocument.defaultView === window.top,
        parentIsContentContainer:
          node.parentElement === document.querySelector('.contentWidgets'),
        maxWidth: node.style.maxWidth,
      })),
    ).toEqual({
      ownerIsCurrentWindow: true,
      ownerIsTopWindow: false,
      parentIsContentContainer: true,
      maxWidth: '430px',
    });
    expect(
      await overflow.evaluate((node) => ({
        ownerIsCurrentWindow: node.ownerDocument.defaultView === window,
        ownerIsTopWindow: node.ownerDocument.defaultView === window.top,
        parentIsOverflowContainer:
          node.parentElement ===
          document.querySelector('.overflowingContentWidgets'),
        maxWidth: node.style.maxWidth,
      })),
    ).toEqual({
      ownerIsCurrentWindow: true,
      ownerIsTopWindow: false,
      parentIsOverflowContainer: true,
      maxWidth: `${environment.ownerWidth}px`,
    });
  } finally {
    reporter.dispose();
  }
});

test('DOM ranges public caret positions and content-widget anchors agree within one CSS pixel', async ({
  page,
}, testInfo) => {
  const reporter = await mountGeometry(page, testInfo);
  try {
    for (const font of fonts) {
      const injection = await injectedGeometry(page, font);
      const anchorStart = await textRange(page, font, 3, 'anchor', 0, 0);
      const afterFirstAnchorGlyph = await textRange(page, font, 3, 'anchor', 1, 1);
      const atInjection = await state(page, font, 3, 5);
      const atCaret = await state(page, font, 3, 6);

      expectNear(
        atInjection.offset,
        injection.rect.left - injection.contentRect.left,
      );
      expectNear(
        atInjection.visible.left,
        injection.rect.left - injection.rootRect.left,
      );
      expectNear(
        atCaret.offset,
        afterFirstAnchorGlyph.left - afterFirstAnchorGlyph.contentLeft,
      );
      expectNear(
        atCaret.visible.left,
        afterFirstAnchorGlyph.left - afterFirstAnchorGlyph.rootLeft,
      );

      await control(page, 'set_position', font, 3, 6);
      await control(page, 'focus', font);
      await settle(page);
      const cursor = page.locator(`${hostSelector(font)} .cursor`).first();
      await expect(cursor).toBeVisible();
      const cursorRect = await cursor.boundingBox();
      expectNear(cursorRect.x, afterFirstAnchorGlyph.left);

      // Hover at the range start. The hover widget's secondary anchor is the
      // provider range start (model column 5), exactly the injected span's
      // left edge; the content-widget layer must use the same DOM geometry.
      await page.mouse.move(0, 0);
      await page.mouse.move(
        anchorStart.left + 0.25,
        anchorStart.top + anchorStart.height / 2,
      );
      const widget = page.locator(
        `${hostSelector(font)} [data-content-widget="editor.contrib.resizableContentHoverWidget"]`,
      );
      await expect(widget.locator('.monaco-hover:not(.hidden)')).toBeVisible({
        timeout: 5_000,
      });
      const widgetRect = await widget.boundingBox();
      expectNear(widgetRect.x, injection.rect.left);

      if (font === 'monospace') {
        // A hidden anchor has no DOM range. If focus is inside the widget, the
        // source parks it at -1000px instead of applying visibility:hidden;
        // clearing the hidden area restores the same mounted widget.
        const link = widget.locator('a');
        await link.focus();
        await expect
          .poll(() => link.evaluate((node) => document.activeElement === node))
          .toBe(true);
        await control(page, 'set_anchor_hidden', font, true);
        await expect(
          page.locator(`${hostSelector(font)} .view-line`, { hasText: 'anchor' }),
        ).toHaveCount(0);
        await expect(widget).not.toHaveAttribute(
          'monaco-visible-content-widget',
          'true',
        );
        expect(await widget.evaluate((node) => node.style.top)).toBe('-1000px');
        expect(await widget.evaluate((node) => node.style.visibility)).not.toBe(
          'hidden',
        );
        expect(await link.evaluate((node) => document.activeElement === node)).toBe(
          true,
        );

        await control(page, 'set_anchor_hidden', font, false);
        await expect(
          page.locator(`${hostSelector(font)} .view-line`, { hasText: 'anchor' }),
        ).toBeVisible();
        await expect(widget).toHaveAttribute(
          'monaco-visible-content-widget',
          'true',
        );
        expect(await link.evaluate((node) => document.activeElement === node)).toBe(
          true,
        );
      }

      await page.mouse.move(1000, 500);

      const beforeState = await state(page, font, 3, 6);
      const beforeInjection = await injectedGeometry(page, font);
      await control(page, 'set_injected', font, true);
      await expect(
        page.locator(`${hostSelector(font)} .geometry-injected`),
      ).toHaveText('[WWWW]');
      await settle(page);
      const afterState = await state(page, font, 3, 6);
      const afterInjection = await injectedGeometry(page, font);
      expectNear(
        afterState.offset - beforeState.offset,
        afterInjection.rect.width - beforeInjection.rect.width,
      );
      const shiftedCaret = await textRange(page, font, 3, 'anchor', 1, 1);
      expectNear(afterState.offset, shiftedCaret.left - shiftedCaret.contentLeft);

      // Exercise the reverse transition too: no stale geometry may survive a
      // same-position injected-text replacement.
      await control(page, 'set_injected', font, false);
      await expect(
        page.locator(`${hostSelector(font)} .geometry-injected`),
      ).toHaveText('[i]');
      await settle(page);
      expectNear((await state(page, font, 3, 6)).offset, beforeState.offset);
    }
  } finally {
    reporter.dispose();
  }
});

test('measured widest-line feedback grows on scroll stays reachable and shrinks on replacement', async ({
  page,
}, testInfo) => {
  const reporter = await mountGeometry(page, testInfo);
  try {
    const initial = await state(page, 'monospace', 4, 2);
    const initiallyRendered = await renderedLines(page, 'monospace');
    const initialWidest = Math.max(...initiallyRendered.map((line) => line.width));
    expect(initiallyRendered.some((line) => line.text.includes('hidden_widest'))).toBe(
      false,
    );
    expectNear(initial.contentWidth, initialWidest + verticalScrollbarWidth);
    expectNear(initial.lineWidth, initiallyRendered.find((line) => line.line === 4).width);

    await control(page, 'set_scroll', 'monospace', 0, 200);
    await expect(
      page.locator(`${hostSelector('monospace')} .view-line`, {
        hasText: 'hidden_widest',
      }),
    ).toBeVisible();
    await expect
      .poll(async () => (await state(page, 'monospace', 12, 2)).contentWidth)
      .toBeGreaterThan(initial.contentWidth + 200);
    const hiddenLines = await renderedLines(page, 'monospace');
    const hidden = hiddenLines.find((line) => line.text.includes('hidden_widest'));
    const afterHidden = await state(page, 'monospace', 12, 2);
    expect(afterHidden.scrollTop).toBe(200);
    expectNear(afterHidden.contentWidth, hidden.width + verticalScrollbarWidth);
    expectNear(afterHidden.lineWidth, hidden.width);

    await control(page, 'set_scroll', 'monospace', 9999, 200);
    await expect
      .poll(async () => (await state(page, 'monospace', 12, 2)).scrollLeft)
      .toBeGreaterThan(0);
    const atRight = await state(page, 'monospace', 12, 2);
    expectNear(
      atRight.scrollLeft,
      atRight.scrollWidth - atRight.layout.contentWidth,
    );
    const rightEdge = await page.locator(hostSelector('monospace')).evaluate((host) => {
      const root = host.querySelector('.monaco-editor.readonly-editor');
      const line = Array.from(host.querySelectorAll('.view-line-content')).find((node) =>
        node.textContent.includes('hidden_widest'),
      );
      return {
        root: root.getBoundingClientRect().toJSON(),
        line: line.getBoundingClientRect().toJSON(),
      };
    });
    expect(rightEdge.line.right).toBeLessThanOrEqual(rightEdge.root.right + 1);
    expectNear(
      rightEdge.root.right - rightEdge.line.right,
      verticalScrollbarWidth,
    );

    await control(page, 'set_hidden_widest', 'monospace', false);
    await expect(
      page.locator(`${hostSelector('monospace')} .view-line`, {
        hasText: 'hidden_widest_WWWWWWWW',
      }),
    ).toBeVisible();
    await expect
      .poll(async () => (await state(page, 'monospace', 12, 2)).scrollLeft)
      .toBe(0);
    await settle(page);
    const replacement = (await renderedLines(page, 'monospace')).find((line) =>
      line.text.includes('hidden_widest'),
    );
    const afterReplacement = await state(page, 'monospace', 12, 2);
    expectNear(
      afterReplacement.contentWidth,
      replacement.width + verticalScrollbarWidth,
    );
    expect(afterReplacement.contentWidth).toBeLessThan(initial.contentWidth);
    expectNear(afterReplacement.contentHeight, 25 * lineHeight);

    // Returning to the initial rendered window discovers its own widest line
    // again; the removed hidden maximum never remains as permanent excess.
    await control(page, 'set_scroll', 'monospace', 0, 0);
    await expect(
      page.locator(`${hostSelector('monospace')} .view-line`, {
        hasText: 'visible_widest',
      }),
    ).toBeVisible();
    await expect
      .poll(async () => (await state(page, 'monospace', 4, 2)).contentWidth)
      .toBeGreaterThan(afterReplacement.contentWidth);
    expectNear((await state(page, 'monospace', 4, 2)).contentWidth, initial.contentWidth);
  } finally {
    reporter.dispose();
  }
});

test('wrap transitions and bottom scroll extent preserve numeric width-height feedback', async ({
  page,
}, testInfo) => {
  const reporter = await mountGeometry(page, testInfo);
  try {
    const noWrap = await state(page, 'monospace', 4, 2);
    expect(noWrap.softWrap).toBe(false);
    expect(noWrap.viewLines).toBe(25);
    expectNear(
      noWrap.contentHeight,
      noWrap.viewLines * lineHeight + horizontalScrollbarHeight,
    );

    await control(page, 'set_wrap', 'monospace', true);
    await expect
      .poll(async () => (await state(page, 'monospace', 4, 2)).viewLines)
      .toBeGreaterThan(25);
    await settle(page);
    const wrapped = await state(page, 'monospace', 4, 2);
    expect(wrapped.softWrap).toBe(true);
    expect(wrapped.contentWidth).toBeLessThan(noWrap.contentWidth);
    const wrappedScrollbar =
      wrapped.scrollWidth > wrapped.layout.contentWidth
        ? horizontalScrollbarHeight
        : 0;
    expectNear(
      wrapped.contentHeight,
      wrapped.viewLines * lineHeight + wrappedScrollbar,
    );

    await control(page, 'set_wrap', 'monospace', false);
    await expect
      .poll(async () => (await state(page, 'monospace', 4, 2)).viewLines)
      .toBe(25);
    await settle(page);
    const restored = await state(page, 'monospace', 4, 2);
    expect(restored.softWrap).toBe(false);
    expectNear(restored.contentWidth, noWrap.contentWidth);
    expectNear(restored.contentHeight, noWrap.contentHeight);

    await control(page, 'set_scroll', 'monospace', 0, 99999);
    await expect
      .poll(async () => (await state(page, 'monospace', 25, 1)).scrollTop)
      .toBeGreaterThan(0);
    const bottom = await state(page, 'monospace', 25, 1);
    expectNear(bottom.scrollTop, bottom.scrollHeight - bottom.layout.height);
    const lastLine = await page.locator(hostSelector('monospace')).evaluate((host) => {
      const root = host.querySelector('.monaco-editor.readonly-editor');
      const line = Array.from(host.querySelectorAll('.view-line-content')).find((node) =>
        node.textContent.includes('last_line_25'),
      );
      return {
        root: root.getBoundingClientRect().toJSON(),
        line: line.getBoundingClientRect().toJSON(),
      };
    });
    expect(lastLine.line.bottom).toBeLessThanOrEqual(lastLine.root.bottom + 1);
    expectNear(
      lastLine.root.bottom - lastLine.line.bottom,
      horizontalScrollbarHeight,
    );

    await control(page, 'set_scroll', 'monospace', 0, 0);
    await expect
      .poll(async () => (await state(page, 'monospace', 1, 1)).scrollTop)
      .toBe(0);
  } finally {
    reporter.dispose();
  }
});

test('fold-generated ellipsis participates in measured line width', async ({
  page,
}, testInfo) => {
  const reporter = await mountGeometry(page, testInfo);
  try {
    await control(page, 'set_scroll', 'monospace', 0, 320);
    const header = page.locator(`${hostSelector('monospace')} .view-line`, {
      hasText: 'fold_header_',
    });
    await expect(header).toBeVisible();
    const beforeWidth = await header.locator('.view-line-content').evaluate(
      (node) => node.offsetWidth,
    );
    const expanded = page.locator(
      `${hostSelector('monospace')} .cldr.codicon-folding-expanded`,
    );
    await expect(expanded).toHaveCount(1);
    await expanded.hover();
    await expanded.click();
    const generated = header.locator('.inline-folded');
    await expect(generated).toHaveCount(1);
    const afterWidth = await header.locator('.view-line-content').evaluate(
      (node) => node.offsetWidth,
    );
    // U+22EF advances 9.6px in Geometry Mono and the source CSS contributes
    // 0.4em of horizontal margin: 16px total, rounded by offsetWidth.
    expectNear(afterWidth - beforeWidth, 16, 1);
    expectNear((await state(page, 'monospace', 18, 2)).lineWidth, afterWidth);

    const collapsed = page.locator(
      `${hostSelector('monospace')} .cldr.codicon-folding-collapsed`,
    );
    await collapsed.hover();
    await collapsed.click();
    await expect(header.locator('.inline-folded')).toHaveCount(0);
    expectNear(
      await header.locator('.view-line-content').evaluate((node) => node.offsetWidth),
      beforeWidth,
    );
  } finally {
    reporter.dispose();
  }
});

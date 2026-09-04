import { expect, gotoBrowserScenario, test } from '../support/test.js';
import {
  expectMoonBitReportPassed,
  installMoonBitReporter,
} from '../support/moonbit_reporter.js';

const host = '.markdown-comments-host';
const editor = `${host} > .monaco-editor.readonly-editor`;
const zone = `${editor} .moonbit-viewer-markdown-comment`;
const content = '.moonbit-viewer-markdown-comment-content';
const diagram = '.moonbit-viewer-markdown-diagram';
const diagramViewport =
  `${diagram}.moonbit-viewer-markdown-diagram-viewport`;
const diagramContent = '.moonbit-viewer-markdown-diagram-content';
const diagramSvg = `${diagramContent} > svg`;
const diagramControls = '.moonbit-viewer-markdown-diagram-controls';
const diagramResizeHandle =
  '.moonbit-viewer-markdown-diagram-resize-handle';
const imageUrl = 'https://images.example.test/markdown-comment.svg';
const mermaidModulePath = '/mermaid/mermaid.esm.min.mjs';

const fakeMermaidModule = `
  let currentTheme = '';

  export function initialize(options) {
    currentTheme = options.theme;
  }

  export async function render(_id, source) {
    if (source.includes('INVALID')) {
      throw new Error('deterministic invalid Mermaid fixture');
    }
    const theme = currentTheme;
    const responsive = source.includes('RESPONSIVE_OFFSCREEN');
    const tall = source.includes('VALID_SECOND');
    const width = responsive ? 720 : 360;
    const height = responsive
      ? 240
      : tall
        ? 960
        : theme === 'default'
          ? 132
          : 76;
    const label = responsive
      ? 'RESPONSIVE_OFFSCREEN'
      : source.includes('DELAYED_OLD')
        ? 'DELAYED_OLD'
        : source.includes('CURRENT_NEW')
          ? 'CURRENT_NEW'
          : source.includes('VALID_SECOND')
            ? 'VALID_SECOND'
            : 'VALID_ONE';
    return {
      svg:
        '<svg xmlns="http://www.w3.org/2000/svg" width="' +
        width +
        '" height="' +
        height +
        '" viewBox="0 0 ' +
        width +
        ' ' +
        height +
        '">' +
        '<rect width="' +
        width +
        '" height="' +
        height +
        '" fill="' +
        (theme === 'default' ? '#f4f7fb' : '#1f2937') +
        '"/>' +
        '<text x="16" y="36" fill="' +
        (theme === 'default' ? '#172033' : '#f8fafc') +
        '">' +
        label +
        '</text></svg>',
      bindFunctions() {},
    };
  }

  export default { initialize, render };
`;

const fixtureSvg = `
  <svg xmlns="http://www.w3.org/2000/svg" width="180" height="48" viewBox="0 0 180 48">
    <rect width="180" height="48" rx="4" fill="#315f8c"/>
    <text x="12" y="30" fill="white" font-size="16">markdown fixture</text>
  </svg>
`;

async function settle(page) {
  await page.evaluate(
    () =>
      new Promise((resolve) =>
        requestAnimationFrame(() =>
          requestAnimationFrame(() => requestAnimationFrame(resolve)),
        ),
      ),
  );
}

async function mountMarkdownComments(
  page,
  testInfo,
) {
  await page.route(imageUrl, (route) =>
    route.fulfill({
      status: 200,
      contentType: 'image/svg+xml',
      body: fixtureSvg,
    }),
  );
  await page.route(`**${mermaidModulePath}`, (route) =>
    route.fulfill({
      status: 200,
      contentType: 'text/javascript',
      headers: {
        'access-control-allow-origin': '*',
        'cache-control': 'no-store',
      },
      body: fakeMermaidModule,
    }),
  );
  const reporter = await installMoonBitReporter(page);
  await gotoBrowserScenario(page, 'markdown-comments');
  await page.waitForFunction(() => Boolean(globalThis.__markdownCommentsControls));
  const report = await reporter.waitForReport(testInfo, {
    suite: 'markdown_comments',
    timeout: 15_000,
  });
  expectMoonBitReportPassed(report, { suite: 'markdown_comments' });
  expect(report.metrics.initialZones).toBe(3);
  expect(report.metrics.initialDiagrams).toBe(2);
  await expect(page.locator(zone)).toHaveCount(3);
  await settle(page);
  return reporter;
}

async function control(page, name, ...args) {
  return page.evaluate(
    ({ method, values }) =>
      globalThis.__markdownCommentsControls[method](...values),
    { method: name, values: args },
  );
}

async function state(page) {
  return control(page, 'state');
}

async function horizontalViewportGeometry(page) {
  return page.locator(editor).evaluate((root) => {
    const rect = (node) => {
      const value = node.getBoundingClientRect();
      return {
        top: value.top,
        bottom: value.bottom,
        left: value.left,
        right: value.right,
        width: value.width,
        height: value.height,
      };
    };
    const required = (selector, scope = root) => {
      const node = scope.querySelector(selector);
      if (!node) throw new Error(`missing horizontal geometry node: ${selector}`);
      return node;
    };
    const scrollable = required(
      '.monaco-scrollable-element.editor-scrollable',
    );
    const rail = required(':scope > .scrollbar.vertical', scrollable);
    const viewZones = required('.view-zones');
    const outers = Array.from(
      root.querySelectorAll('.moonbit-viewer-markdown-comment'),
    );
    if (outers.length === 0) {
      throw new Error('missing Markdown comment outer nodes');
    }
    const sourceLine = Array.from(
      root.querySelectorAll('.view-lines .view-line'),
    ).find((node) =>
      node.textContent.includes('horizontal_overflow_sentinel'));
    if (!sourceLine) throw new Error('missing horizontal overflow source line');
    const sourceContent =
      sourceLine.querySelector('.view-line-content') ?? sourceLine;
    const viewport = required(
      '.moonbit-viewer-markdown-diagram-viewport',
    );
    const toolbar = required(
      ':scope > .moonbit-viewer-markdown-diagram-controls',
      viewport,
    );
    const transformContent = required(
      ':scope > .moonbit-viewer-markdown-diagram-content',
      viewport,
    );
    return {
      scrollable: rect(scrollable),
      rail: rect(rail),
      viewZones: rect(viewZones),
      outers: outers.map(rect),
      source: rect(sourceContent),
      diagram: rect(viewport),
      toolbar: rect(toolbar),
      diagramTransform: transformContent.style.transform,
    };
  });
}

function expectMarkdownPinnedToVisibleViewport(geometry) {
  expect(geometry.rail.width).toBeGreaterThan(0);
  for (const outer of geometry.outers) {
    expectNear(outer.left, geometry.scrollable.left);
    expectNear(outer.right, geometry.rail.left);
    expectNear(
      outer.width,
      geometry.rail.left - geometry.scrollable.left,
    );
  }
}

async function zoneRanges(page) {
  return page.locator(zone).evaluateAll((nodes) =>
    nodes.map((node) => [
      Number(node.getAttribute('data-start-line')),
      Number(node.getAttribute('data-end-line')),
    ]),
  );
}

async function viewportGeometry(locator) {
  return locator.evaluate((wrapper) => {
    const transformContent = wrapper.querySelector(
      ':scope > .moonbit-viewer-markdown-diagram-content',
    );
    const svg = transformContent.querySelector(':scope > svg');
    const wrapperRect = wrapper.getBoundingClientRect();
    const svgRect = svg.getBoundingClientRect();
    const transform = new DOMMatrixReadOnly(
      window.getComputedStyle(transformContent).transform,
    );
    return {
      heightLimit: Math.min(window.innerHeight * 0.5, 480),
      wrapperHeight: wrapperRect.height,
      wrapperWidth: wrapperRect.width,
      inlineHeight: Number.parseFloat(wrapper.style.height),
      svgHeight: svgRect.height,
      svgWidth: svgRect.width,
      scale: transform.a,
      scaleY: transform.d,
      translateX: transform.e,
      translateY: transform.f,
      transform: transformContent.style.transform,
      fullyVisible:
        svgRect.left >= wrapperRect.left - 1 &&
        svgRect.right <= wrapperRect.right + 1 &&
        svgRect.top >= wrapperRect.top - 1 &&
        svgRect.bottom <= wrapperRect.bottom + 1,
    };
  });
}

function expectNear(actual, expected, tolerance = 1) {
  expect(Math.abs(actual - expected)).toBeLessThanOrEqual(tolerance);
}

test('public Viewer replaces whole-line source with themed Markdown while model and native input stay truthful', async ({
  page,
}, testInfo) => {
  await page.context().grantPermissions(['clipboard-read', 'clipboard-write']);
  const reporter = await mountMarkdownComments(page, testInfo);
  try {
    expect(await zoneRanges(page)).toEqual([
      [1, 3],
      [5, 9],
      [10, 29],
    ]);

    const zones = page.locator(zone);
    await expect(zones.nth(0).locator('h1')).toHaveText('Start comment');
    await expect(zones.nth(1).locator('h2')).toHaveText('Middle comment');
    await expect(zones.nth(1).locator('strong')).toHaveText(
      'same-key initial phrase',
    );
    await expect(zones.nth(1).locator('li')).toHaveCount(2);

    // Source presentation is owned per block and shows the exact model text,
    // including MoonBit comment syntax, without changing a sibling block.
    const firstSourceToggle = zones.nth(0).getByRole('button', {
      name: 'Original source',
    });
    await expect(firstSourceToggle).toHaveAttribute('aria-pressed', 'false');
    await expect(firstSourceToggle).toHaveAttribute(
      'title',
      'Show original source',
    );
    await expect(
      zones
        .nth(0)
        .locator('.moonbit-viewer-markdown-comment-source .monaco-tokenized-source'),
    ).toHaveCount(0);
    await expect(
      zones
        .nth(1)
        .locator('.moonbit-viewer-markdown-comment-source .monaco-tokenized-source'),
    ).toHaveCount(0);
    expect(
      await zones.nth(0).locator(content).evaluate((element) =>
        Number.parseFloat(getComputedStyle(element).paddingRight)),
    ).toBeGreaterThanOrEqual(40);
    await firstSourceToggle.click();
    await expect(zones.nth(0)).toHaveAttribute('data-source-visible', 'true');
    await expect(zones.nth(0).locator('h1')).toBeHidden();
    await expect(
      zones.nth(0).locator('.moonbit-viewer-markdown-comment-source'),
    ).toContainText('/// # Start comment');
    await expect(
      zones.nth(0).locator('.moonbit-viewer-markdown-comment-source'),
    ).toContainText(
      '/// Start prose with [fixture link](https://example.test/docs).',
    );
    await expect(
      zones
        .nth(1)
        .locator('.moonbit-viewer-markdown-comment-source .monaco-tokenized-source'),
    ).toHaveCount(0);
    await expect(zones.nth(1)).toHaveAttribute('data-source-visible', 'false');
    await expect(zones.nth(1).locator('h2')).toBeVisible();
    await expect(firstSourceToggle).toHaveAttribute('aria-pressed', 'true');
    await expect(firstSourceToggle).toHaveAttribute(
      'title',
      'Show rendered documentation',
    );
    await firstSourceToggle.focus();
    await firstSourceToggle.press('Enter');
    await expect(zones.nth(0)).toHaveAttribute('data-source-visible', 'false');
    await expect(zones.nth(0).locator('h1')).toBeVisible();

    const fencedCode = zones
      .nth(2)
      .locator(
        '.moonbit-viewer-markdown-comment-full .monaco-tokenized-source',
      );
    await expect(fencedCode).toContainText(
      'let fenced_value = 42',
    );
    await expect(fencedCode.locator('.mtk3')).not.toHaveCount(0);
    const diagoDiagrams = zones
      .nth(2)
      .locator(`${diagram}[data-diagram-language="diago"]`);
    await expect(diagoDiagrams).toHaveCount(2);
    const diagoDiagram = diagoDiagrams.nth(0);
    const compactDiagram = diagoDiagrams.nth(1);
    for (const renderedDiagram of [diagoDiagram, compactDiagram]) {
      await expect(renderedDiagram).toHaveClass(
        /moonbit-viewer-markdown-diagram-viewport/,
      );
      await expect(
        renderedDiagram.locator(`:scope > ${diagramContent} > svg`),
      ).toHaveCount(1);
      await expect(renderedDiagram.locator(':scope > svg')).toHaveCount(0);
      await expect(
        renderedDiagram.locator(`:scope > ${diagramControls} > button`),
      ).toHaveCount(4);
      await expect(
        renderedDiagram.locator(`:scope > ${diagramResizeHandle}`),
      ).toHaveCount(1);
      await expect(renderedDiagram).toHaveAttribute(
        'aria-label',
        'Interactive Diago diagram',
      );
      await expect(renderedDiagram).toHaveAttribute('tabindex', '0');
    }
    await expect(
      diagoDiagram.locator('[aria-label="Toggle pan mode"]'),
    ).toHaveAttribute('aria-pressed', 'false');
    await expect(
      diagoDiagram.locator('[aria-label="Zoom out"]'),
    ).toHaveCount(1);
    await expect(
      diagoDiagram.locator('[aria-label="Zoom in"]'),
    ).toHaveCount(1);
    await expect(
      diagoDiagram.locator('[aria-label="Fit diagram"]'),
    ).toHaveCount(1);
    const resizeHandle = diagoDiagram.locator(
      '[aria-label="Resize diagram"]',
    );
    await expect(resizeHandle).toHaveAttribute('role', 'separator');
    await expect(resizeHandle).toHaveAttribute('tabindex', '0');
    await expect(resizeHandle).toHaveAttribute(
      'aria-orientation',
      'horizontal',
    );
    const diagramLayout = await diagoDiagram.evaluate((wrapper) => {
      const transformContent = wrapper.querySelector(
        ':scope > .moonbit-viewer-markdown-diagram-content',
      );
      const svg = transformContent.querySelector(':scope > svg');
      const inner = wrapper.closest(
        '.moonbit-viewer-markdown-comment-content',
      );
      const outer = wrapper.closest('.moonbit-viewer-markdown-comment');
      const wrapperRect = wrapper.getBoundingClientRect();
      const svgRect = svg.getBoundingClientRect();
      const innerRect = inner.getBoundingClientRect();
      const outerRect = outer.getBoundingClientRect();
      const viewBox = svg.viewBox.baseVal;
      const transform = new DOMMatrixReadOnly(
        window.getComputedStyle(transformContent).transform,
      );
      return {
        viewportHeight: window.innerHeight,
        wrapperHeight: wrapperRect.height,
        wrapperWidth: wrapperRect.width,
        wrapperClientHeight: wrapper.clientHeight,
        wrapperClientWidth: wrapper.clientWidth,
        wrapperScrollHeight: wrapper.scrollHeight,
        svgHeight: svgRect.height,
        svgWidth: svgRect.width,
        svgAspectRatio: svgRect.width / svgRect.height,
        viewBoxAspectRatio: viewBox.width / viewBox.height,
        innerClientWidth: inner.clientWidth,
        innerHeight: inner.offsetHeight,
        outerHeight: outerRect.height,
        outerStyleHeight: Number.parseFloat(outer.style.height),
        wrapperWithinContent:
          wrapperRect.left >= innerRect.left - 1 &&
          wrapperRect.right <= innerRect.right + 1,
        svgWithinWrapper:
          svgRect.left >= wrapperRect.left - 1 &&
          svgRect.right <= wrapperRect.right + 1 &&
          svgRect.top >= wrapperRect.top - 1 &&
          svgRect.bottom <= wrapperRect.bottom + 1,
        diagramWithinMeasuredHeight: wrapperRect.bottom <= innerRect.bottom + 1,
        overflowX: window.getComputedStyle(wrapper).overflowX,
        overflowY: window.getComputedStyle(wrapper).overflowY,
        position: window.getComputedStyle(wrapper).position,
        boxSizing: window.getComputedStyle(wrapper).boxSizing,
        wrapperMaxWidth: window.getComputedStyle(wrapper).maxWidth,
        svgDisplay: window.getComputedStyle(svg).display,
        svgMaxWidth: window.getComputedStyle(svg).maxWidth,
        transformOrigin:
          window.getComputedStyle(transformContent).transformOrigin,
        scale: transform.a,
        translateY: transform.f,
        preserveAspectRatio: svg.getAttribute('preserveAspectRatio'),
        hasWidth: svg.hasAttribute('width'),
        hasHeight: svg.hasAttribute('height'),
      };
    });
    expect(diagramLayout).toMatchObject({
      wrapperWithinContent: true,
      svgWithinWrapper: true,
      diagramWithinMeasuredHeight: true,
      overflowX: 'hidden',
      overflowY: 'hidden',
      position: 'relative',
      boxSizing: 'border-box',
      wrapperMaxWidth: '100%',
      svgDisplay: 'block',
      svgMaxWidth: '100%',
      transformOrigin: '0px 0px',
      preserveAspectRatio: 'xMinYMin meet',
      hasWidth: false,
      hasHeight: false,
    });
    expectNear(
      diagramLayout.wrapperHeight,
      Math.min(diagramLayout.viewportHeight * 0.5, 480),
    );
    expect(diagramLayout.svgHeight).toBeGreaterThan(0);
    expect(diagramLayout.scale).toBeLessThan(1);
    expectNear(diagramLayout.translateY, 16);
    expectNear(
      diagramLayout.wrapperHeight,
      diagramLayout.wrapperClientHeight,
    );
    expect(diagramLayout.svgHeight).toBeLessThanOrEqual(
      diagramLayout.wrapperClientHeight - 32 + 1,
    );
    expect(
      Math.abs(
        diagramLayout.svgAspectRatio - diagramLayout.viewBoxAspectRatio,
      ),
    ).toBeLessThan(0.001);
    expect(diagramLayout.wrapperWidth).toBeLessThanOrEqual(
      diagramLayout.innerClientWidth + 1,
    );
    expect(diagramLayout.svgWidth).toBeLessThanOrEqual(
      diagramLayout.wrapperClientWidth + 1,
    );
    expect(
      Math.abs(diagramLayout.outerHeight - diagramLayout.innerHeight),
    ).toBeLessThanOrEqual(1);
    expect(
      Math.abs(diagramLayout.outerStyleHeight - diagramLayout.innerHeight),
    ).toBeLessThanOrEqual(1);

    const renderedImage = zones.nth(2).locator('img');
    await expect(renderedImage).toHaveAttribute('src', imageUrl);
    await expect
      .poll(() =>
        renderedImage.evaluate((node) => ({
          complete: node.complete,
          width: node.naturalWidth,
          height: node.naturalHeight,
        })),
      )
      .toEqual({ complete: true, width: 180, height: 48 });

    // Generic ViewZones default to aria-hidden per caller node. The Markdown
    // contribution explicitly exposes its interactive rendered zones while
    // the shared container remains presentation-only.
    const link = zones.nth(0).locator('a');
    await expect(link).toHaveText('fixture link');
    await expect(link).toHaveAttribute('href', 'https://example.test/docs');
    await expect(link).toHaveAttribute('target', '_blank');
    await expect(link).toHaveAttribute('rel', 'noopener noreferrer');
    await expect(link).not.toHaveAttribute('role');
    await expect(link).not.toHaveAttribute('tabindex');
    await expect(zones.nth(0).locator(content)).toHaveCSS(
      'user-select',
      'text',
    );
    await expect(page.locator(`${editor} .view-zones`)).not.toHaveAttribute(
      'aria-hidden',
    );
    await expect(zones.nth(0)).not.toHaveAttribute('aria-hidden');

    await expect
      .poll(() =>
        zones.evaluateAll((nodes) =>
          nodes.every((outer) => {
            const inner = outer.querySelector(
              '.moonbit-viewer-markdown-comment-content',
            );
            const outerHeight = outer.getBoundingClientRect().height;
            const innerHeight = inner.offsetHeight;
            const styleHeight = Number.parseFloat(outer.style.height);
            return (
              innerHeight > 0 &&
              outerHeight > 0 &&
              Math.abs(outerHeight - innerHeight) <= 1 &&
              Math.abs(styleHeight - innerHeight) <= 1
            );
          }),
        ),
      )
      .toBe(true);

    const geometry = await page.locator(editor).evaluate((root) => {
      const rect = (node) => {
        const value = node.getBoundingClientRect();
        return {
          top: value.top,
          bottom: value.bottom,
          left: value.left,
          height: value.height,
        };
      };
      const byRange = (start, end) =>
        root.querySelector(
          `.moonbit-viewer-markdown-comment[data-start-line="${start}"][data-end-line="${end}"]`,
        );
      const lines = Array.from(root.querySelectorAll('.view-lines .view-line'));
      const lineWith = (needle) =>
        lines.find((node) => node.textContent.includes(needle));
      return {
        start: rect(byRange(1, 3)),
        middle: rect(byRange(5, 9)),
        eof: rect(byRange(10, 29)),
        alpha: rect(lineWith('alpha_code_truth')),
        omega: rect(lineWith('omega_code_truth')),
        startHeading: rect(byRange(1, 3).querySelector('h1')),
        eofCode: rect(
          byRange(10, 29).querySelector('.monaco-tokenized-source'),
        ),
        alphaContent: rect(
          lineWith('alpha_code_truth').querySelector('.view-line-content'),
        ),
        omegaContent: rect(
          lineWith('omega_code_truth').querySelector('.view-line-content'),
        ),
        visibleLineCount: lines.length,
        visibleSourceText: lines.map((node) => node.textContent).join('\n'),
      };
    });
    expect(geometry.start.bottom).toBeLessThanOrEqual(geometry.alpha.top + 1);
    expect(geometry.alpha.bottom).toBeLessThanOrEqual(geometry.middle.top + 1);
    expect(geometry.middle.bottom).toBeLessThanOrEqual(geometry.omega.top + 1);
    expect(geometry.omega.bottom).toBeLessThanOrEqual(geometry.eof.top + 1);
    expect(
      Math.abs(geometry.startHeading.left - geometry.alphaContent.left),
    ).toBeLessThanOrEqual(1);
    expect(
      Math.abs(geometry.eofCode.left - geometry.omegaContent.left),
    ).toBeLessThanOrEqual(1);
    expect(geometry.visibleLineCount).toBeGreaterThanOrEqual(3);
    expect(geometry.visibleSourceText).not.toContain('///');
    expect(geometry.visibleSourceText).not.toContain('Start comment');

    const initialState = await state(page);
    expect(initialState.selection).toEqual({
      anchorLine: 1,
      anchorColumn: 1,
      activeLine: 1,
      activeColumn: 1,
    });

    // An interactive viewport has no native diagram scroller. Ordinary wheel
    // input bubbles to the public Viewer scroll surface without changing its
    // transform.
    await diagoDiagram.scrollIntoViewIfNeeded();
    await settle(page);
    const diagramBox = await diagoDiagram.boundingBox();
    expect(diagramBox).not.toBeNull();
    await page.mouse.move(
      diagramBox.x + diagramBox.width / 2,
      Math.max(20, Math.min(660, diagramBox.y + 100)),
    );
    const diagramBeforeWheel = await viewportGeometry(diagoDiagram);
    const editorScrollBefore = (await state(page)).scrollTop;
    await page.mouse.wheel(0, 160);
    await expect
      .poll(async () => (await state(page)).scrollTop)
      .toBeGreaterThan(editorScrollBefore);
    const diagramAfterWheel = await viewportGeometry(diagoDiagram);
    expect(diagramAfterWheel.transform).toBe(diagramBeforeWheel.transform);
    expect(await diagoDiagram.evaluate((wrapper) => wrapper.scrollTop)).toBe(0);
    await control(page, 'set_scroll_top', 0);
    await settle(page);

    await control(page, 'set_model_selection');
    await control(page, 'focus');
    await control(page, 'clear_input_log');
    expect((await state(page)).selection).toEqual({
      anchorLine: 3,
      anchorColumn: 1,
      activeLine: 3,
      activeColumn: 17,
    });
    await page.keyboard.press('ControlOrMeta+C');
    const modelCopy = await control(page, 'copied_payload');
    expect(modelCopy.plain).toBe('alpha_code_truth');
    expect(modelCopy.html).toContain('alpha_code_truth');
    expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(
      'alpha_code_truth',
    );
    expect((await control(page, 'copies')).at(-1)).toMatchObject({
      defaultPrevented: true,
      nativeSelection: '',
    });

    const nativeSelection = await page.evaluate(() => {
      const controls = globalThis.__markdownCommentsControls;
      controls.set_model_selection();
      controls.focus();
      controls.clear_input_log();
      const target = document.querySelector(
        '.moonbit-viewer-markdown-comment strong',
      );
      const range = document.createRange();
      range.selectNodeContents(target);
      const selection = document.getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
      return selection.toString();
    });
    expect(nativeSelection).toBe('same-key initial phrase');
    await page.keyboard.press('ControlOrMeta+C');
    expect(await control(page, 'copies')).toEqual([
      expect.objectContaining({
        defaultPrevented: false,
        nativeSelection: 'same-key initial phrase',
      }),
    ]);
    expect((await control(page, 'copied_payload')).plain).toBe('');
    expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(
      'same-key initial phrase',
    );

    await page.evaluate(() => document.getSelection()?.removeAllRanges());
    const selectionBeforeLink = (await state(page)).selection;
    await link.focus();
    await page.keyboard.press('ArrowLeft');
    await settle(page);
    expect((await state(page)).selection).toEqual(selectionBeforeLink);
    const keyLog = await control(page, 'keys');
    expect(keyLog.slice(-1)).toEqual([
      expect.objectContaining({
        key: 'ArrowLeft',
        defaultPrevented: false,
        targetRole: '',
      }),
    ]);
  } finally {
    reporter.dispose();
  }
});

test('pins Markdown to the visible viewport while long source keeps its horizontal scroll plane', async ({
  page,
}, testInfo) => {
  const reporter = await mountMarkdownComments(page, testInfo);
  try {
    const zeroState = await state(page);
    expect(zeroState.softWrap).toBe(false);
    expect(zeroState.scrollLeft).toBe(0);

    const zero = await horizontalViewportGeometry(page);
    expectMarkdownPinnedToVisibleViewport(zero);
    expect(zeroState.scrollWidth).toBeGreaterThan(zero.scrollable.width + 100);
    expect(zeroState.contentWidth).toBeGreaterThan(
      zero.scrollable.width + 100,
    );
    expect(zero.viewZones.width).toBeGreaterThan(
      zero.scrollable.width + 100,
    );

    const maximumRequest = Math.floor(zeroState.scrollWidth);
    const middleRequest = Math.max(
      1,
      Math.floor((zeroState.scrollWidth - zero.scrollable.width) / 2),
    );
    const samples = [{ state: zeroState, geometry: zero }];
    for (const requested of [middleRequest, maximumRequest]) {
      await control(page, 'set_scroll_left', requested);
      await expect
        .poll(async () => (await state(page)).scrollLeft)
        .toBeGreaterThan(samples.at(-1).state.scrollLeft);
      await settle(page);
      samples.push({
        state: await state(page),
        geometry: await horizontalViewportGeometry(page),
      });
    }

    for (const sample of samples) {
      expectMarkdownPinnedToVisibleViewport(sample.geometry);
      expect(sample.geometry.viewZones.width).toBeGreaterThan(
        sample.geometry.scrollable.width + 100,
      );
      expectNear(
        sample.geometry.source.left,
        zero.source.left - sample.state.scrollLeft,
      );
      expectNear(sample.geometry.diagram.left, zero.diagram.left);
      expectNear(sample.geometry.diagram.right, zero.diagram.right);
      expectNear(sample.geometry.toolbar.right, zero.toolbar.right);
      expect(sample.geometry.diagramTransform).toBe(zero.diagramTransform);
      sample.geometry.outers.forEach((outer, index) => {
        expectNear(outer.height, zero.outers[index].height);
      });
    }

    // Widen from the maximum horizontal position so the new maximum is
    // smaller but remains non-zero. This exercises real scrollLeft clamping,
    // not merely a resize that increases the available scroll range.
    const maximumSample = samples.at(-1);
    await control(page, 'resize', 900);
    await expect
      .poll(async () => (await state(page)).scrollLeft)
      .toBeGreaterThan(0);
    await expect
      .poll(async () => (await state(page)).scrollLeft)
      .toBeLessThan(maximumSample.state.scrollLeft);
    await settle(page);
    const resizedState = await state(page);
    const resized = await horizontalViewportGeometry(page);
    expect(resizedState.scrollLeft).toBeLessThanOrEqual(
      Math.max(0, resizedState.scrollWidth - resized.scrollable.width) + 1,
    );
    expectMarkdownPinnedToVisibleViewport(resized);
    expectNear(
      resized.source.left - resized.scrollable.left + resizedState.scrollLeft,
      zero.source.left - zero.scrollable.left,
    );
    expectNear(
      resized.diagram.right - resized.toolbar.right,
      zero.diagram.right - zero.toolbar.right,
    );
    expect(resized.diagram.right).toBeLessThanOrEqual(resized.rail.left + 1);
    expect(
      resized.outers.some(
        (outer, index) =>
          Math.abs(outer.height - maximumSample.geometry.outers[index].height)
          > 1,
      ),
    ).toBe(true);

    // Soft wrap removes the horizontal range and clamps scrollLeft. Toggling
    // it back restores overflow without changing the Markdown viewport
    // contract, after which horizontal scrolling can resume.
    await control(page, 'set_soft_wrap', true);
    await expect.poll(async () => (await state(page)).softWrap).toBe(true);
    await expect
      .poll(async () => (await state(page)).scrollLeft)
      .toBeLessThan(resizedState.scrollLeft);
    await settle(page);
    const wrappedState = await state(page);
    const wrapped = await horizontalViewportGeometry(page);
    expect(wrappedState.scrollLeft).toBeLessThanOrEqual(
      Math.max(0, wrappedState.scrollWidth - wrapped.scrollable.width) + 1,
    );
    expectMarkdownPinnedToVisibleViewport(wrapped);

    await control(page, 'set_soft_wrap', false);
    await expect.poll(async () => (await state(page)).softWrap).toBe(false);
    await expect
      .poll(async () => (await state(page)).scrollWidth)
      .toBeGreaterThan(resized.scrollable.width + 100);
    await control(page, 'set_scroll_left', middleRequest);
    await expect
      .poll(async () => (await state(page)).scrollLeft)
      .toBeGreaterThan(0);
    await settle(page);
    expectMarkdownPinnedToVisibleViewport(
      await horizontalViewportGeometry(page),
    );
  } finally {
    reporter.dispose();
  }
});

test('interactive Diago controls pan zoom fit resize and keep sibling state independent', async ({
  page,
}, testInfo) => {
  const reporter = await mountMarkdownComments(page, testInfo);
  try {
    const viewports = page.locator(`${zone} ${diagramViewport}`);
    await expect(viewports).toHaveCount(2);
    const large = viewports.nth(0);
    const compact = viewports.nth(1);

    // Before either diagram has been touched, a host resize recomputes the
    // bounded initial fit. Both controllers observe the same public Viewer
    // layout but own independent transforms.
    const compactWide = await viewportGeometry(compact);
    await control(page, 'resize', 420);
    await expect
      .poll(async () => (await viewportGeometry(compact)).wrapperWidth)
      .toBeLessThan(compactWide.wrapperWidth - 20);
    const compactNarrow = await viewportGeometry(compact);
    expect(compactNarrow.scale).toBeGreaterThan(0);
    expect(compactNarrow.scale).toBeLessThanOrEqual(1);
    expectNear(compactNarrow.scaleY, compactNarrow.scale, 0.001);
    expect(compactNarrow.wrapperHeight).toBeLessThanOrEqual(
      compactNarrow.heightLimit + 1,
    );
    expect(compactNarrow.fullyVisible).toBe(true);
    expect(
      Math.abs(compactNarrow.scale - compactWide.scale),
    ).toBeGreaterThan(0.001);

    await large.scrollIntoViewIfNeeded();
    await settle(page);
    await control(page, 'set_model_selection');
    const selectionBeforeInput = (await state(page)).selection;
    const compactBeforeLargeInput = await viewportGeometry(compact);
    const initial = await viewportGeometry(large);
    expect(initial.scale).toBeGreaterThan(0);
    expect(initial.scale).toBeLessThan(1);
    expectNear(initial.wrapperHeight, initial.heightLimit);
    expect(initial.fullyVisible).toBe(true);

    const pan = large.locator('[aria-label="Toggle pan mode"]');
    const zoomOut = large.locator('[aria-label="Zoom out"]');
    const zoomIn = large.locator('[aria-label="Zoom in"]');
    const fit = large.locator('[aria-label="Fit diagram"]');
    await expect(
      large.getByRole('toolbar', { name: 'D2 diagram controls' }),
    ).toBeVisible();
    await zoomIn.focus();
    const windowWidth = await page.evaluate(() => window.innerWidth);
    await page.mouse.move(windowWidth - 2, 20);
    await expect(large.locator(`:scope > ${diagramControls}`)).toHaveCSS(
      'opacity',
      '1',
    );
    await pan.click();
    await expect(pan).toHaveAttribute('aria-pressed', 'true');
    const panBox = await large.boundingBox();
    expect(panBox).not.toBeNull();
    const panX = panBox.x + panBox.width * 0.35;
    const panY = Math.max(30, Math.min(620, panBox.y + 160));
    await page.mouse.move(panX, panY);
    await page.mouse.down();
    await page.mouse.move(panX + 36, panY + 24, { steps: 3 });
    await page.mouse.up();
    const plainPanned = await viewportGeometry(large);
    expectNear(plainPanned.translateX - initial.translateX, 36, 2);
    expectNear(plainPanned.translateY - initial.translateY, 24, 2);
    await pan.click();
    await expect(pan).toHaveAttribute('aria-pressed', 'false');

    // Alt drag pans while the toggle is off. Its >3px single-move threshold is
    // covered exactly by the reference test; this direct proof uses a clearly
    // visible gesture.
    const altPanBox = await large.boundingBox();
    const altPanX = altPanBox.x + altPanBox.width * 0.35;
    const altPanY = Math.max(30, Math.min(620, altPanBox.y + 190));
    await page.keyboard.down('Alt');
    await page.mouse.move(altPanX, altPanY);
    await page.mouse.down();
    await page.mouse.move(altPanX + 28, altPanY - 20, { steps: 2 });
    await page.mouse.up();
    await page.keyboard.up('Alt');
    const modifierPanned = await viewportGeometry(large);
    expectNear(modifierPanned.translateX - plainPanned.translateX, 28, 2);
    expectNear(modifierPanned.translateY - plainPanned.translateY, -20, 2);

    await zoomOut.click();
    expectNear((await viewportGeometry(large)).scale, initial.scale, 0.001);
    await zoomIn.click();
    expectNear(
      (await viewportGeometry(large)).scale,
      initial.scale * 1.25,
      0.001,
    );
    await fit.click();
    const fitted = await viewportGeometry(large);
    expect(fitted.scale).toBeGreaterThan(0);
    expect(fitted.scale).toBeLessThan(1);
    const fittedRect = await large.evaluate((wrapper) => {
      const svg = wrapper.querySelector(
        ':scope > .moonbit-viewer-markdown-diagram-content > svg',
      );
      const viewportRect = wrapper.getBoundingClientRect();
      const svgRect = svg.getBoundingClientRect();
      return {
        left: svgRect.left - viewportRect.left,
        right: viewportRect.right - svgRect.right,
        top: svgRect.top - viewportRect.top,
        bottom: viewportRect.bottom - svgRect.bottom,
      };
    });
    expect(fittedRect.left).toBeGreaterThanOrEqual(15);
    expect(fittedRect.right).toBeGreaterThanOrEqual(15);
    expect(fittedRect.top).toBeGreaterThanOrEqual(15);
    expect(fittedRect.bottom).toBeGreaterThanOrEqual(15);

    await zoomIn.click();
    expectNear((await viewportGeometry(large)).scale, fitted.scale * 1.25, 0.002);

    const clickBox = await large.boundingBox();
    const clickPosition = {
      x: clickBox.width * 0.3,
      y: Math.min(120, clickBox.height * 0.3),
    };
    const beforeAltClick = await viewportGeometry(large);
    await large.click({ position: clickPosition, modifiers: ['Alt'] });
    const afterAltClick = await viewportGeometry(large);
    expect(afterAltClick.scale).toBeGreaterThan(beforeAltClick.scale);
    await large.click({
      position: clickPosition,
      modifiers: ['Alt', 'Shift'],
    });
    expect((await viewportGeometry(large)).scale).toBeLessThan(
      afterAltClick.scale,
    );

    const compactAfterLargeInput = await viewportGeometry(compact);
    expect(compactAfterLargeInput.transform).toBe(
      compactBeforeLargeInput.transform,
    );

    const handle = large.locator(diagramResizeHandle);
    await handle.scrollIntoViewIfNeeded();
    await handle.evaluate((element) =>
      element.scrollIntoView({ block: 'center', inline: 'nearest' }),
    );
    await settle(page);
    const heightBeforePointer = (await viewportGeometry(large)).wrapperHeight;
    const zoneHeightBeforePointer = await large.evaluate(
      (wrapper) =>
        wrapper.closest('.moonbit-viewer-markdown-comment')
          .getBoundingClientRect().height,
    );
    const handleBox = await handle.boundingBox();
    expect(handleBox).not.toBeNull();
    await page.mouse.move(
      handleBox.x + handleBox.width / 2,
      handleBox.y + handleBox.height / 2,
    );
    await page.mouse.down();
    await page.mouse.move(
      handleBox.x + handleBox.width / 2,
      handleBox.y + handleBox.height / 2 + 60,
      { steps: 4 },
    );
    await page.mouse.up();
    await expect
      .poll(async () => (await viewportGeometry(large)).wrapperHeight)
      .toBeGreaterThan(heightBeforePointer + 55);
    await expect
      .poll(() =>
        large.evaluate(
          (wrapper) =>
            wrapper.closest('.moonbit-viewer-markdown-comment')
              .getBoundingClientRect().height,
        ),
      )
      .toBeGreaterThan(zoneHeightBeforePointer + 55);

    await handle.focus();
    const heightBeforeKeyboard = (await viewportGeometry(large)).wrapperHeight;
    await page.keyboard.press('ArrowDown');
    await expect
      .poll(async () => (await viewportGeometry(large)).wrapperHeight)
      .toBeCloseTo(heightBeforeKeyboard + 10, 0);
    await page.keyboard.press('Shift+ArrowDown');
    await expect
      .poll(async () => (await viewportGeometry(large)).wrapperHeight)
      .toBeCloseTo(heightBeforeKeyboard + 60, 0);
    await page.keyboard.press('ArrowUp');
    await expect
      .poll(async () => (await viewportGeometry(large)).wrapperHeight)
      .toBeCloseTo(heightBeforeKeyboard + 50, 0);

    // A custom height wins across a later host resize, while prior fit/pan
    // keeps scale and preserves a visible origin instead of resetting.
    const beforeResponsiveResize = await viewportGeometry(large);
    await control(page, 'resize', 620);
    await expect
      .poll(async () => (await viewportGeometry(large)).wrapperWidth)
      .toBeGreaterThan(beforeResponsiveResize.wrapperWidth + 100);
    const afterResponsiveResize = await viewportGeometry(large);
    expectNear(
      afterResponsiveResize.wrapperHeight,
      beforeResponsiveResize.wrapperHeight,
      1,
    );
    expectNear(afterResponsiveResize.scale, beforeResponsiveResize.scale, 0.002);
    expect(afterResponsiveResize.transform).not.toBe(
      beforeResponsiveResize.transform,
    );

    // A pure horizontal source scroll must not enter the diagram resize or
    // transform paths. In particular, its caller-selected height is stable.
    // Bring the long source sentinel into the vertically rendered range so
    // it contributes the no-wrap horizontal extent used by this gesture.
    await control(page, 'set_scroll_top', 0);
    await settle(page);
    const customHeightBeforeHorizontal = await viewportGeometry(large);
    await control(page, 'set_scroll_left', 200);
    await expect
      .poll(async () => (await state(page)).scrollLeft)
      .toBeGreaterThan(0);
    await settle(page);
    const customHeightAfterHorizontal = await viewportGeometry(large);
    expectNear(
      customHeightAfterHorizontal.wrapperHeight,
      customHeightBeforeHorizontal.wrapperHeight,
    );
    expectNear(
      customHeightAfterHorizontal.inlineHeight,
      customHeightBeforeHorizontal.inlineHeight,
    );
    expect(customHeightAfterHorizontal.transform).toBe(
      customHeightBeforeHorizontal.transform,
    );
    expect((await state(page)).selection).toEqual(selectionBeforeInput);
  } finally {
    reporter.dispose();
  }
});

test('renders exact Mermaid fences and rerenders them in place for Viewer themes', async ({
  page,
}, testInfo) => {
  const reporter = await mountMarkdownComments(page, testInfo);
  try {
    await control(page, 'mermaid_source');

    const mermaidDiagram = `${zone} ${diagram}[data-diagram-language="mermaid"]`;
    const mermaidDiagrams = page.locator(mermaidDiagram);
    const renderedSvgs = page.locator(`${mermaidDiagram} > ${diagramSvg}`);
    await expect(mermaidDiagrams).toHaveCount(3);
    await expect(renderedSvgs).toHaveCount(2);
    const renderedMermaid = page.locator(
      `${mermaidDiagram}[data-mermaid-state="rendered"]`,
    );
    await expect(renderedMermaid).toHaveCount(2);
    for (const rendered of [renderedMermaid.first(), renderedMermaid.last()]) {
      await expect(rendered).toHaveAttribute(
        'aria-label',
        'Interactive Mermaid diagram',
      );
    }
    await expect(
      renderedMermaid.locator(`:scope > ${diagramControls} > button`),
    ).toHaveCount(8);
    const interactiveMermaid = renderedMermaid.first();
    const initialInteractiveGeometry = await viewportGeometry(
      interactiveMermaid,
    );
    await interactiveMermaid.hover();
    await interactiveMermaid.getByRole('button', { name: 'Zoom in' }).click();
    expect((await viewportGeometry(interactiveMermaid)).scale).toBeGreaterThan(
      initialInteractiveGeometry.scale,
    );
    const panButton = interactiveMermaid.getByRole('button', {
      name: 'Toggle pan mode',
    });
    await panButton.click();
    await expect(panButton).toHaveAttribute('aria-pressed', 'true');
    const beforePan = await viewportGeometry(interactiveMermaid);
    const interactiveBox = await interactiveMermaid.boundingBox();
    expect(interactiveBox).not.toBeNull();
    await page.mouse.move(
      interactiveBox.x + interactiveBox.width / 2,
      interactiveBox.y + interactiveBox.height / 2,
    );
    await page.mouse.down();
    await page.mouse.move(
      interactiveBox.x + interactiveBox.width / 2 + 24,
      interactiveBox.y + interactiveBox.height / 2,
      { steps: 3 },
    );
    await page.mouse.up();
    expect((await viewportGeometry(interactiveMermaid)).translateX).toBeGreaterThan(
      beforePan.translateX,
    );

    const tallMermaid = renderedSvgs.last();
    const tallMermaidLayout = await tallMermaid.evaluate((svg) => {
      const wrapper = svg.closest('.moonbit-viewer-markdown-diagram');
      const wrapperRect = wrapper.getBoundingClientRect();
      const svgRect = svg.getBoundingClientRect();
      const viewBox = svg.viewBox.baseVal;
      return {
        heightLimit: Math.min(window.innerHeight * 0.5, 480),
        wrapperHeight: wrapperRect.height,
        svgHeight: svgRect.height,
        svgAspectRatio: svgRect.width / svgRect.height,
        viewBoxAspectRatio: viewBox.width / viewBox.height,
        fullyVisible:
          svgRect.left >= wrapperRect.left - 1 &&
          svgRect.right <= wrapperRect.right + 1 &&
          svgRect.top >= wrapperRect.top - 1 &&
          svgRect.bottom <= wrapperRect.bottom + 1,
        overflowY: window.getComputedStyle(wrapper).overflowY,
      };
    });
    expectNear(
      tallMermaidLayout.svgHeight,
      tallMermaidLayout.heightLimit - 32,
    );
    expectNear(
      tallMermaidLayout.wrapperHeight,
      tallMermaidLayout.heightLimit,
    );
    expect(tallMermaidLayout.fullyVisible).toBe(true);
    expect(tallMermaidLayout.overflowY).toBe('hidden');
    expect(
      Math.abs(
        tallMermaidLayout.svgAspectRatio -
          tallMermaidLayout.viewBoxAspectRatio,
      ),
    ).toBeLessThan(0.001);

    const retainedZone = await page.locator(zone).elementHandle();
    const retainedWrappers = await mermaidDiagrams.elementHandles();
    const darkHeight = await page
      .locator(zone)
      .evaluate((node) => node.getBoundingClientRect().height);
    expect(retainedZone).not.toBeNull();
    expect(retainedWrappers).toHaveLength(3);

    await control(page, 'theme_light');
    await expect(page.locator(editor)).toHaveAttribute('data-theme', 'light');
    await expect
      .poll(() =>
        page.locator(zone).evaluate((node) => node.getBoundingClientRect().height),
      )
      .toBeGreaterThan(darkHeight);
    await expect
      .poll(() =>
        page.locator(zone).evaluate((node) => {
          const inner = node.querySelector(
            '.moonbit-viewer-markdown-comment-content',
          );
          const outer = node.getBoundingClientRect().height;
          const style = Number.parseFloat(node.style.height);
          const innerHeight = inner.offsetHeight;
          return (
            Math.abs(outer - innerHeight) <= 1 &&
            Math.abs(style - innerHeight) <= 1
          );
        }),
      )
      .toBe(true);
    const lightGeometry = await page.locator(zone).evaluate((node) => {
      const inner = node.querySelector(
        '.moonbit-viewer-markdown-comment-content',
      );
      return {
        outer: node.getBoundingClientRect().height,
        style: Number.parseFloat(node.style.height),
        inner: inner.offsetHeight,
      };
    });
    expect(Math.abs(lightGeometry.outer - lightGeometry.inner)).toBeLessThanOrEqual(
      1,
    );
    expect(Math.abs(lightGeometry.style - lightGeometry.inner)).toBeLessThanOrEqual(
      1,
    );
    expect(lightGeometry.outer).toBeGreaterThan(darkHeight);
    expect(
      await retainedZone.evaluate(
        (node) =>
          node ===
          document.querySelector(
            '.markdown-comments-host .moonbit-viewer-markdown-comment',
          ),
      ),
    ).toBe(true);
    for (let index = 0; index < retainedWrappers.length; index += 1) {
      expect(
        await retainedWrappers[index].evaluate(
          (node, selectorIndex) =>
            node ===
            document.querySelectorAll(
              '.markdown-comments-host .moonbit-viewer-markdown-diagram[data-diagram-language="mermaid"]',
            )[selectorIndex],
          index,
        ),
      ).toBe(true);
    }

    await control(page, 'theme_dark');
    await expect(page.locator(editor)).toHaveAttribute('data-theme', 'dark');
    await expect(
      renderedMermaid.locator(`:scope > ${diagramControls} > button`),
    ).toHaveCount(8);
    await expect
      .poll(() =>
        page
          .locator(zone)
          .evaluate((node) => node.getBoundingClientRect().height),
      )
      .toBeLessThan(lightGeometry.outer);

  } finally {
    reporter.dispose();
  }
});

test('keeps an offscreen Mermaid SVG and its ViewZone height synchronized across resize and reveal', async ({
  page,
}, testInfo) => {
  const reporter = await mountMarkdownComments(page, testInfo);
  try {
    await control(page, 'mermaid_offscreen_source');
    await expect(page.locator(zone)).toHaveCount(1);
    expect(await zoneRanges(page)).toEqual([[81, 88]]);
    const mermaidWrapper = page.locator(
      `${zone} ${diagram}[data-diagram-language="mermaid"]`,
    );
    const svg = mermaidWrapper.locator(`:scope > ${diagramSvg}`);
    await expect(svg).toHaveCount(1);
    await expect(page.locator(zone)).not.toBeVisible();

    const retainedZone = await page.locator(zone).elementHandle();
    const retainedWrapper = await mermaidWrapper.elementHandle();
    const retainedSvg = await svg.elementHandle();
    expect(retainedZone).not.toBeNull();
    expect(retainedWrapper).not.toBeNull();
    expect(retainedSvg).not.toBeNull();

    const svgContract = await svg.evaluate((node) => ({
      width: node.getAttribute('width'),
      height: node.getAttribute('height'),
      viewBox: node.getAttribute('viewBox'),
    }));
    expect(svgContract).toEqual({
      width: '720',
      height: '240',
      viewBox: '0 0 720 240',
    });
    const wideScrollHeight = (await state(page)).scrollHeight;

    await control(page, 'resize', 240);
    await expect(page.locator(zone)).not.toBeVisible();
    await expect
      .poll(async () =>
        Math.abs((await state(page)).scrollHeight - wideScrollHeight),
      )
      .toBeGreaterThan(1);
    const narrowScrollHeight = (await state(page)).scrollHeight;
    expect(
      await retainedZone.evaluate(
        (node) =>
          node ===
          document.querySelector(
            '.markdown-comments-host .moonbit-viewer-markdown-comment',
          ),
      ),
    ).toBe(true);
    expect(
      await retainedWrapper.evaluate(
        (node) =>
          node ===
          document.querySelector(
            '.markdown-comments-host .moonbit-viewer-markdown-diagram[data-diagram-language="mermaid"]',
          ),
      ),
    ).toBe(true);
    expect(
      await retainedSvg.evaluate(
        (node) =>
          node ===
          document.querySelector(
            '.markdown-comments-host .moonbit-viewer-markdown-diagram[data-diagram-language="mermaid"] > .moonbit-viewer-markdown-diagram-content > svg',
          ),
      ),
    ).toBe(true);

    await control(page, 'scroll_to_bottom');
    await settle(page);
    await expect(page.locator(zone)).toBeVisible();
    await expect
      .poll(async () =>
        Math.abs((await state(page)).scrollHeight - narrowScrollHeight),
      )
      .toBeLessThanOrEqual(1);
    const revealed = await page.locator(zone).evaluate((outer) => {
      const inner = outer.querySelector(
        '.moonbit-viewer-markdown-comment-content',
      );
      const rendered = outer.querySelector(
        '.moonbit-viewer-markdown-diagram[data-diagram-language="mermaid"] > .moonbit-viewer-markdown-diagram-content > svg',
      );
      const svgRect = rendered.getBoundingClientRect();
      return {
        outer: outer.getBoundingClientRect().height,
        style: Number.parseFloat(outer.style.height),
        inner: inner.offsetHeight,
        svgWidth: svgRect.width,
        svgHeight: svgRect.height,
        svgAspectRatio: svgRect.width / svgRect.height,
      };
    });
    expect(revealed.svgWidth).toBeGreaterThan(0);
    expect(revealed.svgHeight).toBeGreaterThan(0);
    expect(revealed.svgWidth).toBeLessThan(720);
    expect(Math.abs(revealed.svgAspectRatio - 3)).toBeLessThan(0.001);
    expect(Math.abs(revealed.outer - revealed.inner)).toBeLessThanOrEqual(1);
    expect(Math.abs(revealed.style - revealed.inner)).toBeLessThanOrEqual(1);
  } finally {
    reporter.dispose();
  }
});

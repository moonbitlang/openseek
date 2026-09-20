import { expect, gotoBrowserScenario, test } from '../support/test.js';

const diffLifecycleRoot =
  '.diff-lifecycle-host > .moonbit-diff-editor';

async function openDiffLifecycle(page) {
  await gotoBrowserScenario(page, 'diff-editor-lifecycle');
  await page.waitForFunction(() =>
    Boolean(globalThis.__diffEditorLifecycleControls),
  );
  const root = page.locator(diffLifecycleRoot);
  await expect(root).toHaveCount(1);
  return root;
}

async function waitForAnimationFrames(page, count = 2) {
  await page.evaluate((frameCount) => new Promise((resolve) => {
    let remaining = frameCount;
    const advance = () => {
      remaining -= 1;
      if (remaining <= 0) {
        resolve();
      } else {
        requestAnimationFrame(advance);
      }
    };
    requestAnimationFrame(advance);
  }), count);
}

async function waitForDiffBands(root) {
  const modifiedOverview = root.locator(
    '[data-diff-overview-side="modified"]',
  );
  await expect
    .poll(async () => Number(await modifiedOverview.getAttribute(
      'data-overview-ruler-band-count',
    )))
    .toBeGreaterThan(0);
}

async function setDiffLifecycleFixture(page, fixture) {
  await page.evaluate((value) =>
    globalThis.__diffEditorLifecycleControls.set_fixture(value), fixture,
  );
}

async function setDiffLifecycleOptions(
  page,
  { layout, renderIndicators, fontSize = 12 },
) {
  await page.evaluate(({ nextLayout, nextRenderIndicators, nextFontSize }) =>
    globalThis.__diffEditorLifecycleControls.set_options(
      nextLayout,
      nextRenderIndicators,
      nextFontSize,
    ), {
    nextLayout: layout,
    nextRenderIndicators: renderIndicators,
    nextFontSize: fontSize,
  });
}

async function disposeDiffLifecycle(page) {
  await page.evaluate(() => {
    globalThis.__diffEditorLifecycleControls.dispose();
    globalThis.__diffEditorLifecycleControls.dispose_models();
  });
}

// Behavior port: VS Code 07c20d96cf3f2cbc8142ac7079ba9048cf7f6134,
// multiDiffEditor/diffEditorItemTemplate.ts, setScrollLeft. The outer host
// drives the pane with the larger overflow; the narrower pane clamps locally.
// Chromium is required because the pane scroll echoes fire during rendering.
for (const wider of ['original', 'modified', 'equal']) {
  test(`shared horizontal scroll preserves each pane's limit (${wider})`, async ({ page }) => {
    const root = await openDiffLifecycle(page);
    await setDiffLifecycleFixture(page, `horizontal-${wider}`);
    const readPanes = () => root.evaluate((node) =>
      [...node.querySelectorAll('.moonbit-diff-editor-pane')].map((pane) => {
        const lines = pane.querySelector('.view-lines');
        const viewport = pane.querySelector('.monaco-scrollable-element');
        const content = pane.querySelector('.lines-content');
        return {
          maxLeft: lines.clientWidth - viewport.clientWidth,
          left: Math.max(0, -Number.parseFloat(content.style.left)),
        };
      }),
    );
    await expect.poll(async () => Math.min(...(await readPanes()).map(p => p.maxLeft)))
      .toBeGreaterThan(100);
    const initial = await readPanes();
    const [originalMax, modifiedMax] = initial.map(p => p.maxLeft);
    if (wider === 'equal') {
      expect(originalMax).toBe(modifiedMax);
    } else {
      expect(wider === 'original' ? originalMax - modifiedMax : modifiedMax - originalMax)
        .toBeGreaterThan(100);
    }
    const sharedMax = Math.min(originalMax, modifiedMax);
    // Cross the short pane's limit, repeat the outer write (e.g. vertical
    // host scrolling), overshoot both limits, then reverse into shared range.
    for (const requested of [sharedMax + 80, sharedMax + 80, 100_000, 80, 0]) {
      await page.evaluate(left =>
        globalThis.__diffEditorLifecycleControls.set_scroll_left(left), requested,
      );
      await waitForAnimationFrames(page, 6);
      const panes = await readPanes();
      for (const [index, pane] of panes.entries()) {
        expect(pane.left, `pane ${index}, request ${requested}`)
          .toBe(Math.min(requested, initial[index].maxLeft));
      }
    }
    await disposeDiffLifecycle(page);
  });
}

async function modifiedScrollTop(root) {
  return root.evaluate((node) => {
    const content = node.querySelector(
      '.moonbit-diff-editor-modified .lines-content',
    );
    if (!content) {
      throw new Error('missing modified diff lines content');
    }
    return Math.max(
      0,
      -(Number.parseFloat(getComputedStyle(content).top) || 0),
    );
  });
}

test('reveals raw mappings[0] when the first hunk starts on the cursor line', async ({ page }) => {
  const root = await openDiffLifecycle(page);
  const modified = root.locator('.moonbit-diff-editor-modified');
  const scrollable = modified.locator(
    '.monaco-scrollable-element.editor-scrollable',
  );
  await setDiffLifecycleFixture(page, 'first-line');
  await waitForDiffBands(root);

  // Keep the model cursor at its initial line 1 while moving the viewport.
  // Cursor-relative `reveal_next_change` would skip that first hunk and land
  // on line 100; the VS Code API must always reveal raw mappings[0].
  await scrollable.hover();
  await page.mouse.wheel(0, 1400);
  await expect
    .poll(() => modifiedScrollTop(root))
    .toBeGreaterThan(500);
  await page.evaluate(() =>
    globalThis.__diffEditorLifecycleControls.reveal_first_diff(),
  );

  await expect(
    modified.locator('.line-numbers.active-line-number'),
  ).toHaveText('1');
  await expect(
    modified.locator('.view-line').filter({
      hasText: 'new first hunk at line 1',
    }),
  ).toBeVisible();
  await expect
    .poll(() => modifiedScrollTop(root))
    .toBeLessThan(100);

  await disposeDiffLifecycle(page);
});

test('reveals the final raw mapping for backward multi-diff navigation', async ({ page }) => {
  const root = await openDiffLifecycle(page);
  const modified = root.locator('.moonbit-diff-editor-modified');
  await setDiffLifecycleFixture(page, 'first-line');
  await waitForDiffBands(root);

  await page.evaluate(() =>
    globalThis.__diffEditorLifecycleControls.reveal_last_diff(),
  );

  await expect(
    modified.locator('.line-numbers.active-line-number'),
  ).toHaveText('100');
  await expect(
    modified.locator('.view-line').filter({
      hasText: 'new second hunk at line 100',
    }),
  ).toBeVisible();

  await disposeDiffLifecycle(page);
});

test('defers a one-shot first-diff reveal through hidden layout', async ({ page }) => {
  const root = await openDiffLifecycle(page);
  const host = page.locator('.diff-lifecycle-host');
  const modified = root.locator('.moonbit-diff-editor-modified');
  const scrollable = modified.locator(
    '.monaco-scrollable-element.editor-scrollable',
  );

  await setDiffLifecycleFixture(page, 'late');
  await waitForDiffBands(root);

  // Request the VS Code-style reveal while no measurable two-pane layout is
  // available. Showing the host later must consume the request for this exact
  // model pair rather than dropping it.
  await host.evaluate((node) => {
    node.style.display = 'none';
  });
  await page.evaluate(() =>
    globalThis.__diffEditorLifecycleControls.reveal_first_diff(),
  );
  await host.evaluate((node) => {
    node.style.display = 'block';
  });

  await expect(
    modified.locator('.line-numbers.active-line-number'),
  ).toHaveText('121');
  await expect(
    modified.locator('.view-line').filter({ hasText: 'new first hunk' }),
  ).toBeVisible();
  const revealedScrollTop = await modifiedScrollTop(root);
  expect(revealedScrollTop).toBeGreaterThan(0);

  // The request is consumed once. A same-pair provider recomputation must not
  // pull a reviewer who has scrolled onward back to the first hunk.
  await scrollable.hover();
  await page.mouse.wheel(0, 1800);
  await expect
    .poll(() => modifiedScrollTop(root))
    .toBeGreaterThan(revealedScrollTop + 500);
  const reviewerScrollTop = await modifiedScrollTop(root);
  await page.evaluate(() =>
    globalThis.__diffEditorLifecycleControls.set_provider('core'),
  );
  await waitForAnimationFrames(page, 4);
  const recomputedScrollTop = await modifiedScrollTop(root);
  expect(Math.abs(recomputedScrollTop - reviewerScrollTop)).toBeLessThanOrEqual(1);

  await disposeDiffLifecycle(page);
});

test('the latest deferred edge reveal supersedes an earlier request', async ({ page }) => {
  const root = await openDiffLifecycle(page);
  const host = page.locator('.diff-lifecycle-host');
  const modified = root.locator('.moonbit-diff-editor-modified');

  await setDiffLifecycleFixture(page, 'late');
  await waitForDiffBands(root);

  // Semantic MultiDiff items request their initial first hunk while hidden.
  // Shift+F7 can supersede that with a last-hunk request before layout becomes
  // ready. Only the later request may move the cursor/viewport.
  await host.evaluate((node) => {
    node.style.display = 'none';
  });
  await page.evaluate(() => {
    globalThis.__diffEditorLifecycleControls.reveal_first_diff();
    globalThis.__diffEditorLifecycleControls.reveal_last_diff();
  });
  await host.evaluate((node) => {
    node.style.display = 'block';
  });

  await expect(
    modified.locator('.line-numbers.active-line-number'),
  ).toHaveText('190');
  await expect(
    modified.locator('.view-line').filter({ hasText: 'new second hunk' }),
  ).toBeVisible();

  await disposeDiffLifecycle(page);
});

test('keeps overview interactions, failure status, and disposal observable', async ({ page }) => {
  const root = await openDiffLifecycle(page);
  await expect(root.locator('.moonbit-diff-editor-pane > .monaco-editor')).toHaveCount(2);
  await expect(
    root.locator('.diff-editor-inline-deleted-block'),
  ).toHaveCount(1);

  const overview = root.locator('.moonbit-diff-overview');
  const overviewViewport = overview.locator('.moonbit-diff-overview-viewport');
  const overviewCanvases = overview.locator('.diffOverviewRuler');
  await expect(overview).toBeVisible();
  await expect(overviewCanvases).toHaveCount(2);
  await expect(
    overview.locator('[data-diff-overview-side="original"]'),
  ).toHaveCSS('width', '15px');
  await expect(
    overview.locator('[data-diff-overview-side="modified"]'),
  ).toHaveCSS('width', '15px');
  await expect(overview).toHaveCSS('width', '30px');
  const reservedLayout = await root.evaluate((node) => ({
    root: node.getBoundingClientRect().width,
    panes: node.querySelector('.moonbit-diff-editor-panes')
      ?.getBoundingClientRect().width,
  }));
  expect(reservedLayout.root - reservedLayout.panes).toBe(30);

  const modifiedOverview = overview.locator(
    '[data-diff-overview-side="modified"]',
  );
  const originalOverview = overview.locator(
    '[data-diff-overview-side="original"]',
  );
  await expect
    .poll(async () => Number(await modifiedOverview.getAttribute(
      'data-overview-ruler-scroll-height',
    )))
    .toBeGreaterThan(420);
  const originalScrollHeight = Number(await originalOverview.getAttribute(
    'data-overview-ruler-scroll-height',
  ));
  const initialModifiedScrollHeight = Number(await modifiedOverview.getAttribute(
    'data-overview-ruler-scroll-height',
  ));
  // The original kernel itself stays unwrapped, but paired continuation
  // spacers make every wrapped deleted visual row consume equal geometry on
  // both sides.
  expect(originalScrollHeight).toBeGreaterThan(6000);
  expect(Math.abs(originalScrollHeight - initialModifiedScrollHeight)).toBeLessThanOrEqual(20);
  await page.locator('.diff-lifecycle-host').evaluate((node) => {
    node.style.width = '520px';
  });
  await expect
    .poll(async () => Number(await originalOverview.getAttribute(
        'data-overview-ruler-scroll-height',
      )))
    .toBeGreaterThan(originalScrollHeight);
  const resizedModifiedScrollHeight = Number(await modifiedOverview.getAttribute(
    'data-overview-ruler-scroll-height',
  ));
  expect(
    Math.abs(
      Number(await originalOverview.getAttribute('data-overview-ruler-scroll-height')) -
        resizedModifiedScrollHeight,
    ),
  ).toBeLessThanOrEqual(20);
  const initialScrollTop = Number(await modifiedOverview.getAttribute(
    'data-overview-ruler-scroll-top',
  ));
  await overview.hover();
  await page.mouse.wheel(0, 600);
  await expect
    .poll(async () => Number(await modifiedOverview.getAttribute(
      'data-overview-ruler-scroll-top',
    )))
    .toBeGreaterThan(initialScrollTop);
  await expect
    .poll(async () => Number(await overviewViewport.getAttribute(
      'data-diff-viewport-top',
    )))
    .toBeGreaterThan(0);

  const overviewBox = await overview.boundingBox();
  expect(overviewBox).not.toBeNull();
  const viewportBox = await overviewViewport.boundingBox();
  expect(viewportBox).not.toBeNull();
  await page.mouse.move(
    overviewBox.x + overviewBox.width / 2,
    overviewBox.y + overviewBox.height - 2,
  );
  const trackBackground = await overviewViewport.evaluate((node) =>
    getComputedStyle(node).backgroundColor,
  );
  await page.mouse.move(
    viewportBox.x + viewportBox.width / 2,
    viewportBox.y + viewportBox.height / 2,
  );
  const hoverBackground = await overviewViewport.evaluate((node) =>
    getComputedStyle(node).backgroundColor,
  );
  expect(hoverBackground).not.toBe(trackBackground);
  await page.mouse.down();
  const activeBackground = await overviewViewport.evaluate((node) =>
    getComputedStyle(node).backgroundColor,
  );
  expect(activeBackground).not.toBe(hoverBackground);
  await page.mouse.up();
  await page.mouse.click(
    overviewBox.x + overviewBox.width / 2,
    overviewBox.y + overviewBox.height - 12,
  );
  const afterTrackClick = Number(await modifiedOverview.getAttribute(
    'data-overview-ruler-scroll-top',
  ));
  expect(afterTrackClick).toBeGreaterThan(initialScrollTop);
  await page.mouse.move(
    overviewBox.x + overviewBox.width / 2,
    overviewBox.y + overviewBox.height - 12,
  );
  await page.mouse.down();
  await page.mouse.move(
    overviewBox.x + overviewBox.width / 2,
    overviewBox.y + 40,
    { steps: 4 },
  );
  await page.mouse.up();
  await expect
    .poll(async () => Number(await modifiedOverview.getAttribute(
      'data-overview-ruler-scroll-top',
    )))
    .toBeLessThan(afterTrackClick);

  const status = root.locator('.moonbit-diff-editor-status');
  await page.evaluate(() =>
    globalThis.__diffEditorLifecycleControls.set_provider('provider'),
  );
  await expect(root).toHaveAttribute('data-diff-failure', 'provider error');
  await expect(status).toBeVisible();
  await expect(status).toHaveText('Unable to compute this diff.');
  await page.evaluate(() =>
    globalThis.__diffEditorLifecycleControls.set_provider('validator'),
  );
  await expect(root).toHaveAttribute(
    'data-diff-failure',
    'validator rejection',
  );
  await expect(status).toHaveText(
    'The diff provider returned an invalid result.',
  );
  const clearedFailure = await page.evaluate(() => {
    globalThis.__diffEditorLifecycleControls.set_model_attached(false);
    const editor = document.querySelector(
      '.diff-lifecycle-host > .moonbit-diff-editor',
    );
    const diagnostic = editor.querySelector('.moonbit-diff-editor-status');
    return {
      failurePresent: editor.hasAttribute('data-diff-failure'),
      diagnosticHidden: diagnostic.hasAttribute('hidden'),
    };
  });
  expect(clearedFailure).toEqual({
    failurePresent: false,
    diagnosticHidden: true,
  });
  await page.evaluate(() =>
    globalThis.__diffEditorLifecycleControls.set_provider('core'),
  );
  await page.evaluate(() =>
    globalThis.__diffEditorLifecycleControls.set_model_attached(true),
  );
  await expect(root).not.toHaveAttribute('data-diff-failure');
  await expect(status).toBeHidden();
  await expect(
    root.locator('.diff-editor-inline-deleted-block'),
  ).toHaveCount(1);

  await page.evaluate(() => globalThis.__diffEditorLifecycleControls.dispose());
  await expect(root).toHaveCount(0);
  await expect(page.locator('.diff-lifecycle-host .monaco-editor')).toHaveCount(0);

  await page.evaluate(() => globalThis.__diffEditorLifecycleControls.dispose());
  await expect(root).toHaveCount(0);
  await expect(page.locator('.diff-lifecycle-host .monaco-editor')).toHaveCount(0);
  await page.evaluate(() =>
    globalThis.__diffEditorLifecycleControls.dispose_models(),
  );
});

test('inline original strip follows decimal digit bands and font metrics', async ({ page }) => {
  const root = await openDiffLifecycle(page);
  await setDiffLifecycleFixture(page, 'digits');
  await setDiffLifecycleOptions(page, {
    layout: 'inline',
    renderIndicators: true,
    fontSize: 12,
  });
  await expect(root).toHaveAttribute('data-render-mode', 'inline');
  await expect(
    root.locator('.moonbit-diff-editor-original .line-numbers').last(),
  ).toHaveText('9');

  const readGeometry = () => root.evaluate((node) => {
    const original = node.querySelector('.moonbit-diff-editor-original');
    const modified = node.querySelector('.moonbit-diff-editor-modified');
    const originalRect = original.getBoundingClientRect();
    const modifiedRect = modified.getBoundingClientRect();
    return {
      attributeWidth: Number(node.getAttribute('data-inline-original-width')),
      originalWidth: originalRect.width,
      originalRight: originalRect.right,
      modifiedLeft: modifiedRect.left,
    };
  });
  const expectJoinedGeometry = (geometry) => {
    expect(Math.abs(geometry.attributeWidth - geometry.originalWidth))
      .toBeLessThanOrEqual(1);
    expect(Math.abs(geometry.originalRight - geometry.modifiedLeft))
      .toBeLessThanOrEqual(1);
  };

  const nineLineGeometry = await readGeometry();
  expectJoinedGeometry(nineLineGeometry);

  await page.evaluate(() =>
    globalThis.__diffEditorLifecycleControls.set_digit_line_count(10),
  );
  await expect(
    root.locator('.moonbit-diff-editor-original .line-numbers').last(),
  ).toHaveText('10');
  const tenLineGeometry = await readGeometry();
  expectJoinedGeometry(tenLineGeometry);
  expect(tenLineGeometry.attributeWidth)
    .toBeGreaterThan(nineLineGeometry.attributeWidth);

  await setDiffLifecycleOptions(page, {
    layout: 'inline',
    renderIndicators: true,
    fontSize: 24,
  });
  await expect
    .poll(async () => (await readGeometry()).attributeWidth)
    .toBeGreaterThan(tenLineGeometry.attributeWidth);
  const largeFontGeometry = await readGeometry();
  expectJoinedGeometry(largeFontGeometry);
  expect(largeFontGeometry.attributeWidth)
    .toBeGreaterThan(tenLineGeometry.attributeWidth);

  await disposeDiffLifecycle(page);
});

test('renderIndicators removes only split and inline glyphs while retaining diff backgrounds', async ({ page }) => {
  const root = await openDiffLifecycle(page);
  const originalPane = root.locator('.moonbit-diff-editor-original');
  const modifiedPane = root.locator('.moonbit-diff-editor-modified');
  const expectBackgrounds = async () => {
    await expect
      .poll(() => originalPane.locator(
        '.cmdr.diff-editor-gutter-delete',
      ).count())
      .toBeGreaterThan(0);
    await expect
      .poll(() => modifiedPane.locator(
        '.cmdr.diff-editor-gutter-insert',
      ).count())
      .toBeGreaterThan(0);
    await expect
      .poll(() => originalPane.locator('.diff-editor-line-delete').count())
      .toBeGreaterThan(0);
    await expect
      .poll(() => modifiedPane.locator('.diff-editor-line-insert').count())
      .toBeGreaterThan(0);
  };
  const expectLaneIndicators = async () => {
    await expect
      .poll(() => originalPane.locator(
        '.cldr.delete-sign.codicon-diff-remove',
      ).count())
      .toBeGreaterThan(0);
    await expect
      .poll(() => modifiedPane.locator(
        '.cldr.insert-sign.codicon-diff-insert',
      ).count())
      .toBeGreaterThan(0);
  };

  await setDiffLifecycleFixture(page, 'indicators');
  await setDiffLifecycleOptions(page, {
    layout: 'split',
    renderIndicators: true,
  });
  await expect(root).toHaveAttribute('data-render-mode', 'side-by-side');
  await expectBackgrounds();
  await expectLaneIndicators();

  await setDiffLifecycleOptions(page, {
    layout: 'split',
    renderIndicators: false,
  });
  await expect(root.locator('.cldr.delete-sign, .cldr.insert-sign')).toHaveCount(0);
  await expect(root.locator('.diff-editor-inline-delete-sign')).toHaveCount(0);
  await expectBackgrounds();

  await setDiffLifecycleOptions(page, {
    layout: 'inline',
    renderIndicators: true,
  });
  await expect(root).toHaveAttribute('data-render-mode', 'inline');
  await expectLaneIndicators();
  await expect
    .poll(() => root.locator('.diff-editor-inline-delete-sign').count())
    .toBeGreaterThan(0);
  await expectBackgrounds();

  await setDiffLifecycleOptions(page, {
    layout: 'inline',
    renderIndicators: false,
  });
  await expect(root.locator('.cldr.delete-sign, .cldr.insert-sign')).toHaveCount(0);
  await expect(root.locator('.diff-editor-inline-delete-sign')).toHaveCount(0);
  await expect(root.locator('.diff-editor-inline-deleted-block')).not.toHaveCount(0);
  await expectBackgrounds();

  await disposeDiffLifecycle(page);
});


for (const layout of ['split', 'inline']) {
  test(`ignored changes retain ${layout} geometry without visible markers`, async ({ page }) => {
    const root = await openDiffLifecycle(page);
    await setDiffLifecycleFixture(page, 'ignored');
    await setDiffLifecycleOptions(page, { layout, renderIndicators: true });
    const original = root.locator('.moonbit-diff-editor-original');
    const modified = root.locator('.moonbit-diff-editor-modified');
    const bands = root.locator('[data-diff-overview-side="modified"]');
    const deleted = root.locator('.diff-editor-inline-deleted-block');

    for (const provider of ['ignored', 'core', 'ignored']) {
      await page.evaluate((kind) =>
        globalThis.__diffEditorLifecycleControls.set_provider(kind), provider);
      await expect(root).not.toHaveAttribute('data-diff-failure');
      if (provider === 'core') {
        await expect.poll(async () => Number(await bands.getAttribute(
          'data-overview-ruler-band-count'))).toBeGreaterThan(1);
        if (layout === 'inline') {
          await expect(deleted.filter({ hasText: '// removed' })).toHaveCount(1);
        }
        continue;
      }
      await expect(bands).toHaveAttribute('data-overview-ruler-band-count', '1');
      await expect(modified.locator('.diff-editor-line-insert')).toHaveCount(1);
      if (layout === 'split') {
        await expect(original.locator('.diff-editor-line-delete')).toHaveCount(1);
        // Inserted/deleted ignored rows still contribute spacers, so retained
        // source anchors after both edits must line up in the actual DOM.
        for (const text of ['keep', 'last', 'end']) {
          const oldLine = original.locator('.view-line').filter({ hasText: new RegExp(`^${text}$`) });
          const newLine = modified.locator('.view-line').filter({ hasText: new RegExp(`^${text}$`) });
          await expect.poll(async () => {
            const a = await oldLine.boundingBox();
            const b = await newLine.boundingBox();
            return a && b ? Math.abs(a.y - b.y) : Number.POSITIVE_INFINITY;
          }).toBeLessThanOrEqual(1);
        }
      } else {
        await expect(deleted).toHaveCount(1);
        await expect(deleted).toContainText('old value');
        await expect(deleted).not.toContainText('// removed');
        await expect(deleted).not.toContainText('// tail old');
        await expect(modified.locator('.view-line').filter({ hasText: '// inserted' })).toBeVisible();
        // The ignored deletion and visible old code share a modified-side
        // anchor. Their ViewZones must keep source order so old code stays
        // beside its own line number, including after provider toggles.
        const oldNumber = original.locator('.line-numbers').filter({ hasText: /^5$/ });
        await expect.poll(async () => {
          const code = await deleted.boundingBox();
          const gutter = await oldNumber.boundingBox();
          return code && gutter ? Math.abs(code.y - gutter.y) : Number.POSITIVE_INFINITY;
        }).toBeLessThanOrEqual(1);
      }
    }
    await disposeDiffLifecycle(page);
  });
}

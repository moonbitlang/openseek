import { expect, test } from '../support/test.js';

test('defaults to the dark theme and persists the toggled choice', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('.editor-shell')).toHaveAttribute('data-theme', 'dark');

  await page.locator('[data-action="toggle-theme"]').click();
  await expect(page.locator('.editor-shell')).toHaveAttribute('data-theme', 'light');

  await page.reload();
  await expect(page.locator('.editor-shell')).toHaveAttribute('data-theme', 'light');

  await page.locator('[data-action="toggle-theme"]').click();
  await expect(page.locator('.editor-shell')).toHaveAttribute('data-theme', 'dark');
});

test('toggles the explorer without giving up its editor space', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('.editor-shell')).toHaveAttribute('data-status', 'ready');

  const toggle = page.locator('[data-action="toggle-explorer"]');
  const explorer = page.locator('#workspace-explorer');
  const viewerHost = page.locator('.viewer-host');
  const initialWidth = await viewerHost.evaluate((element) =>
    element.getBoundingClientRect().width,
  );

  await expect(toggle).toHaveAttribute('aria-expanded', 'true');
  await toggle.click();
  await expect(toggle).toHaveAttribute('aria-expanded', 'false');
  await expect(toggle).toHaveAttribute('aria-label', 'Show Explorer');
  await expect(explorer).toBeHidden();
  await expect(page.locator('.editor-shell')).toHaveAttribute(
    'data-explorer-visible',
    'false',
  );
  const hiddenWidth = await viewerHost.evaluate((element) =>
    element.getBoundingClientRect().width,
  );
  expect(hiddenWidth).toBeGreaterThan(initialWidth + 150);

  await toggle.click();
  await expect(toggle).toHaveAttribute('aria-expanded', 'true');
  await expect(toggle).toHaveAttribute('aria-label', 'Hide Explorer');
  await expect(explorer).toBeVisible();
});

test('keeps the explorer compact and exposes an accessible splitter', async ({
  page,
}) => {
  await page.goto('/');
  await expect(page.locator('.editor-shell')).toHaveAttribute(
    'data-status',
    'ready',
  );

  const explorer = page.locator('#workspace-explorer');
  const viewerHost = page.locator('.viewer-host');
  const title = explorer.locator('.workspace-title');
  const rows = explorer.locator('.workspace-item');
  await expect(explorer).toHaveCSS('width', '280px');
  await expect(title).toHaveCSS('height', '30px');
  await expect(rows.first()).toHaveCSS('height', '22px');

  const splitter = page.locator('[data-action="resize-explorer"]');
  await expect(splitter).toHaveAttribute('role', 'separator');
  await expect(splitter).toHaveAttribute('tabindex', '0');
  await expect(splitter).toHaveAttribute('aria-controls', 'workspace-explorer');
  await expect(splitter).toHaveAttribute('aria-orientation', 'vertical');
  await expect(splitter).toHaveAttribute('aria-valuemin', '200');
  await expect(splitter).toHaveAttribute('aria-valuemax', '420');
  await expect(splitter).toHaveAttribute('aria-valuenow', '280');
  await expect.poll(() =>
    splitter.evaluate((element) =>
      Number.parseFloat(getComputedStyle(element, '::after').width),
    )
  ).toBeGreaterThanOrEqual(24);

  // The Viewer has positioned margin layers of its own. Exercise the target's
  // right overhang in Code view to prove the splitter stacks above them.
  const codeSplitterBox = await splitter.boundingBox();
  await page.mouse.move(
    codeSplitterBox.x + codeSplitterBox.width + 6,
    codeSplitterBox.y + codeSplitterBox.height / 2,
  );
  await page.mouse.down();
  await page.mouse.move(
    codeSplitterBox.x + codeSplitterBox.width + 26,
    codeSplitterBox.y + codeSplitterBox.height / 2,
  );
  await page.mouse.up();
  await expect(splitter).toHaveAttribute('aria-valuenow', '300');
  await splitter.focus();
  await splitter.press('ArrowLeft');
  await splitter.press('ArrowLeft');
  await expect(splitter).toHaveAttribute('aria-valuenow', '280');

  await page.locator(
    '[data-workspace-id="readonly-remote://workspace/README.md"]',
  ).click();
  const markdownRoot = viewerHost.locator(
    '.moonbit-viewer-markdown-document',
  );
  await expect(markdownRoot).toBeVisible();

  const before = await page.locator('.editor-main').evaluate((main) => {
    const sidebar = main.querySelector('#workspace-explorer')
      .getBoundingClientRect();
    const viewer = main.querySelector('.viewer-host').getBoundingClientRect();
    return { sidebarWidth: sidebar.width, viewerLeft: viewer.left };
  });

  await splitter.focus();
  await splitter.press('ArrowRight');
  await expect(splitter).toHaveAttribute('aria-valuenow', '290');
  const after = await page.locator('.editor-main').evaluate((main) => {
    const sidebar = main.querySelector('#workspace-explorer')
      .getBoundingClientRect();
    const viewer = main.querySelector('.viewer-host').getBoundingClientRect();
    return {
      sidebarRight: sidebar.right,
      sidebarWidth: sidebar.width,
      viewerLeft: viewer.left,
    };
  });
  expect(after.sidebarWidth).toBe(290);
  expect(after.viewerLeft - before.viewerLeft).toBeCloseTo(10, 1);
  expect(after.viewerLeft - after.sidebarRight).toBeCloseTo(4, 1);

  const splitterBox = await splitter.boundingBox();
  await page.mouse.move(
    splitterBox.x - 6,
    splitterBox.y + splitterBox.height / 2,
  );
  await page.mouse.down();
  await page.mouse.move(
    splitterBox.x - 6 + 50,
    splitterBox.y + splitterBox.height / 2,
    { steps: 5 },
  );
  await page.mouse.up();
  await expect(splitter).toHaveAttribute('aria-valuenow', '340');
  await expect.poll(() =>
    page.locator('.editor-main').evaluate((main) => {
      const host = main.querySelector('.viewer-host').getBoundingClientRect();
      const root = main.querySelector('.moonbit-viewer-markdown-document')
        .getBoundingClientRect();
      return Math.abs(host.width - root.width);
    })
  ).toBeLessThan(1);

  // A different pointer must neither resize nor terminate this drag. Cancel
  // restores the prior inline styles and removes the window listeners.
  await splitter.evaluate(handle => {
    document.body.style.cursor = 'crosshair';
    document.body.style.userSelect = 'text';
    handle.dispatchEvent(new PointerEvent('pointerdown', {
      pointerId: 99, button: 0, clientX: 340, bubbles: true,
    }));
    window.dispatchEvent(new PointerEvent('pointermove', { pointerId: 98, clientX: 400 }));
    window.dispatchEvent(new PointerEvent('pointerup', { pointerId: 98 }));
  });
  await expect(splitter).toHaveAttribute('aria-valuenow', '340');
  await expect(page.locator('body')).toHaveCSS('cursor', 'ew-resize');
  await page.evaluate(() => {
    window.dispatchEvent(new PointerEvent('pointermove', { pointerId: 99, clientX: 370 }));
    window.dispatchEvent(new PointerEvent('pointercancel', { pointerId: 99 }));
    window.dispatchEvent(new PointerEvent('pointermove', { pointerId: 99, clientX: 400 }));
  });
  await expect(splitter).toHaveAttribute('aria-valuenow', '370');
  await expect(page.locator('body')).toHaveCSS('cursor', 'crosshair');
  await expect(page.locator('body')).toHaveCSS('user-select', 'text');
  await splitter.press('Home');
  await expect(splitter).toHaveAttribute('aria-valuenow', '200');
  await splitter.press('End');
  await expect(splitter).toHaveAttribute('aria-valuenow', '420');

  await page.setViewportSize({ width: 640, height: 700 });
  await expect(explorer).toHaveCSS('width', '148px');
  await expect(splitter).toBeHidden();
  await expect(viewerHost).toBeVisible();
  await expect.poll(() =>
    page.locator('.editor-main').evaluate((main) => {
      const host = main.querySelector('.viewer-host').getBoundingClientRect();
      const root = main.querySelector('.moonbit-viewer-markdown-document')
        .getBoundingClientRect();
      return Math.abs(host.width - root.width);
    })
  ).toBeLessThan(1);

  // A mobile-first load must retain the desktop default instead of treating
  // the responsive 148px column as the user's preferred width.
  await page.setViewportSize({ width: 390, height: 700 });
  await page.reload();
  await expect(page.locator('.editor-shell')).toHaveAttribute(
    'data-status',
    'ready',
  );
  await expect(explorer).toHaveCSS('width', '148px');
  await page.setViewportSize({ width: 800, height: 700 });
  await expect(explorer).toHaveCSS('width', '280px');
  await expect(splitter).toBeVisible();
  await expect(splitter).toHaveAttribute('aria-valuenow', '280');
});

test('renders explorer rows with twisties and file icons', async ({ page }) => {
  await page.goto('/');

  // src/main.mbt becomes visible once auto-reveal expands src.
  await expect(
    page.locator(
      '[data-workspace-id="readonly-remote://workspace/src"] .workspace-twistie svg',
    ),
  ).toBeVisible();
  await expect(
    page.locator(
      '[data-workspace-id="readonly-remote://workspace/src/main.mbt"] .workspace-file-icon svg',
    ),
  ).toBeVisible();
});

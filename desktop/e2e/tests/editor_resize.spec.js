import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

for (const handleSelector of ['.editor-resize-handle', '.tree-resize-handle']) {
  test(`${handleSelector} suspends editor mouse events until the drag ends`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    await app.install();
    await app.goto();
    await app.openSession();
    await app.openQuickOpen();
    await page.getByRole('option', { name: /src\/main\.mbt/ }).click();

    const viewer = page.locator('#viewer-host');
    await expect(viewer).toBeVisible();
    const content = viewer.locator('.view-lines');
    await expect(content).toBeVisible();
    // Observe actual browser hit testing, rather than dispatching synthetic
    // events, which would bypass pointer-events and still reach the editor.
    await viewer.evaluate(element => {
      element.dataset.testMouseMoves = '0';
      element.addEventListener('mousemove', () => {
        element.dataset.testMouseMoves = String(Number(element.dataset.testMouseMoves) + 1);
      }, true);
    });
    await content.hover();
    await expect.poll(() => viewer.getAttribute('data-test-mouse-moves'))
      .not.toBe('0');

    const handle = page.locator(handleSelector);
    await expect(handle).toBeVisible();
    await handle.hover();
    const start = await handle.boundingBox();
    const editorBefore = await viewer.boundingBox();
    await page.mouse.move(start.x + start.width / 2, start.y + start.height / 2);
    await page.mouse.down();
    try {
      await expect(content).toHaveCSS('pointer-events', 'none');
      await expect(handle).not.toHaveCSS('pointer-events', 'none');
      await viewer.evaluate(element => { element.dataset.testMouseMoves = '0'; });
      await page.mouse.move(
        editorBefore.x + editorBefore.width * 0.7,
        editorBefore.y + 30,
        { steps: 6 },
      );
      await expect(viewer).toHaveAttribute('data-test-mouse-moves', '0');
      // The document drag listener still receives movement over the disabled
      // viewer, so the divider actually moves while the editor stays quiet.
      await expect.poll(async () => (await handle.boundingBox()).x)
        .not.toBe(start.x);
    } finally {
      await page.mouse.up();
    }

    await expect(content).not.toHaveCSS('pointer-events', 'none');
    await page.mouse.move(2, 2);
    await viewer.evaluate(element => { element.dataset.testMouseMoves = '0'; });
    await content.hover();
    await expect.poll(() => viewer.getAttribute('data-test-mouse-moves'))
      .not.toBe('0');
    expect(app.pageErrors).toEqual([]);
  });
}

import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

for (const mode of ['Token', 'Tree']) {
  test(`${mode} split diff supports horizontal and vertical scrolling`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    const source = (version) => Array.from({ length: 12 }, (_, index) =>
      `///|\nfn section_${index}() -> String {\n  "${version} ${'long content '.repeat(50)}"\n}\n`,
    ).join('\n');
    app.workingFiles['src/main.mbt'] = source('modified');
    app.gitFilesByRevision[app.gitBaseline]['src/main.mbt'] = source('original');
    await app.install();
    await app.goto();
    await app.openSession();
    await app.openReview();
    await page.locator('[role="treeitem"][data-path="src/main.mbt"]').click();
    await page.locator(`[data-diff-mode="${mode.toLowerCase()}"]`).click();
    await page.locator('[data-layout="side-by-side"]').click();

    const host = page.locator('#semantic-review-host');
    const entry = host.locator('.semantic-diff-editor-host').first();
    await expect(entry.locator('.moonbit-diff-editor').first())
      .toHaveAttribute('data-render-mode', 'side-by-side');
    await entry.hover();
    await page.mouse.wheel(250, 0);
    await expect.poll(() => host.evaluate(node => node.scrollLeft)).toBeGreaterThan(0);

    // Boundary gestures stay within this scroll plane; vertical gestures still
    // navigate the aggregate document.
    await page.mouse.wheel(100000, 0);
    await page.mouse.wheel(-100000, 0);
    await expect.poll(() => host.evaluate(node => node.scrollLeft)).toBe(0);
    await page.mouse.wheel(0, 300);
    await expect.poll(() => host.evaluate(node => node.scrollTop)).toBeGreaterThan(0);
    expect(app.pageErrors).toEqual([]);
  });
}

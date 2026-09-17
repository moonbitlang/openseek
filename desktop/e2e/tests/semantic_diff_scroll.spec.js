import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

for (const mode of ['Token', 'Tree']) {
  test(`${mode} split diff scrolls code while keeping item frames fixed`, async ({ page }) => {
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
    await page.getByRole('treeitem', { name: /View diff: src\/main\.mbt/ }).click();
    await page.getByRole('button', { name: `${mode} diff`, exact: true }).click();
    await page.getByRole('button', { name: 'Split diff layout', exact: true }).click();

    const host = page.locator('#semantic-review-host');
    const entry = host.locator('.semantic-diff-editor-host').first();
    await expect(entry.locator('.moonbit-diff-editor').first())
      .toHaveAttribute('data-render-mode', 'side-by-side');
    await expect.poll(() => host.evaluate(node => node.scrollWidth - node.clientWidth))
      .toBeGreaterThan(500);
    await page.setViewportSize({ width: 1100, height: 800 });
    await expect.poll(() => host.evaluate(node => Math.abs(
      node.querySelector('.semantic-document').getBoundingClientRect().width - node.clientWidth,
    ))).toBeLessThanOrEqual(1);

    // Read geometry in the same task that changes scrollLeft, before a JS
    // scroll listener can compensate. Native scrolling must never move frames.
    const drift = await host.evaluate(node => {
      const header = node.querySelector('.semantic-entry-header');
      const pane = node.querySelector('.moonbit-diff-editor-modified');
      const before = [header, pane].map(element => element.getBoundingClientRect().left);
      node.scrollLeft = 200;
      return [header, pane].map((element, index) =>
        element.getBoundingClientRect().left - before[index]);
    });
    for (const offset of drift) expect(Math.abs(offset)).toBeLessThanOrEqual(1);
    await host.evaluate(node => { node.scrollLeft = 0; });
    const line = entry.locator('.moonbit-diff-editor-modified .view-line')
      .filter({ hasText: 'modified long content' }).first();
    await expect(line).toBeVisible();
    const before = await line.boundingBox();
    const frame = await entry.boundingBox();
    await page.mouse.move(frame.x + frame.width * 0.75, frame.y + 35);
    await page.mouse.wheel(250, 0);
    await expect.poll(async () => (await line.boundingBox()).x)
      .toBeLessThan(before.x - 100);
    expect(Math.abs((await entry.boundingBox()).x - frame.x)).toBeLessThanOrEqual(1);

    // Boundary gestures stay within this scroll plane; vertical gestures still
    // navigate the aggregate document.
    await page.mouse.wheel(100000, 0);
    await expect.poll(() => host.evaluate(node =>
      Math.abs(node.scrollLeft - (node.scrollWidth - node.clientWidth))))
      .toBeLessThanOrEqual(1);
    expect(Math.abs((await entry.boundingBox()).x - frame.x)).toBeLessThanOrEqual(1);
    await page.mouse.wheel(-100000, 0);
    await expect.poll(() => host.evaluate(node => node.scrollLeft)).toBe(0);
    await page.mouse.wheel(0, 300);
    await expect.poll(() => host.evaluate(node => node.scrollTop)).toBeGreaterThan(0);
    expect(app.pageErrors).toEqual([]);
  });
}

import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

// Exercise the real scroll -> active-hunk message -> after-render path. Node
// identity and active-hunk state are the regression gates.
for (const mode of ['Token', 'Tree']) {
  test(`${mode} review scrolling retains hunk controls`, async ({ page }) => {
    test.setTimeout(90_000);
    const app = new DesktopBrowserHarness(page);
    const source = version => Array.from({ length: 32 }, (_, i) =>
      `///|\nfn section_${i}() -> String {\n  "${version} ${'content '.repeat(12)}"\n}\n`,
    ).join('\n');
    app.workingFiles['src/main.mbt'] = source('modified');
    app.gitFilesByRevision[app.gitBaseline]['src/main.mbt'] = source('original');
    await app.install();
    await app.goto();
    await app.openSession();
    await app.openReview();
    await page.locator('[role="treeitem"][data-path="src/main.mbt"]').click();
    const modeButton = page.locator(`[data-diff-mode="${mode.toLowerCase()}"]`);
    if (await modeButton.getAttribute('aria-pressed') !== 'true') await modeButton.click();
    await expect(page.locator('#review-navigation-controls')).toHaveAttribute('aria-busy', 'false');
    const host = page.locator('#semantic-review-host');
    await expect(host.locator('.review-hunk-marker')).toHaveCount(32);
    // Wait for initial diff and provider work before retaining the live nodes.
    await page.evaluate(() => new Promise(resolve => {
      let remaining = 8;
      const tick = () => --remaining ? requestAnimationFrame(tick) : resolve();
      requestAnimationFrame(tick);
    }));
    const result = await host.evaluate(async node => {
      const buttons = [...node.querySelectorAll('.review-hunk-marker')];
      const entries = [...node.querySelectorAll('.semantic-diff-editor-host')];
      const positions = [];
      let addedActions = 0;
      const observer = new MutationObserver(records => {
        for (const record of records) for (const added of record.addedNodes) {
          if (added.nodeType === 1 && added.matches('.moonbit-diff-hunk-action')) addedActions++;
        }
      });
      observer.observe(node, { childList: true, subtree: true });
      for (const index of [4, 12, 24, 8, 20, 0]) {
        node.scrollTop += entries[index].getBoundingClientRect().top - node.getBoundingClientRect().top;
        await new Promise(resolve => {
          let remaining = 4;
          const tick = () => --remaining ? requestAnimationFrame(tick) : resolve();
          requestAnimationFrame(tick);
        });
        positions.push(document.querySelector('.review-hunk-position').textContent);
      }
      observer.disconnect();
      return {
        retained: buttons.filter(button => button.isConnected).length,
        count: buttons.length, addedActions, positions,
      };
    });
    expect(new Set(result.positions).size).toBeGreaterThan(3);
    expect(result.retained).toBe(result.count);
    expect(result.addedActions).toBe(0);
    const retained = await host.locator('.review-hunk-marker').elementHandles();
    await page.locator('#task').fill('An unrelated composer update');
    await page.locator('#task').pressSequentially(' while reviewing');
    await expect(page.locator('#task')).toHaveValue('An unrelated composer update while reviewing');
    for (const button of retained) expect(await button.evaluate(node => node.isConnected)).toBe(true);

    // The retained listener must still toggle current state twice. Other
    // hunks and this button keep their identities through both updates.
    const first = host.locator('.review-hunk-marker').first();
    await first.click();
    await expect(first).toHaveAttribute('aria-pressed', 'true');
    await first.click();
    await expect(first).toHaveAttribute('aria-pressed', 'false');
    for (const button of retained) expect(await button.evaluate(node => node.isConnected)).toBe(true);
    expect(app.pageErrors).toEqual([]);
  });
}

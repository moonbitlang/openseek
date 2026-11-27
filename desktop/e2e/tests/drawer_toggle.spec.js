import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('panel toggle keeps its node, focus and position across drawer transitions', { tag: '@motion' }, async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  const toggle = await page.getByRole('button', { name: 'Show panel', exact: true }).elementHandle();
  const initial = await toggle.boundingBox();
  for (const open of [true, false, true, false]) {
    await toggle.focus();
    await page.evaluate(() => {
      const frames = window.drawerFrames = [];
      const start = performance.now();
      const button = document.querySelector('.topbar [title="Show terminal (Ctrl+`)"]');
      const sample = () => {
        frames.push(button.getBoundingClientRect().x);
        if (performance.now() - start < 450) requestAnimationFrame(sample);
      };
      sample();
    });
    await page.keyboard.press('Enter');
    await expect.poll(() => toggle.evaluate(node => node.isConnected)).toBe(true);
    await expect(page.getByRole('button', { name: open ? 'Hide panel' : 'Show panel', exact: true })).toBeFocused();
    await page.waitForTimeout(500);
    const final = await toggle.boundingBox();
    expect(Math.abs(final.x - initial.x)).toBeLessThanOrEqual(1);
    const frames = await page.evaluate(() => window.drawerFrames);
    expect(Math.abs(frames.at(-1) - frames[0])).toBeGreaterThan(100);
    for (let i = 1; i < frames.length; i++) {
      const reverse = open ? frames[i] - frames[i - 1] : frames[i - 1] - frames[i];
      expect(reverse).toBeLessThanOrEqual(1);
    }
  }
});

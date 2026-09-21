import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('Codex uses the shell panel control', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.codexModels = [{ id: 'gpt-test', displayName: 'Codex fixture', isDefault: true }];
  await app.install();
  await app.goto();
  await page.getByRole('button', { name: 'Model', exact: true }).click();
  await page.getByRole('option', { name: 'Codex fixture', exact: true }).click();
  const toggle = page.getByRole('button', { name: 'Show files', exact: true });
  await expect(toggle).toBeEnabled();
  const original = await toggle.elementHandle();
  await toggle.click();
  const close = page.getByRole('button', { name: 'Hide panel', exact: true });
  await expect(close).toBeFocused();
  await close.press('Enter');
  await expect(toggle).toBeFocused();
  expect(await original.evaluate(node => node.isConnected)).toBe(true);
  expect(app.pageErrors).toEqual([]);
});

test('panel toggle keeps its node, focus and position across drawer transitions', async ({ page }) => {
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
  expect(app.pageErrors).toEqual([]);
});

test('shell panel control remains reachable when expanded and on narrow screens', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  // Exercise reserved native control space without opening a native window.
  await page.evaluate(() => {
    document.documentElement.classList.add('native-titlebar-overlay');
    document.documentElement.style.setProperty('--native-titlebar-right', '138px');
    document.documentElement.style.setProperty('--native-titlebar-height', '48px');
  });
  const toggle = page.locator('.right-panel-toggle');
  const original = await toggle.elementHandle();
  const initial = await toggle.boundingBox();
  expect(initial.x + initial.width).toBe(1440 - 138);
  expect(initial.y + initial.height / 2).toBe(24);
  await toggle.click();
  await expect(toggle).toHaveAttribute('aria-expanded', 'true');
  const expand = page.getByRole('button', { name: 'Expand panel', exact: true });
  await expand.click();
  await expect(page.getByRole('button', { name: 'Restore panel', exact: true })).toBeVisible();
  expect(await toggle.boundingBox()).toEqual(initial);
  await toggle.click();
  await expect(toggle).toHaveAttribute('aria-expanded', 'false');
  await page.evaluate(() => {
    document.documentElement.classList.remove('native-titlebar-overlay');
    document.documentElement.style.removeProperty('--native-titlebar-right');
    document.documentElement.style.removeProperty('--native-titlebar-height');
  });
  await page.setViewportSize({ width: 390, height: 844 });
  await expect(toggle).toBeHidden();
  await app.openQuickOpen();
  await page.getByRole('option', { name: /src\/main\.mbt/ }).click();
  await expect(toggle).toBeVisible();
  await expect(toggle).toHaveAccessibleName('Hide panel');
  await toggle.click();
  await expect(toggle).toBeHidden();
  expect(await original.evaluate(node => node.isConnected)).toBe(true);
  expect(app.pageErrors).toEqual([]);
});

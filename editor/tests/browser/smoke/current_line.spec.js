import { expect, test } from '../support/test.js';
import { openWorkspaceFile } from '../support/app.js';

test('default current-line fill follows the caret and the theme, including blur', async ({ page }, testInfo) => {
  await page.goto('/');
  await openWorkspaceFile(page, 'notes.txt');
  const editor = page.locator('.monaco-editor.readonly-editor');
  const highlight = editor.locator('.view-overlays .current-line');

  for (const [theme, color] of [
    ['dark', 'rgba(255, 255, 255, 0.05)'],
    ['light', 'rgba(0, 0, 0, 0.04)'],
  ]) {
    const line = editor.locator('.view-line').nth(theme === 'dark' ? 0 : 2);
    if (theme === 'light') {
      await page.locator('[data-action="toggle-theme"]').click();
    }
    await line.click({ position: { x: 8, y: 8 } });
    await expect(highlight).toHaveCount(1);
    await expect(highlight).toHaveCSS('background-color', color);
    await expect.poll(async () => {
      const a = await highlight.boundingBox();
      const b = await line.boundingBox();
      return a !== null && b !== null && Math.abs(a.y - b.y) < 1;
    }).toBe(true);
    await page.screenshot({ path: testInfo.outputPath(`current-line-${theme}.png`) });

    await page.locator('[data-action="toggle-theme"]').focus();
    await expect(editor).not.toHaveClass(/focused/);
    await expect(highlight).toHaveCSS('background-color', color);
  }
});

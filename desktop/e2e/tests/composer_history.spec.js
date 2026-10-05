import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

// The opened session's own record holds one prompt.
const prompt = 'Show the browser fixture at https://example.test/docs but keep `https://inside.example.test` inert.';

test('Up and Down recall the conversation\'s sent prompts', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  const task = page.locator('#task');
  const caption = page.locator('.composer-mode-chip');

  await task.press('ArrowUp');
  await expect(task).toHaveValue(prompt);
  await expect(caption).toHaveText('History 1/1');

  // Down from the latest prompt returns to the empty draft recall started from.
  await task.press('ArrowDown');
  await expect(task).toHaveValue('');
  await expect(caption).toHaveCount(0);

  // A draft the user typed is never replaced.
  await task.fill('typed');
  await task.press('Home');
  await task.press('ArrowUp');
  await expect(task).toHaveValue('typed');

  // Editing a recalled prompt ends the recall.
  await task.fill('');
  // A script, unlike a person, can fill and press a key inside one animation
  // frame, before Rabbita has rendered the key's new meaning.
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  await task.press('ArrowUp');
  await expect(caption).toHaveText('History 1/1');
  await task.pressSequentially('!');
  await expect(caption).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

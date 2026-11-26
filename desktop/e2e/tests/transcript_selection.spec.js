import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('detailed transcript drag supports keyboard copy', async ({ page, context }) => {
  const app = new DesktopBrowserHarness(page);
  app.sessionEvents = [
    { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture selection' } } },
    { sequence: 2, item: { kind: 'assistant', payload: { content: 'Selectable answer paragraph.' } } },
  ];
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await page.addInitScript(() => {
    localStorage.setItem('openseek.minimal_transcript', 'false');
  });
  await app.install();
  await app.goto();
  await app.openSession();
  const paragraph = page.locator('#transcript .msg-content').getByText('Selectable answer paragraph.', { exact: true });
  const box = await paragraph.evaluate(element => {
    const range = document.createRange();
    range.setStart(element.firstChild, 0);
    range.setEnd(element.firstChild, 'Selectable'.length);
    const rect = range.getBoundingClientRect();
    return { x: rect.x, y: rect.y + rect.height / 2, width: rect.width };
  });
  await page.mouse.move(box.x, box.y);
  await page.mouse.down();
  await page.mouse.move(box.x + box.width, box.y, { steps: 5 });
  await page.mouse.up();
  const toolbar = page.getByRole('toolbar', { name: 'Selection actions' });
  await expect(toolbar).toBeVisible();
  await expect(toolbar.getByRole('button')).toHaveText(['Reply']);
  await expect(page.getByRole('dialog', { name: 'Reply to selection' })).toHaveCount(0);
  expect(await page.evaluate(() => document.getSelection().toString())).toBe('Selectable');
  await page.evaluate(() => navigator.clipboard.writeText('clipboard before selection'));
  await page.keyboard.press('ControlOrMeta+c');
  await expect.poll(() => page.evaluate(() => navigator.clipboard.readText())).toBe('Selectable');
});

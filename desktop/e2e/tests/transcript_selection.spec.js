import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

// Cover both renderers, both selection gestures and all three copy mechanisms without their Cartesian product.
for (const [minimal, gesture, action] of [
  [false, 'drag', 'keyboard copy'],
  [true, 'double click', 'toolbar copy'],
  [true, 'drag', 'context menu'],
  [false, 'double click', 'toolbar copy'],
]) {
  test(`${minimal ? 'minimal' : 'detailed'} transcript ${gesture} supports ${action}`, async ({ page, context }) => {
    const app = new DesktopBrowserHarness(page);
    app.sessionEvents = [
      { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture selection' } } },
      { sequence: 2, item: { kind: 'assistant', payload: { content: 'Selectable answer paragraph.' } } },
    ];
    await context.grantPermissions(['clipboard-read', 'clipboard-write']);
    await page.addInitScript(minimal => {
      localStorage.setItem('openseek.minimal_transcript', String(minimal));
    }, minimal);
    await app.install();
    await app.goto();
    await app.openSession();
    const paragraph = page.locator('#transcript .msg-content.markdown p');
    if (gesture === 'double click') {
      await paragraph.dblclick({ position: { x: 8, y: 8 } });
    } else {
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
    }
    const toolbar = page.locator('.selection-actions[role="toolbar"]');
    await expect(toolbar).toBeVisible();
    await expect(toolbar.locator('#selection-copy')).toBeVisible();
    await expect(toolbar.locator('#selection-reply')).toBeVisible();
    await expect(page.locator('.selection-actions.replying')).toHaveCount(0);
    expect(await page.evaluate(() => document.getSelection().toString())).toBe('Selectable');
    if (action === 'keyboard copy') {
      await page.evaluate(() => navigator.clipboard.writeText('clipboard before selection'));
      await page.keyboard.press('ControlOrMeta+c');
      await expect.poll(() => page.evaluate(() => navigator.clipboard.readText())).toBe('Selectable');
    } else if (action === 'toolbar copy') {
      await toolbar.locator('#selection-copy').click();
      await expect.poll(() => page.evaluate(() => navigator.clipboard.readText())).toBe('Selectable');
      expect(await page.evaluate(() => document.getSelection().toString())).toBe('Selectable');
      await expect(toolbar).toHaveCount(0);
      const copied = page.locator('.selection-copy-feedback');
      await expect(copied).toBeVisible();
      await expect(page.locator('[data-selection-actions]')).toHaveCount(0);
      expect(await page.evaluate(() => document.getSelection().toString())).toBe('Selectable');
      await paragraph.dblclick({ position: { x: 8, y: 8 } });
      await toolbar.locator('#selection-reply').click();
      const reply = page.locator('.selection-actions.replying');
      await expect(reply.locator('blockquote')).toHaveText('Selectable');
      await expect(reply.locator('#selection-reply-input')).toBeFocused();
    } else {
      await paragraph.click({ button: 'right', position: { x: 8, y: 8 } });
      const menu = page.locator('[id="app-context-menu-content"]:visible');
      await expect(menu).toBeVisible();
      await menu.locator('[role="menuitem"][data-action="copy"]:visible').click();
      await expect.poll(() => page.evaluate(() => navigator.clipboard.readText())).toBe('Selectable');
    }
    expect(app.pageErrors).toEqual([]);
  });
}

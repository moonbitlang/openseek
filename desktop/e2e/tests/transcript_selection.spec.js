import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

for (const minimal of [false, true]) for (const gesture of ['drag', 'double click']) for (const action of ['keyboard copy', 'context menu', 'toolbar copy']) {
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
    const paragraph = page.locator('#transcript .msg-content').getByText('Selectable answer paragraph.', { exact: true });
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
    const toolbar = page.getByRole('toolbar', { name: 'Selection actions' });
    await expect(toolbar).toBeVisible();
    await expect(toolbar.getByRole('button')).toHaveText(['Copy', 'Reply']);
    await expect(page.getByRole('dialog', { name: 'Reply to selection' })).toHaveCount(0);
    expect(await page.evaluate(() => document.getSelection().toString())).toBe('Selectable');
    if (action === 'keyboard copy') {
      await page.evaluate(() => navigator.clipboard.writeText('clipboard before selection'));
      await page.keyboard.press('ControlOrMeta+c');
      await expect.poll(() => page.evaluate(() => navigator.clipboard.readText())).toBe('Selectable');
    } else if (action === 'toolbar copy') {
      await toolbar.getByRole('button', { name: 'Copy', exact: true }).click();
      await expect.poll(() => page.evaluate(() => navigator.clipboard.readText())).toBe('Selectable');
      expect(await page.evaluate(() => document.getSelection().toString())).toBe('Selectable');
      await expect(toolbar).toHaveCount(0);
      await expect(page.getByRole('status', { name: 'Copied', exact: true })).toBeVisible();
      await expect(page.locator('[data-selection-actions]')).toHaveCount(0);
      expect(await page.evaluate(() => document.getSelection().toString())).toBe('Selectable');
      await paragraph.dblclick({ position: { x: 8, y: 8 } });
      await toolbar.getByRole('button', { name: 'Reply', exact: true }).click();
      const reply = page.getByRole('dialog', { name: 'Reply to selection' });
      await expect(reply.locator('blockquote')).toHaveText('Selectable');
      await expect(reply.getByRole('textbox', { name: 'Reply', exact: true })).toBeFocused();
    } else {
      await paragraph.click({ button: 'right', position: { x: 8, y: 8 } });
      const menu = page.getByRole('menu', { name: 'Context menu' });
      await expect(menu).toBeVisible();
      await menu.getByRole('menuitem', { name: 'Copy', exact: true }).click();
      await expect.poll(() => page.evaluate(() => navigator.clipboard.readText())).toBe('Selectable');
    }
    expect(app.pageErrors).toEqual([]);
  });
}

test('Chinese selection toolbar shows only copy and reply', async ({ page, context }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  app.sessionEvents = [
    { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture selection' } } },
    { sequence: 2, item: { kind: 'assistant', payload: { content: '选中这段文字，可以复制，也可以回复。' } } },
  ];
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await page.addInitScript(() => localStorage.setItem('openseek.language', 'zh-Hans'));
  await app.install();
  await app.goto();
  await app.openSession();
  const paragraph = page.locator('#transcript .msg-content').getByText('选中这段文字，可以复制，也可以回复。', { exact: true });
  const selectionBox = await paragraph.evaluate(element => {
    const range = document.createRange();
    range.selectNodeContents(element);
    const rect = range.getBoundingClientRect();
    return { x: rect.x, y: rect.y + rect.height / 2, width: rect.width };
  });
  await page.mouse.move(selectionBox.x, selectionBox.y);
  await page.mouse.down();
  await page.mouse.move(selectionBox.x + selectionBox.width, selectionBox.y, { steps: 5 });
  await page.mouse.up();
  const toolbar = page.getByRole('toolbar', { name: '选区操作' });
  await expect(toolbar.getByRole('button')).toHaveText(['复制', '回复']);
  await expect(page.getByRole('dialog', { name: '回复选中内容' })).toHaveCount(0);
  const selected = await page.evaluate(() => document.getSelection().toString());
  const textBox = await paragraph.boundingBox();
  const toolbarBox = await toolbar.boundingBox();
  expect(toolbarBox.height).toBeLessThan(45);
  expect(toolbarBox.y + toolbarBox.height).toBeLessThanOrEqual(textBox.y);
  await page.screenshot({ path: testInfo.outputPath('selection-toolbar.png'), clip: {
    x: Math.max(0, Math.min(textBox.x, toolbarBox.x) - 20),
    y: toolbarBox.y - 20,
    width: Math.max(textBox.width, toolbarBox.width) + 40,
    height: textBox.y + textBox.height - toolbarBox.y + 40,
  } });
  await toolbar.getByRole('button', { name: '复制', exact: true }).click();
  await expect.poll(() => page.evaluate(() => navigator.clipboard.readText())).toBe(selected);
});

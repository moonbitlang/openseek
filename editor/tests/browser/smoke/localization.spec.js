import { expect, test } from '../support/test.js';

test('host language updates a mounted editor and its context menu', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('.editor-shell')).toHaveAttribute('data-status', 'ready');
  const editor = page.getByLabel('Readonly code viewer', { exact: true });
  await expect(editor).toBeVisible();
  const source = await page.locator('.view-lines').first().innerText();
  await page.locator('[data-action="toggle-ui-language"]').click();
  await expect(page.getByLabel('只读代码查看器', { exact: true })).toBeVisible();
  expect(await page.locator('.view-lines').first().innerText()).toBe(source);
  await page.locator('.view-line').first().click({ button: 'right' });
  await expect(page.getByRole('menu', { name: '编辑器上下文菜单', exact: true })).toBeVisible();
  await expect(page.getByRole('menuitem', { name: /转到定义/ })).toBeVisible();
  await page.keyboard.press('Escape');
  await page.locator('[data-action="toggle-ui-language"]').click();
  await expect(page.getByLabel('Readonly code viewer', { exact: true })).toBeVisible();
});

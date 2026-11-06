import { test, expect } from './support/test.js';
import { openThemeLab } from '../../dev/theme-lab.mjs';

test('Theme Lab applies palettes to the real app without remounting its draft or editor', async ({ page }) => {
  const app = await openThemeLab(page);
  const preview = page.frameLocator('#preview');
  const composer = preview.locator('#task');
  await composer.fill('Keep this unsent draft');
  const editor = await preview.locator('#viewer-host').elementHandle();
  await expect(preview.locator('.transcript')).toContainText('Check the application colors');
  await expect(preview.locator('.editor-tab.active')).toContainText('main.mbt');

  await page.getByRole('button', { name: 'Light', exact: true }).click();
  const presets = page.getByRole('combobox', { name: 'Color presets' });
  for (const name of ['GitHub Light', 'Atom One Light', 'Catppuccin Latte', 'Rosé Pine Dawn', 'Solarized Light']) {
    await presets.selectOption({ label: name });
    const canvas = await page.getByRole('textbox', { name: 'Canvas HEX', exact: true }).inputValue();
    await expect.poll(() => preview.locator('body').evaluate(el => {
      const color = getComputedStyle(el).backgroundColor.match(/\d+/g);
      return '#' + color.slice(0, 3).map(n => Number(n).toString(16).padStart(2, '0')).join('');
    })).toBe(canvas.toLowerCase());
  }
  await presets.selectOption({ label: 'GitHub Light' });
  await page.getByRole('textbox', { name: 'Canvas HEX', exact: true }).fill('#fafbfc');
  await expect(preview.locator('body')).toHaveCSS('background-color', 'rgb(250, 251, 252)');
  await page.getByRole('checkbox', { name: 'Compare with current SeekMoon colors' }).check();
  await expect(preview.locator('body')).not.toHaveCSS('background-color', 'rgb(250, 251, 252)');
  await page.getByRole('checkbox', { name: 'Compare with current SeekMoon colors' }).uncheck();
  await expect(preview.locator('body')).toHaveCSS('background-color', 'rgb(250, 251, 252)');
  await page.getByRole('button', { name: 'Reset preset', exact: true }).click();
  await expect(preview.locator('body')).toHaveCSS('background-color', 'rgb(255, 255, 255)');
  await expect(composer).toHaveValue('Keep this unsent draft');
  expect(await editor.evaluate(el => el.isConnected)).toBe(true);

  await page.context().grantPermissions(['clipboard-read', 'clipboard-write']);
  await page.getByRole('button', { name: 'Copy CSS', exact: true }).click();
  await expect.poll(() => page.evaluate(() => navigator.clipboard.readText())).toContain('--light-bg-canvas: #ffffff;');
  await page.getByRole('button', { name: 'Dark', exact: true }).click();
  await expect(preview.locator('#viewer-host [data-theme]').first()).toHaveAttribute('data-theme', 'dark');
  await expect(composer).toHaveValue('Keep this unsent draft');
  await preview.getByRole('button', { name: 'Settings', exact: true }).click();
  await expect(preview.getByRole('button', { name: 'Theme', exact: true })).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('palette edits recolor an existing real terminal without losing output', async ({ page }) => {
  const app = await openThemeLab(page);
  const preview = page.frameLocator('#preview');
  await page.getByRole('button', { name: 'Light', exact: true }).click();
  await preview.getByTitle('Show terminal (Ctrl+`)').click();
  await expect.poll(() => app.requests.filter(r => r.method === 'terminal.open').length).toBe(1);
  app.notify('terminal.output', { id: 'terminal-1', sequence: 1, data: Buffer.from('PALETTE_PREVIEW\r\n').toString('base64') });
  const terminal = preview.locator('.terminal-instance:visible');
  await expect(terminal.locator('.xterm-rows')).toContainText('PALETTE_PREVIEW');
  const emulator = await terminal.locator('.xterm').elementHandle();
  await page.getByRole('textbox', { name: 'Sidebar / cards HEX', exact: true }).fill('#f0e4d0');
  await expect(terminal.locator('.xterm-viewport')).toHaveCSS('background-color', 'rgb(240, 228, 208)');
  await expect(terminal.locator('.xterm-rows')).toContainText('PALETTE_PREVIEW');
  expect(await emulator.evaluate(el => el.isConnected)).toBe(true);
  expect(app.pageErrors).toEqual([]);
});

test('opening the HTML directly explains how to launch the real preview', async ({ page }) => {
  await page.goto(new URL('../../dev/theme-lab.html', import.meta.url).href);
  await expect(page.locator('#preview-help')).toContainText('node desktop/dev/theme-lab.mjs');
  await expect(page.locator('#preview')).toBeHidden();
  await page.getByRole('button', { name: 'Light', exact: true }).click();
  await page.getByRole('combobox', { name: 'Color presets' }).selectOption({ label: 'GitHub Light' });
  await expect(page.getByRole('textbox', { name: 'Canvas HEX', exact: true })).toHaveValue('#FFFFFF');
});

test.describe('a localized browser', () => {
  test.use({ locale: 'zh-CN' });

  test('the real preview opens its demo file independently of translated tooltips', async ({ page }) => {
    const app = await openThemeLab(page);
    await expect(page.frameLocator('#preview').locator('.editor-tab.active')).toContainText('main.mbt');
    expect(app.pageErrors).toEqual([]);
  });
});

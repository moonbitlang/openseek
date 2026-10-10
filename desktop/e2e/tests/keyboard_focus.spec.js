import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

async function appearance(control) {
  return control.evaluate(element => {
    const style = getComputedStyle(element);
    return {
      background: style.backgroundColor,
      borderWidth: style.borderWidth,
      borderStyle: style.borderStyle,
      borderColor: style.borderColor,
      outline: style.outlineStyle,
      outlineWidth: style.outlineWidth,
      decoration: style.textDecorationLine,
      keyboardFocus: element.matches(':focus-visible'),
    };
  });
}

async function tabTo(page, control) {
  for (let i = 0; i < 40; i++) {
    await page.keyboard.press('Tab');
    if (await control.evaluate(element => element === document.activeElement)) return;
  }
  await expect(control).toBeFocused();
}

async function expectFocusFrame(control) {
  await expect(control).toBeFocused();
  const focused = await appearance(control);
  expect(focused.keyboardFocus).toBe(true);
  expect(focused.outline).not.toBe('none');
  expect(parseFloat(focused.outlineWidth)).toBeGreaterThan(0);
  expect(focused.decoration).not.toContain('underline');
}

for (const theme of ['light', 'dark']) {
  test(`keyboard focus uses a single visible frame in ${theme} theme`, async ({ page }, testInfo) => {
    const app = new DesktopBrowserHarness(page);
    app.hostSettings.theme = theme;
    await page.emulateMedia({ colorScheme: theme });
    await app.install();
    await app.goto();
    await page.setViewportSize({ width: 1000, height: 800 });
    const model = page.getByRole('button', { name: 'Model', exact: true });
    const settings = page.getByRole('button', { name: 'Settings', exact: true });
    const restingModel = await appearance(model);

    await page.locator('#task').click();
    await page.mouse.move(999, 0);
    await tabTo(page, model);
    await expectFocusFrame(model);
    const focusedModel = await appearance(model);
    expect(focusedModel.keyboardFocus).toBe(true);
    expect(focusedModel.borderStyle).toBe('solid');
    expect(parseFloat(focusedModel.borderWidth)).toBeGreaterThan(0);
    expect(focusedModel.borderColor).toBe(restingModel.borderColor);
    expect(focusedModel.outline).toBe('solid');
    expect(focusedModel.outlineWidth).toBe('2px');
    expect(focusedModel.background).toBe(restingModel.background);
    expect(focusedModel.decoration).not.toContain('underline');
    await page.screenshot({ path: testInfo.outputPath(`composer-focus-${theme}.png`) });
    await model.press('ArrowDown');
    const menu = page.getByRole('listbox', { name: 'Model', exact: true });
    const selected = menu.getByRole('option', { selected: true });
    await expect(selected).toBeFocused();
    await expectFocusFrame(selected);
    await page.keyboard.press('ArrowDown');
    expect((await appearance(selected)).background).toBe('rgba(0, 0, 0, 0)');
    const next = menu.locator(':focus');
    await expectFocusFrame(next);
    await page.screenshot({ path: testInfo.outputPath(`model-menu-focus-${theme}.png`) });
    await page.keyboard.press('Escape');

    // Switching to the pointer must not leave a keyboard-only highlight.
    await page.locator('#task').click();
    await model.click();
    await page.locator('#task').click();
    await page.mouse.move(999, 0);
    expect(await appearance(model)).toEqual(restingModel);

    await tabTo(page, settings);
    await expectFocusFrame(settings);
    await page.keyboard.press('Enter');
    const fontSize = page.getByRole('slider', { name: 'Font size' });
    await expect(fontSize).toBeVisible();
    await page.getByRole('complementary').getByRole('button', { name: 'Add a project', exact: true }).click();
    const dialog = page.getByRole('dialog', { name: 'Add a project' });
    const close = dialog.getByRole('button', { name: 'Close project picker' });
    await expect(dialog).toBeVisible();
    await page.mouse.move(999, 0);
    await tabTo(page, close);
    await expectFocusFrame(close);
    await page.keyboard.press('Enter');
    await expect(dialog).toBeHidden();
    expect(app.pageErrors).toEqual([]);
  });
}

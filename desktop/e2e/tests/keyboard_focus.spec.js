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

async function expectHighlight(control, resting) {
  await expect(control).toBeFocused();
  const focused = await appearance(control);
  expect(focused.keyboardFocus).toBe(true);
  expect(focused.background).not.toBe(resting.background);
  expect(focused.background).not.toBe('rgba(0, 0, 0, 0)');
  expect(focused.borderWidth).toBe(resting.borderWidth);
  expect(focused.borderStyle).toBe(resting.borderStyle);
  if (resting.borderStyle !== 'none' && resting.borderWidth !== '0px') {
    expect(focused.borderColor).toBe(resting.borderColor);
  }
  expect(focused.outline).toBe('none');
  expect(focused.decoration).not.toContain('underline');
}

for (const theme of ['light', 'dark']) {
  test(`keyboard focus remains visible without frames in ${theme} theme`, async ({ page }, testInfo) => {
    const app = new DesktopBrowserHarness(page);
    app.hostSettings.theme = theme;
    await page.emulateMedia({ colorScheme: theme });
    await app.install();
    await app.goto();
    await page.setViewportSize({ width: 1000, height: 800 });
    const model = page.getByRole('button', { name: 'Model', exact: true });
    const settings = page.getByRole('button', { name: 'Settings', exact: true });
    const restingModel = await appearance(model);
    const restingSettings = await appearance(settings);

    await page.locator('#task').click();
    await page.mouse.move(999, 0);
    await tabTo(page, model);
    await expectHighlight(model, restingModel);
    await page.screenshot({ path: testInfo.outputPath(`composer-focus-${theme}.png`) });
    await model.press('ArrowDown');
    const menu = page.getByRole('listbox', { name: 'Model', exact: true });
    const selected = menu.getByRole('option', { selected: true });
    await expect(selected).toBeFocused();
    const selectedFocused = await appearance(selected);
    expect(selectedFocused.background).not.toBe('rgba(0, 0, 0, 0)');
    expect(selectedFocused.outline).toBe('none');
    await page.keyboard.press('ArrowDown');
    expect((await appearance(selected)).background).toBe('rgba(0, 0, 0, 0)');
    const next = menu.locator(':focus');
    expect((await appearance(next)).background).not.toBe('rgba(0, 0, 0, 0)');
    await page.screenshot({ path: testInfo.outputPath(`model-menu-focus-${theme}.png`) });
    await page.keyboard.press('Escape');

    // Switching to the pointer must not leave a keyboard-only highlight.
    await page.locator('#task').click();
    await model.click();
    await page.locator('#task').click();
    await page.mouse.move(999, 0);
    expect(await appearance(model)).toEqual(restingModel);

    await tabTo(page, settings);
    await expectHighlight(settings, restingSettings);
    await page.keyboard.press('Enter');
    const fontSize = page.getByRole('slider', { name: 'Font size' });
    await expect(fontSize).toBeVisible();
    await page.getByRole('complementary').getByRole('button', { name: 'Add a project', exact: true }).click();
    const dialog = page.getByRole('dialog', { name: 'Add a project' });
    const close = dialog.getByRole('button', { name: 'Close project picker' });
    await expect(dialog).toBeVisible();
    await page.mouse.move(999, 0);
    const restingClose = await appearance(close);
    await tabTo(page, close);
    await expectHighlight(close, restingClose);
    await page.keyboard.press('Enter');
    await expect(dialog).toBeHidden();
    expect(app.pageErrors).toEqual([]);
  });
}

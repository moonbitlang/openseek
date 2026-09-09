import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

async function openTabs(page, names) {
  const app = new DesktopBrowserHarness(page);
  app.searchFiles = names.map(name => `src/${name}.mbt`);
  for (const path of app.searchFiles) app.workingFiles[path] = 'fn main {}\n';
  await app.install();
  await app.goto();
  await app.openSession();
  for (const name of names) {
    await app.openQuickOpen();
    await page.locator('#quick-open-input').fill(name);
    await page.getByRole('option', { name: new RegExp(`${name}\\.mbt`) }).click();
  }
  return app;
}

test('new-tab menu stays anchored to plus in split, expanded and narrow panels', async ({ page }) => {
  const app = await openTabs(page, ['alpha']);
  const add = page.getByRole('button', { name: 'New tab', exact: true });
  const menu = page.locator('.dock-menu');
  for (const layout of ['split', 'expanded', 'narrow']) {
    if (layout === 'expanded') {
      await page.getByRole('button', { name: 'Expand panel', exact: true }).click();
    } else if (layout === 'narrow') {
      await page.setViewportSize({ width: 390, height: 844 });
    }
    await add.click();
    await expect(menu).toBeVisible();
    await expect.poll(() => menu.evaluate(popup => {
      const bounds = popup.getBoundingClientRect();
      const bar = popup.closest('.editor-tabsbar');
      const trigger = bar.querySelector('.tab-add').getBoundingClientRect();
      return {
        aligned: Math.abs(bounds.right - trigger.right) <= 1,
        below: bounds.top >= trigger.bottom && bounds.top <= trigger.bottom + 10,
        contained: bounds.left >= bar.getBoundingClientRect().left &&
          bounds.right <= window.innerWidth && bounds.bottom <= window.innerHeight,
        fits: popup.scrollWidth <= popup.clientWidth,
      };
    }), { message: `${layout} menu should open beneath plus and remain readable` }).toEqual({
      aligned: true, below: true, contained: true, fits: true,
    });
    await add.click();
    await expect(menu).toBeHidden();
  }
  await add.click();
  await menu.getByRole('button', { name: 'Search', exact: false }).click();
  await expect(menu).toBeHidden();
  await expect(page.locator('.editor-tab.active')).toContainText('Search');
  expect(app.pageErrors).toEqual([]);
});

for (const [action, remaining, active] of [
  ['Close Others', ['bravo.mbt'], 'bravo.mbt'],
  ['Close to the Left', ['bravo.mbt', 'charlie.mbt', 'Review Changes'], 'Review Changes'],
  ['Close to the Right', ['alpha.mbt', 'bravo.mbt'], 'bravo.mbt'],
]) {
  test(`${action} is relative to the context tab, across file and picker tabs`, async ({ page }) => {
    const app = await openTabs(page, ['alpha', 'bravo', 'charlie']);
    await app.openReview();
    await page.getByRole('button', { name: 'Expand panel', exact: true }).click();
    const tabs = page.locator('.editor-tab');
    await tabs.filter({ hasText: 'bravo.mbt' }).click({ button: 'right' });
    await expect(page.locator('.editor-tab.active')).toContainText('Review Changes');
    const menu = page.getByRole('menu', { name: 'Tab actions' });
    await expect(menu).toBeVisible();
    await menu.getByRole('menuitem', { name: action, exact: true }).click();
    await expect(menu).toBeHidden();
    await expect(tabs.locator('.tab-name')).toHaveText(remaining);
    await expect(page.locator('.editor-tab.active')).toContainText(active);
    await expect(page.locator('.content.panel-open > .editor')).toBeFocused();
    await expect(page.getByRole('button', { name: 'Restore panel', exact: true })).toBeVisible();
    expect(app.pageErrors).toEqual([]);
  });
}

test('tab menu disables empty ranges and supports keyboard dismissal and Close All', async ({ page }) => {
  const app = await openTabs(page, ['alpha', 'bravo']);
  const tabs = page.locator('.editor-tab');
  const menu = page.getByRole('menu', { name: 'Tab actions' });
  await tabs.first().click({ button: 'right' });
  await expect(menu.getByRole('menuitem', { name: 'Close to the Left' })).toBeDisabled();
  await expect(menu.getByRole('menuitem', { name: 'Close to the Right' })).toBeEnabled();
  await page.keyboard.press('Escape');
  await tabs.last().focus();
  await page.keyboard.press('Shift+F10');
  await expect(menu).toBeVisible();
  await expect(menu.getByRole('menuitem', { name: 'Close to the Right' })).toBeDisabled();
  await page.keyboard.press('Escape');
  await expect(tabs.last()).toBeFocused();
  await page.keyboard.press('Shift+F10');
  await menu.getByRole('menuitem', { name: 'Close Others', exact: true }).click();
  await expect(tabs).toHaveCount(1);
  await tabs.first().click({ button: 'right' });
  for (const name of ['Close Others', 'Close to the Left', 'Close to the Right']) {
    await expect(menu.getByRole('menuitem', { name, exact: true })).toBeDisabled();
  }
  await menu.getByRole('menuitem', { name: 'Close All', exact: true }).click();
  await expect(tabs).toHaveCount(0);
  await expect(page.locator('.dock-launcher')).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

for (const entry of ['menu', 'toolbar']) {
  test(`Close All from the ${entry} preserves the expanded launcher and the next tab`, async ({ page }) => {
    const app = await openTabs(page, ['alpha', 'bravo']);
    await page.getByRole('button', { name: 'Expand panel', exact: true }).click();
    if (entry === 'menu') {
      await page.locator('.editor-tab').first().click({ button: 'right' });
      await page.getByRole('menuitem', { name: 'Close All', exact: true }).click();
    } else {
      await page.getByRole('button', { name: 'Close all tabs', exact: true }).click();
    }
    await expect(page.locator('.editor-tab')).toHaveCount(0);
    await expect(page.locator('.dock-launcher')).toBeVisible();
    const restore = page.getByRole('button', { name: 'Restore panel', exact: true });
    await expect(restore).toHaveAttribute('aria-pressed', 'true');
    await app.openQuickOpen();
    await page.locator('#quick-open-input').fill('alpha');
    await page.getByRole('option', { name: /alpha\.mbt/ }).click();
    await expect(page.locator('.editor-tab.active')).toContainText('alpha.mbt');
    await expect(restore).toHaveAttribute('aria-pressed', 'true');
    expect(app.pageErrors).toEqual([]);
  });
}

test('tab and sidebar menus replace each other without changing selection', async ({ page }) => {
  const app = await openTabs(page, ['alpha', 'bravo']);
  const first = page.locator('.editor-tab').first();
  const active = page.locator('.editor-tab.active');
  const restingBackground = await first.evaluate(tab => getComputedStyle(tab).backgroundColor);
  const selectedBackground = await active.evaluate(tab => getComputedStyle(tab).backgroundColor);
  await first.hover();
  const hoverBackground = await first.evaluate(tab => getComputedStyle(tab).backgroundColor);
  const workspace = page.locator('.workspace-row').first();
  await first.click({ button: 'right' });
  await expect(page.getByRole('menu', { name: 'Tab actions' })).toBeVisible();
  await page.getByRole('menuitem', { name: 'Close Others', exact: true }).hover();
  await expect(first).toHaveAttribute('aria-expanded', 'true');
  await expect(first).toHaveCSS('background-color', hoverBackground);
  await expect(active).toHaveCSS('background-color', selectedBackground);
  await page.keyboard.press('Escape');
  await expect(first).toHaveAttribute('aria-expanded', 'false');
  await expect(first).toHaveCSS('background-color', restingBackground);
  await first.click({ button: 'right' });
  await workspace.click({ button: 'right', position: { x: 24, y: 16 } });
  await expect(page.getByRole('menu', { name: 'Workspace actions' })).toBeVisible();
  await expect(page.getByRole('menu', { name: 'Tab actions' })).toBeHidden();
  await expect(first).toHaveCSS('background-color', restingBackground);
  await first.click({ button: 'right' });
  await expect(page.getByRole('menu', { name: 'Workspace actions' })).toBeHidden();
  await expect(page.getByRole('menu', { name: 'Tab actions' })).toBeVisible();
  await expect(page.locator('.editor-tab.active')).toContainText('bravo.mbt');
  await page.getByRole('menuitem', { name: 'Close', exact: true }).click();
  await expect(page.locator('.editor-tab .tab-name')).toHaveText(['bravo.mbt']);
  await expect(page.locator('.content.panel-open > .editor')).toBeFocused();
  expect(app.pageErrors).toEqual([]);
});

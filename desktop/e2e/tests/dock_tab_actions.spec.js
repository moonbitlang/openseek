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
  await menu.getByRole('menuitem', { name: 'Search', exact: true }).click();
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

for (const gesture of ['right-click', 'keyboard']) {
  test(`opening a tab menu by ${gesture} dismisses the plus launcher`, async ({ page }) => {
    const app = await openTabs(page, ['alpha']);
    await page.locator('.tab-add').click();
    await expect(page.locator('.dock-menu')).toBeVisible();
    const tab = page.locator('.editor-tab').first();
    if (gesture === 'right-click') await tab.click({ button: 'right' });
    else {
      await tab.focus();
      await page.keyboard.press('Shift+F10');
    }
    await expect(page.getByRole('menu', { name: 'Tab actions' })).toBeVisible();
    await expect(page.locator('.dock-menu')).toBeHidden();
    await page.keyboard.press('Escape');
    await page.locator('.tab-add').click();
    await expect(page.locator('.dock-menu')).toBeVisible();
    expect(app.pageErrors).toEqual([]);
  });
}

test('open tab menu follows live locale changes', async ({ page }) => {
  const app = await openTabs(page, ['alpha', 'bravo']);
  await page.locator('.editor-tab').first().click({ button: 'right' });
  for (const [locale, label, closeTitle, items] of [
    ['zh-CN', '标签页操作', '关闭此标签页', ['关闭', '关闭其他标签页', '关闭左侧标签页', '关闭右侧标签页', '关闭所有标签页']],
    ['zh-TW', '標籤頁操作', '關閉此標籤頁', ['關閉', '關閉其他標籤頁', '關閉左側標籤頁', '關閉右側標籤頁', '關閉所有標籤頁']],
    ['ja', 'タブの操作', 'このタブを閉じる', ['閉じる', '他のタブを閉じる', '左側のタブを閉じる', '右側のタブを閉じる', 'すべて閉じる']],
    ['es', 'Acciones de pestaña', 'Cerrar esta pestaña', ['Cerrar', 'Cerrar las demás pestañas', 'Cerrar pestañas a la izquierda', 'Cerrar pestañas a la derecha', 'Cerrar todas']],
    ['en', 'Tab actions', 'Close this tab', ['Close', 'Close Others', 'Close to the Left', 'Close to the Right', 'Close All']],
  ]) {
    await page.evaluate(locale => {
      Object.defineProperty(navigator, 'languages', { configurable: true, value: [locale] });
      window.dispatchEvent(new Event('languagechange'));
    }, locale);
    const menu = page.getByRole('menu', { name: label, exact: true });
    await expect(menu).toBeVisible();
    await expect(menu.getByRole('menuitem')).toHaveText(items);
    await expect(menu.getByRole('menuitem').first()).toHaveAttribute('title', closeTitle);
    await expect(menu).toBeFocused();
  }
  expect(app.pageErrors).toEqual([]);
});

// Exercise the real frontend visibility commands with a simulated Proton
// transport. This does not launch a native CEF window.
test('tab menu hides and restores the native browser view through the host bridge', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await page.exposeFunction('dockDesktopRequest', request => {
    app.requests.push(request);
    if (request.method === 'app.system_appearance') return { dark: false };
    return app.replyFor(request);
  });
  await page.addInitScript(() => {
    const listeners = new Map();
    const events = { on(name, callback) {
      const callbacks = listeners.get(name) || new Set();
      listeners.set(name, callbacks);
      callbacks.add(callback);
      return () => callbacks.delete(callback);
    } };
    window.__MoonBit__ = {
      getTitlebarArea: async () => null,
      app: events, events,
      openseek: new Proxy({}, { get: (_, method) => async params => {
        if (method === 'host.connect') {
          for (const callback of listeners.get('openseek.agent.connected') || []) {
            callback({ payload: { stage: 'serving' } });
          }
        }
        return window.dockDesktopRequest({ method, params });
      } }),
    };
  });
  await page.goto('/dist/browser/index.html');
  await app.openSession();
  await app.openReview();
  await page.locator('.tab-add').click();
  await page.locator('.dock-menu').getByRole('menuitem', { name: 'Browse', exact: true }).click();
  await page.locator('#browser-address-input').fill('https://example.com');
  await page.locator('#browser-address-input').press('Enter');
  const visible = () => app.requests.filter(r => r.method === 'browser.set_visible').at(-1)?.params.visible;
  await expect.poll(visible).toBe(true);
  const tab = page.locator('.editor-tab.active');
  const menu = page.getByRole('menu', { name: 'Tab actions' });
  for (const dismiss of ['escape', 'outside', 'resize', 'action']) {
    await tab.click({ button: 'right' });
    await expect(menu).toBeVisible();
    await expect.poll(visible).toBe(false);
    if (dismiss === 'escape') await page.keyboard.press('Escape');
    else if (dismiss === 'outside') await page.locator('#task').click();
    else if (dismiss === 'resize') await page.setViewportSize({ width: 1300, height: 900 });
    else await menu.getByRole('menuitem', { name: 'Close Others', exact: true }).click();
    await expect(menu).toBeHidden();
    await expect.poll(visible).toBe(true);
  }
  expect(app.pageErrors).toEqual([]);
});

import { test, expect } from './support/test.js';
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
    await page.locator(`#quick-open-list [data-path="src/${name}.mbt"]`).click();
  }
  return app;
}

for (const [action, remaining, active] of [
  ['close-others', ['bravo.mbt'], 'bravo.mbt'],
  ['close-left', ['bravo.mbt', 'charlie.mbt', 'Review Changes'], 'Review Changes'],
  ['close-right', ['alpha.mbt', 'bravo.mbt'], 'bravo.mbt'],
]) {
  test(`${action} is relative to the context tab, across file and picker tabs`, async ({ page }) => {
    const app = await openTabs(page, ['alpha', 'bravo', 'charlie']);
    await app.openReview();
    await page.locator('#panel-expand').click();
    const tabs = page.locator('.editor-tab');
    await tabs.and(page.locator('[data-path="/workspace/src/bravo.mbt"]')).click({ button: 'right' });
    await expect(page.locator('.editor-tab.active')).toContainText('Review Changes');
    const menu = page.locator('[role="menu"][id^="dock:"][id$=":pointer-menu-content"]:visible');
    await expect(menu).toBeVisible();
    await menu.locator(`[role="menuitem"][data-action="${action}"]:visible`).click();
    await expect(menu).toBeHidden();
    await expect(tabs.locator('.tab-name')).toHaveText(remaining);
    await expect(page.locator('.editor-tab.active')).toContainText(active);
    await expect(page.locator('.content.panel-open > .editor')).toBeFocused();
    await expect(page.locator('#panel-expand[aria-pressed="true"]')).toBeVisible();
    expect(app.pageErrors).toEqual([]);
  });
}

test('tab menu replaces sidebar menus, preserves selection and supports keyboard range actions', async ({ page }) => {
  const app = await openTabs(page, ['alpha', 'bravo']);
  const tabs = page.locator('.editor-tab');
  const menu = page.locator('[role="menu"][id^="dock:"][id$=":pointer-menu-content"]:visible');
  await tabs.first().click({ button: 'right' });
  await expect(menu.locator('[role="menuitem"][data-action="close-left"]:visible')).toBeDisabled();
  await expect(menu.locator('[role="menuitem"][data-action="close-right"]:visible')).toBeEnabled();
  await expect(page.locator('.editor-tab.active')).toContainText('bravo.mbt');
  await page.locator('.workspace-row').first().click({ button: 'right', position: { x: 24, y: 16 } });
  await expect(page.locator('[role="menu"][id^="project:"][id$=":context-content"]:visible')).toBeVisible();
  await expect(menu).toBeHidden();
  await tabs.first().click({ button: 'right' });
  await expect(page.locator('[role="menu"][id^="project:"][id$=":context-content"]:visible')).toBeHidden();
  await expect(menu).toBeVisible();
  await expect(page.locator('.editor-tab.active')).toContainText('bravo.mbt');
  await page.keyboard.press('Escape');
  await tabs.last().focus();
  await page.keyboard.press('Shift+F10');
  await expect(menu).toBeVisible();
  await expect(menu.locator('[role="menuitem"][data-action="close-right"]:visible')).toBeDisabled();
  await menu.locator('[role="menuitem"][data-action="close-others"]:visible').click();
  await expect(tabs).toHaveCount(1);
  await tabs.first().click({ button: 'right' });
  for (const action of ['close-others', 'close-left', 'close-right']) {
    await expect(menu.locator(`[role="menuitem"][data-action="${action}"]:visible`)).toBeDisabled();
  }
  await menu.locator('[role="menuitem"][data-action="close-all"]:visible').click();
  await expect(tabs).toHaveCount(0);
  await expect(page.locator('.dock-launcher')).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

for (const entry of ['menu', 'toolbar']) {
  test(`Close All from the ${entry} preserves the expanded launcher and the next tab`, async ({ page }) => {
    const app = await openTabs(page, ['alpha', 'bravo']);
    await page.locator('#panel-expand').click();
    if (entry === 'menu') {
      await page.locator('.editor-tab').first().click({ button: 'right' });
      await page.locator('[role="menuitem"][data-action="close-all"]:visible').click();
    } else {
      await page.locator('#dock-close-all').click();
    }
    await expect(page.locator('.editor-tab')).toHaveCount(0);
    await expect(page.locator('.dock-launcher')).toBeVisible();
    const restore = page.locator('#panel-expand[aria-pressed="true"]');
    await expect(restore).toHaveAttribute('aria-pressed', 'true');
    await app.openQuickOpen();
    await page.locator('#quick-open-input').fill('alpha');
    await page.locator('#quick-open-list [data-path="src/alpha.mbt"]').click();
    await expect(page.locator('.editor-tab.active')).toContainText('alpha.mbt');
    await expect(restore).toHaveAttribute('aria-pressed', 'true');
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
    const menu = page.locator('[role="menu"][id^="dock:"][id$=":pointer-menu-content"]:visible');
    await expect(menu).toBeVisible();
    await expect(menu).toHaveAccessibleName(label);
    await expect(menu.getByRole('menuitem')).toHaveText(items);
    await expect(menu.getByRole('menuitem').first()).toHaveAttribute('title', closeTitle);
  }
  expect(app.pageErrors).toEqual([]);
});

// Exercise the real frontend visibility commands with a simulated Proton
// transport. This does not launch a native CEF window.
test('tab menu hides and restores the native browser view through the host bridge', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  app.channel = 'local';
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
            callback({ payload: { protocol: 5 } });
          }
        }
        return window.dockDesktopRequest({ method, params });
      } }),
    };
  });
  await page.goto('/index.html');
  await app.openSession();
  await app.openReview();
  await page.locator('.tab-add').click();
  await page.locator('.dock-menu').locator('[data-dock-action="browser"]').click();
  await page.locator('#browser-address-input').fill('https://example.com');
  await page.locator('#browser-address-input').press('Enter');
  const visible = () => app.requests.filter(r => r.method === 'browser.set_visible').at(-1)?.params.visible;
  await expect.poll(visible).toBe(true);
  const shows = () => app.requests.filter(r => r.method === 'browser.set_visible' && r.params.visible);
  const composer = page.locator('#task');
  await composer.fill('Keep this draft');
  // Native browser contents have a separate renderer. Model its focus return
  // at the window boundary, while leaving the real composer focused.
  for (let attempt = 0; attempt < 2; attempt++) {
    const before = shows().length;
    await page.evaluate(() => window.dispatchEvent(new Event('blur')));
    await page.evaluate(() => window.dispatchEvent(new Event('focus')));
    await expect.poll(() => shows().length).toBe(before + 1);
    await expect(composer).toBeFocused();
    await expect(composer).toHaveValue('Keep this draft');
  }
  // Switching between HTML controls does not refire the window focus event.
  await page.locator('#browser-address-input').focus();
  const beforeComposerFocus = shows().length;
  await composer.focus();
  await expect.poll(() => shows().length).toBeGreaterThan(beforeComposerFocus);
  await expect(composer).toBeFocused();
  await expect(composer).toHaveValue('Keep this draft');
  // Clicking a control that already has focus still raises CEF's main HWND.
  const beforeComposerClick = shows().length;
  await composer.click();
  await expect.poll(() => shows().length).toBeGreaterThan(beforeComposerClick);
  await expect(composer).toBeFocused();
  const tab = page.locator('.editor-tab.active');
  const menu = page.locator('[role="menu"][id^="dock:"][id$=":pointer-menu-content"]:visible');
  for (const dismiss of ['escape', 'outside', 'resize', 'action']) {
    await tab.click({ button: 'right' });
    await expect(menu).toBeVisible();
    await expect.poll(visible).toBe(false);
    const before = shows().length;
    await page.evaluate(() => window.dispatchEvent(new Event('focus')));
    // A focus return must not expose a browser over an HTML popup.
    await page.waitForTimeout(100);
    expect(shows()).toHaveLength(before);
    if (dismiss === 'escape') await page.keyboard.press('Escape');
    else if (dismiss === 'outside') await page.locator('#task').click();
    else if (dismiss === 'resize') await page.setViewportSize({ width: 1300, height: 900 });
    else await menu.locator('[role="menuitem"][data-action="close-others"]:visible').click();
    await expect(menu).toBeHidden();
    await expect.poll(visible).toBe(true);
  }
  expect(app.pageErrors).toEqual([]);
});

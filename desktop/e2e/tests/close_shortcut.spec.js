import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

// Replace only Proton's transport. The real shell, DOM focus, and xterm run
// in Chromium; macOS menu key-equivalent handling still needs a native test.
async function installDesktop(page, systemDark = false) {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  app.channel = 'local';
  app.systemDark = systemDark;
  let terminalId = 0;
  await page.exposeFunction('desktopRequest', request => {
    app.requests.push(request);
    if (request.method === 'app.system_appearance') {
      return { dark: app.systemDark };
    }
    if (request.method === 'terminal.open') return { id: `terminal-${++terminalId}` };
    return app.replyFor(request);
  });
  await page.addInitScript(() => {
    const listeners = new Map();
    const events = {
      on(name, callback) {
        const callbacks = listeners.get(name) || new Set();
        listeners.set(name, callbacks);
        callbacks.add(callback);
        return () => callbacks.delete(callback);
      },
    };
    window.desktopEvent = (name, payload) => {
      for (const callback of listeners.get(name) || []) callback({ payload });
    };
    window.titlebarArea = null;
    window.__MoonBit__ = {
      getTitlebarArea: async () => window.titlebarArea,
      app: events,
      events,
      openseek: new Proxy({}, {
        get: (_, method) => async params => {
          if (method === 'host.connect') {
            window.desktopEvent('openseek.agent.connected', { protocol: 5 });
          }
          return window.desktopRequest({ method, params });
        },
      }),
    };
  });
  await page.goto('/index.html');
  await app.openSession();
  return app;
}

async function closeFocused(page) {
  await page.evaluate(() => window.desktopEvent('menu.command', {
    command_id: 'app.close_focused',
  }));
}

test('native browser notifications cross the local bridge with navigation and failure semantics intact', async ({ page }) => {
  const app = await installDesktop(page);
  const notify = payload => page.evaluate(value => {
    window.desktopEvent('openseek.browser.event', value);
  }, payload);
  const url = 'https://example.test/start';
  await notify({ kind: 'open_requested', request: 'browser-request', session: 'session-1', url });
  await expect.poll(() => app.requests.filter(request => request.method === 'browser.open').length).toBe(1);
  const opened = app.requests.find(request => request.method === 'browser.open').params;
  expect(opened).toMatchObject({ request: 'browser-request', session: 'session-1', url });
  const id = opened.id;
  const address = page.locator('#browser-address-input');
  const tab = page.locator('.editor-tab.active .tab-name');
  const reload = page.locator('#browser-reload');
  const failure = page.locator('.browser-failure');
  await expect(address).toHaveValue(url);
  await notify({ kind: 'title', id, title: 'Example browser page' });
  await expect(tab).toHaveText('Example browser page');
  await notify({ kind: 'loading', id, loading: false });
  await expect(reload).not.toHaveClass(/loading/);
  await notify({ kind: 'load_failed', id, url, code: -102, text: 'ERR_CONNECTION_REFUSED' });
  await expect(failure).toContainText('ERR_CONNECTION_REFUSED');

  const next = 'https://example.test/next';
  await notify({ kind: 'navigated', id, url: next });
  await expect(address).toHaveValue(next);
  await expect(failure).toBeHidden();
  await notify({ kind: 'loading', id, loading: true });
  await expect(reload).toHaveClass(/loading/);
  await notify({ kind: 'load_failed', id, url: next, code: -3, text: 'ERR_ABORTED' });
  // Malformed and unsupported events must not mutate state or allocate a tab.
  for (const payload of [
    { kind: 'navigated', id, url: 7 },
    { kind: 'title', id, title: null },
    { kind: 'open_requested', session: 'session-1', url },
    { kind: 'closed', id },
    { kind: 'found_in_page', id },
    { kind: 'future', id },
  ]) await notify(payload);
  await notify({ kind: 'loading', id, loading: false, future: 'ignored' });
  await expect(reload).not.toHaveClass(/loading/);
  await expect(address).toHaveValue(next);
  await expect(failure).toBeHidden();
  expect(app.requests.filter(request => request.method === 'browser.open')).toHaveLength(1);

  await notify({ kind: 'renderer_process_terminated', id, url: next, code: -3, text: 'Fixture renderer stopped' });
  await expect(failure).toContainText('Fixture renderer stopped');
  await reload.click();
  await expect.poll(() => app.requests.filter(request => request.method === 'browser.reload').length).toBe(1);
  await page.locator('.editor-tab.active .tab-close').click();
  await expect(page.locator('.editor-tab')).toHaveCount(0);
  await expect.poll(() => app.requests.filter(request => request.method === 'browser.close').map(request => request.params.id)).toEqual([id]);
  expect(app.pageErrors).toEqual([]);
});

test('fixed sidebar toggle respects native geometry across pages and fullscreen', async ({ page }) => {
  const app = await installDesktop(page);
  const toggle = page.locator('#sidebar-toggle');
  const desktopToggle = await toggle.boundingBox();
  await page.evaluate(() => {
    // The configured macOS buttons sit at y=16 with a 14pt height. Proton
    // reserves equal space above and below them: 16 + 14 + 16 = 46.
    window.titlebarArea = { x: 88, y: 0, width: innerWidth - 88, height: 46 };
    window.desktopEvent('openseek.window.chrome_changed', {});
  });
  await expect.poll(async () => (await toggle.boundingBox()).x).toBe(88);
  await expect.poll(async () => {
    const box = await toggle.boundingBox();
    return box.y + box.height / 2;
  }).toBe(23);
  const original = await toggle.elementHandle();
  for (const name of ['Hide sidebar', 'Show sidebar']) {
    await expect(toggle).toHaveAccessibleName(name);
    const frames = await toggle.evaluate(button => new Promise(resolve => {
      const positions = [button.getBoundingClientRect().x];
      const start = performance.now();
      button.click();
      const sample = now => {
        positions.push(button.getBoundingClientRect().x);
        if (now - start < 250) requestAnimationFrame(sample);
        else resolve(positions);
      };
      requestAnimationFrame(sample);
    }));
    expect(frames.every(x => x === 88)).toBe(true);
  }
  await page.locator('#right-panel-toggle[aria-expanded="false"]').click();
  await page.locator('#panel-expand').click();
  await expect(toggle).toBeVisible();
  await expect(toggle).toHaveAccessibleName('Show sidebar');
  await expect(page.locator('.app > aside')).toBeHidden();
  await expect.poll(async () => (await toggle.boundingBox()).x).toBe(88);
  await page.locator('#right-panel-toggle[aria-expanded="true"]').click();
  await toggle.click();
  await page.locator('#sidebar-settings').click();
  await expect(page.locator('#management-settings')).toBeVisible();
  await expect(toggle).toHaveCount(1);
  expect(await original.evaluate(button => button.isConnected)).toBe(true);
  await page.setViewportSize({ width: 640, height: 850 });
  await expect.poll(async () => (await toggle.boundingBox()).x).toBe(88);
  await page.evaluate(() => {
    window.titlebarArea = null;
    window.desktopEvent('openseek.window.chrome_changed', {});
  });
  // Without native chrome, narrow screens retain the desktop inset and size.
  await expect.poll(async () => {
    const { x, width, height } = await toggle.boundingBox();
    return { x, width, height };
  }).toEqual({
    x: desktopToggle.x,
    width: desktopToggle.width,
    height: desktopToggle.height,
  });
  await expect.poll(async () => {
    const box = await toggle.boundingBox();
    // `--app-header-height` is a calc() over the app font size, and a custom
    // property's computed value stays unresolved text; resolve it as a length.
    const headerHeight = await toggle.evaluate(button => {
      const probe = document.createElement('div');
      probe.style.height = 'var(--app-header-height)';
      button.closest('.app').append(probe);
      const height = probe.getBoundingClientRect().height;
      probe.remove();
      return height;
    });
    return box.y + box.height / 2 - headerHeight / 2;
  }).toBe(0);
  await page.locator('#management-dialog')
    .locator('[data-slot="dialog-close"]').click();
  // A real click must reach the fixed control above the narrow drawer.
  await toggle.click();
  await expect(toggle).toHaveAccessibleName('Hide sidebar');
  await toggle.click();
  await expect(toggle).toHaveAccessibleName('Show sidebar');
  expect(app.pageErrors).toEqual([]);
});

test('Launcher tabs receive focus and Close never closes the window', async ({ page }) => {
  const app = await installDesktop(page);
  app.gitChanges = [];
  const tabs = page.locator('.editor-tab');
  for (const action of ['review', 'files', 'search']) {
    await page.locator('#right-panel-toggle[aria-expanded="false"]').click();
    await page.locator(`.dock-launcher-menu [data-dock-action="${action}"]`).click();
    await expect(tabs).toHaveCount(1);
    if (action === 'review') {
      await expect(page.locator('.file-panel-empty')).toBeVisible();
    }
    if (action === 'search') {
      await expect(page.locator('#workspace-search-input')).toBeFocused();
    }
    await closeFocused(page);
    await expect(tabs).toHaveCount(0);
    await expect(page.locator('#right-panel-toggle[aria-expanded="false"]')).toBeVisible();
  }
  expect(app.requests.filter(request => request.method === 'app.close_window')).toEqual([]);
  expect(app.pageErrors).toEqual([]);
});

test('Selecting a dock tab moves focus out of the composer', async ({ page }) => {
  const app = await installDesktop(page);
  await page.locator('#right-panel-toggle[aria-expanded="false"]').click();
  await page.locator('.dock-launcher-menu [data-dock-action="review"]').click();
  const review = page.locator('.editor-tab[data-action-menu-context$=":picker"]');
  await page.locator('#dock-new-tab').click();
  await page.locator('#dock-new-tab-menu')
    .locator('[data-dock-action="browser"]').click();
  await page.locator('#task').click();
  await review.click();
  // Tabs are now keyboard targets for their context menus. Selecting one
  // keeps focus on that tab, inside the dock's Close shortcut scope.
  await expect(review).toBeFocused();
  await page.locator('#task').click();
  await review.click();
  await expect(review).toBeFocused();
  await closeFocused(page);
  await expect(review).toHaveCount(0);
  await expect(page.locator('.editor-tab')).toHaveCount(1);
  await closeFocused(page);
  await expect(page.locator('.editor-tab')).toHaveCount(0);
  expect(app.requests.filter(request => request.method === 'app.close_window')).toEqual([]);
});

test('Close follows terminal focus and keeps the remaining terminal usable', async ({ page }) => {
  const app = await installDesktop(page);
  const requests = method => app.requests.filter(request => request.method === method);
  await page.keyboard.press('Control+Backquote');
  const input = page.locator('.terminal-instance:visible .xterm-helper-textarea');
  await expect(input).toBeFocused();
  await expect.poll(() => requests('terminal.open').length).toBe(1);
  await page.locator('#terminal-new').click();
  await expect.poll(() => requests('terminal.open').length).toBe(2);
  await expect(input).toBeFocused();

  await closeFocused(page);
  await expect(page.locator('.terminal-tab')).toHaveCount(1);
  await expect(input).toBeFocused();
  await expect.poll(() => requests('terminal.close').map(request => request.params.id))
    .toEqual(['terminal-2']);
  await page.keyboard.type('pwd');
  await expect.poll(() => requests('terminal.input')
    .filter(request => request.params.id === 'terminal-1')
    .map(request => request.params.data).join('')).toBe('pwd');

  await closeFocused(page);
  await expect(page.locator('.terminal-tab')).toHaveCount(0);
  await expect(input).toHaveCount(0);
  await expect.poll(() => requests('terminal.close').map(request => request.params.id))
    .toEqual(['terminal-2', 'terminal-1']);
  expect(requests('terminal.open')).toHaveLength(2);
  expect(requests('app.close_window')).toHaveLength(0);

  await page.locator('#task').click();
  await closeFocused(page);
  await expect.poll(() => requests('app.close_window').length).toBe(1);
  expect(app.pageErrors).toEqual([]);
});

// A native dialog can change CEF's media query without changing OS appearance.
test('desktop theme follows Proton and ignores browser color-scheme changes', async ({ page }) => {
  await page.emulateMedia({ colorScheme: 'light' });
  const app = await installDesktop(page, true);
  const root = page.locator('html');
  await expect(root).toHaveAttribute('data-theme', 'dark');
  await page.emulateMedia({ colorScheme: 'dark' });
  await page.emulateMedia({ colorScheme: 'light' });
  await expect(root).toHaveAttribute('data-theme', 'dark');
  app.systemDark = false;
  await page.evaluate(() => window.desktopEvent('openseek.app.system_appearance_changed', {}));
  await expect(root).toHaveAttribute('data-theme', 'light');
  await page.locator('#sidebar-settings').click();
  await page.locator('#theme-select').click();
  await page.locator('#theme-select-menu [data-value="dark"]').click();
  await expect(root).toHaveAttribute('data-theme', 'dark');
  const queries = () => app.requests.filter(r => r.method === 'app.system_appearance').length;
  const before = queries();
  await page.evaluate(() => window.desktopEvent('openseek.app.system_appearance_changed', {}));
  await expect.poll(queries).toBe(before + 1);
  await expect(root).toHaveAttribute('data-theme', 'dark');
  await page.locator('#theme-select').click();
  await page.locator('#theme-select-menu [data-value="system"]').click();
  await expect(root).toHaveAttribute('data-theme', 'light');
  await page.reload();
  await expect.poll(queries).toBe(before + 2);
  await expect(root).toHaveAttribute('data-theme', 'light');
  expect(app.pageErrors).toEqual([]);
});

test('web theme follows the browser without querying native appearance', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await page.emulateMedia({ colorScheme: 'dark' });
  await app.goto();
  await app.openSession();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
  await page.emulateMedia({ colorScheme: 'light' });
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'light');
  expect(app.requests.some(r => r.method === 'app.system_appearance')).toBe(false);
  expect(app.pageErrors).toEqual([]);
});

test('titlebar geometry ignores stale replies and preserves the last valid area on errors', async ({ page }) => {
  const app = await installDesktop(page);
  const errors = [];
  page.on('console', message => {
    if (message.type() === 'error') errors.push(message.text());
  });
  const root = page.locator('html');
  const leftInset = () => root.evaluate(element => element.style.getPropertyValue('--native-titlebar-left'));
  await page.evaluate(() => {
    window.titlebarArea = { x: 88, y: 0, width: innerWidth - 88, height: 46 };
    window.desktopEvent('openseek.window.chrome_changed', {});
  });
  await expect.poll(leftInset).toBe('88px');
  await page.evaluate(() => {
    window.titlebarReads = [];
    window.__MoonBit__.getTitlebarArea = () => new Promise((resolve, reject) => {
      window.titlebarReads.push({ resolve, reject });
    });
    window.desktopEvent('openseek.window.chrome_changed', {});
  });
  await expect.poll(() => page.evaluate(() => window.titlebarReads.length)).toBe(1);
  await page.evaluate(() => {
    window.desktopEvent('openseek.window.chrome_changed', {});
    window.titlebarReads[0].resolve(null);
  });
  await expect.poll(() => page.evaluate(() => window.titlebarReads.length)).toBe(2);
  expect(await leftInset()).toBe('88px');
  await page.evaluate(() => window.titlebarReads[1].resolve({
    x: 96, y: 0, width: innerWidth - 96, height: 46,
  }));
  await expect.poll(leftInset).toBe('96px');
  for (const failure of ['reject', 'malformed']) {
    const before = await page.evaluate(() => window.titlebarReads.length);
    await page.evaluate(() => window.desktopEvent('openseek.window.chrome_changed', {}));
    await expect.poll(() => page.evaluate(() => window.titlebarReads.length)).toBe(before + 1);
    const errorsBefore = errors.length;
    await page.evaluate(failure => {
      const read = window.titlebarReads.at(-1);
      if (failure === 'reject') read.reject(new Error('fixture query failure'));
      else read.resolve({ x: 0, y: 0, width: 0, height: 46 });
    }, failure);
    await expect.poll(() => errors.length).toBe(errorsBefore + 1);
    expect(await leftInset()).toBe('96px');
    await expect(root).toHaveClass(/native-titlebar-overlay/);
  }
  const before = await page.evaluate(() => window.titlebarReads.length);
  await page.evaluate(() => window.desktopEvent('openseek.window.chrome_changed', {}));
  await expect.poll(() => page.evaluate(() => window.titlebarReads.length)).toBe(before + 1);
  await page.evaluate(() => window.titlebarReads.at(-1).resolve(null));
  await expect.poll(leftInset).toBe('');
  await expect(root).not.toHaveClass(/native-titlebar-overlay/);
  expect(app.pageErrors).toEqual([]);
});

import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

// Replace only Proton's transport. The real shell, DOM focus, and xterm run
// in Chromium; macOS menu key-equivalent handling still needs a native test.
async function installDesktop(page) {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  let terminalId = 0;
  await page.exposeFunction('desktopRequest', request => {
    app.requests.push(request);
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
            window.desktopEvent('openseek.agent.connected', { stage: 'serving' });
          }
          return window.desktopRequest({ method, params });
        },
      }),
    };
  });
  await page.goto('/dist/browser/index.html');
  await app.openSession();
  return app;
}

async function closeFocused(page) {
  await page.evaluate(() => window.desktopEvent('menu.command', {
    command_id: 'app.close_focused',
  }));
}

test('fixed sidebar toggle respects native geometry across pages and fullscreen', async ({ page }) => {
  const app = await installDesktop(page);
  const toggle = page.getByRole('button', { name: /^(Hide|Show) sidebar$/ });
  await page.evaluate(() => {
    window.titlebarArea = { x: 88, y: 0, width: innerWidth - 88, height: 32 };
    window.desktopEvent('openseek.window.chrome_changed', {});
  });
  await expect.poll(async () => (await toggle.boundingBox()).x).toBe(88);
  await expect.poll(async () => {
    const box = await toggle.boundingBox();
    return box.y + box.height / 2;
  }).toBe(16);
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
  await page.getByRole('button', { name: 'Show panel', exact: true }).click();
  await page.getByRole('button', { name: 'Expand panel', exact: true }).click();
  await expect(toggle).toBeVisible();
  await toggle.click();
  await expect(toggle).toHaveAccessibleName('Show sidebar');
  await expect.poll(async () => (await toggle.boundingBox()).x).toBe(88);
  await page.getByRole('button', { name: 'Hide panel', exact: true }).click();
  await toggle.click();
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Settings', exact: true })).toBeVisible();
  await expect(toggle).toHaveCount(1);
  expect(await original.evaluate(button => button.isConnected)).toBe(true);
  await page.setViewportSize({ width: 640, height: 850 });
  await expect.poll(async () => (await toggle.boundingBox()).x).toBe(88);
  await page.evaluate(() => {
    window.titlebarArea = null;
    window.desktopEvent('openseek.window.chrome_changed', {});
  });
  await expect.poll(async () => (await toggle.boundingBox()).x).toBe(8);
  await expect.poll(async () => {
    const box = await toggle.boundingBox();
    const headerHeight = await toggle.evaluate(button =>
      parseFloat(getComputedStyle(button.closest('.app')).getPropertyValue('--app-header-height')));
    return box.y + box.height / 2 - headerHeight / 2;
  }).toBe(0);
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
  for (const name of ['Review', 'Files', 'Search']) {
    await page.getByRole('button', { name: 'Show panel', exact: true }).click();
    await page.getByRole('button', { name: new RegExp(`^${name} `) }).click();
    await expect(tabs).toHaveCount(1);
    if (name === 'Review') {
      await expect(page.getByText('No changed files.', { exact: true })).toBeVisible();
    }
    if (name === 'Search') {
      await expect(page.locator('#workspace-search-input')).toBeFocused();
    }
    await closeFocused(page);
    await expect(tabs).toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Show panel', exact: true })).toBeVisible();
  }
  expect(app.requests.filter(request => request.method === 'app.close_window')).toEqual([]);
  expect(app.pageErrors).toEqual([]);
});

test('Selecting a dock tab moves focus out of the composer', async ({ page }) => {
  const app = await installDesktop(page);
  await page.getByRole('button', { name: 'Show panel', exact: true }).click();
  await page.getByRole('button', { name: /^Review / }).click();
  const review = page.locator('.editor-tab', { hasText: 'Review Changes' });
  await page.getByTitle('New tab', { exact: true }).click();
  await page.getByRole('button', { name: /^Browse / }).click();
  await page.locator('#task').click();
  await review.click();
  await expect(page.locator('.content.panel-open > .editor')).toBeFocused();
  await page.locator('#task').click();
  await review.click();
  await expect(page.locator('.content.panel-open > .editor')).toBeFocused();
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
  await page.getByTitle('New terminal in this workspace', { exact: true }).click();
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

test('Close respects dialogs and closes successive dock tabs without closing the window', async ({ page }) => {
  const app = await installDesktop(page);
  await app.openQuickOpen();
  await page.locator('#quick-open-input').fill('main');
  await page.getByRole('option', { name: /main\.mbt/ }).click();
  const tabs = page.locator('.editor-tab');
  await expect(tabs).toHaveCount(1);
  await expect(page.getByRole('region', { name: 'Readonly code viewer' })).toBeVisible();
  await page.getByTitle('New tab', { exact: true }).click();
  await page.getByRole('button', { name: /^Browse/ }).click();
  await expect(tabs).toHaveCount(2);

  await app.openQuickOpen();
  await expect(page.locator('#quick-open-input')).toBeFocused();
  await closeFocused(page);
  await expect(page.locator('#quick-open-input')).toBeFocused();
  await page.keyboard.press('Escape');
  // A tab's close button will disappear on close. Focus must remain in the
  // dock for the next command, instead of falling back to the window.
  await tabs.last().locator('.tab-close').focus();
  await closeFocused(page);
  await expect(tabs).toHaveCount(1);
  await expect(page.locator('.content.panel-open > .editor')).toBeFocused();
  await closeFocused(page);
  await expect(tabs).toHaveCount(0);
  await expect(page.locator('.content.panel-open')).toHaveCount(0);
  expect(app.requests.filter(request => request.method === 'app.close_window'))
    .toHaveLength(0);
  expect(app.pageErrors).toEqual([]);
});

import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';
import { CloudHarness, authOrigin } from './support/cloud_harness.js';

// Exercise the browser packager's normal HTML, CSS and frontend bundle.
// Only the remote account and host responses contain fixture data.
async function installConsole(page) {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  return app;
}

test.use({ viewport: { width: 393, height: 851 }, isMobile: true, hasTouch: true });

test('phone conversation sends once, stops and reconnects without repeating the send', async ({ page }) => {
  const app = await installConsole(page);
  await app.goto();
  await expect(page.locator('#transcript')).toHaveAttribute('data-transcript-session', /.+/);
  await page.locator('.sidebar-toggle').click();
  await app.openSession();
  await expect(page.locator('.app')).toHaveClass(/sidebar-collapsed/);
  await page.locator('#task').fill('Continue from my phone');
  await page.locator('#send').click();
  await expect.poll(() => app.requests.filter(r => r.method === 'agent.start').length).toBe(1);
  await page.locator('#stop').click();
  await expect.poll(() => app.requests.filter(r => r.method === 'agent.cancel').length).toBe(1);
  const oldSocket = app.socket;
  oldSocket.close({ code: 1001, reason: 'fixture network transition' });
  await expect.poll(() => app.socket !== oldSocket, { timeout: 15000 }).toBe(true);
  await expect(page.locator('#task')).toBeEnabled();
  expect(app.requests.filter(r => r.method === 'agent.start')).toHaveLength(1);
  await page.locator('#task').fill('Unsent draft after reconnection');
  expect(app.pageErrors).toEqual([]);
});

test('Back closes the topmost layer first and reports when none is open', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.gitBranch = { branch: 'phone/back', diffstat: { added: 1, removed: 0, files: 1, partial: false } };
  await app.install();
  await app.goto();
  await expect(page.locator('#transcript')).toHaveAttribute('data-transcript-session', /.+/);
  // The Android shell's Back: true exactly when a layer took it.
  const back = () => page.evaluate(() => !document.dispatchEvent(new Event('openseek-back', { cancelable: true })));
  expect(await back()).toBe(false);
  await page.locator('.sidebar-toggle').click();
  await expect(page.locator('.sidebar-backdrop')).toHaveClass(/open/);
  await page.locator('.workspace-row').first().click({ button: 'right', position: { x: 24, y: 16 } });
  const menu = page.getByRole('menu');
  await expect(menu).toBeVisible();
  // The menu opened over the drawer, so it closes first.
  expect(await back()).toBe(true);
  await expect(menu).toBeHidden();
  await expect(page.locator('.sidebar-backdrop')).toHaveClass(/open/);
  expect(await back()).toBe(true);
  await expect(page.locator('.app')).toHaveClass(/sidebar-collapsed/);
  expect(await back()).toBe(false);
  // Escape reaches the same layers from a keyboard, including the Git menu,
  // which has no Escape handling of its own.
  await page.locator('.sidebar-toggle').click();
  await app.openSession();
  await expect(page.locator('.app')).toHaveClass(/sidebar-collapsed/);
  await page.locator('.composer-git-button').click();
  await expect(page.locator('.composer-git-menu')).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(page.locator('.composer-git-menu')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('a browser close request closes one layer at a time, as Back does in an installed web app', async ({ page, browserName }) => {
  test.skip(browserName !== 'chromium', 'CloseWatcher is Chromium-only');
  const app = await installConsole(page);
  await app.goto();
  await expect(page.locator('#transcript')).toHaveAttribute('data-transcript-session', /.+/);
  // Escape is Chromium's desktop close request. Hiding it from the page's
  // listeners leaves only the close request, which is what Android's Back
  // sends an installed web app.
  await page.evaluate(() => addEventListener('keydown', event => {
    if (event.key === 'Escape') event.stopImmediatePropagation();
  }, true));
  await page.locator('.sidebar-toggle').click();
  await expect(page.locator('.sidebar-backdrop')).toHaveClass(/open/);
  await page.locator('.workspace-row').first().click({ button: 'right', position: { x: 24, y: 16 } });
  const menu = page.getByRole('menu');
  await expect(menu).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(menu).toBeHidden();
  await expect(page.locator('.sidebar-backdrop')).toHaveClass(/open/);
  await page.keyboard.press('Escape');
  await expect(page.locator('.app')).toHaveClass(/sidebar-collapsed/);
  expect(app.pageErrors).toEqual([]);
});

test('a held, modified or consumed Escape closes only what one press would', async ({ page }) => {
  const app = await installConsole(page);
  await app.goto();
  await expect(page.locator('#transcript')).toHaveAttribute('data-transcript-session', /.+/);
  await page.locator('.sidebar-toggle').click();
  const drawer = page.locator('.sidebar-backdrop');
  await expect(drawer).toHaveClass(/open/);
  // The drawer has no Escape handling of its own; only Back closes it.
  await page.keyboard.press('Shift+Escape');
  await expect(drawer).toHaveClass(/open/);
  // A focused control that consumes Escape by stopping it keeps it.
  const search = page.locator('#session-search-input');
  await search.evaluate(input => input.addEventListener('keydown', event => {
    if (event.key === 'Escape') event.stopPropagation();
  }));
  await search.focus();
  await page.keyboard.press('Escape');
  await expect(drawer).toHaveClass(/open/);
  await page.locator('.workspace-row').first().click({ button: 'right', position: { x: 24, y: 16 } });
  const menu = page.getByRole('menu');
  await expect(menu).toBeVisible();
  // The second keydown of a held key repeats.
  await page.keyboard.down('Escape');
  await page.keyboard.down('Escape');
  await page.keyboard.up('Escape');
  await expect(menu).toBeHidden();
  await expect(drawer).toHaveClass(/open/);
  expect(app.pageErrors).toEqual([]);
});

test('engine-start failures preserve their full diagnostic and restore the draft', async ({ page }) => {
  const app = await installConsole(page);
  const failure = 'Engine failed to start: invalid option\nUsage: openseek serve [OPTIONS]\n' +
    '--session-root <directory> Directory containing durable sessions.\n'.repeat(65);
  app.rpcErrors.set('agent.start', failure);
  await app.goto();
  await expect(page.locator('#transcript')).toHaveAttribute('data-transcript-session', /.+/);
  await page.locator('.sidebar-toggle').click();
  await app.openSession();
  await expect(page.locator('.app')).toHaveClass(/sidebar-collapsed/);
  await page.locator('#task').fill('Retryable draft');
  await page.locator('#send').click();
  const notice = page.locator('.notifications > .notification');
  await expect(notice).toBeVisible();
  await expect(notice).toHaveText(failure);
  await expect(page.locator('#task')).toHaveValue('Retryable draft');
  await notice.click();
  await expect(notice).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('Cloud conversation sends once and preserves a multiline follow-up draft', async ({ page }) => {
  const cloud = new CloudHarness(page);
  await cloud.install();
  await page.goto(`${authOrigin}/cloud`);
  await expect(page.locator('#task')).toBeEnabled();
  await page.locator('#task').fill('A mobile browser Cloud message');
  await page.locator('#send').click();
  await expect(page.locator('#transcript').getByText('您好 🌙 — calculation complete.', { exact: true })).toHaveCount(1);
  await expect(page.locator('#task')).toHaveValue('');
  await page.locator('#task').fill('An unsent follow-up\nwith a second line\nand a third line');
  await expect(page.locator('#task')).toHaveValue('An unsent follow-up\nwith a second line\nand a third line');
  await expect(page.locator('#send')).toBeEnabled();
  expect(cloud.postCount).toBe(1);
  expect(cloud.device.ticketRequests).toHaveLength(0);
  expect(cloud.device.socket).toBeNull();
  expect(cloud.device.pageErrors).toEqual([]);
});

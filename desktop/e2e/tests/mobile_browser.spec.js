import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';
import { CloudHarness, authOrigin, sessionA } from './support/cloud_harness.js';

// Exercise the browser packager's normal HTML, CSS and frontend bundle.
// Only the remote account and host responses contain fixture data.
async function installConsole(page) {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  return app;
}

async function assertFits(page) {
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
}

test.use({ viewport: { width: 393, height: 851 }, isMobile: true, hasTouch: true });

test('phone conversation sends once, stops, reconnects and keeps the composer visible when the available viewport height shrinks', async ({ page }) => {
  const app = await installConsole(page);
  await app.goto();
  // Layout checks begin after the initial conversation has finished activating.
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
  await page.setViewportSize({ width: 393, height: 480 });
  await page.locator('#task').fill('Unsent draft after reconnection');
  await assertFits(page);
  const box = await page.locator('#task').boundingBox();
  expect(box.y + box.height).toBeLessThanOrEqual(480);
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
  const menu = page.getByRole('menu', { name: 'Workspace actions' });
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
});

test('long engine-start failures remain readable within the phone viewport and restore the draft', { tag: '@webkit-layout' }, async ({ page }) => {
  const app = await installConsole(page);
  const failure = 'Engine failed to start: invalid option\nUsage: openseek serve [OPTIONS]\n' +
    '--session-root <directory> Directory containing durable sessions.\n'.repeat(65);
  app.rpcErrors.set('agent.start', failure);
  await app.goto();
  // Layout checks begin after the initial conversation has finished activating.
  await expect(page.locator('#transcript')).toHaveAttribute('data-transcript-session', /.+/);
  await page.locator('.sidebar-toggle').click();
  await app.openSession();
  await expect(page.locator('.app')).toHaveClass(/sidebar-collapsed/);
  await page.locator('#task').fill('Retryable draft');
  await page.locator('#send').click();
  const notice = page.locator('.notification').filter({ hasText: 'Engine failed to start' });
  await expect(notice).toBeVisible();
  await expect(page.locator('#task')).toHaveValue('Retryable draft');
  const bounds = await notice.boundingBox();
  expect(bounds.y).toBeGreaterThanOrEqual(0);
  expect(bounds.height).toBeLessThanOrEqual(851 * 0.4);
  const task = await page.locator('#task').boundingBox();
  expect(bounds.y + bounds.height).toBeLessThanOrEqual(task.y);
  const header = await page.locator('.topbar').boundingBox();
  expect(bounds.y).toBeGreaterThanOrEqual(header.y + header.height);
  await expect(notice).toHaveCSS('overflow-y', 'auto');
  await expect(notice).toHaveCSS('white-space', 'pre-wrap');
  await page.setViewportSize({ width: 393, height: 480 });
  const reduced = await notice.boundingBox();
  const reducedTask = await page.locator('#task').boundingBox();
  expect(reduced.y + reduced.height).toBeLessThanOrEqual(reducedTask.y);
  await notice.click();
  await expect(notice).toHaveCount(0);
});

for (const viewport of [
  { width: 393, height: 851 },
  { width: 851, height: 393 },
]) {
  test(`conversation and drawer fit ${viewport.width}x${viewport.height}`, { tag: '@webkit-layout' }, async ({ page }) => {
    await page.setViewportSize(viewport);
    const app = await installConsole(page);
    await app.goto();
    // Initial host activation is navigation and closes a phone drawer.
    await expect(page.locator('#transcript')).toHaveAttribute('data-transcript-session', /.+/);
    if (viewport.width <= 760) await page.locator('.sidebar-toggle').click();
    await app.openSession();
    await page.locator('#task').fill('An unsent mobile browser draft');
    await assertFits(page);
    for (const selector of ['.topbar', '#task', '#send']) {
      const box = await page.locator(selector).boundingBox();
      expect(box.x).toBeGreaterThanOrEqual(0);
      expect(box.y).toBeGreaterThanOrEqual(0);
      expect(box.x + box.width).toBeLessThanOrEqual(viewport.width + 1);
      expect(box.y + box.height).toBeLessThanOrEqual(viewport.height + 1);
    }
    if (viewport.width <= 760) {
      await page.locator('.sidebar-toggle').click();
      await expect(page.locator('.sidebar-backdrop')).toHaveClass(/open/);
      const mode = await page.locator('.sidebar-mode').boundingBox();
      const option = await page.locator('.sidebar-mode-option').first().boundingBox();
      expect(option.y).toBeGreaterThanOrEqual(mode.y);
      expect(option.y + option.height).toBeLessThanOrEqual(mode.y + mode.height);
      await page.locator('.sidebar-backdrop').click({ position: { x: viewport.width - 5, y: 100 } });
      await expect(page.locator('.app')).toHaveClass(/sidebar-collapsed/);
    }
    await expect(page.locator('#task')).toHaveValue('An unsent mobile browser draft');
  });
}

test('signed-out entry fits a phone viewport', { tag: '@webkit-layout' }, async ({ page }) => {
  await page.setViewportSize({ width: 393, height: 851 });
  await installConsole(page);
  await page.route('**/v2/auth/me', route => route.fulfill({ status: 401 }));
  await page.goto('/device/device-a/chat');
  const login = page.getByRole('link', { name: 'Sign in', exact: true });
  await expect(login).toBeVisible();
  await assertFits(page);
  const box = await login.boundingBox();
  expect(box.height).toBeGreaterThanOrEqual(44);
  expect(box.x + box.width).toBeLessThanOrEqual(393);
});

test('Cloud conversation fits a small phone and a multiline draft survives a height change', { tag: '@webkit-layout' }, async ({ page }) => {
  await page.setViewportSize({ width: 393, height: 851 });
  const cloud = new CloudHarness(page);
  // Cloud must work with none of the account's devices reachable.
  cloud.device.connectionAvailable = false;
  await cloud.install();
  await page.goto(`${authOrigin}/cloud`);
  await expect(page.locator('#task')).toBeEnabled();
  await page.locator('#task').fill('A mobile browser Cloud message');
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect(page.locator('#transcript').getByText('您好 🌙 — calculation complete.', { exact: true })).toHaveCount(1);
  await expect(page.locator('#task')).toHaveValue('');
  await page.locator('#task').fill('An unsent follow-up\nwith a second line\nand a third line');
  await page.setViewportSize({ width: 393, height: 480 });
  await assertFits(page);
  for (const selector of ['#task', '#send']) {
    const box = await page.locator(selector).boundingBox();
    expect(box.y).toBeGreaterThanOrEqual(0);
    expect(box.y + box.height).toBeLessThanOrEqual(480);
    expect(box.x + box.width).toBeLessThanOrEqual(393);
  }
  await expect(page.locator('#task')).toHaveValue('An unsent follow-up\nwith a second line\nand a third line');
  await expect(page.getByRole('button', { name: 'Send', exact: true })).toBeEnabled();
  expect(cloud.postCount).toBe(1);
  expect(cloud.device.socket).toBeNull();
});

test.describe('Cloud ask_user on a phone', () => {
  // The bundled apps run the shared frontend without a desktop bridge.
  test.use({ userAgent: 'Mozilla/5.0 (iPhone) Mobile SeekMoonIOS/0.1.0' });

  async function openChat(page) {
    const app = new CloudHarness(page);
    app.device.connectionAvailable = false;
    await app.install();
    await page.goto(`${authOrigin}/cloud/session/${sessionA}`);
    await expect.poll(() => app.mcpFrames.filter(f => f.session === sessionA && f.frame.type === 'auth').length).toBe(1);
    return app;
  }

  function request(app, id, method, params) {
    app.mcpSockets.get(sessionA).send(JSON.stringify({ jsonrpc: '2.0', id, method, params }));
  }

  function reply(app, id) {
    return app.mcpFrames.find(f => f.session === sessionA && f.frame.id === id)?.frame.result;
  }

  function ask(app, id) {
    request(app, id, 'tools/call', { name: 'ask_user', arguments: {
      questions: [{ id: 'plan', title: 'Which plan?', options: ['Small change'] }],
    } });
  }

  test('discovers ask_user and returns a choice over MCP @webkit-layout', async ({ page }) => {
    const app = await openChat(page);
    request(app, 1, 'tools/list', {});
    await expect.poll(() => reply(app, 1)?.tools.map(t => t.name)).toEqual(['ask_user']);
    ask(app, 2);
    const card = page.locator('.user-question-card');
    await expect(card).toContainText('Which plan?');
    await card.getByRole('button', { name: 'Small change', exact: true }).click();
    await card.getByRole('button', { name: 'Send', exact: true }).click();
    await expect.poll(() => reply(app, 2)?.content[0].text).toBeTruthy();
    expect(JSON.parse(reply(app, 2).content[0].text)).toMatchObject({ status: 'answered', answers: { plan: 'Small change' } });
    await expect(card).toHaveCount(0);
    expect(app.requests.filter(r => r.path.endsWith('/commands'))).toHaveLength(0);
  });

  for (const reason of ['timeout', 'disconnect']) {
    test(`delivers a late answer once after ${reason}`, async ({ page }) => {
      if (reason === 'timeout') await page.clock.install();
      const app = await openChat(page);
      ask(app, 3);
      const card = page.locator('.user-question-card');
      await expect(card).toContainText('Which plan?');
      await card.locator('textarea').fill('Keep the existing layout');
      if (reason === 'timeout') {
        await page.clock.fastForward(31_000);
        await expect.poll(() => reply(app, 3)?.content[0].text).toBeTruthy();
        expect(JSON.parse(reply(app, 3).content[0].text).status).toBe('pending');
      } else {
        app.mcpSockets.get(sessionA).close({ code: 1012, reason: 'fixture restart' });
        await expect.poll(() => app.mcpFrames.filter(f => f.session === sessionA && f.frame.type === 'auth').length).toBe(2);
      }
      await card.getByRole('button', { name: 'Send', exact: true }).click();
      const deliveries = () => app.requests.filter(r => r.path === `/v1/sessions/${sessionA}/commands` && r.method === 'POST');
      await expect.poll(() => deliveries().length).toBe(1);
      expect(JSON.parse(deliveries()[0].body).command).toMatchObject({ command: 'prompt', submission_id: expect.stringMatching(/^question-.*-result$/) });
      expect(deliveries()[0].body).toContain('Keep the existing layout');
      await expect(card).toHaveCount(0);
      if (reason === 'disconnect') expect(reply(app, 3)).toBeUndefined();
    });
  }
});

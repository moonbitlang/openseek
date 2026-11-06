import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

const path = suffix => `/device/device-a/${suffix}`;
const dialog = page => page.getByRole('dialog');

test('management dialogs preserve the work surface, draft and browser entry', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install(); await app.goto(); await app.openSession();
  await expect(page).toHaveURL(new RegExp(path('chat/session/session-1') + '$'));
  const composer = page.locator('#task');
  await composer.fill('Unsent input survives dialogs');
  const url = page.url();
  const entries = await page.evaluate(() => history.length);
  const originalComposer = await composer.elementHandle();
  for (const [entry, title] of [
    ['#sidebar-settings', 'Settings'],
    ['#sidebar-skills', 'Skills'],
    ['#sidebar-schedules', 'Scheduled tasks'],
  ]) {
    await page.locator(entry).click();
    await expect(dialog(page)).toHaveAccessibleName(title);
    await expect(dialog(page)).toBeVisible();
    await expect(page).toHaveURL(url);
    expect(await page.evaluate(() => history.length)).toBe(entries);
    expect(await originalComposer.evaluate(node => node.isConnected)).toBe(true);
    await dialog(page).locator('[data-slot="dialog-close"]').click();
    await expect(page.locator('#management-dialog')).not.toBeVisible();
    await expect(composer).toHaveValue('Unsent input survives dialogs');
  }
  expect(app.pageErrors).toEqual([]);
});

test('local console opens a session without a device query', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  let signInChecks = 0;
  await page.route('**/v2/auth/**', route => route.fulfill({ status: 404 }));
  await page.route('**/v1/auth/me', route => {
    signInChecks += 1;
    return route.fulfill({ contentType: 'application/json', body: JSON.stringify({ login: 'local' }) });
  });
  await page.route('**/v1/devices', route => route.fulfill({ contentType: 'application/json', body: JSON.stringify({ devices: [{ id: 'host', name: 'Local test host', online: true }] }) }));
  await page.routeWebSocket('**/v1/devices/host/ws', socket => {
    app.socketURLs.push(socket.url());
    socket.onMessage(async message => {
      const request = JSON.parse(message.toString()); app.requests.push(request);
      if (request.id !== undefined) socket.send(JSON.stringify({ jsonrpc: '2.0', id: request.id, result: await app.replyFor(request) }));
    });
    socket.send(JSON.stringify({ jsonrpc: '2.0', method: 'agent.connected', params: { protocol: app.hostProtocol } }));
  });
  await page.goto('/device/host/chat/session/session-1');
  await expect.poll(() => signInChecks).toBe(1);
  await expect(page.locator('#transcript')).toContainText('Browser result');
  await page.reload();
  await expect.poll(() => signInChecks).toBe(2);
  await expect(page.locator('#task')).toBeVisible();
  expect(new URL(page.url()).search).toBe('');
  await expect.poll(() => app.socketURLs.length).toBe(2);
  expect(app.ticketRequests).toEqual([]);
  expect(app.pageErrors).toEqual([]);
});

test('dialogs can open over an invalid route without changing it', async ({ page }) => {
  const app = new DesktopBrowserHarness(page); await app.install();
  const invalid = '/device/%64evice-a/not-a-page';
  await page.goto(invalid); await expect(page.locator('.navigation-notice')).toBeVisible();
  await page.locator('#sidebar-settings').click();
  await expect(dialog(page)).toBeVisible(); await expect(page).toHaveURL(new RegExp(invalid + '$'));
  await page.keyboard.press('Escape'); await expect(page.locator('.navigation-notice')).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('session deep links wait for catalogs and distinguish missing from failed loading', async ({ page }) => {
  const app = new DesktopBrowserHarness(page); app.rpcDelays.set('session.list', 500);
  await app.install(); await page.goto(path('chat/session/session-1'));
  await expect(page.locator('#transcript')).toContainText('Browser result');
  await page.goto(path('chat/session/does-not-exist')); await expect(page.locator('.navigation-notice')).toContainText('no longer exists');
  await page.goto(path('chat/draft/not-in-this-tab')); await expect(page).toHaveURL(new RegExp(path('chat/new') + '$'));
  await expect(page.locator('#task')).toHaveValue('');
  app.rpcErrors.set('session.list', 'catalog unavailable');
  await page.goto(path('chat/session/does-not-exist'));
  await expect(page.locator('.navigation-notice')).toContainText('catalog unavailable');
  await expect(page.locator('.navigation-notice')).not.toContainText('no longer exists');
  expect(app.pageErrors).toEqual([]);
});

test('first send promotes an OpenSeek draft in place without adding a history entry', async ({ page }) => {
  const app = new DesktopBrowserHarness(page); await app.install(); await app.goto();
  await page.locator('#task').fill('Promote this draft'); await expect(page).toHaveURL(/\/chat\/draft\//);
  const draft = new URL(page.url()).pathname;
  const entries = await page.evaluate(() => history.length);
  await page.locator('#sidebar-settings').click();
  await expect(dialog(page)).toBeVisible();
  await page.keyboard.press('Escape'); await expect(dialog(page)).not.toBeVisible();
  await expect(page.locator('#task')).toHaveValue('Promote this draft');
  await page.locator('#send').click(); await expect(page).toHaveURL(new RegExp(draft.replace('/draft/', '/session/') + '$'));
  expect(await page.evaluate(() => history.length)).toBe(entries);
  expect(app.pageErrors).toEqual([]);
});

for (const refresh of [false, true]) {
  test(`sending a transferred draft behind Settings promotes its work URL (refresh=${refresh})`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    app.codexModels = [{ id: 'gpt-test', displayName: 'Navigation Codex', isDefault: true }];
    let finishStart; const pendingStart = new Promise(resolve => { finishStart = resolve; });
    const fallback = app.replyFor.bind(app);
    app.replyFor = request => {
      if (request.method === 'codex.thread.start') return pendingStart.then(() => fallback(request));
      if (['codex.thread.read', 'codex.thread.resume'].includes(request.method)) return { thread: { id: 'codex-thread-e2e', cwd: '/workspace', projectRoot: '/workspace', preview: 'Navigation thread', updatedAt: 2, turns: [] } };
      return fallback(request);
    };
    await app.install(); await app.goto();
    await page.locator('#task').fill('Transfer this addressed draft'); await expect(page).toHaveURL(/\/chat\/draft\//);
    await page.locator('#openseek-model-picker').click();
    await page.locator('#openseek-model-picker-menu [data-value="codex:gpt-test"]').click(); await expect(page).toHaveURL(/\/codex\/draft\//);
    const entries = await page.evaluate(() => history.length);
    await page.locator('#send').click();
    await page.locator('#sidebar-settings').click(); await expect(dialog(page)).toBeVisible();
    finishStart(); await expect.poll(() => app.requests.some(r => r.method === 'codex.turn.start')).toBe(true);
    await expect(page).toHaveURL(new RegExp(path('codex/thread/codex-thread-e2e') + '$'));
    await expect(dialog(page)).toBeVisible();
    if (refresh) await page.reload(); else await page.keyboard.press('Escape');
    await expect(dialog(page)).not.toBeVisible(); await expect(page.locator('.codex-topbar')).toBeVisible();
    expect(await page.evaluate(() => history.length)).toBe(entries);
    expect(app.pageErrors).toEqual([]);
  });
}

for (const engine of ['chat', 'codex']) {
  test(`${engine} blank routes remain stable until content exists`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    app.codexModels = [{ id: 'gpt-test', displayName: 'Navigation Codex', isDefault: true }];
    await app.install(); await page.goto(path(`${engine}/new`)); await expect(page.locator('#task')).toBeEditable();
    const entries = await page.evaluate(() => history.length);
    await page.locator('.workspace-row').hover();
    const newChat = app.projectControl('/workspace', 'new-conversation');
    await newChat.click(); await newChat.click();
    await expect(page).toHaveURL(new RegExp(path(`${engine}/new`) + '$'));
    expect(await page.evaluate(() => history.length)).toBe(entries);
    await page.locator('#task').fill('Local draft'); await expect(page).toHaveURL(new RegExp(`/${engine}/draft/`));
    const draft = page.url(); await page.locator('#task').fill(''); await expect(page).toHaveURL(draft);
    if (engine === 'codex') {
      await page.reload(); await expect(page).toHaveURL(new RegExp(path('codex/new') + '$'));
    } else {
      await app.openSession(); await page.goBack(); await expect(page).toHaveURL(draft);
    }
    await expect(page.locator('#task')).toHaveValue(''); expect(app.pageErrors).toEqual([]);
  });
}

test('history restores the project before creating the next conversation', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.workspaces = ['/project-a', '/project-b'];
  app.liveSessions = [{ id: 'session-a', title: 'A', updated_at_ms: 1 }, { id: 'session-b', title: 'B', updated_at_ms: 2 }];
  app.sessionGroups = sessions => ({ groups: app.workspaces.map((workspace, i) => ({ workspace, name: workspace, session_root: workspace + '/.openseek', sessions: sessions.filter(s => s.id === (i === 0 ? 'session-a' : 'session-b')), error: '' })) });
  const fallback = app.replyFor.bind(app);
  app.replyFor = request => { const result = fallback(request); if (request.method === 'session.load') result.session.id = request.params.session; return result; };
  await app.install(); await app.goto();
  for (const id of ['session-a', 'session-b']) {
    await app.sessionButton(id, { root: `/project-${id.slice(-1)}` }).click(); await expect(page.locator('#transcript')).toContainText('Browser result');
  }
  await page.goBack(); await expect(page).toHaveURL(/session\/session-a$/);
  await expect(page.locator('.topbar-workspace')).toContainText('project-a');
  const shortcut = await page.evaluate(() => navigator.platform.includes('Mac') ? 'Meta+N' : 'Control+N');
  await page.keyboard.press(shortcut); await expect(page).toHaveURL(/\/chat\/new$/);
  await expect(page.locator('.topbar-workspace')).toContainText('project-a'); expect(app.pageErrors).toEqual([]);
});

for (const failure of ['rpc', 'store']) {
  test(`archived session deep links report ${failure} errors and recover on retry`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page); app.liveSessions = [];
    app.archivedSessions = [{ id: 'session-1', title: 'Archived fixture', updated_at_ms: 1 }];
    let unavailable = true; const fallback = app.replyFor.bind(app);
    app.replyFor = request => failure === 'store' && unavailable && request.method === 'session.list_archived'
      ? { groups: [{ workspace: '/workspace', name: 'workspace', session_root: '/workspace/.openseek', sessions: [], error: 'Archive unavailable' }] }
      : fallback(request);
    if (failure === 'rpc') app.rpcErrors.set('session.list_archived', 'Archive unavailable');
    await app.install(); await page.goto(path('chat/session/session-1'));
    await expect(page.locator('.navigation-notice')).toContainText('Archive unavailable');
    await expect(page.locator('.navigation-notice')).not.toContainText('no longer exists');
    unavailable = false; app.rpcErrors.delete('session.list_archived');
    await page.locator('#navigation-retry').click();
    await expect(page.locator('#transcript')).toContainText('Browser result');
    await expect(page.locator('.navigation-notice')).toHaveCount(0);
    expect(app.requests.some(r => r.method === 'session.load_archived')).toBe(true); expect(app.pageErrors).toEqual([]);
  });
}

test("Back closes the management dialog before it reaches the page", async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install(); await app.goto(); await app.openSession();
  // The host's Back event, as the Android shell dispatches it: true exactly
  // when a layer took it.
  const hostBack = () => page.evaluate(() => !document.dispatchEvent(new Event('openseek-back', { cancelable: true })));
  expect(await hostBack()).toBe(false);
  await page.locator('#sidebar-skills').click();
  await expect(dialog(page)).toHaveAccessibleName('Skills');
  expect(await hostBack()).toBe(true);
  await expect(dialog(page)).not.toBeVisible();
  await expect(page.locator('#transcript')).toContainText('Browser result');
  expect(await hostBack()).toBe(false);
  expect(app.pageErrors).toEqual([]);
});

import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

const path = suffix => `/device/device-a/${suffix}`;
const dialog = page => page.getByRole('dialog');

function skills(app) {
  const fallback = app.replyFor.bind(app);
  app.replyFor = request => {
    if (request.method === 'skills.catalog') return { skills: [{
      name: 'route-skill', module_name: 'example/route-skill', package_path: '',
      version: '1.0.0', description: 'Navigation fixture', author: 'example', repository: '',
    }] };
    if (request.method === 'skills.content') return { kind: 'content', content: '# Route skill\n\nDetail reached.', absolute: '', sig: '' };
    return fallback(request);
  };
}

test('management dialogs preserve the work surface, draft and browser entry', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install(); await app.goto(); await app.openSession();
  await expect(page).toHaveURL(new RegExp(path('chat/session/session-1') + '$'));
  const composer = page.locator('#task');
  await composer.fill('Unsent input survives dialogs');
  const url = page.url();
  const entries = await page.evaluate(() => history.length);
  const originalComposer = await composer.elementHandle();
  for (const [entry, title, dismiss] of [
    ['Settings', 'Settings', 'close'],
    ['Skills', 'Skills', 'escape'],
    ['Scheduled', 'Scheduled tasks', 'backdrop'],
  ]) {
    await page.getByRole('button', { name: entry, exact: true }).click();
    await expect(dialog(page)).toHaveAccessibleName(title);
    await expect(dialog(page)).toBeVisible();
    await expect(page).toHaveURL(url);
    expect(await page.evaluate(() => history.length)).toBe(entries);
    expect(await originalComposer.evaluate(node => node.isConnected)).toBe(true);
    await page.screenshot({ animations: 'disabled', path: test.info().outputPath(`${entry.toLowerCase()}-dialog.png`) });
    // Every dismissal animates out and leaves nothing interactive behind.
    if (dismiss === 'close') await dialog(page).getByRole('button', { name: 'Dismiss', exact: true }).click();
    else if (dismiss === 'escape') await page.keyboard.press('Escape');
    else await page.mouse.click(8, 8);
    await expect(page.locator('#management-dialog')).not.toBeVisible();
    await expect(composer).toHaveValue('Unsent input survives dialogs');
    await expect(page.getByRole('button', { name: entry, exact: true })).toBeFocused();
  }
  expect(app.pageErrors).toEqual([]);
});

for (const target of ['settings', 'skills', 'schedules', 'skills/market/example%2Froute-skill%401.0.0']) {
  test(`old ${target} links open dialogs without retaining a management page`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page); skills(app);
    await app.install(); await page.goto(path(target));
    await expect(dialog(page)).toBeVisible();
    if (target.includes('/market/')) await expect(page.locator('.skill-preview-markdown')).toContainText('Detail reached.');
    await expect(page).toHaveURL(/\/chat\/(new|draft\/[^/]+)$/);
    const url = page.url();
    await page.keyboard.press('Escape');
    await expect(dialog(page)).not.toBeVisible();
    await expect(page.locator('#task')).toBeVisible();
    await page.reload();
    await expect(dialog(page)).not.toBeVisible();
    await expect(page).toHaveURL(url);
    expect(app.pageErrors).toEqual([]);
  });
}

for (const target of ['settings', 'chat/session/session-1', 'skills/market/example%2Froute-skill%401.0.0']) {
  test(`local console opens ${target} without a device query`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page); skills(app);
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
    await page.goto(`/device/host/${target}`);
    await expect.poll(() => signInChecks).toBe(1);
    if (target.startsWith('chat/')) await expect(page.getByText('Browser result', { exact: true })).toBeVisible();
    else await expect(dialog(page)).toBeVisible();
    await page.reload();
    await expect.poll(() => signInChecks).toBe(2);
    await expect(page.locator('#task')).toBeVisible();
    expect(new URL(page.url()).search).toBe('');
    await expect.poll(() => app.socketURLs.length).toBe(2);
    expect(app.ticketRequests).toEqual([]);
    expect(app.pageErrors).toEqual([]);
  });
}

for (const restored of [false, true]) {
  test(`encoded device conversation links share canonical browser history (restored=${restored})`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page); await app.install();
    if (restored) await page.addInitScript(() => {
      if (sessionStorage.getItem('encoded-history-seeded')) return;
      sessionStorage.setItem('encoded-history-seeded', 'yes');
      const initial = '/device/device-a/chat/new';
      const session = '/device/%64evice-a/chat/session/session-1';
      const marker = key => ({ seekmoonNavigation: { group: 'encoded-group', key }, foreignState: 'keep' });
      history.replaceState(marker('initial'), '', initial);
      history.pushState(marker('session'), '', session);
      sessionStorage.setItem('seekmoon.history.v1.encoded-group', JSON.stringify({ entries: [
        { key: 'initial', path: initial, original: initial }, { key: 'session', path: session, original: session },
      ] }));
    });
    await page.goto('/device/%64evice-a/chat/session/session-1');
    await expect(page.getByText('Browser result', { exact: true })).toBeVisible();
    await expect(page).toHaveURL(new RegExp(path('chat/session/session-1') + '$'));
    if (restored) expect(await page.evaluate(() => history.state.foreignState)).toBe('keep');
    await page.reload();
    await expect(page.getByText('Browser result', { exact: true })).toBeVisible();
    if (restored) {
      await page.goBack(); await expect(page).toHaveURL(new RegExp(path('chat/new') + '$'));
      await page.goForward(); await expect(page.getByText('Browser result', { exact: true })).toBeVisible();
    }
    expect(app.pageErrors).toEqual([]);
  });
}

test('dialogs can open over an invalid route without changing it', async ({ page }) => {
  const app = new DesktopBrowserHarness(page); await app.install();
  const invalid = '/device/%64evice-a/not-a-page';
  await page.goto(invalid); await expect(page.locator('.navigation-notice')).toBeVisible();
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await expect(dialog(page)).toBeVisible(); await expect(page).toHaveURL(new RegExp(invalid + '$'));
  await page.keyboard.press('Escape'); await expect(page.locator('.navigation-notice')).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

for (const storage of ['malformed', 'unavailable']) {
  test(`conversation history remains usable when persisted storage is ${storage}`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page); await app.install();
    if (storage === 'unavailable') await page.addInitScript(() => {
      for (const name of ['getItem', 'setItem']) {
        const original = Storage.prototype[name];
        Storage.prototype[name] = function (key, ...args) {
          if (key.startsWith('seekmoon.history.v1.')) throw new DOMException('Storage denied', 'SecurityError');
          return original.call(this, key, ...args);
        };
      }
    });
    await page.goto(path('chat/new')); await app.openSession();
    await expect(page.getByText('Browser result', { exact: true })).toBeVisible();
    if (storage === 'malformed') await page.evaluate(() => sessionStorage.setItem('seekmoon.history.v1.' + history.state.seekmoonNavigation.group, '{broken'));
    await page.reload(); await expect(page.getByText('Browser result', { exact: true })).toBeVisible();
    await page.goBack(); await expect(page).toHaveURL(new RegExp(path('chat/new') + '$'));
    await page.goForward(); await expect(page.getByText('Browser result', { exact: true })).toBeVisible();
    expect(app.pageErrors).toEqual([]);
  });
}

test('session deep links wait for catalogs and distinguish missing from failed loading', async ({ page }) => {
  const app = new DesktopBrowserHarness(page); app.rpcDelays.set('session.list', 500);
  await app.install(); await page.goto(path('chat/session/session-1'));
  await expect(page.getByText('Browser result', { exact: true })).toBeVisible();
  await page.goto(path('chat/session/does-not-exist')); await expect(page.locator('.navigation-notice')).toContainText('no longer exists');
  await page.goto(path('chat/draft/not-in-this-tab')); await expect(page).toHaveURL(new RegExp(path('chat/new') + '$'));
  await expect(page.locator('#task')).toHaveValue('');
  app.rpcErrors.set('session.list', 'catalog unavailable');
  await page.goto(path('chat/session/does-not-exist'));
  await expect(page.locator('.navigation-notice')).toContainText('catalog unavailable');
  await expect(page.locator('.navigation-notice')).not.toContainText('no longer exists');
  expect(app.pageErrors).toEqual([]);
});

test('market detail reports catalog failure and retries only on request', async ({ page }) => {
  const app = new DesktopBrowserHarness(page); skills(app);
  app.rpcErrors.set('skills.catalog', 'catalog unavailable');
  await app.install(); await page.goto(path('skills/market/example%2Froute-skill%401.0.0'));
  await expect(dialog(page).locator('.navigation-notice')).toContainText('catalog unavailable');
  expect(app.requests.filter(r => r.method === 'skills.catalog')).toHaveLength(1);
  app.rpcErrors.delete('skills.catalog');
  await dialog(page).getByRole('button', { name: 'Retry', exact: true }).click();
  await expect(page.locator('.skill-preview-markdown')).toContainText('Detail reached.');
  expect(app.requests.filter(r => r.method === 'skills.catalog')).toHaveLength(2);
  expect(app.pageErrors).toEqual([]);
});

test('Skills detail returns to its list within the dialog', async ({ page }) => {
  const app = new DesktopBrowserHarness(page); skills(app);
  await app.install(); await app.goto();
  const url = page.url();
  await page.getByRole('button', { name: 'Skills', exact: true }).click();
  await page.locator('.skill-summary', { hasText: 'route-skill' }).click();
  await expect(page.locator('.skill-preview-markdown')).toContainText('Detail reached.');
  await expect(page).toHaveURL(url);
  await dialog(page).getByRole('button', { name: 'Skills', exact: true }).click();
  await expect(page.locator('.skill-summary', { hasText: 'route-skill' })).toBeVisible();
  await page.keyboard.press('Escape'); await expect(dialog(page)).not.toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('first send promotes an OpenSeek draft in place without adding a history entry', async ({ page }) => {
  const app = new DesktopBrowserHarness(page); await app.install(); await app.goto();
  await page.locator('#task').fill('Promote this draft'); await expect(page).toHaveURL(/\/chat\/draft\//);
  const draft = new URL(page.url()).pathname;
  const entries = await page.evaluate(() => history.length);
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
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
    await page.getByRole('button', { name: 'Model', exact: true }).click();
    await page.getByRole('option', { name: 'Navigation Codex', exact: true }).click(); await expect(page).toHaveURL(/\/codex\/draft\//);
    const entries = await page.evaluate(() => history.length);
    await page.locator('#send').click();
    await page.getByRole('button', { name: 'Settings', exact: true }).click(); await expect(dialog(page)).toBeVisible();
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
    const newChat = page.getByRole('button', { name: 'New conversation in this project', exact: true });
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
    await page.locator(`.conversation-row[title="${id}"]`).click(); await expect(page.getByText('Browser result', { exact: true })).toBeVisible();
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
    await page.getByRole('button', { name: 'Retry', exact: true }).click();
    await expect(page.getByText('Browser result', { exact: true })).toBeVisible();
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
  await page.getByRole('button', { name: 'Skills', exact: true }).click();
  await expect(dialog(page)).toHaveAccessibleName('Skills');
  expect(await hostBack()).toBe(true);
  await expect(dialog(page)).not.toBeVisible();
  await expect(page.getByText('Browser result', { exact: true })).toBeVisible();
  expect(await hostBack()).toBe(false);
  expect(app.pageErrors).toEqual([]);
});

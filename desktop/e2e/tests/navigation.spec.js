import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

const path = suffix => `/device/device-a/${suffix}`;
const back = page => page.getByRole('button', { name: 'Back', exact: true });
const forward = page => page.getByRole('button', { name: 'Forward', exact: true });
const heading = page => page.locator('main > .topbar h1');

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

test('browser and application arrows share history, preserve drafts and branch after back', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install(); await app.goto(); await app.openSession();
  await expect(page).toHaveURL(new RegExp(path('chat/session/session-1') + '$'));
  const composer = page.getByRole('textbox', { name: 'Ask SeekMoon to inspect, edit, or explain this workspace.' });
  await composer.fill('Unsent input survives navigation');
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await page.getByRole('button', { name: 'Skills', exact: true }).click();
  await back(page).click(); await expect(heading(page)).toHaveText('Settings');
  await page.goBack(); await expect(composer).toHaveValue('Unsent input survives navigation');
  await forward(page).click(); await expect(heading(page)).toHaveText('Settings');
  await page.getByRole('button', { name: 'Scheduled', exact: true }).click();
  await expect(forward(page)).toBeDisabled();
  await page.reload(); await expect(heading(page)).toHaveText('Scheduled tasks');
  await back(page).click(); await expect(heading(page)).toHaveText('Settings');
  await back(page).click(); await expect(page.getByText('Browser result', { exact: true })).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('direct management entry has no invented predecessor and refresh keeps its route', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install(); await page.goto(path('settings'));
  await expect(heading(page)).toHaveText('Settings'); await expect(back(page)).toBeDisabled();
  await page.reload(); await expect(heading(page)).toHaveText('Settings'); await expect(back(page)).toBeDisabled();
  await page.getByRole('button', { name: 'Skills', exact: true }).click();
  await page.reload(); await back(page).click(); await expect(heading(page)).toHaveText('Settings');
  await forward(page).click(); await expect(heading(page)).toHaveText('Skills');
  expect(app.pageErrors).toEqual([]);
});

test('MoonBit history restores the existing v1 browser entries after refresh', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await page.addInitScript(() => {
    if (sessionStorage.getItem('history-fixture-seeded')) return;
    sessionStorage.setItem('history-fixture-seeded', 'yes');
    const initial = '/device/device-a/chat/new';
    const settings = '/device/device-a/settings';
    const marker = key => ({ seekmoonNavigation: { group: 'legacy-group', key }, foreignState: 'keep' });
    history.replaceState(marker('initial'), '', initial);
    history.pushState(marker('settings'), '', settings);
    sessionStorage.setItem('seekmoon.history.v1.legacy-group', JSON.stringify({ entries: [
      { key: 'initial', path: initial, original: initial },
      { key: 'settings', path: settings, original: settings },
    ] }));
  });
  await page.goto(path('settings'));
  await expect(heading(page)).toHaveText('Settings');
  await expect(back(page)).toBeEnabled();
  expect(await page.evaluate(() => history.state)).toEqual({
    seekmoonNavigation: { group: 'legacy-group', key: 'settings' }, foreignState: 'keep',
  });
  await page.reload();
  await expect(heading(page)).toHaveText('Settings');
  await back(page).click();
  await expect(page).toHaveURL(new RegExp(path('chat/new') + '$'));
  await expect(back(page)).toBeDisabled();
  await expect(forward(page)).toBeEnabled();
  await forward(page).click();
  await expect(heading(page)).toHaveText('Settings');
  expect(app.pageErrors).toEqual([]);
});

for (const storage of ['malformed', 'unavailable']) {
  test(`history remains usable when persisted storage is ${storage}`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    await app.install();
    if (storage === 'unavailable') {
      await page.addInitScript(() => {
        for (const name of ['getItem', 'setItem']) {
          const original = Storage.prototype[name];
          Storage.prototype[name] = function (key, ...args) {
            if (key.startsWith('seekmoon.history.v1.')) throw new DOMException('Storage denied', 'SecurityError');
            return original.call(this, key, ...args);
          };
        }
      });
    }
    await page.goto(path('settings'));
    await expect(heading(page)).toHaveText('Settings');
    await page.getByRole('button', { name: 'Scheduled', exact: true }).click();
    await expect(heading(page)).toHaveText('Scheduled tasks');
    await back(page).click();
    await expect(heading(page)).toHaveText('Settings');
    await expect(forward(page)).toBeEnabled();
    if (storage === 'malformed') {
      await page.evaluate(() => {
        sessionStorage.setItem('seekmoon.history.v1.' + history.state.seekmoonNavigation.group, '{broken');
      });
    }
    await page.reload();
    await expect(heading(page)).toHaveText('Settings');
    await expect(back(page)).toBeDisabled();
    await expect(forward(page)).toBeDisabled();
    await page.getByRole('button', { name: 'Scheduled', exact: true }).click();
    await expect(heading(page)).toHaveText('Scheduled tasks');
    await back(page).click();
    await expect(heading(page)).toHaveText('Settings');
    expect(app.pageErrors).toEqual([]);
  });
}

test('session deep links wait for catalogs and distinguish missing from failed loading', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.rpcDelays.set('session.list', 500);
  await app.install(); await page.goto(path('chat/session/session-1'));
  await expect(page.getByText('Browser result', { exact: true })).toBeVisible();
  await page.goto(path('chat/session/does-not-exist'));
  await expect(page.locator('.navigation-notice')).toContainText('no longer exists');
  await page.goto(path('chat/draft/not-in-this-tab'));
  await expect(page).toHaveURL(new RegExp(path('chat/new') + '$'));
  await expect(page.locator('#task')).toHaveValue('');
  app.rpcErrors.set('session.list', 'catalog unavailable');
  await page.goto(path('chat/session/does-not-exist'));
  await expect(page.locator('.navigation-notice')).toContainText('catalog unavailable');
  await expect(page.locator('.navigation-notice')).not.toContainText('no longer exists');
  expect(app.pageErrors).toEqual([]);
});

test('Skills detail is addressable, refreshable and participates in history', async ({ page }) => {
  const app = new DesktopBrowserHarness(page); skills(app);
  await app.install(); await page.goto(path('skills'));
  await page.locator('.skill-summary', { hasText: 'route-skill' }).click();
  await expect(page).toHaveURL(new RegExp('/skills/market/example%2Froute-skill%401.0.0$'));
  await expect(page.locator('.skill-preview-markdown')).toContainText('Detail reached.');
  await page.reload(); await expect(page.locator('.skill-preview-markdown')).toContainText('Detail reached.');
  await back(page).click(); await expect(page.locator('.skill-summary', { hasText: 'route-skill' })).toBeVisible();
  await forward(page).click(); await expect(page.locator('.skill-preview-markdown')).toContainText('Detail reached.');
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await page.getByRole('button', { name: 'Skills', exact: true }).click();
  await expect(page.locator('.skill-summary', { hasText: 'route-skill' })).toBeVisible();
  await page.goBack(); await page.goBack();
  await expect(page.locator('.skill-preview-markdown')).toContainText('Detail reached.');
  expect(app.pageErrors).toEqual([]);
});

test('titlebar order and narrow layout keep navigation visible', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  await app.install(); await page.goto(path('settings'));
  for (const width of [1440, 390]) {
    await page.setViewportSize({ width, height: 844 });
    await expect(back(page)).toBeInViewport(); await expect(forward(page)).toBeInViewport();
    const bounds = await Promise.all([page.locator('.sidebar-toggle'), back(page), forward(page)].map(el => el.boundingBox()));
    expect(bounds[0].x + bounds[0].width).toBeLessThanOrEqual(bounds[1].x);
    expect(bounds[1].x + bounds[1].width).toBeLessThanOrEqual(bounds[2].x);
    await page.screenshot({ path: testInfo.outputPath(`navigation-${width}.png`) });
  }
  expect(app.pageErrors).toEqual([]);
});

test('first send promotes an OpenSeek draft in place without adding a history entry', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install(); await app.goto();
  await expect(page).toHaveURL(/\/chat\/new(?:\?|$)/);
  await page.locator('#task').fill('Promote this draft');
  await expect(page).toHaveURL(/\/chat\/draft\//);
  const draft = new URL(page.url()).pathname;
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await back(page).click();
  await expect(page.locator('#task')).toHaveValue('Promote this draft');
  await page.locator('#send').click();
  await expect(page).toHaveURL(new RegExp(draft.replace('/draft/', '/session/') + '$'));
  await expect(back(page)).toBeDisabled();
  await forward(page).click(); await expect(heading(page)).toHaveText('Settings');
  await back(page).click();
  await expect(page).toHaveURL(new RegExp(draft.replace('/draft/', '/session/') + '$'));
  expect(app.pageErrors).toEqual([]);
});

test('Codex draft promotion while covered preserves the selected page and history', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.codexModels = [{ id: 'gpt-test', displayName: 'Navigation Codex', isDefault: true }];
  const fallback = app.replyFor.bind(app);
  app.replyFor = request => request.method === 'codex.thread.read' || request.method === 'codex.thread.resume'
    ? { thread: { id: request.params?.threadId || request.params?.thread_id || 'codex-thread-e2e', cwd: '/workspace', projectRoot: '/workspace', preview: 'Navigation thread', updatedAt: 2, turns: [] } }
    : fallback(request);
  await app.install(); await app.goto();
  await page.getByRole('button', { name: 'Model', exact: true }).click();
  await page.getByRole('option', { name: 'Navigation Codex', exact: true }).click();
  await expect(page).toHaveURL(/\/codex\/new$/);
  await page.locator('#task').fill('First Codex prompt');
  await expect(page).toHaveURL(/\/codex\/draft\//);
  app.rpcDelays.set('codex.thread.start', 800);
  await page.locator('#send').click();
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await expect.poll(() => app.requests.some(request => request.method === 'codex.turn.start')).toBe(true);
  await expect(heading(page)).toHaveText('Settings');
  await back(page).click(); await expect(page).toHaveURL(/\/codex\/thread\/codex-thread-e2e$/);
  await back(page).click(); await expect(page).toHaveURL(/\/chat\/new(?:\?|$)/);
  await forward(page).click(); await expect(page).toHaveURL(/\/codex\/thread\/codex-thread-e2e$/);
  await page.reload(); await expect(page.locator('.codex-topbar')).toBeVisible();
  await expect(page).toHaveURL(/\/codex\/thread\/codex-thread-e2e$/);
  expect(app.pageErrors).toEqual([]);
});

test('native titlebar insets keep the sidebar mode switch clear at its minimum width', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  await app.install(); await page.goto(path('settings'));
  await expect(heading(page)).toHaveText('Settings');
  await page.evaluate(() => {
    document.documentElement.style.setProperty('--native-titlebar-left', '84px');
    document.documentElement.style.setProperty('--native-titlebar-height', '28px');
    document.querySelector('.app').style.setProperty('--sidebar-width', '220px');
  });
  const toggle = await page.locator('.sidebar-toggle').boundingBox();
  const backBounds = await back(page).boundingBox();
  const forwardBounds = await forward(page).boundingBox();
  const mode = await page.locator('.sidebar-mode').boundingBox();
  const header = await page.locator('.sidebar-header').boundingBox();
  expect(toggle.x).toBeGreaterThanOrEqual(84);
  expect(toggle.x + toggle.width).toBeLessThanOrEqual(backBounds.x);
  expect(backBounds.x + backBounds.width).toBeLessThanOrEqual(forwardBounds.x);
  expect(mode.x).toBeGreaterThanOrEqual(forwardBounds.x + forwardBounds.width + 8);
  for (const control of [toggle, backBounds, forwardBounds, mode]) {
    expect(Math.abs(control.y + control.height / 2 - (header.y + header.height / 2))).toBeLessThan(1);
  }
  const sidebar = await page.locator('aside').boundingBox();
  expect(mode.x + mode.width).toBeLessThanOrEqual(sidebar.x + sidebar.width - 8);
  const options = await page.locator('.sidebar-mode-option').all();
  for (const option of options) expect((await option.boundingBox()).width).toBeGreaterThanOrEqual(28);
  await page.screenshot({ path: testInfo.outputPath('navigation-native-geometry.png') });
  expect(app.pageErrors).toEqual([]);
});


test('blank new routes and the New chat action share one entry until content exists', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install(); await page.goto(path('chat/new'));
  await expect(page.locator('#task')).toBeVisible();
  await expect(page).toHaveURL(new RegExp(path('chat/new') + '$'));
  const newChat = page.getByRole('button', { name: 'New conversation in this project', exact: true });
  await page.locator('.workspace-row').hover();
  const entries = await page.evaluate(() => history.length);
  await newChat.click(); await newChat.click();
  await expect(page).toHaveURL(new RegExp(path('chat/new') + '$'));
  expect(await page.evaluate(() => history.length)).toBe(entries);
  await page.locator('#task').fill('Give this draft an identity');
  await expect(page).toHaveURL(/\/chat\/draft\//);
  const draft = page.url();
  await page.locator('#task').fill('');
  await expect(page).toHaveURL(draft);
  await app.openSession();
  await back(page).click();
  await expect(page).toHaveURL(draft);
  await expect(page.locator('#task')).toHaveValue('');
  await expect(back(page)).toBeDisabled();
  await forward(page).click();
  await page.locator('.workspace-row').hover(); await newChat.click();
  await expect(page).toHaveURL(new RegExp(path('chat/new') + '$'));
  await expect(page.locator('#task')).toHaveValue('');
  await expect(page.locator('.conversation-row.active')).toHaveCount(0);
  await back(page).click();
  await expect(page).toHaveURL(new RegExp(path('chat/session/session-1') + '$'));
  expect(app.pageErrors).toEqual([]);
});

test('Codex new is stable until input and expired drafts replace back to new', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.codexModels = [{ id: 'gpt-test', displayName: 'Navigation Codex', isDefault: true }];
  await app.install(); await page.goto(path('codex/new'));
  await expect(page.locator('#task')).toBeEditable();
  await expect(page).toHaveURL(new RegExp(path('codex/new') + '$'));
  await expect(back(page)).toBeDisabled();
  const entries = await page.evaluate(() => history.length);
  await page.locator('.workspace-row').hover();
  const newChat = page.getByRole('button', { name: 'New conversation in this project', exact: true });
  await newChat.click(); await newChat.click();
  await expect(page).toHaveURL(new RegExp(path('codex/new') + '$'));
  expect(await page.evaluate(() => history.length)).toBe(entries);
  await page.locator('#task').fill('Local Codex input');
  await expect(page).toHaveURL(/\/codex\/draft\//);
  const draft = page.url();
  await page.locator('#task').fill(''); await expect(page).toHaveURL(draft);
  await page.reload();
  await expect(page).toHaveURL(new RegExp(path('codex/new') + '$'));
  await expect(page.locator('#task')).toBeEditable();
  await expect(page.locator('#task')).toHaveValue('');
  await expect(back(page)).toBeDisabled();
  expect(app.pageErrors).toEqual([]);
});

test('market detail reports catalog failure and retries only on request', async ({ page }) => {
  const app = new DesktopBrowserHarness(page); skills(app);
  app.rpcErrors.set('skills.catalog', 'catalog unavailable');
  await app.install(); await page.goto(path('skills/market/example%2Froute-skill%401.0.0'));
  await expect(page.locator('.navigation-notice')).toContainText('catalog unavailable');
  await page.getByRole('button', { name: 'Hide sidebar', exact: true }).click();
  await page.getByRole('button', { name: 'Show sidebar', exact: true }).click();
  expect(app.requests.filter(r => r.method === 'skills.catalog')).toHaveLength(1);
  app.rpcErrors.delete('skills.catalog');
  await page.getByRole('button', { name: 'Retry', exact: true }).click();
  await expect(page.locator('.skill-preview-markdown')).toContainText('Detail reached.');
  expect(app.requests.filter(r => r.method === 'skills.catalog')).toHaveLength(2);
  expect(app.pageErrors).toEqual([]);
});

test('history restores the project before creating the next conversation', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.workspaces = ['/project-a', '/project-b'];
  app.liveSessions = [{ id: 'session-a', title: 'A', updated_at_ms: 1 }, { id: 'session-b', title: 'B', updated_at_ms: 2 }];
  app.sessionGroups = sessions => ({ groups: app.workspaces.map((workspace, i) => ({
    workspace, name: workspace, session_root: workspace + '/.openseek',
    sessions: sessions.filter(s => s.id === (i === 0 ? 'session-a' : 'session-b')), error: '',
  })) });
  const fallback = app.replyFor.bind(app);
  app.replyFor = request => {
    const result = fallback(request);
    if (request.method === 'session.load') result.session.id = request.params.session;
    return result;
  };
  await app.install(); await app.goto();
  const workspace = page.locator('.topbar-workspace');
  for (const id of ['session-a', 'session-b']) {
    await page.locator(`.conversation-row[title="${id}"]`).click();
    await expect(page.getByText('Browser result', { exact: true })).toBeVisible();
  }
  await back(page).click();
  await expect(page).toHaveURL(/session\/session-a$/);
  await expect(workspace).toContainText('project-a');
  const newShortcut = await page.evaluate(() => navigator.platform.includes('Mac') ? 'Meta+N' : 'Control+N');
  await page.keyboard.press(newShortcut);
  await expect(page).toHaveURL(/\/chat\/new$/);
  await expect(workspace).toContainText('project-a');
  await page.locator('#task').fill('Draft in project A');
  const draft = page.url();
  await page.locator('.conversation-row[title="session-b"]').click();
  await expect(page).toHaveURL(/session\/session-b$/);
  await back(page).click(); await expect(page).toHaveURL(draft);
  await page.keyboard.press(newShortcut);
  await expect(page).toHaveURL(/\/chat\/new$/);
  await expect(workspace).toContainText('project-a');
  expect(app.pageErrors).toEqual([]);
});

test('returning to a Codex draft reloads skills and preserves structured mentions', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.codexModels = [{ id: 'gpt-test', displayName: 'Navigation Codex', isDefault: true }];
  const fallback = app.replyFor.bind(app);
  app.replyFor = request => request.method === 'codex.skills.list'
    ? { data: [{ cwd: '/workspace', skills: [{ name: 'review-pr', description: 'Review a pull request', path: '/skills/review-pr/SKILL.md', enabled: true }] }] }
    : fallback(request);
  await app.install(); await app.goto();
  await page.getByRole('button', { name: 'Model', exact: true }).click();
  await page.getByRole('option', { name: 'Navigation Codex', exact: true }).click();
  const composer = page.locator('#task');
  await composer.fill('$review');
  await page.getByText('Review a pull request', { exact: true }).click();
  await composer.fill('Review this change');
  const draft = page.url();
  await page.locator('.workspace-row').hover();
  await page.getByRole('button', { name: 'New conversation in this project', exact: true }).click();
  await expect(page).toHaveURL(/\/codex\/new$/);
  await expect.poll(() => app.requests.filter(r => r.method === 'codex.skills.list').length).toBe(2);
  await back(page).click(); await expect(page).toHaveURL(draft);
  await expect.poll(() => app.requests.filter(r => r.method === 'codex.skills.list').length).toBe(3);
  await composer.fill('$review');
  await expect(page.getByText('Review a pull request', { exact: true })).toBeVisible();
  await composer.fill('Review this change');
  await page.locator('#send').click();
  await expect.poll(() => app.requests.filter(r => r.method === 'codex.turn.start').length).toBe(1);
  expect(app.requests.find(r => r.method === 'codex.turn.start').params.input).toContainEqual({ type: 'skill', name: 'review-pr', path: '/skills/review-pr/SKILL.md' });
  expect(app.pageErrors).toEqual([]);
});

test('returning to a Codex draft restores its project for the next New chat', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.workspaces = ['/project-a', '/project-b'];
  app.codexModels = [{ id: 'gpt-test', displayName: 'Navigation Codex', isDefault: true }];
  await app.install(); await app.goto();
  await page.getByRole('button', { name: 'Model', exact: true }).click();
  await page.getByRole('option', { name: 'Navigation Codex', exact: true }).click();
  await page.locator('#task').fill('Draft in project A');
  const draft = page.url();
  const projectB = page.locator('.workspace-row', { hasText: 'project-b' });
  await projectB.hover();
  await projectB.getByRole('button', { name: 'New conversation in this project', exact: true }).click();
  await expect(page).toHaveURL(/\/codex\/new$/);
  await expect.poll(() => app.requests.filter(r => r.method === 'codex.draft.open').at(-1)?.params.cwd).toBe('/project-b');
  await back(page).click(); await expect(page).toHaveURL(draft);
  const newShortcut = await page.evaluate(() => navigator.platform.includes('Mac') ? 'Meta+N' : 'Control+N');
  await page.keyboard.press(newShortcut);
  await expect(page).toHaveURL(/\/codex\/new$/);
  await expect.poll(() => app.requests.filter(r => r.method === 'codex.draft.open').at(-1)?.params.cwd).toBe('/project-a');
  expect(app.pageErrors).toEqual([]);
});

import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

async function open(page, workspaces = ['/workspace'], signedIn = false) {
  const app = new DesktopBrowserHarness(page);
  app.workspaces = workspaces;
  app.codexModels = [{ id: 'gpt-test', displayName: 'Codex test', isDefault: true }];
  app.searchFiles = ['src/main.mbt'];
  if (signedIn) {
    const reply = app.replyFor.bind(app);
    app.replyFor = request => request.method === 'codex.account.read'
      ? { account: { type: 'chatgpt', planType: 'pro' }, requiresOpenaiAuth: true }
      : reply(request);
  }
  await app.install();
  await app.goto();
  await expect(app.sessionButton()).toBeVisible();
  return app;
}

async function chooseCodex(page) {
  await page.locator('#openseek-model-picker:visible, #codex-model-picker:visible').click();
  await page.locator('[role="option"][data-value="codex:gpt-test"]').click();
  await expect(page.locator('#openseek-model-picker:visible, #codex-model-picker:visible')).toHaveAttribute('data-value', 'codex:gpt-test');
}

test('both agents share the first screen and Codex can choose its project in the title', async ({ page }) => {
  const app = await open(page, ['/workspace', '/other']);
  const title = page.locator('.empty-title');
  const badge = page.locator('.empty-badge');
  const transcript = page.locator('#transcript');
  await expect(title).toHaveText('What should we build in workspace?');
  const logo = await badge.innerHTML();
  await chooseCodex(page);
  const trigger = page.locator('#empty-project-trigger');
  await expect(trigger).toBeVisible();
  expect(await badge.innerHTML()).toBe(logo);
  const session = await transcript.getAttribute('data-transcript-session');
  const openCount = app.requests.filter(r => r.method === 'codex.draft.open').length;
  const task = page.locator('#task');
  await task.fill('@main');
  await page.locator('[data-completion-path="src/main.mbt"]').click();
  await task.press('End');
  await task.pressSequentially(' Keep this draft when changing projects');
  const draftText = await task.inputValue();
  const png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aCfoAAAAASUVORK5CYII=';
  const imageURL = `data:image/png;base64,${png}`;
  const chooser = page.waitForEvent('filechooser');
  await page.locator('#composer-attach').click();
  await (await chooser).setFiles({ name: 'screen.png', mimeType: 'image/png', buffer: Buffer.from(png, 'base64') });
  await expect(page.locator('.composer-image img')).toHaveAttribute('src', imageURL);

  await trigger.click();
  const picker = page.locator('#empty-project-menu');
  const search = picker.locator('#empty-project-search');
  await search.fill('oth');
  await expect(picker.locator('[data-project-path="/workspace"]')).toHaveCount(0);
  await expect(picker.locator('[data-project-path="/other"]')).toBeVisible();
  await search.fill('');
  await picker.locator('[data-project-path="/workspace"]').click();
  await expect(picker).toBeHidden();
  await expect(transcript).toHaveAttribute('data-transcript-session', session);
  expect(app.requests.filter(r => r.method === 'codex.draft.open')).toHaveLength(openCount);
  await trigger.click();
  await picker.locator('[data-project-path="/other"]').click();
  await expect(title).toHaveText('What should we build in other?');
  await expect(app.projectRow('/other')).toHaveClass(/\bactive\b/);
  await expect(transcript).toHaveAttribute('data-transcript-session', session);
  await expect(page.locator('#codex-model-picker')).toHaveAttribute('data-value', 'codex:gpt-test');
  await expect.poll(() => app.requests.filter(r => r.method === 'codex.draft.open').at(-1)?.params.cwd).toBe('/other');
  await expect(task).toHaveValue(draftText);
  await expect(page.locator('.composer-image img')).toHaveAttribute('src', imageURL);
  await expect(page.locator('.mention-chip[data-mention-path="src/main.mbt"]')).toContainText('src/main.mbt');
  expect(app.requests.filter(r => r.method === 'codex.draft.close')).toHaveLength(0);
  const otherTrigger = page.locator('#empty-project-trigger');
  await otherTrigger.click();
  await picker.locator('#empty-project-new').click();
  const addProject = page.locator('#project-picker-dialog');
  await expect(addProject).toBeVisible();
  await addProject.locator('#project-picker-add').click();
  await expect.poll(() => app.requests.some(r => r.method === 'workspace.add')).toBe(true);
  app.notify('workspace.changed', { workspaces: app.workspaces });
  await expect(title).toHaveText('What should we build in test?');
  await expect(transcript).toHaveAttribute('data-transcript-session', session);
  await expect(task).toHaveValue(draftText);
  await expect(page.locator('.composer-image img')).toHaveAttribute('src', imageURL);
  await expect(page.locator('.mention-chip[data-mention-path="src/main.mbt"]')).toContainText('src/main.mbt');
  await expect(addProject).toBeHidden();
  await page.locator('#send').click();
  await expect.poll(() => app.requests.find(r => r.method === 'codex.thread.start')?.params.cwd).toBe('/Users/test');
  await expect(page.locator('#empty-project-trigger')).toHaveCount(0);
  await expect.poll(() => app.requests.find(r => r.method === 'codex.turn.start')?.params.input).toEqual([
    { type: 'text', text: expect.stringContaining('Keep this draft when changing projects') },
    { type: 'mention', name: 'main.mbt', path: 'src/main.mbt' },
    { type: 'image', url: imageURL },
  ]);
  expect(app.pageErrors).toEqual([]);
});

for (const failure of ['rpc', 'malformed']) {
  test(`Codex project selection recovers after a ${failure} draft-open failure`, async ({ page }) => {
    await page.addInitScript(minimal => {
      localStorage.setItem('openseek.minimal_transcript', String(minimal));
    }, failure === 'malformed');
    const app = await open(page, ['/workspace', '/other']);
    await chooseCodex(page);
    const task = page.locator('#task');
    await task.fill('Keep this input after an open failure');
    const session = await page.locator('#transcript').getAttribute('data-transcript-session');
    const reply = app.replyFor.bind(app);
    if (failure === 'rpc') {
      app.rpcErrors.set('codex.draft.open', 'Project unavailable');
    } else {
      app.replyFor = request => request.method === 'codex.draft.open' ? {} : reply(request);
    }
    await page.locator('#empty-project-trigger').click();
    const picker = page.locator('#empty-project-menu');
    await picker.locator('[data-project-path="/other"]').click();
    const other = page.locator('#empty-project-trigger');
    await expect(other).toBeVisible();
    await expect(page.locator('#send')).toBeDisabled();
    // Wait for the error result to settle before retrying the same project.
    await expect(page.locator('#transcript .transcript-error-message')).toBeVisible();
    app.rpcErrors.delete('codex.draft.open');
    app.replyFor = reply;
    await other.click();
    if (failure === 'rpc') {
      await picker.locator('[data-project-path="/other"]').click();
    } else {
      await picker.locator('[data-project-path="/workspace"]').click();
    }
    await expect(page.locator('#send')).toBeEnabled();
    await expect(page.locator('#transcript')).toHaveAttribute('data-transcript-session', session);
    await expect(task).toHaveValue('Keep this input after an open failure');
    await page.locator('#send').click();
    await expect.poll(() => app.requests.find(r => r.method === 'codex.thread.start')?.params.cwd)
      .toBe(failure === 'rpc' ? '/other' : '/workspace');
    expect(app.pageErrors).toEqual([]);
  });
}

test('a failed thread start keeps its original draft identity and project for retry', async ({ page }) => {
  const app = await open(page, ['/workspace', '/other']);
  await chooseCodex(page);
  await page.locator('#task').fill('Retry this prompt');
  app.rpcErrors.set('codex.thread.start', 'Reply lost');
  await page.locator('#send').click();
  await expect(page.locator('#transcript .transcript-error-message')).toBeVisible();
  await expect(page.locator('#empty-project-trigger')).toHaveCount(0);
  await expect(page.locator('[id="section:openseek.projects:remote.device-a:action"]')).toBeDisabled();
  await expect(page.locator('#task')).toHaveValue('Retry this prompt');
  await page.keyboard.press('ControlOrMeta+o');
  await expect(page.locator('#project-picker-dialog')).toHaveCount(0);
  expect(app.requests.some(r => r.method === 'workspace.add')).toBe(false);
  const first = app.requests.find(r => r.method === 'codex.thread.start');
  app.rpcErrors.delete('codex.thread.start');
  await page.locator('#send').click();
  await expect.poll(() => app.requests.filter(r => r.method === 'codex.thread.start').length).toBe(2);
  expect(app.requests.filter(r => r.method === 'codex.thread.start')[1].params).toEqual(first.params);
  await expect.poll(() => app.requests.some(r => r.method === 'codex.turn.start')).toBe(true);
  await expect(page.locator('[id="section:openseek.projects:remote.device-a:action"]')).toBeEnabled();
  expect(app.pageErrors).toEqual([]);
});

test('the title cannot add or change projects until draft opening settles', async ({ page }) => {
  const app = await open(page, ['/workspace', '/other']);
  const pending = Promise.withResolvers();
  const reply = app.replyFor.bind(app);
  app.replyFor = request => request.method === 'codex.draft.open' ? pending.promise : reply(request);
  await chooseCodex(page);
  await expect.poll(() => app.requests.some(r => r.method === 'codex.draft.open')).toBe(true);
  await expect(page.locator('#empty-project-trigger')).toHaveCount(0);
  await expect(page.locator('[id="section:openseek.projects:remote.device-a:action"]')).toBeDisabled();
  const request = app.requests.find(r => r.method === 'codex.draft.open');
  app.replyFor = reply;
  pending.resolve(reply(request));
  await expect(page.locator('[id="section:openseek.projects:remote.device-a:action"]')).toBeEnabled();
  await page.locator('#empty-project-trigger').click();
  await page.locator('#empty-project-menu').locator('#empty-project-new').click();
  await page.locator('#project-picker-dialog').locator('#project-picker-add').click();
  await expect.poll(() => app.requests.some(r => r.method === 'workspace.add')).toBe(true);
  app.notify('workspace.changed', { workspaces: app.workspaces });
  await expect(page.locator('#empty-project-trigger')).toBeVisible();
  await page.locator('#task').fill('Use the newly added project');
  await page.locator('#send').click();
  await expect.poll(() => app.requests.find(r => r.method === 'codex.thread.start')?.params.cwd).toBe('/Users/test');
  expect(app.pageErrors).toEqual([]);
});

test('returning to the same blank Codex entry retains its pending project add', async ({ page }) => {
  const app = await open(page, ['/workspace', '/other'], true);
  await chooseCodex(page);
  await expect(page).toHaveURL(/\/codex\/new$/);
  const session = await page.locator('#transcript').getAttribute('data-transcript-session');
  const pending = Promise.withResolvers();
  const reply = app.replyFor.bind(app);
  app.replyFor = request => request.method === 'workspace.add' ? pending.promise : reply(request);
  await page.locator('#empty-project-trigger').click();
  await page.locator('#empty-project-menu').locator('#empty-project-new').click();
  await page.locator('#project-picker-dialog').locator('#project-picker-add').click();
  await expect.poll(() => app.requests.some(r => r.method === 'workspace.add')).toBe(true);
  await page.locator('#sidebar-settings').click();
  await page.getByRole('dialog').locator('[data-slot="dialog-close"]').click();
  await expect(page).toHaveURL(/\/codex\/new$/);
  await expect(page.locator('#transcript')).toHaveAttribute('data-transcript-session', session);
  await expect(page.locator('#openseek-model-picker:visible, #codex-model-picker:visible')).toBeDisabled();
  pending.resolve(reply(app.requests.find(r => r.method === 'workspace.add')));
  app.notify('workspace.changed', { workspaces: app.workspaces });
  await expect(page.locator('#empty-project-trigger')).toBeVisible();
  await expect(page.locator('#transcript')).toHaveAttribute('data-transcript-session', session);
  await expect(page.locator('#task')).toHaveValue('');
  await expect(page).toHaveURL(/\/codex\/new$/);
  expect(app.pageErrors).toEqual([]);
});

// The two conditions are independent, so each value runs once.
for (const [detachPrevious, managementPage] of [[false, null], [true, 'Settings']]) {
  test(`a pending project add preserves its draft while sending is blocked (detach previous: ${detachPrevious}, page: ${managementPage})`, async ({ page }) => {
    const app = await open(page, ['/workspace', '/other'], true);
    await chooseCodex(page);
    await expect.poll(() => app.requests.some(r => r.method === 'codex.draft.open')).toBe(true);
    await expect(page.locator('#empty-project-trigger')).toBeVisible();
    await page.locator('#task').fill('Send in the added project');
    await expect(page.locator('#send')).toBeEnabled();
    const session = await page.locator('#transcript').getAttribute('data-transcript-session');
    const pending = Promise.withResolvers();
    const reply = app.replyFor.bind(app);
    app.replyFor = request => request.method === 'workspace.add' ? pending.promise : reply(request);
    await page.locator('#empty-project-trigger').click();
    await page.locator('#empty-project-menu').locator('#empty-project-new').click();
    await page.locator('#project-picker-dialog').locator('#project-picker-add').click();
    await expect.poll(() => app.requests.some(r => r.method === 'workspace.add')).toBe(true);
    await expect(page.locator('#empty-project-trigger')).toHaveCount(0);
    const addRequest = app.requests.find(r => r.method === 'workspace.add');
    await expect(page.locator('#send')).toBeDisabled();
    await expect(page.locator('#openseek-model-picker:visible, #codex-model-picker:visible')).toBeDisabled();
    await page.locator('#task').press('Enter');
    expect(app.requests.some(r => r.method === 'codex.thread.start')).toBe(false);
    await expect(page.locator('#task')).toHaveValue('Send in the added project');
    if (managementPage) {
      await page.locator('#sidebar-settings').click();
      await expect(page.getByRole('dialog')).toBeVisible();
      if (managementPage === 'Settings') {
        await expect(page.locator('#codex-logout')).toBeDisabled();
      }
    }
    if (detachPrevious) {
      app.workspaces = app.workspaces.filter(path => path !== '/workspace');
    }
    pending.resolve(reply(addRequest));
    app.notify('workspace.changed', { workspaces: app.workspaces });
    await expect.poll(() => app.requests.filter(r => r.method === 'codex.draft.open').at(-1)?.params.cwd).toBe('/Users/test');
    if (managementPage) {
      const back = page.getByRole('dialog').locator('[data-slot="dialog-close"]');
      await expect(back).toBeVisible();
      if (managementPage === 'Settings') {
        await expect(page.locator('#codex-logout')).toBeEnabled();
      }
      await back.click();
    }
    await expect(page.locator('#empty-project-trigger')).toBeVisible();
    await expect(app.projectRow('/Users/test')).toHaveClass(/\bactive\b/);
    expect(app.requests.filter(r => r.method === 'codex.draft.open').map(r => r.params.cwd)).toEqual(['/workspace', '/Users/test']);
    await expect(page.locator('#transcript')).toHaveAttribute('data-transcript-session', session);
    await expect(page.locator('#task')).toHaveValue('Send in the added project');
    await expect(page.locator('#openseek-model-picker:visible, #codex-model-picker:visible')).toBeEnabled();
    await page.locator('#send').click();
    await expect.poll(() => app.requests.find(r => r.method === 'codex.thread.start')?.params.cwd).toBe('/Users/test');
    expect(app.pageErrors).toEqual([]);
  });
}

{
  const managementPage = 'Settings';

  for (const broadcastFirst of [false, true]) {
    test(`adding a project behind ${managementPage} preserves its draft (broadcast first: ${broadcastFirst})`, async ({ page }) => {
      const app = await open(page, ['/workspace', '/other']);
      await chooseCodex(page);
      await expect(page.locator('#empty-project-trigger')).toBeVisible();
      await page.locator('#task').fill('Keep the hidden draft');
      const session = await page.locator('#transcript').getAttribute('data-transcript-session');
      const pending = Promise.withResolvers();
      const reply = app.replyFor.bind(app);
      app.replyFor = request => request.method === 'workspace.add' ? pending.promise : reply(request);
      await page.locator('[id="section:openseek.projects:remote.device-a:action"]').click();
      await page.locator('#project-picker-dialog').locator('#project-picker-add').click();
      await expect.poll(() => app.requests.some(r => r.method === 'workspace.add')).toBe(true);
      await page.locator('#sidebar-settings').click();
      const result = reply(app.requests.find(r => r.method === 'workspace.add'));
      if (broadcastFirst) {
        app.notify('workspace.changed', { workspaces: app.workspaces });
        await expect(app.projectRow('/Users/test')).toBeVisible();
        pending.resolve(result);
      } else {
        pending.resolve(result);
        // Let the RPC callback settle before publishing the registry snapshot.
        await page.waitForTimeout(100);
        app.notify('workspace.changed', { workspaces: app.workspaces });
      }
      await expect.poll(() => app.requests.filter(r => r.method === 'codex.draft.open').at(-1)?.params.cwd).toBe('/Users/test');
      const back = page.getByRole('dialog').locator('[data-slot="dialog-close"]');
      await expect(back).toBeVisible();
      await back.click();
      await expect(page.locator('#transcript')).toHaveAttribute('data-transcript-session', session);
      await expect(page.locator('#task')).toHaveValue('Keep the hidden draft');
      await expect(page.locator('#empty-project-trigger')).toBeVisible();
      expect(app.pageErrors).toEqual([]);
    });
  }
}

for (const agent of ['Codex', 'OpenSeek']) {
  test(`a completed project add does not replace a newer ${agent} sidebar selection`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    app.codexModels = [{ id: 'gpt-test', displayName: 'Codex test', isDefault: true }];
    const existing = {
      id: 'codex-existing', cwd: '/workspace', projectRoot: '/workspace',
      preview: 'Existing Codex task', updatedAt: 2, turns: [],
    };
    const pending = Promise.withResolvers();
    const reply = app.replyFor.bind(app);
    app.replyFor = request => {
      if (request.method === 'codex.thread.list') return { data: request.params?.archived ? [] : [existing] };
      if (request.method === 'codex.thread.history.read') return { thread: existing };
      if (request.method === 'workspace.add') return pending.promise;
      return reply(request);
    };
    await app.install();
    await app.goto();
    await chooseCodex(page);
    await page.locator('#task').fill('Leave the selected thread alone');
    await page.locator('#empty-project-trigger').click();
    await page.locator('#empty-project-menu').locator('#empty-project-new').click();
    await page.locator('#project-picker-dialog').locator('#project-picker-add').click();
    await expect.poll(() => app.requests.some(r => r.method === 'workspace.add')).toBe(true);
    const session = agent === 'Codex' ? existing.id : 'session-1';
    await app.sessionButton(session, { source: agent === 'Codex' ? 'codex.live' : 'openseek.live' }).click();
    await expect(page.locator('#transcript')).toHaveAttribute('data-transcript-session', session);
    const opens = app.requests.filter(r => r.method === 'codex.draft.open').length;
    pending.resolve(reply(app.requests.find(r => r.method === 'workspace.add')));
    app.notify('workspace.changed', { workspaces: app.workspaces });
    await expect(app.projectRow('/Users/test')).toBeVisible();
    await expect(page.locator('#transcript')).toHaveAttribute('data-transcript-session', session);
    await expect(app.projectRow('/workspace')).toHaveClass(/\bactive\b/);
    expect(app.requests.filter(r => r.method === 'codex.draft.open')).toHaveLength(opens);
    expect(app.pageErrors).toEqual([]);
  });
}

test('a failed hidden Codex draft does not block adding a project from OpenSeek', async ({ page }) => {
  const app = await open(page);
  await chooseCodex(page);
  await page.locator('#task').fill('Retry this Codex prompt later');
  app.rpcErrors.set('codex.thread.start', 'Reply lost');
  await page.locator('#send').click();
  await expect(page.locator('#transcript .transcript-error-message')).toBeVisible();
  await expect(page.locator('[id="section:openseek.projects:remote.device-a:action"]')).toBeDisabled();
  await app.sessionButton().click();
  await expect(page.locator('#transcript')).toHaveAttribute('data-transcript-session', 'session-1');
  await expect(page.locator('[id="section:openseek.projects:remote.device-a:action"]')).toBeEnabled();
  await page.locator('#sidebar-settings').click();
  await expect(page.locator('[id="section:openseek.projects:remote.device-a:action"]')).toBeEnabled();
  await page.keyboard.press('ControlOrMeta+o');
  await expect(page.locator('#project-picker-dialog')).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

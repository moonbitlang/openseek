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
  await expect(page.getByRole('button', { name: 'Rabbita browser fixture', exact: true })).toBeVisible();
  return app;
}

async function choose(page, name) {
  await page.getByRole('button', { name: 'Model', exact: true }).click();
  await page.getByRole('option', { name, exact: true }).click();
  await expect(page.getByRole('button', { name: 'Model', exact: true })).toContainText(name);
}

test('both agents share the first screen and Codex can choose its project in the title', async ({ page }) => {
  const app = await open(page, ['/workspace', '/other']);
  const title = page.locator('.empty-title');
  const badge = page.locator('.empty-badge');
  const transcript = page.locator('#transcript');
  await expect(title).toHaveText('What should we build in workspace?');
  const logo = await badge.innerHTML();
  await choose(page, 'Codex test');
  const trigger = page.getByRole('button', {
    name: 'Choose project, current project workspace', exact: true,
  });
  await expect(trigger).toBeVisible();
  expect(await badge.innerHTML()).toBe(logo);
  const session = await transcript.getAttribute('data-transcript-session');
  const openCount = app.requests.filter(r => r.method === 'codex.draft.open').length;
  const task = page.locator('#task');
  await task.fill('@main');
  await page.locator('.completion-item').filter({ hasText: 'src/main.mbt' }).click();
  await task.press('End');
  await task.pressSequentially(' Keep this draft when changing projects');
  const draftText = await task.inputValue();
  const png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aCfoAAAAASUVORK5CYII=';
  const imageURL = `data:image/png;base64,${png}`;
  const chooser = page.waitForEvent('filechooser');
  await page.getByRole('button', { name: 'Attach files', exact: true }).click();
  await (await chooser).setFiles({ name: 'screen.png', mimeType: 'image/png', buffer: Buffer.from(png, 'base64') });
  await expect(page.locator('.composer-image img')).toHaveAttribute('src', imageURL);

  await trigger.click();
  const picker = page.getByRole('dialog', { name: 'Choose a project' });
  const search = picker.getByRole('textbox', { name: 'Search projects' });
  await expect(search).toBeFocused();
  await search.fill('oth');
  await expect(picker.getByRole('button', { name: /^workspace/ })).toHaveCount(0);
  await expect(picker.getByRole('button', { name: /^other —/ })).toBeVisible();
  await search.press('Escape');
  await expect(picker).toBeHidden();
  await expect(trigger).toBeFocused();
  await trigger.click();
  await picker.getByRole('button', { name: /^workspace, current project/ }).click();
  await expect(picker).toBeHidden();
  await expect(transcript).toHaveAttribute('data-transcript-session', session);
  expect(app.requests.filter(r => r.method === 'codex.draft.open')).toHaveLength(openCount);
  await trigger.click();
  await picker.getByRole('button', { name: /^other —/ }).click();
  await expect(title).toHaveText('What should we build in other?');
  await expect(app.projectRow('/other')).toHaveClass(/\bactive\b/);
  await expect(transcript).toHaveAttribute('data-transcript-session', session);
  await expect(page.getByRole('button', { name: 'Model', exact: true })).toContainText('Codex test');
  await expect.poll(() => app.requests.filter(r => r.method === 'codex.draft.open').at(-1)?.params.cwd).toBe('/other');
  await expect(task).toHaveValue(draftText);
  await expect(page.locator('.composer-image img')).toHaveAttribute('src', imageURL);
  await expect(page.locator('.mention-chip').filter({ hasText: 'src/main.mbt' })).toContainText('src/main.mbt');
  expect(app.requests.filter(r => r.method === 'codex.draft.close')).toHaveLength(0);
  const otherTrigger = page.getByRole('button', {
    name: 'Choose project, current project other', exact: true,
  });
  await otherTrigger.click();
  await picker.getByRole('button', { name: 'New project', exact: true }).click();
  const addProject = page.getByRole('dialog', { name: 'Add a project' });
  await expect(addProject).toBeVisible();
  await addProject.getByRole('button', { name: 'Add project', exact: true }).click();
  await expect.poll(() => app.requests.some(r => r.method === 'workspace.add')).toBe(true);
  app.notify('workspace.changed', { workspaces: app.workspaces });
  await expect(title).toHaveText('What should we build in test?');
  await expect(transcript).toHaveAttribute('data-transcript-session', session);
  await expect(task).toHaveValue(draftText);
  await expect(page.locator('.composer-image img')).toHaveAttribute('src', imageURL);
  await expect(page.locator('.mention-chip')).toContainText('src/main.mbt');
  await expect(addProject).toBeHidden();
  await page.locator('#send').click();
  await expect.poll(() => app.requests.find(r => r.method === 'codex.thread.start')?.params.cwd).toBe('/Users/test');
  await expect(page.getByRole('button', { name: /^Choose project, current project/ })).toHaveCount(0);
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
    await choose(page, 'Codex test');
    const task = page.locator('#task');
    await task.fill('Keep this input after an open failure');
    const session = await page.locator('#transcript').getAttribute('data-transcript-session');
    const reply = app.replyFor.bind(app);
    if (failure === 'rpc') {
      app.rpcErrors.set('codex.draft.open', 'Project unavailable');
    } else {
      app.replyFor = request => request.method === 'codex.draft.open' ? {} : reply(request);
    }
    await page.getByRole('button', { name: 'Choose project, current project workspace', exact: true }).click();
    const picker = page.getByRole('dialog', { name: 'Choose a project' });
    await picker.getByRole('button', { name: /^other —/ }).click();
    const other = page.getByRole('button', { name: 'Choose project, current project other', exact: true });
    await expect(other).toBeVisible();
    await expect(page.locator('#send')).toBeDisabled();
    // Wait for the error result to settle before retrying the same project.
    await expect(page.getByText(failure === 'rpc' ? /Project unavailable/ : /Malformed reply from codex.draft.open/)).toBeVisible();
    app.rpcErrors.delete('codex.draft.open');
    app.replyFor = reply;
    await other.click();
    if (failure === 'rpc') {
      await picker.getByRole('button', { name: /^other, current project/ }).click();
    } else {
      await picker.getByRole('button', { name: /^workspace —/ }).click();
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
  await choose(page, 'Codex test');
  await page.locator('#task').fill('Retry this prompt');
  app.rpcErrors.set('codex.thread.start', 'Reply lost');
  await page.locator('#send').click();
  await expect(page.getByText(/Reply lost/)).toBeVisible();
  await expect(page.getByRole('button', { name: /^Choose project, current project/ })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'New Project', exact: true })).toBeDisabled();
  await expect(page.locator('#task')).toHaveValue('Retry this prompt');
  await page.keyboard.press('ControlOrMeta+o');
  await expect(page.getByRole('dialog', { name: 'Add a project' })).toHaveCount(0);
  expect(app.requests.some(r => r.method === 'workspace.add')).toBe(false);
  const first = app.requests.find(r => r.method === 'codex.thread.start');
  app.rpcErrors.delete('codex.thread.start');
  await page.locator('#send').click();
  await expect.poll(() => app.requests.filter(r => r.method === 'codex.thread.start').length).toBe(2);
  expect(app.requests.filter(r => r.method === 'codex.thread.start')[1].params).toEqual(first.params);
  await expect.poll(() => app.requests.some(r => r.method === 'codex.turn.start')).toBe(true);
  await expect(page.getByRole('button', { name: 'New Project', exact: true })).toBeEnabled();
  expect(app.pageErrors).toEqual([]);
});

test('the title cannot add or change projects until draft opening settles', async ({ page }) => {
  const app = await open(page, ['/workspace', '/other']);
  const pending = Promise.withResolvers();
  const reply = app.replyFor.bind(app);
  app.replyFor = request => request.method === 'codex.draft.open' ? pending.promise : reply(request);
  await choose(page, 'Codex test');
  await expect.poll(() => app.requests.some(r => r.method === 'codex.draft.open')).toBe(true);
  await expect(page.getByRole('button', { name: /^Choose project, current project/ })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'New Project', exact: true })).toBeDisabled();
  const request = app.requests.find(r => r.method === 'codex.draft.open');
  app.replyFor = reply;
  pending.resolve(reply(request));
  await expect(page.getByRole('button', { name: 'New Project', exact: true })).toBeEnabled();
  await page.getByRole('button', { name: 'Choose project, current project workspace', exact: true }).click();
  await page.getByRole('dialog', { name: 'Choose a project' }).getByRole('button', { name: 'New project', exact: true }).click();
  await page.getByRole('dialog', { name: 'Add a project' }).getByRole('button', { name: 'Add project', exact: true }).click();
  await expect.poll(() => app.requests.some(r => r.method === 'workspace.add')).toBe(true);
  app.notify('workspace.changed', { workspaces: app.workspaces });
  await expect(page.getByRole('button', { name: 'Choose project, current project test', exact: true })).toBeVisible();
  await page.locator('#task').fill('Use the newly added project');
  await page.locator('#send').click();
  await expect.poll(() => app.requests.find(r => r.method === 'codex.thread.start')?.params.cwd).toBe('/Users/test');
  expect(app.pageErrors).toEqual([]);
});

test('returning to the same blank Codex entry retains its pending project add', async ({ page }) => {
  const app = await open(page, ['/workspace', '/other'], true);
  await choose(page, 'Codex test');
  await expect(page).toHaveURL(/\/codex\/new$/);
  const session = await page.locator('#transcript').getAttribute('data-transcript-session');
  const pending = Promise.withResolvers();
  const reply = app.replyFor.bind(app);
  app.replyFor = request => request.method === 'workspace.add' ? pending.promise : reply(request);
  await page.getByRole('button', { name: 'Choose project, current project workspace', exact: true }).click();
  await page.getByRole('dialog', { name: 'Choose a project' }).getByRole('button', { name: 'New project', exact: true }).click();
  await page.getByRole('dialog', { name: 'Add a project' }).getByRole('button', { name: 'Add project', exact: true }).click();
  await expect.poll(() => app.requests.some(r => r.method === 'workspace.add')).toBe(true);
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await page.getByRole('dialog').getByRole('button', { name: 'Dismiss', exact: true }).click();
  await expect(page).toHaveURL(/\/codex\/new$/);
  await expect(page.locator('#transcript')).toHaveAttribute('data-transcript-session', session);
  await expect(page.getByRole('button', { name: 'Model', exact: true })).toBeDisabled();
  pending.resolve(reply(app.requests.find(r => r.method === 'workspace.add')));
  app.notify('workspace.changed', { workspaces: app.workspaces });
  await expect(page.getByRole('button', { name: 'Choose project, current project test', exact: true })).toBeVisible();
  await expect(page.locator('#transcript')).toHaveAttribute('data-transcript-session', session);
  await expect(page.locator('#task')).toHaveValue('');
  await expect(page).toHaveURL(/\/codex\/new$/);
  expect(app.pageErrors).toEqual([]);
});

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
    await choose(page, 'Codex test');
    await page.locator('#task').fill('Leave the selected thread alone');
    await page.getByRole('button', { name: 'Choose project, current project workspace', exact: true }).click();
    await page.getByRole('dialog', { name: 'Choose a project' }).getByRole('button', { name: 'New project', exact: true }).click();
    await page.getByRole('dialog', { name: 'Add a project' }).getByRole('button', { name: 'Add project', exact: true }).click();
    await expect.poll(() => app.requests.some(r => r.method === 'workspace.add')).toBe(true);
    const title = agent === 'Codex' ? 'Existing Codex task' : 'Rabbita browser fixture';
    const session = agent === 'Codex' ? existing.id : 'session-1';
    await page.getByRole('button', { name: title, exact: true }).click();
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
  await choose(page, 'Codex test');
  await page.locator('#task').fill('Retry this Codex prompt later');
  app.rpcErrors.set('codex.thread.start', 'Reply lost');
  await page.locator('#send').click();
  await expect(page.getByText(/Reply lost/)).toBeVisible();
  await expect(page.getByRole('button', { name: 'New Project', exact: true })).toBeDisabled();
  await page.getByRole('button', { name: 'Rabbita browser fixture', exact: true }).click();
  await expect(page.locator('#transcript')).toHaveAttribute('data-transcript-session', 'session-1');
  await expect(page.getByRole('button', { name: 'New Project', exact: true })).toBeEnabled();
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await expect(page.getByRole('button', { name: 'New Project', exact: true })).toBeEnabled();
  await page.keyboard.press('ControlOrMeta+o');
  await expect(page.getByRole('dialog', { name: 'Add a project' })).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

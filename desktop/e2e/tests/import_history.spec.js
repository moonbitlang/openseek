import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

const event = (sequence, kind, payload) => ({ sequence, item: { kind, payload } });
const events = [
  event(1, 'user', { content: 'Hello from imported history' }),
  event(2, 'assistant', { content: 'Historical answer', tool_calls: [] }),
  event(3, 'terminal', { kind: 'finished', message: 'Historical answer' }),
];
const log = [{ version: 1, id: 'original', system_prompt: 'Historical environment' }, ...events].map(JSON.stringify).join('\n') + '\n';
const json = JSON.stringify({
  '/api/sessions': JSON.stringify([{ key: 'session-0', id: 'original', first_prompt: 'Imported fixture' }]),
  '/api/sessions/session-0': JSON.stringify({ found: true, events: log }),
});
const success = session_id => ({ status: 'success', session_id });
const failed = message => ({ status: 'failed', message });

async function setup(page, worktree = false, unplaced = false) {
  const app = new DesktopBrowserHarness(page);
  if (unplaced) {
    app.workspaces = [];
    app.liveSessions = [];
    app.sessionGroups = sessions => ({ groups: app.workspaces.map(workspace => ({ workspace, name: 'Unnamed workspace', session_root: `${workspace}/.openseek`, sessions, error: '' })) });
  }
  const original = app.replyFor.bind(app);
  app.importFailure = null;
  app.imports = new Map();
  const trees = worktree ? [{ name: 'feature', sessions: ['session-1'], path: '/workspace/.worktrees/feature', present: true, branch: 'feature', base: 'main', codex_thread: null }] : [];
  app.replyFor = request => {
    if (request.method === 'workspace.add') {
      if (app.workspaceFailure) return { error: app.workspaceFailure };
      const reply = original(request);
      app.notify('workspace.changed', { ...reply, chat_root: app.chatRoot });
      return reply;
    }
    if (request.method === 'worktree.list') return { worktrees: trees };
    if (request.method === 'session.import') {
      if (app.importFailure) return failed(app.importFailure);
      const session_id = `desktop-import-${app.imports.size}`;
      const row = { id: session_id, title: 'Imported fixture', updated_at_ms: null };
      app.imports.set(session_id, request.params.workspace);
      app.liveSessions.push(row);
      if (request.params.worktree_of && trees.length) trees[0].sessions.push(session_id);
      app.notify('worktree.changed', { workspace: request.params.workspace, worktrees: trees });
      app.notify('session.changed', { change: 'created', session: session_id, workspace: request.params.workspace });
      return success(session_id);
    }
    if (request.method === 'session.load' && app.imports.has(request.params.session)) {
      return { session: { version: 1, id: request.params.session, events }, watermark: null, prediction: null };
    }
    return original(request);
  };
  await app.install();
  await app.goto();
  if (unplaced) {
    await page.getByRole('group', { name: 'Sidebar list' }).getByRole('button', { name: 'Chat', exact: true }).click();
  } else {
    await app.openSession();
  }
  await openImport(page);
  const dialog = page.getByRole('dialog', { name: 'Import conversation' });
  await expect(dialog).toBeVisible();
  return { app, dialog };
}

async function openImport(page) {
  await expect(page.locator('.sidebar').getByRole('button', { name: 'Import conversation', exact: true })).toHaveCount(0);
  await page.getByRole('button', { name: 'Export and import', exact: true }).click();
  await page.getByRole('menuitem', { name: 'Import', exact: true }).click();
}

async function chooseJson(page, dialog) {
  const chooser = page.waitForEvent('filechooser');
  await dialog.getByRole('button', { name: 'Import JSON file' }).click();
  await (await chooser).setFiles({ name: 'conversation.json', mimeType: 'application/json', buffer: Buffer.from(json) });
}

async function expectWritable(page, app) {
  await expect(page.locator('#transcript')).toContainText('Hello from imported history');
  await expect(page.locator('#transcript')).toContainText('Historical answer');
  await expect(page.locator('#task')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Edit message', exact: true }).first()).toBeVisible();
  expect(app.pageErrors).toEqual([]);
}

for (const worktree of [false, true]) {
  test(`JSON opens a normal writable session in the ${worktree ? 'current worktree' : 'project'} and survives reload`, async ({ page }) => {
    const { app, dialog } = await setup(page, worktree);
    if (worktree) {
      const notify = app.notify.bind(app);
      app.notify = (...args) => setTimeout(() => notify(...args), 200);
    }
    await chooseJson(page, dialog);
    await expect(dialog).not.toBeVisible();
    const row = page.locator('.conversation-row').filter({ has: page.getByRole('button', { name: 'Imported fixture', exact: true }) });
    await expect(row).toHaveClass(/active/);
    await expectWritable(page, app);
    const imported = app.requests.find(request => request.method === 'session.import');
    expect(imported.params.source).toEqual({ kind: 'json', text: json });
    expect(imported.params.workspace).toBe('/workspace');
    expect(imported.params.worktree_of).toBe('session-1');
    await page.reload();
    await page.getByRole('button', { name: 'Imported fixture', exact: true }).click();
    await expectWritable(page, app);
  });
}

test('closing a pending import does not navigate away and narrow dialog fits', async ({ page }, testInfo) => {
  const { app, dialog } = await setup(page);
  await dialog.screenshot({ path: testInfo.outputPath('import-dialog-desktop.png') });
  await dialog.getByRole('button', { name: 'Close imported history' }).click();
  await page.setViewportSize({ width: 390, height: 844 });
  await openImport(page);
  expect(await dialog.evaluate(el => el.scrollWidth <= el.clientWidth)).toBe(true);
  await dialog.screenshot({ path: testInfo.outputPath('import-dialog-narrow.png') });
  app.rpcDelays.set('session.import', 300);
  await dialog.getByRole('textbox').fill('https://shares.example/v1/shares/sh_test');
  await dialog.getByRole('button', { name: 'Import link', exact: true }).click();
  await expect(dialog.getByRole('status')).toContainText('Importing');
  await dialog.getByRole('button', { name: 'Close imported history' }).click();
  await expect.poll(() => app.imports.size).toBe(1);
  await expect(dialog).not.toBeVisible();
  await expect(page.locator('#transcript')).toContainText('Show the browser fixture');
  expect(app.pageErrors).toEqual([]);
});


test('Chat import creates a chat workspace and appears in Chats after reload', async ({ page }, testInfo) => {
  const { app, dialog } = await setup(page, false, true);
  await dialog.getByRole('textbox').fill('https://shares.example/v1/shares/sh_test');
  await dialog.getByRole('button', { name: 'Import link', exact: true }).click();
  await expectWritable(page, app);
  const request = app.requests.find(request => request.method === 'session.import');
  expect(request.params.workspace).toBe(`${app.chatRoot}/Unnamed workspace`);
  expect(app.requests.filter(request => request.method === 'fs.create_unnamed_workspace')).toHaveLength(1);
  await expect(page.locator('.workspace-row')).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Imported fixture', exact: true })).toBeVisible();
  await page.reload();
  await page.getByRole('button', { name: 'Imported fixture', exact: true }).click();
  await expectWritable(page, app);
  await page.screenshot({ path: testInfo.outputPath('imported-chat.png') });
});


test('imported session accepts a new prompt using the selected workspace', async ({ page }) => {
  const { app, dialog } = await setup(page, true);
  await chooseJson(page, dialog);
  await expectWritable(page, app);
  await page.locator('#task').fill('Continue from this history');
  await page.locator('#send').click();
  await expect.poll(() => app.requests.find(request => request.method === 'agent.start')?.params.task).toBe('Continue from this history');
  const request = app.requests.find(request => request.method === 'agent.start');
  expect(request.params.session).toBe('desktop-import-0');
  expect(request.params.workspace).toBe('/workspace');
  expect(app.pageErrors).toEqual([]);
});

test('catalog failure after import retries navigation without importing again', async ({ page }) => {
  const { app, dialog } = await setup(page);
  app.rpcErrors.set('session.list', 'Catalog unavailable');
  await chooseJson(page, dialog);
  await expect(dialog).not.toBeVisible();
  await expect(page.locator('.navigation-notice')).toContainText('Catalog unavailable');
  app.rpcErrors.delete('session.list');
  await page.locator('.navigation-notice').getByRole('button', { name: 'Retry', exact: true }).click();
  await expectWritable(page, app);
  expect(app.requests.filter(request => request.method === 'session.import')).toHaveLength(1);
});

test('leaving while the imported catalog loads prevents a late navigation', async ({ page }) => {
  const { app, dialog } = await setup(page);
  app.rpcDelays.set('session.list', 1000);
  await chooseJson(page, dialog);
  await expect(page.locator('.navigation-notice')).toContainText('Loading destination');
  expect(app.requests.some(request => request.method === 'session.load' && request.params.session === 'desktop-import-0')).toBe(false);
  await page.getByRole('button', { name: 'Back', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Imported fixture', exact: true })).toBeVisible();
  await expect(page.locator('#transcript')).toContainText('Show the browser fixture');
  expect(app.requests.some(request => request.method === 'session.load' && request.params.session === 'desktop-import-0')).toBe(false);
});

for (const failure of ['import', 'registration']) {
  test(`Chat import reuses its workspace after ${failure} failures`, async ({ page }) => {
    const { app, dialog } = await setup(page, false, true);
    const link = 'https://shares.example/v1/shares/sh_test';
    await dialog.getByRole('textbox').fill(link);
    const error = failure === 'import' ? 'The share has expired.' : 'Could not register workspace.';
    if (failure === 'import') app.importFailure = error;
    else app.workspaceFailure = error;
    for (let attempt = 0; attempt < 2; attempt++) {
      await dialog.getByRole('button', { name: 'Import link', exact: true }).click();
      await expect(dialog.getByRole('status')).toHaveText(error);
      await expect(dialog.getByRole('textbox')).toHaveValue(link);
      await expect(dialog.getByRole('button', { name: 'Import link', exact: true })).toBeEnabled();
    }
    app.importFailure = null;
    app.workspaceFailure = null;
    await dialog.getByRole('button', { name: 'Import link', exact: true }).click();
    await expectWritable(page, app);
    expect(app.requests.filter(request => request.method === 'session.import').at(-1).params.source).toEqual({ kind: 'share', url: link });
    expect(app.requests.filter(request => request.method === 'fs.create_unnamed_workspace')).toHaveLength(1);
    const registrations = app.requests.filter(request => request.method === 'workspace.add');
    expect(registrations).toHaveLength(failure === 'registration' ? 3 : 1);
    const destinations = [...registrations.map(request => request.params.path),
      ...app.requests.filter(request => request.method === 'session.import').map(request => request.params.workspace)];
    expect(new Set(destinations).size).toBe(1);
  });
}

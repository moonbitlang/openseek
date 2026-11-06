import { test, expect } from './support/test.js';
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

async function setup(page, destination = '/workspace') {
  const app = new DesktopBrowserHarness(page);
  const original = app.replyFor.bind(app);
  app.importFailure = null;
  app.imports = new Map();
  app.workspaces = ['/workspace', '/other'];
  app.activeWorkspace = '/workspace';
  const trees = [];
  app.sessionGroups = sessions => ({ groups: [...new Set(['/workspace', ...app.imports.values()])].map(workspace => ({
    workspace, name: workspace === '/workspace' ? 'Fixture' : 'Imported project',
    session_root: `${workspace}/.openseek`, error: '',
    sessions: sessions.filter(row => (app.imports.get(row.id) || '/workspace') === workspace),
  })) });
  app.replyFor = request => {
    if (request.method === 'worktree.list') return { worktrees: trees };
    if (request.method === 'session.import') {
      if (app.importFailure) return failed(app.importFailure);
      const session_id = `desktop-import-${app.imports.size}`;
      const row = { id: session_id, title: 'Imported fixture', updated_at_ms: null };
      app.imports.set(session_id, request.params.workspace);
      app.liveSessions.push(row);
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
  await app.openSession();
  await openImport(page, destination);
  const dialog = page.getByRole('dialog', { name: 'Import conversation' });
  await expect(dialog).toBeVisible();
  return { app, dialog };
}

async function openImport(page, destination = '/workspace') {
  const sidebarToggle = page.getByRole('button', { name: 'Show sidebar', exact: true });
  if (await sidebarToggle.isVisible()) await sidebarToggle.click();
  const row = page.locator('.workspace-row').filter({
    has: page.getByRole('button', { name: destination.slice(1), exact: true }),
  });
  await row.hover();
  await row.getByRole('button', { name: 'Workspace actions', exact: true }).click();
  await page.getByRole('menuitem', { name: 'Import conversation', exact: true }).click();
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

for (const destination of ['/workspace', '/other']) {
  test(`JSON imports into the selected ${destination} project and survives reload`, async ({ page }) => {
    const { app, dialog } = await setup(page, destination);
    await chooseJson(page, dialog);
    await expect(dialog).not.toBeVisible();
    const row = page.locator('.conversation-row').filter({ has: page.getByRole('button', { name: 'Imported fixture', exact: true }) });
    await expect(row).toHaveClass(/active/);
    await expectWritable(page, app);
    const imported = app.requests.find(request => request.method === 'session.import');
    expect(imported.params.source).toEqual({ kind: 'json', text: json });
    expect(imported.params.workspace).toBe(destination);
    expect(imported.params.worktree_of).toBeNull();
    expect(app.requests.some(r => r.method === 'workspace.add')).toBe(false);
    await page.reload();
    await page.getByRole('button', { name: 'Imported fixture', exact: true }).click();
    await expectWritable(page, app);
  });
}

test('closing a pending import does not navigate away and narrow dialog fits', async ({ page }) => {
  const { app, dialog } = await setup(page);
  await dialog.getByRole('button', { name: 'Close imported history' }).click();
  await page.setViewportSize({ width: 390, height: 844 });
  await openImport(page);
  expect(await dialog.evaluate(el => el.scrollWidth <= el.clientWidth)).toBe(true);
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


test('imported session accepts a new prompt using the selected workspace', async ({ page }) => {
  const { app, dialog } = await setup(page);
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
  await page.goBack();
  await expect(page.getByRole('button', { name: 'Imported fixture', exact: true })).toBeVisible();
  await expect(page.locator('#transcript')).toContainText('Show the browser fixture');
  expect(app.requests.some(request => request.method === 'session.load' && request.params.session === 'desktop-import-0')).toBe(false);
});

test('a failed project import retains its destination and input for retry', async ({ page }) => {
  const { app, dialog } = await setup(page);
  const link = 'https://shares.example/v1/shares/sh_test';
  await dialog.getByRole('textbox').fill(link);
  app.importFailure = 'The share has expired.';
  await dialog.getByRole('button', { name: 'Import link', exact: true }).click();
  await expect(dialog.getByRole('status')).toHaveText(app.importFailure);
  await expect(dialog.getByRole('textbox')).toHaveValue(link);
  app.importFailure = null;
  await dialog.getByRole('button', { name: 'Import link', exact: true }).click();
  await expectWritable(page, app);
  const requests = app.requests.filter(request => request.method === 'session.import');
  expect(requests).toHaveLength(2);
  expect(requests.map(request => request.params.workspace)).toEqual(['/workspace', '/workspace']);
  expect(requests[1].params.source).toEqual({ kind: 'share', url: link });
});

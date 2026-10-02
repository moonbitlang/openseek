import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

async function open(page) {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  return app;
}

// The `<user_shell_command>` envelope the host hands the engine for a `!`
// command; the engine stores it as the durable user message.
function envelope(command, result) {
  return `<user_shell_command>\n<command>\n${command}\n</command>\n<result>\n${result}\n</result>\n</user_shell_command>`;
}

test('a leading ! switches the composer into shell mode and Backspace leaves it', async ({ page }) => {
  const app = await open(page);
  const task = page.locator('#task');
  await task.fill('!');
  await expect(page.locator('.composer-mode-chip')).toHaveText('shell');
  await expect(task).toHaveValue('');
  await expect(task).toHaveAttribute('placeholder', /Run a shell command/);
  await task.press('Backspace');
  await expect(page.locator('.composer-mode-chip')).toHaveCount(0);
  await expect(task).toHaveValue('');
  // Typed, not filled: `!` at the start of existing text enters shell mode
  // with that text as the command, and the marker leaves the field.
  await task.fill('git status');
  await task.press('Home');
  await task.press('!');
  await expect(page.locator('.composer-mode-chip')).toBeVisible();
  await expect(task).toHaveValue('git status');
  expect(app.pageErrors).toEqual([]);
});

test('a shell command runs through agent.shell and its output renders as a card', async ({ page }) => {
  const app = await open(page);
  app.rpcDelays.set('agent.shell', 600);
  const task = page.locator('#task');
  await task.pressSequentially('!ls -la');
  await expect(page.locator('.composer-mode-chip')).toBeVisible();
  await expect(task).toHaveValue('ls -la');
  // A person cannot type and press Enter inside one animation frame; a script
  // can, and Rabbita would then render the cleared draft once against the
  // value it last rendered (empty), patching nothing.
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  await task.press('Enter');
  // While the host runs it, the command is listed above the composer.
  await expect(page.locator('.shell-commands-running')).toContainText('$ ls -la');
  await expect(page.locator('.composer-mode-chip')).toHaveCount(0);
  await expect(task).toHaveValue('');
  await expect.poll(() => app.requests.find(r => r.method === 'agent.shell')?.params)
    .toMatchObject({ session: 'session-1', command: 'ls -la' });
  await expect(page.locator('.shell-commands-running')).toHaveCount(0);
  // The output arrives as the durable user message the engine appended.
  const text = envelope('ls -la', 'exit=2\ntotal 0\nls: cannot access x\n');
  const event = { sequence: 18, item: { kind: 'user', payload: { content: [{ type: 'text', text }] } } };
  app.sessionEvents.push(event);
  app.notify('session.event', { session: 'session-1', session_root: '/workspace/.openseek', sequence: 18, event });
  const card = page.locator('.user-bubble .user-shell-command');
  await expect(card.locator('.user-shell-line')).toHaveText('$ ls -la');
  await expect(card.locator('.user-shell-status')).toHaveText('exit 2');
  await expect(card.locator('.user-shell-output')).toHaveText('total 0\nls: cannot access x');
  await expect(page.locator('.user-bubble', { hasText: '<user_shell_command>' })).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('a refused shell command is reported', async ({ page }) => {
  const app = await open(page);
  app.rpcErrors.set('agent.shell', 'shell refused for the test');
  const task = page.locator('#task');
  await task.fill('!pwd');
  await expect(page.locator('.composer-mode-chip')).toBeVisible();
  await task.press('Enter');
  await expect(page.getByText('shell refused for the test', { exact: false }).first()).toBeVisible();
  await expect(page.locator('.shell-commands-running')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

async function typeCommand(page, text) {
  const task = page.locator('#task');
  await task.pressSequentially(text);
  await expect(page.locator('.composer-mode-chip')).toBeVisible();
  // A script, unlike a person, can type and press Enter inside one frame.
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  await task.press('Enter');
}

test('a first ! command in a fresh worktree-mode chat creates its worktree first', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  const replyFor = app.replyFor.bind(app);
  app.replyFor = request => request.method === 'worktree.create'
    ? { name: 'shell-e2e', worktrees: [{
        name: 'shell-e2e', branch: 'test', base: 'main', path: '/workspace/worktrees/shell-e2e', present: true,
      }] }
    : replyFor(request);
  await app.install();
  await app.goto();
  await page.locator('button.composer-worktree').click();
  await typeCommand(page, '!pwd');
  await expect.poll(() => app.requests.some(r => r.method === 'agent.shell')).toBe(true);
  const methods = app.requests.map(r => r.method);
  const create = app.requests.find(r => r.method === 'worktree.create');
  const shell = app.requests.find(r => r.method === 'agent.shell');
  expect(methods.indexOf('worktree.create')).toBeLessThan(methods.indexOf('agent.shell'));
  expect(shell.params.session).toBe(create.params.session);
  expect(shell.params.command).toBe('pwd');
  expect(app.pageErrors).toEqual([]);
});

test('a ! command whose worktree cannot be set up runs nothing and comes back', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.rpcErrors.set('worktree.create', 'not a git repository');
  await app.install();
  await app.goto();
  await page.locator('button.composer-worktree').click();
  await typeCommand(page, '!pwd');
  await expect(page.getByText('the command did not run', { exact: false }).first()).toBeVisible();
  await expect(page.locator('.composer-mode-chip')).toBeVisible();
  await expect(page.locator('#task')).toHaveValue('pwd');
  expect(app.requests.some(r => r.method === 'agent.shell')).toBe(false);
  expect(app.pageErrors).toEqual([]);
});

test('a steer sent while a ! command runs waits for its output', async ({ page }) => {
  const app = await open(page);
  const task = page.locator('#task');
  await task.fill('Begin');
  await page.locator('#send').click();
  await expect.poll(() => app.requests.some(r => r.method === 'agent.start')).toBe(true);
  const start = app.requests.find(r => r.method === 'agent.start');
  app.notify('agent.started', {
    run_id: 'run-e2e', session: 'session-1', session_root: '/workspace/.openseek',
    submission_id: start.params.submission_id, model: 'deepseek-v4-pro', max_steps: 1000,
  });
  app.rpcDelays.set('agent.shell', 1500);
  await typeCommand(page, '!moon test');
  await expect(page.locator('.shell-commands-running')).toContainText('$ moon test');
  await expect(task).toHaveValue('');
  await task.pressSequentially('fix the failures');
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  await task.press('Enter');
  await page.waitForTimeout(500);
  expect(app.requests.some(r => r.method === 'agent.steer')).toBe(false);
  await expect(page.locator('.shell-commands-running')).toHaveCount(0);
  await expect.poll(() => app.requests.find(r => r.method === 'agent.steer')?.params.text).toBe('fix the failures');
  expect(app.pageErrors).toEqual([]);
});

test('a steer deferred behind a ! command comes back if its turn ends first', async ({ page }) => {
  const app = await open(page);
  const replyFor = app.replyFor.bind(app);
  // The turn is over by the time the deferred steer goes out, so the host
  // refuses it, as a real host does for a finished run.
  app.replyFor = request => request.method === 'agent.steer'
    ? { steered: false }
    : replyFor(request);
  const task = page.locator('#task');
  await task.fill('Begin');
  await page.locator('#send').click();
  await expect.poll(() => app.requests.some(r => r.method === 'agent.start')).toBe(true);
  const start = app.requests.find(r => r.method === 'agent.start');
  app.notify('agent.started', {
    run_id: 'run-e2e', session: 'session-1', session_root: '/workspace/.openseek',
    submission_id: start.params.submission_id, model: 'deepseek-v4-pro', max_steps: 1000,
  });
  app.rpcDelays.set('agent.shell', 1500);
  await typeCommand(page, '!moon test');
  await expect(page.locator('.shell-commands-running')).toContainText('$ moon test');
  await task.pressSequentially('fix the failures');
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  await task.press('Enter');
  await expect(task).toHaveValue('');
  app.notify('agent.finished', { run_id: 'run-e2e', status: 'success', answer: 'done' });
  await expect.poll(() => app.requests.some(r => r.method === 'agent.steer')).toBe(true);
  await expect(task).toHaveValue('fix the failures');
  await expect(page.getByText('it is back in the composer', { exact: false }).first()).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

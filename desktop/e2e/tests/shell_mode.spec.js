import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

async function open(page) {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  return app;
}

// The `<user_shell_command>` envelope a `!` command's result travels in; the
// engine stores it as the durable user message.
function envelope(command, result) {
  return `<user_shell_command>\n<command>\n${command}\n</command>\n<result>\n${result}\n</result>\n</user_shell_command>`;
}

async function typeCommand(page, text) {
  const task = page.locator('#task');
  await task.pressSequentially(text);
  await expect(page.locator('.composer-mode-chip')).toBeVisible();
  // A script, unlike a person, can type and press Enter inside one animation
  // frame, which Rabbita would render once against an unchanged value.
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  await task.press('Enter');
}

// The terminal session the page opened for `command`: the harness names
// sessions `terminal-N` in open order.
async function commandTerminal(app, command) {
  await expect.poll(() => app.requests.some(r => r.method === 'terminal.open' && r.params.command === command)).toBe(true);
  const opens = app.requests.filter(r => r.method === 'terminal.open');
  return `terminal-${opens.findIndex(r => r.params.command === command) + 1}`;
}

// What the host pushes while a command runs and when it ends.
function print(app, id, text, sequence = 1) {
  app.notify('terminal.output', { id, sequence, data: Buffer.from(text).toString('base64') });
}

function exit(app, id, code) {
  app.notify('terminal.exit', { id, code });
}

async function startTurn(page, app) {
  await page.locator('#task').fill('Begin');
  await page.locator('#send').click();
  await expect.poll(() => app.requests.some(r => r.method === 'agent.start')).toBe(true);
  const start = app.requests.find(r => r.method === 'agent.start');
  app.notify('agent.started', {
    run_id: 'run-e2e', session: 'session-1', session_root: '/workspace/.openseek',
    submission_id: start.params.submission_id, model: 'deepseek-v4-pro', max_steps: 1000,
  });
  // The sent draft leaves the composer once the start is acknowledged; typing
  // before that would append to it.
  await expect(page.locator('#task')).toHaveValue('');
}

test('a leading ! switches the composer into shell mode and deleting it leaves', async ({ page }) => {
  const app = await open(page);
  const task = page.locator('#task');
  await task.fill('!');
  await expect(page.locator('.composer-mode-chip')).toHaveText('shell');
  await expect(task).toHaveValue('!');
  await task.press('Backspace');
  await expect(page.locator('.composer-mode-chip')).toHaveCount(0);
  await expect(task).toHaveValue('');
  // `!` typed at the start of existing text makes that text the command.
  await task.fill('git status');
  await task.press('Home');
  await task.press('!');
  await expect(page.locator('.composer-mode-chip')).toBeVisible();
  await expect(task).toHaveValue('!git status');
  expect(app.pageErrors).toEqual([]);
});

// A finished command's result is sent like a typed message: as the prompt of
// a new turn while the conversation is idle.
function sentResult(app) {
  return app.requests.filter(r => r.method === 'agent.start').at(-1)?.params.task;
}

// The running row's button: the terminal stays out of the way until asked for.
async function showTerminal(page) {
  await page.locator('.shell-commands-running').getByRole('button', { name: 'Terminal' }).click();
  await expect(page.locator('.terminal-panel.open')).toBeVisible();
}

test('a ! command runs in a terminal tab and its output becomes a card', async ({ page }) => {
  const app = await open(page);
  const task = page.locator('#task');
  await typeCommand(page, '!ls -la');
  // The command is a terminal session's only process, at a real terminal's
  // size, but the panel does not open for it: the composer keeps the focus
  // and lists the command as running.
  const id = await commandTerminal(app, 'ls -la');
  const opened = app.requests.find(r => r.method === 'terminal.open' && r.params.command === 'ls -la');
  expect(opened.params.cols).toBeGreaterThanOrEqual(80);
  expect(opened.params.rows).toBeGreaterThanOrEqual(24);
  await expect(page.locator('.terminal-panel.open')).toHaveCount(0);
  await expect(page.locator('.shell-commands-running')).toContainText('$ ls -la');
  await expect(page.locator('.composer-mode-chip')).toHaveCount(0);
  await expect(task).toHaveValue('');
  await expect(task).toBeFocused();
  expect(app.requests.some(r => r.method === 'agent.start')).toBe(false);
  // Colored output: the terminal shows the colors, the conversation gets the
  // text the terminal rendered.
  print(app, id, 'total 0\r\n\x1b[31mls: cannot access x\x1b[0m\r\n');
  exit(app, id, 2);
  // The result starts a turn, so the agent answers it.
  await expect.poll(() => app.requests.find(r => r.method === 'agent.start')?.params)
    .toMatchObject({ session: 'session-1', task: envelope('ls -la', 'exit=2\ntotal 0\nls: cannot access x') });
  await expect(page.locator('.shell-commands-running')).toHaveCount(0);
  // Its tab retired with it, and the panel never opened.
  await expect(page.locator('.terminal-tab')).toHaveCount(0);
  await expect(page.locator('.terminal-panel.open')).toHaveCount(0);
  // The output arrives as the durable user message the engine appended.
  const text = sentResult(app);
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

test('the running row opens the terminal, where Ctrl+C interrupts the command', async ({ page }) => {
  const app = await open(page);
  await typeCommand(page, '!sleep 100000');
  const id = await commandTerminal(app, 'sleep 100000');
  print(app, id, 'waiting...\r\n');
  await showTerminal(page);
  // What it printed while nobody was looking is on its screen.
  await expect(page.locator('.terminal-tab.active')).toContainText('$ sleep 100000');
  await expect(page.locator('.terminal-instance .xterm-rows').last()).toContainText('waiting...');
  await page.locator('.terminal-instance .xterm').last().click();
  await page.keyboard.press('Control+C');
  await expect.poll(() => app.requests.find(r => r.method === 'terminal.input')?.params)
    .toMatchObject({ id, data: '\x03' });
  // The host reports a signal death as a negative status: the command did
  // not choose an exit code, so the result reads as cancelled.
  print(app, id, '^C\r\n', 2);
  exit(app, id, -2);
  await expect.poll(() => sentResult(app))
    .toBe(envelope('sleep 100000', 'exit=cancelled\nwaiting...\n^C'));
  await expect(page.locator('.shell-commands-running')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('closing a running command tab settles the command as cancelled', async ({ page }) => {
  const app = await open(page);
  await typeCommand(page, '!npm run dev');
  const id = await commandTerminal(app, 'npm run dev');
  print(app, id, 'listening on :3000\r\n');
  await showTerminal(page);
  await expect(page.locator('.terminal-instance .xterm-rows').last()).toContainText('listening on :3000');
  await page.locator('.terminal-tab.active .terminal-tab-close').click();
  await expect.poll(() => app.requests.some(r => r.method === 'terminal.close' && r.params.id === id)).toBe(true);
  await expect.poll(() => sentResult(app))
    .toBe(envelope('npm run dev', 'exit=cancelled\nlistening on :3000'));
  await expect(page.locator('.shell-commands-running')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('a result the host refuses comes back to the composer', async ({ page }) => {
  const app = await open(page);
  app.rpcErrors.set('agent.start', 'start refused for the test');
  await typeCommand(page, '!pwd');
  const id = await commandTerminal(app, 'pwd');
  print(app, id, '/workspace\r\n');
  exit(app, id, 0);
  await expect(page.getByText('start refused for the test', { exact: false }).first()).toBeVisible();
  await expect(page.locator('.shell-commands-running')).toHaveCount(0);
  // Nothing the command printed is lost: the result is the restored draft.
  await expect(page.locator('#task')).toHaveValue(envelope('pwd', 'exit=0\n/workspace'));
  expect(app.pageErrors).toEqual([]);
});

test('a ! command whose terminal cannot open runs nothing and comes back', async ({ page }) => {
  const app = await open(page);
  app.rpcErrors.set('terminal.open', 'terminal requires a conversation workspace');
  await typeCommand(page, '!pwd');
  await expect(page.getByText('terminal requires a conversation workspace', { exact: false }).first()).toBeVisible();
  await expect(page.locator('.composer-mode-chip')).toBeVisible();
  await expect(page.locator('#task')).toHaveValue('!pwd');
  await expect(page.locator('.shell-commands-running')).toHaveCount(0);
  expect(app.requests.some(r => r.method === 'agent.start')).toBe(false);
  expect(app.pageErrors).toEqual([]);
});

test('a first ! command in a fresh worktree-mode chat creates its worktree first', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  const replyFor = app.replyFor.bind(app);
  app.replyFor = request => {
    if (request.method !== 'worktree.create') return replyFor(request);
    const worktrees = [{
      name: 'shell-e2e', branch: 'test', base: 'main', path: '/workspace/worktrees/shell-e2e', present: true,
      session: request.params.session,
    }];
    // The registry row reaches the page as its own broadcast, after the
    // reply: the command waits for it to learn the checkout it runs in.
    setTimeout(() => app.notify('worktree.changed', { workspace: '/workspace', worktrees }), 300);
    return { name: 'shell-e2e', worktrees };
  };
  await app.install();
  await app.goto();
  await page.locator('button.composer-worktree').click();
  await typeCommand(page, '!pwd');
  const id = await commandTerminal(app, 'pwd');
  const methods = app.requests.map(r => r.method);
  const create = app.requests.find(r => r.method === 'worktree.create');
  const terminal = app.requests.find(r => r.method === 'terminal.open');
  expect(methods.indexOf('worktree.create')).toBeLessThan(methods.indexOf('terminal.open'));
  expect(terminal.params.session).toBe(create.params.session);
  print(app, id, '/workspace/worktrees/shell-e2e\r\n');
  exit(app, id, 0);
  // The result then starts an ordinary turn in the bound session: the
  // worktree exists, so nothing is created twice.
  await expect.poll(() => app.requests.find(r => r.method === 'agent.start')?.params.session).toBe(create.params.session);
  expect(app.requests.filter(r => r.method === 'worktree.create')).toHaveLength(1);
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
  await expect(page.locator('#task')).toHaveValue('!pwd');
  expect(app.requests.some(r => r.method === 'terminal.open')).toBe(false);
  expect(app.requests.some(r => r.method === 'agent.start')).toBe(false);
  expect(app.pageErrors).toEqual([]);
});

test('a command that finishes mid-turn steers the running turn with its result', async ({ page }) => {
  const app = await open(page);
  await startTurn(page, app);
  await typeCommand(page, '!moon test');
  const id = await commandTerminal(app, 'moon test');
  print(app, id, '2 tests failed\r\n');
  exit(app, id, 1);
  await expect.poll(() => app.requests.find(r => r.method === 'agent.steer')?.params)
    .toMatchObject({ run_id: 'run-e2e', text: envelope('moon test', 'exit=1\n2 tests failed') });
  // One turn is open; the result joined it and started no second one.
  expect(app.requests.filter(r => r.method === 'agent.start')).toHaveLength(1);
  await expect(page.locator('.shell-commands-running')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('a quick command that ends before its terminal reply still delivers its output', async ({ page }) => {
  const app = await open(page);
  // `!ls` routinely finishes before `terminal.open` answers: the output and
  // the exit arrive for a session the page cannot name yet.
  app.rpcDelays.set('terminal.open', 400);
  await typeCommand(page, '!ls');
  const id = await commandTerminal(app, 'ls');
  print(app, id, 'README.md\r\nsrc\r\n');
  exit(app, id, 0);
  await expect.poll(() => sentResult(app)).toBe(envelope('ls', 'exit=0\nREADME.md\nsrc'));
  await expect(page.locator('.shell-commands-running')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('a tab closed as its command exits still delivers the result once', async ({ page }) => {
  const app = await open(page);
  await typeCommand(page, '!make');
  const id = await commandTerminal(app, 'make');
  print(app, id, 'built\r\n');
  await showTerminal(page);
  await expect(page.locator('.terminal-instance .xterm-rows').last()).toContainText('built');
  // The exit's report waits for the emulator to finish rendering, then the
  // tab retires by itself; closing it by hand disposes that emulator sooner.
  // Whichever gets there first reports, and only once.
  exit(app, id, 0);
  await page.locator('.terminal-tab.active .terminal-tab-close').click({ timeout: 1000 }).catch(() => {});
  await expect.poll(() => app.requests.filter(r => r.method === 'agent.start').length).toBe(1);
  expect(sentResult(app)).toContain('\nbuilt\n');
  await expect(page.locator('.shell-commands-running')).toHaveCount(0);
  await page.waitForTimeout(300);
  expect(app.requests.filter(r => r.method === 'agent.start').length).toBe(1);
  expect(app.pageErrors).toEqual([]);
});

test('a command finishing beside an open shell tab leaves the keyboard in the composer', async ({ page }) => {
  const app = await open(page);
  // The user's own shell is open in the panel.
  await page.locator('button[title*="erminal (Ctrl"]').first().click();
  await expect(page.locator('.terminal-panel.open .terminal-tab')).toHaveCount(1);
  await page.locator('#task').click();
  await typeCommand(page, '!ls');
  const id = await commandTerminal(app, 'ls');
  await expect(page.locator('.terminal-tab')).toHaveCount(2);
  print(app, id, 'src\r\n');
  exit(app, id, 0);
  // The command tab retires and the shell tab is back on screen, but the
  // next keystrokes still belong to the draft.
  await expect(page.locator('.terminal-tab')).toHaveCount(1);
  await expect(page.locator('.terminal-panel.open')).toBeVisible();
  await expect(page.locator('#task')).toBeFocused();
  expect(app.pageErrors).toEqual([]);
});

test('a wide character at the wrap column gains no space in the result', async ({ page }) => {
  const app = await open(page);
  await typeCommand(page, '!ls');
  const id = await commandTerminal(app, 'ls');
  // 79 columns of ASCII, then a double-width character that cannot fit in the
  // 80th: the terminal wraps it whole and leaves that cell empty.
  const line = 'a'.repeat(79) + '文件.txt';
  // A space the command did print stays.
  print(app, id, line + '\r\nprinted trailing space \r\n');
  exit(app, id, 0);
  await expect.poll(() => sentResult(app)).toBe(envelope('ls', 'exit=0\n' + line + '\nprinted trailing space '));
  expect(app.pageErrors).toEqual([]);
});

test('output that outruns the terminal scrollback is marked truncated', async ({ page }) => {
  const app = await open(page);
  await typeCommand(page, '!yes');
  const id = await commandTerminal(app, 'yes');
  // More lines than the emulator keeps: the first ones are gone for good,
  // even though what is left is short.
  print(app, id, 'first line\r\n' + '\r\n'.repeat(10100) + 'last line\r\n');
  exit(app, id, 0);
  await expect.poll(() => sentResult(app), { timeout: 15000 }).toBeTruthy();
  const result = sentResult(app);
  expect(result).toContain('truncated=true');
  expect(result).toContain('last line');
  expect(result).not.toContain('first line');
  expect(app.pageErrors).toEqual([]);
});

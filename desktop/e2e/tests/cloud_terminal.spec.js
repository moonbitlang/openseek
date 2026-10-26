import { test, expect } from '@playwright/test';
import { CloudHarness, sessionA, sessionB, sessionC } from './support/cloud_harness.js';
import { CloudTerminalHarness } from './support/cloud_terminal_harness.js';

const show = page => page.getByRole('button', { name: 'Show terminal (Ctrl+`)', exact: true });
const hide = page => page.getByRole('button', { name: 'Hide terminal (Ctrl+`)', exact: true });
const screen = page => page.locator('.terminal-instance:visible .xterm-rows');
const input = page => page.locator('.terminal-instance:visible .xterm-helper-textarea');
const creations = cloud => cloud.requests.filter(request => request.method === 'POST' && request.path === '/v1/sessions');

async function setup(page, options) {
  const cloud = new CloudHarness(page, options);
  const terminal = new CloudTerminalHarness(page);
  await cloud.install();
  await terminal.install();
  await cloud.goto();
  return { cloud, terminal };
}

test('Cloud terminal authenticates before RPC and reuses xterm input, resize and output acknowledgements', async ({ page }, testInfo) => {
  const { cloud, terminal } = await setup(page);
  terminal.authenticate = false;
  await cloud.open();
  await show(page).click();
  await expect.poll(() => terminal.connections.length).toBe(1);
  const connection = terminal.connections[0];
  await expect.poll(() => connection.frames.length).toBe(1);
  expect(connection.frames).toEqual([{ type: 'auth', token: 'ts_fixture-123' }]);
  expect(new URL(connection.url).search).toBe('');
  connection.socket.send(JSON.stringify({ type: 'authenticated' }));
  await expect.poll(() => terminal.requests('terminal.open').length).toBe(1);
  expect(terminal.requests('terminal.open')[0].params).toMatchObject({ session: sessionA });
  await input(page).focus();
  await page.keyboard.insertText('echo hello');
  await expect.poll(() => terminal.requests('terminal.input').length).toBe(1);
  expect(terminal.requests('terminal.input')[0].params).toEqual({ id: 'terminal-1', data: 'echo hello' });
  await page.keyboard.press('Enter');
  await expect.poll(() => terminal.requests('terminal.input').length).toBe(2);
  expect(terminal.requests('terminal.input')[1].params.data).toBe('\r');
  terminal.output(connection, 'hello from Cloud\r\n');
  await expect(screen(page)).toContainText('hello from Cloud');
  await expect.poll(() => terminal.requests('terminal.ack').length).toBe(1);
  expect(terminal.requests('terminal.ack')[0].params).toEqual({ id: 'terminal-1', sequence: 1 });
  await page.setViewportSize({ width: 1100, height: 800 });
  await expect.poll(() => terminal.requests('terminal.resize').length).toBeGreaterThan(0);
  await page.screenshot({ path: testInfo.outputPath('cloud-terminal.png') });
  await page.getByTitle('Close terminal', { exact: true }).click();
  await expect.poll(() => terminal.requests('terminal.close').length).toBe(1);
  expect(cloud.hostRequests.filter(request => request.method.startsWith('terminal.'))).toEqual([]);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('only starting a terminal creates a Cloud session and preserves the unsent composer draft', async ({ page }) => {
  const { cloud, terminal } = await setup(page);
  await cloud.create();
  await page.locator('#task').fill('Keep this unsent draft');
  expect(creations(cloud)).toHaveLength(0);
  expect(terminal.connections).toHaveLength(0);
  await show(page).click();
  await expect.poll(() => terminal.requests('terminal.open').length).toBe(1);
  await expect(cloud.row(sessionC)).toHaveAttribute('aria-current', 'true');
  await expect(page.locator('#task')).toHaveValue('Keep this unsent draft');
  expect(creations(cloud)).toHaveLength(1);
  expect(cloud.postCount).toBe(0);
  expect(terminal.requests('terminal.open')[0].params.session).toBe(sessionC);
});

test('Cloud session switches and panel hiding retain separate terminals even with equal PTY ids', async ({ page }) => {
  const { cloud, terminal } = await setup(page);
  await cloud.open();
  await show(page).click();
  await expect.poll(() => terminal.requests('terminal.open').length).toBe(1);
  const a = terminal.connections[0];
  terminal.output(a, 'SCREEN_A\r\n');
  await expect(screen(page)).toContainText('SCREEN_A');
  await cloud.open(sessionB);
  await expect.poll(() => terminal.requests('terminal.open').length).toBe(2);
  const b = terminal.connections[1];
  terminal.output(b, 'SCREEN_B\r\n');
  terminal.output(a, 'A_WHILE_HIDDEN\r\n', 2);
  await expect(screen(page)).toContainText('SCREEN_B');
  await hide(page).click();
  await show(page).click();
  await cloud.open(sessionA);
  await expect(screen(page)).toContainText('A_WHILE_HIDDEN');
  await expect(screen(page)).not.toContainText('SCREEN_B');
  expect(terminal.connections).toHaveLength(2);
  expect(terminal.requests('terminal.close')).toHaveLength(0);
  expect(terminal.connections.every(connection => !connection.closed)).toBe(true);
});

test('Cloud disconnect ends terminals and discards queued input without automatically reconnecting', async ({ page }) => {
  const { cloud, terminal } = await setup(page);
  await cloud.open();
  await show(page).click();
  await expect.poll(() => terminal.requests('terminal.open').length).toBe(1);
  terminal.holdInput = true;
  await input(page).focus();
  await page.keyboard.insertText('maybe-delivered');
  await expect.poll(() => terminal.requests('terminal.input').length).toBe(1);
  await page.keyboard.insertText('queued-tail');
  await terminal.connections[0].socket.close({ code: 1011, reason: 'Fixture disconnect' });
  await expect(page.locator('.terminal-status')).toHaveText('Terminal connection closed. Open a new terminal to continue.');
  await hide(page).click();
  await show(page).click();
  await expect(page.locator('.terminal-panel.open')).toBeVisible();
  await expect(page.locator('.terminal-status')).toHaveText('Terminal connection closed. Open a new terminal to continue.');
  await expect(page.locator('.terminal-tab')).toHaveCount(0);
  expect(terminal.connections).toHaveLength(1);
  await page.getByTitle('New terminal in this workspace', { exact: true }).click();
  await expect.poll(() => terminal.connections.length).toBe(2);
  await expect.poll(() => terminal.requests('terminal.open').length).toBe(2);
  expect(terminal.requests('terminal.input').map(request => request.params.data)).toEqual(['maybe-delivered']);
});

test('account replacement closes this client sockets and cannot display the old account terminals', async ({ page }) => {
  const { cloud, terminal } = await setup(page, { desktop: true });
  await cloud.open();
  await show(page).click();
  await expect.poll(() => terminal.requests('terminal.open').length).toBe(1);
  const old = terminal.connections[0];
  terminal.output(old, 'OLD_ACCOUNT\r\n');
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  const account = page.locator('.settings-group', { hasText: 'Account · Remote access' });
  await account.getByRole('button', { name: 'Sign out', exact: true }).click();
  await expect.poll(() => old.closed).toBe(true);
  cloud.userId = '456';
  await account.getByRole('button', { name: 'Sign in', exact: true }).click();
  await expect(account.getByRole('button', { name: 'Sign out', exact: true })).toBeVisible();
  await cloud.open();
  if (await show(page).isVisible()) await show(page).click();
  await expect.poll(() => terminal.connections.length).toBe(2);
  await expect.poll(() => terminal.requests('terminal.open').length).toBe(2);
  expect(terminal.connections[1].frames[0]).toEqual({ type: 'auth', token: 'ts_fixture-456' });
  await expect(screen(page)).not.toContainText('OLD_ACCOUNT');
});

test('failed session creation leaves the Cloud draft intact and never starts a terminal or model', async ({ page }) => {
  const { cloud, terminal } = await setup(page);
  cloud.createStatus = 500;
  await cloud.create();
  await page.locator('#task').fill('Unsent text');
  await show(page).click();
  await expect(page.getByText('Cloud answered HTTP 500. Try again.', { exact: true }).last()).toBeVisible();
  await expect(page.locator('#task')).toHaveValue('Unsent text');
  await expect(page.locator('#task')).toBeEnabled();
  expect(terminal.connections).toHaveLength(0);
  expect(cloud.postCount).toBe(0);
});

test('terminal authentication refusal ends the connection without sending RPC or retrying', async ({ page }) => {
  const { cloud, terminal } = await setup(page);
  terminal.authenticate = false;
  await cloud.open();
  await show(page).click();
  await expect.poll(() => terminal.connections[0]?.frames.length).toBe(1);
  terminal.connections[0].socket.send(JSON.stringify({ type: 'error', error: 'Fixture authentication refused' }));
  await expect(page.locator('.terminal-status')).toHaveText('Terminal connection closed. Open a new terminal to continue.');
  expect(terminal.connections).toHaveLength(1);
  expect(terminal.requests('terminal.open')).toHaveLength(0);
});

test('two clients keep independent terminals for the same Cloud workspace', async ({ page, context }) => {
  const a = await setup(page);
  await a.cloud.open();
  await show(page).click();
  await expect.poll(() => a.terminal.requests('terminal.open').length).toBe(1);
  const other = await context.newPage();
  const b = await setup(other);
  await b.cloud.open();
  await show(other).click();
  await expect.poll(() => b.terminal.requests('terminal.open').length).toBe(1);
  expect(a.terminal.connections[0].session).toBe(b.terminal.connections[0].session);
  a.terminal.output(a.terminal.connections[0], 'CLIENT_A\r\n');
  b.terminal.output(b.terminal.connections[0], 'CLIENT_B\r\n');
  await expect(screen(page)).toContainText('CLIENT_A');
  await expect(screen(other)).toContainText('CLIENT_B');
  await expect(screen(other)).not.toContainText('CLIENT_A');
  await page.getByTitle('Close terminal', { exact: true }).click();
  await expect.poll(() => a.terminal.requests('terminal.close').length).toBe(1);
  expect(b.terminal.requests('terminal.close')).toHaveLength(0);
  b.terminal.output(b.terminal.connections[0], 'STILL_RUNNING\r\n', 2);
  await expect(screen(other)).toContainText('STILL_RUNNING');
  await other.close();
});

async function shell(page, terminal, command) {
  const count = terminal.requests('terminal.open').length;
  await page.locator('#task').pressSequentially(`!${command}`);
  await expect(page.locator('.composer-mode-chip')).toBeVisible();
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  await page.locator('#task').press('Enter');
  await expect.poll(() => terminal.requests('terminal.open').length).toBe(count + 1);
  const connection = terminal.connections.at(-1);
  const tab = connection.terminals.at(-1);
  expect(tab.command).toBe(command);
  await expect(page.locator('#task')).toHaveValue('');
  return { connection, id: tab.id };
}

const commands = (cloud, kind) => cloud.requests.filter(request => request.path.endsWith('/commands') && JSON.parse(request.body).command.command === kind).map(request => JSON.parse(request.body));

function finish(terminal, { connection, id }, output = 'command output', code = 0) {
  terminal.output(connection, `${output}\r\n`, 1, id);
  terminal.exit(connection, code, id);
}

test('Cloud ! lazily creates one session, reuses terminal result encoding, and preserves later text', async ({ page }) => {
  const { cloud, terminal } = await setup(page);
  await cloud.create();
  const tab = await shell(page, terminal, 'printf hello');
  expect(creations(cloud)).toHaveLength(1);
  expect(cloud.postCount).toBe(0);
  await page.locator('#task').fill('Later writing');
  finish(terminal, tab, 'hello');
  await expect.poll(() => commands(cloud, 'prompt').length).toBe(1);
  const sent = commands(cloud, 'prompt')[0].command.content;
  expect(sent).toBe('<user_shell_command>\n<command>\nprintf hello\n</command>\n<result>\nexit=0\nhello\n</result>\n</user_shell_command>');
  await expect(page.locator('#task')).toHaveValue('Later writing');
  await expect(page.locator('.shell-commands-running')).toHaveCount(0);
  await expect(page.locator('.terminal-tab')).toHaveCount(0);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('a Cloud ! result follows its owning session after navigation without consuming either draft', async ({ page }) => {
  const { cloud, terminal } = await setup(page);
  await cloud.open();
  const tab = await shell(page, terminal, 'ls');
  await page.locator('#task').fill('Draft A');
  await cloud.open(sessionB);
  await page.locator('#task').fill('Draft B');
  finish(terminal, tab);
  await expect.poll(() => cloud.postCount).toBe(1);
  expect(cloud.requests.find(request => request.path.endsWith('/commands')).path).toBe(`/v1/sessions/${sessionA}/commands`);
  await expect(page.locator('#task')).toHaveValue('Draft B');
  await cloud.open(sessionA);
  await expect(page.locator('#task')).toHaveValue('Draft A');
});

test('a rejected Cloud ! result remains in the composer ahead of newer writing without automatic retry', async ({ page }) => {
  const { cloud, terminal } = await setup(page);
  cloud.sendStatus = 409;
  cloud.sendErrorBody = 'Fixture rejected prompt';
  await cloud.open();
  const tab = await shell(page, terminal, 'ls');
  await page.locator('#task').fill('Newer input');
  finish(terminal, tab);
  await expect(page.locator('#task')).toHaveValue(/<user_shell_command>[\s\S]*command output[\s\S]*Newer input/);
  expect(cloud.postCount).toBe(1);
  await cloud.open(sessionB);
  await cloud.open(sessionA);
  await expect(page.locator('#task')).toHaveValue(/command output[\s\S]*Newer input/);
  expect(cloud.postCount).toBe(1);
});

for (const mode of ['steer', 'queue']) {
  test(`Cloud ! during generation uses existing ${mode} delivery and keeps newer writing`, async ({ page }) => {
    const { cloud, terminal } = await setup(page);
    cloud.manualTasks = true;
    await cloud.open();
    await page.locator('#task').fill('Start turn');
    await page.locator('#send').click();
    await expect(page.locator('#stop')).toBeEnabled();
    const tab = await shell(page, terminal, 'ls');
    await page.getByRole('button', { name: 'Follow-up action', exact: true }).click();
    await page.getByRole('option', { name: mode === 'queue' ? /^Queue next/ : /^Steer now/ }).click();
    await page.locator('#task').fill('Next draft');
    finish(terminal, tab);
    if (mode === 'queue') {
      await expect.poll(() => cloud.requests.filter(request => request.path.endsWith('/queue')).length).toBe(1);
      await expect(page.locator('.queued-inputs')).toContainText('command output');
    } else {
      await expect.poll(() => commands(cloud, 'steer').length).toBe(1);
      const request = commands(cloud, 'steer')[0].command;
      await expect(page.locator('.pending-steer-row')).toContainText('command output');
      await cloud.emitSessionEvent(sessionA, 'steer_dropped', { submission_id: request.submission_id, content: request.content });
      await expect(page.locator('#task')).toHaveValue(/command output[\s\S]*Next draft/);
    }
    if (mode === 'queue') await expect(page.locator('#task')).toHaveValue('Next draft');
    expect(cloud.postCount).toBe(1);
  });
}

test('Cloud ! authentication failure restores the command and never submits a model prompt', async ({ page }) => {
  const { cloud, terminal } = await setup(page);
  terminal.authenticate = false;
  await cloud.open();
  await page.locator('#task').pressSequentially('!ls');
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  await page.locator('#task').press('Enter');
  await expect.poll(() => terminal.connections.length).toBe(1);
  terminal.connections[0].socket.send(JSON.stringify({ type: 'error', error: 'Fixture refused' }));
  await expect(page.locator('#task')).toHaveValue('!ls');
  await expect(page.locator('.shell-commands-running')).toHaveCount(0);
  expect(cloud.postCount).toBe(0);
  expect(terminal.requests('terminal.open')).toHaveLength(0);
});

test('an uncertain Cloud ! steer can later be applied without duplicating the recovered result', async ({ page }) => {
  const { cloud, terminal } = await setup(page);
  cloud.manualTasks = true;
  await cloud.open();
  await page.locator('#task').fill('Start turn');
  await page.locator('#send').click();
  await expect(page.locator('#stop')).toBeEnabled();
  const tab = await shell(page, terminal, 'ls');
  await page.locator('#task').fill('Later draft');
  cloud.controlOffline = true;
  finish(terminal, tab);
  await expect.poll(() => commands(cloud, 'steer').length).toBe(1);
  const request = commands(cloud, 'steer')[0].command;
  await expect(page.locator('#task')).toHaveValue(/command output[\s\S]*Later draft/);
  await cloud.emitSessionEvent(sessionA, 'steer_applied', { submission_id: request.submission_id, kind: 'prompt', content: request.content });
  await expect(page.locator('#task')).toHaveValue('Later draft');
  expect(commands(cloud, 'steer')).toHaveLength(1);
});

test('signing out while Cloud ! runs clears the operation without submitting it under the next account', async ({ page }) => {
  const { cloud, terminal } = await setup(page, { desktop: true });
  await cloud.open();
  const tab = await shell(page, terminal, 'ls');
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await page.locator('.settings-group', { hasText: 'Account · Remote access' }).getByRole('button', { name: 'Sign out', exact: true }).click();
  await expect.poll(() => tab.connection.closed).toBe(true);
  expect(cloud.postCount).toBe(0);
  await expect(page.locator('.shell-commands-running')).toHaveCount(0);
  expect(terminal.requests('terminal.open')).toHaveLength(1);
});

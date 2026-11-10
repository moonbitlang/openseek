import { test, expect } from './support/test.js';
import { CloudHarness, sessionA } from './support/cloud_harness.js';
import { CloudTerminalHarness } from './support/cloud_terminal_harness.js';

const show = page => page.getByRole('button', { name: 'Show terminal (Ctrl+`)', exact: true });
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

test('Cloud terminal authenticates before RPC and reuses xterm input, resize and output acknowledgements', async ({ page }) => {
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
  await page.getByTitle('Close terminal', { exact: true }).click();
  await expect.poll(() => terminal.requests('terminal.close').length).toBe(1);
  expect(cloud.hostRequests.filter(request => request.method.startsWith('terminal.'))).toEqual([]);
  expect(cloud.device.pageErrors).toEqual([]);
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


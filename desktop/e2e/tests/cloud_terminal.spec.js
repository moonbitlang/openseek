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

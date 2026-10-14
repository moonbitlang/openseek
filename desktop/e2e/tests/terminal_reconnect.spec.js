import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

async function openTerminal(page, app) {
  await app.install();
  await app.goto();
  await app.openSession();
  await page.getByTitle('Show terminal (Ctrl+`)').click();
  await expect.poll(() => app.requests.filter(r => r.method === 'terminal.open').length).toBe(1);
  const input = page.locator('.terminal-instance:visible .xterm-helper-textarea');
  await input.focus();
  return input;
}

test('socket loss reconnects the terminal without replaying active or queued input', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  const replyFor = app.replyFor.bind(app);
  let held = false;
  app.replyFor = request => {
    if (request.method === 'terminal.input' && !held) {
      held = true;
      // The host received the input but its acknowledgement never arrives.
      return new Promise(() => {});
    }
    return replyFor(request);
  };
  await openTerminal(page, app);
  app.notify('terminal.output', { id: 'terminal-1', sequence: 1, data: Buffer.from('BEFORE_DISCONNECT\r\n').toString('base64') });
  await expect(page.locator('.terminal-instance:visible .xterm-rows')).toContainText('BEFORE_DISCONNECT');
  const emulator = await page.locator('.terminal-instance:visible').elementHandle();
  await page.keyboard.insertText('maybe-delivered');
  await expect.poll(() => app.requests.filter(r => r.method === 'terminal.input').length).toBe(1);
  await page.keyboard.insertText('queued-tail');
  const oldSocket = app.socket;
  await oldSocket.close({ code: 1011, reason: 'test network interruption' });
  await expect(page.locator('.terminal-status')).toContainText('Reconnecting');
  await page.screenshot({ path: testInfo.outputPath('terminal-reconnecting.png') });
  await expect.poll(() => app.requests.filter(r => r.method === 'terminal.attach').length).toBe(1);
  expect(app.requests.filter(r => r.method === 'terminal.open')).toHaveLength(1);
  expect(app.requests.find(r => r.method === 'terminal.attach').params).toEqual({ id: 'terminal-1', sequence: 1 });
  await expect(page.locator('.terminal-status')).toHaveText('Reconnected to the existing shell; previous input was not replayed.');
  expect(app.socket).not.toBe(oldSocket);
  expect(app.requests.filter(r => r.method === 'terminal.input').map(r => r.params)).toEqual([
    { id: 'terminal-1', data: 'maybe-delivered' },
  ]);
  await expect(page.getByText('Close this terminal and open a new one.', { exact: false })).toHaveCount(0);
  expect(await emulator.evaluate(node => node.isConnected)).toBe(true);
  // A lost ACK can replay an already displayed record. Render it once, then
  // append the bytes generated while the browser was disconnected.
  app.notify('terminal.output', { id: 'terminal-1', sequence: 1, data: Buffer.from('BEFORE_DISCONNECT\r\n').toString('base64') });
  app.notify('terminal.output', { id: 'terminal-1', sequence: 2, data: Buffer.from('DURING_DISCONNECT\r\n').toString('base64') });
  await expect(page.locator('.terminal-instance:visible .xterm-rows')).toContainText('DURING_DISCONNECT');
  const screen = await page.locator('.terminal-instance:visible .xterm-rows').innerText();
  expect(screen.match(/BEFORE_DISCONNECT/g)).toHaveLength(1);
  await page.screenshot({ path: testInfo.outputPath('terminal-reconnected.png') });
  await page.locator('.terminal-instance:visible .xterm-helper-textarea').focus();
  await page.keyboard.insertText('fresh-input');
  await expect.poll(() => app.requests.filter(r => r.method === 'terminal.input').map(r => r.params)).toEqual([
    { id: 'terminal-1', data: 'maybe-delivered' },
    { id: 'terminal-1', data: 'fresh-input' },
  ]);
  await expect(page.locator('.terminal-status')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('a host write rejection pauses input without reconnecting or blocking output', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  // Error text must not be used to classify a transport failure.
  app.rpcErrors.set('terminal.input', 'connection lost while writing PTY');
  await openTerminal(page, app);
  const socket = app.socket;
  await page.keyboard.insertText('rejected');
  await expect(page.locator('.terminal-status')).toContainText('input is paused');
  await page.keyboard.insertText('must-not-send');
  app.notify('terminal.output', { id: 'terminal-1', sequence: 1, data: Buffer.from('OUTPUT_STILL_WORKS\r\n').toString('base64') });
  await expect(page.locator('.terminal-instance:visible .xterm-rows')).toContainText('OUTPUT_STILL_WORKS');
  expect(app.requests.filter(r => r.method === 'terminal.input')).toHaveLength(1);
  expect(app.requests.filter(r => r.method === 'terminal.open')).toHaveLength(1);
  expect(app.socket).toBe(socket);
  expect(app.pageErrors).toEqual([]);
});


test('an expired session keeps its screen and reports failure without spawning a shell', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  const replyFor = app.replyFor.bind(app);
  app.replyFor = request => request.method === 'terminal.attach' ? { attached: false } : replyFor(request);
  await openTerminal(page, app);
  app.notify('terminal.output', { id: 'terminal-1', sequence: 1, data: Buffer.from('PRESERVED_SCREEN\r\n').toString('base64') });
  await expect(page.locator('.terminal-instance:visible .xterm-rows')).toContainText('PRESERVED_SCREEN');
  await app.socket.close({ code: 1011, reason: 'expired session' });
  await expect(page.locator('.terminal-status')).toContainText('session expired or the host restarted');
  await expect(page.locator('.terminal-instance:visible .xterm-rows')).toContainText('PRESERVED_SCREEN');
  expect(app.requests.filter(r => r.method === 'terminal.open')).toHaveLength(1);
  await page.locator('.terminal-instance:visible .xterm-helper-textarea').focus();
  await page.keyboard.insertText('must-not-send');
  expect(app.requests.filter(r => r.method === 'terminal.input')).toHaveLength(0);
  expect(app.pageErrors).toEqual([]);
});

test('closing a tab during attachment also closes the late accepted session', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  const replyFor = app.replyFor.bind(app);
  let finishAttach;
  app.replyFor = request => request.method === 'terminal.attach'
    ? new Promise(resolve => { finishAttach = resolve; })
    : replyFor(request);
  await openTerminal(page, app);
  await app.socket.close({ code: 1011, reason: 'reconnect then close' });
  await expect.poll(() => typeof finishAttach).toBe('function');
  await page.locator('.terminal-tab-close').click();
  await expect.poll(() => app.requests.filter(r => r.method === 'terminal.close').length).toBe(1);
  finishAttach({ attached: true });
  await expect.poll(() => app.requests.filter(r => r.method === 'terminal.close').length).toBe(2);
  await expect(page.locator('.terminal-tab')).toHaveCount(0);
  expect(app.requests.filter(r => r.method === 'terminal.open')).toHaveLength(1);
  expect(app.pageErrors).toEqual([]);
});

test('all tabs reattach to their own shells and retain their separate screens', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await openTerminal(page, app);
  app.notify('terminal.output', { id: 'terminal-1', sequence: 1, data: Buffer.from('FIRST_SHELL\r\n').toString('base64') });
  await expect(page.locator('.terminal-instance').nth(0).locator('.xterm-rows')).toContainText('FIRST_SHELL');
  await page.locator('.terminal-new').click();
  await expect.poll(() => app.requests.filter(r => r.method === 'terminal.open').length).toBe(2);
  app.notify('terminal.output', { id: 'terminal-2', sequence: 1, data: Buffer.from('SECOND_SHELL\r\n').toString('base64') });
  await expect(page.locator('.terminal-instance').nth(1).locator('.xterm-rows')).toContainText('SECOND_SHELL');
  await app.socket.close({ code: 1011, reason: 'both shells disconnected' });
  await expect.poll(() => app.requests.filter(r => r.method === 'terminal.attach').map(r => r.params).sort((a, b) => a.id.localeCompare(b.id))).toEqual([
    { id: 'terminal-1', sequence: 1 }, { id: 'terminal-2', sequence: 1 },
  ]);
  await expect(page.locator('.terminal-status')).toContainText('Reconnected to the existing shell');
  await expect(page.locator('.terminal-instance').nth(0).locator('.xterm-rows')).toContainText('FIRST_SHELL');
  await expect(page.locator('.terminal-instance').nth(1).locator('.xterm-rows')).toContainText('SECOND_SHELL');
  await page.locator('.terminal-instance:visible .xterm-helper-textarea').focus();
  await page.keyboard.insertText('second-input');
  await expect.poll(() => app.requests.filter(r => r.method === 'terminal.input').map(r => r.params)).toEqual([{ id: 'terminal-2', data: 'second-input' }]);
  expect(app.requests.filter(r => r.method === 'terminal.open')).toHaveLength(2);
  expect(app.pageErrors).toEqual([]);
});

for (const kind of ['command', 'shell', 'closed tab']) {
  test(`an exit before the open reply releases the retained ${kind} session`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    const replyFor = app.replyFor.bind(app);
    let finishOpen;
    app.replyFor = request => request.method === 'terminal.open'
      ? new Promise(resolve => { finishOpen = resolve; })
      : replyFor(request);
    if (kind === 'command') {
      await app.install();
      await app.goto();
      await app.openSession();
      await page.locator('#task').fill('!printf early');
      await expect(page.locator('.composer-mode-chip')).toBeVisible();
      await page.locator('#task').press('Enter');
    } else {
      await openTerminal(page, app);
    }
    await expect.poll(() => typeof finishOpen).toBe('function');
    app.notify('terminal.output', { id: 'early-exit', sequence: 1, data: Buffer.from('early\r\n').toString('base64') });
    app.notify('terminal.exit', { id: 'early-exit', code: 0 });
    // Let the exit reach the opening tab before releasing its held reply.
    await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
    if (kind === 'closed tab') {
      await page.locator('.terminal-tab-close').click();
      await expect(page.locator('.terminal-tab')).toHaveCount(0);
    }
    finishOpen({ id: 'early-exit' });
    await expect.poll(() => app.requests.filter(r => r.method === 'terminal.close').map(r => r.params)).toEqual([{ id: 'early-exit' }]);
    if (kind === 'command') {
      await expect.poll(() => app.requests.find(r => r.method === 'agent.start')?.params.task).toContain('exit=0\nearly');
    }
    await expect(page.locator('.terminal-tab')).toHaveCount(0);
    expect(app.pageErrors).toEqual([]);
  });
}

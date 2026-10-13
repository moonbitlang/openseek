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
  await page.keyboard.insertText('maybe-delivered');
  await expect.poll(() => app.requests.filter(r => r.method === 'terminal.input').length).toBe(1);
  await page.keyboard.insertText('queued-tail');
  const oldSocket = app.socket;
  await oldSocket.close({ code: 1011, reason: 'test network interruption' });
  await expect(page.locator('.terminal-status')).toContainText('Reconnecting');
  await page.screenshot({ path: testInfo.outputPath('terminal-reconnecting.png') });
  await expect.poll(() => app.requests.filter(r => r.method === 'terminal.open').length).toBe(2);
  await expect(page.locator('.terminal-status')).toHaveText('Reconnected with a new shell; previous input was not replayed.');
  expect(app.socket).not.toBe(oldSocket);
  expect(app.requests.filter(r => r.method === 'terminal.input').map(r => r.params)).toEqual([
    { id: 'terminal-1', data: 'maybe-delivered' },
  ]);
  await expect(page.getByText('Close this terminal and open a new one.', { exact: false })).toHaveCount(0);
  await page.screenshot({ path: testInfo.outputPath('terminal-reconnected.png') });
  await page.locator('.terminal-instance:visible .xterm-helper-textarea').focus();
  await page.keyboard.insertText('fresh-input');
  await expect.poll(() => app.requests.filter(r => r.method === 'terminal.input').map(r => r.params)).toEqual([
    { id: 'terminal-1', data: 'maybe-delivered' },
    { id: 'terminal-2', data: 'fresh-input' },
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

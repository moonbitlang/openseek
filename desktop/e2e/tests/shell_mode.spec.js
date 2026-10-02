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

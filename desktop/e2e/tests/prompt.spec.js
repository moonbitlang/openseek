import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

class PromptHarness extends DesktopBrowserHarness {
  replyFor(request) {
    if (request.method === 'agent.start' && !this.liveSessions.some(session => session.id === request.params.session)) {
      this.liveSessions.push({ id: request.params.session, title: 'Prompt choice fixture', updated_at_ms: 2 });
    }
    return super.replyFor(request);
  }
}

async function settings(page) {
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Settings', exact: true })).toBeVisible();
  return page.getByRole('button', { name: 'Additional prompt', exact: true });
}

async function choose(page, name) {
  const control = await settings(page);
  await control.click();
  await page.getByRole('option', { name, exact: true }).click();
  await expect(control).toContainText(name);
}

async function newChat(page) {
  await page.locator('.workspace-row').hover();
  await page.getByRole('button', { name: 'New conversation in this project', exact: true }).click();
  await expect(page.locator('#task')).toBeVisible();
}

async function send(page, app, text) {
  const requests = () => app.requests.filter(request => request.method === 'agent.start');
  const previous = requests().length;
  await page.locator('#task').fill(text);
  await page.locator('#send').click();
  await expect.poll(() => requests().length).toBe(previous + 1);
  return requests().at(-1).params;
}

test('custom prompt persists and both sources send complete system prompts', async ({ page }, testInfo) => {
  const app = new PromptHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  const builtin = (await send(page, app, 'Use the builtin prompt')).system_prompt;
  expect(typeof builtin).toBe('string');
  expect(builtin.length).toBeGreaterThan(0);
  await choose(page, 'Custom prompt');
  const custom = '  Project instructions\n保留空格、引号 "text" 与 $literal\n';
  const editor = page.getByRole('textbox', { name: 'Custom prompt', exact: true });
  await editor.fill(custom);
  await expect.poll(() => page.evaluate(() => JSON.parse(localStorage.getItem('openseek.prompt')))).toEqual({ kind: 'custom', text: custom });
  await page.reload();
  await expect(editor).toHaveValue(custom);
  await page.screenshot({ animations: 'disabled', path: testInfo.outputPath('custom-prompt-light.png') });
  await newChat(page);
  const complete = (await send(page, app, 'Use custom text')).system_prompt;
  expect(complete).not.toBe(custom);
  expect(complete.endsWith('\n\n' + custom)).toBe(true);
  await choose(page, 'MoonBit guide');
  await newChat(page);
  expect((await send(page, app, 'Use the builtin again')).system_prompt).toBe(builtin);
  await choose(page, 'Custom prompt');
  await expect(editor).toHaveValue(custom);
  await choose(page, 'MoonBit guide');
  await page.reload();
  await expect(page.getByRole('button', { name: 'Additional prompt', exact: true })).toContainText('MoonBit guide');
  await choose(page, 'Custom prompt');
  await expect(editor).toHaveValue(custom);
  await newChat(page);
  expect((await send(page, app, 'Use the restored custom text')).system_prompt).toBe(complete);
  expect(app.pageErrors).toEqual([]);
});

test('changing the default preserves an existing unsent draft', async ({ page }) => {
  const app = new PromptHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  const builtin = (await send(page, app, 'Remember the builtin text')).system_prompt;
  await newChat(page);
  await page.locator('#task').fill('Keep this draft');
  const draft = new URL(page.url()).pathname;
  await choose(page, 'Custom prompt');
  await page.getByRole('textbox', { name: 'Custom prompt', exact: true }).fill('New default');
  await page.getByRole('button', { name: 'Back', exact: true }).click();
  await expect.poll(() => new URL(page.url()).pathname).toBe(draft);
  await expect(page.locator('#task')).toHaveValue('Keep this draft');
  expect((await send(page, app, 'Send the existing draft')).system_prompt).toBe(builtin);
  expect(app.pageErrors).toEqual([]);
});

test('an empty prompt retains the disabled preference and works in narrow dark Settings', async ({ page }, testInfo) => {
  await page.addInitScript(() => localStorage.setItem('openseek.moonbit_guide', 'false'));
  const app = new PromptHarness(page);
  await app.install();
  await app.goto();
  const control = await settings(page);
  await expect(control).toContainText('Custom prompt');
  const editor = page.getByRole('textbox', { name: 'Custom prompt', exact: true });
  await expect(editor).toHaveValue('');
  await page.setViewportSize({ width: 390, height: 844 });
  await page.emulateMedia({ colorScheme: 'dark' });
  await expect.poll(() => page.locator('.app > aside').evaluate(el => el.getBoundingClientRect().right)).toBeLessThanOrEqual(0);
  await editor.fill('Text to clear');
  await editor.fill('');
  await expect.poll(() => page.evaluate(() => JSON.parse(localStorage.getItem('openseek.prompt')))).toEqual({ kind: 'custom', text: '' });
  const bounds = await editor.boundingBox();
  expect(bounds.x).toBeGreaterThanOrEqual(0);
  expect(bounds.x + bounds.width).toBeLessThanOrEqual(390);
  await page.screenshot({ animations: 'disabled', path: testInfo.outputPath('custom-prompt-narrow-dark.png') });
  await page.setViewportSize({ width: 1440, height: 900 });
  await newChat(page);
  const complete = (await send(page, app, 'Create without additional instructions')).system_prompt;
  expect(typeof complete).toBe('string');
  expect(complete.length).toBeGreaterThan(0);
  expect(app.pageErrors).toEqual([]);
});

test('the first native goal carries the same custom prompt as a first message', async ({ page }) => {
  const app = new PromptHarness(page);
  await app.install();
  await app.goto();
  await choose(page, 'Custom prompt');
  const custom = '  Goal instructions\n中文\n';
  await page.getByRole('textbox', { name: 'Custom prompt', exact: true }).fill(custom);
  await newChat(page);
  const task = page.locator('#task');
  await task.fill('/goal');
  await expect(page.locator('.completion-item').filter({ hasText: '/goal' })).toBeVisible();
  await task.press('Enter');
  await expect(page.locator('#goal-set')).toBeVisible();
  await task.fill('Complete the requested work');
  await page.locator('#goal-set').click();
  const requests = () => app.requests.filter(request => request.method === 'agent.command');
  await expect.poll(() => requests().length).toBe(1);
  const complete = requests()[0].params.system_prompt;
  expect(complete).not.toBe(custom);
  expect(complete.endsWith('\n\n' + custom)).toBe(true);
  expect(app.pageErrors).toEqual([]);
});

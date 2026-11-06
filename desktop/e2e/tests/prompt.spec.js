import { test, expect } from './support/test.js';
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
  await page.locator('#sidebar-settings').click();
  await expect(page.getByRole('dialog')).toBeVisible();
  return page.locator('#prompt-choice');
}

async function choose(page, value) {
  const control = await settings(page);
  await control.click();
  await page.locator(`#prompt-choice-menu [data-value=${JSON.stringify(value)}]`).click();
  await expect(control).toHaveAttribute('data-value', value);
}

async function saveCustom(page, app, text) {
  await page.locator('#prompt-custom-text').fill(text);
  await expect(page.locator('.prompt-save-status')).toHaveText('You have unsaved changes');
  await page.locator('#prompt-save').click();
  await expect.poll(() => app.hostSettings.custom_prompt).toBe(text);
  await expect(page.locator('#prompt-save')).toBeDisabled();
  await expect(page.locator('.prompt-save-status')).toHaveText('');
}

async function newChat(page, fromSettings = true) {
  if (fromSettings) await page.getByRole('dialog').locator('[data-slot="dialog-close"]').click();
  await page.locator('.workspace-row').hover();
  await page.locator('.workspace-row [id$=":new-conversation"]').click();
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

test('custom prompt persists and both sources send complete system prompts', async ({ page }) => {
  const app = new PromptHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  const builtin = (await send(page, app, 'Use the builtin prompt')).system_prompt;
  expect(typeof builtin).toBe('string');
  expect(builtin.length).toBeGreaterThan(0);
  await choose(page, 'custom');
  const custom = '  Project instructions\n保留空格、引号 "text" 与 $literal\n';
  const editor = page.locator('#prompt-custom-text');
  await saveCustom(page, app, custom);
  await page.reload();
  await settings(page);
  await expect(editor).toHaveValue(custom);
  await newChat(page);
  const complete = (await send(page, app, 'Use custom text')).system_prompt;
  expect(complete).not.toBe(custom);
  expect(complete.endsWith('\n\n' + custom)).toBe(true);
  await choose(page, 'builtin_moonbit_guide');
  await page.reload();
  await settings(page);
  await expect(page.locator('#prompt-choice')).toHaveAttribute('data-value', 'builtin_moonbit_guide');
  await newChat(page);
  expect((await send(page, app, 'Use the builtin again')).system_prompt).toBe(builtin);
  await choose(page, 'custom');
  await expect(editor).toHaveValue(custom);
  await newChat(page);
  expect((await send(page, app, 'Use the restored custom text')).system_prompt).toBe(complete);
  await settings(page);
  app.hostSettings = { ...app.hostSettings, revision: app.hostSettings.revision + 1, custom_prompt: 'Saved by another client' };
  app.notify('settings.changed', app.hostSettings);
  await expect(editor).toHaveValue('Saved by another client');
  await newChat(page);
  expect((await send(page, app, 'Use the shared host setting')).system_prompt.endsWith('\n\nSaved by another client')).toBe(true);
  expect(app.pageErrors).toEqual([]);
});

test('changing the default preserves an existing unsent draft', async ({ page }) => {
  const app = new PromptHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  const builtin = (await send(page, app, 'Remember the builtin text')).system_prompt;
  await newChat(page, false);
  await page.locator('#task').fill('Keep this draft');
  await expect(page).toHaveURL(/\/chat\/draft\/[^/?#]+$/);
  const draft = new URL(page.url()).pathname;
  await choose(page, 'custom');
  await saveCustom(page, app, 'New default');
  await page.getByRole('dialog').locator('[data-slot="dialog-close"]').click();
  await expect.poll(() => new URL(page.url()).pathname).toBe(draft);
  await expect(page.locator('#task')).toHaveValue('Keep this draft');
  expect((await send(page, app, 'Send the existing draft')).system_prompt).toBe(builtin);
  expect(app.pageErrors).toEqual([]);
});

test('the host custom prompt can be cleared', async ({ page }) => {
  const app = new PromptHarness(page);
  app.hostSettings.prompt_source = 'custom';
  app.hostSettings.custom_prompt = 'Text to clear';
  await app.install();
  await app.goto();
  const control = await settings(page);
  await expect(control).toHaveAttribute('data-value', 'custom');
  const editor = page.locator('#prompt-custom-text');
  await expect(editor).toHaveValue('Text to clear');
  await saveCustom(page, app, '');
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
  await app.openSession();
  await choose(page, 'custom');
  const custom = '  Goal instructions\n中文\n';
  await saveCustom(page, app, custom);
  await newChat(page);
  const task = page.locator('#task');
  await task.fill('/goal');
  await expect(page.locator('[data-completion-value="goal"]')).toBeVisible();
  await task.press('Enter');
  await expect(page.locator('#goal-cancel')).toBeVisible();
  await task.fill('Complete the requested work');
  await expect(page.locator('#goal-set')).toBeVisible();
  await page.locator('#goal-set').click();
  const requests = () => app.requests.filter(request => request.method === 'agent.command');
  await expect.poll(() => requests().length).toBe(1);
  const complete = requests()[0].params.system_prompt;
  expect(complete).not.toBe(custom);
  expect(complete.endsWith('\n\n' + custom)).toBe(true);
  expect(app.pageErrors).toEqual([]);
});

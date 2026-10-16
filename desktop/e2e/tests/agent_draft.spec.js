import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

const png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aCfoAAAAASUVORK5CYII=';
const imageURL = `data:image/png;base64,${png}`;

async function open(page) {
  const app = new DesktopBrowserHarness(page);
  app.codexModels = [{ id: 'gpt-test', displayName: 'Codex test', isDefault: true }];
  app.searchFiles = ['src/main.mbt'];
  await app.install();
  await app.goto();
  await expect(page.getByRole('button', { name: 'Rabbita browser fixture', exact: true })).toBeVisible();
  return app;
}

async function choose(page, name) {
  await page.getByRole('button', { name: 'Model', exact: true }).click();
  await page.getByRole('option', { name, exact: true }).click();
  await expect(page.getByRole('button', { name: 'Model', exact: true })).toContainText(name);
}

async function noDraftRows(page, initialRows) {
  await expect(page.locator('.conversation-row')).toHaveCount(initialRows);
  await expect(page.locator('.conversation-row').filter({ hasText: /^New chat$/ })).toHaveCount(0);
}

test('one draft carries current text, file mentions and images through repeated agent switches', async ({ page }, testInfo) => {
  const app = await open(page);
  const initialRows = await page.locator('.conversation-row').count();
  const task = page.locator('#task');
  await task.fill('@main');
  await page.locator('.completion-item').filter({ hasText: 'src/main.mbt' }).click();
  await task.press('End');
  await task.pressSequentially(' Inspect this 👀');
  const initialText = await task.inputValue();
  const chooser = page.waitForEvent('filechooser');
  await page.getByRole('button', { name: 'Attach files', exact: true }).click();
  await (await chooser).setFiles({ name: 'screen.png', mimeType: 'image/png', buffer: Buffer.from(png, 'base64') });
  await expect(page.locator('.composer-image img')).toHaveAttribute('src', imageURL);

  await choose(page, 'Codex test');
  await expect(task).toHaveValue(initialText);
  await expect(page.locator('.composer-image img')).toHaveAttribute('src', imageURL);
  await noDraftRows(page, initialRows);
  await page.screenshot({ path: testInfo.outputPath('draft-in-codex.png') });
  await task.press('End');
  await task.pressSequentially(' Edited in Codex');
  const codexText = await task.inputValue();
  await choose(page, 'DS Pro');
  await expect(task).toHaveValue(codexText);
  await expect(page.locator('.composer-image img')).toHaveAttribute('src', imageURL);
  await noDraftRows(page, initialRows);
  await page.screenshot({ path: testInfo.outputPath('draft-back-in-deepseek.png') });

  await task.press('End');
  await task.pressSequentially(' Edited in DeepSeek');
  const finalText = await task.inputValue();
  await choose(page, 'Codex test');
  await expect(task).toHaveValue(finalText);
  await noDraftRows(page, initialRows);
  await page.locator('#send').click();
  await expect.poll(() => app.requests.find(r => r.method === 'codex.turn.start')?.params.input).toEqual([
    { type: 'text', text: expect.stringContaining('Edited in DeepSeek') },
    { type: 'mention', name: 'main.mbt', path: 'src/main.mbt' },
    { type: 'image', url: imageURL },
  ]);
  await expect(page.locator('.conversation-row')).toHaveCount(initialRows + 1);
  expect(app.pageErrors).toEqual([]);
});

test('clearing the migrated draft never revives an earlier engine copy', async ({ page }) => {
  const app = await open(page);
  const initialRows = await page.locator('.conversation-row').count();
  const task = page.locator('#task');
  await choose(page, 'Codex test');
  await task.fill('Started in Codex');
  await choose(page, 'DS Pro');
  await expect(task).toHaveValue('Started in Codex');
  await task.fill('');
  await choose(page, 'Codex test');
  await expect(task).toHaveValue('');
  await task.fill('Replacement');
  await choose(page, 'DS Pro');
  await expect(task).toHaveValue('Replacement');
  await choose(page, 'Codex test');
  await task.fill('');
  await choose(page, 'DS Pro');
  await expect(task).toHaveValue('');
  await noDraftRows(page, initialRows);
  expect(app.pageErrors).toEqual([]);
});

test('an image-only Codex draft migrates back and sends through DeepSeek', async ({ page }) => {
  const app = await open(page);
  const initialRows = await page.locator('.conversation-row').count();
  await choose(page, 'Codex test');
  const chooser = page.waitForEvent('filechooser');
  await page.getByRole('button', { name: 'Attach files', exact: true }).click();
  await (await chooser).setFiles({ name: 'screen.png', mimeType: 'image/png', buffer: Buffer.from(png, 'base64') });
  await expect(page.locator('.composer-image img')).toHaveAttribute('src', imageURL);
  await choose(page, 'DS Pro');
  await expect(page.locator('#task')).toHaveValue('');
  await expect(page.locator('.composer-image img')).toHaveAttribute('src', imageURL);
  await noDraftRows(page, initialRows);
  await page.locator('#send').click();
  await expect.poll(() => app.requests.find(r => r.method === 'agent.start')?.params.images).toEqual([imageURL]);
  expect(app.requests.filter(r => r.method === 'codex.thread.start')).toHaveLength(0);
  await expect(page.locator('.conversation-row')).toHaveCount(initialRows + 1);
  expect(app.pageErrors).toEqual([]);
});

test('a submitted Codex draft cannot switch agents while thread creation is pending', async ({ page }) => {
  const app = await open(page);
  await choose(page, 'Codex test');
  const pending = Promise.withResolvers();
  const replyFor = app.replyFor.bind(app);
  app.replyFor = async request => {
    if (request.method === 'codex.thread.start') await pending.promise;
    return replyFor(request);
  };
  await page.locator('#task').fill('Create this conversation');
  await page.locator('#send').click();
  await expect.poll(() => app.requests.some(r => r.method === 'codex.thread.start')).toBe(true);
  await page.getByRole('button', { name: 'Model', exact: true }).click();
  await expect(page.getByRole('option', { name: 'DS Pro', exact: true })).toHaveCount(0);
  pending.resolve();
  expect(app.pageErrors).toEqual([]);
});


test('editing a goal protects its text until the editor is closed', async ({ page }) => {
  const app = await open(page);
  const task = page.locator('#task');
  await task.fill('/goal');
  await expect(page.locator('.completion-item').filter({ hasText: 'goal' }).first()).toBeVisible();
  await task.press('Enter');
  await expect(page.locator('#goal-set')).toBeVisible();
  await task.fill('Do not lose this goal');
  await expect(page.getByRole('button', { name: 'Model', exact: true })).toBeDisabled();
  await expect(task).toHaveValue('Do not lose this goal');
  await page.locator('#goal-cancel').click();
  await expect(page.getByRole('button', { name: 'Model', exact: true })).toBeEnabled();
  await choose(page, 'Codex test');
  expect(app.pageErrors).toEqual([]);
});

test('a failed first Codex send keeps the agent fixed while retrying', async ({ page }) => {
  const app = await open(page);
  await choose(page, 'Codex test');
  app.rpcErrors.set('codex.thread.start', 'Reply lost');
  await page.locator('#task').fill('Keep this conversation in Codex');
  await page.locator('#send').click();
  await expect(page.getByText(/Reply lost/)).toBeVisible();
  await page.getByRole('button', { name: 'Model', exact: true }).click();
  await expect(page.getByRole('option', { name: 'DS Pro', exact: true })).toHaveCount(0);
  await page.keyboard.press('Escape');
  const first = app.requests.find(r => r.method === 'codex.thread.start');
  app.rpcErrors.delete('codex.thread.start');
  await page.locator('#send').click();
  await expect.poll(() => app.requests.filter(r => r.method === 'codex.thread.start').length).toBe(2);
  expect(app.requests.filter(r => r.method === 'codex.thread.start')[1].params).toEqual(first.params);
  await expect.poll(() => app.requests.some(r => r.method === 'codex.turn.start')).toBe(true);
  expect(app.requests.filter(r => r.method === 'agent.start')).toHaveLength(0);
  expect(app.pageErrors).toEqual([]);
});

test('reusing a draft waits for its pending open and close before reopening', async ({ page }) => {
  const app = await open(page);
  const firstOpen = Promise.withResolvers();
  const closing = Promise.withResolvers();
  const reply = app.replyFor.bind(app);
  const authorized = new Set();
  let opens = 0;
  app.replyFor = async request => {
    if (request.method === 'codex.draft.open') {
      opens += 1;
      if (opens === 1) await firstOpen.promise;
      authorized.add(request.params.draft_id);
    }
    if (request.method === 'codex.draft.close') {
      await closing.promise;
      authorized.delete(request.params.draft_id);
    }
    return reply(request);
  };
  await page.locator('#task').fill('Retain this prompt');
  await choose(page, 'Codex test');
  await expect.poll(() => opens).toBe(1);
  const id = app.requests.find(r => r.method === 'codex.draft.open').params.draft_id;
  await choose(page, 'DS Pro');
  await choose(page, 'Codex test');
  expect(app.requests.filter(r => r.method === 'codex.draft.close')).toHaveLength(0);
  expect(opens).toBe(1);
  firstOpen.resolve();
  await expect.poll(() => app.requests.filter(r => r.method === 'codex.draft.close').length).toBe(1);
  expect(opens).toBe(1);
  closing.resolve();
  await expect.poll(() => opens).toBe(2);
  await expect(page.locator('#send')).toBeEnabled();
  expect(authorized.has(id)).toBe(true);
  expect(app.requests.filter(r => r.method === 'codex.draft.open').every(r => r.params.draft_id === id)).toBe(true);
  await page.locator('#send').click();
  await expect.poll(() => app.requests.some(r => r.method === 'codex.turn.start')).toBe(true);
  expect(app.pageErrors).toEqual([]);
});

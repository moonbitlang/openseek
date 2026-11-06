import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

const png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aCfoAAAAASUVORK5CYII=';
const imageURL = `data:image/png;base64,${png}`;

async function open(page) {
  const app = new DesktopBrowserHarness(page);
  app.codexModels = [{ id: 'gpt-test', displayName: 'Codex test', isDefault: true }];
  app.searchFiles = ['src/main.mbt'];
  await app.install();
  await app.goto();
  await expect(app.sessionButton()).toBeVisible();
  return app;
}

async function choose(page, value) {
  await page.locator('#openseek-model-picker, #codex-model-picker, #model').click();
  await page.locator(`[role="option"][data-value=${JSON.stringify(value)}]`).click();
  await expect(page.locator('#openseek-model-picker, #codex-model-picker, #model')).toHaveAttribute('data-value', value);
}

async function noDraftRows(page, initialRows) {
  await expect(page.locator('.conversation-row')).toHaveCount(initialRows);
}

test('one draft carries current text, file mentions and images through repeated agent switches', async ({ page }) => {
  const app = await open(page);
  const initialRows = await page.locator('.conversation-row').count();
  const task = page.locator('#task');
  await task.fill('@main');
  await page.locator('[data-completion-path="src/main.mbt"]').click();
  await task.press('End');
  await task.pressSequentially(' Inspect this 👀');
  const initialText = await task.inputValue();
  const chooser = page.waitForEvent('filechooser');
  await page.locator('#composer-attach').click();
  await (await chooser).setFiles({ name: 'screen.png', mimeType: 'image/png', buffer: Buffer.from(png, 'base64') });
  await expect(page.locator('.composer-image img')).toHaveAttribute('src', imageURL);

  const chatDraftPath = new URL(page.url()).pathname;
  expect(chatDraftPath).toMatch(/\/chat\/draft\//);
  const codexDraftPath = chatDraftPath.replace('/chat/draft/', '/codex/draft/');
  const historyLength = await page.evaluate(() => history.length);
  await choose(page, 'codex:gpt-test');
  await expect.poll(() => new URL(page.url()).pathname).toBe(codexDraftPath);
  expect(await page.evaluate(() => history.length)).toBe(historyLength);
  await expect(task).toHaveValue(initialText);
  await expect(page.locator('.composer-image img')).toHaveAttribute('src', imageURL);
  await noDraftRows(page, initialRows);
  await task.press('End');
  await task.pressSequentially(' Edited in Codex');
  const codexText = await task.inputValue();
  await choose(page, 'openseek:deepseek-v4-pro');
  await expect.poll(() => new URL(page.url()).pathname).toBe(chatDraftPath);
  expect(await page.evaluate(() => history.length)).toBe(historyLength);
  await expect(task).toHaveValue(codexText);
  await expect(page.locator('.composer-image img')).toHaveAttribute('src', imageURL);
  await noDraftRows(page, initialRows);

  await task.press('End');
  await task.pressSequentially(' Edited in DeepSeek');
  const finalText = await task.inputValue();
  await choose(page, 'codex:gpt-test');
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
  await choose(page, 'codex:gpt-test');
  await task.fill('Started in Codex');
  await choose(page, 'openseek:deepseek-v4-pro');
  await expect(task).toHaveValue('Started in Codex');
  await task.fill('');
  await choose(page, 'codex:gpt-test');
  await expect(task).toHaveValue('');
  await task.fill('Replacement');
  await choose(page, 'openseek:deepseek-v4-pro');
  await expect(task).toHaveValue('Replacement');
  await choose(page, 'codex:gpt-test');
  await task.fill('');
  await choose(page, 'openseek:deepseek-v4-pro');
  await expect(task).toHaveValue('');
  await noDraftRows(page, initialRows);
  expect(app.pageErrors).toEqual([]);
});

test('an image-only Codex draft migrates back and sends through DeepSeek', async ({ page }) => {
  const app = await open(page);
  const initialRows = await page.locator('.conversation-row').count();
  await choose(page, 'codex:gpt-test');
  const chooser = page.waitForEvent('filechooser');
  await page.locator('#composer-attach').click();
  await (await chooser).setFiles({ name: 'screen.png', mimeType: 'image/png', buffer: Buffer.from(png, 'base64') });
  await expect(page.locator('.composer-image img')).toHaveAttribute('src', imageURL);
  await choose(page, 'openseek:deepseek-v4-pro');
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
  await choose(page, 'codex:gpt-test');
  const pending = Promise.withResolvers();
  const replyFor = app.replyFor.bind(app);
  app.replyFor = async request => {
    if (request.method === 'codex.thread.start') await pending.promise;
    return replyFor(request);
  };
  await page.locator('#task').fill('Create this conversation');
  await page.locator('#send').click();
  await expect.poll(() => app.requests.some(r => r.method === 'codex.thread.start')).toBe(true);
  await page.locator('#openseek-model-picker, #codex-model-picker, #model').click();
  await expect(page.locator('[role="option"][data-value="openseek:deepseek-v4-pro"]')).toHaveCount(0);
  pending.resolve();
  expect(app.pageErrors).toEqual([]);
});


test('editing a goal protects its text until the editor is closed', async ({ page }) => {
  const app = await open(page);
  const task = page.locator('#task');
  await task.fill('/goal');
  await expect(page.locator('[data-completion-value="goal"]')).toBeVisible();
  await task.press('Enter');
  await expect(page.locator('#goal-cancel')).toBeVisible();
  await task.fill('Do not lose this goal');
  await expect(page.locator('#openseek-model-picker, #codex-model-picker, #model')).toBeDisabled();
  await expect(task).toHaveValue('Do not lose this goal');
  await page.locator('#goal-cancel').click();
  await expect(page.locator('#openseek-model-picker, #codex-model-picker, #model')).toBeEnabled();
  await choose(page, 'codex:gpt-test');
  expect(app.pageErrors).toEqual([]);
});

test('ultrareview stays a command in the composer and sends the swarm prompt', async ({ page }) => {
  const app = await open(page);
  const task = page.locator('#task');
  await task.fill('/ultrareview');
  await expect(page.locator('[data-completion-value="ultrareview"]')).toBeVisible();
  await task.press('Enter');
  await expect(task).toHaveValue('/ultrareview ');
  await expect(task).toBeFocused();
  await page.keyboard.type('the parser');
  expect(app.requests.filter(r => r.method === 'agent.start')).toHaveLength(0);
  await page.locator('#send').click();
  await expect.poll(() => app.requests.find(r => r.method === 'agent.start')?.params.task).toContain('Focus: the parser');
  const sent = app.requests.find(r => r.method === 'agent.start').params.task;
  expect(sent).toContain('"@builtin/review.mbtx"');
  expect(sent).toContain('"--swarm"');
  // The composer clears as for any sent prompt; the expansion is not left behind.
  await expect(task).toHaveValue('');
  expect(app.pageErrors).toEqual([]);
});

test('simplify sends the sweep prompt with its focus', async ({ page }) => {
  const app = await open(page);
  const task = page.locator('#task');
  await task.fill('/simpl');
  await expect(page.locator('[data-completion-value="simplify"]')).toBeVisible();
  await task.press('Enter');
  await expect(task).toHaveValue('/simplify ');
  await page.keyboard.type('pattern matching');
  expect(app.requests.filter(r => r.method === 'agent.start')).toHaveLength(0);
  await page.locator('#send').click();
  await expect.poll(() => app.requests.find(r => r.method === 'agent.start')?.params.task).toContain('Focus: pattern matching');
  expect(app.requests.find(r => r.method === 'agent.start').params.task).toContain('"@builtin/simplify.mbtx"');
  expect(app.pageErrors).toEqual([]);
});

test('a failed first Codex send keeps the agent fixed while retrying', async ({ page }) => {
  const app = await open(page);
  await choose(page, 'codex:gpt-test');
  app.rpcErrors.set('codex.thread.start', 'Reply lost');
  await page.locator('#task').fill('Keep this conversation in Codex');
  await page.locator('#send').click();
  await expect(page.locator('#transcript .transcript-error-message')).toBeVisible();
  await page.locator('#openseek-model-picker, #codex-model-picker, #model').click();
  await expect(page.locator('#openseek-model-picker-menu, #codex-model-picker-menu, #model-menu')).toBeVisible();
  await expect(page.locator('[role="option"][data-value="openseek:deepseek-v4-pro"]')).toHaveCount(0);
  await page.keyboard.press('Escape');
  await expect(page.locator('#openseek-model-picker-menu, #codex-model-picker-menu, #model-menu')).toHaveCount(0);
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
  await choose(page, 'codex:gpt-test');
  await expect.poll(() => opens).toBe(1);
  const id = app.requests.find(r => r.method === 'codex.draft.open').params.draft_id;
  await choose(page, 'openseek:deepseek-v4-pro');
  await choose(page, 'codex:gpt-test');
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

test('Local native goal and compact commands share input and wait for engine confirmation', async ({ page }) => {
  const app = await open(page);
  await app.openSession();
  await expect(page.locator('.composer-goal')).toContainText('Ship Rabbita 0.15 browser tests');
  const task = page.locator('#task');
  const requests = () => app.requests.filter(r => r.method === 'agent.command');
  await task.fill('/goal');
  await expect(page.locator('[data-completion-value="goal"]')).toBeVisible();
  await task.press('Enter');
  await expect(page.locator('#goal-cancel')).toBeVisible();
  await task.fill('Finish the shared command work');
  await page.locator('#goal-set').click();
  await expect.poll(() => requests().length).toBe(1);
  expect(requests()[0].params.command).toEqual({command: 'goal', action: 'set', text: 'Finish the shared command work'});
  expect(requests()[0].params.session).toBe('session-1');
  await expect(page.locator('.composer-goal.pending')).toContainText('Setting goal');
  const sequence = app.sessionEvents.at(-1).sequence + 1;
  const event = {sequence, item: {kind: 'runtime_notice', payload: {content: '[goal]\nFinish the shared command work'}}};
  app.sessionEvents.push(event);
  app.notify('session.event', {session: 'session-1', session_root: '/workspace/.openseek', sequence, event});
  await expect(page.locator('.composer-goal.pending')).toHaveCount(0);
  await expect(page.locator('.composer-goal')).toContainText('Goal: Finish the shared command work');
  await task.fill('/compact');
  await expect(page.locator('[data-completion-value="compact"]')).toBeVisible();
  await task.press('Enter');
  await expect.poll(() => requests().length).toBe(2);
  expect(requests()[1].params.command).toEqual({command: 'compact'});
  await expect(page.locator('.composer-notice-text')).toContainText('Compacting context');
  app.notify('agent.event', {session: 'session-1', event: {event: 'compaction_started', from_sequence: 1, to_sequence: sequence}});
  app.notify('agent.event', {session: 'session-1', event: {event: 'compaction_finished', from_sequence: 1, to_sequence: sequence, summary: 'Shared command work'}});
  await expect(page.locator('.composer-notice-text')).toHaveCount(0);
  await task.fill('Keep this draft');
  expect(app.pageErrors).toEqual([]);
});

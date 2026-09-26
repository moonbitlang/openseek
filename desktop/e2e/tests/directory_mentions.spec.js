import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('directory mention can be selected and sent', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.searchFiles = ['src/main.mbt', 'src/nested/lib.mbt'];
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openQuickOpen();
  await expect(page.getByRole('option')).toHaveCount(2);
  await expect(page.getByRole('option', { name: /main\.mbt/ })).toBeVisible();
  await page.locator('#quick-open-input').press('Escape');
  await page.locator('#task').fill('Inspect @src');
  const directory = page.locator('.completion-item').filter({ has: page.getByText('src/', { exact: true }) });
  await expect(directory).toBeVisible();
  await directory.click();
  await expect(page.locator('.mention-chip')).toContainText('src/');
  await expect(page.locator('#task')).toHaveValue('Inspect ');
  await page.locator('#task').fill('Inspect @src/main');
  await page.locator('.completion-item').filter({ hasText: 'main.mbt' }).click();
  await expect(page.locator('.composer .mention-chip')).toHaveCount(2);
  await page.locator('#send').click();
  await expect.poll(() => app.requests.find(r => r.method === 'agent.start')?.params.task)
    .toContain('<directory path="src"');
  const content = app.requests.find(r => r.method === 'agent.start').params.task;
  expect(content).toContain('<file path="src/main.mbt"/>');
  app.sessionEvents.push({ sequence: 18, item: { kind: 'user', payload: { content } } });
  await page.reload();
  await app.openSession();
  await expect(page.locator('.user-bubble .mention-label').filter({ hasText: /^src\/$/ })).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

for (const provider of ['OpenSeek', 'Codex']) {
  test(`${provider} supports empty and nested directories with keyboard selection`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    app.searchDirectories = ['src', 'src/nested', 'empty'];
    app.codexModels = [{ id: 'gpt-test', displayName: 'Codex directories', isDefault: true }];
    await app.install();
    await app.goto();
    if (provider === 'Codex') {
      await page.getByRole('button', { name: 'Model', exact: true }).click();
      await page.getByRole('option', { name: 'Codex directories', exact: true }).click();
    } else {
      await app.openSession();
    }
    const composer = page.locator('#task');
    for (const path of ['src/nested', 'empty']) {
      await composer.fill(`@${path}/`);
      await expect(page.locator('.completion-item').first().locator('.completion-label')).toHaveText(`${path.split('/').at(-1)}/`);
      await composer.press('Tab');
      await expect(page.locator('.composer .mention-chip').filter({ hasText: `${path}/` })).toBeVisible();
      await expect(composer).toHaveValue('');
    }
    await page.getByTitle('Send', { exact: true }).click();
    if (provider === 'Codex') {
      await expect.poll(() => app.requests.find(r => r.method === 'codex.turn.start')?.params.input)
        .toEqual(expect.arrayContaining([
          { type: 'text', text: '<user_mentions>\n<directory path="src/nested"/>\n</user_mentions>' },
          { type: 'text', text: '<user_mentions>\n<directory path="empty"/>\n</user_mentions>' },
        ]));
    } else {
      await expect.poll(() => app.requests.find(r => r.method === 'agent.start')?.params.task)
        .toContain('<directory path="empty"/>');
    }
    expect(app.requests.some(r => r.method === 'fs.read_file' && ['/workspace/src/nested', '/workspace/empty'].includes(r.params.path))).toBe(false);
    expect(app.pageErrors).toEqual([]);
  });
}

test('directory completion searches beyond the bounded initial index', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  const replyFor = app.replyFor.bind(app);
  app.replyFor = request => {
    const reply = replyFor(request);
    if (request.method === 'fs.search_files') {
      return { ...reply, directories: request.params.query ? ['late/empty'] : ['src'], limit_hit: !request.params.query };
    }
    return reply;
  };
  await app.install();
  await app.goto();
  await app.openSession();
  await page.locator('#task').fill('@late/empty/');
  const directory = page.locator('.completion-item').filter({ hasText: 'late/empty/' });
  await expect(directory).toBeVisible();
  await directory.click();
  await expect(page.locator('.mention-chip')).toContainText('late/empty/');
  expect(app.requests.some(r => r.method === 'fs.search_files' && r.params.query === 'late/empty/')).toBe(true);
  expect(app.pageErrors).toEqual([]);
});

test('Codex directory mentions retain their identity in returned and reopened history', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.searchFiles = ['src/main.mbt'];
  app.searchDirectories = ['empty'];
  app.codexModels = [{ id: 'gpt-test', displayName: 'Codex directories', isDefault: true }];
  const thread = {
    id: 'codex-thread-e2e', cwd: '/workspace', projectRoot: '/workspace',
    preview: 'Codex directory history', updatedAt: 2, turns: [],
  };
  const replyFor = app.replyFor.bind(app);
  app.replyFor = request => {
    if (request.method === 'codex.turn.start') {
      // Echo the actual submitted input, then serve it again after a reload.
      const turn = { id: 'directory-turn', status: 'completed', items: [
        { id: 'directory-user', type: 'userMessage', content: request.params.input },
      ] };
      thread.turns = [turn];
      return { turn };
    }
    if (request.method === 'codex.thread.list') {
      return { data: !request.params.archived && thread.turns.length ? [thread] : [] };
    }
    if (request.method === 'codex.thread.history.read') return { thread };
    return replyFor(request);
  };
  await app.install();
  await app.goto();
  await page.getByRole('button', { name: 'Model', exact: true }).click();
  await page.getByRole('option', { name: 'Codex directories', exact: true }).click();
  const composer = page.getByRole('textbox', { name: 'Ask Codex to inspect, edit, or explain this workspace.', exact: true });
  for (const path of ['empty/', 'src/main.mbt']) {
    await composer.fill(`@${path}`);
    await expect(page.locator('.completion-item')).toHaveCount(1);
    await composer.press('Tab');
  }
  await page.getByTitle('Send', { exact: true }).click();
  const labels = page.locator('.user-bubble .mention-label');
  await expect(labels).toHaveText(['empty/', 'main.mbt']);
  await expect(page.locator('.user-bubble .mention-jump')).toHaveCount(1);
  await page.locator('.user-bubble .mention-body').click();
  await page.reload();
  await page.getByText('Codex directory history', { exact: true }).first().click();
  await expect(labels).toHaveText(['empty/', 'main.mbt']);
  await expect(page.locator('.user-bubble .mention-jump')).toHaveCount(1);
  await page.locator('.user-bubble .mention-body').click();
  expect(app.requests.some(r => r.method === 'codex.thread.history.read')).toBe(true);
  expect(app.requests.some(r => r.method === 'fs.read_file' && r.params.path.endsWith('/empty'))).toBe(false);
  expect(app.pageErrors).toEqual([]);
});

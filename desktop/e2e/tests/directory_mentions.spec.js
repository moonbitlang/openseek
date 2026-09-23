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
          { type: 'mention', name: 'nested', path: 'src/nested' },
          { type: 'mention', name: 'empty', path: 'empty' },
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

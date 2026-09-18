import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('semantic selection follows match, file, and pattern controls', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.semanticSearchMatches = ['src/main.mbt', 'src/main.mbt', 'src/other.mbt'].map((path, index) => ({
    path, rule_id: 'inspect($(x:arg))',
    start_line: index + 1, start_column: 1, end_line: index + 1, end_column: 11,
    matched_source: 'inspect(x)', source_context: [],
  }));
  await app.install();
  await app.goto();
  await app.openSession();
  const shortcut = await page.evaluate(() =>
    navigator.platform.includes('Mac') ? 'Meta+Shift+F' : 'Control+Shift+F');
  await page.keyboard.press(shortcut);
  await page.getByRole('button', { name: 'Code search', exact: true }).click();
  await page.getByRole('textbox', { name: 'pattern', exact: true }).fill('inspect($(x:arg))');

  const results = page.locator('.search-results');
  const chip = page.locator('.mention-chip');
  await expect(results.getByRole('button', { name: 'Select match', exact: true })).toHaveCount(3);
  await results.getByRole('button', { name: 'Select match', exact: true }).first().click();
  await expect(chip).toContainText('1 matches');
  // A partially selected file becomes fully selected without collapsing it.
  await results.getByLabel('Select file', { exact: true }).first().click();
  await expect(results.getByRole('button', { name: 'Deselect match', exact: true })).toHaveCount(2);
  await expect(chip).toContainText('2 matches');
  await results.getByLabel('Deselect file', { exact: true }).click();
  await expect(chip).toHaveCount(0);
  await results.getByRole('button', { name: 'Select match', exact: true }).first().click();
  await results.getByLabel('Select pattern', { exact: true }).click();
  await expect(results.getByRole('button', { name: 'Deselect match', exact: true })).toHaveCount(3);
  await expect(results.locator('.search-selection-toolbar')).toContainText('3 selected');
  await expect(chip).toContainText('3 matches');
  await results.getByLabel('Deselect pattern', { exact: true }).click();
  await expect(chip).toHaveCount(0);
  await results.getByLabel('Select pattern', { exact: true }).click();
  await results.getByRole('button', { name: 'Clear selection', exact: true }).click();
  await expect(results.getByRole('button', { name: 'Select match', exact: true })).toHaveCount(3);
  await expect(chip).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('large semantic selection retries and sends its original draft while later selection changes survive', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  // 101 matches cross the inline limit; the real frontend must request a file.
  app.semanticSearchMatches = Array.from({ length: 101 }, (_, index) => ({
    path: 'src/main.mbt', rule_id: 'inspect($(x:arg))',
    start_line: index + 1, start_column: 1, end_line: index + 1, end_column: 11,
    matched_source: 'inspect(x)', source_context: [],
  }));
  const method = 'fs.materialize_semantic_selection';
  const materialization = Promise.withResolvers();
  const replyFor = app.replyFor.bind(app);
  app.replyFor = request => request.method === method ? materialization.promise : replyFor(request);
  app.rpcErrors.set(method, 'disk full');
  await app.install();
  await app.goto();
  await app.openSession();
  const shortcut = await page.evaluate(() =>
    navigator.platform.includes('Mac') ? 'Meta+Shift+F' : 'Control+Shift+F');
  await page.keyboard.press(shortcut);
  await page.getByRole('button', { name: 'Code search', exact: true }).click();
  await page.getByRole('textbox', { name: 'pattern', exact: true }).fill('inspect($(x:arg))');
  await page.getByLabel('Select pattern', { exact: true }).click();
  const chips = page.locator('.mention-chip');
  await expect(chips).toContainText('101 matches');
  expect(app.requests.filter(request => request.method === method)).toHaveLength(0);

  const composer = page.locator('#task');
  await composer.fill('Inspect the original selection');
  await page.getByTitle('Send', { exact: true }).click();
  await expect(page.getByText('Could not prepare semantic-search selection: disk full', { exact: true })).toBeVisible();
  await expect(chips).not.toContainText('preparing');
  await expect(composer).toHaveValue('Inspect the original selection');
  expect(app.requests.filter(request => request.method === 'agent.start')).toHaveLength(0);

  app.rpcErrors.delete(method);
  await page.getByTitle('Send', { exact: true }).click();
  await expect(chips).toContainText('preparing file');
  await expect.poll(() => app.requests.filter(request => request.method === method).length).toBe(2);
  const attempts = app.requests.filter(request => request.method === method);
  expect(attempts[1].params).toEqual(attempts[0].params);
  expect(attempts[1].params.matches).toHaveLength(101);

  // Preparing disables text input, but search selection remains interactive.
  await expect(composer).toBeDisabled();
  await page.getByRole('button', { name: 'Deselect match', exact: true }).first().click();
  await expect(chips.filter({ hasText: '100 matches' })).toHaveCount(1);
  expect(app.requests.filter(request => request.method === 'agent.start')).toHaveLength(0);
  const path = '.openseek/agent-context/semantic-search/selection.jsonl';
  materialization.resolve({ path, match_count: 101, file_count: 1 });
  await expect.poll(() => app.requests.find(request => request.method === 'agent.start')?.params.task)
    .toContain(`<semantic_search_file path="${path}" patterns="1" matches="101">`);
  const sent = app.requests.find(request => request.method === 'agent.start').params.task;
  expect(sent).toContain('Inspect the original selection');
  expect(sent).not.toContain('semantic_search_pending');
  await expect(composer).toBeEnabled();
  await expect(composer).toHaveValue('');
  await expect(chips).toHaveCount(1);
  await expect(chips).toContainText('100 matches');
  expect(app.requests.filter(request => request.method === 'agent.start')).toHaveLength(1);
  expect(app.pageErrors).toEqual([]);
});

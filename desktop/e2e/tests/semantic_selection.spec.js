import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

const method = 'fs.materialize_semantic_selection';
const path = '.openseek/agent-context/semantic-search/selection.jsonl';
const codexModels = [{ id: 'gpt-5.4-codex', displayName: 'GPT-5.4 Codex', isDefault: true,
  defaultReasoningEffort: 'medium', supportedReasoningEfforts: [{ reasoningEffort: 'medium', description: 'Balanced' }] }];

// 101 matches cross the inline limit; the real frontend must request a file.
const largeSelection = () => Array.from({ length: 101 }, (_, index) => ({
  path: 'src/main.mbt', rule_id: 'inspect($(x:arg))',
  start_line: index + 1, start_column: 1, end_line: index + 1, end_column: 11,
  matched_source: 'inspect(x)', source_context: [],
}));

async function openCodeSearch(page) {
  await page.keyboard.press(await page.evaluate(() =>
    navigator.platform.includes('Mac') ? 'Meta+Shift+F' : 'Control+Shift+F'));
  await page.getByRole('button', { name: 'Code search', exact: true }).click();
  await page.getByRole('textbox', { name: 'pattern', exact: true }).fill('inspect($(x:arg))');
}

async function selectWholePattern(page) {
  await openCodeSearch(page);
  await page.getByLabel('Select pattern', { exact: true }).click();
}

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
  await openCodeSearch(page);

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
  await results.getByRole('button', { name: 'Select match', exact: true }).first().click();
  await expect(chip).toContainText('1 matches');
  await page.getByRole('button', { name: 'Text search', exact: true }).click();
  await expect(chip).toHaveCount(0);
  await page.getByRole('button', { name: 'Code search', exact: true }).click();
  await expect(chip).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('closing the follow-up menu does not steal focus back from the composer', async ({ page }) => {
  await page.clock.install();
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  const composer = page.locator('#task');
  await composer.fill('Start a turn');
  await page.getByTitle('Send', { exact: true }).click();
  const choice = page.getByRole('button', { name: 'Follow-up action', exact: true });
  await expect(choice).toContainText('Steer now');
  await composer.fill('Queued draft to preserve');
  await choice.click();
  await expect(page.getByRole('listbox', { name: 'Follow-up action' })).toBeVisible();

  // Put the user's next focus change between selection and the closing paint.
  // Enter must still reach the composer when that paint eventually completes.
  await page.clock.pauseAt(await page.evaluate(() => Date.now()) + 100);
  await page.getByRole('option', { name: 'Queue next', exact: true }).click();
  await composer.focus();
  await page.clock.runFor(32);
  await expect(choice).toContainText('Queue next');
  await expect(composer).toBeFocused();
  await page.clock.resume();
  await page.keyboard.press('Enter');
  await expect(page.locator('.queued-input-row')).toContainText('Queued draft to preserve');
  expect(app.requests.filter(request => request.method === 'agent.steer')).toHaveLength(0);
  expect(app.pageErrors).toEqual([]);
});

for (const provider of ['OpenSeek session', 'Codex']) {
  test(`${provider} semantic chip opens the selected search results`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    app.codexModels = codexModels;
    app.semanticSearchMatches = [1, 2].map(line => ({
      path: 'src/main.mbt', rule_id: 'inspect($(x:arg))',
      start_line: line, start_column: 1, end_line: line, end_column: 11,
      matched_source: 'inspect(x)', source_context: [],
    }));
    await app.install();
    await app.goto();
    if (provider === 'Codex') {
      await page.getByRole('button', { name: 'Model', exact: true }).click();
      await page.getByRole('option', { name: 'GPT-5.4 Codex' }).click();
    } else if (provider === 'OpenSeek session') {
      await app.openSession();
    } else {
      // The shell can render before the new chat has an active workspace.
      await expect(page.getByRole('button', { name: 'Choose project, current project workspace', exact: true })).toBeVisible();
    }
    await openCodeSearch(page);
    await page.getByRole('button', { name: 'Select match', exact: true }).first().click();
    const chip = page.locator('.mention-chip .mention-jump');
    await expect(chip).toContainText('1 matches');
    await page.getByTitle('Open src/main.mbt:1', { exact: true }).click();
    await expect(page.locator('.search-results')).toBeHidden();
    await chip.click();
    await expect(page.getByRole('button', { name: 'Show all', exact: true })).toBeVisible();
    await expect(page.locator('.search-semantic-hit')).toHaveCount(1);
    await page.getByRole('button', { name: 'Show all', exact: true }).click();
    await expect(page.locator('.search-semantic-hit')).toHaveCount(2);
    await page.getByRole('button', { name: 'Hide panel', exact: true }).click();
    await chip.click();
    await expect(page.getByRole('button', { name: 'Show all', exact: true })).toBeVisible();
    await expect(page.locator('.search-semantic-hit')).toHaveCount(1);
    expect(app.pageErrors).toEqual([]);
  });
}

for (const worktree of [false, true]) {
  test(`Codex materializes large selections before start and steer (${worktree ? 'worktree' : 'local'})`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    app.codexModels = codexModels;
    app.semanticSearchMatches = largeSelection();
      const root = worktree ? '/workspace/worktrees/semantic-e2e' : '/workspace';
      const replyFor = app.replyFor.bind(app);
    app.replyFor = request => {
      if (request.method === method) return { path, match_count: 101, file_count: 1 };
      if (request.method === 'worktree.create') return { name: 'semantic-e2e', worktrees: [{
        name: 'semantic-e2e', branch: 'test', base: 'main', path: root, present: true,
        sessions: [], codex_thread: 'codex-thread-e2e',
      }] };
      if (request.method === 'codex.thread.resume') return { thread: { id: 'codex-thread-e2e', cwd: root, turns: [] } };
      if (request.method === 'codex.turn.steer') return { turnId: 'codex-turn-e2e' };
      return replyFor(request);
    };
    app.rpcErrors.set(method, 'disk full');
    await app.install();
    await app.goto();
    await page.getByRole('button', { name: 'Model', exact: true }).click();
    await page.getByRole('option', { name: 'GPT-5.4 Codex' }).click();
    if (worktree) await page.locator('button.composer-worktree').click();
    await selectWholePattern(page);
    const composer = page.locator('#task');
    await composer.fill('Inspect selected matches');
    expect(app.requests.filter(request => request.method === method)).toHaveLength(0);
    await page.getByTitle('Send', { exact: true }).click();
    await expect(page.getByText('Codex turn: disk full', { exact: true })).toBeVisible();
    await expect(composer).toHaveValue('Inspect selected matches');
    expect(app.requests.filter(request => request.method === 'codex.turn.start')).toHaveLength(0);
    app.rpcErrors.delete(method);
    await page.getByTitle('Send', { exact: true }).click();
    await expect.poll(() => app.requests.filter(request => request.method === 'codex.turn.start').length).toBe(1);
    const started = app.requests.find(request => request.method === 'codex.turn.start');
    expect(started.params.input).toContainEqual({ type: 'mention', name: 'selection.jsonl', path: `${root}/${path}` });
    expect(JSON.stringify(started.params.input)).not.toContain('<match file=');
    expect(app.requests.filter(request => request.method === method).map(request => request.params.root)).toEqual([root, root]);
    await expect(page.locator('.mention-chip')).toHaveCount(0);
    // The new thread has its own search state; select again for a running turn.
    await selectWholePattern(page);
    await expect(page.locator('.mention-chip')).toContainText('101 matches');
    await composer.fill('Inspect these too');
    await page.getByTitle('Steer the running task', { exact: true }).click();
    await expect.poll(() => app.requests.filter(request => request.method === 'codex.turn.steer').length).toBe(1);
    const steered = app.requests.find(request => request.method === 'codex.turn.steer');
    expect(steered.params.input).toContainEqual({ type: 'mention', name: 'selection.jsonl', path: `${root}/${path}` });
    expect(JSON.stringify(steered.params.input)).not.toContain('<match file=');
    expect(app.pageErrors).toEqual([]);
  });
}

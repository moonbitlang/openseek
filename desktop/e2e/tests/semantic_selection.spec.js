import { test, expect } from '@playwright/test';
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

test('large semantic selection retries and sends its original draft while later selection changes survive', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.semanticSearchMatches = largeSelection();
  const materialization = Promise.withResolvers();
  const replyFor = app.replyFor.bind(app);
  app.replyFor = request => request.method === method ? materialization.promise : replyFor(request);
  app.rpcErrors.set(method, 'disk full');
  await app.install();
  await app.goto();
  await app.openSession();
  await selectWholePattern(page);
  const chips = page.locator('.mention-chip');
  await expect(chips).toContainText('101 matches');
  expect(app.requests.filter(request => request.method === method)).toHaveLength(0);

  const composer = page.locator('#task');
  await composer.fill('Inspect the original selection');
  await page.getByTitle('Send', { exact: true }).click();
  await expect(page.getByText('Could not prepare semantic-search selection: disk full', { exact: true })).toBeVisible();
  await expect(composer).toBeEnabled();
  await expect(composer).toHaveValue('Inspect the original selection');
  expect(app.requests.filter(request => request.method === 'agent.start')).toHaveLength(0);

  app.rpcErrors.delete(method);
  await page.getByTitle('Send', { exact: true }).click();
  await expect(composer).toBeDisabled();
  await expect.poll(() => app.requests.filter(request => request.method === method).length).toBe(2);
  const attempts = app.requests.filter(request => request.method === method);
  expect(attempts[1].params).toEqual(attempts[0].params);
  expect(attempts[1].params.matches).toHaveLength(101);

  // Preparing disables text input, but search selection remains interactive.
  await page.getByRole('button', { name: 'Deselect match', exact: true }).first().click();
  await expect(chips.filter({ hasText: '100 matches' })).toHaveCount(1);
  expect(app.requests.filter(request => request.method === 'agent.start')).toHaveLength(0);
  materialization.resolve({ path, match_count: 101, file_count: 1 });
  await expect.poll(() => app.requests.find(request => request.method === 'agent.start')?.params.task)
    .toContain(`<semantic_search_file path="${path}" patterns="1" matches="101">`);
  const sent = app.requests.find(request => request.method === 'agent.start').params.task;
  expect(sent).toContain('Inspect the original selection');
  await expect(composer).toBeEnabled();
  await expect(composer).toHaveValue('');
  await expect(chips).toHaveCount(1);
  await expect(chips).toContainText('100 matches');
  expect(app.requests.filter(request => request.method === 'agent.start')).toHaveLength(1);
  expect(app.pageErrors).toEqual([]);
});


test('queued message Edit waits for semantic preparation so the send keeps its draft and target', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.semanticSearchMatches = largeSelection();
  const materialization = Promise.withResolvers();
  const replyFor = app.replyFor.bind(app);
  app.replyFor = request => request.method === method
    ? materialization.promise : replyFor(request);
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
  await page.getByRole('option', { name: 'Queue next', exact: true }).click();
  await composer.press('Enter');
  const queued = page.locator('.queued-input-row');
  await expect(queued).toContainText('Queued draft to preserve');

  await selectWholePattern(page);
  await composer.fill('Inspect the original selection');
  await page.getByTitle('Steer the running task', { exact: true }).click();
  await expect(composer).toBeDisabled();
  // Edit is inert while the frozen draft waits for its file.
  await queued.getByTitle('Edit', { exact: true }).click();
  await expect(composer).toHaveValue('Inspect the original selection');
  materialization.resolve({ path, match_count: 101, file_count: 1 });
  await expect(composer).toBeEnabled();
  await expect(composer).toHaveValue('');
  await expect.poll(() => app.requests.find(request => request.method === 'agent.steer')?.params.text)
    .toContain(`<semantic_search_file path="${path}" patterns="1" matches="101">`);
  expect(app.requests.find(request => request.method === 'agent.steer').params.text)
    .toContain('Inspect the original selection');
  expect(app.requests.filter(request => request.method === 'agent.queue' && request.params.action === 'edit'))
    .toHaveLength(0);
  await expect(queued).toContainText('Queued draft to preserve');
  await queued.getByTitle('Edit', { exact: true }).click();
  await expect(composer).toHaveValue('Queued draft to preserve');
  await composer.fill('Edited after preparation');
  await page.getByTitle('Save queued message', { exact: true }).click();
  await expect(queued).toContainText('Edited after preparation');
  expect(app.pageErrors).toEqual([]);
});

for (const provider of ['OpenSeek new chat', 'OpenSeek session', 'Codex']) {
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
        codex_thread: 'codex-thread-e2e',
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

for (const clear of [false, true]) {
  test(`failed preparation restores the ${clear ? 'cleared' : 'latest'} selection`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    app.semanticSearchMatches = largeSelection();
      app.rpcErrors.set(method, 'disk full');
    app.rpcDelays.set(method, 1500);
    await app.install();
    await app.goto();
    await app.openSession();
    await selectWholePattern(page);
    const composer = page.locator('#task');
    const chips = page.locator('.mention-chip');
    await composer.fill('Inspect selected matches');
    await page.getByTitle('Send', { exact: true }).click();
    await expect(composer).toBeDisabled();
    if (clear) await page.getByRole('button', { name: 'Clear selection', exact: true }).click();
    else await page.getByRole('button', { name: 'Deselect match', exact: true }).first().click();
    await expect(page.getByText('Could not prepare semantic-search selection: disk full', { exact: true })).toBeVisible();
    await expect(composer).toHaveValue('Inspect selected matches');
    await expect(chips).toHaveCount(clear ? 0 : 1);
    if (!clear) await expect(chips).toContainText('100 matches');
    await page.getByTitle('Send', { exact: true }).click();
    await expect.poll(() => app.requests.find(request => request.method === 'agent.start')).toBeTruthy();
    const sent = app.requests.find(request => request.method === 'agent.start').params.task;
    expect(sent.match(/<match file=/g) || []).toHaveLength(clear ? 0 : 100);
    expect(sent).not.toContain('semantic_search_file');
    expect(app.requests.filter(request => request.method === method)).toHaveLength(1);
    expect(app.pageErrors).toEqual([]);
  });
}


test('a fresh draft cannot switch agents while its semantic snapshot is being written', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.codexModels = codexModels;
  app.semanticSearchMatches = largeSelection();
  const materialization = Promise.withResolvers();
  const replyFor = app.replyFor.bind(app);
  app.replyFor = request => request.method === method ? materialization.promise : replyFor(request);
  await app.install();
  await app.goto();
  await selectWholePattern(page);
  const picker = page.getByRole('button', { name: 'Model', exact: true });
  await expect(picker).toBeEnabled();
  await picker.click();
  await expect(page.getByRole('option', { name: 'GPT-5.4 Codex', exact: true })).toBeVisible();
  await page.keyboard.press('Escape');
  await page.locator('#task').fill('Inspect the original selection');
  await page.locator('#send').click();
  await expect.poll(() => app.requests.filter(request => request.method === method).length).toBe(1);
  await expect(picker).toBeDisabled();
  materialization.resolve({ path, match_count: 101, file_count: 1 });
  await expect.poll(() => app.requests.find(request => request.method === 'agent.start')?.params.task)
    .toContain(`<semantic_search_file path="${path}" patterns="1" matches="101">`);
  await expect(picker).toBeEnabled();
  expect(app.requests.filter(request => request.method === 'agent.start')).toHaveLength(1);
  expect(app.requests.filter(request => request.method === 'codex.draft.open')).toHaveLength(0);
  expect(app.pageErrors).toEqual([]);
});

import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('workspace search supports toggles and keyboard navigation', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  // The query field is rendered once the project's checkout is known, and the
  // shortcut focuses it only once. Pressed earlier, the panel keeps the focus
  // and the field that appears later is left unfocused. The composer offers a
  // retry for the worktree list for as long as the checkout is unknown.
  await expect(page.getByRole('complementary').getByRole('button', { name: 'workspace', exact: true })).toBeVisible();
  await expect(page.getByTitle("Request this workspace's worktree list again", { exact: true })).toBeHidden();

  const shortcut = await page.evaluate(() =>
    navigator.platform.includes('Mac') ? 'Meta+Shift+F' : 'Control+Shift+F');
  await page.keyboard.press(shortcut);

  const tabs = page.getByRole('tablist', { name: 'Explorer views' });
  const filesTab = tabs.getByRole('tab', { name: 'Files' });
  const searchTab = tabs.getByRole('tab', { name: 'Search' });
  await expect(searchTab).toHaveAttribute('aria-selected', 'true');

  const query = page.getByRole('tabpanel', { name: 'Search', exact: true })
    .getByRole('textbox', { name: 'Search', exact: true });
  await expect(query).toBeFocused();

  const wholeWord = page.getByRole('button', { name: 'Match Whole Word' });
  await expect(wholeWord).toHaveAttribute('aria-pressed', 'false');
  await wholeWord.click();
  await expect(wholeWord).toHaveAttribute('aria-pressed', 'true');

  await searchTab.focus();
  await page.keyboard.press('ArrowRight');
  await expect(filesTab).toBeFocused();
  await expect(filesTab).toHaveAttribute('aria-selected', 'true');
  await page.keyboard.press('End');
  await expect(searchTab).toHaveAttribute('aria-selected', 'true');
  await expect(query).toBeFocused();
  expect(app.pageErrors).toEqual([]);
});

test('Review loads changed files and preserves its interactive diff workflow', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openReview();

  await expect(page.getByRole('tab', { name: 'Changes 2', exact: true }))
    .toHaveAttribute('aria-selected', 'true');
  await expect.poll(() => app.requests.find(request => request.method === 'git.changes'))
    .toMatchObject({
      params: {
        session: 'session-1',
        workspace: '/workspace',
      },
    });
  const changes = page.locator('#review-changes-body');
  await expect(changes.locator('.review-progress-summary')).toHaveText(
    '0 / 2 reviewed',
  );
  const main = changes.getByRole('treeitem', { name: /View diff: src\/main\.mbt/ });
  const library = changes.getByRole('treeitem', { name: /View diff: src\/lib\.mbt/ });
  await expect(main).toHaveAttribute('aria-current', 'false');
  await main.click();
  await page.getByRole('button', { name: 'Show file tree', exact: true }).click();

  await expect.poll(() => app.requests.find(request =>
    request.method === 'fs.read_file' && request.params?.path === '/workspace/src/main.mbt'))
    .toBeTruthy();
  await expect.poll(() => app.requests.find(request =>
    request.method === 'git.original_file' &&
    request.params?.path === 'src/main.mbt' &&
    request.params?.revision === app.gitBaseline))
    .toBeTruthy();
  const reviewToolbar = page.getByRole('toolbar', { name: 'Review mode' });
  await expect(reviewToolbar.getByRole('button', { name: 'Token diff' })).toHaveAttribute(
    'aria-pressed',
    'true',
  );
  await expect(page.locator('.semantic-review[data-mode="token"]')).toBeVisible();

  // Line diff keeps semantic-only filters inert. Token and Tree make those
  // user controls available.
  await reviewToolbar.getByRole('button', { name: 'Line diff' }).click();
  const ignoreComments = page.getByRole('button', { name: 'Ignore comments' });
  const ignoreTests = page.getByRole('button', { name: 'Ignore tests' });
  await expect(ignoreComments).toBeDisabled();
  await expect(ignoreTests).toBeDisabled();

  await reviewToolbar.getByRole('button', { name: 'File view' }).click();
  await expect(reviewToolbar.getByRole('button', { name: 'File view' })).toHaveAttribute(
    'aria-pressed',
    'true',
  );
  await reviewToolbar.getByRole('button', { name: 'Line diff' }).click();

  await reviewToolbar.getByRole('button', { name: 'Token diff' }).click();
  await expect(reviewToolbar.getByRole('button', { name: 'Token diff' })).toHaveAttribute(
    'aria-pressed',
    'true',
  );
  await expect(ignoreComments).toHaveAttribute('aria-pressed', 'true');
  await expect(ignoreTests).toHaveAttribute('aria-pressed', 'true');
  await ignoreComments.click();
  await ignoreTests.click();
  await expect(ignoreComments).toHaveAttribute('aria-pressed', 'false');
  await expect(ignoreTests).toHaveAttribute('aria-pressed', 'false');

  await reviewToolbar.getByRole('button', { name: 'Tree diff' }).click();
  await expect(reviewToolbar.getByRole('button', { name: 'Tree diff' })).toHaveAttribute(
    'aria-pressed',
    'true',
  );

  const layout = page.getByRole('group', { name: 'Diff layout' });
  await layout.getByRole('button', { name: 'Unified diff layout' }).click();
  await expect(layout.getByRole('button', { name: 'Unified diff layout' })).toHaveAttribute(
    'aria-pressed',
    'true',
  );
  const semantic = page.locator(
    '.semantic-review[data-mode="tree"][data-layout="unified"]',
  );
  await expect(semantic).toBeVisible();
  const semanticDiffCandidate = semantic.locator('.semantic-diff-editor-host').filter({
    has: page.locator(
      '.moonbit-diff-editor-modified '
        + '.view-lines[data-view-part="view-lines"] > .view-line',
      { hasText: 'working tree' },
    ),
  }).first();
  await expect(semanticDiffCandidate).toBeVisible();
  const semanticDiffId = await semanticDiffCandidate.getAttribute('id');
  expect(semanticDiffId).not.toBeNull();
  const semanticDiff = semantic.locator(`[id=${JSON.stringify(semanticDiffId)}]`);
  const semanticModified = semanticDiff.locator('.moonbit-diff-editor-modified');
  await expect(semanticDiff).toBeVisible();
  await expect(semanticDiff.locator('.moonbit-diff-editor').first())
    .toHaveAttribute('data-render-mode', 'inline');

  const feedbackLine = semanticModified.locator(
    '.view-lines[data-view-part="view-lines"] > .view-line',
  ).filter({ hasText: 'working tree' }).first();
  await expect(feedbackLine).toBeVisible();
  const feedbackLineBox = await feedbackLine.boundingBox();
  const modifiedBox = await semanticModified.boundingBox();
  expect(feedbackLineBox).not.toBeNull();
  expect(modifiedBox).not.toBeNull();
  await page.mouse.move(
    Math.min(
      feedbackLineBox.x + 20,
      modifiedBox.x + modifiedBox.width - 10,
    ),
    feedbackLineBox.y + feedbackLineBox.height / 2,
  );
  const feedbackGlyph = semanticModified.locator(
    '.agent-feedback-glyph.line-hover',
  );
  await expect(feedbackGlyph).toBeVisible();
  const feedbackGlyphBox = await feedbackGlyph.boundingBox();
  expect(feedbackGlyphBox).not.toBeNull();
  await page.mouse.click(
    feedbackGlyphBox.x + feedbackGlyphBox.width / 2,
    feedbackGlyphBox.y + feedbackGlyphBox.height / 2,
  );
  const feedbackInput = semanticDiff.locator(
    '.agent-feedback-input-widget textarea',
  );
  await expect(feedbackInput).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(feedbackInput).toBeHidden();

  await reviewToolbar.getByRole('button', { name: 'Line diff' }).click();
  await expect(reviewToolbar.getByRole('button', { name: 'Line diff' })).toHaveAttribute(
    'aria-pressed',
    'true',
  );
  await expect(layout.getByRole('button', { name: 'Unified diff layout' })).toHaveAttribute(
    'aria-pressed',
    'true',
  );

  const progress = page.getByRole('button', { name: 'Mark file reviewed' });
  await progress.click();
  await expect(page.getByRole('button', { name: 'Mark file unreviewed' }))
    .toHaveAttribute('aria-pressed', 'true');
  await expect(changes.locator('.review-progress-summary')).toHaveText(
    '1 / 2 reviewed',
  );
  await page.getByRole('button', { name: 'Next change' }).click();
  await expect(library).toHaveAttribute('aria-current', 'page');
  await expect(page.locator('.review-nav-position')).toHaveText('File 2 of 2');
  await expect.poll(() => app.requests.find(request =>
    request.method === 'git.original_file' &&
    request.params?.path === 'src/lib.mbt' &&
    request.params?.revision === app.gitBaseline))
    .toBeTruthy();
  expect(app.pageErrors).toEqual([]);
});

test('Git history expands commits and opens an immutable historical diff', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openReview();

  await expect.poll(() => app.requests.find(request => request.method === 'git.history'))
    .toMatchObject({
      params: {
        session: 'session-1',
        workspace: '/workspace',
      },
    });
  const history = page.getByRole('tree', { name: 'Git commit history', includeHidden: true });
  const head = history.getByRole('treeitem', { name: /Cover Desktop Git flows/ });
  const merge = history.getByRole('treeitem', { name: /Merge fixture lanes/ });
  const parent = history.getByRole('treeitem', { name: /Add Review surface/ });
  await head.focus();
  await page.keyboard.press('ArrowDown');
  await expect(merge).toBeFocused();
  await page.keyboard.press('ArrowDown');
  await expect(parent).toBeFocused();
  await page.keyboard.press('Home');
  await expect(head).toBeFocused();
  await page.keyboard.press('Enter');

  await expect.poll(() => app.requests.find(request =>
    request.method === 'git.commit_changes' && request.params?.commit === app.gitHead))
    .toMatchObject({
      params: {
        session: 'session-1',
        workspace: '/workspace',
        commit: app.gitHead,
      },
    });
  await expect(head).toHaveAttribute('aria-expanded', 'true');
  const historicalMain = history.getByRole('treeitem', { name: /src\/main\.mbt/, includeHidden: true });
  await historicalMain.click();
  await expect(history).toBeHidden();
  await expect(historicalMain).toHaveAttribute('aria-current', 'page');

  await expect.poll(() => app.requests.filter(request =>
    request.method === 'git.original_file' &&
    request.params?.path === 'src/main.mbt' &&
    [app.gitMerge, app.gitHead].includes(request.params?.revision)).length)
    .toBe(2);
  await expect(page.locator('.editor-tab.active')).toContainText('main.mbt (cccccccc)');
  const breadcrumb = page.locator('.history-breadcrumb');
  await expect(breadcrumb.locator('.history-commit-crumb')).toHaveText('cccccccc');
  await expect(breadcrumb.locator('.crumb-file')).toHaveText('src/main.mbt');
  const algorithms = page.getByRole('toolbar', { name: 'Comparison algorithm' });
  await expect(algorithms.getByRole('button', { name: 'Token diff' })).toHaveAttribute(
    'aria-pressed',
    'true',
  );
  await expect(algorithms.getByRole('button')).toHaveText(['Line', 'Token', 'Tree']);
  await expect(page.getByRole('button', { name: 'Ignore comments' })).toBeEnabled();
  await expect(page.getByRole('button', { name: 'Ignore tests' })).toBeEnabled();
  expect(app.pageErrors).toEqual([]);
});

test('quick open moves its keyboard selection and opens the chosen file', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openQuickOpen();
  const input = page.getByRole('combobox', { name: 'Search workspace files' });
  await expect(input).toBeFocused();
  const mainResult = page.getByRole('option', { name: /main\.mbt/ });
  const readmeResult = page.getByRole('option', { name: /README\.md/ });
  await expect(mainResult).toBeVisible();
  await expect(readmeResult).toBeVisible();
  await expect(mainResult).toHaveAttribute('aria-selected', 'true');
  await input.press('ArrowDown');
  await expect(readmeResult).toHaveAttribute('aria-selected', 'true');
  await input.press('ArrowUp');
  await expect(mainResult).toHaveAttribute('aria-selected', 'true');
  await input.press('Enter');

  await expect(input).toBeHidden();
  await expect.poll(() => app.requests.find(request =>
    request.method === 'fs.read_file' &&
    request.params?.path === '/workspace/src/main.mbt')).toBeTruthy();
  expect(app.pageErrors).toEqual([]);
});

test('transcript overview previews failed turns and jumps among mounted messages', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  const events = [
    {
      sequence: 1,
      ts: 1_781_144_351_123,
      item: {
        kind: 'user',
        payload: { content: 'Show the browser fixture: first question' },
      },
    },
    {
      sequence: 2,
      ts: 1_781_144_352_123,
      item: {
        kind: 'assistant',
        payload: {
          content: 'First answer recovered after the tool failed.',
          tool_calls: [{ id: 'failed-after-answer', name: 'shell', arguments: '{}' }],
        },
      },
    },
    {
      sequence: 3,
      ts: 1_781_144_353_123,
      item: {
        kind: 'tool_result',
        payload: {
          tool_call_id: 'failed-after-answer',
          tool_name: 'shell',
          content: 'fixture failure',
          is_error: true,
          brief: 'failed after answer',
        },
      },
    },
  ];
  let sequence = 4;
  for (let turn = 2; turn <= 100; turn += 1) {
    events.push({
      sequence,
      ts: 1_781_144_350_123 + sequence * 1_000,
      item: {
        kind: 'user',
        payload: { content: `Question ${turn} keeps the overview rail scrollable` },
      },
    });
    sequence += 1;
    events.push({
      sequence,
      ts: 1_781_144_350_123 + sequence * 1_000,
      item: {
        kind: 'assistant',
        payload: { content: `Answer ${turn}` },
      },
    });
    sequence += 1;
  }
  app.sessionEvents = events;
  await app.install();
  await app.goto();
  await app.openSession();

  const overview = page.getByRole('navigation', { name: 'Conversation overview' });
  const ticks = overview.locator('.overview-tick-button');
  const failed = ticks.first();
  await expect(failed).toBeVisible();
  await expect(failed).toHaveAccessibleName(
    'Show the browser fixture: first question (had errors)',
  );
  await failed.hover();
  const preview = overview.getByRole('tooltip');
  await expect(preview.locator('.overview-preview-prompt')).toContainText('first question');
  await expect(preview.locator('.overview-preview-reply')).toContainText('First answer');
  await expect(preview.locator('.overview-preview-failed')).toHaveText('had errors');
  const transcript = page.locator('#transcript');
  const scrollTopBeforeJump = await transcript.evaluate(node => node.scrollTop);
  await failed.click();
  await expect.poll(() => transcript.evaluate(node => node.scrollTop))
    .toBeLessThan(scrollTopBeforeJump);

  await overview.dispatchEvent('mouseleave');
  await expect(overview.getByRole('tooltip')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('selected transcript text can be quoted in a floating reply', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  const filler = Array.from({ length: 40 }, (_, index) => `Filler paragraph ${index + 1}.`);
  app.sessionEvents = [
    {
      sequence: 1,
      item: { kind: 'user', payload: { content: 'Show the browser fixture quote reply' } },
    },
    {
      sequence: 2,
      item: {
        kind: 'assistant',
        payload: {
          content: [...filler, 'First answer paragraph.', 'Second answer paragraph.']
            .join('\n\n'),
        },
      },
    },
  ];
  await app.install();
  await app.goto();
  await app.openSession();

  const transcript = page.locator('#transcript');
  const markdown = page.locator('.transcript .msg-content.markdown');
  const first = markdown.getByText('First answer paragraph.');
  const second = markdown.getByText('Second answer paragraph.');
  const bar = page.getByRole('toolbar', { name: 'Selection actions' });
  const reply = page.getByRole('dialog', { name: 'Reply to selection' });
  const comment = reply.getByRole('textbox', { name: 'Reply' });
  const batch = reply.getByRole('checkbox', { name: 'Batch' });
  const task = page.locator('#task');
  const pinned = () => page.evaluate(() => CSS.highlights.has('quote-reply'));
  const selectWord = paragraph => paragraph.dblclick({ position: { x: 8, y: 8 } });
  const openReply = async paragraph => {
    await selectWord(paragraph);
    await bar.getByRole('button', { name: 'Reply' }).click();
    await expect(comment).toBeFocused();
  };
  const scrollTranscript = async delta => {
    const box = await transcript.boundingBox();
    await page.mouse.move(box.x + box.width / 2, box.y + 40);
    await page.mouse.wheel(0, delta);
  };

  // Selecting text offers Reply just above it; Reply opens a composer that
  // keeps the quote in view and painted while the comment is typed.
  await selectWord(first);
  await expect(bar.getByRole('button')).toHaveText(['Copy', 'Reply']);
  const barBox = await bar.boundingBox();
  const firstBox = await first.boundingBox();
  expect(barBox.y + barBox.height).toBeLessThanOrEqual(firstBox.y);
  await bar.getByRole('button', { name: 'Reply' }).click();
  await expect(reply.locator('blockquote')).toHaveText('First');
  await expect(comment).toBeFocused();
  expect(await pinned()).toBe(true);
  await expect(reply.getByRole('button', { name: 'Send reply' })).toBeDisabled();

  // Batched, the reply joins the message being written, which is where the
  // reader lands; nothing is sent.
  await batch.check();
  await expect(comment).toBeFocused();
  await expect(reply.getByRole('button', { name: 'Add to message' })).toBeEnabled();
  await page.keyboard.type('Why first?');
  await page.keyboard.press('Enter');
  await expect(reply).toHaveCount(0);
  await expect(task).toHaveValue('> First\n\nWhy first?\n\n');
  await expect(task).toBeFocused();
  expect(await pinned()).toBe(false);
  expect(app.requests.some(request => request.method === 'agent.start')).toBe(false);

  // An offer follows its selection: it goes on Escape, when the selection
  // goes, and when a scroll moves the text from under it.
  await selectWord(first);
  await expect(bar).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(bar).toHaveCount(0);
  await selectWord(first);
  await expect(bar).toBeVisible();
  await page.evaluate(() => document.getSelection().removeAllRanges());
  await expect(bar).toHaveCount(0);
  await selectWord(first);
  await expect(bar).toBeVisible();
  await scrollTranscript(-60);
  await expect(bar).toHaveCount(0);
  await scrollTranscript(60);

  // A reply being typed survives a scroll, and closes on Escape or a press
  // elsewhere.
  await openReply(first);
  await page.keyboard.type('Keep me');
  await scrollTranscript(-60);
  await expect(comment).toHaveValue('Keep me');
  await scrollTranscript(60);
  await page.keyboard.press('Escape');
  await expect(reply).toHaveCount(0);
  await openReply(first);
  await page.locator('main .topbar-title').click();
  await expect(reply).toHaveCount(0);
  await expect(task).toHaveValue('> First\n\nWhy first?\n\n');

  // Text selected outside the transcript gets no offer, and neither does a
  // transcript selection left from earlier when the mouse is pressed and
  // released somewhere else.
  const press = (locator, selected) => locator.evaluate((element, selected) => {
    const event = type => new MouseEvent(type, { bubbles: true, button: 0 });
    element.dispatchEvent(event('mousedown'));
    const range = document.createRange();
    range.selectNodeContents(selected ?? element);
    const selection = document.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
    element.dispatchEvent(event('mouseup'));
  }, selected);
  const settled = () => page.evaluate(() => new Promise(resolve => {
    setTimeout(() => requestAnimationFrame(() => requestAnimationFrame(resolve)), 0);
  }));
  const title = page.locator('main .topbar-title');
  await press(title);
  await settled();
  await expect(bar).toHaveCount(0);
  await press(title, await first.elementHandle());
  await settled();
  await expect(bar).toHaveCount(0);
  await press(first);
  await expect(bar).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(bar).toHaveCount(0);

  // Escape meant for another overlay leaves the reply and its text alone.
  await openReply(first);
  await page.keyboard.type('Still here');
  await page.keyboard.press(await page.evaluate(() =>
    navigator.platform.includes('Mac') ? 'Meta+KeyP' : 'Control+KeyP'));
  const quickOpen = page.getByRole('dialog', { name: 'Search workspace files' });
  await expect(quickOpen).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(quickOpen).toHaveCount(0);
  await expect(comment).toHaveValue('Still here');
  await comment.focus();
  await page.keyboard.press('Escape');
  await expect(reply).toHaveCount(0);

  // A composer holding a shell command is not editing a message: it declines
  // the reply, which says so and keeps what was typed until it is taken.
  const batched = '> First\n\nWhy first?\n\n';
  await task.fill('!echo hello');
  await expect(page.locator('.composer-mode-chip')).toBeVisible();
  await openReply(first);
  await page.keyboard.type('Not a command');
  await page.keyboard.press('Enter');
  await expect(reply.getByRole('status')).toHaveText(
    "The message box can't take a reply right now.");
  await expect(comment).toHaveValue('Not a command');
  await expect(task).toHaveValue('!echo hello');
  expect(app.requests.some(request => request.method === 'terminal.open')).toBe(false);
  await task.fill(batched);
  await comment.focus();
  await page.keyboard.press('Enter');
  await expect(reply).toHaveCount(0);
  await expect(task).toHaveValue(`${batched}> First\n\nNot a command\n\n`);
  await task.fill(batched);

  // A reply belongs to the conversation it quotes: leaving that conversation
  // from the keyboard takes the reply off screen instead of retargeting it.
  await openReply(second);
  await page.keyboard.type('Wrong place');
  await page.keyboard.press(await page.evaluate(() =>
    navigator.platform.includes('Mac') ? 'Meta+KeyN' : 'Control+KeyN'));
  await expect(page.locator('.empty-title')).toBeVisible();
  await expect(reply).toHaveCount(0);
  await expect(task).toHaveValue('');
  await page.getByText('Rabbita browser fixture', { exact: true }).first().click();
  await expect(second).toBeVisible();
  await expect(reply).toHaveCount(0);
  await expect(task).toHaveValue('> First\n\nWhy first?\n\n');

  // Unbatched, the reply is sent at once with what was already batched.
  await openReply(second);
  await expect(batch).toBeChecked();
  await batch.uncheck();
  await expect(comment).toBeFocused();
  await page.keyboard.type('And this?');
  await page.keyboard.press('Enter');
  await expect(reply).toHaveCount(0);
  await expect.poll(() => app.requests.find(request =>
    request.method === 'agent.start')?.params.task)
    .toBe('> First\n\nWhy first?\n\n> Second\n\nAnd this?');
  await expect(task).toHaveValue('');
  expect(app.pageErrors).toEqual([]);
});

test('approval card mirrors host claims and sends an unclaimed decision', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();

  app.notify('agent.started', {
    run_id: 'run-1',
    session: 'session-1',
    session_root: '/workspace/.openseek',
    model: 'deepseek-v4-pro',
    max_steps: 1000,
  });
  const pending = {
    run_id: 'run-1', session: 'session-1', answered: false,
    id: 'approval-1', tool_name: 'mbtx',
    detail: 'run this snippet with no sandbox policy',
    body: 'fn main { @myshell.Cmd("npm", ["ci"]) }',
  };
  app.notify('agent.approvals', { generation: 1, approvals: [pending] });

  const approval = page.locator('.composer-approval');
  await expect(approval).toBeVisible();
  // A different client answered: this page must stop offering either decision.
  app.notify('agent.approvals', { generation: 2, approvals: [{ ...pending, answered: true }] });
  await expect(approval.locator('.composer-approval-state')).toBeVisible();
  await expect(approval.getByRole('button')).toHaveCount(0);
  app.notify('agent.approvals', { generation: 3, approvals: [] });
  await expect(approval).toHaveCount(0);

  // A subsequent, unclaimed question is still answerable through the bridge.
  app.notify('agent.approvals', { generation: 4, approvals: [{ ...pending, id: 'approval-2' }] });
  await approval.getByRole('button', { name: 'Allow once' }).click();
  await expect.poll(() => app.requests.some(request =>
    request.method === 'agent.approval' &&
    request.params?.run_id === 'run-1' &&
    request.params?.id === 'approval-2' &&
    request.params?.allow === true)).toBe(true);
  await expect(approval.locator('.composer-approval-state')).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('composer sends a turn and stops the accepted run', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();

  const composer = page.locator('#task');
  await composer.fill('Run the browser E2E turn');
  await page.getByTitle('Send', { exact: true }).click();
  await expect.poll(() => app.requests.find(request =>
    request.method === 'agent.start'))
    .toMatchObject({
      params: {
        task: 'Run the browser E2E turn',
        session: 'session-1',
      },
    });

  await composer.fill('Steer without losing the interrupt control');
  await expect(page.getByTitle('Stop', { exact: true })).toBeVisible();
  await expect(page.getByTitle('Steer the running task', { exact: true })).toBeVisible();
  await page.getByTitle('Stop', { exact: true }).click();
  await expect.poll(() => app.requests.find(request =>
    request.method === 'agent.cancel'))
    .toMatchObject({ params: { run_id: 'run-e2e' } });
  expect(app.pageErrors).toEqual([]);
});

test('deleting a live chat asks the host what goes with it and confirms once', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();

  const sent = method => app.requests
    .filter(request => request.method === method)
    .map(request => request.params);
  const stored = page.locator('.conversation-row[title="session-1"]');
  await stored.click();
  await expect(page.getByText('Browser result', { exact: true })).toBeVisible();
  const askToDelete = async () => {
    await stored.hover();
    await stored.getByRole('button', { name: 'Conversation actions' }).click();
    await page.getByRole('menuitem', { name: 'Delete…' }).click();
  };
  const body = page.getByRole('dialog', { name: 'Permanently delete this chat?', exact: true });

  // A chat without a worktree: the dialog is the plain one, and Cancel
  // deletes nothing.
  await askToDelete();
  await expect(body.getByRole('heading', { name: 'Permanently delete this chat?', exact: true })).toBeVisible();
  await expect(body).toContainText('“Rabbita browser fixture” and all of its subagent history');
  await expect(body).toContainText('Project files and Git branches will remain.');
  await expect(body).not.toContainText('worktree');
  expect(sent('session.delete_check')).toEqual([
    { session: 'session-1', workspace: '/workspace' },
  ]);
  await body.getByRole('button', { name: 'Cancel' }).click();
  await expect(body).toBeHidden();
  expect(sent('session.delete')).toEqual([]);
  await expect(stored).toBeVisible();

  // The host is asked again on every click, and the delete removes only
  // what its dialog showed. Here another window repairs the chat's worktree
  // while the plain dialog is open: the confirm names no checkout, so the
  // host stops and the same dialog comes back naming it.
  await askToDelete();
  await expect(body).not.toContainText('worktree');
  expect(sent('session.delete_check')).toHaveLength(2);
  app.sessionCheckout = { worktree: 'wt-1', dirty_paths: [], dirty_path_count: 0 };
  await page.getByRole('button', { name: 'Delete permanently' }).click();
  await expect(body).toContainText('its worktree checkout wt-1 is removed along with any ignored files in it');
  await expect(body).not.toContainText('uncommitted changes');
  await expect(stored).toBeVisible();

  // Then the checkout turns dirty before the next confirm. That request
  // agreed to remove a clean checkout, so the dialog comes back once more,
  // now with the changed paths, instead of quietly closing.
  app.sessionCheckout = {
    worktree: 'wt-1',
    dirty_paths: ['notes.txt'],
    dirty_path_count: 1,
  };
  await page.getByRole('button', { name: 'Delete permanently' }).click();
  await expect(body).toContainText('That checkout has uncommitted changes. Changed paths: notes.txt.');
  await expect(stored).toBeVisible();

  // Confirming now agrees to discard what the dialog listed, and there is
  // no further question.
  await page.getByRole('button', { name: 'Delete permanently' }).click();
  await expect.poll(() => sent('session.delete')).toEqual([
    { session: 'session-1', workspace: '/workspace' },
    { session: 'session-1', workspace: '/workspace', worktree: 'wt-1' },
    { session: 'session-1', workspace: '/workspace', worktree: 'wt-1', force: true },
  ]);
  await expect(body).toBeHidden();

  // Deleting the chat on screen replaces its entry with a fresh draft
  // instead of leaving an unavailable target behind.
  await expect(stored).toHaveCount(0);
  await expect(page.getByText('Browser result', { exact: true })).toHaveCount(0);
  await expect(page.getByText('This destination no longer exists or is no longer attached.')).toHaveCount(0);
  await expect(page).toHaveURL(/\/chat\/new$/);
  expect(sent('session.archive')).toEqual([]);
  expect(app.pageErrors).toEqual([]);
});

test('a failed first conversation load keeps selection and can retry', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.rpcErrors.set('session.load', 'fixture unavailable');
  await app.install();
  await app.goto();

  const row = page.locator('.conversation-row[title="session-1"]');
  await row.click();
  await expect(row).toHaveClass(/active/);
  await expect(page.getByText('Could not load conversation', { exact: true })).toBeVisible();
  await expect(page.getByText(/fixture unavailable/).last()).toBeVisible();
  await expect(row).toHaveClass(/load-failed/);

  app.rpcErrors.delete('session.load');
  await page.getByRole('button', { name: 'Retry' }).click();
  await expect(page.getByText('Browser result', { exact: true })).toBeVisible();
  await expect(row).toHaveClass(/active/);
  await expect(row).not.toHaveClass(/load-failed/);
  expect(app.pageErrors).toEqual([]);
});

test('settings persist host API changes through settings.set', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();

  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Settings' })).toBeVisible();
  await page.getByRole('tab', { name: 'Engine', exact: true }).click();
  await page.getByRole('button', { name: 'API endpoint' }).click();
  await page.getByRole('option', { name: 'Custom URL' }).click();
  await expect.poll(() => app.requests.some(request =>
    request.method === 'settings.set' &&
    request.params?.provider === 'custom')).toBe(true);

  await page.getByRole('textbox', { name: 'Endpoint URL' }).fill(
    'https://example.test/chat/completions',
  );
  await expect.poll(() => app.requests.some(request =>
    request.method === 'settings.set' &&
    request.params?.custom_api_url === 'https://example.test/chat/completions'))
    .toBe(true);
  await expect(page.getByRole('textbox', { name: 'Endpoint URL' })).toHaveValue(
    'https://example.test/chat/completions',
  );
  expect(app.pageErrors).toEqual([]);
});

test('initial OpenRouter setup only needs an API key', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.hostSettings.has_deepseek_key = false;
  await app.install();
  await app.goto();

  await expect(page.getByText('Set up your DeepSeek API key')).toBeVisible();
  await page.getByRole('button', { name: 'API endpoint' }).click();
  await page.getByRole('option', { name: 'OpenRouter' }).click();
  await page.locator('.setup-modal').getByLabel('API key').fill('sk-openrouter-test');
  await page.getByRole('button', { name: 'Save API key' }).click();

  await expect.poll(() => app.requests.some(request =>
    request.method === 'settings.set' &&
    request.params?.provider === 'custom' &&
    request.params?.custom_api_url === 'https://openrouter.ai/api/v1/chat/completions')).toBe(true);
  await expect.poll(() => app.requests.some(request =>
    request.method === 'settings.set' &&
    request.params?.provider === 'custom' &&
    request.params?.custom_api_key === 'sk-openrouter-test')).toBe(true);
  await expect(page.getByText('Set up OpenRouter')).toBeHidden();
  expect(app.requests.some(request => request.method === 'settings.set' && request.params?.deepseek_api_key !== undefined)).toBe(false);

  // OpenRouter uses the ordinary chat model selector and persisted preference.
  await app.openSession();
  await page.getByRole('button', { name: 'Model', exact: true }).click();
  await page.getByRole('option', { name: 'DS Pro', exact: true }).click();
  await expect.poll(() => page.evaluate(() => localStorage.getItem('openseek.model')))
    .toBe('deepseek-v4-pro');
  await page.getByRole('button', { name: 'Model', exact: true }).click();
  await page.getByRole('option', { name: 'DS Flash', exact: true }).click();
  await expect.poll(() => page.evaluate(() => localStorage.getItem('openseek.model')))
    .toBe('deepseek-flash');
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  expect(app.pageErrors).toEqual([]);
});

test('Codex account login can be started and cancelled from Settings', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.codexRequiresAuth = true;
  await app.install();
  await app.goto();

  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await page.getByRole('tab', { name: 'Engine', exact: true }).click();
  await page.getByRole('button', { name: 'Sign in with ChatGPT' }).click();
  await expect.poll(() => app.requests.some(request =>
    request.method === 'codex.account.login.start')).toBe(true);
  await expect(page.getByRole('link', { name: 'Open' })).toHaveAttribute(
    'href',
    'https://example.test/codex-login',
  );

  await page.getByRole('button', { name: 'Cancel sign-in' }).click();
  await expect.poll(() => app.requests.some(request =>
    request.method === 'codex.account.login.cancel' &&
    request.params?.loginId === 'login-e2e')).toBe(true);
  await expect(page.getByRole('button', { name: 'Sign in with ChatGPT' })).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('Codex creates a thread, sends its first turn, and stops it', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.codexModels = [
    {
      id: 'gpt-5.4-codex',
      displayName: 'GPT-5.4 Codex',
      isDefault: true,
      defaultReasoningEffort: 'medium',
      supportedReasoningEfforts: [
        { reasoningEffort: 'medium', description: 'Balanced' },
      ],
    },
  ];
  await app.install();
  await app.goto();

  // A model pick is the product's hand-off from a fresh OpenSeek draft to a
  // Codex draft. The rest of the test exercises the ordinary composer path.
  await page.getByRole('button', { name: 'Model', exact: true }).click();
  await page.getByRole('option', { name: 'GPT-5.4 Codex' }).click();
  await expect.poll(() => app.requests.find(request =>
    request.method === 'codex.draft.open'))
    .toMatchObject({ params: { cwd: '/workspace' } });

  // The request leaves in the same update that selects the Codex draft, a
  // frame before the Codex composer replaces SeekMoon's in the shared #task.
  // Wait for the destination textbox rather than filling the old one.
  await page.getByRole('textbox', {
    name: 'Ask Codex to inspect, edit, or explain this workspace.',
    exact: true,
  }).fill('Run the Codex browser E2E turn');
  await page.getByTitle('Send', { exact: true }).click();
  await expect.poll(() => app.requests.find(request =>
    request.method === 'codex.thread.start'))
    .toMatchObject({
      params: {
        cwd: '/workspace',
        model: 'gpt-5.4-codex',
      },
    });
  await expect.poll(() => app.requests.find(request =>
    request.method === 'codex.turn.start'))
    .toMatchObject({
      params: {
        threadId: 'codex-thread-e2e',
        input: [{ type: 'text', text: 'Run the Codex browser E2E turn' }],
      },
    });

  await page.getByTitle('Stop', { exact: true }).click();
  await expect.poll(() => app.requests.find(request =>
    request.method === 'codex.turn.interrupt'))
    .toMatchObject({
      params: {
        threadId: 'codex-thread-e2e',
        turnId: 'codex-turn-e2e',
      },
    });
  expect(app.pageErrors).toEqual([]);
});

test('workspace settings dialog opens and persists per-workspace choices', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();

  // The project row's "⋮" menu opens its workspace settings dialog.
  await page.locator('.workspace-row', { hasText: 'workspace' }).hover();
  await page.getByRole('button', { name: 'Workspace actions', exact: true }).click();
  await page.getByRole('menuitem', { name: 'Workspace settings' }).click();
  const workspaceSettings = page.getByRole('dialog', { name: 'Workspace settings' });
  await expect(workspaceSettings).toBeVisible();

  // The dialog reads the host's authoritative snapshot before enabling the
  // selects.
  await expect.poll(() => app.requests.find(request =>
    request.method === 'workspace.settings_get')).toMatchObject({
    params: { workspace: '/workspace' },
  });

  const launchMode = page.getByRole('button', { name: 'New chats' });
  await expect(launchMode).toBeEnabled();
  await launchMode.click();
  await page.getByRole('option', { name: 'Worktree' }).click();
  await expect.poll(() => app.requests.find(request =>
    request.method === 'workspace.settings_set' &&
    request.params?.worktree_mode === true)).toBeTruthy();
  // Wait for the harness store to settle before replaying the commit
  // broadcast, so the optimistic mirror is never rolled back by a
  // pre-mutation payload.
  await expect.poll(() => app.workspaceSettingsFor('/workspace').worktree_mode).toBe(true);
  app.notify(
    'workspace.settings_changed',
    { ...app.workspaceSettingsFor('/workspace') },
  );
  await expect(launchMode).toHaveText('Worktree');

  const submodules = page.getByRole('button', { name: 'Submodules in worktrees' });
  await submodules.click();
  await page.getByRole('option', { name: 'Initialize', exact: true }).click();
  await expect.poll(() => app.requests.find(request =>
    request.method === 'workspace.settings_set' &&
    request.params?.checkout_submodules === true)).toBeTruthy();
  await expect.poll(() => app.workspaceSettingsFor('/workspace').checkout_submodules).toBe(true);
  app.notify(
    'workspace.settings_changed',
    { ...app.workspaceSettingsFor('/workspace') },
  );

  const timeout = page.getByRole('button', { name: 'Submodule checkout timeout' });
  await timeout.click();
  await page.getByRole('option', { name: '60 seconds' }).click();
  await expect.poll(() => app.requests.find(request =>
    request.method === 'workspace.settings_set' &&
    request.params?.submodule_checkout_timeout_seconds === 60)).toBeTruthy();
  await expect.poll(() =>
    app.workspaceSettingsFor('/workspace').submodule_checkout_timeout_seconds,
  ).toBe(60);
  app.notify(
    'workspace.settings_changed',
    { ...app.workspaceSettingsFor('/workspace') },
  );

  // Close and re-enter: the dialog keeps the committed values.
  await page.getByRole('button', { name: 'Close workspace settings' }).click();
  await page.locator('.workspace-row', { hasText: 'workspace' }).hover();
  await page.getByRole('button', { name: 'Workspace actions', exact: true }).click();
  await page.getByRole('menuitem', { name: 'Workspace settings' }).click();
  await expect(page.getByRole('button', { name: 'New chats' })).toHaveText('Worktree');
  await expect(page.getByRole('button', { name: 'Submodules in worktrees' })).toHaveText('Initialize');
  await expect(page.getByRole('button', { name: 'Submodule checkout timeout' })).toHaveText('60 seconds');
  // Settings are stored per workspace: committing this workspace's values
  // never writes to a sibling project.
  expect(app.requests.filter(request => request.method === 'workspace.settings_set' && request.params?.workspace === '/other')).toEqual([]);

  // Detaching the workspace closes the dialog and its select menu. Reopening
  // starts with closed selects, so the first trigger click opens the menu.
  const reentered = page.getByRole('button', { name: 'New chats' });
  await reentered.click();
  await expect(reentered).toHaveAttribute('aria-expanded', 'true');
  app.notify('workspace.changed', { workspaces: [] });
  await expect(page.getByRole('button', { name: 'New chats' })).toHaveCount(0);
  app.notify('workspace.changed', { workspaces: ['/workspace'] });
  await page.locator('.workspace-row', { hasText: 'workspace' }).hover();
  await page.getByRole('button', { name: 'Workspace actions', exact: true }).click();
  await page.getByRole('menuitem', { name: 'Workspace settings' }).click();
  const reopened = page.getByRole('button', { name: 'New chats' });
  await expect(reopened).toHaveAttribute('aria-expanded', 'false');
  await reopened.click();
  await expect(reopened).toHaveAttribute('aria-expanded', 'true');

  expect(app.pageErrors).toEqual([]);
});

{
  const modifier = 'Meta';

  test('font size shortcuts clamp and persist', async ({ page }) => {
    await page.addInitScript(() => {
      Object.defineProperty(navigator, 'platform', { get: () => 'MacIntel' });
      Object.defineProperty(navigator, 'userAgentData', { get: () => undefined });
    });
    const app = new DesktopBrowserHarness(page);
    await app.install();
    await app.goto();
    await page.getByRole('button', { name: 'Settings', exact: true }).click();
    const slider = page.getByRole('slider', { name: 'Font size' });
    await slider.focus();
    await page.keyboard.press(`${modifier}+Equal`);
    await expect(slider).toHaveValue('15');
    await page.keyboard.press(`${modifier}+Shift+Equal`);
    await expect(slider).toHaveValue('16');
    await page.keyboard.press(`${modifier}+Minus`);
    await expect(slider).toHaveValue('15');
    await page.keyboard.press(`${modifier}+Alt+Equal`);
    await expect(slider).toHaveValue('15');
    // Capture must prevent the browser's zoom even for held-key repeats.
    const prevented = await slider.evaluate((element, modifier) => {
      const event = new KeyboardEvent('keydown', {
        key: '+', code: 'Equal', shiftKey: true,
        metaKey: modifier === 'Meta', ctrlKey: modifier === 'Control',
        repeat: true, bubbles: true, cancelable: true,
      });
      element.dispatchEvent(event);
      return event.defaultPrevented;
    }, modifier);
    expect(prevented).toBe(true);
    await expect(slider).toHaveValue('16');
    for (let i = 0; i < 5; i++) await page.keyboard.press(`${modifier}+Equal`);
    await expect(slider).toHaveValue('18');
    for (let i = 0; i < 9; i++) await page.keyboard.press(`${modifier}+Minus`);
    await expect(slider).toHaveValue('12');
    await expect(page.locator('body')).toHaveCSS('font-size', '12px');
    await page.reload();
    await expect(page.locator('body')).toHaveCSS('font-size', '12px');
    expect(app.pageErrors).toEqual([]);
  });
}

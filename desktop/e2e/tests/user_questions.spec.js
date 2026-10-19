import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

function setup(page, questions = [
  { id: 'approach', title: 'Which approach should we use?', options: ['Small change', 'Full redesign'] },
  { id: 'details', title: 'Any details?\n<script>plain text</script>' },
]) {
  const app = new DesktopBrowserHarness(page);
  let generation = 1;
  let requests = [{
    id: 'question-1', session: 'session-1', questions,
  }, {
    id: 'question-2', session: 'session-1', questions: [{ id: 'extra', title: 'Anything else?' }],
  }];
  const snapshot = () => ({ generation, requests });
  const replyFor = app.replyFor.bind(app);
  app.replyFor = request => {
    if (request.method === 'user_questions.list') return snapshot();
    if (request.method === 'user_questions.answer') {
      expect(request.params.session).toBe('session-1');
      requests = requests.filter(item => item.id !== request.params.id);
      generation++;
      app.notify('user_questions.changed', snapshot());
      return snapshot();
    }
    return replyFor(request);
  };
  return { app, snapshot };
}

test('choosing an option advances to the next question and retains the answer', async ({ page }) => {
  const { app } = setup(page);
  await app.install();
  await app.goto();
  await app.openSession();
  const card = page.locator('.user-question-card');
  await card.getByRole('button', { name: 'Small change', exact: true }).click();
  await expect(card.locator('.user-question-progress')).toHaveText('2 / 2');
  expect(app.requests.filter(r => r.method === 'user_questions.answer')).toHaveLength(0);
  await card.getByRole('button', { name: 'Previous question', exact: true }).click();
  await expect(card.getByRole('button', { name: 'Small change', exact: true })).toHaveAttribute('aria-pressed', 'true');
  await card.getByRole('button', { name: 'Small change', exact: true }).press('Enter');
  await expect(card.locator('.user-question-progress')).toHaveText('2 / 2');
  await card.locator('textarea').fill('Keep keyboard support.');
  await card.getByRole('button', { name: 'Send', exact: true }).click();
  await expect(card).toContainText('Anything else?');
  expect(app.requests.filter(r => r.method === 'user_questions.answer').map(r => r.params.answers)).toEqual([
    { approach: 'Small change', details: 'Keep keyboard support.' },
  ]);
  expect(app.pageErrors).toEqual([]);
});

test('choosing a final option waits for Send', async ({ page }) => {
  const { app } = setup(page, [
    { id: 'approach', title: 'Which approach should we use?', options: ['Small change', 'Full redesign'] },
    { id: 'scope', title: 'Which scope?', options: ['Keep scope', 'Expand scope'] },
  ]);
  await app.install();
  await app.goto();
  await app.openSession();
  const card = page.locator('.user-question-card');
  await card.getByRole('button', { name: 'Small change', exact: true }).click();
  await expect(card.locator('.user-question-progress')).toHaveText('2 / 2');
  await card.getByRole('button', { name: 'Keep scope', exact: true }).click();
  await expect(card.locator('.user-question-progress')).toHaveText('2 / 2');
  await expect(card.getByRole('button', { name: 'Keep scope', exact: true })).toHaveAttribute('aria-pressed', 'true');
  await expect(card.getByRole('button', { name: 'Send', exact: true })).toBeEnabled();
  expect(app.requests.filter(r => r.method === 'user_questions.answer')).toHaveLength(0);
  await card.getByRole('button', { name: 'Send', exact: true }).click();
  await expect(card).toContainText('Anything else?');
  expect(app.requests.filter(r => r.method === 'user_questions.answer').map(r => r.params.answers)).toEqual([
    { approach: 'Small change', scope: 'Keep scope' },
  ]);
  expect(app.pageErrors).toEqual([]);
});

test('custom answer Enter advances questions and submits the final answer', async ({ page }) => {
  const { app } = setup(page);
  await app.install();
  await app.goto();
  await app.openSession();
  const card = page.locator('.user-question-card');
  const input = card.locator('textarea');
  await input.fill('A custom approach');
  await expect(card.getByRole('button', { name: 'Next', exact: true })).toBeEnabled();
  await input.press('Enter');
  await expect(card.locator('.user-question-progress')).toHaveText('2 / 2');
  await expect(input).toBeFocused();
  expect(app.requests.filter(r => r.method === 'user_questions.answer')).toHaveLength(0);
  await input.fill('Keep keyboard support.');
  await expect(card.getByRole('button', { name: 'Send', exact: true })).toBeEnabled();
  await input.press('Enter');
  await expect(card).toContainText('Anything else?');
  await input.fill('One more detail');
  await expect(card.getByRole('button', { name: 'Send', exact: true })).toBeEnabled();
  await input.press('Enter');
  await expect(card).toHaveCount(0);
  expect(app.requests.filter(r => r.method === 'user_questions.answer').map(r => r.params)).toEqual([
    { id: 'question-1', session: 'session-1', answers: { approach: 'A custom approach', details: 'Keep keyboard support.' } },
    { id: 'question-2', session: 'session-1', answers: { extra: 'One more detail' } },
  ]);
  expect(app.pageErrors).toEqual([]);
});

test('custom answer Shift+Enter inserts a line and IME Enter keeps the current question', async ({ page }) => {
  const { app } = setup(page);
  await app.install();
  await app.goto();
  await app.openSession();
  const card = page.locator('.user-question-card');
  const input = card.locator('textarea');
  await input.fill('First line');
  await expect(card.getByRole('button', { name: 'Next', exact: true })).toBeEnabled();
  await input.press('End');
  await input.press('Shift+Enter');
  await input.press('x');
  await expect(input).toHaveValue('First line\nx');
  await expect(card.locator('.user-question-progress')).toHaveText('1 / 2');
  for (const progress of ['1 / 2', '2 / 2']) {
    await expect(card.getByRole('button', { name: progress === '1 / 2' ? 'Next' : 'Send', exact: true })).toBeEnabled();
    await input.dispatchEvent('keydown', { key: 'Enter', code: 'Enter', isComposing: true });
    await expect(card.locator('.user-question-progress')).toHaveText(progress);
    expect(app.requests.filter(r => r.method === 'user_questions.answer')).toHaveLength(0);
    if (progress === '1 / 2') {
      await expect(input).toHaveValue('First line\nx');
      await input.press('Enter');
      await expect(card.locator('.user-question-progress')).toHaveText('2 / 2');
      await input.fill('Final detail');
    }
  }
  await input.press('Enter');
  await expect(card).toContainText('Anything else?');
  expect(app.requests.filter(r => r.method === 'user_questions.answer').map(r => r.params.answers)).toEqual([
    { approach: 'First line\nx', details: 'Final detail' },
  ]);
  expect(app.pageErrors).toEqual([]);
});

test('custom answer Enter leaves empty questions pending', async ({ page }) => {
  const { app } = setup(page);
  await app.install();
  await app.goto();
  await app.openSession();
  const card = page.locator('.user-question-card');
  const input = card.locator('textarea');
  await input.fill('   ');
  await expect(card.getByRole('button', { name: 'Next', exact: true })).toBeDisabled();
  await input.press('Enter');
  await expect(card.locator('.user-question-progress')).toHaveText('1 / 2');
  await expect(input).toHaveValue('   ');
  await expect(card.getByRole('button', { name: 'Next', exact: true })).toBeDisabled();
  await input.fill('A custom approach');
  await expect(card.getByRole('button', { name: 'Next', exact: true })).toBeEnabled();
  await input.press('Enter');
  await expect(card.locator('.user-question-progress')).toHaveText('2 / 2');
  await expect(card.getByRole('button', { name: 'Send', exact: true })).toBeDisabled();
  await input.press('Enter');
  await expect(input).toHaveValue('');
  await expect(card.getByRole('button', { name: 'Send', exact: true })).toBeDisabled();
  expect(app.requests.filter(r => r.method === 'user_questions.answer')).toHaveLength(0);
  expect(app.pageErrors).toEqual([]);
});

test('live questions occupy visible space between the transcript and composer', { tag: '@webkit-layout' }, async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  app.notify('user_questions.changed', { generation: 1, requests: [{
    id: 'live-question', session: 'session-1', questions: [{
      id: 'approach', title: 'Which approach should we use?', options: ['Small change', 'Full redesign'],
    }],
  }] });
  const card = page.locator('.user-question-card');
  await expect(card).toContainText('Which approach should we use?');
  const region = page.locator('.user-question-region');
  await expect.poll(() => region.evaluate(el => el.clientHeight)).toBeGreaterThan(0);
  await expect(card).toBeInViewport({ ratio: 1 });
  const regionBox = await region.boundingBox();
  const transcriptBox = await page.locator('.transcript').boundingBox();
  const composerBox = await page.locator('.composer').boundingBox();
  expect(regionBox.y).toBeGreaterThanOrEqual(transcriptBox.y + transcriptBox.height - 1);
  expect(regionBox.y + regionBox.height).toBeLessThanOrEqual(composerBox.y + 1);
  await card.getByRole('button', { name: 'Small change', exact: true }).click();
  await expect(card.getByRole('button', { name: 'Send', exact: true })).toBeEnabled();
  expect(app.requests.filter(r => r.method === 'user_questions.answer')).toHaveLength(0);
  await page.screenshot({ path: testInfo.outputPath('live-question.png'), animations: 'disabled' });
  app.notify('user_questions.changed', { generation: 2, requests: [{
    id: 'long-question', session: 'session-1', questions: [{
      id: 'many', title: 'Choose an option', options: Array.from({ length: 30 }, (_, i) => `Option ${i + 1}`),
    }],
  }] });
  await expect(card).toContainText('Choose an option');
  expect(await region.evaluate(el => el.clientHeight)).toBeLessThanOrEqual(page.viewportSize().height / 2);
  expect(await region.evaluate(el => el.scrollHeight > el.clientHeight)).toBe(true);
  await card.getByRole('button', { name: 'Option 30', exact: true }).click();
  await expect(card.getByRole('button', { name: 'Option 30', exact: true })).toHaveAttribute('aria-pressed', 'true');
  app.notify('user_questions.changed', { generation: 3, requests: [] });
  await expect(region).toBeHidden();
  expect(app.pageErrors).toEqual([]);
});

test('questions survive reload and a finished turn, accept choices and text, and queue independently of approvals', async ({ page }, testInfo) => {
  const { app, snapshot } = setup(page);
  await app.install();
  await app.goto();
  await app.openSession();
  const card = page.locator('.user-question-card');
  await expect(card).toContainText('Which approach should we use?');
  await expect(card.locator('script')).toHaveCount(0);
  await expect(card.getByRole('button', { name: 'Next', exact: true })).toBeDisabled();
  await page.reload();
  await app.openSession();
  await expect(card).toContainText('Which approach should we use?');
  await page.locator('#task').fill('Continue independent work');
  await page.locator('#send').click();
  app.notify('agent.event', { session: 'session-1', run_id: 'run-e2e', event: { event: 'agent_finished', answer: 'Done' } });
  app.notify('agent.finished', { run_id: 'run-e2e', status: 'finished', answer: 'Done' });
  await expect(card).toBeVisible();
  app.notify('agent.approvals', { generation: 1, approvals: [{
    id: 'message-1', session: 'session-1', run_id: null, tool_name: 'session.send', detail: 'Other chat', body: 'Example message', answered: false,
  }] });
  await expect(page.locator('.composer-approval')).toBeVisible();
  await expect(card).toBeVisible();
  await card.getByRole('button', { name: 'Small change', exact: true }).click();
  await expect(card.locator('textarea')).toHaveValue('');
  await expect(card.locator('.user-question-progress')).toHaveText('2 / 2');
  await card.locator('textarea').fill('Keep keyboard support.\n<literal>');
  // Replayed snapshots must neither steal focus nor erase the draft.
  app.notify('user_questions.changed', snapshot());
  await expect(card.locator('textarea')).toBeFocused();
  await expect(card.locator('textarea')).toHaveValue('Keep keyboard support.\n<literal>');
  const screenshot = testInfo.outputPath('questions-and-approval.png');
  await page.screenshot({ path: screenshot, animations: 'disabled' });
  await testInfo.attach('Independent question and approval cards', { path: screenshot, contentType: 'image/png' });
  await card.getByRole('button', { name: 'Send', exact: true }).click();
  await expect(card).toContainText('Anything else?');
  await card.locator('.user-question-close').click();
  await expect(card).toHaveCount(0);
  await expect(page.locator('.composer-approval')).toBeVisible();
  expect(app.requests.filter(r => r.method === 'user_questions.answer').map(r => r.params)).toEqual([
    { id: 'question-1', session: 'session-1', answers: { approach: 'Small change', details: 'Keep keyboard support.\n<literal>' } },
    { id: 'question-2', session: 'session-1', answers: null },
  ]);
  expect(app.requests.some(r => r.method === 'agent.approval')).toBe(false);
  expect(app.pageErrors).toEqual([]);
});

test('failed answers retain text for retry, and a newer resolution beats stale snapshots', async ({ page }) => {
  const { app, snapshot } = setup(page);
  await app.install();
  await app.goto();
  await app.openSession();
  const card = page.locator('.user-question-card');
  await card.locator('textarea').first().fill('A custom approach');
  await card.getByRole('button', { name: 'Next', exact: true }).click();
  await expect(card.locator('.user-question-progress')).toHaveText('2 / 2');
  await card.locator('textarea').fill('Details');
  app.rpcErrors.set('user_questions.answer', 'Temporary failure');
  await card.getByRole('button', { name: 'Send', exact: true }).click();
  await expect(card.locator('.user-question-error')).toContainText('Temporary failure');
  await card.getByRole('button', { name: 'Previous question', exact: true }).click();
  await expect(card.locator('textarea')).toHaveValue('A custom approach');
  await card.getByRole('button', { name: 'Next', exact: true }).click();
  await expect(card.getByRole('button', { name: 'Send', exact: true })).toBeEnabled();
  // A second client answers while this client's error is visible.
  const stale = snapshot();
  app.notify('user_questions.changed', { generation: 3, requests: [] });
  await expect(card).toHaveCount(0);
  app.notify('user_questions.changed', stale);
  await expect(card).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('question drafts are scoped to the originating conversation and fit a narrow viewport', { tag: '@webkit-layout' }, async ({ page }, testInfo) => {
  const { app } = setup(page);
  app.liveSessions.push({ id: 'session-2', title: 'Another conversation', updated_at_ms: 2 });
  const reply = app.replyFor.bind(app);
  app.replyFor = request => {
    const result = reply(request);
    if (request.method === 'session.load') result.session.id = request.params.session;
    return result;
  };
  await app.install();
  await app.goto();
  await app.openSession();
  const card = page.locator('.user-question-card');
  await card.locator('textarea').first().fill('Keep this draft');
  await page.locator('.conversation-row[title="session-2"]').click();
  await expect(card).toHaveCount(0);
  await page.locator('.conversation-row[title="session-1"]').click();
  await expect(card.locator('textarea').first()).toHaveValue('Keep this draft');
  await page.getByRole('button', { name: 'Hide sidebar', exact: true }).click();
  await page.setViewportSize({ width: 390, height: 844 });
  await expect(page.locator('.app')).toHaveClass(/sidebar-collapsed/);
  await expect(card).toBeVisible();
  const box = await card.boundingBox();
  expect(box.x).toBeGreaterThanOrEqual(0);
  expect(box.x + box.width).toBeLessThanOrEqual(390);
  const screenshot = testInfo.outputPath('questions-narrow.png');
  await page.screenshot({ path: screenshot, animations: 'disabled' });
  await testInfo.attach('Questions on a narrow viewport', { path: screenshot, contentType: 'image/png' });
  expect(app.pageErrors).toEqual([]);
});

{
  const width = 390;

  test(`XML question responses render answers and skips live and after reload at ${width}px`, async ({ page }, testInfo) => {
    const app = new DesktopBrowserHarness(page);
    const answered = '<user_question_response request_id="question-1" status="answered">\n'
      + '<question id="plan">\n<title>Which plan?</title>\n<options>\n<option>Small change</option>\n<option>Full redesign</option>\n</options>\n<answer>Small change</answer>\n</question>\n'
      + '<question id="details">\n<title>Any details?&#10;中文🙂</title>\n<answer>Keep keyboard support.&#10;&lt;script&gt;plain text&lt;/script&gt; &amp; &amp;lt;/answer&amp;gt;</answer>\n</question>\n'
      + '</user_question_response>';
    const skipped = '<user_question_response request_id="question-2" status="skipped">\n'
      + '<question id="extra">\n<title>Anything else?</title>\n</question>\n</user_question_response>';
    const event = (sequence, content) => ({ sequence, item: { kind: 'user', payload: { content } } });
    app.sessionEvents = [event(1, answered)];
    await app.install();
    await app.goto();
    await page.getByRole('button', { name: 'Rabbita browser fixture', exact: true }).click();
    await page.getByRole('button', { name: 'Hide sidebar', exact: true }).click();
    await page.setViewportSize({ width, height: 900 });
    const responses = page.locator('.transcript-question-response');
    await expect(responses).toHaveCount(1);
    const next = event(2, skipped);
    app.sessionEvents.push(next);
    app.notify('session.event', { session: 'session-1', session_root: '/workspace/.openseek', sequence: 2, event: next });
    for (const reload of [false, true]) {
      if (reload) {
        await page.setViewportSize({ width: 1440, height: 900 });
        await page.reload();
        await page.getByRole('main').waitFor();
        const showSidebar = page.getByRole('button', { name: 'Show sidebar', exact: true });
        if (await showSidebar.isVisible()) await showSidebar.click();
        await page.getByRole('button', { name: 'Rabbita browser fixture', exact: true }).click();
        await page.getByRole('button', { name: 'Hide sidebar', exact: true }).click();
        await page.setViewportSize({ width, height: 900 });
      }
      await expect(responses).toHaveCount(2);
      await expect(page.locator('.app')).toHaveClass(/sidebar-collapsed/);
      await expect(page.locator('.app > aside')).toHaveCSS('visibility', 'hidden');
      const items = responses.first().locator('.question-response-item');
      const first = await items.nth(0).boundingBox();
      const second = await items.nth(1).boundingBox();
      expect(second.y).toBeGreaterThanOrEqual(first.y + first.height);
      await expect(responses.first().locator('.session-message-source')).toHaveText('Your answers');
      await expect(responses.first().locator('.question-response-title')).toHaveText(['Which plan?', 'Any details?\n中文🙂']);
      await expect(responses.first().locator('.msg-content')).toHaveText(['Small change', 'Keep keyboard support.\n<script>plain text</script> & &lt;/answer&gt;']);
      await expect(responses.first()).not.toContainText('Full redesign');
      await expect(responses.last()).toHaveText('Questions skipped');
      await expect(page.locator('#stream')).not.toContainText('user_question_response');
      await expect(page.locator('#stream')).not.toContainText('User response to ask_user:');
      await expect(responses.locator('script')).toHaveCount(0);
      for (const response of await responses.all()) {
        await expect.poll(() => response.evaluate(el => el.scrollWidth <= el.clientWidth + 1)).toBe(true);
      }
    }
    const screenshot = testInfo.outputPath(`question-responses-${width}.png`);
    await page.locator('#stream').screenshot({ path: screenshot, animations: 'disabled' });
    await testInfo.attach('Formatted question responses', { path: screenshot, contentType: 'image/png' });
    expect(app.pageErrors).toEqual([]);
  });
}

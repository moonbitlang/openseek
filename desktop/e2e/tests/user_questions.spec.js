import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

function setup(page) {
  const app = new DesktopBrowserHarness(page);
  let generation = 1;
  let requests = [{
    id: 'question-1', session: 'session-1', questions: [
      { id: 'approach', title: 'Which approach should we use?', options: ['Small change', 'Full redesign'] },
      { id: 'details', title: 'Any details?\n<script>plain text</script>' },
    ],
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

test('questions survive reload and a finished turn, accept choices and text, and queue independently of approvals', async ({ page }, testInfo) => {
  const { app, snapshot } = setup(page);
  await app.install();
  await app.goto();
  await app.openSession();
  const card = page.locator('.user-question-card');
  await expect(card).toContainText('Which approach should we use?');
  await expect(card.locator('script')).toHaveCount(0);
  await expect(card.getByRole('button', { name: 'Next', exact: true })).toBeDisabled();
  await expect(card).not.toContainText(/countdown|seconds|30s/i);
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
  await card.getByRole('button', { name: 'Next', exact: true }).click();
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

test('question drafts are scoped to the originating conversation and fit a narrow viewport', async ({ page }, testInfo) => {
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


test('reference card presents numbered choices above the reply row and closes by skipping', async ({ page }, testInfo) => {
  const { app } = setup(page);
  await app.install();
  await app.goto();
  await app.openSession();
  app.notify('user_questions.changed', { generation: 2, requests: [{
    id: 'question-1', session: 'session-1', questions: [{
      id: 'folders',
      title: '浏览器端的「添加文件夹」怎么处理？桌面端仍可只引用本机目录路径；浏览器端若要让宿主读取客户端目录，需要上传内容。',
      options: ['浏览器暂时隐藏「添加文件夹」，保留客户端文件或照片上传', '浏览器也允许选择客户端文件夹，并上传其内容'],
    }],
  }] });
  const card = page.locator('.user-question-card');
  await expect(card).toContainText('浏览器端的「添加文件夹」');
  await expect(card.locator('.user-question-number')).toHaveText(['1', '2']);
  await expect(card.locator('.user-question-submit')).toBeDisabled();
  const optionsBox = await card.locator('.user-question-options').boundingBox();
  const responseBox = await card.locator('.user-question-response').boundingBox();
  expect(responseBox.y).toBeGreaterThan(optionsBox.y + optionsBox.height);
  const option = card.locator('.user-question-option').first();
  await option.focus();
  await page.keyboard.press('Enter');
  await expect(option).toHaveAttribute('aria-pressed', 'true');
  await expect(card.locator('textarea')).toHaveValue('');
  await expect(card.locator('.user-question-submit')).toBeEnabled();
  const screenshot = testInfo.outputPath('question-reference.png');
  await card.screenshot({ path: screenshot, animations: 'disabled' });
  await testInfo.attach('Selected question option', { path: screenshot, contentType: 'image/png' });
  await card.locator('textarea').fill('Use a custom folder flow');
  await expect(option).toHaveAttribute('aria-pressed', 'false');
  await card.locator('.user-question-close').click();
  expect(app.requests.filter(r => r.method === 'user_questions.answer').at(-1).params.answers).toBeNull();
  expect(app.pageErrors).toEqual([]);
});


test('six questions page independently, retain drafts, and send all answers once', async ({ page }, testInfo) => {
  const { app } = setup(page);
  await app.install(); await app.goto(); await app.openSession();
  app.notify('user_questions.changed', { generation: 2, requests: [{
    id: 'question-1', session: 'session-1', questions: Array.from({length:6}, (_, i) => ({
      id: 'q' + i, title: 'Question ' + (i + 1), options: ['Choice A', 'Choice B'],
    })),
  }] });
  const card = page.locator('.user-question-card');
  await expect(card.locator('.user-question-progress')).toHaveText('1 / 6');
  await expect(card.locator('.user-question-field')).toHaveCount(1);
  await expect(card.locator('.user-question-previous')).toBeDisabled();
  await expect(card.locator('.user-question-skip')).toHaveCount(0);
  const answers = {};
  for (let i=0; i<6; i++) {
    await expect(card.locator('.user-question-progress')).toHaveText((i + 1) + ' / 6');
    await expect(card.locator('.user-question-submit')).toBeDisabled();
    await card.getByRole('button', {name:'Choice A',exact:true}).click();
    await expect(card.locator('textarea')).toHaveValue('');
    if (i === 0) {
      const screenshot = testInfo.outputPath('six-questions.png');
      await card.screenshot({ path: screenshot, animations: 'disabled' });
      await testInfo.attach('Multiple questions with a selected answer', { path: screenshot, contentType: 'image/png' });
    }
    if (i===1) {
      await card.locator('textarea').fill('Custom answer');
      await expect(card.getByRole('button', {name:'Choice A',exact:true})).toHaveAttribute('aria-pressed','false');
      await card.locator('.user-question-previous').click();
      await expect(card.getByRole('button', {name:'Choice A',exact:true})).toHaveAttribute('aria-pressed','true');
      await card.locator('.user-question-next').click();
      await expect(card.locator('textarea')).toHaveValue('Custom answer');
    }
    answers['q'+i] = i===1 ? 'Custom answer' : 'Choice A';
    if (i<5) await card.getByRole('button',{name:'Next',exact:true}).click();
  }
  await expect(card.locator('.user-question-next')).toBeDisabled();
  expect(app.requests.filter(r=>r.method==='user_questions.answer')).toHaveLength(0);
  await card.getByRole('button',{name:'Send',exact:true}).click();
  await expect(card).toContainText('Anything else?');
  expect(app.requests.filter(r=>r.method==='user_questions.answer').map(r=>r.params.answers)).toEqual([answers]);
  expect(app.pageErrors).toEqual([]);
});

for (const theme of ['light', 'dark']) {
  test(`question controls follow ${theme} appearance and font settings without clipping`, async ({ page }, testInfo) => {
    await page.addInitScript(theme => localStorage.setItem('openseek.theme', theme), theme);
    const { app } = setup(page);
    await app.install();
    await app.goto();
    for (const font of [12, 18]) {
      await page.setViewportSize({ width: 1440, height: 900 });
      await page.getByRole('button', { name: 'Settings', exact: true }).click();
      await page.getByRole('slider', { name: 'Font size', exact: true }).fill(String(font));
      await page.reload();
      await app.openSession();
      await expect(page.locator('html')).toHaveAttribute('data-theme', theme);
      const card = page.locator('.user-question-card');
      const input = card.locator('textarea');
      await card.getByRole('button', { name: 'Small change', exact: true }).click();
      for (const width of [1440, 390]) {
        await page.setViewportSize({ width, height: 900 });
        await expect(input).toHaveCSS('font-size', `${width === 390 ? Math.max(16, font) : font}px`);
        await input.focus();
        await expect(input).toHaveCSS('outline-style', 'none');
        await expect(card.locator('.user-question-input')).toHaveCSS('outline-style', 'none');
        await expect.poll(() => card.evaluate(el => el.scrollWidth <= el.clientWidth + 1)).toBe(true);
        const digit = card.locator('.user-question-number').first();
        const digitBox = await digit.boundingBox();
        expect(digitBox.height).toBeGreaterThanOrEqual(await digit.evaluate(el => parseFloat(getComputedStyle(el).lineHeight)));
        await input.press('Tab');
        const next = card.getByRole('button', { name: 'Next', exact: true });
        await expect(next).toBeFocused();
        await expect(next).toHaveCSS('outline-style', 'solid');
        const screenshot = testInfo.outputPath(`question-${theme}-${font}-${width}.png`);
        await card.screenshot({ path: screenshot, animations: 'disabled' });
      }
    }
    expect(app.pageErrors).toEqual([]);
  });
}

for (const width of [1440, 390]) {
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

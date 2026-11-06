import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('approval disclosure preserves draft focus and actions', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.hostSettings.followup_behavior = 'queue';
  await app.install();
  await app.goto();
  await app.openSession();
  const composer = page.locator('#task');
  await composer.fill('Start a turn');
  await page.locator('#send').click();
  for (const text of ['Check the parser tests', 'Review the API changes']) {
    await composer.fill(text);
    await composer.press('Enter');
    const id = app.requests.filter(r => r.method === 'agent.queue').at(-1).params.id;
    await expect(page.locator(`[data-queued-input-id=${JSON.stringify(id)}]`)).toContainText(text);
  }
  const notify = event => app.notify('agent.event', { session: 'session-1', run_id: 'run-e2e', event });
  notify({ event: 'subrun_started', id: 'review-1', kind: 'review', label: 'Review API changes' });
  const content = '///|\nfn main {\n  println("<script>你好</script>")\n}\n';
  app.notify('agent.approvals', { generation: 1, approvals: [{
    session: 'session-1', run_id: 'run-e2e', answered: false,
    id: 'approval-context', tool_name: 'write',
    detail: '/workspace/src/parser.mbt (overwrite existing source file)',
    body: JSON.stringify({ path: '/workspace/src/parser.mbt', content }, null, 2) }] });
  const approval = page.locator('.composer-approval');
  await expect(approval).toBeVisible();
  await expect(approval.locator('summary')).toContainText('write /workspace/src/parser.mbt (overwrite existing source file)');
  const source = approval.locator('.composer-approval-body');
  await expect(source).toBeVisible();
  expect(await source.textContent()).toBe(content);
  await expect(source.locator('script')).toHaveCount(0);
  await expect(source.locator('.mtk3').filter({ hasText: /^fn$/ })).toBeVisible();
  await expect(source.locator('.mtk5')).toHaveText('"<script>你好</script>"');
  expect(await source.locator('.mtk3').first().evaluate(el => getComputedStyle(el).color))
    .not.toBe(await source.locator('.mtk5').first().evaluate(el => getComputedStyle(el).color));
  await approval.locator('summary').click();
  await composer.fill('Draft while collapsed');
  await expect(approval.locator('.composer-approval-body')).toBeHidden();
  await approval.locator('summary').click();
  await expect(approval.locator('.composer-approval-body')).toBeVisible();
  await composer.fill('Keep this draft');
  await expect(composer).toBeFocused();
  // An unrelated composer update must preserve the browser-owned disclosure.
  await expect(approval).toHaveAttribute('open', '');
  await approval.locator('summary').focus();
  await page.keyboard.press('Enter');
  await expect(approval.locator('.composer-approval-body')).toBeHidden();
  await approval.getByTestId('approval-allow').click();
  await expect.poll(() => app.requests.find(r => r.method === 'agent.approval')?.params.allow).toBe(true);
  await expect(composer).toHaveValue('Keep this draft');
  expect(app.pageErrors).toEqual([]);
});

test('replayed write approvals decode content and preserve unrecognized bodies', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  const content = 'fn main {\n  println("recovered")\n}\n';
  const replyFor = app.replyFor.bind(app);
  app.replyFor = request => request.method === 'agent.runs' ? {
    runs: [{ run_id: 'run-e2e', session: 'session-1', model: 'deepseek-flash', max_steps: 1000 }],
    settled: [], approval_generation: 1,
    approvals: [{ answered: false, id: 'approval-replay', session: 'session-1', run_id: 'run-e2e',
      tool_name: 'write', detail: '/workspace/src/parser.mbt (overwrite existing source file)',
      body: JSON.stringify({ path: '/workspace/src/parser.mbt', content }) }],
  } : replyFor(request);
  await app.install();
  await app.goto();
  await app.openSession();
  const approval = page.locator('.composer-approval');
  const source = approval.locator('.composer-approval-body');
  await expect(source).toBeVisible();
  expect(await source.textContent()).toBe(content);
  let generation = 1;
  for (const [tool_name, body, expected] of [
    ['write', '{"content":""}', ''],
    ['write', '{"content":null}', '{"content":null}'],
    ['write', 'malformed {', 'malformed {'],
    ['mbtx', content, content],
  ]) {
    app.notify('agent.approvals', { generation: ++generation, approvals: [{
      session: 'session-1', run_id: 'run-e2e', answered: false, id: 'approval-fallback', tool_name,
      detail: 'Inspect operation', body,
    }] });
    await expect.poll(() => source.textContent()).toBe(expected);
  }
  expect(app.pageErrors).toEqual([]);
});

for (const [name, content, allow] of [
  ['many short lines', 'x\n'.repeat(10_000) + '<script>你好</script>\n', false],
  ['one long line', 'x '.repeat(20_000) + '<script>你好</script>', true],
]) {
  test(`large write approval preserves ${name} without token nodes`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    await app.install();
    await app.goto();
    await app.openSession();
    await page.locator('#task').fill('Start a turn');
    await page.locator('#send').click();
    app.notify('agent.approvals', { generation: 1, approvals: [{
      session: 'session-1', run_id: 'run-e2e', answered: false, id: 'approval-large', tool_name: 'write',
      detail: '/workspace/generated.mbt (overwrite existing source file)',
      body: JSON.stringify({ path: '/workspace/generated.mbt', content }),
    }] });
    const approval = page.locator('.composer-approval');
    const source = approval.locator('.composer-approval-body');
    await expect(source).toBeVisible();
    expect(await source.textContent()).toBe(content);
    expect(await source.locator('code').evaluate(el => ({
      elements: el.childElementCount, nodes: el.childNodes.length,
    }))).toEqual({ elements: 0, nodes: 1 });
    await page.locator('#task').fill('Draft while inspecting large content');
    expect(await source.textContent()).toBe(content);
    await approval.getByTestId(allow ? 'approval-allow' : 'approval-deny').click();
    await expect.poll(() => app.requests.find(r => r.method === 'agent.approval')?.params.allow).toBe(allow);
    expect(app.pageErrors).toEqual([]);
  });
}

test('Codex shares the question card while approvals retain their disclosure', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.codexModels = [{ id: 'gpt-5.4-codex', displayName: 'GPT-5.4 Codex', isDefault: true,
    defaultReasoningEffort: 'medium', supportedReasoningEfforts: [{ reasoningEffort: 'medium', description: 'Balanced' }] }];
  await app.install();
  await app.goto();
  await page.locator('#openseek-model-picker, #codex-model-picker, #model').click();
  await page.locator('[role=option][data-value="codex:gpt-5.4-codex"]:visible').click();
  await expect(page.locator('#task')).toHaveAttribute('placeholder', /Ask Codex/);
  await expect(page.locator('#task')).toBeEnabled();
  await page.locator('#task').fill('Review this project');
  await page.locator('#send').click();
  await expect.poll(() => app.requests.some(r => r.method === 'codex.turn.start')).toBe(true);
  let generation = 1;
  const request = (id, method, params) => app.notify('codex.server_request', {
    response_token: id, request_id: id, method, generation: ++generation,
    params: { threadId: 'codex-thread-e2e', ...params },
  });
  request('question-1', 'item/tool/requestUserInput', { questions: [{
    id: 'scope', header: 'Scope', question: 'Which tests should run?', options: [
      { label: 'All tests', description: 'Run the complete suite' },
      { label: 'Parser tests', description: 'Run only the parser suite' },
    ],
  }] });
  const question = page.locator('.user-question-card');
  await expect(question).toBeVisible();
  await expect(question.locator('.user-question-option-description').first()).toHaveText('Run the complete suite');
  await question.locator('[data-question-option="All tests"]').click();
  await expect(question.locator('[data-question-option="All tests"]')).toHaveAttribute('aria-pressed', 'true');
  await expect(question.locator('textarea')).toHaveValue('');
  await question.getByTestId('question-submit').click();
  await expect.poll(() => app.requests.find(r => r.method === 'codex.server_request.respond')?.params)
    .toMatchObject({ response_token: 'question-1', result: { answers: { scope: { answers: ['All tests'] } } } });
  request('approval-2', 'item/commandExecution/requestApproval', { command: 'moon test', cwd: '/workspace', reason: 'Run the project tests' });
  const approval = page.locator('.codex-request[data-request-key="approval-2"]');
  await expect(approval).toBeVisible();
  await approval.locator('summary').first().click();
  await expect(approval.locator('.codex-request-command')).toHaveText('moon test');
  await approval.locator('[data-approval-decision="accept"]:visible').click();
  await expect.poll(() => app.requests.filter(r => r.method === 'codex.server_request.respond').length).toBe(2);
  expect(app.pageErrors).toEqual([]);
});

for (const expanded of [false, true]) {
  test(`Codex request retains its ${expanded ? 'expanded' : 'collapsed'} state when an earlier request resolves`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    app.codexModels = [{ id: 'gpt-5.4-codex', displayName: 'GPT-5.4 Codex', isDefault: true,
      defaultReasoningEffort: 'medium', supportedReasoningEfforts: [{ reasoningEffort: 'medium', description: 'Balanced' }] }];
    await app.install();
    await app.goto();
    await page.locator('#openseek-model-picker, #codex-model-picker, #model').click();
    await page.locator('[role=option][data-value="codex:gpt-5.4-codex"]:visible').click();
    await expect(page.locator('#task')).toHaveAttribute('placeholder', /Ask Codex/);
    await expect(page.locator('#task')).toBeEnabled();
    await page.locator('#task').fill('Review this project');
    await page.locator('#send').click();
    await expect.poll(() => app.requests.some(r => r.method === 'codex.turn.start')).toBe(true);
    for (const [index, command] of ['first-command', 'second-command'].entries()) {
      app.notify('codex.server_request', {
        response_token: command, request_id: command, generation: index + 2,
        method: 'item/commandExecution/requestApproval',
        params: { threadId: 'codex-thread-e2e', command, cwd: '/workspace' },
      });
    }
    const first = page.locator('.codex-request[data-request-key="first-command"]');
    const second = page.locator('.codex-request[data-request-key="second-command"]');
    await expect(first).toBeVisible();
    await expect(second).toBeVisible();
    const opened = expanded ? second : first;
    await opened.locator('summary').first().focus();
    await page.keyboard.press('Enter');
    await expect(opened).toHaveAttribute('open', '');
    app.notify('codex.notification', {
      generation: 4, method: 'serverRequest/resolved',
      params: { requestId: 'first-command' },
    });
    await expect(first).toHaveCount(0);
    await expect(second).toHaveCount(1);
    if (expanded) await expect(second).toHaveAttribute('open', '');
    else await expect(second).not.toHaveAttribute('open');
    await second.locator('summary').first().focus();
    await page.keyboard.press('Space');
    if (expanded) await expect(second).not.toHaveAttribute('open');
    else await expect(second).toHaveAttribute('open', '');
    expect(app.pageErrors).toEqual([]);
  });
}

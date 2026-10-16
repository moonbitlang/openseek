import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

async function openCodex(page) {
  const app = new DesktopBrowserHarness(page);
  app.codexModels = [{ id: 'gpt-test', displayName: 'Codex focus', isDefault: true }];
  await app.install();
  await app.goto();
  await page.getByRole('button', { name: 'Model', exact: true }).click();
  await page.getByRole('option', { name: 'Codex focus', exact: true }).click();
  await expect(page.locator('#task')).toHaveAttribute('placeholder', /Ask Codex/);
  await expect(page.locator('#task')).toBeEnabled();
  await page.locator('#task').fill('Review this project');
  await page.getByTitle('Send', { exact: true }).click();
  await expect.poll(() => app.requests.some(r => r.method === 'codex.turn.start')).toBe(true);
  return app;
}

function request(app, token, generation, method, params, id = token) {
  app.notify('codex.server_request', {
    response_token: token, request_id: id, generation, method,
    params: { threadId: 'codex-thread-e2e', ...params },
  });
}

function approval(app, token, generation, id = token) {
  request(app, token, generation, 'item/commandExecution/requestApproval', {
    command: token, cwd: '/workspace', availableDecisions: ['accept', 'decline'],
  }, id);
}

function resolve(app, id, generation) {
  app.notify('codex.notification', {
    generation, method: 'serverRequest/resolved', params: { requestId: id },
  });
}

function card(page, text) {
  return page.locator('.codex-request').filter({ hasText: text });
}

// Parallel exec_command calls can both wait for approval in the same thread.
test('removing an earlier approval preserves keyboard focus and response ownership', async ({ page }, testInfo) => {
  const app = await openCodex(page);
  approval(app, 'first-command', 2);
  approval(app, 'second-command', 3);
  const second = card(page, 'second-command');
  await second.locator(':scope > summary').click();
  const approve = second.getByRole('button', { name: 'Approve once', exact: true });
  await approve.focus();
  const original = await approve.elementHandle();
  await page.locator('.codex-pending').screenshot({ path: testInfo.outputPath('two-approvals-focused.png') });
  resolve(app, 'first-command', 4);
  await expect(card(page, 'first-command')).toHaveCount(0);
  await expect(approve).toBeFocused();
  expect(await approve.evaluate((node, old) => node === old, original)).toBe(true);
  await page.locator('.codex-pending').screenshot({ path: testInfo.outputPath('surviving-approval-focused.png') });
  await page.keyboard.press('Enter');
  await expect.poll(() => app.requests.filter(r => r.method === 'codex.server_request.respond').length).toBe(1);
  expect(app.requests.find(r => r.method === 'codex.server_request.respond').params).toMatchObject({
    request_id: 'second-command', response_token: 'second-command', result: { decision: 'accept' },
  });
  expect(app.pageErrors).toEqual([]);
});

// Renderer fixtures cover both editable request types; this does not assert
// that ordinary request_user_input can run alongside a blocked exec_command.
for (const kind of ['question', 'mcp-form']) {
  test(`${kind} retains its input node, selection and draft when a sibling resolves`, async ({ page }, testInfo) => {
    const app = await openCodex(page);
    approval(app, 'first-command', 2);
    if (kind === 'question') {
      request(app, 'editable', 3, 'item/tool/requestUserInput', {
        questions: [{ id: 'scope', header: 'Scope', question: 'Which files?' }],
      });
    } else {
      request(app, 'editable', 3, 'mcpServer/elicitation/request', {
        serverName: 'demo', mode: 'form', message: 'Choose files',
        requestedSchema: { type: 'object', properties: { scope: { type: 'string' } } },
      });
    }
    if (kind === 'mcp-form') {
      await page.locator('.codex-request').filter({ hasText: 'Choose files' }).locator(':scope > summary').click();
    }
    const input = page.locator(kind === 'question' ? '.user-question-answer' : '.codex-request textarea');
    const draft = kind === 'question' ? 'the parser files' : '{"scope":"parser"}';
    await input.fill(draft);
    await input.evaluate(node => node.setSelectionRange(3, 6, 'backward'));
    const original = await input.elementHandle();
    await page.locator('.codex-pending').screenshot({ path: testInfo.outputPath('input-before-removal.png') });
    resolve(app, 'first-command', 4);
    await expect(card(page, 'first-command')).toHaveCount(0);
    await expect(input).toBeFocused();
    await expect(input).toHaveValue(draft);
    expect(await input.evaluate((node, old) => node === old, original)).toBe(true);
    expect(await input.evaluate(node => [node.selectionStart, node.selectionEnd, node.selectionDirection]))
      .toEqual([3, 6, 'backward']);
    await page.locator('.codex-pending').screenshot({ path: testInfo.outputPath('input-after-removal.png') });
    await page.keyboard.insertText('NEW');
    await expect(input).toHaveValue(draft.slice(0, 3) + 'NEW' + draft.slice(6));
    expect(app.pageErrors).toEqual([]);
  });
}

test('reusing a request id with a new response token replaces its DOM node', async ({ page }) => {
  const app = await openCodex(page);
  approval(app, 'old-command', 2, 'reused-id');
  await card(page, 'old-command').locator(':scope > summary').click();
  const old = card(page, 'old-command').getByRole('button', { name: 'Approve once', exact: true });
  await old.focus();
  const original = await old.elementHandle();
  approval(app, 'new-command', 3, 'reused-id');
  await expect(card(page, 'old-command')).toHaveCount(0);
  await expect(card(page, 'new-command')).not.toHaveAttribute('open', '');
  await card(page, 'new-command').locator(':scope > summary').click();
  const replacement = card(page, 'new-command').getByRole('button', { name: 'Approve once', exact: true });
  await expect(replacement).toBeVisible();
  expect(await original.evaluate(node => node.isConnected)).toBe(false);
  await expect(replacement).not.toBeFocused();
  await replacement.click();
  await expect.poll(() => app.requests.filter(r => r.method === 'codex.server_request.respond').length).toBe(1);
  expect(app.requests.find(r => r.method === 'codex.server_request.respond').params.response_token).toBe('new-command');
  expect(app.pageErrors).toEqual([]);
});

test('Codex question pages share selection, custom replies, retry and close behavior', async ({ page }, testInfo) => {
  const app = await openCodex(page);
  request(app, 'questions', 2, 'item/tool/requestUserInput', {
    questions: [
      { id: 'scope', header: 'Scope', question: 'Which approach should we use?', options: [
        { label: 'Small change', description: 'Keep the current layout' },
        { label: 'Full redesign', description: 'Replace the layout' },
      ] },
      { id: 'details', header: 'Details', question: 'Any details?' },
    ],
  });
  const card = page.locator('.user-question-card');
  const option = card.getByRole('button', { name: /Small change/ });
  await expect(card.locator('.user-question-progress')).toHaveText('1 / 2');
  await expect(card.getByRole('button', { name: 'Next', exact: true })).toBeDisabled();
  await option.click();
  await expect(option).toHaveAttribute('aria-pressed', 'true');
  await expect(card.locator('textarea')).toHaveValue('');
  const badge = option.locator('.user-question-number');
  expect(await badge.evaluate(node => getComputedStyle(node).backgroundColor))
    .toBe(await badge.evaluate(node => getComputedStyle(node).borderTopColor));
  await page.screenshot({ path: testInfo.outputPath('codex-shared-question-selected.png'), animations: 'disabled' });
  await card.getByRole('button', { name: 'Next', exact: true }).click();
  await expect(card.locator('.user-question-progress')).toHaveText('2 / 2');
  await card.locator('textarea').fill('Keep keyboard support.');
  await card.getByRole('button', { name: 'Previous question', exact: true }).click();
  await expect(card.locator('.user-question-progress')).toHaveText('1 / 2');
  await expect(option).toHaveAttribute('aria-pressed', 'true');
  await card.locator('textarea').fill('Small change, with updated spacing');
  await expect(option).toHaveAttribute('aria-pressed', 'false');
  await card.getByRole('button', { name: 'Next', exact: true }).click();
  await expect(card.locator('textarea')).toHaveValue('Keep keyboard support.');
  app.rpcErrors.set('codex.server_request.respond', 'Temporary failure');
  await card.getByRole('button', { name: 'Send', exact: true }).click();
  await expect(card.locator('.user-question-error')).toContainText('Temporary failure');
  app.rpcErrors.delete('codex.server_request.respond');
  await card.getByRole('button', { name: 'Send', exact: true }).click();
  await expect(card.getByRole('button', { name: 'Sending…', exact: true })).toBeDisabled();
  await expect.poll(() => app.requests.filter(r => r.method === 'codex.server_request.respond').length).toBe(2);
  expect(app.requests.filter(r => r.method === 'codex.server_request.respond').at(-1).params).toMatchObject({
    response_token: 'questions', result: { answers: {
      scope: { answers: ['Small change, with updated spacing'] },
      details: { answers: ['Keep keyboard support.'] },
    } },
  });
  resolve(app, 'questions', 3);
  await expect(card).toHaveCount(0);
  request(app, 'close-me', 4, 'item/tool/requestUserInput', {
    questions: [{ id: 'more', question: 'Anything else?' }],
  });
  await card.locator('.user-question-close').click();
  await expect.poll(() => app.requests.filter(r => r.method === 'codex.server_request.respond').length).toBe(3);
  expect(app.requests.filter(r => r.method === 'codex.server_request.respond').at(-1).params)
    .toMatchObject({ response_token: 'close-me', result: { answers: {} } });
  resolve(app, 'close-me', 5);
  await expect(card).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

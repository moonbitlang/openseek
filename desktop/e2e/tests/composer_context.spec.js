import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

async function capture(page, testInfo, name) {
  const path = testInfo.outputPath(`${name}.png`);
  await page.locator('.composer').screenshot({ path });
  await testInfo.attach(name, { path, contentType: 'image/png' });
}

async function expectAlignedRows(page) {
  const composer = await page.locator('.composer-inner').boundingBox();
  const rows = page.locator('.composer-context-row:visible');
  for (const row of await rows.all()) {
    const rect = await row.boundingBox();
    expect(Math.abs(rect.x - composer.x)).toBeLessThan(1);
    expect(Math.abs(rect.width - composer.width)).toBeLessThan(1);
    await expect(row).toHaveCSS('border-radius', '14px');
    expect(await row.evaluate(el => el.scrollWidth <= el.clientWidth + 1)).toBe(true);
  }
}

test('context rows align and approval disclosure preserves draft focus and actions', async ({ page }, testInfo) => {
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
    await expect(page.locator('.queued-input-row').filter({ hasText: text })).toBeVisible();
  }
  const notify = event => app.notify('agent.event', { session: 'session-1', run_id: 'run-e2e', event });
  notify({ event: 'subrun_started', id: 'review-1', kind: 'review', label: 'Review API changes' });
  notify({ event: 'approval_requested', id: 'approval-context', tool_name: 'mbtx',
    detail: 'run the test suite', body: 'fn main { println("Run tests") }' });
  const approval = page.locator('.composer-approval');
  await expect(approval).toBeVisible();
  await expect(approval.locator('.composer-approval-body')).toBeHidden();
  await expectAlignedRows(page);
  await capture(page, testInfo, 'context-collapsed');
  await approval.locator('summary').click();
  await expect(approval.locator('.composer-approval-body')).toBeVisible();
  await composer.fill('Keep this draft');
  await expect(composer).toBeFocused();
  // An unrelated composer update must preserve the browser-owned disclosure.
  await expect(approval).toHaveAttribute('open', '');
  await capture(page, testInfo, 'context-expanded');
  await page.emulateMedia({ colorScheme: 'dark' });
  await expect(approval).toHaveCSS('background-color', 'rgb(35, 39, 47)');
  await capture(page, testInfo, 'context-dark');
  await page.emulateMedia({ colorScheme: 'light' });
  await page.setViewportSize({ width: 560, height: 960 });
  await expect(page.getByRole('button', { name: 'Show sidebar', exact: true })).toBeVisible();
  await expect.poll(() => page.locator('.app > aside').evaluate(el => el.getBoundingClientRect().right)).toBeLessThanOrEqual(0);
  await expectAlignedRows(page);
  await capture(page, testInfo, 'context-narrow');
  await approval.locator('summary').focus();
  await page.keyboard.press('Enter');
  await expect(approval.locator('.composer-approval-body')).toBeHidden();
  await approval.getByRole('button', { name: 'Allow once', exact: true }).click();
  await expect.poll(() => app.requests.find(r => r.method === 'agent.approval')?.params.allow).toBe(true);
  await expect(composer).toHaveValue('Keep this draft');
  expect(app.pageErrors).toEqual([]);
});

test('Codex questions and approvals expand and retain their responses', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  app.codexModels = [{ id: 'gpt-5.4-codex', displayName: 'GPT-5.4 Codex', isDefault: true,
    defaultReasoningEffort: 'medium', supportedReasoningEfforts: [{ reasoningEffort: 'medium', description: 'Balanced' }] }];
  await app.install();
  await app.goto();
  await page.getByRole('button', { name: 'Model', exact: true }).click();
  await page.getByRole('option', { name: 'GPT-5.4 Codex' }).click();
  await expect(page.locator('#task')).toHaveAttribute('placeholder', /Ask Codex/);
  await expect(page.locator('#task')).toBeEnabled();
  await page.locator('#task').fill('Review this project');
  await page.getByTitle('Send', { exact: true }).click();
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
  const question = page.locator('.codex-request').first();
  await expect(question).toBeVisible();
  await expect(question.getByRole('button', { name: /All tests/ })).toBeHidden();
  await question.locator('summary').first().click();
  await question.getByRole('button', { name: /All tests/ }).click();
  await expect(question.getByRole('button', { name: /All tests/ })).toHaveClass(/selected/);
  await question.locator('summary').first().click();
  await question.locator('summary').first().click();
  await expect(question.getByRole('button', { name: /All tests/ })).toHaveClass(/selected/);
  await question.getByRole('button', { name: 'Submit answers', exact: true }).click();
  await expect.poll(() => app.requests.find(r => r.method === 'codex.server_request.respond')?.params)
    .toMatchObject({ response_token: 'question-1', result: { answers: { scope: { answers: ['All tests'] } } } });
  request('approval-2', 'item/commandExecution/requestApproval', { command: 'moon test', cwd: '/workspace', reason: 'Run the project tests' });
  const approval = page.locator('.codex-request').filter({ hasText: 'Command approval' });
  await expect(approval).toBeVisible();
  await approval.locator('summary').first().click();
  await expect(approval.locator('.codex-request-command')).toHaveText('moon test');
  await expectAlignedRows(page);
  await capture(page, testInfo, 'codex-approval');
  await approval.getByRole('button', { name: 'Approve once', exact: true }).click();
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
    await page.getByRole('button', { name: 'Model', exact: true }).click();
    await page.getByRole('option', { name: 'GPT-5.4 Codex' }).click();
    await expect(page.locator('#task')).toHaveAttribute('placeholder', /Ask Codex/);
    await expect(page.locator('#task')).toBeEnabled();
    await page.locator('#task').fill('Review this project');
    await page.getByTitle('Send', { exact: true }).click();
    await expect.poll(() => app.requests.some(r => r.method === 'codex.turn.start')).toBe(true);
    for (const [index, command] of ['first-command', 'second-command'].entries()) {
      app.notify('codex.server_request', {
        response_token: command, request_id: command, generation: index + 2,
        method: 'item/commandExecution/requestApproval',
        params: { threadId: 'codex-thread-e2e', command, cwd: '/workspace' },
      });
    }
    const first = page.locator('.codex-request').filter({ hasText: 'first-command' });
    const second = page.locator('.codex-request').filter({ hasText: 'second-command' });
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

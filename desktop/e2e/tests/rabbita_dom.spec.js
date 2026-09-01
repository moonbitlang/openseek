import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('desktop browser shell renders host and conversation DOM', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();

  await expect(page.getByText('@octocat', { exact: true })).toBeVisible();
  await expect(page.getByText('Ready', { exact: true })).toBeVisible();
  await expect(page.getByText('Rabbita browser fixture', { exact: true }).first()).toBeVisible();
  await app.openSession();
  await expect(page.locator('.transcript')).toBeVisible();
  await expect(page.locator('.composer-input')).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('project picker and quick open use browser focus and keyboard events', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();

  await page.getByRole('button', { name: 'Add a project' }).click();
  const picker = page.getByRole('dialog', { name: 'Add a project' });
  await expect(picker).toBeVisible();
  await expect(picker.locator('.picker-list')).toContainText('Projects');
  await expect(picker.locator('.picker-list')).toContainText('Workspace');
  await page.getByRole('button', { name: 'Close project picker' }).click();
  await expect(picker).toBeHidden();

  await app.openSession();
  await app.openQuickOpen();
  const input = page.locator('#quick-open-input');
  await expect(input).toBeFocused();
  await input.fill('main');
  const mainResult = page.getByRole('option', { name: /main\.mbt/ });
  await expect(mainResult).toBeVisible();
  await expect(mainResult).toHaveAttribute('aria-selected', 'true');
  await page.keyboard.press('Escape');
  await expect(input).toBeHidden();
  expect(app.pageErrors).toEqual([]);
});

test('transcript mounts markdown, plan, goal, and MoonBit tool DOM', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();

  const transcript = page.locator('.transcript');
  await expect(transcript.getByRole('heading', { name: 'Browser result' })).toBeVisible();
  await expect(transcript.locator('strong')).toHaveText('successfully');
  await expect(transcript.locator('code').filter({ hasText: 'Rabbita 0.15' }).first()).toBeVisible();
  await expect(transcript.locator('.plan-step.completed')).toContainText('Inspect DOM');
  await expect(transcript.locator('.plan-step.in_progress')).toContainText('Run Playwright');
  await expect(transcript.locator('.plan-step.pending')).toContainText('Review layout');
  await expect(page.locator('.composer-goal')).toContainText('Ship Rabbita 0.15 browser tests');
  const mbtxCall = transcript.locator('.tool-call').filter({ has: page.locator('.mbtx-args') });
  await mbtxCall.locator('.tool-call-summary').click();
  await expect(mbtxCall.locator('.mbtx-args')).toContainText('fn main { println(42) }');
  const mbtxResult = transcript.locator('.tool-result').filter({ hasText: 'mbtx' });
  await mbtxResult.locator('.tool-result-summary').click();
  await expect(mbtxResult.locator('.tool-call-output')).toContainText('42');
  expect(app.pageErrors).toEqual([]);
});

test('approval card sends its decision through the browser transport', async ({ page }) => {
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
  app.notify('agent.event', {
    run_id: 'run-1',
    session: 'session-1',
    event: {
      event: 'approval_requested',
      id: 'approval-1',
      tool_name: 'mbtx',
      detail: 'run this snippet with no sandbox policy',
      body: 'fn main { @myshell.Cmd("npm", ["ci"]) }',
    },
  });

  const approval = page.locator('.composer-approval');
  await expect(approval).toBeVisible();
  await expect(approval.locator('.composer-approval-tool')).toContainText('mbtx');
  await expect(approval.locator('.composer-approval-body')).toContainText('@myshell.Cmd');
  await approval.getByRole('button', { name: 'Allow once' }).click();
  await expect.poll(() => app.requests.some(request =>
    request.method === 'agent.approval' &&
    request.params?.id === 'approval-1' &&
    request.params?.allow === true)).toBe(true);
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

  await page.getByTitle('Stop', { exact: true }).click();
  await expect.poll(() => app.requests.find(request =>
    request.method === 'agent.cancel'))
    .toMatchObject({ params: { run_id: 'run-e2e' } });
  expect(app.pageErrors).toEqual([]);
});

test('new chat, archive, and restore update the conversation sidebar', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();

  await page.locator('.workspace-row', { hasText: 'workspace' }).hover();
  await page.getByTitle('New conversation in this project').click();
  await expect(page.locator('.conversation-row', { hasText: 'New chat' })).toBeVisible();
  await expect(page.locator('#task')).toHaveValue('');

  await page.getByText('Rabbita browser fixture', { exact: true }).first().click();
  const liveRow = page.locator('.conversation-row[title="session-1"]');
  await liveRow.hover();
  await liveRow.getByTitle(/Archive —/).click();
  await expect.poll(() => app.requests.some(request =>
    request.method === 'session.archive' &&
    request.params?.session === 'session-1')).toBe(true);

  const archivedHeading = page.locator('.section-heading', {
    hasText: 'Archived chats (1)',
  });
  await archivedHeading.click();
  const archivedRow = page.locator('.conversation-row[title="session-1"]');
  await expect(archivedRow).toBeVisible();
  await archivedRow.hover();
  await archivedRow.getByTitle('Restore this conversation to the sidebar').click();
  await expect.poll(() => app.requests.some(request =>
    request.method === 'session.unarchive' &&
    request.params?.session === 'session-1')).toBe(true);
  await expect(page.getByText('Rabbita browser fixture', { exact: true }).first()).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('settings persist host API changes through settings.set', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();

  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Settings' })).toBeVisible();
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

test('skills installs a catalog entry and refreshes the installed library', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();

  await page.getByRole('button', { name: 'Skills', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Skills' })).toBeVisible();
  const registry = page.locator('.settings-group').filter({
    has: page.getByRole('heading', { name: 'Mooncakes registry' }),
  });
  const rabbita = registry.locator('.skill-row').filter({ hasText: /Rabbita/i });
  await rabbita.getByRole('button', { name: 'Install' }).click();
  await expect.poll(() => app.requests.some(request =>
    request.method === 'skills.install' &&
    request.params?.module_name === 'rabbita')).toBe(true);

  const installed = page.locator('.settings-group').filter({
    has: page.getByRole('heading', { name: 'Installed' }),
  });
  await expect(installed.locator('.skill-row').filter({ hasText: 'Rabbita' })).toBeVisible();
  await expect(rabbita).toContainText('Installed');
  expect(app.pageErrors).toEqual([]);
});

test('Codex account login can be started and cancelled from Settings', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.codexRequiresAuth = true;
  await app.install();
  await app.goto();

  await page.getByRole('button', { name: 'Settings', exact: true }).click();
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

  await page.locator('#task').fill('Run the Codex browser E2E turn');
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

test('desktop shell and modal stay inside a narrow browser viewport', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  const app = new DesktopBrowserHarness(page);
  await app.install();
  await app.goto();

  await page.getByRole('button', { name: 'Show sidebar' }).click();
  await page.getByRole('button', { name: 'Add a project' }).click();
  const bounds = await page.locator('.picker-modal').boundingBox();
  expect(bounds).not.toBeNull();
  expect(bounds.x).toBeGreaterThanOrEqual(0);
  expect(bounds.y).toBeGreaterThanOrEqual(0);
  expect(bounds.x + bounds.width).toBeLessThanOrEqual(390);
  expect(bounds.y + bounds.height).toBeLessThanOrEqual(844);
  await expect.poll(() => page.evaluate(() =>
    document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true);
  expect(app.pageErrors).toEqual([]);
});

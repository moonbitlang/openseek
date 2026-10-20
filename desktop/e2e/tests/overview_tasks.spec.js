import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

const command = 'npm run dev -- --host 127.0.0.1 --port 5173 --strictPort --open false';

function job(id, { command, state, startedAgoMs = 65000, subagent = null }) {
  const now = Date.now();
  return {
    job: {
      schema_version: 1, generation: 'runtime', id, revision: 1, command,
      description: null, cwd: '/workspace', state,
      started_at_ms: now - startedAgoMs, backgrounded_at_ms: now - startedAgoMs,
      finished_at_ms: state.kind === 'running' ? null : now - 1000,
      last_output_at_ms: null, output_file: null, output_persistent: false,
      output_bytes: 0, output_chars: 0, output_truncated: false, invalid_utf8: false,
      output_error: null, persistence_error: null, cleanup_error: null,
      ...(subagent ? { subagent } : {}),
    },
    output_path: null,
    controllable: state.kind === 'running',
    error: null,
  };
}

const running = { kind: 'running' };

function lists(app) {
  return app.requests.filter(request => request.method === 'jobs.list').length;
}

function overview(page) {
  return page.getByRole('complementary', { name: 'Overview' });
}

test('the overview lists what the conversation runs in the background', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  app.jobs = [
    job('bg-3', { command, state: running }),
    job('bg-2', {
      command: 'subagent',
      state: running,
      subagent: {
        kind: 'explore',
        label: 'map the jobs package',
        session: 'session-1-sr-1',
        launch: { kind: 'direct' },
        workspace: { kind: 'in_place' },
      },
    }),
    job('bg-1', { command: 'just test', state: { kind: 'exited', code: 0 } }),
  ];
  await app.install();
  await app.goto();
  await app.openSession();
  // Nothing on screen reads the jobs yet.
  expect(lists(app)).toBe(0);

  await page.getByRole('button', { name: 'Show overview', exact: true }).click();
  const panel = overview(page);
  const title = panel.getByRole('button', { name: 'Background tasks', exact: true });
  await expect(title).toBeVisible();
  // Folded, the card says how many tasks run.
  await expect(panel.getByText('2 running', { exact: true })).toBeVisible();

  // Unfolded, it says what each is.
  await title.click();
  await expect(panel.getByText('2 running', { exact: true })).toBeHidden();
  const row = panel.locator('.conv-overview-row', { hasText: 'npm run dev' });
  await expect(row).toHaveAttribute('title', command);
  await expect(row.locator('.conv-overview-command')).toHaveCSS('text-overflow', 'ellipsis');
  await expect(row.locator('.conv-overview-row-sub')).toHaveText(/^1m \d+s$/);
  await expect(panel.getByText('explore: map the jobs package', { exact: true })).toBeVisible();
  await expect(panel.getByText('1 finished', { exact: true })).toBeVisible();
  await page.screenshot({ path: testInfo.outputPath('overview-tasks.png') });
  // The summary lists the jobs; reading their output is the Jobs panel's.
  expect(app.requests.some(request => request.method === 'jobs.read')).toBe(false);
  const scope = app.requests.find(request => request.method === 'jobs.list').params.scope;
  expect(scope).toMatchObject({ session: 'session-1', workspace: '/workspace', archived: false });

  // The overview keeps the card current at its own, slower pace.
  const shown = lists(app);
  await expect.poll(() => lists(app), { timeout: 5000 }).toBeGreaterThan(shown);

  // Hidden, it asks nothing.
  await page.getByRole('button', { name: 'Hide overview', exact: true }).click();
  await expect(panel).toBeHidden();
  const hidden = lists(app);
  await page.waitForTimeout(3500);
  expect(lists(app)).toBe(hidden);

  // The card's button opens the Jobs panel, which lists every job.
  await page.getByRole('button', { name: 'Show overview', exact: true }).click();
  await panel.getByRole('button', { name: 'Open Jobs', exact: true }).click();
  await expect(page.locator('.jobs-panel')).toBeVisible();
  await expect(page.locator('.jobs-panel')).toContainText('just test');

  // Once nothing runs, the card goes away.
  for (const view of app.jobs) {
    view.job.state = { kind: 'exited', code: 0 };
    view.job.finished_at_ms = Date.now();
    view.job.revision += 1;
    view.controllable = false;
  }
  await expect(title).toBeHidden();
  await expect(panel.getByRole('button', { name: 'Environment', exact: true })).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('a conversation with nothing running shows no background tasks card', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.jobs = [job('bg-1', { command: 'just test', state: { kind: 'exited', code: 1 } })];
  await app.install();
  await app.goto();
  await app.openSession();
  await page.getByRole('button', { name: 'Show overview', exact: true }).click();
  const panel = overview(page);
  await expect(panel.getByRole('button', { name: 'Connectors', exact: true })).toBeVisible();
  await expect.poll(() => lists(app)).toBeGreaterThan(0);
  await expect(panel.getByRole('button', { name: 'Background tasks', exact: true })).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

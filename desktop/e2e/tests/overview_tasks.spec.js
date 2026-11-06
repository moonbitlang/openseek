import { test, expect } from './support/test.js';
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
  return page.locator('#conversation-overview');
}

test('the overview lists what the conversation runs in the background', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.jobs = [
    job('bg-3', { command, state: running }),
    job('bg-2', { command: 'subagent', state: running, subagent: {
      kind: 'explore', label: 'map the jobs package', session: 'session-1-sr-1',
      launch: { kind: 'direct' }, workspace: { kind: 'in_place' },
    } }),
    job('bg-1', { command: 'just test', state: { kind: 'exited', code: 0 } }),
  ];
  await app.install();
  await app.goto();
  await app.openSession();
  // Nothing on screen reads the jobs yet.
  expect(lists(app)).toBe(0);

  await page.locator('#conversation-overview-toggle[aria-pressed="false"]').click();
  const panel = overview(page);
  const title = panel.locator('[data-section="background"]').getByTestId('overview-card-toggle');
  await expect(title).toBeVisible();
  // Folded, the card says how many tasks run.
  await expect(panel.locator('[data-section="background"] .conv-overview-summary')).toBeVisible();

  // Unfolded, it says what each is.
  await title.click();
  await expect(panel.locator('[data-section="background"] .conv-overview-summary')).toBeHidden();
  const row = panel.locator('[data-section="background"] .conv-overview-row').filter({ has: page.locator('.conv-overview-command') });
  await expect(row).toHaveAttribute('title', command);
  await expect(row.locator('.conv-overview-row-sub')).toHaveText(/^1m \d+s$/);
  await expect(panel.locator('[data-section="background"]')).toContainText('explore: map the jobs package');
  await expect(panel.locator('[data-section="background"]')).toContainText('1 finished');
  // The summary lists the jobs; reading their output is the Jobs panel's.
  expect(app.requests.some(request => request.method === 'jobs.read')).toBe(false);
  const scope = app.requests.find(request => request.method === 'jobs.list').params.scope;
  expect(scope).toMatchObject({ session: 'session-1', workspace: '/workspace', archived: false });

  // The overview keeps the card current at its own, slower pace.
  const shown = lists(app);
  await expect.poll(() => lists(app), { timeout: 5000 }).toBeGreaterThan(shown);

  // Hidden, it asks nothing.
  await page.locator('#conversation-overview-toggle[aria-pressed="true"]').click();
  await expect(panel).toBeHidden();
  const hidden = lists(app);
  await page.waitForTimeout(3500);
  expect(lists(app)).toBe(hidden);

  // The card's button opens the Jobs panel, which lists every job, and hides
  // it again like the titlebar's panel toggles.
  await page.locator('#conversation-overview-toggle[aria-pressed="false"]').click();
  const open = panel.locator('[data-section="background"] .conv-overview-mini');
  await expect(open).toHaveAttribute('aria-pressed', 'false');
  await open.click();
  await expect(page.locator('.jobs-panel')).toBeVisible();
  await expect(page.locator('.jobs-panel')).toContainText('just test');
  const hide = panel.locator('[data-section="background"] .conv-overview-mini');
  await expect(hide).toHaveAttribute('aria-pressed', 'true');
  await hide.click();
  await expect(page.locator('.jobs-panel')).toBeHidden();
  await expect(open).toBeVisible();

  // Once nothing runs, the card goes away.
  for (const view of app.jobs) {
    view.job.state = { kind: 'exited', code: 0 };
    view.job.finished_at_ms = Date.now();
    view.job.revision += 1;
    view.controllable = false;
  }
  await expect(title).toBeHidden();
  expect(app.pageErrors).toEqual([]);
});

import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

class ScheduleHarness extends DesktopBrowserHarness {
  constructor(page) {
    super(page);
    this.schedules = { entries: [], runs: [] };
  }
  replyFor(request) {
    if (request.method === 'schedules.list') return structuredClone(this.schedules);
    if (request.method === 'schedules.save') {
      const { id, spec, run_now } = request.params;
      const entry = { id: id || 'plan-1', spec, enabled: true, run_requested: run_now, next_at: Date.now() + 60000 };
      this.schedules.entries = [...this.schedules.entries.filter(e => e.id !== entry.id), entry];
      return structuredClone(this.schedules);
    }
    if (request.method === 'schedules.action') {
      const entry = this.schedules.entries.find(e => e.id === request.params.id);
      switch (request.params.action) {
        case 'pause': entry.enabled = false; delete entry.next_at; break;
        case 'resume': entry.enabled = true; entry.next_at = Date.now() + 60000; break;
        case 'delete': this.schedules.entries = []; break;
        case 'run': this.schedules.runs.push({
          id: 'run-1', schedule_id: entry.id, name: entry.spec.name, workspace: '/workspace',
          session: 'session-1', started_at: Date.now(), status: { kind: 'running' }, log_path: '/runtime/run-1.log',
        }); break;
        case 'stop': this.schedules.runs[0].status = { kind: 'stopped' }; this.schedules.runs[0].finished_at = Date.now(); break;
      }
      return structuredClone(this.schedules);
    }
    return super.replyFor(request);
  }
}

test('schedule form, running controls, and completed session navigation', async ({ page }) => {
  const app = new ScheduleHarness(page);
  await app.install();
  await app.goto();
  await page.locator('#sidebar-schedules').click();
  await expect(page.locator('#management-dialog-title')).toBeVisible();
  await page.getByTestId('schedule-new').click();
  await page.locator('#schedule-name').fill('Inspect project');
  await page.locator('#schedule-workspace').selectOption('/workspace');
  await page.locator('#schedule-task').fill('Check the repository and summarize findings.');
  await page.locator('#schedule-timing').selectOption('once');
  await page.locator('#schedule-minutes').fill('10');
  await page.getByTestId('schedule-save').click();
  await expect(page.locator('.schedule-form')).toHaveCount(0);
  await expect(page.locator('[data-schedule-id="plan-1"] h2')).toHaveText('Inspect project');
  expect(app.requests.find(r => r.method === 'schedules.save').params.spec.timing.kind).toBe('once');
  await page.getByTestId('schedule-toggle').click();
  await expect(page.getByTestId('schedule-toggle')).toHaveAttribute('aria-pressed', 'false');
  await page.getByTestId('schedule-run').click();
  await expect(page.getByTestId('schedule-run')).toBeDisabled();
  await expect(page.getByTestId('schedule-open-session')).toBeVisible();
  await page.getByTestId('schedule-open-session').click();
  await expect.poll(() => app.requests.some(r => r.method === 'session.load')).toBe(true);
  await page.locator('#sidebar-schedules').click();
  await page.getByTestId('schedule-stop').first().click();
  await expect(page.getByTestId('schedule-open-session')).toBeVisible();
  await page.getByTestId('schedule-open-session').click();
  await expect.poll(() => app.requests.some(r => r.method === 'session.load')).toBe(true);
  expect(app.pageErrors).toEqual([]);
});

test('failed save retains the draft and editing preserves its fields', async ({ page }) => {
  const app = new ScheduleHarness(page);
  await app.install();
  await app.goto();
  await page.locator('#sidebar-schedules').click();
  await page.getByTestId('schedule-new').click();
  await page.locator('#schedule-name').fill('Daily work');
  await page.locator('#schedule-task').fill('Inspect changes');
  app.rpcErrors.set('schedules.save', 'Cannot save: disk full');
  await page.getByTestId('schedule-save').click();
  await expect(page.getByRole('alert')).toContainText('disk full');
  await expect(page.locator('#schedule-task')).toHaveValue('Inspect changes');
  app.rpcErrors.delete('schedules.save');
  await page.getByTestId('schedule-save').click();
  await expect(page.locator('.schedule-form')).toHaveCount(0);
  await page.getByTestId('schedule-edit').click();
  await expect(page.locator('#schedule-name')).toHaveValue('Daily work');
  await expect(page.locator('#schedule-minutes')).toHaveValue('30');
  await page.setViewportSize({ width: 420, height: 900 });
  await expect(page.locator('#management-dialog')).toBeVisible();
  await expect(page.getByTestId('schedule-save')).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});


test('automatic directory and save-and-run-now work without choosing a project', async ({ page }) => {
  const app = new ScheduleHarness(page);
  await app.install();
  await app.goto();
  await page.locator('#sidebar-schedules').click();
  await page.getByTestId('schedule-new').click();
  await expect(page.locator('#schedule-workspace')).toHaveValue('auto');
  await page.locator('#schedule-name').fill('Community updates');
  await page.locator('#schedule-task').fill('Summarize new community posts.');
  await page.getByTestId('schedule-save-run').click();
  await expect(page.locator('.schedule-form')).toHaveCount(0);
  const payload = app.requests.find(r => r.method === 'schedules.save').params;
  expect(payload.run_now).toBe(true);
  expect(payload.spec).not.toHaveProperty('workspace');
  expect(payload.spec.timing).toEqual({ kind: 'every', minutes: 30 });
  await expect(page.locator('[data-schedule-id=plan-1] .schedule-meta').first()).toHaveText('Every 30 min · Queued');
  await expect(page.getByTestId('schedule-run')).toBeDisabled();
  await page.getByTestId('schedule-edit').click();
  await expect(page.locator('#schedule-workspace')).toHaveValue('auto');
  expect(app.pageErrors).toEqual([]);
});


test('old setup failure remains readable when no log file was created', async ({ page }) => {
  const app = new ScheduleHarness(page);
  app.schedules.runs.push({ id: 'old-run', schedule_id: 'old-plan', name: 'Community', workspace: '/workspace', session: 'old-session', started_at: Date.now(), finished_at: Date.now(), status: { kind: 'failed', message: 'Could not prepare working directory' }, log_path: '/missing.log' });
  app.rpcErrors.set('fs.read_file', 'No such file');
  await app.install();
  await app.goto();
  await page.locator('#sidebar-schedules').click();
  await page.getByTestId('schedule-view-log').click();
  await expect(page.locator('.schedule-log-content')).toContainText('Could not prepare working directory');
  await expect(page.getByRole('alert')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});


for (const broadcastDirectory of [true, false]) {
  test(`new automatic folder resolves placement and tails without refresh (directory notification: ${broadcastDirectory})`, async ({ page }) => {
    const app = new ScheduleHarness(page);
    await app.install();
    await app.goto();
    await page.locator('#sidebar-schedules').click();
    await expect(page.locator('#schedule-empty')).toBeVisible();
    const workspace = '/Users/test/OpenSeek/Scheduled/new-task';
    app.workspaces.push(workspace);
    app.sessionGroups = (sessions) => ({ groups: [{ workspace, name: 'Automatic task', session_root: workspace + '/.openseek', sessions: sessions === app.archivedSessions ? [] : [{ id: 'session-1', title: 'Community watch', updated_at_ms: Date.now() }], error: '' }] });
    app.schedules.runs.push({ id: 'live-run', schedule_id: 'live-plan', name: 'Community watch', workspace, session: 'session-1', started_at: Date.now(), status: { kind: 'running' }, log_path: '/run.log' });
    if (broadcastDirectory) app.notify('workspace.changed', { workspaces: app.workspaces });
    app.notify('session.changed', { change: 'created', session: 'session-1', workspace });
    await expect(page.getByTestId('schedule-open-session')).toBeVisible();
    await page.getByTestId('schedule-open-session').click();
    await expect.poll(() => app.requests.some(r => r.method === 'worktree.list' && r.params.workspace === workspace)).toBe(true);
    await expect(page.locator('.composer-notice-text')).toHaveCount(0);
    await expect(page.locator('#transcript')).toBeVisible();
    await expect(page.locator('#transcript')).toContainText('Browser result');
    await expect(page.locator('.archived-read-only-text')).toBeVisible();
    await expect(page.locator('textarea#task')).toHaveCount(0);
    const submissionsBefore = app.requests.filter(r => ['agent.start', 'agent.command'].includes(r.method)).length;
    await page.locator('#transcript').click();
    await page.keyboard.press('Enter');
    await page.keyboard.press('Control+Enter');
    expect(app.requests.filter(r => ['agent.start', 'agent.command'].includes(r.method)).length).toBe(submissionsBefore);
    const readsBefore = app.requests.filter(r => r.method === 'session.load').length;
    let sequence = Math.max(...app.sessionEvents.map(e => e.sequence));
    for (const content of ['Automatic live update one', 'Automatic live update two']) {
      sequence += 1;
      app.notify('session.event', { session: 'session-1', session_root: workspace + '/.openseek', sequence, event: { sequence, item: { kind: 'assistant', payload: { content } } } });
      await expect(page.locator('#transcript')).toContainText(content);
    }
    expect(app.requests.filter(r => r.method === 'session.load').length).toBe(readsBefore);
    app.schedules.runs[0].status = { kind: 'succeeded' };
    app.schedules.runs[0].finished_at = Date.now();
    app.notify('session.changed', { change: 'created', session: 'session-1', workspace });
    await expect(page.locator('textarea#task')).toBeVisible();
    await expect(page.locator('.archived-read-only-text')).toHaveCount(0);
    app.schedules.runs[0].status = { kind: 'running' };
    await page.locator('#sidebar-schedules').click();
    await expect(page.locator('#schedule-running').getByTestId('schedule-open-session')).toBeVisible();
    app.schedules.runs[0].status = { kind: 'succeeded' };
    app.schedules.runs[0].finished_at = Date.now();
    app.notify('session.changed', { change: 'created', session: 'session-1', workspace });
    await expect(page.locator('#schedule-running').getByTestId('schedule-open-session')).toHaveCount(0);
    await expect(page.locator('#schedule-history')).toContainText('Completed');
    expect(app.pageErrors).toEqual([]);
  });
}


test('reopening Scheduled while save is pending preserves its acknowledgement', async ({ page }) => {
  const app = new ScheduleHarness(page);
  app.rpcDelays.set('schedules.save', 1200);
  await app.install();
  await app.goto();
  await page.locator('#sidebar-schedules').click();
  await page.getByTestId('schedule-new').click();
  await page.locator('#schedule-name').fill('Only one plan');
  await page.locator('#schedule-task').fill('Summarize updates');
  await page.getByTestId('schedule-save').click();
  await expect.poll(() => app.requests.filter(r => r.method === 'schedules.save').length).toBe(1);
  await page.keyboard.press('Escape');
  await page.locator('#sidebar-schedules').click();
  await expect(page.getByTestId('schedule-save')).toBeDisabled();
  await expect(page.locator('.schedule-form')).toHaveCount(0);
  expect(app.requests.filter(r => r.method === 'schedules.save')).toHaveLength(1);
});

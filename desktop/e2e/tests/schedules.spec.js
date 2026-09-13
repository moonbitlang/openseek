import { test, expect } from '@playwright/test';
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
  await page.getByRole('button', { name: 'Scheduled', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Scheduled tasks' })).toBeVisible();
  await page.getByRole('button', { name: 'New schedule', exact: true }).click();
  await page.getByLabel('Name', { exact: true }).fill('Inspect project');
  await page.getByLabel('Working directory', { exact: true }).selectOption('/workspace');
  await page.getByLabel('Task', { exact: true }).fill('Check the repository and summarize findings.');
  await page.getByLabel('Schedule', { exact: true }).selectOption('once');
  await page.getByLabel('Minutes', { exact: true }).fill('10');
  await page.getByRole('button', { name: 'Save schedule', exact: true }).click();
  await expect(page.locator('.schedule-form')).toHaveCount(0);
  await expect(page.getByRole('heading', { name: 'Inspect project', exact: true })).toBeVisible();
  expect(app.requests.find(r => r.method === 'schedules.save').params.spec.timing.kind).toBe('once');
  await page.getByRole('button', { name: 'Pause', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Resume', exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Run now', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Run now', exact: true })).toBeDisabled();
  await expect(page.getByRole('button', { name: 'Open session', exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Open session', exact: true }).click();
  await expect(page.locator('.schedules-page')).toHaveCount(0);
  await expect.poll(() => app.requests.some(r => r.method === 'session.load')).toBe(true);
  await page.getByRole('button', { name: 'Scheduled', exact: true }).click();
  await page.getByRole('button', { name: 'Stop run', exact: true }).first().click();
  await expect(page.getByRole('button', { name: 'Open session', exact: true })).toBeVisible();
  await page.screenshot({ animations: 'disabled', path: test.info().outputPath('scheduled-tasks.png') });
  await page.getByRole('button', { name: 'Open session', exact: true }).click();
  await expect(page.locator('.schedules-page')).toHaveCount(0);
  await expect.poll(() => app.requests.some(r => r.method === 'session.load')).toBe(true);
  expect(app.pageErrors).toEqual([]);
});

test('failed save retains the draft and editing preserves its fields', async ({ page }) => {
  const app = new ScheduleHarness(page);
  await app.install();
  await app.goto();
  await page.getByRole('button', { name: 'Scheduled', exact: true }).click();
  await page.getByRole('button', { name: 'New schedule', exact: true }).click();
  await page.getByLabel('Name', { exact: true }).fill('Daily work');
  await page.getByLabel('Task', { exact: true }).fill('Inspect changes');
  app.rpcErrors.set('schedules.save', 'Cannot save: disk full');
  await page.getByRole('button', { name: 'Save schedule', exact: true }).click();
  await expect(page.getByRole('alert')).toContainText('disk full');
  await expect(page.getByLabel('Task', { exact: true })).toHaveValue('Inspect changes');
  app.rpcErrors.delete('schedules.save');
  await page.getByRole('button', { name: 'Save schedule', exact: true }).click();
  await expect(page.locator('.schedule-form')).toHaveCount(0);
  await page.getByRole('button', { name: 'Edit', exact: true }).click();
  await expect(page.getByLabel('Name', { exact: true })).toHaveValue('Daily work');
  await expect(page.getByLabel('Minutes', { exact: true })).toHaveValue('30');
  await page.setViewportSize({ width: 420, height: 900 });
  await expect(page.getByRole('button', { name: 'Show sidebar', exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Save schedule', exact: true })).toBeVisible();
  await page.screenshot({ animations: 'disabled', path: test.info().outputPath('schedule-form-mobile.png') });
  expect(app.pageErrors).toEqual([]);
});


test('automatic directory and save-and-run-now work without choosing a project', async ({ page }) => {
  const app = new ScheduleHarness(page);
  await app.install();
  await app.goto();
  await page.getByRole('button', { name: 'Scheduled', exact: true }).click();
  await page.getByRole('button', { name: 'New schedule', exact: true }).click();
  await expect(page.getByLabel('Working directory', { exact: true })).toHaveValue('auto');
  await page.getByLabel('Name', { exact: true }).fill('Community updates');
  await page.getByLabel('Task', { exact: true }).fill('Summarize new community posts.');
  await page.getByRole('button', { name: 'Save and run now', exact: true }).click();
  await expect(page.locator('.schedule-form')).toHaveCount(0);
  const payload = app.requests.find(r => r.method === 'schedules.save').params;
  expect(payload.run_now).toBe(true);
  expect(payload.spec).not.toHaveProperty('workspace');
  expect(payload.spec.timing).toEqual({ kind: 'every', minutes: 30 });
  await expect(page.getByText('Every 30 min · Queued', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Run now', exact: true })).toBeDisabled();
  await page.getByRole('button', { name: 'Edit', exact: true }).click();
  await expect(page.getByLabel('Working directory', { exact: true })).toHaveValue('auto');
  await page.screenshot({ animations: 'disabled', path: test.info().outputPath('automatic-schedule.png') });
  expect(app.pageErrors).toEqual([]);
});


test('old setup failure remains readable when no log file was created', async ({ page }) => {
  const app = new ScheduleHarness(page);
  app.schedules.runs.push({ id: 'old-run', schedule_id: 'old-plan', name: 'Community', workspace: '/workspace', session: 'old-session', started_at: Date.now(), finished_at: Date.now(), status: { kind: 'failed', message: 'Could not prepare working directory' }, log_path: '/missing.log' });
  app.rpcErrors.set('fs.read_file', 'No such file');
  await app.install();
  await app.goto();
  await page.getByRole('button', { name: 'Scheduled', exact: true }).click();
  await page.getByRole('button', { name: 'View log', exact: true }).click();
  await expect(page.locator('.schedule-log-content')).toContainText('Could not prepare working directory');
  await expect(page.getByRole('alert')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});


for (const broadcastDirectory of [true, false]) {
  test(`new automatic folder resolves placement and tails without refresh (directory notification: ${broadcastDirectory})`, async ({ page }) => {
    const app = new ScheduleHarness(page);
    await app.install();
    await app.goto();
    await page.getByRole('button', { name: 'Scheduled', exact: true }).click();
    await expect(page.getByText('No schedules yet.', { exact: false })).toBeVisible();
    const workspace = '/Users/test/OpenSeek/Scheduled/new-task';
    app.workspaces.push(workspace);
    app.sessionGroups = (sessions) => ({ groups: [{ workspace, name: 'Automatic task', session_root: workspace + '/.openseek', sessions: sessions === app.archivedSessions ? [] : [{ id: 'session-1', title: 'Community watch', updated_at_ms: Date.now() }], error: '' }] });
    app.schedules.runs.push({ id: 'live-run', schedule_id: 'live-plan', name: 'Community watch', workspace, session: 'session-1', started_at: Date.now(), status: { kind: 'running' }, log_path: '/run.log' });
    if (broadcastDirectory) app.notify('workspace.changed', { workspaces: app.workspaces });
    app.notify('session.changed', { change: 'created', session: 'session-1', workspace });
    await expect(page.getByRole('button', { name: 'Open session', exact: true })).toBeVisible();
    await page.getByRole('button', { name: 'Open session', exact: true }).click();
    await expect.poll(() => app.requests.some(r => r.method === 'worktree.list' && r.params.workspace === workspace)).toBe(true);
    await expect(page.getByText('Waiting for workspace placement…', { exact: true })).toHaveCount(0);
    await expect(page.locator('#transcript')).toBeVisible();
    await expect(page.locator('#transcript')).toContainText('Browser result');
    const readsBefore = app.requests.filter(r => r.method === 'session.load').length;
    let sequence = Math.max(...app.sessionEvents.map(e => e.sequence));
    for (const content of ['Automatic live update one', 'Automatic live update two']) {
      sequence += 1;
      app.notify('session.event', { session: 'session-1', session_root: workspace + '/.openseek', sequence, event: { sequence, item: { kind: 'assistant', payload: { content } } } });
      await expect(page.locator('#transcript')).toContainText(content);
    }
    expect(app.requests.filter(r => r.method === 'session.load').length).toBe(readsBefore);
    await page.getByRole('button', { name: 'Scheduled', exact: true }).click();
    await expect(page.getByRole('region', { name: 'Running', exact: true }).getByRole('button', { name: 'Open session' })).toBeVisible();
    app.schedules.runs[0].status = { kind: 'succeeded' };
    app.schedules.runs[0].finished_at = Date.now();
    app.notify('session.changed', { change: 'created', session: 'session-1', workspace });
    await expect(page.getByRole('region', { name: 'Running', exact: true }).getByRole('button', { name: 'Open session' })).toHaveCount(0);
    await expect(page.getByRole('region', { name: 'Run history', exact: true })).toContainText('Completed');
    expect(app.pageErrors).toEqual([]);
  });
}

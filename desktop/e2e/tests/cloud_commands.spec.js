import { test, expect } from '@playwright/test';
import { CloudHarness, sessionA, sessionB } from './support/cloud_harness.js';

const commands = app => app.requests.filter(request => request.method === 'POST' && request.path.endsWith('/commands')).map(request => JSON.parse(request.body));

async function open(page) {
  const app = new CloudHarness(page);
  await app.install();
  await app.goto();
  await app.open();
  return app;
}

test('Cloud goals use the shared editor and settle on goal_updated without creating a task', async ({ page }, testInfo) => {
  const app = await open(page);
  const task = page.locator('#task');
  await task.fill('/goal');
  await expect(page.locator('.completion-item').filter({ hasText: '/goal' })).toBeVisible();
  await task.press('Enter');
  await expect(page.locator('#goal-set')).toBeVisible();
  await task.fill('Ship the feature');
  await page.locator('#goal-set').click();
  await expect.poll(() => commands(app)).toEqual([{ command: { command: 'goal', action: 'set', text: 'Ship the feature' } }]);
  await expect(page.locator('.composer-goal')).toContainText('Setting goal');
  await expect(page.locator('#stop')).toHaveCount(0);
  expect(app.controlState(sessionA).data.active_task_id).toBeNull();
  await app.emitSessionEvent(sessionA, 'goal_updated', { goal: 'Ship the feature' }, { task: null });
  await expect(page.locator('.composer-goal')).toContainText('Goal: Ship the feature');
  await expect(page.locator('.composer-goal.pending')).toHaveCount(0);
  await task.fill('Keep this prompt');
  await page.locator('.composer-goal').getByRole('button', { name: 'Edit', exact: true }).click();
  await expect(task).toHaveValue('Ship the feature');
  await task.fill('A revised goal');
  await page.locator('#goal-cancel').click();
  await expect(task).toHaveValue('Keep this prompt');
  await page.screenshot({ path: testInfo.outputPath('cloud-goal.png') });
  await app.open(sessionB);
  await app.open(sessionA);
  await expect(page.locator('.composer-goal')).toContainText('Goal: Ship the feature');
  await page.locator('.composer-goal').getByRole('button', { name: 'Clear the standing goal', exact: true }).click();
  await expect.poll(() => commands(app)).toHaveLength(2);
  expect(commands(app)[1]).toEqual({ command: { command: 'goal', action: 'clear' } });
  await expect(page.locator('.composer-goal')).toContainText('Clearing goal');
  await app.emitSessionEvent(sessionA, 'goal_updated', { goal: null }, { task: null });
  await expect(page.locator('.composer-goal:not(.hidden)')).toHaveCount(0);
  await expect(task).toHaveValue('Keep this prompt');
  expect(app.postCount).toBe(0);
  expect(app.requests.filter(request => request.method === 'POST' && request.path === '/v1/sessions')).toHaveLength(0);
  expect(app.device.pageErrors).toEqual([]);
});

test('Cloud blank does not expose engine-only commands or create a session for them', async ({ page }) => {
  const app = await open(page);
  await page.getByRole('button', { name: 'New chat', exact: true }).click();
  await page.locator('#task').fill('/goal');
  await expect(page.locator('.completion-item')).toHaveCount(0);
  expect(commands(app)).toEqual([]);
  expect(app.requests.filter(request => request.method === 'POST' && request.path === '/v1/sessions')).toHaveLength(0);
});

test('Cloud reload restores the goal and summary from the native session document', async ({ page }) => {
  const app = new CloudHarness(page);
  app.histories.set(sessionA, {
    messages: [], generating: false,
    session: { events: [
      { sequence: 1, item: { kind: 'runtime_notice', payload: { content: '[goal]\nFinish the release' } } },
      { sequence: 2, item: { kind: 'summary', payload: { content: 'Earlier release work', from_sequence: 0, to_sequence: 1 } } },
    ] },
  });
  await app.install();
  await app.goto();
  await app.open();
  await expect(page.locator('.composer-goal')).toContainText('Finish the release');
  await expect(page.getByText('Earlier release work', { exact: true })).toHaveCount(1);
  await page.reload();
  await app.open();
  await expect(page.locator('.composer-goal')).toContainText('Finish the release');
  await expect(page.getByText('Earlier release work', { exact: true })).toHaveCount(1);
  expect(commands(app)).toHaveLength(0);
});

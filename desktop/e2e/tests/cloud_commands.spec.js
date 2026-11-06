import { test, expect } from './support/test.js';
import { CloudHarness, sessionA, sessionB } from './support/cloud_harness.js';

const commands = app => app.requests.filter(request => request.method === 'POST' && request.path.endsWith('/commands')).map(request => JSON.parse(request.body));

async function open(page) {
  const app = new CloudHarness(page);
  await app.install();
  await app.goto();
  await app.open();
  return app;
}

test('Cloud goals use the shared editor and settle on goal_updated without creating a task', async ({ page }) => {
  const app = await open(page);
  const task = page.locator('#task');
  await task.fill('/goal');
  await expect(page.locator('.completion-item').filter({ hasText: '/goal' })).toBeVisible();
  await task.press('Enter');
  await expect(page.locator('#goal-cancel')).toBeVisible();
  await task.fill('Ship the feature');
  await page.locator('#goal-set').click();
  await expect.poll(() => commands(app)).toEqual([{ command: { command: 'goal', action: 'set', text: 'Ship the feature' } }]);
  await expect(page.locator('.composer-goal')).toContainText('Setting goal');
  await expect(page.locator('#stop')).toHaveCount(0);
  await app.emitSessionEvent(sessionA, 'goal_updated', { goal: 'Ship the feature' }, { task: null });
  await expect(page.locator('.composer-goal')).toContainText('Goal: Ship the feature');
  await expect(page.locator('.composer-goal.pending')).toHaveCount(0);
  await task.fill('Keep this prompt');
  await page.locator('.composer-goal').getByRole('button', { name: 'Edit', exact: true }).click();
  await expect(task).toHaveValue('Ship the feature');
  await task.fill('A revised goal');
  await page.locator('#goal-cancel').click();
  await expect(task).toHaveValue('Keep this prompt');
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

// Prompt expansion is shared: one command runs in an existing session and the other in a new one.
for (const [name, workflow, fresh] of [['simplify', 'simplify.mbtx', false], ['ultrareview', 'review.mbtx', true]]) {
  test(`Cloud ${name} shares prompt expansion in ${fresh ? 'a new' : 'an existing'} session`, async ({ page }) => {
    const app = await open(page);
    if (fresh) await app.create();
    const task = page.locator('#task');
    await task.fill(`/${name}`);
    await expect(page.locator('.completion-item').filter({ hasText: `/${name}` })).toBeVisible();
    if (!fresh && name === 'simplify') {
      await task.fill('/');
      await expect(page.locator('.completion-item')).toHaveCount(4);
      await task.fill(`/${name}`);
    }
    await task.press('Enter');
    await expect(task).toHaveValue(`/${name} `);
    await page.keyboard.type('the parser');
    expect(commands(app)).toEqual([]);
    expect(app.requests.filter(request => request.method === 'POST' && request.path === '/v1/sessions')).toHaveLength(0);
    await page.locator('#send').click();
    await expect.poll(() => commands(app).length).toBe(1);
    const command = commands(app)[0].command;
    expect(command.command).toBe('prompt');
    const content = typeof command.content === 'string' ? command.content : command.content.filter(part => part.type === 'text').map(part => part.text).join('');
    expect(content).toContain(`"@builtin/${workflow}"`);
    expect(content).toContain('Focus: the parser');
    if (name === 'ultrareview') expect(content).toContain('"--swarm"');
    await expect(task).toHaveValue('');
    expect(app.requests.filter(request => request.method === 'POST' && request.path === '/v1/sessions')).toHaveLength(fresh ? 1 : 0);
    expect(app.device.pageErrors).toEqual([]);
  });
}

async function compact(page) {
  await page.locator('#task').fill('/compact');
  await expect(page.locator('.completion-item').filter({ hasText: '/compact' })).toBeVisible();
  await page.locator('#task').press('Enter');
}

test('Cloud idle compaction settles without an assistant or a task and reports failure', async ({ page }) => {
  const app = await open(page);
  await compact(page);
  await expect.poll(() => commands(app)).toEqual([{ command: { command: 'compact' } }]);
  await expect(page.locator('.composer-notice-text')).toContainText('queued');
  await expect(page.locator('#stop')).toHaveCount(0);
  await app.emitSessionEvent(sessionA, 'compaction_started', { from_sequence: 1, to_sequence: 2 }, { task: null });
  await app.emitSessionEvent(sessionA, 'compaction_failed', { error: 'Fixture compaction failed' }, { task: null });
  await expect(page.locator('.composer-notice-text')).toHaveCount(0);
  await expect(page.getByText('Fixture compaction failed', { exact: true })).toBeVisible();
  expect(app.postCount).toBe(0);
});

import { test, expect } from './support/test.js';
import { CloudHarness } from './support/cloud_harness.js';

const commands = app => app.requests.filter(request => request.method === 'POST' && request.path.endsWith('/commands')).map(request => JSON.parse(request.body));

async function open(page) {
  const app = new CloudHarness(page);
  await app.install();
  await app.goto();
  await app.open();
  return app;
}

test('Cloud /simplify expands its workflow prompt in the existing session', async ({ page }) => {
  const app = await open(page);
  const task = page.locator('#task');
  await task.fill('/simplify');
  await expect(page.locator('.completion-item').filter({ hasText: '/simplify' })).toBeVisible();
  await task.press('Enter');
  await expect(task).toHaveValue('/simplify ');
  await page.keyboard.type('the parser');
  expect(commands(app)).toEqual([]);
  await page.locator('#send').click();
  await expect.poll(() => commands(app).length).toBe(1);
  const command = commands(app)[0].command;
  expect(command.command).toBe('prompt');
  const content = typeof command.content === 'string' ? command.content : command.content.filter(part => part.type === 'text').map(part => part.text).join('');
  expect(content).toContain('"@builtin/simplify.mbtx"');
  expect(content).toContain('Focus: the parser');
  await expect(task).toHaveValue('');
  expect(app.requests.filter(request => request.method === 'POST' && request.path === '/v1/sessions')).toHaveLength(0);
});


test('Cloud can continue a checkpoint without overwriting a draft or starting another session', async ({ page }) => {
  const app = new CloudHarness(page);
  app.histories.set(app.sessionIds[0], { generating: false, messages: [
    { task_id: 'first', kind: 'user', data: { content: 'Finish this task' }, created_at: 1 },
    { task_id: 'first', kind: 'task_finished', data: { status: 'incomplete', result: { status: 'context_yield', reason: 'Checkpoint' } }, created_at: 2 },
  ] });
  app.manualTasks = true;
  await app.install(); await app.goto(); await app.open();
  const task = page.locator('#task');
  const resume = page.getByRole('button', { name: 'Continue', exact: true });
  await expect(resume).toBeVisible();
  await task.fill('My draft');
  await expect(resume).toHaveCount(0);
  await expect(task).toHaveValue('My draft');
  await task.fill('');
  await resume.click();
  await expect.poll(() => commands(app).length).toBe(1);
  expect(commands(app)[0].command).toMatchObject({ command: 'prompt', content: 'Continue the task from the checkpoint summary. Do not redo finished work; take the next step.' });
  await expect(resume).toHaveCount(0);
  expect(app.requests.filter(r => r.method === 'POST' && r.path === '/v1/sessions')).toHaveLength(0);
});

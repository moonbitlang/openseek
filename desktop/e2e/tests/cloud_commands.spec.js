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
  expect(app.device.pageErrors).toEqual([]);
});

async function compact(page) {
  await page.locator('#task').fill('/compact');
  await expect(page.locator('.completion-item').filter({ hasText: '/compact' })).toBeVisible();
  await page.locator('#task').press('Enter');
}


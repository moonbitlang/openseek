import { test, expect } from '@playwright/test';
import { CloudHarness, sessionA } from './support/cloud_harness.js';

test('Cloud detail toggle updates the transcript and preserves the preference across narrow layouts and reloads', async ({ page }, testInfo) => {
  const cloud = new CloudHarness(page);
  cloud.histories.set(sessionA, {
    messages: [{ task_id: 'fixture-task', kind: 'assistant_message', created_at: 1000,
      data: { content: 'Cloud answer', reasoning_content: 'Cloud reasoning details' } }],
    generating: false,
  });
  await cloud.install();
  await cloud.goto();
  const toggle = page.getByRole('button', { name: 'Detailed mode', exact: true });
  await cloud.create();
  await expect(toggle).toHaveCount(0);
  await cloud.open();
  await expect(page.locator('#transcript')).toContainText('Cloud answer');
  await expect(toggle).toHaveAttribute('aria-pressed', 'false');
  await expect(page.locator('#transcript')).not.toContainText('Cloud reasoning details');
  await page.screenshot({ path: testInfo.outputPath('cloud-minimal.png'), animations: 'disabled' });
  await toggle.click();
  await expect(toggle).toHaveAttribute('aria-pressed', 'true');
  await expect(toggle).toHaveClass(/active/);
  await expect(page.locator('#transcript .activity-thinking')).toHaveText('Cloud reasoning details');
  await page.screenshot({ path: testInfo.outputPath('cloud-detailed.png'), animations: 'disabled' });
  await page.setViewportSize({ width: 390, height: 844 });
  await expect(toggle).toHaveCount(0);
  await expect(page.locator('#transcript')).not.toContainText('Cloud reasoning details');
  await page.setViewportSize({ width: 1440, height: 900 });
  await expect(toggle).toHaveAttribute('aria-pressed', 'true');
  await expect(page.locator('#transcript .activity-thinking')).toHaveText('Cloud reasoning details');
  await page.reload();
  await cloud.open();
  await expect(toggle).toHaveAttribute('aria-pressed', 'true');
  await expect(page.locator('#transcript .activity-thinking')).toHaveText('Cloud reasoning details');
  await toggle.focus();
  await page.keyboard.press('Space');
  await expect(toggle).toHaveAttribute('aria-pressed', 'false');
  await expect(page.locator('#transcript')).not.toContainText('Cloud reasoning details');
  expect(cloud.device.pageErrors).toEqual([]);
  expect(await page.evaluate(() => window.cloudUnhandledRejections)).toEqual([]);
});

test('Cloud reuses live reasoning, actual usage, stages and compaction UI before committing history', async ({ page }) => {
  const cloud = new CloudHarness(page);
  cloud.streamEvents = [
    ['task_started', {}],
    ['step', { step: 3 }],
    ['stream_retry', { attempt: 1, max_attempts: 3, reason: 'network' }],
    ['reasoning_delta', { content: 'Partial reasoning' }],
    ['reasoning_delta', { content: ' fragment' }],
    ['reasoning_message', { content: 'Complete reasoning' }],
    ['usage', { usage: { prompt_tokens: 100, completion_tokens: 20, total_tokens: 120, prompt_cache_hit_tokens: 50, prompt_cache_miss_tokens: 50 } }],
    ['assistant_delta', { content: 'Answer' }],
    ['assistant_message', { content: 'Answer', reasoning_content: 'Complete reasoning' }],
    ['auto_compaction_started', { from_sequence: 1, to_sequence: 10 }],
    ['auto_compaction_finished', { from_sequence: 1, to_sequence: 10, summary: 'Earlier work' }],
    ['task_finished', { status: 'completed', result: { output: { answer: 'Answer' }, usage: { total_tokens: 350 }, steps: 3 } }],
  ];
  const resume = [];
  cloud.eventPauses = new Map([0, 2, 3, 5, 7, 9, 10].map(index => [index, new Promise(resolve => resume.push(resolve))]));
  try {
    await page.addInitScript(() => localStorage.setItem('openseek.minimal_transcript', 'false'));
    await cloud.install();
    await cloud.goto();
    await cloud.open();
    const status = page.locator('main .run-status');
    await expect(status).toHaveText('Ready');
    await page.locator('#task').fill('Explain the input');
    await page.getByRole('button', { name: 'Send', exact: true }).click();
    const heartbeat = page.locator('.composer-running-text');
    const reasoning = page.locator('#transcript .activity-thinking');
    await expect(heartbeat).toHaveText('Thinking…');
    await expect(status).toHaveText('Running');
    await expect(status.locator('.run-dot')).toHaveClass(/pulse/);
    resume[0]();
    await expect(heartbeat).toContainText('Retrying');
    await expect(status).toHaveText('Step 3');
    resume[1]();
    await expect(heartbeat).toHaveText('Working · step 3');
    await expect(page.locator('#transcript .activity-thinking-live')).toHaveText('Partial reasoning');
    resume[2]();
    await expect(reasoning).toHaveText('Complete reasoning');
    await expect(page.locator('#transcript .activity-thinking-live')).toHaveCount(0);
    resume[3]();
    await expect(heartbeat).toHaveText('Working · step 3 (120 tokens)');
    await expect(page.locator('#transcript').getByText('Answer', { exact: true })).toHaveCount(1);
    resume[4]();
    await expect(page.locator('#transcript .streaming')).toHaveCount(0);
    await expect(reasoning).toHaveText('Complete reasoning');
    await expect(page.locator('.composer-context')).toContainText('Compacting');
    resume[5]();
    await expect(page.locator('.composer-context')).not.toContainText('Compacting');
    resume[6]();
    await expect(heartbeat).toHaveCount(0);
    await expect(status).toHaveText('Finished');
    await expect(status.locator('.run-dot')).toHaveClass('run-dot ok');
    await expect(page.getByRole('button', { name: 'Send', exact: true })).toBeDisabled();
    await expect(reasoning).toHaveCount(1);
    await expect(reasoning).toHaveText('Complete reasoning');
    await expect(page.locator('#transcript').getByText('Answer', { exact: true })).toHaveCount(1);
    expect(cloud.device.pageErrors).toEqual([]);
    expect(await page.evaluate(() => window.cloudUnhandledRejections)).toEqual([]);
  } finally {
    resume.forEach(resolve => resolve());
  }
});

test('Cloud title status uses recorded outcomes and marks archived history read-only', async ({ page }, testInfo) => {
  const cloud = new CloudHarness(page);
  cloud.histories.set(sessionA, { messages: [{
    task_id: 'context-task', kind: 'task_finished', created_at: 100,
    data: { status: 'incomplete', result: { status: 'context_yield', reason: 'context limit' } },
  }], generating: false });
  await cloud.install(); await cloud.goto(); await cloud.open();
  const status = page.locator('main .run-status');
  await expect(status).toHaveText('Context limit reached');
  await expect(status.locator('.run-dot')).toHaveClass('run-dot warn');
  await page.reload(); await cloud.open();
  await expect(status).toHaveText('Context limit reached');
  await page.screenshot({ path: testInfo.outputPath('cloud-title-context-limit.png'), fullPage: true });
  cloud.archived.add(sessionA);
  await page.reload();
  const archived = page.getByRole('button', { name: /^Archived chats \(/ });
  if (await archived.getAttribute('aria-expanded') === 'false') await archived.click();
  await cloud.row(sessionA).click();
  await expect(status).toHaveText('Archived conversation · Read only');
  await expect(status.locator('.run-dot')).not.toHaveClass(/pulse|ok|danger/);
  await expect(page.locator('#task')).toHaveCount(0);
  expect(cloud.postCount).toBe(0);
  expect(cloud.device.pageErrors).toEqual([]);
});

test('Cloud title status covers loading, service failure and first-send startup without local API configuration', async ({ page }, testInfo) => {
  const cloud = new CloudHarness(page);
  cloud.device.hostSettings.has_deepseek_key = false;
  let loaded, created;
  cloud.pauseHistory = new Promise(resolve => { loaded = resolve; });
  cloud.pauseCreate = new Promise(resolve => { created = resolve; });
  try {
    await cloud.install(); await cloud.goto();
    await cloud.row(sessionA).click();
    const status = page.locator('main .run-status');
    await expect(status).toHaveText('Loading conversation…');
    loaded();
    await expect(status).toHaveText('Ready');
    cloud.sendStatus = 503;
    cloud.sendErrorBody = 'server model credentials are not configured';
    await page.locator('#task').fill('Check the service');
    await page.getByRole('button', { name: 'Send', exact: true }).click();
    await expect(status).toHaveText('Error');
    await expect(status.locator('.run-dot')).toHaveClass('run-dot danger');
    await cloud.create();
    await expect(status).toHaveText('Ready');
    expect(cloud.requests.filter(request => request.method === 'POST' && request.path === '/v1/sessions')).toHaveLength(0);
    await page.screenshot({ path: testInfo.outputPath('cloud-title-ready.png'), fullPage: true });
    cloud.sendStatus = 202;
    await page.locator('#task').fill('First message');
    await page.getByRole('button', { name: 'Send', exact: true }).click();
    await expect(status).toHaveText('Starting');
    await expect(status.locator('.run-dot')).toHaveClass(/pulse/);
    created();
    await expect(status).toHaveText('Finished');
    expect(cloud.device.pageErrors).toEqual([]);
  } finally {
    loaded(); created();
  }
});

import { test, expect } from '@playwright/test';
import { CloudHarness } from './support/cloud_harness.js';

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
    await page.locator('#task').fill('Explain the input');
    await page.getByRole('button', { name: 'Send', exact: true }).click();
    const heartbeat = page.locator('.composer-running-text');
    const reasoning = page.locator('#transcript .activity-thinking');
    await expect(heartbeat).toHaveText('Thinking…');
    resume[0]();
    await expect(heartbeat).toContainText('Retrying');
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

import { test, expect } from '@playwright/test';
import { CloudHarness, sessionA, sessionB } from './support/cloud_harness.js';

const prediction = (source_sequence = 12, text = 'Commit the fix') => ({
  version: 1, source_sequence,
  outcome: { kind: 'completed', text, input_tokens: 40, output_tokens: 8 },
});

class CloudPredictionHarness extends CloudHarness {
  constructor(page) {
    super(page);
    this.history(sessionA, 12);
    this.history(sessionB, 32, prediction(32, 'Review the documentation'));
  }

  history(session, frontier, record = null) {
    this.histories.set(session, {
      generating: false, prediction: record,
      messages: [
        { task_id: 'fixture-task', kind: 'user', created_at: 100, data: { content: 'Fix the bug' }, engine_sequence: 1 },
        { task_id: 'fixture-task', kind: 'assistant_message', created_at: 101, data: { content: `Done at ${frontier}` } },
      ],
      session: { version: 1, id: session, events: [
        { sequence: 1, item: { kind: 'user', payload: { content: 'Fix the bug' } } },
        { sequence: frontier - 1, item: { kind: 'assistant', payload: { content: `Done at ${frontier}` } } },
        { sequence: frontier, item: { kind: 'terminal', payload: { kind: 'finished', message: `Done at ${frontier}` } } },
      ] },
    });
    if (!this.controlSnapshots.has(session)) {
      this.controlSnapshots.set(session, {
        session_id: session, task_id: 'fixture-task', seq: 900,
        data: { active_task_id: null, status: 'idle', paused: false, queue: [], steers: [], compacting: false, compact_queued: false },
      });
    }
  }

  async publish(record = prediction(), { session = sessionA, task = 'fixture-task', persist = true } = {}) {
    await expect.poll(() => this.page.evaluate(session => window.cloudSessionStreams.get(session)?.size || 0, session)).toBe(1);
    if (persist && record.outcome.kind === 'completed') {
      this.histories.set(session, { ...this.histories.get(session), prediction: record });
    }
    await this.emitSessionEvent(session, 'prediction_result', {
      source_sequence: record.source_sequence, outcome: record.outcome,
    }, { task });
  }

  assertNoPredictionRequests() {
    expect(this.requests.filter(request => /predict/.test(request.path))).toEqual([]);
    expect(this.device.requests.filter(request => /predict/.test(request.method))).toEqual([]);
    expect(this.device.pageErrors).toEqual([]);
  }
}

async function open(page) {
  const cloud = new CloudPredictionHarness(page);
  await cloud.install(); await cloud.goto(); await cloud.open();
  await expect(page.getByText('Done at 12', { exact: true }).first()).toBeVisible();
  return cloud;
}

test('Cloud shows native predictions and Tab fills the shared composer without sending', async ({ page }, testInfo) => {
  const cloud = await open(page);
  await cloud.publish();
  const input = page.locator('#task');
  await expect(input).toHaveAttribute('placeholder', 'Commit the fix');
  await expect(input).toHaveValue('');
  await input.focus();
  await page.screenshot({ path: testInfo.outputPath('cloud-composer-prediction.png') });
  await input.press('Shift+Tab');
  await expect(input).toHaveValue('');
  await input.focus(); await input.press('Tab');
  await expect(input).toHaveValue('Commit the fix');
  await expect(input).toBeFocused();
  expect(cloud.postCount).toBe(0);
  await input.fill('My own request');
  await expect(input).not.toHaveAttribute('placeholder', 'Commit the fix');
  await cloud.publish(prediction(12, 'Another suggestion'));
  await expect(input).toHaveValue('My own request');
  await input.fill('');
  await expect(input).toHaveAttribute('placeholder', 'Another suggestion');
  await input.fill('   ');
  await expect(input).not.toHaveAttribute('placeholder', 'Another suggestion');
  await input.press('Tab');
  await expect(input).toHaveValue('   ');
  await expect(input).not.toBeFocused();
  expect(cloud.postCount).toBe(0);
  cloud.assertNoPredictionRequests();
});

test('Cloud drops late predictions after the native log advances, independent of SSE and task IDs', async ({ page }) => {
  const cloud = await open(page);
  await cloud.publish();
  const input = page.locator('#task');
  await expect(input).toHaveAttribute('placeholder', 'Commit the fix');
  cloud.history(sessionA, 31);
  await cloud.emitSessionEvent(sessionA, 'task_started', {}, { task: 'next-task' });
  await expect(input).not.toHaveAttribute('placeholder', 'Commit the fix');
  await cloud.emitSessionEvent(sessionA, 'task_finished', { status: 'completed' }, { task: 'next-task' });
  await expect(page.getByText('Done at 31', { exact: true }).first()).toBeVisible();
  await cloud.publish(prediction(12, 'Stale suggestion'), { task: 'fixture-task', persist: false });
  await expect(input).not.toHaveAttribute('placeholder', 'Stale suggestion');
  await cloud.publish(prediction(31, 'Review the fix'), { task: 'fixture-task' });
  await expect(input).toHaveAttribute('placeholder', 'Review the fix');
  cloud.assertNoPredictionRequests();
});

test('Cloud restores native prediction metadata on session switches and reload without leaking drafts', async ({ page }) => {
  const cloud = await open(page);
  await cloud.publish();
  const input = page.locator('#task');
  await expect(input).toHaveAttribute('placeholder', 'Commit the fix');
  await input.fill('Unsent draft');
  await cloud.open(sessionB);
  await expect(input).toHaveValue('');
  await expect(input).toHaveAttribute('placeholder', 'Review the documentation');
  await cloud.open(sessionA);
  await expect(input).toHaveValue('Unsent draft');
  await expect(input).not.toHaveAttribute('placeholder', 'Commit the fix');
  await input.fill('');
  await expect(input).toHaveAttribute('placeholder', 'Commit the fix');
  await page.reload(); await cloud.open(sessionA);
  await expect(input).toHaveAttribute('placeholder', 'Commit the fix');
  await expect(input).toHaveValue('');
  cloud.assertNoPredictionRequests();
});

test('missing failed and obsolete Cloud predictions leave ordinary chat available', async ({ page }) => {
  const cloud = await open(page);
  const input = page.locator('#task');
  await expect(input).not.toHaveAttribute('placeholder', 'Commit the fix');
  await cloud.publish({ ...prediction(), outcome: { kind: 'failed', message: 'Unavailable' } });
  await expect(page.locator('.notification')).toHaveCount(0);
  await cloud.publish(prediction(11, 'Old suggestion'), { persist: false });
  await expect(input).not.toHaveAttribute('placeholder', 'Old suggestion');
  await input.fill('Continue normally');
  await expect(page.getByRole('button', { name: 'Send', exact: true })).toBeEnabled();
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect.poll(() => cloud.postCount).toBe(1);
  await expect(page.getByText('您好 🌙 — calculation complete.', { exact: true }).first()).toBeVisible();
  cloud.assertNoPredictionRequests();
});

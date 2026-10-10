import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

class PredictionHarness extends DesktopBrowserHarness {
  constructor(page) {
    super(page);
    this.predictionRecord = null;
    this.sessionEvents = [
      { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture' } } },
      { sequence: 2, item: { kind: 'terminal', payload: { kind: 'finished', message: 'The fix is ready and tests pass.' } } },
    ];
  }
  replyFor(request) {
    if (request.method === 'session.load') {
      return { ...super.replyFor(request), prediction: this.predictionRecord };
    }
    if (request.method === 'agent.predict') {
      const outcome = { kind: 'completed', text: 'Commit the fix', input_tokens: 40, output_tokens: 8 };
      this.predictionRecord = { version: 1, source_sequence: request.params.source_sequence, request_id: request.params.request_id, outcome };
      return { outcome };
    }
    if (request.method === 'agent.cancel_prediction') return true;
    return super.replyFor(request);
  }
  async finish() {
    this.notify('agent.started', { run_id: 'prediction-run', session: 'session-1', session_root: '/workspace/.openseek', model: 'deepseek-v4-flash', max_steps: 1000 });
    await expect(this.page.locator('#stop')).toBeVisible();
    this.notify('agent.finished', { run_id: 'prediction-run', status: 'finished', answer: 'The fix is ready and tests pass.', exit_code: 0 });
  }
}

test('accepting and clearing restores the suggestion without another request', async ({ page }) => {
  const app = new PredictionHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  await app.finish();
  const input = page.locator('#task');
  await expect(input).toHaveAttribute('placeholder', 'Commit the fix');
  await expect(input).toHaveValue('');
  await input.focus();
  await page.screenshot({ path: test.info().outputPath('composer-prediction.png') });
  await input.press('Shift+Tab');
  await expect(input).toHaveValue('');
  await input.focus();
  await input.press('Tab');
  await expect(input).toHaveValue('Commit the fix');
  await expect(input).toBeFocused();
  expect(app.requests.filter(r => r.method === 'agent.start')).toHaveLength(0);
  await input.fill('');
  await expect(input).toHaveAttribute('placeholder', 'Commit the fix');
  await input.fill('My own request');
  await expect(input).not.toHaveAttribute('placeholder', 'Commit the fix');
  await input.fill('');
  await expect(input).toHaveAttribute('placeholder', 'Commit the fix');
  await input.press('Tab');
  await expect(input).toHaveValue('Commit the fix');
  expect(app.requests.filter(r => r.method === 'agent.predict')).toHaveLength(1);
  expect(app.requests.filter(r => r.method === 'agent.start')).toHaveLength(0);
  expect(app.pageErrors).toEqual([]);
});

test('typing and clearing cancels an in-flight suggestion and ignores its late response', async ({ page }) => {
  const app = new PredictionHarness(page);
  app.rpcDelays.set('agent.predict', 1200);
  await app.install();
  await app.goto();
  await app.openSession();
  await app.finish();
  await expect.poll(() => app.requests.filter(r => r.method === 'agent.predict').length).toBe(1);
  const input = page.locator('#task');
  await input.fill('My own request');
  await input.fill('');
  await expect.poll(() => app.requests.filter(r => r.method === 'agent.cancel_prediction').length).toBe(1);
  await page.waitForTimeout(1500);
  await expect(input).toHaveValue('');
  await expect(input).not.toHaveAttribute('placeholder', 'Commit the fix');
  expect(app.requests.filter(r => r.method === 'agent.predict')).toHaveLength(1);
  expect(app.pageErrors).toEqual([]);
});

test('Escape leaves the suggestion available for Tab acceptance', async ({ page }) => {
  const app = new PredictionHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  await app.finish();
  const input = page.locator('#task');
  await expect(input).toHaveAttribute('placeholder', 'Commit the fix');
  await input.press('Escape');
  await expect(input).toHaveValue('');
  await expect(input).toHaveAttribute('placeholder', 'Commit the fix');
  await expect(page.locator('.composer-prediction-hint')).toHaveCount(0);
  await input.press('Tab');
  await expect(input).toHaveValue('Commit the fix');
  expect(app.requests.filter(r => r.method === 'agent.predict')).toHaveLength(1);
  expect(app.requests.filter(r => r.method === 'agent.start')).toHaveLength(0);
  expect(app.pageErrors).toEqual([]);
});


test('reopening the page restores the persisted suggestion without another model request', async ({ page }) => {
  const app = new PredictionHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  await app.finish();
  await expect(page.locator('#task')).toHaveAttribute('placeholder', 'Commit the fix');
  expect(app.requests.filter(r => r.method === 'agent.predict')).toHaveLength(1);
  await page.reload();
  await app.openSession();
  await expect(page.locator('#task')).toHaveAttribute('placeholder', 'Commit the fix');
  await expect(page.locator('#task')).toHaveValue('');
  await page.waitForTimeout(500);
  expect(app.requests.filter(r => r.method === 'agent.predict')).toHaveLength(1);
  expect(app.requests.filter(r => r.method === 'agent.start')).toHaveLength(0);
  expect(app.pageErrors).toEqual([]);
});

test('a persisted empty suggestion does not retry when reopened', async ({ page }) => {
  const app = new PredictionHarness(page);
  app.predictionRecord = { version: 1, source_sequence: 2, request_id: 'empty', outcome: { kind: 'completed', text: null, input_tokens: 40, output_tokens: 8 } };
  await app.install();
  await app.goto();
  await app.openSession();
  await page.waitForTimeout(500);
  await expect(page.locator('#task')).not.toHaveAttribute('placeholder', 'Commit the fix');
  expect(app.requests.filter(r => r.method === 'agent.predict')).toHaveLength(0);
  expect(app.pageErrors).toEqual([]);
});

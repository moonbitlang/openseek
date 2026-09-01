import { test, expect } from '@playwright/test';
import { VizBrowserHarness } from './support/viz_browser_harness.js';

// Exercise the mounted session viewer rather than serializing Rabbita's
// virtual DOM into a test-only string representation.
test('session viewer mounts log cards and interactive filters in Chromium', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  await viewer.install();
  await viewer.goto();

  await expect(page.locator('.session-root-name')).toHaveText('/workspace');
  await expect(page.locator('.session-item')).toContainText('Inspect the session viewer');
  await viewer.openSession();

  await expect(page.locator('.header-strip')).toContainText('session header loaded');
  await expect(page.locator('#seq-1.card.user')).toContainText('Inspect the session viewer');
  await expect(page.locator('.tool-call.tool-call-escalated')).toContainText('shell');
  await expect(page.locator('.card.tool.error.escalated')).toContainText('fixture failure');
  await expect(page.locator('.error-count')).toContainText('4 tool errors');
  await expect(page.locator('.escalated-count')).toContainText('1 escalated tool call');
  await expect(page.locator('.filter-bars')).toHaveCount(1);
  await expect(
    page.locator('.filter-bars > .error-bar, .filter-bars > .escalated-bar, .filter-bars > .build-error-bar'),
  ).toHaveCount(3);

  await page.getByRole('button', { name: 'Model view' }).click();
  await expect(page.getByRole('button', { name: 'Model view' })).toHaveClass(/active/);
  await page.getByRole('button', { name: 'Original' }).click();
  await expect(page.locator('.session-view')).toHaveClass(/show-original/);

  await page.getByRole('button', { name: 'Errors only', exact: true }).click();
  await expect(page.locator('.session-view')).toHaveClass(/errors-only/);
  await expect(page.getByRole('button', { name: 'Errors only: on' })).toBeVisible();
  expect(viewer.pageErrors).toEqual([]);
});

test('viewer renders plan evolution, goal markers, tool links, sub-runs, and MoonBit reads', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  await viewer.install();
  await viewer.goto();
  await viewer.openSession();
  await page.getByRole('button', { name: 'Raw log' }).click();

  const planCalls = page.locator('.tool-call').filter({ has: page.locator('.plan-args') });
  await expect(planCalls).toHaveCount(2);
  const updatedPlan = planCalls.nth(1);
  await expect(updatedPlan.locator('.plan-progress-count')).toHaveText('1/3');
  await expect(updatedPlan.locator('.step-delta-done')).toHaveText('done');
  await expect(updatedPlan.locator('.step-delta-started')).toHaveText('started');
  await expect(updatedPlan.locator('.step-delta-new')).toHaveText('new');

  await expect(page.locator('.card.runtime.goal-set')).toContainText(
    'Ship the Playwright migration',
  );
  await expect(page.locator('.card.runtime.goal-blocked')).toContainText(
    'waiting for fixture data',
  );
  await expect(page.locator('.card.runtime.goal-cleared')).toContainText(
    'standing goal cleared',
  );

  await expect(page.locator('#tool-call-1 .tool-link')).toHaveAttribute(
    'href',
    '#tool-result-1',
  );
  await expect(page.locator('#tool-result-1 .tool-link')).toHaveAttribute(
    'href',
    '#tool-call-1',
  );
  await expect(page.locator('.subrun-link')).toHaveAttribute('href', '#s=viz-1-sr-2');

  const readResult = page.locator('#tool-result-5');
  await expect(readResult.locator('.read-moonbit-output')).toBeAttached();
  await expect(readResult.locator('.read-moonbit-gutter')).toHaveText(['9', '10', '11']);
  await expect(readResult.locator('.mtk3').first()).toHaveText('fn');
  await expect(readResult.locator('.read-moonbit-status')).toContainText('start_line=9');

  await expect(page.locator('.step-scrubber [data-seq]')).toHaveCount(5);
  await expect(page.locator('.card-ts').first()).toHaveText('+0.0s');
  expect(viewer.pageErrors).toEqual([]);
});

test('viewer classifies mbtx failure stages and filters to build diagnostics', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  await viewer.install();
  await viewer.goto();
  await viewer.openSession();
  await page.getByRole('button', { name: 'Raw log' }).click();

  const buildCall = page.locator('.tool-call.tool-call-build-failed');
  const runtimeCall = page.locator('.tool-call.tool-call-run-failed');
  const singleShotCall = page.locator(
    '.tool-call.tool-call-failed:not(.tool-call-build-failed):not(.tool-call-run-failed)',
  ).filter({ hasText: 'single shot' });
  await expect(buildCall).toHaveCount(1);
  await expect(buildCall.locator('.tool-stage-build')).toHaveCount(0);
  await expect(runtimeCall).toHaveCount(1);
  await expect(runtimeCall.locator('.tool-stage-run')).toHaveText('runtime error');
  await expect(singleShotCall).toHaveCount(1);
  await expect(singleShotCall.locator('.tool-stage')).toHaveCount(0);

  const buildResult = page.locator('.card.tool.error.build-failed');
  const runtimeResult = page.locator('.card.tool.error').filter({ hasText: 'runtime trap' });
  await expect(buildResult.locator('.tool-flag.tool-stage-build')).toHaveText('🚩 build error');
  await expect(page.locator('.build-error-count')).toHaveText('🔨 1 build error');
  await expect(page.getByTitle('Scroll to the previous build error')).toBeVisible();
  await expect(page.getByTitle('Scroll to the next build error')).toBeVisible();

  await page.getByRole('button', { name: 'Build errors only', exact: true }).click();
  await expect(page.locator('.session-view')).toHaveClass(/build-errors-only/);
  await expect(buildCall).toBeVisible();
  await expect(buildResult).toBeVisible();
  await expect(runtimeCall).toBeHidden();
  await expect(runtimeResult).toBeHidden();
  await expect(page.locator('.card.tool.error.escalated')).toBeHidden();

  await page.getByRole('button', { name: 'Errors only', exact: true }).click();
  await expect(page.locator('.session-view')).toHaveClass(/errors-only/);
  await expect(page.locator('.session-view')).not.toHaveClass(/build-errors-only/);
  expect(viewer.pageErrors).toEqual([]);
});

test('clean mbtx activity exposes the build filter without inventing an error count', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  viewer.events = [
    JSON.stringify({
      version: 1,
      id: 'viz-1',
      system_prompt: 'You are a browser fixture.',
    }),
    JSON.stringify({
      sequence: 1,
      ts: 1_000,
      item: {
        kind: 'user',
        payload: { content: 'Inspect the session viewer' },
      },
    }),
    JSON.stringify({
      sequence: 2,
      ts: 2_000,
      item: {
        kind: 'assistant',
        payload: {
          content: '',
          tool_calls: [{
            id: 'mbtx-clean',
            name: 'mbtx',
            arguments: JSON.stringify({ source: 'fn main { println(42) }' }),
          }],
        },
      },
    }),
    JSON.stringify({
      sequence: 3,
      ts: 3_000,
      item: {
        kind: 'tool_result',
        payload: {
          tool_call_id: 'mbtx-clean',
          tool_name: 'mbtx',
          content: '42',
          is_error: false,
          brief: 'mbtx (exit=0)',
        },
      },
    }),
  ].join('\n') + '\n';
  await viewer.install();
  await viewer.goto();
  await viewer.openSession();

  await expect(page.getByRole('button', {
    name: 'Build errors only',
    exact: true,
  })).toBeVisible();
  await expect(page.locator('.build-error-count')).toHaveCount(0);
  await expect(page.getByTitle('Scroll to the previous build error')).toHaveCount(0);
  await expect(page.getByTitle('Scroll to the next build error')).toHaveCount(0);

  viewer.events = [
    JSON.stringify({
      version: 1,
      id: 'viz-1',
      system_prompt: 'You are a browser fixture.',
    }),
    JSON.stringify({
      sequence: 1,
      ts: 1_000,
      item: {
        kind: 'user',
        payload: { content: 'Inspect the session viewer' },
      },
    }),
  ].join('\n') + '\n';
  await viewer.goto();
  await viewer.openSession();
  await expect(page.getByRole('button', { name: /Build errors only/ })).toHaveCount(0);
  expect(viewer.pageErrors).toEqual([]);
});

test('a dropped session file replaces the served selection without another fetch', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  await viewer.install();
  await viewer.goto();
  const requestsBeforeDrop = viewer.apiRequests.length;

  const dataTransfer = await page.evaluateHandle(events => {
    const transfer = new DataTransfer();
    transfer.items.add(new File([events], 'dropped-session.jsonl', {
      type: 'application/x-ndjson',
    }));
    return transfer;
  }, viewer.events);
  await page.locator('.app').dispatchEvent('drop', { dataTransfer });

  await expect(page.locator('.header-id')).toHaveText('viz-1');
  await expect(page.locator('.header-meta')).toContainText(
    'dropped file: dropped-session.jsonl',
  );
  expect(viewer.apiRequests).toHaveLength(requestsBeforeDrop);
  expect(viewer.pageErrors).toEqual([]);
  await dataTransfer.dispose();
});

test('URL hash restores the session, raw view, and sequence scroll position', async ({ page }) => {
  await page.addInitScript(() => {
    window.__scrollTargets = [];
    const scrollIntoView = Element.prototype.scrollIntoView;
    Element.prototype.scrollIntoView = function (options) {
      window.__scrollTargets.push({ id: this.id, className: this.className });
      return scrollIntoView.call(this, options);
    };
  });
  const viewer = new VizBrowserHarness(page);
  await viewer.install();
  await viewer.goto('#s=viz-1&v=raw&seq=2');

  await expect(page.locator('.header-id')).toHaveText('viz-1');
  await expect(page.getByRole('button', { name: 'Raw log' })).toHaveClass(/active/);
  await expect.poll(() => page.evaluate(() => window.__scrollTargets))
    .toContainEqual(expect.objectContaining({ id: 'seq-2' }));
  await expect.poll(() => page.evaluate(() => {
    const params = new URLSearchParams(location.hash.slice(1));
    return {
      session: params.get('s'),
      view: params.get('v'),
      sequence: params.get('seq'),
    };
  })).toEqual({ session: 'viz-1', view: 'raw', sequence: '2' });
  expect(viewer.pageErrors).toEqual([]);
});

test('keyboard shortcuts navigate failures and unfold the nearest card', async ({ page }) => {
  await page.addInitScript(() => {
    window.__scrollTargets = [];
    const scrollIntoView = Element.prototype.scrollIntoView;
    Element.prototype.scrollIntoView = function (options) {
      window.__scrollTargets.push({ id: this.id, className: this.className });
      return scrollIntoView.call(this, options);
    };
  });
  const viewer = new VizBrowserHarness(page);
  await viewer.install();
  await viewer.goto();
  await viewer.openSession();

  await page.keyboard.press('n');
  await expect.poll(() => page.evaluate(() => window.__scrollTargets.length))
    .toBeGreaterThan(0);
  await expect.poll(() => page.evaluate(() =>
    window.__scrollTargets.at(-1)?.className || ''))
    .toContain('error');
  const jumpsAfterNext = await page.evaluate(() => window.__scrollTargets.length);
  await page.keyboard.press('p');
  await expect.poll(() => page.evaluate(() => window.__scrollTargets.length))
    .toBeGreaterThan(jumpsAfterNext);

  const openBefore = await page.locator('details[open]').count();
  await page.keyboard.press('u');
  await expect.poll(() => page.locator('details[open]').count())
    .toBeGreaterThan(openBefore);
  expect(viewer.pageErrors).toEqual([]);
});

test('standalone export reads embedded data and auto-opens in raw mode', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  await viewer.install({ standalone: true });
  await viewer.goto();

  await expect(page.locator('.header-id')).toHaveText('viz-1');
  await expect(page.getByRole('button', { name: 'Raw log' })).toHaveClass(/active/);
  await expect(page.locator('.card.user')).toContainText('Inspect the session viewer');
  expect(viewer.apiRequests).toEqual([]);
  expect(viewer.pageErrors).toEqual([]);
});

test('Light, Dark, and System theme controls apply their browser palettes', async ({ page }) => {
  await page.emulateMedia({ colorScheme: 'dark' });
  const viewer = new VizBrowserHarness(page);
  await viewer.install();
  await viewer.goto();

  await page.getByRole('button', { name: 'Light' }).click();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'light');
  const lightBackground = await page.evaluate(() =>
    getComputedStyle(document.documentElement).getPropertyValue('--bg'));

  await page.getByRole('button', { name: 'Dark' }).click();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
  const darkBackground = await page.evaluate(() =>
    getComputedStyle(document.documentElement).getPropertyValue('--bg'));
  expect(darkBackground).not.toBe(lightBackground);

  await page.getByRole('button', { name: 'System' }).click();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'system');
  await expect(page.getByRole('button', { name: 'System' })).toHaveClass(/active/);
  const systemBackground = await page.evaluate(() =>
    getComputedStyle(document.documentElement).getPropertyValue('--bg'));
  expect(systemBackground).toBe(darkBackground);
  expect(viewer.pageErrors).toEqual([]);
});

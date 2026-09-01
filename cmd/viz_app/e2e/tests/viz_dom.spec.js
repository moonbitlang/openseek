import { test, expect } from '@playwright/test';
import { VizBrowserHarness } from './support/viz_browser_harness.js';

// Exercise the mounted session viewer through its controls. Fixture strings
// identify rows, but the assertions below verify the resulting browser state.
test('session filters and argument modes change the mounted cards', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  await viewer.install();
  await viewer.goto();
  await expect(page.locator('.session-item')).toHaveCount(1);
  await viewer.openSession();
  await page.getByRole('button', { name: 'Raw log' }).click();

  const userCard = page.locator('#seq-1.card.user');
  const escalatedCall = page.locator('.tool-call.tool-call-escalated');
  const escalatedResult = page.locator('.card.tool.error.escalated');
  const unrelatedError = page.locator('.card.tool.error.build-failed');
  await expect(page.locator('.card.tool.error')).toHaveCount(4);
  await expect(escalatedCall).toHaveCount(1);
  await expect(escalatedResult).toHaveCount(1);
  await expect(page.locator('.filter-bars')).toHaveCount(1);
  await expect(
    page.locator('.filter-bars > .error-bar, .filter-bars > .escalated-bar, .filter-bars > .build-error-bar'),
  ).toHaveCount(3);

  await page.getByRole('button', { name: 'Errors only', exact: true }).click();
  await expect(userCard).toBeHidden();
  await expect(escalatedResult).toBeVisible();
  await page.getByRole('button', { name: 'Errors only: on' }).click();
  await expect(userCard).toBeVisible();

  await page.getByRole('button', { name: 'Escalated only', exact: true }).click();
  await expect(escalatedCall).toBeVisible();
  await expect(escalatedResult).toBeVisible();
  await expect(unrelatedError).toBeHidden();
  await page.getByRole('button', { name: 'Escalated only: on' }).click();
  await expect(unrelatedError).toBeVisible();

  await escalatedCall.locator('summary').click();
  const renderedArguments = escalatedCall.locator('.tool-call-args-rendered');
  const originalArguments = escalatedCall.locator('.tool-call-args-original');
  await expect(renderedArguments).toBeVisible();
  await expect(originalArguments).toBeHidden();
  await page.getByRole('button', { name: 'Original' }).click();
  await expect(renderedArguments).toBeHidden();
  await expect(originalArguments).toBeVisible();
  await page.getByRole('button', { name: 'Rendered' }).click();
  await expect(renderedArguments).toBeVisible();
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
  const completedStep = updatedPlan.locator('.plan-step').filter({ hasText: 'Inspect DOM' });
  const activeStep = updatedPlan.locator('.plan-step').filter({ hasText: 'Run browser tests' });
  const addedStep = updatedPlan.locator('.plan-step').filter({ hasText: 'Review layout' });
  await expect(completedStep).toHaveClass(/completed/);
  await expect(completedStep.locator('.step-delta-done')).toHaveCount(1);
  await expect(activeStep).toHaveClass(/in_progress/);
  await expect(activeStep.locator('.step-delta-started')).toHaveCount(1);
  await expect(addedStep).toHaveClass(/pending/);
  await expect(addedStep.locator('.step-delta-new')).toHaveCount(1);

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

test('tool pairing links only unique calls and heals a dangling call only in model view', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  viewer.events = viewer.eventLog([
    {
      sequence: 1,
      item: {
        kind: 'assistant',
        payload: {
          content: '',
          tool_calls: [
            { id: 'unique', name: 'read', arguments: '{"path":"unique.txt"}' },
            { id: '', name: 'noop', arguments: '{}' },
            { id: 'dup', name: 'duplicate-a', arguments: '{}' },
            { id: 'dup', name: 'duplicate-b', arguments: '{}' },
            { id: 'ambiguous', name: 'read', arguments: '{"path":"ambiguous.txt"}' },
          ],
        },
      },
    },
    {
      sequence: 2,
      item: {
        kind: 'tool_result',
        payload: {
          tool_call_id: 'unique',
          tool_name: 'read',
          content: 'unique result',
          is_error: false,
        },
      },
    },
    {
      sequence: 3,
      item: {
        kind: 'tool_result',
        payload: {
          tool_call_id: 'orphan',
          tool_name: 'ghost',
          content: 'orphan result',
          is_error: false,
        },
      },
    },
    {
      sequence: 4,
      item: {
        kind: 'tool_result',
        payload: {
          tool_call_id: 'ambiguous',
          tool_name: 'read',
          content: 'ambiguous result one',
          is_error: false,
        },
      },
    },
    {
      sequence: 5,
      item: {
        kind: 'tool_result',
        payload: {
          tool_call_id: 'ambiguous',
          tool_name: 'read',
          content: 'ambiguous result two',
          is_error: false,
        },
      },
    },
  ]);
  await viewer.install();
  await viewer.goto();
  await viewer.openSession();
  await page.getByRole('button', { name: 'Raw log' }).click();

  await expect(page.locator('#tool-call-1 .tool-link')).toHaveAttribute(
    'href',
    '#tool-result-1',
  );
  await expect(page.locator('#tool-result-1 .tool-link')).toHaveAttribute(
    'href',
    '#tool-call-1',
  );
  await expect(page.locator('.tool-link')).toHaveCount(2);
  await expect(page.locator('[id^="tool-call-"]')).toHaveCount(1);
  await expect(page.locator('[id^="tool-result-"]')).toHaveCount(1);
  await expect(page.locator('.card.tool').filter({ hasText: 'orphan result' })
    .locator('.tool-link')).toHaveCount(0);
  await expect(page.locator('.card.tool').filter({ hasText: 'ambiguous result one' })
    .locator('.tool-link')).toHaveCount(0);

  // Reload a minimal dangling call. Raw has no result to link to, while the
  // model projection repairs the interrupted exchange with a synthetic row.
  viewer.events = viewer.eventLog([
    {
      sequence: 1,
      item: {
        kind: 'assistant',
        payload: {
          content: '',
          tool_calls: [{
            id: 'dangling',
            name: 'read',
            arguments: '{"path":"dangling.txt"}',
          }],
        },
      },
    },
    {
      sequence: 2,
      item: {
        kind: 'terminal',
        payload: { kind: 'aborted', message: 'stopped' },
      },
    },
  ]);
  await viewer.goto();
  await viewer.openSession();
  await page.getByRole('button', { name: 'Raw log' }).click();
  await expect(page.locator('.tool-link')).toHaveCount(0);
  await page.getByRole('button', { name: 'Model view' }).click();
  await expect(page.locator('#tool-call-1 .tool-link')).toHaveAttribute(
    'href',
    '#tool-result-1',
  );
  await expect(page.locator('#tool-result-1 .tool-link')).toHaveAttribute(
    'href',
    '#tool-call-1',
  );
  expect(viewer.pageErrors).toEqual([]);
});

test('plan history skips rejected baselines and names reopened and paused steps', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  const planA = JSON.stringify({
    steps: [
      { title: 'step a', status: 'in_progress' },
      { title: 'step b', status: 'pending' },
    ],
  });
  const rejected = JSON.stringify({
    steps: [
      { title: 'step a', status: 'in_progress' },
      { title: 'phantom step', status: 'in_progress' },
      { title: 'step b', status: 'pending' },
    ],
  });
  const planC = JSON.stringify({
    steps: [
      { title: 'step a', status: 'completed' },
      { title: 'step b', status: 'in_progress' },
    ],
  });
  const planD = JSON.stringify({
    steps: [
      { title: 'step a', status: 'in_progress' },
      { title: 'step b', status: 'pending' },
    ],
  });
  const events = [];
  let sequence = 1;
  for (const [id, arguments_, result] of [
    ['p1', planA, { content: 'accepted a', is_error: false }],
    ['p2', rejected, { content: 'rejected phantom', is_error: true }],
    ['p3', planC, { content: 'accepted c', is_error: false }],
    ['p4', planD, { content: 'accepted d', is_error: false }],
  ]) {
    events.push({
      sequence,
      item: {
        kind: 'assistant',
        payload: {
          content: '',
          tool_calls: [{ id, name: 'plan', arguments: arguments_ }],
        },
      },
    });
    sequence += 1;
    events.push({
      sequence,
      item: {
        kind: 'tool_result',
        payload: {
          tool_call_id: id,
          tool_name: 'plan',
          content: result.content,
          is_error: result.is_error,
        },
      },
    });
    sequence += 1;
  }
  events.push({
    sequence,
    item: {
      kind: 'assistant',
      payload: {
        content: '',
        tool_calls: [{
          id: 'malformed',
          name: 'plan',
          arguments: JSON.stringify({
            steps: 'not an array',
            marker: 'malformed-browser-plan',
          }),
        }],
      },
    },
  });
  sequence += 1;
  events.push({
    sequence,
    item: {
      kind: 'assistant',
      payload: {
        content: '',
        tool_calls: [
          {
            id: 'duplicate-plan',
            name: 'plan',
            arguments: JSON.stringify({
              steps: [{ title: 'duplicate baseline', status: 'in_progress' }],
            }),
          },
          {
            id: 'duplicate-plan',
            name: 'plan',
            arguments: JSON.stringify({
              steps: [{ title: 'duplicate baseline', status: 'completed' }],
            }),
          },
        ],
      },
    },
  });
  viewer.events = viewer.eventLog(events);
  await viewer.install();
  await viewer.goto();
  await viewer.openSession();
  await page.getByRole('button', { name: 'Raw log' }).click();

  const completedPlan = page.locator('#tool-call-3');
  const reopenedPlan = page.locator('#tool-call-4');
  const completedA = completedPlan.locator('.plan-step').filter({ hasText: 'step a' });
  const startedB = completedPlan.locator('.plan-step').filter({ hasText: 'step b' });
  const reopenedA = reopenedPlan.locator('.plan-step').filter({ hasText: 'step a' });
  const pausedB = reopenedPlan.locator('.plan-step').filter({ hasText: 'step b' });
  await expect(completedA).toHaveClass(/completed/);
  await expect(completedA.locator('.step-delta-done')).toHaveCount(1);
  await expect(startedB).toHaveClass(/in_progress/);
  await expect(startedB.locator('.step-delta-started')).toHaveCount(1);
  await expect(reopenedA).toHaveClass(/in_progress/);
  await expect(reopenedA.locator('.step-delta-reopened')).toHaveCount(1);
  await expect(pausedB).toHaveClass(/pending/);
  await expect(pausedB.locator('.step-delta-paused')).toHaveCount(1);
  await expect(page.locator('.step-delta-dropped')).toHaveCount(0);
  const rejectedCall = page.locator('.tool-call').filter({ hasText: 'phantom step' });
  await expect(rejectedCall.locator('.plan-args')).toHaveCount(0);
  await rejectedCall.locator('summary').click();
  await expect(rejectedCall.locator('.arg-key').first()).toHaveText('steps');
  const malformed = page.locator('.tool-call').filter({ hasText: 'malformed-browser-plan' });
  await malformed.locator('summary').click();
  await expect(malformed.locator('.arg-key')).toHaveText(['steps', 'marker']);
  const duplicatePlans = page.locator('.tool-call').filter({ hasText: 'duplicate baseline' });
  await expect(duplicatePlans).toHaveCount(2);
  await expect(duplicatePlans.locator('.step-delta')).toHaveCount(0);
  expect(viewer.pageErrors).toEqual([]);
});

test('viewer prefetches and namespaces a persisted subrun transcript', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  viewer.events = viewer.eventLog([
    {
      sequence: 1,
      item: { kind: 'user', payload: { content: 'Inspect the session viewer' } },
    },
    {
      sequence: 2,
      item: {
        kind: 'assistant',
        payload: {
          content: '',
          tool_calls: [{
            id: 'explore-parent',
            name: 'explore',
            arguments: '{"query":"find the renderer"}',
          }],
        },
      },
    },
    {
      sequence: 3,
      item: {
        kind: 'tool_result',
        payload: {
          tool_call_id: 'explore-parent',
          tool_name: 'explore',
          content: 'Answer: use the child transcript.',
          is_error: false,
          brief: 'explore sr-2 (1 citation(s), 7 step(s))',
        },
      },
    },
    {
      sequence: 4,
      item: { kind: 'terminal', payload: { kind: 'finished', message: 'done' } },
    },
  ]);
  const childId = 'viz-1-sr-2';
  viewer.extraSessionRows = [{
    key: childId,
    id: childId,
    root_label: '/workspace/.openseek',
    is_marker: true,
    last_active: 2,
    first_prompt: 'Child renderer inspection',
  }];
  viewer.childEvents.set(childId, viewer.eventLog([
    {
      sequence: 1,
      item: { kind: 'user', payload: { content: 'Child question' } },
    },
    {
      sequence: 2,
      item: { kind: 'assistant', payload: { content: 'Child answer' } },
    },
    {
      sequence: 3,
      item: { kind: 'terminal', payload: { kind: 'finished', message: 'submitted' } },
    },
  ], { id: childId, systemPrompt: 'You are the child fixture.' }));
  await viewer.install();
  await viewer.goto();
  await viewer.openSession();
  await page.getByRole('button', { name: 'Raw log' }).click();

  await expect.poll(() => viewer.apiRequests.some(url =>
    new URL(url).pathname === `/api/sessions/${childId}`)).toBe(true);
  await expect(page.locator('.subrun-link')).toHaveAttribute('href', '#s=viz-1-sr-2');
  const nested = page.locator('.subrun-transcript');
  await expect(nested).toHaveCount(1);
  await expect(nested.locator('.subrun-transcript-label')).toContainText(
    'Subagent transcript · viz-1-sr-2',
  );
  await expect(page.locator('#viz-1-sr-2--seq-1')).toContainText('Child question');
  await expect(page.locator('#seq-1')).toHaveCount(1);
  await page.getByRole('button', { name: 'Model view' }).click();
  await expect(page.locator('.subrun-transcript')).toHaveCount(0);
  await expect(page.locator('.subrun-link')).toHaveAttribute('href', '#s=viz-1-sr-2');
  expect(viewer.pageErrors).toEqual([]);
});

test('raw log shows total-second offsets and omits chips for unstamped events', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  viewer.events = viewer.eventLog([
    {
      sequence: 1,
      ts: 1_000,
      item: { kind: 'user', payload: { content: 'Inspect the session viewer' } },
    },
    {
      sequence: 2,
      ts: 2_250,
      item: { kind: 'runtime_notice', payload: { content: 'working' } },
    },
    {
      sequence: 3,
      ts: 126_500,
      item: { kind: 'terminal', payload: { kind: 'finished', message: 'done' } },
    },
  ]);
  await viewer.install();
  await viewer.goto();
  await viewer.openSession();
  await page.getByRole('button', { name: 'Raw log' }).click();

  await expect(page.locator('.card-ts')).toHaveText(['+0.0s', '+1.2s', '+125.5s']);
  await expect(page.locator('.turn-summary')).toContainText('· 125.5s');

  viewer.events = viewer.eventLog([
    {
      sequence: 1,
      item: { kind: 'user', payload: { content: 'Inspect the session viewer' } },
    },
    {
      sequence: 2,
      item: { kind: 'terminal', payload: { kind: 'finished', message: 'done' } },
    },
  ]);
  await viewer.goto();
  await viewer.openSession();
  await page.getByRole('button', { name: 'Raw log' }).click();
  await expect(page.locator('.card-ts')).toHaveCount(0);
  await expect(page.locator('.turn-summary')).not.toContainText('· 125.5s');
  expect(viewer.pageErrors).toEqual([]);
});

test('viewer classifies mbtx failure stages and filters to build diagnostics', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  await viewer.install();
  await viewer.goto();
  await viewer.openSession();
  await page.getByRole('button', { name: 'Raw log' }).click();

  const buildCall = page.locator('.tool-call').filter({ hasText: 'compile_error' });
  const runtimeCall = page.locator('.tool-call').filter({ hasText: 'abort("runtime")' });
  const singleShotCall = page.locator('.tool-call').filter({ hasText: 'single shot' });
  await expect(buildCall).toHaveClass(/tool-call-build-failed/);
  await expect(buildCall.locator('.tool-stage-build')).toHaveCount(0);
  await expect(runtimeCall).toHaveClass(/tool-call-run-failed/);
  await expect(runtimeCall.locator('.tool-stage-run')).toHaveCount(1);
  await expect(singleShotCall).toHaveClass(/tool-call-failed/);
  await expect(singleShotCall).not.toHaveClass(/tool-call-build-failed|tool-call-run-failed/);
  await expect(singleShotCall.locator('.tool-stage')).toHaveCount(0);

  const buildResult = page.locator('.card.tool.error').filter({ hasText: 'type mismatch' });
  const runtimeResult = page.locator('.card.tool.error').filter({ hasText: 'runtime trap' });
  await expect(buildResult).toHaveClass(/build-failed/);
  await expect(buildResult.locator('.tool-flag.tool-stage-build')).toHaveCount(1);
  await expect(runtimeResult).not.toHaveClass(/build-failed/);
  await expect(page.locator('.build-error-count')).toHaveCount(1);
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

  await expect(page.locator('.header-meta')).toContainText(
    'dropped file: dropped-session.jsonl',
  );
  await expect(page.locator('.session-view .card')).not.toHaveCount(0);
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

  await expect(page.getByRole('button', { name: 'Raw log' })).toHaveClass(/active/);
  await expect(page.locator('.session-view .card')).not.toHaveCount(0);
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

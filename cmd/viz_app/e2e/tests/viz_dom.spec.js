import { test, expect } from '@playwright/test';
import { VizBrowserHarness } from './support/viz_browser_harness.js';

test('session filters and argument modes change what the reader can see', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  await viewer.install();
  await viewer.goto();
  await viewer.openSession();
  await page.getByRole('button', { name: 'Raw log' }).click();

  // Scoped to the card: the prompt rail's hover preview repeats the prompt
  // text, and this test is about the card the filters show and hide.
  const userMessage = page.locator('.session-view .card')
    .getByText('Inspect the session viewer', { exact: true });
  const shellCall = page.locator('details.tool-call').filter({ hasText: 'moon test' });
  const shellFailure = page.locator('details.card').filter({ hasText: 'fixture failure' });
  const buildFailure = page.locator('details.card').filter({ hasText: 'type mismatch' });

  await page.getByRole('button', { name: 'Errors only', exact: true }).click();
  await expect(userMessage).toBeHidden();
  await expect(shellFailure).toBeVisible();
  await page.getByRole('button', { name: 'Errors only: on' }).click();
  await expect(userMessage).toBeVisible();

  await page.getByRole('button', { name: 'Escalated only', exact: true }).click();
  await expect(shellCall).toBeVisible();
  await expect(shellFailure).toBeVisible();
  await expect(buildFailure).toBeHidden();
  await page.getByRole('button', { name: 'Escalated only: on' }).click();

  // The two modes are useful only if they expose different user-visible
  // representations of the same arguments.
  await shellCall.locator('summary').click();
  await expect(shellCall.getByText('moon test', { exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Original' }).click();
  await expect(shellCall.getByText(/"cmd":\s*"moon test"/)).toBeVisible();
  await page.getByRole('button', { name: 'Rendered' }).click();
  await expect(shellCall.getByText('moon test', { exact: true })).toBeVisible();
  expect(viewer.pageErrors).toEqual([]);
});

test('build-error filter separates build diagnostics from other failures', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  await viewer.install();
  await viewer.goto();
  await viewer.openSession();
  await page.getByRole('button', { name: 'Raw log' }).click();

  const buildFailure = page.locator('details.card').filter({ hasText: 'type mismatch' });
  const runtimeFailure = page.locator('details.card').filter({ hasText: 'runtime trap' });
  const shellFailure = page.locator('details.card').filter({ hasText: 'fixture failure' });
  await page.getByRole('button', { name: 'Build errors only', exact: true }).click();
  await expect(buildFailure).toBeVisible();
  await expect(runtimeFailure).toBeHidden();
  await expect(shellFailure).toBeHidden();

  await page.getByRole('button', { name: 'Errors only', exact: true }).click();
  await expect(buildFailure).toBeVisible();
  await expect(runtimeFailure).toBeVisible();
  await expect(shellFailure).toBeVisible();
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

  await expect(page.getByText(/dropped file: dropped-session\.jsonl/)).toBeVisible();
  await expect(page.locator('.card').getByText('Running the browser fixture.', { exact: true }))
    .toBeVisible();
  expect(viewer.apiRequests).toHaveLength(requestsBeforeDrop);
  expect(viewer.pageErrors).toEqual([]);
  await dataTransfer.dispose();
});

test('a subrun link opens the child session', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  viewer.sessionId = 'viz parent';
  viewer.events = viewer.eventLog([
    {
      sequence: 1,
      item: { kind: 'user', payload: { content: 'Delegate the investigation' } },
    },
    {
      sequence: 2,
      item: {
        kind: 'assistant',
        payload: {
          content: '',
          tool_calls: [{
            id: 'review-parent',
            name: 'review',
            arguments: '{"focus":"find the renderer"}',
          }],
        },
      },
    },
    {
      sequence: 3,
      item: {
        kind: 'tool_result',
        payload: {
          tool_call_id: 'review-parent',
          tool_name: 'review',
          content: 'Subagent completed.',
          is_error: false,
          brief: 'review sr-2 (completed)',
        },
      },
    },
  ], { id: viewer.sessionId });
  const childId = 'viz parent-sr-2';
  viewer.extraSessionRows = [{
    key: childId,
    id: childId,
    root_label: '/workspace/.openseek',
    is_marker: true,
    last_active: 1,
    first_prompt: 'Child investigation',
  }];
  viewer.childEvents.set(childId, viewer.eventLog([
    {
      sequence: 1,
      item: { kind: 'user', payload: { content: 'Child investigation' } },
    },
    {
      sequence: 2,
      item: {
        kind: 'assistant',
        payload: { content: 'The child session is open.', tool_calls: [] },
      },
    },
  ], { id: childId }));
  await viewer.install();
  await viewer.goto();
  await viewer.openSession();
  await page.getByRole('button', { name: 'Raw log' }).click();

  // Wait for the child prefetch to finish so its parent re-render cannot race
  // the user click that this test exercises.
  await page.locator('.subrun-transcript').waitFor({ state: 'attached' });
  await page.getByRole('link', { name: '↳ subagent' }).click();
  await expect(page.locator('.header-id')).toHaveText(childId);
  await expect(page.getByText('The child session is open.', { exact: true }))
    .toBeVisible();
  expect(viewer.pageErrors).toEqual([]);
});

test('URL hash restores a session and scrolls to its requested event', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  viewer.events = viewer.eventLog(Array.from({ length: 24 }, (_, index) => ({
    sequence: index + 1,
    item: {
      kind: 'assistant',
      payload: {
        content: index === 23 ? 'Final hash target' : `Earlier event ${index + 1}`,
        tool_calls: [],
      },
    },
  })));
  await viewer.install();
  await viewer.goto('#s=viz-1&v=raw&seq=24');

  await expect(page.locator('.header-id')).toHaveText(viewer.sessionId);
  await expect(page.locator('.raw-log')).toBeVisible();
  await expect(page.getByText('Final hash target', { exact: true })).toBeInViewport();
  expect(viewer.pageErrors).toEqual([]);
});

test('keyboard shortcuts navigate between failures', async ({ page }) => {
  await page.setViewportSize({ width: 900, height: 500 });
  const viewer = new VizBrowserHarness(page);
  await viewer.install();
  await viewer.goto();
  await viewer.openSession();
  await page.getByRole('button', { name: 'Raw log' }).click();

  await page.keyboard.press('n');
  await expect(page.locator('details.card').filter({ hasText: 'type mismatch' }))
    .toBeInViewport();
  await page.keyboard.press('p');
  await expect(page.locator('details.card').filter({ hasText: 'fixture failure' }))
    .toBeInViewport();
  expect(viewer.pageErrors).toEqual([]);
});

test('a tool pairing link brings its distant result into view', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  viewer.events = viewer.eventLog([
    {
      sequence: 1,
      item: {
        kind: 'assistant',
        payload: {
          content: '',
          tool_calls: [{
            id: 'long-call',
            name: 'shell',
            arguments: '{"cmd":"moon test"}',
          }],
        },
      },
    },
    ...Array.from({ length: 36 }, (_, index) => ({
      sequence: index + 2,
      item: {
        kind: 'runtime_notice',
        payload: { content: `Progress update ${index + 1}` },
      },
    })),
    {
      sequence: 38,
      item: {
        kind: 'tool_result',
        payload: {
          tool_call_id: 'long-call',
          tool_name: 'shell',
          content: 'done',
          is_error: false,
        },
      },
    },
  ]);
  await viewer.install();
  await viewer.goto();
  await viewer.openSession();
  await page.getByRole('button', { name: 'Raw log' }).click();

  const pairingLinks = page.getByRole('link', { name: 'call 1' });
  await expect(pairingLinks).toHaveCount(2);
  await expect(pairingLinks.first()).toBeInViewport();
  await expect(pairingLinks.last()).not.toBeInViewport();
  await pairingLinks.first().click();
  await expect(pairingLinks.last()).toBeInViewport({ ratio: 1 });
  expect(viewer.pageErrors).toEqual([]);
});

test('keyboard shortcut unfolds the nearest card', async ({ page }) => {
  await page.setViewportSize({ width: 900, height: 900 });
  const viewer = new VizBrowserHarness(page);
  viewer.events = viewer.eventLog([
    {
      sequence: 1,
      item: { kind: 'user', payload: { content: 'Unfold the command' } },
    },
    {
      sequence: 2,
      item: {
        kind: 'assistant',
        payload: {
          content: '',
          tool_calls: [{
            id: 'unfold-command',
            name: 'shell',
            arguments: '{"cmd":"hidden command marker"}',
          }],
        },
      },
    },
  ]);
  await viewer.install();
  await viewer.goto();
  await viewer.openSession();
  await page.getByRole('button', { name: 'Raw log' }).click();
  const command = page.locator('details.tool-call')
    .filter({ hasText: 'hidden command marker' });
  await expect(command.getByText(/"cmd":\s*"hidden command marker"/)).toBeHidden();
  await expect(command).toBeInViewport();
  await page.keyboard.press('u');
  await expect(command.getByText('hidden command marker', { exact: true })).toBeVisible();
  expect(viewer.pageErrors).toEqual([]);
});

test('standalone export reads embedded data without session requests', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  await viewer.install({ standalone: true });
  await viewer.goto();

  await expect(page.locator('.card').getByText('Running the browser fixture.', { exact: true }))
    .toBeVisible();
  expect(viewer.apiRequests).toEqual([]);
  expect(viewer.pageErrors).toEqual([]);
});

test('theme controls change the rendered palette and follow the system theme', async ({ page }) => {
  await page.emulateMedia({ colorScheme: 'dark' });
  const viewer = new VizBrowserHarness(page);
  await viewer.install();
  await viewer.goto();
  // Theme changes animate in production. Removing only the transition keeps
  // this test about the final painted palette rather than an intermediate frame.
  await page.addStyleTag({ content: '* { transition: none !important; }' });

  await page.getByRole('button', { name: 'Light' }).click();
  const lightBackground = await page.evaluate(() =>
    getComputedStyle(document.body).backgroundColor);

  await page.getByRole('button', { name: 'Dark' }).click();
  const darkBackground = await page.evaluate(() =>
    getComputedStyle(document.body).backgroundColor);
  expect(darkBackground).not.toBe(lightBackground);

  await page.getByRole('button', { name: 'System' }).click();
  const systemBackground = await page.evaluate(() =>
    getComputedStyle(document.body).backgroundColor);
  expect(systemBackground).toBe(darkBackground);
  expect(viewer.pageErrors).toEqual([]);
});

test('the raised user card marks only the prompts a person typed', async ({ page }) => {
  const continuePrompt = 'Continue working toward the standing goal. When it is fully met, record\n'
    + 'that by calling the goal tool with status "met".';
  const viewer = new VizBrowserHarness(page);
  viewer.events = viewer.eventLog([
    { sequence: 1, item: { kind: 'user', payload: { content: 'Ship the viewer change' } } },
    {
      sequence: 2,
      item: { kind: 'assistant', payload: { content: 'On it.', tool_calls: [] } },
    },
    { sequence: 3, item: { kind: 'user', payload: { content: 'Also update the docs' } } },
    { sequence: 4, item: { kind: 'terminal', payload: { kind: 'finished', message: 'Done.' } } },
    { sequence: 5, item: { kind: 'user', payload: { content: continuePrompt } } },
    {
      sequence: 6,
      item: { kind: 'terminal', payload: { kind: 'finished', message: 'Done again.' } },
    },
  ]);
  await viewer.install();
  await viewer.goto();
  await viewer.openSession();
  await page.getByRole('button', { name: 'Raw log' }).click();

  // The opening prompt and the mid-turn steer are the user's; the engine's
  // relaunch prompt is not, and must not wear the same raised card.
  await expect(page.locator('.card.user.typed')).toHaveCount(2);
  await expect(page.locator('.card.user.typed').first()).toContainText('You');
  await expect(page.locator('.card.user.auto-continue')).toHaveCount(1);
  await expect(page.locator('.card.user.auto-continue')).toContainText('Auto-continue');

  // The raised card is elevation, fill, and bold type, not only a caption:
  // that is what a reader skimming a long log actually sees. Both cards are
  // measured in one evaluate so a re-render between two measurements cannot
  // split the pair.
  const layout = await page.evaluate(() => {
    const style = selector => getComputedStyle(document.querySelector(selector));
    return {
      typedFill: style('.card.user.typed').backgroundColor,
      plainFill: style('.card.user.auto-continue').backgroundColor,
      typedShadow: style('.card.user.typed').boxShadow,
      plainShadow: style('.card.user.auto-continue').boxShadow,
      typedWeight: style('.card.user.typed .content').fontWeight,
      plainWeight: style('.card.user.auto-continue .content').fontWeight,
    };
  });
  expect(layout.typedFill).not.toBe(layout.plainFill);
  expect(layout.typedShadow).not.toBe('none');
  expect(layout.plainShadow).toBe('none');
  expect(Number(layout.typedWeight)).toBeGreaterThan(Number(layout.plainWeight));

  // A collapsed turn still reports the steer it hides.
  await expect(page.locator('.turn-steer-badge')).toHaveCount(1);
  await expect(page.locator('.turn-steer-badge')).toContainText('1 steer');
  expect(viewer.pageErrors).toEqual([]);
});

test('the prompt rail previews typed prompts and jumps to them', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  viewer.events = viewer.eventLog([
    {
      sequence: 1,
      ts: 1788316865000,
      item: { kind: 'user', payload: { content: 'Ship the viewer change' } },
    },
    {
      sequence: 2,
      item: { kind: 'assistant', payload: { content: 'On it.', tool_calls: [] } },
    },
    ...Array.from({ length: 30 }, (_, index) => ({
      sequence: index + 3,
      item: {
        kind: 'runtime_notice',
        payload: { content: `Progress update ${index + 1}` },
      },
    })),
    { sequence: 33, item: { kind: 'user', payload: { content: 'Also update the docs' } } },
    {
      sequence: 34,
      item: {
        kind: 'tool_result',
        payload: {
          tool_call_id: 'late-call',
          tool_name: 'shell',
          content: 'boom',
          is_error: true,
        },
      },
    },
    { sequence: 35, item: { kind: 'terminal', payload: { kind: 'finished', message: 'Done.' } } },
  ]);
  await viewer.install();
  await viewer.goto();
  await viewer.openSession();
  await page.getByRole('button', { name: 'Raw log' }).click();

  // One tick per typed prompt; the engine wrote nothing here, so two.
  const marks = page.locator('.rail-mark');
  await expect(marks).toHaveCount(2);

  // Hovering a tick raises the Codex-style preview: the prompt in bold, its
  // wall-clock stamp, and the opening of the reply it drew.
  await marks.first().hover();
  const firstPreview = marks.first().locator('.rail-preview');
  await expect(firstPreview).toBeVisible();
  await expect(firstPreview).toContainText('Ship the viewer change');
  await expect(firstPreview).toContainText('2026-09-02 02:41 UTC');
  await expect(firstPreview).toContainText('On it.');

  // The steer's span contains the failed tool call, and its preview says so.
  await marks.last().hover();
  const lastPreview = marks.last().locator('.rail-preview');
  await expect(lastPreview).toBeVisible();
  await expect(lastPreview).toContainText('had error');

  // Clicking the steer's tick crosses thirty notice cards in one jump.
  const steer = page.locator('.card.user.typed').filter({ hasText: 'Also update the docs' });
  await expect(steer).not.toBeInViewport();
  await marks.last().click();
  await expect(steer).toBeInViewport();
  expect(viewer.pageErrors).toEqual([]);
});

test("a subagent transcript's task is not captioned as the user's", async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  viewer.sessionId = 'viz-1-sr-1';
  viewer.events = viewer.eventLog([
    { sequence: 1, item: { kind: 'user', payload: { content: 'Question: which version?' } } },
    {
      sequence: 2,
      item: { kind: 'assistant', payload: { content: 'Looking it up.', tool_calls: [] } },
    },
  ], { id: viewer.sessionId });
  await viewer.install();
  await viewer.goto();
  await viewer.openSession();
  await page.getByRole('button', { name: 'Raw log' }).click();

  await expect(page.locator('.card.user.delegated')).toHaveCount(1);
  await expect(page.locator('.card.user.delegated')).toContainText('Task from parent');
  await expect(page.locator('.card.user.typed')).toHaveCount(0);
  expect(viewer.pageErrors).toEqual([]);
});

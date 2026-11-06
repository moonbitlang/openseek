import { test, expect } from '@playwright/test';
import { VizBrowserHarness } from './support/viz_browser_harness.js';

test('session filters and argument modes change what the reader can see', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  await viewer.install();
  await viewer.goto();
  await viewer.openSession();
  await page.locator('#view-mode-raw').click();

  // Scoped to the card: the prompt rail's hover preview repeats the prompt
  // text, and this test is about the card the filters show and hide.
  const userMessage = page.locator('#seq-1 .content');
  const shellCall = page.locator('[data-call-id="shell-1"]');
  const shellFailure = page.locator('#tool-result-1');
  const buildFailure = page.locator('#tool-result-2');

  await page.locator('#filter-error').click();
  await expect(userMessage).toBeHidden();
  await expect(shellFailure).toBeVisible();
  await page.locator('#filter-error').click();
  await expect(userMessage).toBeVisible();

  await page.locator('#filter-escalated').click();
  await expect(shellCall).toBeVisible();
  await expect(shellFailure).toBeVisible();
  await expect(buildFailure).toBeHidden();
  await page.locator('#filter-escalated').click();

  // The two modes are useful only if they expose different user-visible
  // representations of the same arguments.
  await shellCall.locator('summary').click();
  await expect(shellCall.locator('[data-arg-key="cmd"] .arg-value-inline')).toBeVisible();
  await expect(shellCall.locator('[data-arg-key="cmd"] .arg-value-inline')).toHaveText('moon test');
  await page.locator('#args-original').click();
  await expect(shellCall.locator('.tool-call-args-original')).toBeVisible();
  await expect(shellCall.locator('.tool-call-args-original')).toContainText(/"cmd":\s*"moon test"/);
  await page.locator('#args-rendered').click();
  await expect(shellCall.locator('[data-arg-key="cmd"] .arg-value-inline')).toBeVisible();
  await expect(shellCall.locator('[data-arg-key="cmd"] .arg-value-inline')).toHaveText('moon test');
  expect(viewer.pageErrors).toEqual([]);
});

for (const [mode, label] of [['raw', 'Raw log'], ['model', 'Model view']]) {
  test(`build-error filter separates build diagnostics from other failures in ${label}`, async ({ page }) => {
    const viewer = new VizBrowserHarness(page);
    const events = viewer.events.trim().split('\n').map(line => JSON.parse(line));
    const buildResult = events.find(event => event.item?.kind === 'tool_result' &&
      event.item.payload.tool_call_id === 'mbtx-build');
    buildResult.item.payload.content = [
      { type: 'text', text: 'type mismatch' },
      { type: 'image', media_type: 'image/png', data: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==' },
    ];
    viewer.events = events.map(event => JSON.stringify(event)).join('\n') + '\n';
    await viewer.install();
    await viewer.goto();
    await viewer.openSession();
    await page.locator(`#view-mode-${mode}`).click();

    const buildFailure = page.locator('#tool-result-2');
    await expect(buildFailure).toHaveClass(/\berror\b/);
    await expect(buildFailure.locator(':scope > summary')).toContainText('Tool error · mbtx');
    await buildFailure.locator(':scope > summary').click();
    await expect(buildFailure.locator('.card-body')).toBeVisible();
    await expect(buildFailure.locator('.card-body > .content')).toHaveText([
      'type mismatch',
      mode === 'raw' ? '[Image: image/png, 70 bytes]' : '[Image]',
    ]);
    const buildCall = page.locator('[data-call-id="mbtx-build"] > summary');
    const runtimeCall = page.locator('[data-call-id="mbtx-run"] > summary');
    await expect(buildCall).toBeVisible();
    await expect(buildCall).toContainText('mbtx build 🚩');
    await expect(page.locator('.tool-call-build-failed')).toContainText('Check <compiler> diagnostics');
    await expect(page.locator('.tool-call-run-failed')).toContainText('runtime error');
    const runtimeFailure = page.locator('#tool-result-3');
    const shellFailure = page.locator('#tool-result-1');
    await page.locator('#filter-build-error').click();
    await expect(buildFailure).toBeVisible();
    await expect(buildCall).toBeVisible();
    await expect(runtimeCall).toBeHidden();
    await expect(runtimeFailure).toBeHidden();
    await expect(shellFailure).toBeHidden();

    await page.locator('#filter-error').click();
    await expect(buildFailure).toBeVisible();
    await expect(buildCall).toBeVisible();
    await expect(runtimeCall).toBeVisible();
    await expect(runtimeFailure).toBeVisible();
    await expect(shellFailure).toBeVisible();
    expect(viewer.pageErrors).toEqual([]);
  });
}

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

  await expect(page.locator('.header-meta')).toBeVisible();
  await expect(page.locator('.header-meta')).toContainText('dropped file: dropped-session.jsonl');
  await expect(page.locator('#seq-2 .content')).toBeVisible();
  await expect(page.locator('#seq-2 .content')).toHaveText('Running the browser fixture.');
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
  await page.locator('#view-mode-raw').click();

  // Wait for the child prefetch to finish so its parent re-render cannot race
  // the user click that this test exercises.
  await page.locator('.subrun-transcript').waitFor({ state: 'attached' });
  await page.locator(`.subrun-link[href=${JSON.stringify(`#s=${encodeURIComponent(childId)}`)}]`).click();
  await expect(page.locator('.header-id')).toHaveText(childId);
  await expect(page.locator('#seq-2 .content')).toBeVisible();
  await expect(page.locator('#seq-2 .content')).toHaveText('The child session is open.');
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
  await expect(page.locator('#seq-24 .content')).toBeInViewport();
  await expect(page.locator('#seq-24 .content')).toHaveText('Final hash target');
  expect(viewer.pageErrors).toEqual([]);
});

test('keyboard shortcuts navigate between failures', async ({ page }) => {
  await page.setViewportSize({ width: 900, height: 500 });
  const viewer = new VizBrowserHarness(page);
  await viewer.install();
  await viewer.goto();
  await viewer.openSession();
  await page.locator('#view-mode-raw').click();

  await page.keyboard.press('n');
  await expect(page.locator('#tool-result-2'))
    .toBeInViewport();
  await page.keyboard.press('p');
  await expect(page.locator('#tool-result-1'))
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
  await page.locator('#view-mode-raw').click();

  const resultLink = page.locator('#tool-call-1 .tool-link');
  const callLink = page.locator('#tool-result-1 .tool-link');
  await expect(resultLink).toHaveAttribute('href', '#tool-result-1');
  await expect(callLink).toHaveAttribute('href', '#tool-call-1');
  await expect(resultLink).toBeInViewport();
  await expect(callLink).not.toBeInViewport();
  await resultLink.click();
  await expect(callLink).toBeInViewport({ ratio: 1 });
  expect(viewer.pageErrors).toEqual([]);
});

test('a write body is highlighted by its path extension', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  const writeCall = (id, path, content) => ({ id, name: 'write', arguments: JSON.stringify({ path, content }) });
  viewer.events = viewer.eventLog([
    {
      sequence: 1,
      item: {
        kind: 'assistant',
        payload: {
          content: '',
          tool_calls: [
            writeCall('write-mbtx', 'git.mbtx', 'async fn main {\n  println("hi")\n}'),
            writeCall('write-txt', 'notes.txt', 'fn is not code here'),
          ],
        },
      },
    },
  ]);
  await viewer.install();
  await viewer.goto();
  await viewer.openSession();
  await page.locator('#view-mode-raw').click();

  const bodies = page.locator('[data-arg-key="content"] pre.moonbit-source');
  await expect(bodies).toHaveCount(2);
  const mbtx = page.locator('[data-call-id="write-mbtx"] [data-arg-key="content"] pre.moonbit-source');
  await expect(mbtx.locator('.mtk3').first()).toHaveText('async');
  await expect(mbtx.locator('.mtk5').first()).toContainText('"hi"');
  await expect(mbtx.locator('.moonbit-line')).toHaveCount(3);
  // An extension without a tokenizer keeps plain, numbered text.
  const plain = page.locator('[data-call-id="write-txt"] [data-arg-key="content"] pre.moonbit-source');
  await expect(plain).toContainText('fn is not code here');
  await expect(plain.locator('[class^="mtk"]')).toHaveCount(0);
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
  await page.locator('#view-mode-raw').click();
  const command = page.locator('[data-call-id="unfold-command"]');
  await expect(command.locator('.tool-call-args-original')).toBeHidden();
  await expect(command).toBeInViewport();
  await page.keyboard.press('u');
  await expect(command.locator('[data-arg-key="cmd"] .arg-value-inline')).toBeVisible();
  await expect(command.locator('[data-arg-key="cmd"] .arg-value-inline')).toHaveText('hidden command marker');
  expect(viewer.pageErrors).toEqual([]);
});

test('standalone export reads embedded data without session requests', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  await viewer.install({ standalone: true });
  await viewer.goto();

  await expect(page.locator('#seq-2 .content')).toBeVisible();
  await expect(page.locator('#seq-2 .content')).toHaveText('Running the browser fixture.');
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

  await page.locator('#theme-light').click();
  const lightBackground = await page.evaluate(() =>
    getComputedStyle(document.body).backgroundColor);

  await page.locator('#theme-dark').click();
  const darkBackground = await page.evaluate(() =>
    getComputedStyle(document.body).backgroundColor);
  expect(darkBackground).not.toBe(lightBackground);

  await page.locator('#theme-system').click();
  const systemBackground = await page.evaluate(() =>
    getComputedStyle(document.body).backgroundColor);
  expect(systemBackground).toBe(darkBackground);
  expect(viewer.pageErrors).toEqual([]);
});

test('typed prompts are distinguished from automatic continuation', async ({ page }) => {
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
  await page.locator('#view-mode-raw').click();

  // The opening prompt and mid-turn steer are typed user input; the engine's
  // relaunch prompt is an automatic continuation.
  await expect(page.locator('.card.user.typed')).toHaveCount(2);
  await expect(page.locator('.card.user.typed').first()).toContainText('You');
  await expect(page.locator('.card.user.auto-continue')).toHaveCount(1);
  await expect(page.locator('.card.user.auto-continue')).toContainText('Auto-continue');

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
  await page.locator('#view-mode-raw').click();

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
  const steer = page.locator('#seq-33');
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
  await page.locator('#view-mode-raw').click();

  await expect(page.locator('.card.user.delegated')).toHaveCount(1);
  await expect(page.locator('.card.user.delegated')).toContainText('Task from parent');
  await expect(page.locator('.card.user.typed')).toHaveCount(0);
  expect(viewer.pageErrors).toEqual([]);
});

test('scrubber navigation previews events and preserves hash state', async ({ page }) => {
  await page.setViewportSize({ width: 900, height: 500 });
  const viewer = new VizBrowserHarness(page);
  viewer.events = viewer.eventLog(Array.from({ length: 30 }, (_, i) => ({
    sequence: i * 2 + 2,
    item: { kind: 'assistant', payload: { content: `Step ${i + 1}`, tool_calls: [] } },
  })));
  await viewer.install();
  // Sequence 3 is absent: restore to the following visible anchor, not the top.
  await viewer.goto('#s=viz-1&v=raw&seq=3&extra=keep');
  await expect(page.locator('#seq-4')).toBeInViewport();
  const segments = page.locator('.step-seg');
  await expect(segments).toHaveCount(30);
  const tip = page.locator('.scrubber-tip');
  for (const segment of [segments.first(), segments.last()]) {
    await segment.hover();
    await expect(tip).toBeVisible();
    await expect(tip).toHaveText(await segment.getAttribute('data-label'));
  }
  const historyLength = await page.evaluate(() => history.length);
  await segments.last().click();
  await expect(page.locator('#seq-60')).toBeInViewport();
  await expect(tip).toBeHidden();
  const hash = await page.evaluate(() => Object.fromEntries(new URLSearchParams(location.hash.slice(1))));
  expect(hash).toMatchObject({ s: 'viz-1', v: 'raw', extra: 'keep' });
  expect(await page.evaluate(() => history.length)).toBe(historyLength);
  await expect(page.locator('.step-seg.current')).toHaveCount(1);
  expect(viewer.pageErrors).toEqual([]);
});

test('--watch refreshes the open session as its log grows', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  await viewer.install({ watchMs: 200 });
  await viewer.goto();
  await viewer.openSession();
  await expect(page.locator('.header-meta')).toContainText('live');

  // Polls while nothing changed ask with the size the viewer already has.
  await expect.poll(() => viewer.apiRequests.filter(url => url.includes('known_bytes=')).length)
    .toBeGreaterThan(1);

  viewer.events += JSON.stringify({
    sequence: 8,
    ts: 8_000,
    item: { kind: 'user', payload: { content: 'A prompt that arrived later' } },
  }) + '\n';
  await expect(page.locator('#seq-8 .content')).toBeVisible();
  await expect(page.locator('#seq-8 .content')).toHaveText('A prompt that arrived later');
  await expect(page.locator('.header-meta')).toContainText('8 event(s)');
  expect(viewer.pageErrors).toEqual([]);
});

test('a served viewer without --watch never polls', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  await viewer.install();
  await viewer.goto();
  await viewer.openSession();
  await page.waitForTimeout(600);
  await expect(page.locator('.header-meta')).not.toContainText('live');
  expect(viewer.apiRequests.filter(url => url.includes('known_bytes='))).toEqual([]);
});

test('--watch opens a linked session once it starts', async ({ page }) => {
  // `openseek run --inspect` prints its link before the run records anything,
  // so the page can load before the session is listed.
  const viewer = new VizBrowserHarness(page);
  await viewer.install({ watchMs: 200 });
  await viewer.goto('#s=run-late');
  await expect(page.locator('#session-list-status')).toBeVisible();
  await expect(page.locator('#session-list-status')).toHaveText('waiting for run-late to start…');

  viewer.extraSessionRows.push({
    key: 'run-late',
    id: 'run-late',
    root_label: '/workspace/.openseek',
    is_marker: true,
    last_active: 2,
    first_prompt: 'A run that started after its link',
  });
  viewer.childEvents.set('run-late', viewer.eventLog([
    { sequence: 1, item: { kind: 'user', payload: { content: 'A run that started after its link' } } },
  ], { id: 'run-late' }));

  await expect(page.locator('.header-id')).toBeVisible();
  await expect(page.locator('.header-id')).toHaveText('run-late');
  await expect(page.locator('.header-meta')).toContainText('live');
  expect(viewer.pageErrors).toEqual([]);
});

test('without --watch a link to an unknown session does not wait', async ({ page }) => {
  const viewer = new VizBrowserHarness(page);
  await viewer.install();
  await viewer.goto('#s=run-late');
  await expect(page.locator('#session-list-status')).toBeVisible();
  await expect(page.locator('#session-list-status')).toHaveText('1 session(s)');
  await expect(page.locator('.placeholder')).not.toContainText('waiting for run-late to start…');
});

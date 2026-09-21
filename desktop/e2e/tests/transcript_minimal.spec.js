import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

// Minimal mode is opt-in. Seed the preference only when the profile has none,
// so the persistence test can still observe an explicit choice surviving reloads.
test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => {
    if (localStorage.getItem('openseek.minimal_transcript') === null) {
      localStorage.setItem('openseek.minimal_transcript', 'true');
    }
  });
});

// Exercise the production transport and renderer with recorded events. Fixtures
// deliberately contain parameters, output, and reasoning that must never enter
// the minimal subtree, even after every disclosure has been opened.
class MinimalTranscriptHarness extends DesktopBrowserHarness {
  constructor(page) {
    super(page);
    this.sessionEvents = [
      { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture minimal mode' } } },
      { sequence: 2, item: { kind: 'assistant', payload: {
        content: 'I will explore this project.',
        reasoning_content: 'REASONING_SENTINEL',
        tool_calls: [
          { id: 'read-a', name: 'read', arguments: '{"path":"PARAMETER_SENTINEL"}' },
          { id: 'read-b', name: 'read', arguments: '{"path":"second"}' },
        ],
      } } },
      { sequence: 3, item: { kind: 'tool_result', payload: {
        tool_call_id: 'read-a', tool_name: 'read', content: 'OUTPUT_SENTINEL',
        is_error: false, brief: 'Read the project manifest',
      } } },
      { sequence: 4, item: { kind: 'tool_result', payload: {
        tool_call_id: 'read-b', tool_name: 'read', content: 'OUTPUT_SENTINEL',
        is_error: true, brief: 'Cannot read the second file',
      } } },
      { sequence: 5, item: { kind: 'assistant', payload: {
        content: '', tool_calls: [{ id: 'script', name: 'mbtx', arguments: JSON.stringify({
          description: 'Check project details', script: 'SCRIPT_SENTINEL',
        }) }],
      } } },
      { sequence: 6, item: { kind: 'assistant', payload: { content: 'Now I can check the remaining details.' } } },
    ];
  }

  replyFor(request) {
    if (request.method === 'host.open_path' && request.params.path === 'src/main.mbt') {
      return { opened: false, editor_target: { path: '/workspace/src/main.mbt' } };
    }
    return super.replyFor(request);
  }

  // The titlebar telescope is off while the minimal transcript is shown.
  async enableMinimal() {
    await this.openSession();
    await expect(this.page.locator('#stream .minimal-tools, #stream .minimal-tools-live, #stream .minimal-process, #stream .minimal-single-call').first()).toBeVisible();
  }

  detailedMode() {
    return this.page.getByRole('button', { name: 'Detailed mode', exact: true });
  }

  append(kind, payload, ts) {
    const sequence = (this.sessionEvents.at(-1)?.sequence || 0) + 1;
    const event = { sequence, ts, item: { kind, payload } };
    this.sessionEvents.push(event);
    this.notify('session.event', {
      session: 'session-1', session_root: '/workspace/.openseek', sequence, event,
    });
  }
}

test('single minimal calls have no duplicate disclosure and preserve status and edits', async ({ page }) => {
  const app = new MinimalTranscriptHarness(page);
  app.sessionEvents = [
    { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture single call' } } },
    { sequence: 2, item: { kind: 'assistant', payload: { content: 'Checking the project.', tool_calls: [
      { id: 'single', name: 'mbtx', arguments: '{}' },
    ] } } },
  ];
  await app.install();
  await app.goto();
  await app.openSession();
  const stream = page.locator('#stream');
  await expect(stream.locator('.minimal-tools')).toHaveCount(0);
  await expect(stream.locator('.minimal-call .tool-status')).toHaveAttribute('aria-label', 'Tool in progress');
  app.append('tool_result', { tool_call_id: 'single', tool_name: 'mbtx', content: '', brief: 'mbtx (exit=0)', is_error: false });
  await expect(stream.locator('.minimal-call-caption')).toHaveText('mbtx (exit=0)');
  await expect(stream.locator('.minimal-call .tool-status')).toHaveCount(0);
  app.append('terminal', { kind: 'finished', message: 'Checked.' });
  const process = stream.locator('.minimal-process');
  await process.locator(':scope > summary').click();
  await expect(process.locator('.minimal-tools, .minimal-process-body summary')).toHaveCount(0);
  await expect(process.locator('.minimal-call-caption')).toBeVisible();

  app.append('user', { content: 'Edit the file next.' });
  app.append('assistant', { content: '', tool_calls: [
    { id: 'edit', name: 'edit', arguments: JSON.stringify({ path: 'main.mbt', old_string: 'old', new_string: 'new' }) },
  ] });
  const single = stream.locator(':scope > .minimal-messages > .minimal-single-call');
  await expect(single.locator('.tool-status')).toHaveAttribute('aria-label', 'Tool in progress');
  await expect(single.locator('.editor-diff-preview')).toBeVisible();
  app.append('tool_result', { tool_call_id: 'edit', tool_name: 'edit', content: '', brief: 'Edit failed', is_error: true });
  await expect(single.locator('.minimal-call-caption')).toHaveText('Edit failed');
  await expect(single.locator('.tool-status.failed')).toHaveAttribute('aria-label', 'Tool failed');
  await expect(single.locator('.minimal-failure-count')).toHaveCount(0);
  await expect(single).not.toContainText(/tool calls? failed/);
  app.append('terminal', { kind: 'finished', message: 'Could not edit.' });
  await expect(stream.getByText('Could not edit.', { exact: true })).toBeVisible();
  await expect(single.locator('.tool-status')).toBeVisible();
  await expect(single.locator('.editor-diff-preview')).toBeVisible();
  await expect(stream.locator('.minimal-tools')).toHaveCount(0);
  await expect(stream.locator('.minimal-process')).toHaveCount(1);
  expect(app.pageErrors).toEqual([]);
});

test('minimal current tools expand with icons and retire when new prose arrives', async ({ page }, testInfo) => {
  const app = new MinimalTranscriptHarness(page);
  await app.install();
  await app.goto();
  await app.enableMinimal();
  const older = page.locator('.minimal-tools').first();
  await expect(older).not.toHaveAttribute('open', '');
  app.append('assistant', { content: 'Now inspect and edit the implementation.', tool_calls: [
    { id: 'live-read', name: 'read', arguments: JSON.stringify({ description: 'Read the implementation' }) },
    { id: 'live-edit', name: 'edit', arguments: JSON.stringify({ description: 'Edit the implementation' }) },
    { id: 'live-script', name: 'mbtx', arguments: JSON.stringify({ description: 'Verify the implementation' }) },
  ] });
  const live = page.locator('.minimal-tools-live');
  await expect(live.locator('.minimal-call-caption')).toHaveText([
    'Read the implementation', 'Edit the implementation', 'Verify the implementation',
  ]);
  await expect(live.locator('summary')).toHaveCount(0);
  await expect(live.locator('.minimal-tool-icon > svg')).toHaveCount(3);
  await expect(live.locator('.minimal-tool-icon')).toHaveText(['', '', '']);
  for (const name of ['read', 'edit', 'mbtx']) {
    await expect(live.locator(`.minimal-tool-icon[title="${name}"] > svg`)).toBeVisible();
  }
  for (const row of await live.locator('.minimal-call').all()) await expect(row).toBeVisible();
  app.append('tool_result', { tool_call_id: 'live-read', tool_name: 'read', content: '', brief: 'Read implementation.mbt', is_error: false });
  await expect(live.locator('.minimal-call-caption').first()).toHaveText('Read implementation.mbt');
  await expect(live.locator('.tool-status.pending')).toHaveCount(2);
  await expect(older).not.toHaveAttribute('open', '');
  await page.screenshot({ animations: 'disabled', path: testInfo.outputPath('minimal-live-icons.png') });
  await page.locator('.minimal-messages').screenshot({ animations: 'disabled', path: testInfo.outputPath('minimal-icons-alignment.png') });

  app.append('assistant', { content: 'The implementation is ready; check the results.', tool_calls: [
    { id: 'next-read', name: 'read', arguments: JSON.stringify({ description: 'Read the results' }) },
    { id: 'next-image', name: 'imageView', arguments: JSON.stringify({ description: 'Inspect the screenshot' }) },
  ] });
  await expect(page.locator('.minimal-tools')).toHaveCount(2);
  const retired = page.locator('.minimal-tools').last();
  await expect(retired).not.toHaveAttribute('open', '');
  await expect(retired.locator('.minimal-call').first()).toBeHidden();
  await expect(live.locator('.minimal-call-caption')).toHaveText(['Read the results', 'Inspect the screenshot']);
  await expect(live.locator('.minimal-tool-icon > svg')).toHaveCount(2);
  await expect(live.locator('.minimal-tool-icon[title="imageView"] > svg')).toBeVisible();
  await retired.locator(':scope > summary').click();
  app.append('tool_result', { tool_call_id: 'next-read', tool_name: 'read', content: '', brief: 'Read results.json', is_error: false });
  await expect(live.locator('.minimal-call-caption').first()).toHaveText('Read results.json');
  await expect(retired).toHaveAttribute('open', '');
  for (const width of [1440, 640]) {
    await page.setViewportSize({ width, height: 900 });
    const layout = await retired.evaluate(node => {
      const summary = node.querySelector(':scope > summary');
      const label = summary.querySelector('.minimal-summary-text').getBoundingClientRect();
      const arrow = summary.querySelector('.minimal-chevron').getBoundingClientRect();
      const body = node.querySelector('.minimal-call-list');
      return { labelRight: label.right, arrowLeft: arrow.left,
        border: getComputedStyle(body).borderLeftWidth,
        indent: getComputedStyle(body).marginLeft,
        padding: getComputedStyle(body).paddingLeft };
    });
    expect(layout.arrowLeft).toBeGreaterThanOrEqual(layout.labelRight);
    expect(layout.border).toBe('0px');
    expect(layout.indent).toBe('0px');
    expect(layout.padding).toBe('0px');
    // SVG baselines differ from text baselines. Compare visible row centers
    // so folded summaries, expanded calls and their status icons stay aligned.
    const rows = await page.locator('.minimal-activity-summary:visible, .minimal-call:visible').evaluateAll(nodes => nodes.map(node => {
      const caption = node.querySelector('.minimal-summary-text, .minimal-call-caption').getBoundingClientRect();
      const icons = [...node.querySelectorAll(':scope > .minimal-tool-icon > svg, :scope > .minimal-chevron, :scope > .tool-status, :scope > .minimal-tool-status')];
      const tool = node.querySelector(':scope > .minimal-tool-icon > svg').getBoundingClientRect();
      return { width: tool.width, height: tool.height,
        offsets: icons.map(icon => { const box = icon.getBoundingClientRect(); return box.y + box.height / 2 - caption.y - caption.height / 2; }) };
    }));
    for (const row of rows) {
      for (const offset of row.offsets) expect(Math.abs(offset)).toBeLessThanOrEqual(0.5);
      expect(row.width).toBe(14);
      expect(row.height).toBe(14);
    }
  }
  await page.screenshot({ animations: 'disabled', path: testInfo.outputPath('minimal-retired-icons.png') });
  expect(app.pageErrors).toEqual([]);
});

test('minimal captions persist through completion and yield to newer descriptions and briefs', async ({ page }) => {
  const app = new MinimalTranscriptHarness(page);
  app.sessionEvents = [
    { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture latest operation' } } },
    { sequence: 2, item: { kind: 'assistant', payload: { content: '', tool_calls: [
      { id: 'script', name: 'mbtx', arguments: JSON.stringify({ description: 'Run project tests' }) },
    ] } } },
  ];
  await app.install();
  await app.goto();
  await app.enableMinimal();
  const summary = page.locator('#stream > .minimal-messages .minimal-call-caption').last();
  const calls = page.locator('#stream > .minimal-messages > .minimal-tools-live .minimal-call, #stream > .minimal-messages > .minimal-single-call');
  await expect(summary).toHaveText('Run project tests');
  app.append('tool_result', {
    tool_call_id: 'script', tool_name: 'mbtx', brief: 'mbtx → bg bg-1', content: '', is_error: false,
  });
  await expect(calls.locator('.tool-status')).toHaveCount(0);
  await expect(summary).toHaveText('Run project tests');
  app.append('runtime_notice', { content: 'background job bg-1 finished (exit=0): Run project tests' });
  app.append('assistant', { content: '', tool_calls: [{ id: 'edit', name: 'edit', arguments: '{}' }] });
  await expect(calls).toHaveCount(2);
  await expect(summary).toHaveText('edit');
  app.append('tool_result', {
    tool_call_id: 'edit', tool_name: 'edit', brief: 'Edited main.mbt', content: '', is_error: false,
  });
  await expect(calls.last().locator('.minimal-call-caption')).toHaveText('Edited main.mbt');
  await expect(summary).toHaveText('Edited main.mbt');
  app.append('assistant', { content: '', tool_calls: [
    { id: 'next', name: 'read', arguments: JSON.stringify({ description: 'Check test results' }) },
  ] });
  await expect(summary).toHaveText('Check test results');
  app.append('tool_result', {
    tool_call_id: 'next', tool_name: 'read', brief: 'Read results.json', content: '', is_error: false,
  });
  await expect(calls.last().locator('.minimal-call-caption')).toHaveText('Read results.json');
  await expect(summary).toHaveText('Read results.json');
  app.append('assistant', { content: '', tool_calls: [
    { id: 'plan', name: 'plan', arguments: '{}' },
  ] });
  app.append('tool_result', {
    tool_call_id: 'plan', tool_name: 'plan', brief: 'Updated plan', content: '', is_error: false,
  });
  await expect(summary).toHaveText('Updated plan');
  app.append('terminal', { kind: 'finished', message: 'Tests passed.' });
  const completed = page.locator('#stream > .minimal-messages > .minimal-process');
  await expect(completed.locator(':scope > summary > .minimal-summary-text')).toHaveText('Run project tests · Edited main.mbt · Read results.json · …');
  // One tool group needs only the completed-turn disclosure, regardless of
  // how many calls it contains. Opening it once exposes every operation.
  await expect(completed.locator('.minimal-tools')).toHaveCount(0);
  await expect(completed.locator('.minimal-call').first()).toBeHidden();
  await completed.locator(':scope > summary').click();
  await expect(completed.locator('.minimal-call-caption')).toHaveText([
    'Run project tests', 'Edited main.mbt', 'Read results.json', 'Updated plan',
  ]);
  for (const call of await completed.locator('.minimal-call').all()) {
    await expect(call).toBeVisible();
  }
  await expect(completed.locator('.minimal-note')).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('minimal transcript groups live tools and folds completed work around user messages', async ({ page }, testInfo) => {
  const app = new MinimalTranscriptHarness(page);
  await app.install();
  await app.goto();
  await app.openSession();
  await expect(page.locator('.minimal-tools')).toHaveCount(1);
  await app.enableMinimal();
  const stream = page.locator('#stream');
  const tools = stream.locator('.minimal-tools');
  await expect(tools).toHaveCount(1);
  await expect(tools.locator('summary')).toHaveCSS('list-style-type', 'none');
  await expect(tools.locator('.minimal-chevron svg')).toHaveCount(1);
  await expect(tools.locator('summary > .minimal-summary-text')).toHaveText('Read the project manifest · Cannot read the second file · Check project details');
  const aggregate = tools.locator(':scope > summary > .minimal-tool-status');
  await expect(aggregate.locator('.minimal-failure-count')).toHaveCount(0);
  await expect(aggregate).not.toContainText(/tool calls? failed/);
  await expect(aggregate.getByRole('img', { name: 'Tool failed' })).toBeVisible();
  const spinner = aggregate.locator('.tool-status-spinner');
  await expect(spinner).toBeVisible();
  expect(await spinner.evaluate(node => node.getAnimations().some(animation =>
    animation.playState === 'running' && animation.effect.getTiming().iterations === Infinity))).toBe(true);
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await expect(spinner).toHaveCSS('animation-name', 'none');
  await page.emulateMedia({ reducedMotion: 'no-preference' });
  await expect(stream.getByText('I will explore this project.', { exact: true })).toBeVisible();
  await expect(stream.getByText('Now I can check the remaining details.', { exact: true })).toBeVisible();
  await expect(tools).not.toHaveAttribute('open', '');
  await page.screenshot({ animations: 'disabled', path: testInfo.outputPath('minimal-working.png') });
  await tools.locator('summary').focus();
  await page.keyboard.press('Enter');
  await expect(tools.locator('.minimal-call-caption')).toHaveText([
    'Read the project manifest', 'Cannot read the second file', 'Check project details',
  ]);
  await expect(tools.locator('.minimal-call .tool-status').last()).toHaveAttribute('aria-label', 'Tool in progress');
  const originalTools = await tools.elementHandle();
  app.append('tool_result', {
    tool_call_id: 'script', tool_name: 'mbtx', content: 'OUTPUT_SENTINEL', is_error: false,
    brief: 'mbtx (exit=0)',
  });
  await expect(tools.locator('.minimal-call-caption').last()).toHaveText('Check project details');
  await expect(aggregate.locator('.tool-status-spinner')).toHaveCount(0);
  await expect(aggregate.locator('.minimal-failure-count')).toHaveCount(0);
  await expect(aggregate).not.toContainText(/tool calls? failed/);
  await expect(tools.locator('summary > .minimal-summary-text')).toHaveText('Read the project manifest · Cannot read the second file · Check project details');
  await expect(tools).toHaveAttribute('open', '');
  expect(await originalTools.evaluate(node => node.isConnected)).toBe(true);
  await page.screenshot({ animations: 'disabled', path: testInfo.outputPath('minimal-running.png') });

  app.append('user', { content: 'Please focus on the architecture.' });
  app.append('assistant', { content: 'I will focus on architecture.', tool_calls: [
    { id: 'unknown', name: 'mcp__example__inspect', arguments: '{broken' },
  ] });
  app.append('tool_result', {
    tool_call_id: 'unknown', tool_name: 'mcp__example__inspect', content: 'OUTPUT_SENTINEL', is_error: true,
  });
  app.append('assistant', { content: 'Here is the **final summary**.' }, 1700000000000);
  app.append('terminal', { kind: 'finished', message: 'Here is the **final summary**.' });

  const processes = stream.locator('.minimal-process');
  await expect(processes).toHaveCount(2);
  await expect(processes.nth(0).locator(':scope > summary > .minimal-summary-text')).toHaveText('Read the project manifest · Cannot read the second file · Check project details');
  await expect(processes.nth(1).locator(':scope > summary > .minimal-summary-text')).toHaveText('mcp__example__inspect');
  await expect(processes.nth(0).locator(':scope > summary .minimal-failure-count')).toHaveCount(0);
  await expect(processes.nth(1).locator(':scope > summary .minimal-failure-count')).toHaveCount(0);
  await expect(processes.nth(0).locator(':scope > summary')).not.toContainText(/tool calls? failed/);
  await expect(processes.nth(1).locator(':scope > summary')).not.toContainText(/tool calls? failed/);
  await expect(processes.nth(0).locator(':scope > summary').getByRole('img', { name: 'Tool failed' })).toBeVisible();
  await expect(processes.nth(1).locator(':scope > summary').getByRole('img', { name: 'Tool failed' })).toBeVisible();
  await expect(stream.getByText('I will explore this project.', { exact: true })).toBeHidden();
  await expect(stream.getByText('Please focus on the architecture.', { exact: true })).toBeVisible();
  await expect(stream.locator('.msg-content strong')).toHaveText('final summary');
  await expect(stream.locator('.assistant-message-actions .message-copy')).toHaveCount(1);
  // Minimal mode mirrors detailed mode's finish line: the confirmed final
  // answer carries its durable commit instant beside the copy action.
  await expect(stream.locator('.assistant-message-actions .assistant-message-time')).toHaveCount(1);
  await page.screenshot({ animations: 'disabled', path: testInfo.outputPath('minimal-completed.png') });
  for (const process of await processes.all()) {
    await process.locator(':scope > summary').click();
    for (const group of await process.locator('.minimal-tools').all()) {
      await group.locator('summary').click();
    }
  }
  await expect(processes.nth(0).locator('.minimal-tools > summary > .minimal-summary-text')).toHaveText(
    'Read the project manifest · Cannot read the second file · Check project details',
  );
  // Prose keeps the outer process, but its single call needs no inner fold.
  await expect(processes.nth(1).locator('.minimal-tools')).toHaveCount(0);
  await expect(processes.nth(1).locator('.minimal-call .tool-status.failed')).toHaveAttribute('aria-label', 'Tool failed');
  await expect(stream.locator('.minimal-call-caption').filter({ hasText: /^mcp__example__inspect$/ })).toBeVisible();
  await expect(stream).not.toContainText(/REASONING_SENTINEL|PARAMETER_SENTINEL|OUTPUT_SENTINEL|SCRIPT_SENTINEL/);
  await expect(stream.locator('.tool-call-tabs, .activity-thinking')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('minimal message groups separate outer turns from internal tool and prose spacing', async ({ page }, testInfo) => {
  const app = new MinimalTranscriptHarness(page);
  app.sessionEvents = [
    { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture spacing' } } },
  ];
  const events = [];
  for (const [index, calls] of [['single', ['one']], ['group', ['two', 'three']]]) {
    events.push({ kind: 'assistant', payload: { content: `Before ${index}`, tool_calls: calls.map(id => ({
      id, name: 'mbtx', arguments: JSON.stringify({ description: `Inspect ${id}` }),
    })) } });
    for (const id of calls) events.push({ kind: 'tool_result', payload: {
      tool_call_id: id, tool_name: 'mbtx', content: '', is_error: false,
    } });
    events.push({ kind: 'assistant', payload: { content: `After ${index}` } });
  }
  for (const item of events) app.sessionEvents.push({ sequence: app.sessionEvents.length + 1, item });
  await app.install();
  await app.goto();
  // Compare settled layout, without the prose entry animation's translation.
  await page.addStyleTag({ content: '#stream .msg { animation: none; }' });
  await app.enableMinimal();
  for (const completed of [false, true]) {
    if (completed) {
      app.append('assistant', { content: 'Finished inspection.' });
      app.append('terminal', { kind: 'finished', message: 'Finished inspection.' });
      await page.locator('.minimal-process > summary').click();
    }
    await expect(page.locator('#stream')).toHaveCSS('row-gap', '20px');
    await expect(page.locator('#stream > .minimal-messages')).toHaveCount(1);
    const body = completed ? page.locator('.minimal-process-body') : page.locator('#stream > .minimal-messages');
    await expect(body.locator(':scope > .minimal-single-call')).toHaveCount(1);
    await expect(body.locator(':scope > .minimal-tools')).toHaveCount(1);
    await expect(body.locator(':scope > .minimal-tools')).not.toHaveAttribute('open', '');
    for (const width of [1440, 640]) {
      await page.setViewportSize({ width, height: 900 });
      // Both live messages and expanded completed content use the internal
      // gap. Measure the actual tool-to-prose distances, without padding.
      const gaps = await body.evaluate(node => [...node.children]
        .filter(row => row.matches('.minimal-single-call, .minimal-tools'))
        .map(row => {
          const label = row.querySelector('.minimal-call-caption, .minimal-summary-text').getBoundingClientRect();
          return {
            before: label.top - row.previousElementSibling.getBoundingClientRect().bottom,
            after: row.nextElementSibling.getBoundingClientRect().top - label.bottom,
          };
        }));
      expect(Math.abs(gaps[0].before - gaps[1].before)).toBeLessThanOrEqual(1);
      expect(Math.abs(gaps[0].after - gaps[1].after)).toBeLessThanOrEqual(1);
      const expectedGap = 12;
      for (const gap of gaps) {
        expect(Math.abs(gap.before - expectedGap)).toBeLessThanOrEqual(1);
        expect(Math.abs(gap.after - expectedGap)).toBeLessThanOrEqual(1);
      }
      await page.screenshot({ animations: 'disabled', path: testInfo.outputPath(`minimal-spacing-${completed ? 'completed' : 'live'}-${width}.png`) });
    }
    // Successful summaries, singletons, and groups have no status badge.
    await expect(body.locator('.tool-status, .minimal-tool-status')).toHaveCount(0);
  }
  const completedBody = page.locator('.minimal-process-body');
  await completedBody.locator('.minimal-tools > summary').click();
  await expect(completedBody.locator('.minimal-call')).toHaveCount(3);
  await expect(completedBody.locator('.tool-status, .minimal-tool-status')).toHaveCount(0);
  app.append('user', { content: 'Inspect another file.' });
  app.append('assistant', { content: 'I will inspect the next file.', tool_calls: [
    { id: 'second-turn', name: 'read', arguments: JSON.stringify({ description: 'Read the next file' }) },
  ] });
  await expect(page.locator('#stream > .minimal-messages')).toHaveCount(2);
  // Only user rows and their message groups occupy the outer grid. Measure
  // the outer boundary too, so a global gap change cannot satisfy this test.
  const outer = await page.locator('#stream').evaluate(node => ({
    kinds: [...node.children].map(row => row.matches('.msg.user') ? 'user' : row.classList.contains('minimal-messages') ? 'messages' : row.className),
    gaps: [...node.children].slice(1).map(row => row.getBoundingClientRect().top - row.previousElementSibling.getBoundingClientRect().bottom),
  }));
  expect(outer.kinds).toEqual(['user', 'messages', 'user', 'messages']);
  for (const gap of outer.gaps) expect(Math.abs(gap - 20)).toBeLessThanOrEqual(1);
  expect(app.pageErrors).toEqual([]);
});

for (const count of [1, 2]) test(`minimal first tool row has balanced spacing with ${count} calls`, async ({ page }, testInfo) => {
  const app = new MinimalTranscriptHarness(page);
  const calls = Array.from({ length: count }, (_, i) => ({
    id: `first-${i}`, name: 'mbtx', arguments: JSON.stringify({ description: `Inspect stats ${i + 1}` }),
  }));
  const items = [
    { kind: 'user', payload: { content: 'Show the browser fixture first tool row' } },
    { kind: 'assistant', payload: { content: '', tool_calls: calls } },
    ...calls.map(call => ({ kind: 'tool_result', payload: {
      tool_call_id: call.id, tool_name: call.name, content: '', is_error: false,
    } })),
    { kind: 'assistant', payload: { content: 'These stats describe the completed runs. I will compare the results.' } },
    { kind: 'assistant', payload: { content: 'Comparison complete.' } },
    { kind: 'terminal', payload: { kind: 'finished', message: 'Comparison complete.' } },
  ];
  app.sessionEvents = items.map((item, i) => ({ sequence: i + 1, item }));
  await app.install();
  await app.goto();
  await page.addStyleTag({ content: '#stream .msg { animation: none; }' });
  await app.enableMinimal();
  const process = page.locator('.minimal-process');
  await process.locator(':scope > summary').click();
  const first = process.locator('.minimal-process-body > :first-child');
  await expect(first).toHaveClass(count === 1 ? /minimal-single-call/ : /minimal-tools/);
  for (const width of [1440, 640]) {
    await page.setViewportSize({ width, height: 900 });
    const gaps = await process.evaluate(node => {
      const summary = node.querySelector(':scope > summary .minimal-summary-text').getBoundingClientRect();
      const first = node.querySelector('.minimal-process-body > :first-child');
      const label = first.querySelector('.minimal-call-caption, .minimal-summary-text').getBoundingClientRect();
      return {
        before: label.top - summary.bottom,
        after: first.nextElementSibling.getBoundingClientRect().top - label.bottom,
      };
    });
    expect(Math.abs(gaps.before - gaps.after)).toBeLessThanOrEqual(1);
    expect(Math.abs(gaps.before - 12)).toBeLessThanOrEqual(1);
    expect(Math.abs(gaps.after - 12)).toBeLessThanOrEqual(1);
    await page.screenshot({ animations: 'disabled', path: testInfo.outputPath(`first-tool-${width}.png`) });
  }
  expect(app.pageErrors).toEqual([]);
});

test('minimal summaries truncate to one line at wide and narrow widths', async ({ page }, testInfo) => {
  const app = new MinimalTranscriptHarness(page);
  const description = 'Find Url/UrlSearchParams struct definitions and visibility attributes. '.repeat(8);
  app.sessionEvents = [
    { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture long summary' } } },
    { sequence: 2, item: { kind: 'assistant', payload: { content: 'Inspecting the API.', tool_calls: [
      { id: 'long', name: 'mbtx', arguments: JSON.stringify({ description }) },
    ] } } },
  ];
  await app.install();
  await app.goto();
  await app.enableMinimal();
  for (const completed of [false, true]) {
    if (completed) {
      app.append('assistant', { content: '', tool_calls: [
        { id: 'failed', name: 'read', arguments: JSON.stringify({ description }) },
      ] });
      app.append('tool_result', { tool_call_id: 'failed', tool_name: 'read', content: '', is_error: true });
      app.append('tool_result', { tool_call_id: 'long', tool_name: 'mbtx', content: '', is_error: true });
      app.append('terminal', { kind: 'finished', message: 'Inspection complete.' });
      await page.locator('.minimal-process > summary').click();
    }
    for (const width of [1440, 640]) {
      await page.setViewportSize({ width, height: 900 });
      for (const summary of await page.locator('.minimal-activity-summary, .minimal-single-call').all()) {
        const label = summary.locator(':scope > .minimal-summary-text, :scope > .minimal-call-caption');
        const metrics = await label.evaluate(node => ({
          height: node.getBoundingClientRect().height,
          lineHeight: Number.parseFloat(getComputedStyle(node).lineHeight),
          labelWidth: node.clientWidth,
          textWidth: node.scrollWidth,
        }));
        expect(metrics.height).toBeLessThanOrEqual(metrics.lineHeight + 1);
        expect(metrics.textWidth).toBeGreaterThan(metrics.labelWidth);
        await expect(label).toHaveAttribute('title', completed ? `${description} · ${description}` : description);
        const status = summary.locator(':scope > .minimal-tool-status');
        await expect(status).toBeVisible();
        // Read all bounds in one frame while resizing can still animate the
        // surrounding layout, so the comparison uses the same row position.
        const [rowBox, labelBox, statusBox] = await summary.evaluate(node => [
          node.getBoundingClientRect().toJSON(),
          node.querySelector(':scope > .minimal-summary-text, :scope > .minimal-call-caption').getBoundingClientRect().toJSON(),
          node.querySelector(':scope > .minimal-tool-status').getBoundingClientRect().toJSON(),
        ]);
        expect(statusBox.x).toBeGreaterThanOrEqual(labelBox.x + labelBox.width);
        expect(statusBox.x + statusBox.width).toBeLessThanOrEqual(rowBox.x + rowBox.width + 1);
        if (completed) {
          await expect(status.locator('.minimal-failure-count')).toHaveCount(0);
          await expect(status).not.toContainText(/tool calls? failed/);
          await expect(status.getByRole('img', { name: 'Tool failed' })).toBeVisible();
        }
      }
    }
  }
  await page.screenshot({ animations: 'disabled', path: testInfo.outputPath('minimal-single-line.png') });
  expect(app.pageErrors).toEqual([]);
});

test('minimal transcript folds background notices into the surrounding tool activity', async ({ page }) => {
  const app = new MinimalTranscriptHarness(page);
  app.sessionEvents.pop(); // Leave the tool group at the tail.
  await app.install();
  await app.goto();
  await app.enableMinimal();
  const notice = 'background job bg-1 finished (exit=0): Run the issue tests';
  app.append('runtime_notice', { content: notice });
  app.append('assistant', { content: '', tool_calls: [
    { id: 'output', name: 'job_output', arguments: '{"description":"Read test results"}' },
  ] });
  const tools = page.locator('#stream .minimal-tools-live');
  await expect(tools).toHaveCount(1);
  await expect(tools.locator('summary')).toHaveCount(0);
  await expect(page.getByText(notice, { exact: true })).toBeVisible();
  await expect(tools.locator('.minimal-call-caption, .minimal-note')).toHaveText([
    'Read the project manifest', 'Cannot read the second file', 'Check project details',
    notice, 'Read test results',
  ]);
  app.append('terminal', { kind: 'finished', message: 'The tests passed.' });
  const process = page.locator('#stream .minimal-process');
  await expect(process).toHaveCount(1);
  await expect(page.getByText(notice, { exact: true })).toBeHidden();
  await expect(process.locator(':scope > summary .minimal-failure-count')).toHaveCount(0);
  await expect(process.locator(':scope > summary')).not.toContainText(/tool calls? failed/);
  await expect(process.locator(':scope > summary').getByRole('img', { name: 'Tool failed' })).toBeVisible();
  await expect(process.locator(':scope > summary')).not.toContainText(/Background activity|Read job output|Wait for jobs|Stop jobs/);
  await process.locator(':scope > summary').click();
  await process.locator('.minimal-tools > summary').click();
  await expect(page.getByText(notice, { exact: true })).toBeVisible();

  // A notice arriving between turns remains independently expandable, without
  // moving it before an already completed answer or presenting it as prose.
  const lateNotice = 'background job bg-2 finished (exit=0): Run remaining checks';
  app.append('runtime_notice', { content: lateNotice });
  await expect(page.locator('#stream > .minimal-messages > .minimal-tools')).toHaveCount(1);
  await expect(page.getByText(lateNotice, { exact: true })).toBeHidden();
  await page.locator('#stream > .minimal-messages > .minimal-tools > summary').click();
  await expect(page.getByText(lateNotice, { exact: true })).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('minimal transcript folds context summaries separately from final guidance', async ({ page }) => {
  const app = new MinimalTranscriptHarness(page);
  await app.install();
  await app.goto();
  await app.enableMinimal();
  app.append('summary', {
    content: '# Handoff Summary\n\nKeep implementing the project.', from_sequence: 1, to_sequence: 6,
  });
  const checkpoint = page.locator('#stream > .minimal-messages > .minimal-context-summary');
  await expect(checkpoint).toHaveCount(1);
  await expect(checkpoint.locator('summary .minimal-summary-text')).toHaveText('Context summary');
  await expect(checkpoint.getByRole('heading', { name: 'Handoff Summary' })).toBeHidden();
  await checkpoint.locator(':scope > summary').click();
  const originalCheckpoint = await checkpoint.elementHandle();
  const guidance = '[context ceiling] Continue in a new turn.';
  app.append('terminal', { kind: 'finished', message: guidance });
  await expect(page.getByText(guidance, { exact: true })).toBeVisible();
  await expect(checkpoint).toHaveCount(1);
  await expect(page.locator('#stream > .minimal-messages > .minimal-process')).toHaveCount(1);
  expect(await originalCheckpoint.evaluate(node => node.isConnected)).toBe(true);
  await expect(checkpoint.getByRole('heading', { name: 'Handoff Summary' })).toBeVisible();
  await checkpoint.locator('summary').focus();
  await expect(checkpoint.getByText('Keep implementing the project.', { exact: true })).toBeVisible();
  await page.keyboard.press('Enter');
  await expect(checkpoint.getByRole('heading', { name: 'Handoff Summary' })).toBeHidden();

  // Some producers record their checkpoint after the terminal guidance.
  app.append('summary', { content: 'A later checkpoint.', from_sequence: 1, to_sequence: 8 });
  await expect(checkpoint).toHaveCount(2);
  await expect(page.getByText('A later checkpoint.', { exact: true })).toBeHidden();
  await expect(page.getByText(guidance, { exact: true })).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('minimal transcript clears jump to latest when folded content fits the viewport', async ({ page }) => {
  const app = new MinimalTranscriptHarness(page);
  app.sessionEvents[5].item.payload.content = Array.from(
    { length: 60 }, (_, index) => `Progress paragraph ${index}.`,
  ).join('\n\n');
  await app.install();
  await app.goto();
  await app.enableMinimal();
  const transcript = page.locator('#transcript');
  const jump = page.getByTitle('Jump to latest', { exact: true });
  await expect.poll(() => transcript.evaluate(node => node.scrollHeight - node.clientHeight))
    .toBeGreaterThan(1000);
  await transcript.evaluate(node => { node.scrollTop = 0; });
  await expect(jump).toBeVisible();

  // Collapsing from scrollTop=0 changes the available range without a scroll
  // event. The old unpinned state must not leave a button over the summary.
  app.append('terminal', { kind: 'finished', message: 'Finished checking.' });
  await expect(page.locator('.minimal-process')).toHaveCount(1);
  await expect.poll(() => transcript.evaluate(node => node.scrollHeight - node.clientHeight)).toBe(0);
  await expect(jump).toBeHidden();

  const summary = page.locator('.minimal-process > summary');
  await summary.click();
  await expect.poll(() => transcript.evaluate(node => node.scrollHeight - node.clientHeight))
    .toBeGreaterThan(1000);
  await transcript.evaluate(node => { node.scrollTop = 0; });
  await expect(jump).toBeVisible();
  await summary.click();
  await expect.poll(() => transcript.evaluate(node => node.scrollHeight - node.clientHeight)).toBe(0);
  await expect(jump).toBeHidden();
  expect(app.pageErrors).toEqual([]);
});

test('minimal transcript retains stopped failed and empty-success processes across later completion', async ({ page }) => {
  const app = new MinimalTranscriptHarness(page);
  app.sessionEvents = [
    { item: { kind: 'user', payload: { content: 'Show the browser fixture boundaries' } } },
    { item: { kind: 'assistant', payload: { content: 'Stopped process' } } },
    { item: { kind: 'terminal', payload: { kind: 'interrupted', message: '' } } },
    { item: { kind: 'user', payload: { content: 'Try again' } } },
    { item: { kind: 'assistant', payload: { content: 'Failed process' } } },
    { item: { kind: 'terminal', payload: { kind: 'failed', message: 'Connection failed' } } },
    { item: { kind: 'user', payload: { content: 'Try empty completion' } } },
    { item: { kind: 'assistant', payload: { content: 'Answerless process' } } },
    { item: { kind: 'terminal', payload: { kind: 'finished', message: '' } } },
    { item: { kind: 'user', payload: { content: 'A final attempt' } } },
    { item: { kind: 'assistant', payload: { content: 'Successful process' } } },
    { item: { kind: 'terminal', payload: { kind: 'finished', message: 'A real answer' } } },
    { item: { kind: 'user', payload: { content: 'One quick answer' } } },
    { item: { kind: 'terminal', payload: { kind: 'finished', message: 'Only a final answer' } } },
  ].map((event, index) => ({ ...event, sequence: index + 1 }));
  await app.install();
  await app.goto();
  await app.enableMinimal();
  const stream = page.locator('#stream');
  for (const text of ['Stopped process', 'Failed process', 'Answerless process', 'Connection failed', 'A real answer', 'Only a final answer']) {
    await expect(stream.getByText(text, { exact: true })).toBeVisible();
  }
  await expect(stream.getByText('Successful process', { exact: true })).toBeHidden();
  await expect(stream.locator('.minimal-process')).toHaveCount(1);
  await expect(stream.locator('.minimal-process > summary .minimal-summary-text')).toHaveText('Work completed');
  expect(app.pageErrors).toEqual([]);
});

test('minimal transcript preference persists and full mode restores details', async ({ page }) => {
  const app = new MinimalTranscriptHarness(page);
  await app.install();
  await app.goto();
  await app.enableMinimal();
  await expect(page.locator('.minimal-tools')).toHaveCount(1);
  await page.reload();
  await app.openSession();
  await expect(page.locator('.minimal-tools')).toHaveCount(1);
  const toggle = app.detailedMode();
  await expect(toggle).toHaveAttribute('aria-pressed', 'false');
  await expect(toggle).not.toHaveClass(/active/);
  await expect(toggle.locator('svg')).toBeVisible();
  await toggle.click();
  await expect(toggle).toHaveAttribute('aria-pressed', 'true');
  await expect(toggle).toHaveClass(/active/);
  // A click must update the current transcript without reopening the task.
  await expect(page.locator('#stream .minimal-tools')).toHaveCount(0);
  await expect(page.locator('#stream details.tool-call').first()).toBeVisible();
  await app.openSession();
  await expect(page.locator('.minimal-tools')).toHaveCount(0);
  await expect(page.locator('#stream')).toContainText('REASONING_SENTINEL');
  await expect(page.locator('#stream details.tool-call').first()).toBeVisible();
  await page.reload();
  await app.openSession();
  await expect(page.locator('.minimal-tools')).toHaveCount(0);
  await expect(toggle).toHaveAttribute('aria-pressed', 'true');
  await toggle.focus();
  await page.keyboard.press('Space');
  await expect(toggle).toHaveAttribute('aria-pressed', 'false');
  await app.openSession();
  await expect(page.locator('.minimal-tools')).toHaveCount(1);
  await page.reload();
  await app.openSession();
  await expect(toggle).toHaveAttribute('aria-pressed', 'false');
  expect(app.pageErrors).toEqual([]);
});

test('detail toggle stays enabled when a Codex draft gains its working directory', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.codexModels = [{
    id: 'gpt-5.4-codex', displayName: 'GPT-5.4 Codex', isDefault: true,
    defaultReasoningEffort: 'medium',
    supportedReasoningEfforts: [{ reasoningEffort: 'medium', description: 'Balanced' }],
  }];
  // Keep the initial directory-less header visible before the draft reply
  // inserts its workspace label ahead of the buttons.
  app.rpcDelays.set('codex.draft.open', 1000);
  await app.install();
  await app.goto();
  await page.getByRole('button', { name: 'Model', exact: true }).click();
  await page.getByRole('option', { name: 'GPT-5.4 Codex' }).click();
  const terminal = page.getByTitle('Terminal requires an available Codex task placement', { exact: true });
  await expect(terminal).toBeDisabled();
  await expect(page.locator('.codex-topbar .topbar-workspace')).toBeVisible();
  const toggle = page.getByRole('button', { name: 'Detailed mode', exact: true });
  await expect(toggle).toBeEnabled();
  await toggle.click();
  await expect(toggle).toHaveAttribute('aria-pressed', 'true');
  await toggle.click();
  await expect(toggle).toHaveAttribute('aria-pressed', 'false');
  expect(app.pageErrors).toEqual([]);
});

class CodexMinimalHarness extends DesktopBrowserHarness {
  constructor(page, extraItems = []) {
    super(page);
    this.extraItems = extraItems;
  }

  replyFor(request) {
    if (request.method === 'codex.turn.start') {
      return { turn: { id: 'codex-turn-e2e', status: 'completed', items: [
        { id: 'user', type: 'userMessage', content: [{ type: 'text', text: 'Explain the project' }] },
        { id: 'thought', type: 'reasoning', summary: [{ type: 'summary_text', text: 'HIDDEN_CODEX_REASONING' }] },
        { id: 'progress', type: 'agentMessage', phase: 'commentary', text: 'I will inspect the project.' },
        { id: 'command', type: 'commandExecution', command: 'HIDDEN_CODEX_COMMAND', status: 'completed', aggregatedOutput: 'HIDDEN_CODEX_OUTPUT', exitCode: 0 },
        { id: 'spawn', type: 'collabAgentToolCall', tool: 'spawnAgent', status: 'completed' },
        ...this.extraItems,
        { id: 'answer', type: 'agentMessage', phase: 'final_answer', text: 'The project is a desktop assistant.' },
      ] } };
    }
    return super.replyFor(request);
  }
}

test('minimal transcript also collapses Codex final replies and recognizes subagent operations', async ({ page }) => {
  const app = new CodexMinimalHarness(page);
  app.codexModels = [{
    id: 'gpt-5.4-codex', displayName: 'GPT-5.4 Codex', isDefault: true,
    defaultReasoningEffort: 'medium',
    supportedReasoningEfforts: [{ reasoningEffort: 'medium', description: 'Balanced' }],
  }];
  await app.install();
  await app.goto();
  await page.getByRole('button', { name: 'Model', exact: true }).click();
  await page.getByRole('option', { name: 'GPT-5.4 Codex' }).click();
  // The model chip updates before the Codex composer replaces SeekMoon's.
  // Wait for the destination textbox rather than filling the shared old #task.
  await page.getByRole('textbox', { name: 'Ask Codex to inspect, edit, or explain this workspace.', exact: true }).fill('Explain the project');
  await page.getByTitle('Send', { exact: true }).click();
  const stream = page.locator('#stream');
  const process = stream.locator('.minimal-process');
  await expect(process).toHaveCount(1);
  await expect(process.locator(':scope > summary > .minimal-summary-text')).toHaveText('shell · Create subagent');
  await expect(stream.getByText('The project is a desktop assistant.', { exact: true })).toBeVisible();
  await expect(stream.getByText('I will inspect the project.', { exact: true })).toBeHidden();
  await process.locator(':scope > summary').click();
  await process.locator('.minimal-tools > summary').click();
  await expect(process.locator('.minimal-call-caption')).toHaveText(['shell', 'Create subagent']);
  await expect(stream).not.toContainText(/HIDDEN_CODEX_REASONING|HIDDEN_CODEX_OUTPUT|HIDDEN_CODEX_COMMAND/);
  // One preference serves both conversation sources.
  const toggle = page.getByRole('button', { name: 'Detailed mode', exact: true });
  await expect(toggle).toHaveAttribute('aria-pressed', 'false');
  await toggle.click();
  await expect(toggle).toHaveAttribute('aria-pressed', 'true');
  // A click must update the current transcript without reopening the task.
  await expect(stream.locator('.minimal-process, .minimal-tools')).toHaveCount(0);
  await expect(stream.locator('details.tool-call').first()).toBeVisible();
  await app.openSession();
  await expect(page.locator('#stream .minimal-process, #stream .minimal-tools')).toHaveCount(0);
  await expect(page.locator('#stream details.tool-call').first()).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});


test('minimal edit previews share detailed-mode unified lines and preserve call state', async ({ page }, testInfo) => {
  const app = new MinimalTranscriptHarness(page);
  app.sessionEvents = [
    { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture requested edits' } } },
    { sequence: 2, item: { kind: 'assistant', payload: { content: '', tool_calls: [
      { id: 'edit-one', name: 'edit', arguments: JSON.stringify({
        path: 'src/main.mbt', start_line: 12, old_string: 'first\nold\nlast', new_string: 'first\nnew\nlast',
        description: 'Update the entry point', internal: 'PARAMETER_SENTINEL',
      }) },
      { id: 'edit-many', name: 'multi_edit', arguments: JSON.stringify({
        description: 'Update supporting files', edits_file: 'PARAMETER_SENTINEL',
        edits: [
          { file: 'src/add.mbt', old_string: '', new_string: 'added <script>', internal: 'PARAMETER_SENTINEL' },
          { file: 'src/remove.mbt', old_string: 'deleted', new_string: '' },
        ],
      }) },
    ] } } },
  ];
  await app.install();
  await app.goto();
  await app.enableMinimal();
  const stream = page.locator('#stream');
  const tools = stream.locator('.minimal-tools-live');
  await expect(tools.locator('.editor-diff-preview').first()).toBeVisible();
  const calls = tools.locator('.minimal-call');
  await expect(calls.locator('.tool-status.pending')).toHaveCount(2);
  await expect(calls.nth(0).locator('.editor-diff-source')).toHaveText(['first', 'old', 'new', 'last']);
  await expect(calls.nth(0).locator('.editor-diff-sign')).toHaveText(['', '−', '+', '']);
  await expect(calls.nth(0).locator('.edit-path')).toHaveText('src/main.mbt');
  await expect(calls.nth(0).locator('.editor-diff-number')).toHaveText(['12', '13', '13', '14']);
  await expect(calls.locator('.tool-card-chip')).toHaveCount(0);
  await expect(calls.nth(1).locator('.edit-path')).toHaveText(['src/add.mbt', 'src/remove.mbt']);
  await expect(calls.nth(1).locator('.added .editor-diff-source')).toHaveText('added <script>');
  await expect(calls.nth(1).locator('.removed .editor-diff-source')).toHaveText('deleted');
  await expect(calls.locator('.editor-diff-preview script')).toHaveCount(0);
  await expect(tools.locator('summary')).toHaveCount(0);
  for (const [id, name, failed] of [['edit-one', 'edit', false], ['edit-many', 'multi_edit', true]]) {
    app.append('tool_result', { tool_call_id: id, tool_name: name, content: 'OUTPUT_SENTINEL',
      is_error: failed, brief: failed ? 'Batch rejected' : 'Updated entry point' });
  }
  await expect(calls.last().locator('.minimal-call-caption')).toHaveText('Batch rejected');
  await expect(calls.locator('.editor-diff-preview').first()).toBeVisible();
  await expect(calls.nth(1).locator('.tool-status.failed')).toHaveAttribute('aria-label', 'Tool failed');
  await expect(calls.locator('.editor-diff-preview')).toHaveCount(3);
  await expect(stream).not.toContainText('PARAMETER_SENTINEL');
  await expect(stream).not.toContainText('OUTPUT_SENTINEL');
  await expect(stream.locator('.tool-call-tabs')).toHaveCount(0);
  await page.screenshot({ animations: 'disabled', path: testInfo.outputPath('minimal-edit-diffs.png') });
  await page.setViewportSize({ width: 640, height: 900 });
  await page.emulateMedia({ colorScheme: 'dark' });
  for (const block of await calls.locator('.minimal-edit-block').all()) {
    await expect(block.getByRole('button', { name: 'Copy diff', exact: true })).toBeVisible();
    const box = await block.boundingBox();
    expect(box.x + box.width).toBeLessThanOrEqual(640);
  }
  await page.screenshot({ animations: 'disabled', path: testInfo.outputPath('minimal-edit-diffs-dark-narrow.png') });
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.emulateMedia({ colorScheme: 'light' });
  const minimalDiffs = await calls.locator('.editor-diff-source').allTextContents();
  app.append('assistant', { content: 'Finished reviewing the edits.' });
  app.append('terminal', { kind: 'finished', message: 'Finished reviewing the edits.' });
  await expect(stream.locator('.editor-diff-preview').first()).toBeHidden();
  await expect(stream.getByText('Finished reviewing the edits.', { exact: true })).toBeVisible();
  const completed = stream.locator('.minimal-process');
  await expect(completed.locator('.minimal-tools')).toHaveCount(0);
  await completed.locator(':scope > summary').click();
  await expect(completed.locator('.editor-diff-preview').first()).toBeVisible();
  await expect(completed.locator('.editor-diff-preview')).toHaveCount(3);
  await expect(completed.locator('.minimal-call .tool-status.failed')).toHaveAttribute('aria-label', 'Tool failed');

  // Detailed mode keeps the original diff prefixes, while minimal mode uses backgrounds; its
  // Original JSON tabs remain available. Expand parents before tool rows.
  await app.detailedMode().click();
  await app.openSession();
  await expect(stream.locator('details.tool-call')).toHaveCount(2);
  for (const disclosure of await stream.locator('details.activity, details.activity-step-group').all()) {
    if (await disclosure.getAttribute('open') === null) await disclosure.locator(':scope > summary').click();
  }
  for (const disclosure of await stream.locator('details.tool-call').all()) {
    if (await disclosure.getAttribute('open') === null) await disclosure.locator(':scope > summary').click();
  }
  await expect(stream.locator('.tool-diff').first()).toBeVisible();
  expect((await stream.locator('.tool-diff > div').allTextContents()).map(line => line.slice(2))).toEqual(minimalDiffs);
  await expect(stream.getByText('Original JSON', { exact: true }).first()).toBeVisible();
});

test('minimal diff uses syntax colors and change backgrounds', async ({ page }, testInfo) => {
  const app = new MinimalTranscriptHarness(page);
  app.sessionEvents = [
    { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture highlighted edits' } } },
    { sequence: 2, item: { kind: 'assistant', payload: { content: '', tool_calls: [
      { id: 'highlight', name: 'multi_edit', arguments: JSON.stringify({ edits: [
        { file: 'scripts/write-refusals.mbtx', start_line: 297,
          old_string: 'fn main {\n  let message = "before"\n  println(message)\n}',
          new_string: 'fn main {\n  let message = "<script>after</script>"\n  println(message)\n}' },
        { file: 'src/index.js', start_line: 1, old_string: 'const count = 1;', new_string: 'const count = 2;' },
        { file: 'notes.txt', old_string: 'before\n\nend', new_string: 'after\n\nend' },
      ] }) },
    ] } } },
  ];
  await app.install();
  await app.goto();
  await app.enableMinimal();
  const blocks = page.locator('.minimal-edit-block');
  await expect(blocks.first().locator('.added .mtk3')).toHaveText('let');
  await expect(blocks.first().locator('.added .mtk5')).toHaveText('"<script>after</script>"');
  await expect(blocks.first().locator('script')).toHaveCount(0);
  await expect(blocks.nth(1).locator('.added .mtk3')).toHaveText('const');
  await expect(blocks.nth(2).locator('.added .editor-diff-source')).toHaveText('after');
  const blank = blocks.nth(2).locator('.context').first();
  await expect(blank.locator('.editor-diff-source')).toHaveText('');
  expect((await blank.boundingBox()).height).toBeGreaterThan(0);
  for (const colorScheme of ['light', 'dark']) {
    await page.emulateMedia({ colorScheme });
    const colors = await blocks.first().evaluate(block => {
      const add = block.querySelector('.added');
      const del = block.querySelector('.removed');
      return {
        add: getComputedStyle(add).backgroundImage,
        del: getComputedStyle(del).backgroundImage,
        keyword: getComputedStyle(add.querySelector('.mtk3')).color,
        string: getComputedStyle(add.querySelector('.mtk5')).color,
        title: getComputedStyle(block.querySelector('.edit-titlebar')).fontSize,
        code: getComputedStyle(block.querySelector('.editor-diff-preview')).fontSize,
      };
    });
    expect(colors.add).not.toBe(colors.del);
    expect(colors.add).not.toBe('none');
    expect(colors.keyword).not.toBe(colors.string);
    expect(parseFloat(colors.title)).toBeGreaterThan(parseFloat(colors.code));
    await blocks.first().screenshot({ animations: 'disabled', path: testInfo.outputPath(`highlighted-diff-${colorScheme}.png`) });
  }
  expect(app.pageErrors).toEqual([]);
});

test('minimal diff pins line numbers and markers while source scrolls', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 640, height: 900 });
  const app = new MinimalTranscriptHarness(page);
  const source = '  let message = "' + 'long source '.repeat(24) + '"';
  app.sessionEvents = [
    { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture long diff lines' } } },
    { sequence: 2, item: { kind: 'assistant', payload: { content: '', tool_calls: [
      { id: 'long-edit', name: 'edit', arguments: JSON.stringify({
        path: 'desktop/frontend/component_transcript.mbt', start_line: 1529,
        old_string: 'fn main {\n  let message = "before"\n}',
        new_string: `fn main {\n${source}\n}`,
      }) },
    ] } } },
  ];
  await app.install();
  await app.goto();
  await page.getByRole('button', { name: 'Show sidebar', exact: true }).click();
  await app.openSession();
  await expect(page.locator('.app')).toHaveClass(/sidebar-collapsed/);
  const block = page.locator('.minimal-edit-block');
  const diff = block.locator('.editor-diff-preview');
  await expect(block.locator('.added .editor-diff-source')).toHaveText(source);
  for (const colorScheme of ['light', 'dark']) {
    await page.emulateMedia({ colorScheme });
    const title = await block.locator('.edit-titlebar').boundingBox();
    const geometry = await diff.evaluate(el => ({
      width: el.clientWidth, contentWidth: el.scrollWidth,
      heights: [...el.querySelectorAll('.editor-diff-row')].map(row => row.getBoundingClientRect().height),
      widths: [...el.querySelectorAll('.editor-diff-row')].map(row => row.getBoundingClientRect().width),
      lineHeight: parseFloat(getComputedStyle(el).lineHeight),
      pageWidth: document.documentElement.scrollWidth,
    }));
    expect(geometry.contentWidth).toBeGreaterThan(geometry.width);
    expect(geometry.pageWidth).toBeLessThanOrEqual(640);
    for (const height of geometry.heights) expect(height).toBeCloseTo(geometry.lineHeight, 0);
    for (const width of geometry.widths) expect(width).toBeCloseTo(geometry.widths[0], 0);
    const gutters = block.locator('.editor-diff-number, .editor-diff-sign');
    const before = await gutters.evaluateAll(els => els.map(el => el.getBoundingClientRect().x));
    for (const row of await block.locator('.editor-diff-row').all()) {
      const spacing = await row.evaluate(el => {
        const number = el.querySelector('.editor-diff-number');
        const range = document.createRange();
        range.selectNodeContents(number);
        return { number: range.getBoundingClientRect().right,
          marker: el.querySelector('.editor-diff-sign').getBoundingClientRect().x };
      });
      if (spacing.number > 0) expect(spacing.marker - spacing.number).toBeGreaterThanOrEqual(6);
    }
    await diff.evaluate(el => { el.scrollLeft = 160; });
    await expect.poll(() => diff.evaluate(el => el.scrollLeft)).toBe(160);
    expect(await gutters.evaluateAll(els => els.map(el => el.getBoundingClientRect().x))).toEqual(before);
    expect(await block.locator('.edit-titlebar').boundingBox()).toEqual(title);
    await block.hover();
    await expect(block.getByRole('button', { name: 'Copy diff', exact: true })).toBeVisible();
    await block.screenshot({ animations: 'disabled', path: testInfo.outputPath(`scrolling-diff-${colorScheme}.png`) });
    await diff.evaluate(el => { el.scrollLeft = 0; });
  }
  expect(app.pageErrors).toEqual([]);
});

test('minimal edits handle unreadable payloads and bound multi-edit previews', async ({ page }) => {
  const app = new MinimalTranscriptHarness(page);
  const batch = Array.from({ length: 51 }, (_, i) => ({ file: `src/${i}.mbt`, old_string: 'old', new_string: 'new' }));
  batch.splice(1, 0, { file: 'invalid.mbt', old_string: 'missing replacement' });
  const argumentsList = [
    ['edit', '{'],
    ['edit', JSON.stringify({ old_string: 'same', new_string: 'same' })],
    ['multi_edit', JSON.stringify({ edits_file: 'unavailable.json' })],
    ['edit', JSON.stringify({ old_string: 'old', new_string: 'x'.repeat(128001) })],
  ];
  app.sessionEvents = [
    { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture partial edits' } } },
    { sequence: 2, item: { kind: 'assistant', payload: { content: '', tool_calls:
      argumentsList.map(([name, args], i) => ({ id: `edit-${i}`, name, arguments: args })),
    } } },
  ];
  await app.install();
  await app.goto();
  await app.enableMinimal();
  const tools = page.locator('.minimal-tools-live');
  await expect(tools.locator('summary')).toHaveCount(0);
  app.append('assistant', { content: '', tool_calls: [
    { id: 'batch', name: 'multi_edit', arguments: JSON.stringify({ edits: batch }) },
  ] });
  const calls = tools.locator('.minimal-call');
  await expect(calls).toHaveCount(5);
  await expect(calls.last().locator('.editor-diff-preview').first()).toBeVisible();
  for (let i = 0; i < 4; i++) {
    await expect(calls.nth(i).locator('.minimal-call-caption')).toBeVisible();
    await expect(calls.nth(i).locator('.editor-diff-preview')).toHaveCount(0);
  }
  await expect(calls.last().locator('.editor-diff-preview')).toHaveCount(50);
  await expect(calls.last().locator('.edit-omitted')).toContainText('2 more edits not shown');
});

test('minimal job waits name their targets while pending and disappear after success', async ({ page }) => {
  const app = new MinimalTranscriptHarness(page);
  app.sessionEvents = [
    { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture job waits' } } },
    { sequence: 2, item: { kind: 'assistant', payload: { content: '', tool_calls: [
      { id: 'start', name: 'mbtx', arguments: JSON.stringify({ description: 'Run the pr tests', script: 'SCRIPT_SENTINEL' }) },
    ] } } },
    { sequence: 3, item: { kind: 'tool_result', payload: {
      tool_call_id: 'start', tool_name: 'mbtx', brief: 'mbtx → bg bg-2', content: 'OUTPUT_SENTINEL', is_error: false,
    } } },
    { sequence: 4, item: { kind: 'assistant', payload: { content: '', tool_calls: [
      { id: 'wait', name: 'job_wait', arguments: JSON.stringify({ job_ids: ['bg-2', 'bg-2'] }) },
    ] } } },
  ];
  await app.install();
  await app.goto();
  await app.enableMinimal();
  const stream = page.locator('#stream');
  const tools = stream.locator('.minimal-tools-live');
  const caption = 'Wait for job "Run the pr tests" to complete';
  await expect(tools.locator('.minimal-call-caption').last()).toHaveText(caption);

  await expect(tools.locator('.minimal-call-caption')).toHaveText(['Run the pr tests', caption]);
  await expect(tools.locator('.minimal-call .tool-status.pending')).toHaveAttribute('aria-label', 'Tool in progress');
  const notice = 'background job bg-2 finished (exit=0): Run the pr tests';
  app.append('runtime_notice', { content: notice });
  app.append('tool_result', { tool_call_id: 'wait', tool_name: 'job_wait', content: 'WAIT_RESULT_SENTINEL', is_error: false });
  await expect(tools.locator('.minimal-call-caption')).toHaveText(['Run the pr tests']);
  await expect(tools.locator('.minimal-call-caption').last()).toHaveText('Run the pr tests');
  await expect(tools.getByText(notice, { exact: true })).toBeVisible();
  await expect(stream).not.toContainText('WAIT_RESULT_SENTINEL');

  app.append('assistant', { content: '', tool_calls: [
    { id: 'wait-many', name: 'job_wait', arguments: JSON.stringify({ job_ids: ['bg-2', 'bg-unknown'] }) },
  ] });
  await expect(tools.locator('.minimal-call-caption').last()).toHaveText('Wait for any of these jobs to complete: "Run the pr tests", bg-unknown');
  app.append('tool_result', { tool_call_id: 'wait-many', tool_name: 'job_wait', content: 'unknown job', brief: 'Unknown job bg-unknown', is_error: true });
  await expect(tools.locator('.minimal-call-caption')).toHaveText(['Run the pr tests', 'Unknown job bg-unknown']);
  await expect(tools.locator('.minimal-call .tool-status.failed')).toHaveAttribute('aria-label', 'Tool failed');
  await expect(tools.locator('.minimal-call-caption').last()).toHaveText('Unknown job bg-unknown');

  // A wait-only group disappears without leaving an empty activity disclosure.
  app.append('assistant', { content: 'Waiting for another job.', tool_calls: [
    { id: 'wait-only', name: 'job_wait', arguments: JSON.stringify({ job_ids: ['bg-3'] }) },
  ] });
  await expect(stream.locator('.minimal-tools')).toHaveCount(1);
  const singleWait = stream.locator(':scope > .minimal-messages > .minimal-single-call');
  await expect(singleWait.locator('.minimal-call-caption')).toHaveText('Wait for job bg-3 to complete');
  app.append('tool_result', { tool_call_id: 'wait-only', tool_name: 'job_wait', content: 'Woken by user input', is_error: false });
  await expect(stream.locator('.minimal-tools')).toHaveCount(1);
  await expect(stream).not.toContainText('Wait for job bg-3 to complete');
  await expect(singleWait).toHaveCount(0);

  // Full transcript still exposes all three wait calls for inspection.
  await app.detailedMode().click();
  await app.openSession();
  await expect(stream.locator('details.tool-call')).toHaveCount(4);
  expect(app.pageErrors).toEqual([]);
});

test('minimal OpenSeek searches and submit tools use registered activity names', async ({ page }) => {
  const app = new MinimalTranscriptHarness(page);
  const names = ['web_search', 'submit_result', 'submit_answer', 'submit_pattern_repair', 'submit_review', 'finish'];
  app.sessionEvents = [
    { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture built-in activities' } } },
    { sequence: 2, item: { kind: 'assistant', payload: { content: '', tool_calls: names.map(name => ({ id: name, name, arguments: '{}' })) } } },
    ...names.map((name, index) => ({ sequence: index + 3, item: { kind: 'tool_result', payload: {
      tool_call_id: name, tool_name: name, brief: name, content: 'OUTPUT_SENTINEL', is_error: false,
    } } })),
  ];
  await app.install();
  await app.goto();
  await app.enableMinimal();
  const group = page.locator('.minimal-tools-live');
  await expect(group.locator('summary')).toHaveCount(0);
  await expect(group.locator('.minimal-call-caption')).toHaveText(names);
  await expect(group).not.toContainText('OUTPUT_SENTINEL');
});

test('minimal Codex activities render recorded patches without classifying foreign tools as edits', async ({ page }) => {
  const patch = 'diff --git a/main.mbt b/main.mbt\nindex abc..def 100644\n--- a/main.mbt\n+++ b/main.mbt\n@@ -1,2 +1,2 @@\n context\n-old\n\\ No newline at end of file\n+++ new\n\\ No newline at end of file';
  const app = new CodexMinimalHarness(page, [
    { id: 'edit', type: 'fileChange', status: 'completed', changes: [
      { path: 'src/main.mbt', kind: { type: 'update', move_path: null }, diff: patch },
    ] },
    { id: 'send', type: 'collabAgentToolCall', tool: 'sendMessage', status: 'completed' },
    { id: 'image', type: 'imageGeneration', status: 'completed' },
    { id: 'review', type: 'enteredReviewMode', review: 'Review current edits' },
    { id: 'dynamic', type: 'dynamicToolCall', namespace: 'example', tool: 'edit', status: 'completed', success: false,
      arguments: { changes: [{ path: 'FOREIGN_PATCH_SENTINEL', diff: patch }] } },
  ]);
  app.codexModels = [{ id: 'gpt-5.4-codex', displayName: 'GPT-5.4 Codex', isDefault: true,
    defaultReasoningEffort: 'medium', supportedReasoningEfforts: [{ reasoningEffort: 'medium', description: 'Balanced' }] }];
  await app.install();
  await app.goto();
  await page.getByRole('button', { name: 'Model', exact: true }).click();
  await page.getByRole('option', { name: 'GPT-5.4 Codex' }).click();
  // The model chip updates before the Codex composer replaces SeekMoon's.
  // Wait for the destination textbox rather than filling the shared old #task.
  await page.getByRole('textbox', { name: 'Ask Codex to inspect, edit, or explain this workspace.', exact: true }).fill('Explain the project');
  await page.getByTitle('Send', { exact: true }).click();
  const process = page.locator('#stream .minimal-process');
  await expect(process.locator(':scope > summary > .minimal-summary-text')).toHaveText('shell · Create subagent · Changed files · …');
  await expect(process.locator('.editor-diff-preview')).toBeHidden();
  await process.locator(':scope > summary').click();
  const diff = process.locator('.editor-diff-preview');
  await expect(diff).toBeHidden();
  await process.locator('.minimal-tools').filter({ has: page.locator('.editor-diff-preview') }).locator(':scope > summary').click();
  await expect(diff).toBeVisible();
  await expect(diff).toHaveCount(1);
  await expect(diff.locator('.removed .editor-diff-source')).toHaveText(['old']);
  await expect(diff.locator('.added .editor-diff-source')).toHaveText(['++ new']);
  await expect(diff.locator('.context .editor-diff-source')).toHaveText(['context']);
  await expect(diff.locator('.editor-diff-row.gap')).toHaveCount(0);
  await expect(diff.locator('.editor-diff-row')).toHaveCount(3);
  await expect(process.locator('.edit-path')).toHaveText('src/main.mbt');
  await expect(process.locator('.minimal-call-caption').last()).toHaveText('dynamic__example__edit');
  await expect(process.locator('.minimal-call .tool-status.failed')).toHaveAttribute('aria-label', 'Tool failed');
  await expect(process).not.toContainText('FOREIGN_PATCH_SENTINEL');
  expect(app.pageErrors).toEqual([]);
});


for (const scenario of ['partial', 'search-bound', 'append', 'clean', 'recreated']) test(`minimal diff title opens the file without a position check: ${scenario}`, async ({ page, context }) => {
  const app = new MinimalTranscriptHarness(page);
  const source = Array.from({ length: 180 }, (_, i) => `fn line_${i + 1}() -> Int { ${i + 1} }`).join('\n');
  app.gitFilesByRevision[app.gitBaseline]['src/main.mbt'] = source;
  // Later edits do not block opening the file. The requested fragment no
  // longer matches, and the first current hunk is far from the old request.
  app.workingFiles['src/main.mbt'] = scenario === 'clean' ? source : source.replace('Int { 2 }', 'Int { 998 }').replace('Int { 140 }', 'Int { 1000 }');
  if (scenario === 'clean') app.gitChanges = [];
  if (scenario === 'recreated') app.gitChanges = [
    { path: 'src/main.mbt', index_status: 'D', worktree_status: ' ', kind: 'deleted' },
    { path: 'src/main.mbt', index_status: '?', worktree_status: '?', kind: 'untracked' },
  ];
  const old = scenario === 'append' ? '' : '140';
  const modified = scenario === 'append' ? 'fn appended() -> Int { 999 }' : '999';
  const start = scenario === 'append' ? 999999 : scenario === 'search-bound' ? 1 : 140;
  app.rpcDelays.set('git.original_file', 150);
  app.rpcDelays.set('fs.read_file', 75);
  app.sessionEvents = [
    { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture recorded edit' } } },
    { sequence: 2, item: { kind: 'assistant', payload: { content: '', tool_calls: [
      { id: 'recorded', name: scenario === 'search-bound' ? 'multi_edit' : 'edit', arguments: JSON.stringify(scenario === 'search-bound' ? {
        edits: [{ file: 'src/main.mbt', start_line: start, old_string: old, new_string: modified }],
      } : { path: 'src/main.mbt', start_line: start, old_string: old, new_string: modified }) },
    ] } } },
  ];
  await app.install();
  await app.goto();
  await app.enableMinimal();
  const block = page.locator('.minimal-edit-block');
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await block.hover();
  await block.getByRole('button', { name: 'Copy diff', exact: true }).click();
  await expect.poll(() => page.evaluate(() => navigator.clipboard.readText())).toBe(old ? `- ${old}\n+ ${modified}` : `+ ${modified}`);
  const title = block.getByRole('button', { name: 'src/main.mbt', exact: true });
  await title.click();
  await expect(page.locator('#viewer-host')).toBeVisible();
  await expect(page.locator('#viewer-host')).toContainText('line_1()');
  await expect(page.locator('#viewer-host')).toContainText(scenario === 'clean' ? 'Int { 2 }' : 'Int { 998 }');
  await expect(page.locator('#diff-editor-host')).toBeHidden();
  await expect(page.locator('.semantic-review')).toBeHidden();
  await title.click();
  await expect(page.locator('#viewer-host')).toBeVisible();
  await expect(page.locator('.editor-tab')).toHaveCount(1);
  await expect.poll(() => app.requests.filter(r => r.method === 'fs.read_file' && r.params.path === '/workspace/src/main.mbt').length).toBeGreaterThan(0);
  expect(app.requests.filter(r => r.method === 'host.open_path').map(r => r.params.path)).toEqual(['src/main.mbt', 'src/main.mbt']);
  expect(app.requests.filter(r => r.method === 'git.original_file')).toHaveLength(0);
  await expect(page.locator('.notification')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('minimal job output and runtime notices preserve recorded text', async ({ page }) => {
  const app = new MinimalTranscriptHarness(page);
  app.sessionEvents = [{ sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture job text' } } }];
  await app.install(); await app.goto(); await app.openSession();
  const stream = page.locator('#stream');
  const briefs = [
    'job bg-1 (running): Build · run tests',
    'job bg-1 (output capture failed: read ): broken): Build · run tests',
    'Could not read job output',
  ];
  for (const [index, brief] of briefs.entries()) {
    const id = `read-${index}`;
    app.append('assistant', { content: '', tool_calls: [{ id, name: 'job_output', arguments: '{"job_id":"bg-1"}' }] });
    app.append('tool_result', { tool_call_id: id, tool_name: 'job_output', content: 'OUTPUT_SENTINEL', brief, is_error: index > 0 });
    await expect(stream.locator('.minimal-call-caption').last()).toHaveText(`Read output of ${brief}`);
    await expect(stream.locator('.minimal-call').last().locator('.tool-status.failed')).toHaveCount(index > 0 ? 1 : 0);
  }
  const original = await stream.locator('.minimal-call').evaluateAll(rows => rows.map(row => row.outerHTML));
  const notices = [
    'background job bg-1 finished (exit=0): `Build · run tests · mbtx run` — read its output with job_output (job_id="bg-1").',
    'background job bg-1 finished (cleanup failed: read ): broken): `Build · run tests` — read its output with job_output (job_id="other").',
    'background job bg-1 finished (exit=0): `Truncated notice',
    'An unrelated runtime notice',
  ];
  for (const notice of notices) {
    app.append('runtime_notice', { content: notice });
    await expect(stream.locator('.minimal-note').last()).toHaveText(notice);
    await expect(stream.locator('.minimal-note').last().locator('.minimal-tool-icon > svg')).toBeVisible();
  }
  expect(await stream.locator('.minimal-call').evaluateAll(rows => rows.map(row => row.outerHTML))).toEqual(original);
  await expect(stream).not.toContainText('OUTPUT_SENTINEL');
  await page.reload(); await app.openSession();
  await expect(stream.locator('.minimal-call-caption')).toHaveText(briefs.map(brief => `Read output of ${brief}`));
  await expect(stream.locator('.minimal-note')).toHaveText(notices);
  await app.detailedMode().click();
  for (const notice of notices) await expect(stream).toContainText(notice);
  expect(app.pageErrors).toEqual([]);
});

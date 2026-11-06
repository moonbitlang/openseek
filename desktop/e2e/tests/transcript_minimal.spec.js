import { test, expect } from './support/test.js';
import { readFileSync } from 'node:fs';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

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

  // The titlebar debug toggle is off while the minimal transcript is shown.
  async enableMinimal() {
    await this.openSession();
    await expect(this.page.locator('#stream .minimal-tools, #stream .minimal-tools-live, #stream .minimal-process, #stream .minimal-single-call').first()).toBeVisible();
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

test('minimal images open by default and preserve manual collapse across updates', async ({ page }) => {
  const app = new MinimalTranscriptHarness(page);
  const png = readFileSync(new URL('../../../deepseek/client/testdata/two-colors.png', import.meta.url)).toString('base64');
  const image = { type: 'image', media_type: 'image/png', data: png };
  app.sessionEvents = [
    { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture image previews' } } },
    { sequence: 2, item: { kind: 'assistant', payload: { content: '', tool_calls: [
      { id: 'picture', name: 'read_image', arguments: '{"path":"PARAMETER_SENTINEL.png"}' },
      { id: 'missing', name: 'read_image', arguments: '{}' },
      { id: 'ptc', name: 'mbtx', arguments: '{"description":"Inspect generated images"}' },
    ] } } },
  ];
  await app.install();
  await app.goto();
  await app.enableMinimal();
  const stream = page.locator('#stream');
  const rows = stream.locator('.minimal-call');
  await expect(rows).toHaveCount(3);
  await expect(stream.locator('.minimal-image-call')).toHaveCount(0);
  app.append('tool_result', {
    tool_call_id: 'picture', tool_name: 'read_image', brief: 'read_image preview.png', is_error: false,
    content: [{ type: 'text', text: 'OUTPUT_SENTINEL' }, image, image],
  });
  const preview = rows.first().locator('.minimal-image-call');
  await expect(preview).toHaveAttribute('open', '');
  await expect(preview.locator('img')).toHaveCount(2);
  await expect(preview.locator('img').first()).toBeVisible();
  await expect.poll(() => preview.locator('img').first().evaluate(img => img.naturalWidth)).toBeGreaterThan(0);
  // Native summary supports keyboard activation as well as clicking.
  await preview.locator('summary').focus();
  await page.keyboard.press('Enter');
  await expect(preview.locator('img').first()).toBeHidden();
  app.append('tool_result', {
    tool_call_id: 'missing', tool_name: 'read_image', brief: 'Cannot read missing.png', is_error: true,
    content: 'OUTPUT_SENTINEL',
  });
  await expect(rows.nth(1).locator('.tool-status.failed')).toBeVisible();
  await expect(rows.nth(1).locator('details')).toHaveCount(0);
  await expect(preview).not.toHaveAttribute('open', '');
  app.append('tool_result', {
    tool_call_id: 'ptc', tool_name: 'mbtx', brief: 'mbtx (exit=0)', is_error: false,
    content: [image],
    data: { ptc_calls: [{
      name: 'read_image', arguments: { path: 'preview.png' }, status: 'done',
      result: { version: 1, content: 'OUTPUT_SENTINEL', is_error: false },
    }] },
  });
  await expect(rows).toHaveCount(4);
  const ptc = rows.nth(2).locator('.minimal-image-call');
  await expect(ptc).toHaveAttribute('open', '');
  await expect(ptc.locator('img')).toBeVisible();
  await expect(preview).not.toHaveAttribute('open', '');
  await preview.locator('summary').click();
  await expect(preview.locator('img').first()).toBeVisible();
  await expect(stream).not.toContainText('OUTPUT_SENTINEL');
  await expect(stream).not.toContainText('PARAMETER_SENTINEL');

  app.append('terminal', { kind: 'finished', message: 'Images inspected.' });
  await page.reload();
  await app.openSession();
  await expect(preview).toHaveAttribute('open', '');
  const process = stream.locator('.minimal-process');
  await process.locator(':scope > summary').click();
  for (const img of await preview.locator('img').all()) {
    await expect(img).toBeVisible();
    await expect(img).toHaveAttribute('src', `data:image/png;base64,${png}`);
  }
  // Narrow layouts keep both the disclosure and the images inside the row.
  await page.setViewportSize({ width: 640, height: 900 });
  await expect(preview.locator('img').first()).toBeVisible();
  expect(await preview.evaluate(node => node.scrollWidth <= node.clientWidth)).toBe(true);
  expect(app.pageErrors).toEqual([]);
});

for (const retired of [false, true]) test(`minimal image collapse survives preceding PTC insertion (retired=${retired})`, async ({ page }) => {
  const app = new MinimalTranscriptHarness(page);
  const png = readFileSync(new URL('../../../deepseek/client/testdata/two-colors.png', import.meta.url)).toString('base64');
  app.sessionEvents = [
    { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture stable image rows' } } },
    { sequence: 2, item: { kind: 'assistant', payload: { content: '', tool_calls: [
      { id: 'earlier', name: 'mbtx', arguments: '{"description":"Earlier script"}' },
      { id: 'picture', name: 'read_image', arguments: '{}' },
    ] } } },
    { sequence: 3, item: { kind: 'tool_result', payload: {
      tool_call_id: 'picture', tool_name: 'read_image', brief: 'read_image later.png', is_error: false,
      content: [{ type: 'image', media_type: 'image/png', data: png }],
    } } },
  ];
  await app.install();
  await app.goto();
  await app.enableMinimal();
  if (retired) {
    app.append('assistant', { content: 'Continuing while the script runs.' });
    await page.locator('.minimal-tools > summary').click();
  }
  const preview = page.locator('.minimal-image-call');
  await expect(preview.locator('img')).toBeVisible();
  await preview.locator('summary').click();
  await expect(preview).not.toHaveAttribute('open', '');
  const original = await preview.elementHandle();
  app.append('tool_result', {
    tool_call_id: 'earlier', tool_name: 'mbtx', content: '', is_error: false,
    data: { ptc_calls: [{
      name: 'read_image', arguments: { path: 'earlier.png' }, status: 'done',
      result: { version: 1, content: 'Earlier image metadata', is_error: false },
    }] },
  });
  await expect(page.locator('.minimal-call-caption')).toHaveText(['Earlier script', 'read_image', 'read_image later.png']);
  await expect(preview).not.toHaveAttribute('open', '');
  expect(await original.evaluate(node => node.isConnected)).toBe(true);
  await expect(preview.locator('img')).toBeHidden();
  await preview.locator('summary').click();
  await expect(preview.locator('img')).toBeVisible();
  expect(app.pageErrors).toEqual([]);
});

test('minimal transcript groups live tools and folds completed work around user messages', { tag: '@motion' }, async ({ page }) => {
  const app = new MinimalTranscriptHarness(page);
  const nextProse = app.sessionEvents.pop().item.payload;
  await app.install();
  await app.goto();
  await app.openSession();
  const liveCalls = page.locator('.minimal-tools-live .minimal-call');
  await expect(liveCalls).toHaveCount(3);
  for (const call of await liveCalls.all()) await expect(call).toBeVisible();
  app.append('assistant', nextProse);
  await expect(page.locator('.minimal-tools')).toHaveCount(1);
  await expect(page.locator('.minimal-tools .minimal-call').first()).toBeHidden();
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
  await expect(stream.getByRole('button', { name: 'Copy assistant message as Markdown', exact: true })).toHaveCount(1);
  // Minimal mode mirrors detailed mode's finish line: the confirmed final
  // answer carries its durable commit instant beside the copy action.
  await expect(stream.locator('.assistant-message-actions .assistant-message-time')).toHaveCount(1);
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

for (const replayed of [false, true]) test(`minimal transcript clears jump to latest when folded content fits the viewport${replayed ? ' on first history expansion' : ''}`, async ({ page }) => {
  const app = new MinimalTranscriptHarness(page);
  app.sessionEvents[5].item.payload.content = Array.from(
    { length: 60 }, (_, index) => `Progress paragraph ${index}.`,
  ).join('\n\n');
  const terminal = { kind: 'finished', message: 'Finished checking.' };
  if (replayed) {
    app.sessionEvents.push({
      sequence: app.sessionEvents.at(-1).sequence + 1,
      item: { kind: 'terminal', payload: terminal },
    });
  }
  await app.install();
  await app.goto();
  await app.enableMinimal();
  const transcript = page.locator('#transcript');
  const jump = page.getByTitle('Jump to latest', { exact: true });
  if (!replayed) {
    await expect.poll(() => transcript.evaluate(node => node.scrollHeight - node.clientHeight))
      .toBeGreaterThan(1000);
    await transcript.evaluate(node => { node.scrollTop = 0; });
    await expect(jump).toBeVisible();

    // Collapsing from scrollTop=0 changes the available range without a scroll
    // event. The old unpinned state must not leave a button over the summary.
    app.append('terminal', terminal);
  }
  await expect(page.locator('.minimal-process')).toHaveCount(1);
  await expect.poll(() => transcript.evaluate(node => node.scrollHeight - node.clientHeight)).toBe(0);
  await expect(jump).toBeHidden();

  const summary = page.locator('.minimal-process > summary');
  await summary.click();
  await expect.poll(() => transcript.evaluate(node => node.scrollHeight - node.clientHeight))
    .toBeGreaterThan(1000);
  // The reader was pinned while everything fit, so it follows the expansion
  // to the tail one render later. Scroll away only after that follow lands;
  // an earlier scroll is overridden and leaves the reader pinned.
  await expect.poll(() => transcript.evaluate(node => node.scrollHeight - node.scrollTop - node.clientHeight))
    .toBeLessThanOrEqual(4);
  await transcript.evaluate(node => { node.scrollTop = 0; });
  await expect(jump).toBeVisible();
  await summary.click();
  await expect.poll(() => transcript.evaluate(node => node.scrollHeight - node.clientHeight)).toBe(0);
  await expect(jump).toBeHidden();
  expect(app.pageErrors).toEqual([]);
});

test('minimal diff pins line numbers and markers while source scrolls', async ({ page }) => {
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
  await app.showSidebar();
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
    await diff.evaluate(el => { el.scrollLeft = 0; });
  }
  expect(app.pageErrors).toEqual([]);
});

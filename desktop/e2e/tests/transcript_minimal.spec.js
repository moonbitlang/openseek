import { test, expect } from '@playwright/test';
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

  async enableMinimal() {
    await this.openSession();
    const toggle = this.page.locator('.topbar').getByRole('button', { name: 'Transcript details', exact: true });
    await expect(toggle).toHaveAttribute('aria-pressed', 'false');
    await expect(toggle.locator('svg')).toHaveCount(1);
  }

  append(kind, payload) {
    const sequence = (this.sessionEvents.at(-1)?.sequence || 0) + 1;
    const event = { sequence, item: { kind, payload } };
    this.sessionEvents.push(event);
    this.notify('session.event', {
      session: 'session-1', session_root: '/workspace/.openseek', sequence, event,
    });
  }
}

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
  await expect(tools.locator('summary')).toHaveText('Check project details');
  await expect(stream.getByText('I will explore this project.', { exact: true })).toBeVisible();
  await expect(stream.getByText('Now I can check the remaining details.', { exact: true })).toBeVisible();
  await expect(tools).not.toHaveAttribute('open', '');
  await page.screenshot({ animations: 'disabled', path: testInfo.outputPath('minimal-working.png') });
  await tools.locator('summary').focus();
  await page.keyboard.press('Enter');
  await expect(tools.locator('.minimal-call-caption')).toHaveText([
    'Read the project manifest', 'Cannot read the second file', 'Check project details',
  ]);
  await expect(tools.locator('.minimal-call-status').last()).toHaveText('Running…');
  const originalTools = await tools.elementHandle();
  app.append('tool_result', {
    tool_call_id: 'script', tool_name: 'mbtx', content: 'OUTPUT_SENTINEL', is_error: false,
    brief: 'mbtx (exit=0)',
  });
  await expect(tools.locator('.minimal-call-caption').last()).toHaveText('Check project details');
  await expect(tools.locator('summary')).toHaveText('Read files · Execute mbtx scripts · 1 tool call failed');
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
  app.append('assistant', { content: 'Here is the **final summary**.' });
  app.append('terminal', { kind: 'finished', message: 'Here is the **final summary**.' });

  const processes = stream.locator('.minimal-process');
  await expect(processes).toHaveCount(2);
  await expect(processes.nth(0).locator(':scope > summary')).toHaveText('Read files · Execute mbtx scripts · 1 tool call failed');
  await expect(processes.nth(1).locator(':scope > summary')).toHaveText('Other tool calls · 1 tool call failed');
  await expect(stream.getByText('I will explore this project.', { exact: true })).toBeHidden();
  await expect(stream.getByText('Please focus on the architecture.', { exact: true })).toBeVisible();
  await expect(stream.locator('.msg-content strong')).toHaveText('final summary');
  await expect(stream.locator('.assistant-message-copy')).toHaveCount(1);
  await page.screenshot({ animations: 'disabled', path: testInfo.outputPath('minimal-completed.png') });
  for (const process of await processes.all()) {
    await process.locator(':scope > summary').click();
    for (const group of await process.locator('.minimal-tools').all()) {
      await group.locator('summary').click();
    }
  }
  await expect(stream.getByText('mcp__example__inspect', { exact: true })).toBeVisible();
  await expect(stream).not.toContainText(/REASONING_SENTINEL|PARAMETER_SENTINEL|OUTPUT_SENTINEL|SCRIPT_SENTINEL/);
  await expect(stream.locator('.tool-call-tabs, .activity-thinking, .assistant-message-time')).toHaveCount(0);
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
  const tools = page.locator('#stream .minimal-tools');
  await expect(tools).toHaveCount(1);
  await expect(tools.locator('summary')).toHaveText('Read test results');
  await expect(page.getByText(notice, { exact: true })).toBeHidden();
  await tools.locator('summary').click();
  await expect(tools.locator('.minimal-call-caption, .minimal-note')).toHaveText([
    'Read the project manifest', 'Cannot read the second file', 'Check project details',
    notice, 'Read test results',
  ]);
  await tools.locator('summary').click();
  app.append('terminal', { kind: 'finished', message: 'The tests passed.' });
  const process = page.locator('#stream .minimal-process');
  await expect(process).toHaveCount(1);
  await expect(page.getByText(notice, { exact: true })).toBeHidden();
  await expect(process.locator(':scope > summary')).toContainText('1 tool call failed');
  await expect(process.locator(':scope > summary')).not.toContainText(/Background activity|Read job output|Wait for jobs|Stop jobs/);
  await process.locator(':scope > summary').click();
  await process.locator('.minimal-tools > summary').click();
  await expect(page.getByText(notice, { exact: true })).toBeVisible();

  // A notice arriving between turns remains independently expandable, without
  // moving it before an already completed answer or presenting it as prose.
  const lateNotice = 'background job bg-2 finished (exit=0): Run remaining checks';
  app.append('runtime_notice', { content: lateNotice });
  await expect(page.locator('#stream > .minimal-tools')).toHaveCount(1);
  await expect(page.getByText(lateNotice, { exact: true })).toBeHidden();
  await page.locator('#stream > .minimal-tools > summary').click();
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
  const checkpoint = page.locator('#stream > .minimal-context-summary');
  await expect(checkpoint).toHaveCount(1);
  await expect(checkpoint.locator('summary')).toHaveText('Context summary');
  await expect(checkpoint.getByRole('heading', { name: 'Handoff Summary' })).toBeHidden();
  const guidance = '[context ceiling] Continue in a new turn.';
  app.append('terminal', { kind: 'finished', message: guidance });
  await expect(page.getByText(guidance, { exact: true })).toBeVisible();
  await expect(checkpoint).toHaveCount(1);
  await expect(page.locator('#stream > .minimal-process')).toHaveCount(1);
  await checkpoint.locator('summary').focus();
  await page.keyboard.press('Enter');
  await expect(checkpoint.getByRole('heading', { name: 'Handoff Summary' })).toBeVisible();
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
  await expect(stream.locator('.minimal-process > summary')).toHaveText('Work completed');
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
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await expect(page.getByText('Minimal transcript', { exact: true })).toHaveCount(0);
  await app.openSession();
  const toggle = page.locator('.topbar').getByRole('button', { name: 'Transcript details', exact: true });
  await expect(toggle).toHaveAttribute('aria-pressed', 'false');
  await expect(toggle).toHaveAttribute('title', 'Show transcript details');
  await expect(toggle).not.toHaveClass(/active/);
  await toggle.click();
  await expect(toggle).toHaveAttribute('aria-pressed', 'true');
  await expect(toggle).toHaveClass(/active/);
  await expect(page.locator('.minimal-tools')).toHaveCount(0);
  await expect(page.locator('#stream')).toContainText('REASONING_SENTINEL');
  await expect(page.locator('#stream details.tool-call').first()).toBeVisible();
  await page.reload();
  await app.openSession();
  await expect(page.locator('.minimal-tools')).toHaveCount(0);
  await expect(toggle).toHaveAttribute('aria-pressed', 'true');
  await expect(toggle).toHaveAttribute('title', 'Hide transcript details');
  await toggle.focus();
  await page.keyboard.press('Space');
  await expect(toggle).toHaveAttribute('aria-pressed', 'false');
  await expect(page.locator('.minimal-tools')).toHaveCount(1);
  await page.reload();
  await app.openSession();
  await expect(toggle).toHaveAttribute('aria-pressed', 'false');
  expect(app.pageErrors).toEqual([]);
});

class CodexMinimalHarness extends DesktopBrowserHarness {
  replyFor(request) {
    if (request.method === 'codex.turn.start') {
      return { turn: { id: 'codex-turn-e2e', status: 'completed', items: [
        { id: 'user', type: 'userMessage', content: [{ type: 'text', text: 'Explain the project' }] },
        { id: 'thought', type: 'reasoning', summary: [{ type: 'summary_text', text: 'HIDDEN_CODEX_REASONING' }] },
        { id: 'progress', type: 'agentMessage', phase: 'commentary', text: 'I will inspect the project.' },
        { id: 'command', type: 'commandExecution', command: 'HIDDEN_CODEX_COMMAND', status: 'completed', aggregatedOutput: 'HIDDEN_CODEX_OUTPUT', exitCode: 0 },
        { id: 'spawn', type: 'collabAgentToolCall', tool: 'spawnAgent', status: 'completed' },
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
  await page.locator('#task').fill('Explain the project');
  await page.getByTitle('Send', { exact: true }).click();
  const stream = page.locator('#stream');
  const process = stream.locator('.minimal-process');
  await expect(process).toHaveCount(1);
  await expect(process.locator(':scope > summary')).toHaveText('Execute commands · Create subagents');
  await expect(stream.getByText('The project is a desktop assistant.', { exact: true })).toBeVisible();
  await expect(stream.getByText('I will inspect the project.', { exact: true })).toBeHidden();
  await process.locator(':scope > summary').click();
  await process.locator('.minimal-tools > summary').click();
  await expect(process.locator('.minimal-call-caption')).toHaveText(['shell', 'Create subagent']);
  await expect(stream).not.toContainText(/HIDDEN_CODEX_REASONING|HIDDEN_CODEX_OUTPUT|HIDDEN_CODEX_COMMAND/);
  const toggle = page.locator('.codex-topbar').getByRole('button', { name: 'Transcript details', exact: true });
  await expect(toggle).toBeEnabled();
  await expect(toggle).toHaveAttribute('aria-pressed', 'false');
  await toggle.click();
  await expect(toggle).toHaveAttribute('aria-pressed', 'true');
  await expect(process).toHaveCount(0);
  await app.openSession();
  await expect(page.locator('.topbar').getByRole('button', { name: 'Transcript details', exact: true }))
    .toHaveAttribute('aria-pressed', 'true');
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
  const tools = stream.locator('.minimal-tools');
  await expect(tools.locator('.tool-diff').first()).toBeVisible();
  const calls = tools.locator('.minimal-call');
  await expect(calls.locator('.minimal-call-status')).toHaveText(['Running…', 'Running…']);
  await expect(calls.nth(0).locator('.tool-diff > div')).toHaveText(['  first', '- old', '+ new', '  last']);
  await expect(calls.nth(0).locator('.tool-card-chip')).toHaveText(['path: src/main.mbt', 'start_line: 12']);
  await expect(calls.nth(1).locator('.tool-card-chip')).toHaveText(['file: src/add.mbt', 'file: src/remove.mbt']);
  await expect(calls.nth(1).locator('.diff-add')).toHaveText('+ added <script>');
  await expect(calls.nth(1).locator('.diff-del')).toHaveText('- deleted');
  await expect(calls.locator('.tool-diff script')).toHaveCount(0);
  // Closing the default-open group is a user choice that result updates keep.
  await tools.locator(':scope > summary').click();
  await expect(calls.locator('.tool-diff').first()).toBeHidden();
  for (const [id, name, failed] of [['edit-one', 'edit', false], ['edit-many', 'multi_edit', true]]) {
    app.append('tool_result', { tool_call_id: id, tool_name: name, content: 'OUTPUT_SENTINEL',
      is_error: failed, brief: failed ? 'Batch rejected' : 'Updated entry point' });
  }
  await expect(tools.locator(':scope > summary')).toHaveText('Edit files · 1 tool call failed');
  await expect(calls.locator('.tool-diff').first()).toBeHidden();
  await tools.locator(':scope > summary').click();
  await expect(calls.locator('.tool-diff').first()).toBeVisible();
  await expect(calls.nth(1).locator('.minimal-call-status')).toHaveText('Failed');
  await expect(calls.locator('.tool-diff')).toHaveCount(3);
  await expect(stream).not.toContainText('PARAMETER_SENTINEL');
  await expect(stream).not.toContainText('OUTPUT_SENTINEL');
  await expect(stream.locator('.tool-call-tabs')).toHaveCount(0);
  await page.screenshot({ animations: 'disabled', path: testInfo.outputPath('minimal-edit-diffs.png') });
  const minimalDiffs = await calls.locator('.tool-diff').allTextContents();
  app.append('assistant', { content: 'Finished reviewing the edits.' });
  app.append('terminal', { kind: 'finished', message: 'Finished reviewing the edits.' });
  await expect(stream.locator('.tool-diff').first()).toBeHidden();
  await expect(stream.getByText('Finished reviewing the edits.', { exact: true })).toBeVisible();

  // The same recorded snippets render identically in detailed mode, whose
  // Original JSON tabs remain available. Expand parents before tool rows.
  await page.getByRole('button', { name: 'Transcript details', exact: true }).click();
  await expect(stream.locator('details.tool-call')).toHaveCount(2);
  for (const disclosure of await stream.locator('details.activity, details.activity-step-group').all()) {
    if (await disclosure.getAttribute('open') === null) await disclosure.locator(':scope > summary').click();
  }
  for (const disclosure of await stream.locator('details.tool-call').all()) {
    if (await disclosure.getAttribute('open') === null) await disclosure.locator(':scope > summary').click();
  }
  await expect(stream.locator('.tool-diff').first()).toBeVisible();
  expect(await stream.locator('.tool-diff').allTextContents()).toEqual(minimalDiffs);
  await expect(stream.getByText('Original JSON', { exact: true }).first()).toBeVisible();
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
  const tools = page.locator('.minimal-tools');
  await expect(tools).not.toHaveAttribute('open', '');
  app.append('assistant', { content: '', tool_calls: [
    { id: 'batch', name: 'multi_edit', arguments: JSON.stringify({ edits: batch }) },
  ] });
  const calls = tools.locator('.minimal-call');
  await expect(calls).toHaveCount(5);
  await expect(calls.last().locator('.tool-diff').first()).toBeVisible();
  for (let i = 0; i < 4; i++) {
    await expect(calls.nth(i).locator('.minimal-call-caption')).toBeVisible();
    await expect(calls.nth(i).locator('.tool-diff')).toHaveCount(0);
  }
  await expect(calls.last().locator('.tool-diff')).toHaveCount(50);
  await expect(calls.last().locator('.edit-omitted')).toContainText('2 edits not shown');
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
  const tools = stream.locator('.minimal-tools');
  const caption = 'Wait for job "Run the pr tests" to complete';
  await expect(tools.locator(':scope > summary')).toHaveText(caption);
  await tools.locator(':scope > summary').click();
  await expect(tools.locator('.minimal-call-caption')).toHaveText(['Run the pr tests', caption]);
  await expect(tools.locator('.minimal-call-status')).toHaveText('Running…');
  const notice = 'background job bg-2 finished (exit=0): Run the pr tests';
  app.append('runtime_notice', { content: notice });
  app.append('tool_result', { tool_call_id: 'wait', tool_name: 'job_wait', content: 'WAIT_RESULT_SENTINEL', is_error: false });
  await expect(tools.locator('.minimal-call-caption')).toHaveText(['Run the pr tests']);
  await expect(tools.locator(':scope > summary')).toHaveText('Execute mbtx scripts');
  await expect(tools.getByText(notice, { exact: true })).toBeVisible();
  await expect(stream).not.toContainText('WAIT_RESULT_SENTINEL');

  app.append('assistant', { content: '', tool_calls: [
    { id: 'wait-many', name: 'job_wait', arguments: JSON.stringify({ job_ids: ['bg-2', 'bg-unknown'] }) },
  ] });
  await expect(tools.locator(':scope > summary')).toHaveText('Wait for any of these jobs to complete: "Run the pr tests", bg-unknown');
  app.append('tool_result', { tool_call_id: 'wait-many', tool_name: 'job_wait', content: 'unknown job', brief: 'Unknown job bg-unknown', is_error: true });
  await expect(tools.locator('.minimal-call-caption')).toHaveText(['Run the pr tests', 'Unknown job bg-unknown']);
  await expect(tools.locator('.minimal-call-status')).toHaveText('Failed');
  await expect(tools.locator(':scope > summary')).toHaveText('Execute mbtx scripts · 1 tool call failed');

  // A wait-only group disappears without leaving an empty activity disclosure.
  app.append('assistant', { content: 'Waiting for another job.', tool_calls: [
    { id: 'wait-only', name: 'job_wait', arguments: JSON.stringify({ job_ids: ['bg-3'] }) },
  ] });
  await expect(tools).toHaveCount(2);
  await expect(tools.last().locator(':scope > summary')).toHaveText('Wait for job bg-3 to complete');
  app.append('tool_result', { tool_call_id: 'wait-only', tool_name: 'job_wait', content: 'Woken by user input', is_error: false });
  await expect(tools).toHaveCount(1);
  await expect(stream).not.toContainText('Wait for job bg-3 to complete');

  // Full transcript still exposes all three wait calls for inspection.
  await page.getByRole('button', { name: 'Transcript details', exact: true }).click();
  await expect(stream.locator('details.tool-call')).toHaveCount(4);
  expect(app.pageErrors).toEqual([]);
});

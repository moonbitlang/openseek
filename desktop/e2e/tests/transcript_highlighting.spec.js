import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('read workflow shows selectors and highlights each MoonBit file in a mixed batch', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  const output = [
    '=== "src/main.mbt" ===',
    '120 |let answer = 42',
    '<system>start_line=120 shown_lines=1 total_lines=200 truncated=false</system>',
    '=== "README.md" ===',
    '1 |# Documentation <literal>',
    '<system>start_line=1 shown_lines=1 total_lines=1 truncated=false</system>',
    '=== "lib.mbti" ===',
    '1 |pub fn answer() -> Int',
    '<system>start_line=1 shown_lines=1 total_lines=1 truncated=false</system>',
    '',
  ].join('\n');
  app.sessionEvents = [
    { sequence: 1, item: { kind: 'user', payload: { origin: 'human', content: 'Show the browser fixture file reads' } } },
    { sequence: 2, item: { kind: 'assistant', payload: {
      content: '', tool_calls: [{ id: 'read-workflow', name: 'mbtx', arguments: JSON.stringify({
        filename: '@builtin/read.mbtx', args: ['src/main.mbt:120:120', 'README.md', 'lib.mbti'],
      }) }],
    } } },
    { sequence: 3, item: { kind: 'tool_result', payload: {
      tool_call_id: 'read-workflow', tool_name: 'mbtx', content: output,
      is_error: false, brief: 'mbtx (exit=0)',
    } } },
  ];
  await app.install();
  await app.goto();
  await app.openSession();
  const call = page.locator('#transcript details.tool-call');
  await expect(call.locator('.tool-call-text')).toContainText('@builtin/read.mbtx');
  await call.locator('.tool-call-summary').click();
  await call.getByText('Filename', { exact: true }).click();
  await expect(call.locator('.mbtx-args')).toContainText('src/main.mbt:120:120');
  await expect(call.locator('.mbtx-args')).toContainText('README.md');
  const result = page.locator('#transcript details.tool-result');
  await result.locator('.tool-result-summary').click();
  await result.getByText('Output', { exact: true }).click();
  const rendered = result.locator('pre.tool-call-output');
  await expect(rendered.locator('.read-moonbit-output')).toHaveCount(2);
  await expect(rendered.locator('.read-moonbit-gutter')).toHaveText(['120', '1']);
  await expect(rendered.locator('span[class^="mtk"]').first()).toBeVisible();
  await expect(rendered).toContainText('# Documentation <literal>');
  await result.getByText('Original output', { exact: true }).click();
  await expect(result.locator('pre.tool-card-original-json:visible')).toHaveText(output);
  expect(app.pageErrors).toEqual([]);
});

for (const language of ['', 'mbt']) {
  test(`reasoning highlights ${language || 'unlabelled'} code only after completion`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    app.sessionEvents = [{
      sequence: 1,
      item: { kind: 'user', payload: { origin: 'human', content: 'Show the browser fixture code' } },
    }];
    await app.install();
    await app.goto();
    await app.openSession();
    const run = { run_id: 'highlight-run', session: 'session-1' };
    app.notify('agent.started', {
      ...run, session_root: '/workspace/.openseek', model: 'deepseek-v4-pro', max_steps: 1000,
    });
    const content = `\`\`\`${language}\nlet answer = 42\n\`\`\``;
    app.notify('agent.event', { ...run, event: { event: 'reasoning_delta', content } });
    const thought = page.locator('#transcript details.activity');
    // Live reasoning starts expanded in the restored per-step presentation.
    await expect(thought).toHaveAttribute('open', '');
    const body = thought.locator('.activity-thinking');
    // Even a closed fence stays raw while more reasoning can arrive.
    await expect(body).toHaveText(content);
    await expect(body.locator('pre, code, [class^="mtk"]')).toHaveCount(0);
    app.notify('agent.event', {
      ...run, event: { event: 'reasoning_message', content },
    });
    await expect(body.locator('pre.moonbit-source code')).toHaveText('let answer = 42');
    await expect(body.locator('span[class^="mtk"]').first()).toBeVisible();
    // Further answer deltas must retain the completed reasoning's colors.
    app.notify('agent.event', {
      ...run, event: { event: 'assistant_delta', content: 'The answer is 42.' },
    });
    await expect(body.locator('pre.moonbit-source code')).toHaveText('let answer = 42');
    expect(app.pageErrors).toEqual([]);
  });
}

test('saved reasoning and answers default unlabelled code to MoonBit', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  const content = [
    '```\nlet answer = 42\n```',
    '    let indented = 7',
    '```javascript\nconst explicit = 1;\n```',
  ].join('\n\n');
  app.sessionEvents = [
    { sequence: 1, item: { kind: 'user', payload: { origin: 'human', content: 'Show the browser fixture code' } } },
    { sequence: 2, item: { kind: 'assistant', payload: { content, reasoning_content: content } } },
  ];
  await app.install();
  await app.goto();
  await app.openSession();
  // Saved reasoning starts folded; open it before checking rendered code.
  await page.locator('#transcript details.activity > summary').click();
  for (const selector of ['.activity-thinking', '.msg .msg-content']) {
    const body = page.locator('#transcript').locator(selector);
    await expect(body.locator('pre.moonbit-source')).toHaveCount(2);
    await expect(body.locator('pre.moonbit-source').first().locator('span[class^="mtk"]').first()).toHaveText('let');
    await expect(body.locator('code.language-javascript')).toHaveText('const explicit = 1;');
    await expect(body.locator('code.language-javascript span')).toHaveCount(0);
  }
  expect(app.pageErrors).toEqual([]);
});

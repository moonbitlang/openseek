import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

// These cases exercise the detailed transcript's reasoning and tool cards.
test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => localStorage.setItem('openseek.minimal_transcript', 'false'));
});

// Observe rendered text colors rather than tokenizer-generated class names or
// token segmentation. Exclude line-number gutters from this measurement.
const textColorCount = locator => locator.evaluateAll(elements => {
  const colors = new Set();
  for (const element of elements) {
    const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
    for (let text = walker.nextNode(); text; text = walker.nextNode()) {
      if (text.textContent.trim()) colors.add(getComputedStyle(text.parentElement).color);
    }
  }
  return colors.size;
});

test('read workflow keeps thought, prose and tool order and highlights mixed output', async ({ page }) => {
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
    { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture file reads' } } },
    { sequence: 2, item: { kind: 'assistant', payload: {
      reasoning_content: 'The requested range should be enough.',
      content: 'Inspect the requested files.', tool_calls: [{ id: 'read-workflow', name: 'mbtx', arguments: JSON.stringify({
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
  await page.locator('#transcript details.activity > summary').click();
  const thought = page.getByText('The requested range should be enough.', { exact: true });
  const prose = page.getByText('Inspect the requested files.', { exact: true });
  await expect(thought).toBeVisible();
  await expect(prose).toBeVisible();
  // Wait for the details expansion before checking transcript order.
  await expect.poll(async () => {
    const thoughtBox = await thought.boundingBox();
    const proseBox = await prose.boundingBox();
    const callBox = await call.locator('.tool-call-summary').boundingBox();
    return thoughtBox.y + thoughtBox.height <= proseBox.y &&
      proseBox.y + proseBox.height <= callBox.y;
  }).toBe(true);
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
  const sources = rendered.locator('.read-moonbit-code');
  await expect(sources).toHaveText(['let answer = 42', 'pub fn answer() -> Int']);
  for (const code of await sources.all()) {
    await expect.poll(() => textColorCount(code)).toBeGreaterThan(1);
  }
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
      item: { kind: 'user', payload: { content: 'Show the browser fixture code' } },
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
    { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture code' } } },
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

test('write calls show numbered content highlighted by the path language', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  // Paths with a supported language should render syntax colors; plain text should not.
  const writes = [
    { path: 'src/lib.mbt', content: 'pub fn answer() -> Int {\n  42\n}', highlighted: true },
    { path: 'src/pkg.generated.mbti', content: 'package "demo/src"\n\npub fn answer() -> Int', highlighted: true },
    { path: 'scripts/fix.mbtx', content: 'fn main {\n  println("<b>hi</b>")\n}', highlighted: true },
    { path: 'src/moon.pkg', content: 'import {\n  "moonbitlang/core/json",\n}', highlighted: true },
    { path: 'notes.txt', content: 'plain <notes>\nsecond line', highlighted: false },
  ];
  app.sessionEvents = [
    { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture writes' } } },
    { sequence: 2, item: { kind: 'assistant', payload: {
      content: '', tool_calls: writes.map(({ path, content }, index) => ({
        id: `write-${index}`, name: 'write', arguments: JSON.stringify({ path, content }),
      })),
    } } },
  ];
  await app.install();
  await app.goto();
  await app.openSession();
  const calls = page.locator('#transcript details.tool-call');
  await expect(calls).toHaveCount(writes.length);
  for (const [index, { path, content, highlighted }] of writes.entries()) {
    const call = calls.nth(index);
    await call.locator('.tool-call-summary').click();
    const card = call.locator('.write-args');
    await expect(card.locator('.tool-card-chip')).toContainText(path);
    const lines = content.split('\n');
    await expect(card.locator('.moonbit-gutter')).toHaveText(lines.map((_, line) => String(line + 1)));
    await expect(card.locator('.moonbit-code')).toHaveText(lines);
    const colors = () => textColorCount(card.locator('.moonbit-code'));
    if (highlighted) await expect.poll(colors).toBeGreaterThan(1);
    else await expect.poll(colors).toBe(1);
  }
  const plain = calls.nth(writes.length - 1);
  await plain.getByText('Original JSON', { exact: true }).click();
  await expect(plain.locator('pre.tool-card-original-json:visible')).toContainText('"notes.txt"');
  expect(app.pageErrors).toEqual([]);
});

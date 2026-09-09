import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

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
    const thought = page.locator('#transcript .work-thinking');
    await thought.locator(':scope > summary').click();
    const body = thought.locator('.work-thinking-body');
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
  for (const selector of ['.work-thinking-body', '.msg .msg-content']) {
    const body = page.locator('#transcript').locator(selector);
    await expect(body.locator('pre.moonbit-source')).toHaveCount(2);
    await expect(body.locator('pre.moonbit-source').first().locator('span[class^="mtk"]').first()).toHaveText('let');
    await expect(body.locator('code.language-javascript')).toHaveText('const explicit = 1;');
    await expect(body.locator('code.language-javascript span')).toHaveCount(0);
  }
  expect(app.pageErrors).toEqual([]);
});

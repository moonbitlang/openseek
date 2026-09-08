import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

test('transcript renders editor diagram fences and retains them across updates and themes', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.sessionEvents = [
    { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture diagrams' } } },
    { sequence: 2, item: { kind: 'assistant', payload: { content: [
      '```mermaid\nflowchart LR\nAlpha --> Beta\n```',
      '```d2\na -> b\n```',
      '```diago\nc -> d\n```',
      '```uml\n@startuml\nparticipant Alice\nAlice -> Bob : hello\n@enduml\n```',
      '```plantuml\n@startuml\nparticipant Carol\nCarol -> Dave : hello\n@enduml\n```',
      '```d2\na ->\n```',
      '```mermaid\nnot a diagram <img src=x onerror=alert(1)>\n```',
      '```Mermaid\nflowchart LR\nPlain --> Code\n```',
    ].join('\n\n') } } },
  ];
  await app.install();
  await page.emulateMedia({ colorScheme: 'light' });
  await app.goto();
  await app.openSession();

  const transcript = page.locator('#transcript');
  const mermaid = transcript.locator('.chat-mermaid').first();
  await expect(mermaid.locator('svg')).toBeVisible();
  await expect(mermaid.locator('svg')).toContainText('Alpha');
  await expect(transcript.locator('[data-diagram-language="diago"] svg:not(svg svg)')).toHaveCount(2);
  await expect(transcript.locator('[data-diagram-language="uml"] svg')).toHaveCount(2);
  await expect(transcript.locator('.moonbit-viewer-markdown-diagram-viewport')).toHaveCount(5);
  await expect(transcript.locator('pre code.language-d2')).toHaveText('a ->');
  await expect(transcript.locator('pre code.language-Mermaid')).toContainText('Plain --> Code');
  const invalid = transcript.locator('.chat-mermaid').last();
  await expect(invalid.locator('pre code')).toHaveText('not a diagram <img src=x onerror=alert(1)>');
  await expect(invalid.locator('img, svg')).toHaveCount(0);

  // An unrelated Rabbita update must preserve the imperative subtree.
  const originalSvg = await mermaid.locator('svg').elementHandle();
  const originalD2 = await transcript.locator('.chat-diago svg:not(svg svg)').first().elementHandle();
  await page.locator('#task').fill('Unrelated composer update');
  await expect.poll(() => originalSvg.evaluate(svg => svg.isConnected)).toBe(true);
  await expect.poll(() => originalD2.evaluate(svg => svg.isConnected)).toBe(true);
  await expect(mermaid.locator('svg')).toHaveCount(1);

  // System appearance is a real application input, exercising the full theme
  // projection and a fresh SVG/controller after the async renderer completes.
  await page.emulateMedia({ colorScheme: 'dark' });
  await expect(transcript).toHaveAttribute('data-transcript-theme', 'dark');
  await expect.poll(() => originalSvg.evaluate(svg => svg.isConnected)).toBe(false);
  await expect(mermaid.locator('svg')).toContainText('Beta');
  await expect.poll(() => originalD2.evaluate(svg => svg.isConnected)).toBe(true);
  await expect(transcript.locator('.moonbit-viewer-markdown-diagram-viewport')).toHaveCount(5);

  const workspace = page.locator('.workspace-row[title="/workspace"]');
  await workspace.hover();
  await workspace.getByTitle('New conversation in this project').click();
  await expect(transcript.locator('.chat-mermaid')).toHaveCount(0);
  await app.openSession();
  await expect(transcript.locator('.chat-mermaid').first().locator('svg')).toContainText('Alpha');
  expect(app.pageErrors).toEqual([]);
});

test('transcript keeps escaped Mermaid source when local module loading fails', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  const source = 'flowchart LR\nA["<img src=x onerror=alert(1)>"] --> B';
  app.sessionEvents = [
    { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture fallback' } } },
    { sequence: 2, item: { kind: 'assistant', payload: { content: `\`\`\`mermaid\n${source}\n\`\`\`` } } },
  ];
  await app.install();
  await page.route('**/mermaid/mermaid.esm.min.mjs', route => route.abort());
  await app.goto();
  await app.openSession();
  const diagram = page.locator('#transcript .chat-mermaid');
  await expect(diagram.locator('pre code')).toHaveText(source);
  await expect(diagram.locator('img, svg')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('transcript ignores a Mermaid result after its conversation is removed', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  app.sessionEvents = [
    { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture diagram' } } },
    { sequence: 2, item: { kind: 'assistant', payload: { content: '```mermaid\nflowchart LR\nA --> B\n```' } } },
  ];
  await app.install();
  // Hold the library result while the production transcript is unmounted.
  await page.route('**/mermaid/mermaid.esm.min.mjs', route => route.fulfill({
    contentType: 'text/javascript',
    body: `export default { initialize() {}, render() {
      return new Promise(resolve => { window.completeDiagram = () => resolve({
        svg: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 80"><text>Late</text></svg>'
      }); });
    }};`,
  }));
  await app.goto();
  await app.openSession();
  await expect.poll(() => page.evaluate(() => typeof window.completeDiagram)).toBe('function');
  const oldTarget = await page.locator('#transcript .chat-mermaid').elementHandle();
  const workspace = page.locator('.workspace-row[title="/workspace"]');
  await workspace.hover();
  await workspace.getByTitle('New conversation in this project').click();
  await expect(page.locator('#transcript .chat-mermaid')).toHaveCount(0);
  const disposedHtml = await oldTarget.evaluate(element => element.innerHTML);
  await page.evaluate(() => window.completeDiagram());
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  expect(await oldTarget.evaluate(element => element.innerHTML)).toBe(disposedHtml);
  await expect(page.locator('#transcript .chat-mermaid')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

for (const language of ['mermaid', 'd2', 'diago']) {
  test(`streaming ${language} renders only closed fences, including in committed messages`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    await app.install();
    await app.goto();
    await app.openSession();
    const run = { run_id: 'diagram-run', session: 'session-1' };
    app.notify('agent.started', {
      ...run, session_root: '/workspace/.openseek', model: 'deepseek-v4-pro', max_steps: 1000,
    });
    // Tilde closure also comes from cmark, not a search for triple backticks.
    const fence = language === 'diago' ? '~~~~' : '```';
    let content = fence + language + '\n' + (language === 'mermaid' ? 'flowchart LR\nA --> B' : 'a -> b');
    app.notify('agent.event', { ...run, event: { event: 'assistant_delta', content } });
    const live = page.locator('#transcript .msg.streaming');
    await expect(live.locator('pre code')).toContainText(language === 'mermaid' ? 'A --> B' : 'a -> b');
    for (let i = 0; i < 10; i++) {
      const delta = language === 'mermaid' ? `\nB --> N${i}` : `\nb -> n${i}`;
      content += delta;
      app.notify('agent.event', { ...run, event: { event: 'assistant_delta', content: delta } });
      await expect(live.locator('pre code')).toContainText(language === 'mermaid' ? `N${i}` : `n${i}`);
      // No render target exists, so neither compiler can run for this prefix.
      await expect(live.locator('[data-transcript-diagram], svg')).toHaveCount(0);
    }
    const closing = '\n' + fence + '\n';
    content += closing;
    app.notify('agent.event', { ...run, event: { event: 'assistant_delta', content: closing } });
    await expect(live.locator('svg').first()).toBeVisible();
    const svg = await live.locator('svg').first().elementHandle();
    const tail = '\nFollowing prose.\n\n' + fence + language + '\n' + (language === 'mermaid' ? 'flowchart LR\nFinal --> Done' : 'final -> done');
    content += tail;
    app.notify('agent.event', { ...run, event: { event: 'assistant_delta', content: tail } });
    await expect(live.locator('pre code')).toContainText(language === 'mermaid' ? 'Final --> Done' : 'final -> done');
    await expect(live.locator('[data-transcript-diagram]')).toHaveCount(1);
    expect(await svg.evaluate(node => node.isConnected)).toBe(true);

    // Completion does not change the rule: the first closed diagram renders,
    // and the second unclosed fence stays source in the saved message.
    const sequence = Math.max(...app.sessionEvents.map(event => event.sequence)) + 1;
    app.notify('session.event', {
      session: 'session-1', session_root: '/workspace/.openseek', sequence,
      event: { sequence, item: { kind: 'assistant', payload: { content } } },
    });
    app.notify('agent.event', { ...run, event: { event: 'assistant_message', content } });
    await expect(live).toHaveCount(0);
    const diagrams = page.locator('#transcript [data-transcript-diagram]');
    await expect(diagrams).toHaveCount(1);
    await expect(diagrams.first().locator('svg').first()).toBeVisible();
    await expect(page.locator('#transcript pre code').last()).toHaveText(language === 'mermaid' ? 'flowchart LR\nFinal --> Done' : 'final -> done');
    expect(app.pageErrors).toEqual([]);
  });
}

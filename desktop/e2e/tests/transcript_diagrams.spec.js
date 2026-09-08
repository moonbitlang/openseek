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

test('transcript discards Mermaid results for replaced streaming source and removed conversations', async ({ page }) => {
  const app = new DesktopBrowserHarness(page);
  await app.install();
  // Control only the library completion boundary. The production Markdown,
  // transcript subscription, DOM reconciliation and render queue still run.
  await page.route('**/mermaid/mermaid.esm.min.mjs', route => route.fulfill({
    contentType: 'text/javascript',
    body: `export default {
      initialize() {},
      render(id, source) {
        return new Promise(resolve => {
          (window.diagramRequests ??= []).push({source, complete() {
            resolve({svg: '<svg xmlns="http://www.w3.org/2000/svg" width="200" height="80" viewBox="0 0 200 80"><text x="10" y="30">' +
              (source.includes('Latest') ? 'Latest' : 'Old') + '</text></svg>'});
          }});
        });
      }
    };`,
  }));
  await app.goto();
  await app.openSession();
  app.notify('agent.started', {
    run_id: 'diagram-run', session: 'session-1',
    session_root: '/workspace/.openseek', model: 'deepseek-v4-pro', max_steps: 1000,
  });
  app.notify('agent.event', {
    run_id: 'diagram-run', session: 'session-1',
    event: { event: 'assistant_delta', content: '```mermaid\nflowchart LR\nOld --> B' },
  });
  await expect.poll(() => page.evaluate(() => window.diagramRequests?.length)).toBe(1);
  app.notify('agent.event', {
    run_id: 'diagram-run', session: 'session-1',
    event: { event: 'assistant_delta', content: '\nB --> Latest' },
  });
  const diagram = page.locator('#transcript .chat-mermaid');
  await expect(diagram).toHaveAttribute('data-transcript-diagram-source', /Latest/);
  await page.evaluate(() => window.diagramRequests[0].complete());
  await expect.poll(() => page.evaluate(() => window.diagramRequests.length)).toBe(2);
  await expect(diagram.locator('svg')).toHaveCount(0);
  await page.evaluate(() => window.diagramRequests[1].complete());
  await expect(diagram.locator('svg')).toContainText('Latest');

  // A third request remains pending while the mounted conversation is removed.
  app.notify('agent.event', {
    run_id: 'diagram-run', session: 'session-1',
    event: { event: 'assistant_delta', content: '\nLatest --> End\n```' },
  });
  await expect.poll(() => page.evaluate(() => window.diagramRequests.length)).toBe(3);
  const oldTarget = await diagram.elementHandle();
  const workspace = page.locator('.workspace-row[title="/workspace"]');
  await workspace.hover();
  await workspace.getByTitle('New conversation in this project').click();
  await expect(page.locator('#transcript .chat-mermaid')).toHaveCount(0);
  await page.evaluate(() => window.diagramRequests[2].complete());
  await expect.poll(() => oldTarget.evaluate(element => element.querySelectorAll('svg').length)).toBe(0);
  expect(app.pageErrors).toEqual([]);
});

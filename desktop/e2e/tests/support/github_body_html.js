import { readFileSync } from 'node:fs';
import { DesktopBrowserHarness } from './desktop_browser_harness.js';

export const prURL = 'https://github.com/owner/project/pull/42';
export const fixture = (name, suffix = 'github.html') => readFileSync(new URL(`../../fixtures/github-markdown/${name}.${suffix}`, import.meta.url), 'utf8');

export async function openHTMLPR(page, bodyHTML, { chatSource, comments = [] } = {}) {
  const app = new DesktopBrowserHarness(page);
  app.githubBodyHTML = bodyHTML;
  app.githubCommentsHTML = comments;
  if (chatSource) app.sessionEvents = [
    { sequence: 1, item: { kind: 'user', payload: { content: 'Show the browser fixture HTML' } } },
    { sequence: 2, item: { kind: 'assistant', payload: { content: chatSource } } },
  ];
  const original = app.replyFor.bind(app);
  const item = { number: 42, title: 'HTML rendering fixture', url: prURL, author: 'contributor', draft: false };
  app.replyFor = request => {
    if (request.method === 'github.list') return {
      repository: 'owner/project', repository_url: 'https://github.com/owner/project',
      has_more: false, items: request.params.kind === 'issues' ? [] : [item],
    };
    if (request.method === 'github.pull_request') return {
      item, state: 'OPEN', mergeable: 'MERGEABLE', base: 'main', head: 'feature', body_html: app.githubBodyHTML,
      // Deliberately different: a stale Markdown consumer must not pass this fixture.
      body: 'Legacy Markdown must not be displayed',
      additions: 1, deletions: 0, changed_files: 1, checks: [],
      comments: app.githubCommentsHTML.map((body_html, i) => ({ body_html, body: 'Legacy comment Markdown must not be displayed', author: 'reviewer', created_at: '2026-09-20T08:00:00Z', url: `${prURL}#issuecomment-${i}` })),
      created_at: '2026-09-20T08:00:00Z', reviewers: [], assignees: [], labels: [],
    };
    return original(request);
  };
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openReview();
  await page.getByTitle('New tab', { exact: true }).click();
  await page.getByRole('menu', { name: 'New tab', exact: true }).getByRole('menuitem', { name: 'GitHub', exact: true }).click();
  await page.locator('.github-pulls').getByRole('button', { name: /^HTML rendering fixture,/ }).click();
  const body = page.locator('.github-description .markdown');
  await body.waitFor();
  return { app, body };
}

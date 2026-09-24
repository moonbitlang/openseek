import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { fixture, openHTMLPR, prURL } from './support/github_body_html.js';

test('PR descriptions and comments use GitHub HTML while chat keeps raw HTML as text', async ({ page }, testInfo) => {
  await page.clock.install({ time: new Date('2026-09-20T03:51:43Z') });
  const { app, body } = await openHTMLPR(page, fixture('review-summary'), {
    chatSource: fixture('review-summary', 'md'), comments: [fixture('attributes')],
  });
  await expect(body.getByRole('heading', { name: 'Codex Review Summary' })).toBeVisible();
  await expect(body.locator('markdown-accessiblity-table table[role="table"] th')).toHaveText(['Review', 'Status', 'Commit', 'Review trigger']);
  await expect(body.locator('code.notranslate')).toHaveText('fdab425');
  await expect.poll(() => body.locator('relative-time').evaluate(el => el.shadowRoot?.textContent)).toBe('2 minutes ago');
  const details = body.locator('details');
  await expect(details.getByRole('list')).toBeHidden();
  await details.locator('summary').click();
  await expect(details.locator('li')).toHaveCount(3);
  await expect(details.locator('a.user-mention.notranslate')).toHaveCount(2);
  await expect(details.locator('a.user-mention').first()).toHaveAttribute('data-hovercard-url', '/users/codex/hovercard');
  const comment = page.locator('.github-comment:not(.github-description) .markdown');
  await expect(comment.locator('#user-content-box')).toHaveAttribute('dir', 'rtl');
  await expect(comment.locator('table')).toHaveAttribute('cellpadding', '3');
  await expect(comment.locator('th')).toHaveAttribute('rowspan', '3');
  await expect(comment.locator('details')).toHaveAttribute('name', 'user-content-group');
  await expect(comment.locator('#user-content-link')).toHaveAttribute('href', `${prURL}#box`);
  await expect(page.locator('.github-detail')).not.toContainText('Legacy');
  const chat = page.locator('#transcript');
  await expect(chat.locator('details, relative-time, markdown-accessiblity-table')).toHaveCount(0);
  await expect(chat).toContainText('<!-- codex-pull-request-review-summary -->');
  await expect(chat).toContainText('<relative-time datetime="2026-09-20T03:49:43.007844Z">');
  await expect(chat).toContainText('<details> <summary>');
  await body.screenshot({ path: testInfo.outputPath('github-review-summary.png') });
  expect(app.pageErrors).toEqual([]);
});

test('unchanged bodyHTML preserves native disclosure nodes and changed HTML replaces them', async ({ page }) => {
  await page.clock.install({ time: new Date('2026-09-20T08:00:30Z') });
  const { app, body } = await openHTMLPR(page, fixture('mixed'), { comments: [fixture('mixed')] });
  const comment = page.locator('.github-comment:not(.github-description) .markdown');
  const bodies = [body, comment];
  const handles = [];
  for (const root of bodies) {
    const outer = root.locator('details').first();
    await outer.locator(':scope > summary').click();
    await expect(outer.getByText('Final paragraph still inside', { exact: false })).toBeVisible();
    handles.push(await outer.elementHandle());
  }
  await page.locator('#task').fill('Unrelated render');
  await page.getByRole('button', { name: 'Refresh pull request', exact: true }).click();
  await expect.poll(() => app.requests.filter(r => r.method === 'github.pull_request').length).toBe(2);
  for (const handle of handles) await expect.poll(() => handle.evaluate(el => el.isConnected && el.open)).toBe(true);
  await page.clock.fastForward(90_000);
  for (const root of bodies) await expect.poll(() => root.locator('relative-time').evaluate(el => el.shadowRoot?.textContent)).toContain('2 minutes ago');
  app.githubBodyHTML = app.githubBodyHTML.replaceAll('2026-09-20T08:00:00Z', '2026-09-20T07:00:00Z');
  app.githubCommentsHTML = [app.githubBodyHTML];
  await page.getByRole('button', { name: 'Refresh pull request', exact: true }).click();
  for (const [i, root] of bodies.entries()) {
    await expect(root.locator('relative-time')).toHaveAttribute('datetime', '2026-09-20T07:00:00Z');
    await expect.poll(() => handles[i].evaluate(el => el.isConnected)).toBe(false);
    await expect(root.locator('details').first()).not.toHaveAttribute('open');
  }
  expect(app.pageErrors).toEqual([]);
});

test('GitHub code highlighting and task lists remain native without local diagram enhancements', async ({ page }) => {
  const { app, body } = await openHTMLPR(page, fixture('code'));
  await expect(body.locator('.highlight-source-js .pl-k')).toHaveText('const');
  await expect(body.locator('.highlight-source-js .pl-s')).toHaveText('"Hello GitHub"');
  await expect(body.locator('.highlight-source-mermaid')).toHaveText('flowchart LR\nAlpha --> Beta');
  await expect(body.locator('.highlight-source-d2')).toHaveText('one -> two');
  await expect(body.locator('pre[lang="uml"] code.notranslate')).toContainText('@startuml');
  await expect(body.locator('.chat-code-block, .chat-mermaid, .moonbit-viewer-markdown-diagram-viewport')).toHaveCount(0);
  const tasks = body.locator('input.task-list-item-checkbox');
  await expect(tasks).toHaveCount(2);
  await expect(tasks.nth(0)).toBeChecked();
  await expect(tasks.nth(1)).not.toBeChecked();
  for (const task of await tasks.all()) await expect(task).toBeDisabled();
  expect(app.pageErrors).toEqual([]);
});

test('GitHub media keeps proxy URLs, native playback and responsive sizing', async ({ page }, testInfo) => {
  const requests = [];
  const clip = readFileSync(new URL('../fixtures/github-markdown/clip.webm', import.meta.url));
  await page.emulateMedia({ colorScheme: 'dark' });
  await page.route('https://**/*', route => {
    requests.push(route.request().url());
    if (route.request().url() === 'https://example.com/demo.mp4') return route.fulfill({ contentType: 'video/webm', body: clip });
    return route.fulfill({ contentType: 'image/svg+xml', body: '<svg xmlns="http://www.w3.org/2000/svg" width="80" height="40"><rect width="80" height="40" fill="#729ac4"/></svg>' });
  });
  const { app, body } = await openHTMLPR(page, fixture('media'));
  const image = body.getByRole('img', { name: 'HTML image', exact: true });
  await expect(image).toHaveClass('js-gh-image-fallback');
  await expect(image).toHaveAttribute('data-canonical-src', 'https://example.com/html.png');
  await expect(image).toHaveAttribute('src', /^https:\/\/camo\.githubusercontent\.com\//);
  await expect(image).toHaveAttribute('style', /aspect-ratio: 320 \/ 180/);
  await expect(body.locator('themed-picture')).toHaveAttribute('data-catalyst-inline', 'true');
  const pictureSource = await body.locator('picture source').getAttribute('srcset');
  await expect.poll(() => body.locator('picture img').evaluate(el => el.currentSrc)).toBe(pictureSource);
  await expect.poll(() => body.locator('img').evaluateAll(images => images.every(el => el.naturalWidth === 80))).toBe(true);
  const video = body.locator('video');
  await expect(video).toHaveAttribute('controls', '');
  await expect(video).toHaveAttribute('muted', '');
  await expect(video).toHaveAttribute('src', 'https://example.com/demo.mp4');
  await expect.poll(() => video.evaluate(el => el.readyState)).toBeGreaterThanOrEqual(2);
  await video.press('Space');
  await expect.poll(() => video.evaluate(el => el.currentTime)).toBeGreaterThan(0);
  await video.press('Space');
  await expect.poll(() => video.evaluate(el => el.paused)).toBe(true);
  const handle = await video.elementHandle();
  const position = await video.evaluate(el => el.currentTime);
  await page.getByRole('button', { name: 'Refresh pull request', exact: true }).click();
  await expect.poll(() => app.requests.filter(r => r.method === 'github.pull_request').length).toBe(2);
  await expect.poll(() => handle.evaluate(el => el.isConnected)).toBe(true);
  expect(await video.evaluate(el => el.currentTime)).toBe(position);
  for (const width of [1440, 900]) {
    await page.setViewportSize({ width, height: 900 });
    expect(await body.evaluate(root => [...root.querySelectorAll('img, video, picture')].every(el => el.getBoundingClientRect().width <= root.clientWidth + 1))).toBe(true);
  }
  expect(requests.some(url => url.startsWith('https://camo.githubusercontent.com/'))).toBe(true);
  expect(requests.filter(url => /https:\/\/example\.com\/(?:markdown|html|dark|fallback)\.png/.test(url))).toEqual([]);
  expect(app.requests.filter(r => r.method === 'fs.read_file')).toEqual([]);
  await body.screenshot({ path: testInfo.outputPath('github-inline-media.png') });
  expect(app.pageErrors).toEqual([]);
});

test('GitHub HTML links normalize source URLs, copy correctly and route each click once', async ({ page, context }) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await context.route('https://github.com/**', route => route.fulfill({ contentType: 'text/html', body: '<title>GitHub fixture</title>' }));
  const { app, body } = await openHTMLPR(page, '<p><a href="../blob/main/README.md">Guide</a> <a href="#discussion">Discussion</a></p>');
  const guide = body.getByRole('link', { name: 'Guide', exact: true });
  const discussion = body.getByRole('link', { name: 'Discussion', exact: true });
  const guideURL = 'https://github.com/owner/project/blob/main/README.md';
  await expect(guide).toHaveAttribute('href', guideURL);
  await expect(discussion).toHaveAttribute('href', `${prURL}#discussion`);
  await discussion.click({ button: 'right' });
  const menu = page.getByRole('menu', { name: 'Context menu' });
  await expect(menu.getByRole('menuitem')).toHaveText(['Open in New Tab', 'Copy Link']);
  await menu.getByRole('menuitem', { name: 'Copy Link', exact: true }).click();
  await expect.poll(() => page.evaluate(() => navigator.clipboard.readText())).toBe(`${prURL}#discussion`);
  const originalURL = page.url();
  const opened = [];
  context.on('page', popup => opened.push(popup));
  for (const options of [{}, { modifiers: ['ControlOrMeta'] }, { button: 'middle' }]) {
    const popupPromise = context.waitForEvent('page');
    await guide.click(options);
    const popup = await popupPromise;
    await expect(popup).toHaveURL(guideURL);
    await popup.close();
  }
  expect(opened).toHaveLength(3);
  expect(page.url()).toBe(originalURL);
  expect(app.requests.filter(r => ['shell.open_external', 'browser.open', 'host.open_path'].includes(r.method))).toEqual([]);
  expect(app.pageErrors).toEqual([]);
});

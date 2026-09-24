import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';
import { fixture as htmlFixture } from './support/github_body_html.js';

const oldSource = '///|\npub fn retry_delay(attempt : Int) -> Int {\n  500 * attempt\n}\n\n///|\npub fn max_retries() -> Int {\n  3\n}\n';
const newSource = oldSource.replace('500 *', '250 *').replace('  3\n', '  5\n');
const prURL = 'https://github.com/owner/project/pull/42';
const head = 'b'.repeat(40);
const makeComment = (id, body_html, canDelete = false) => ({ id, body_html, url: `${prURL}#discussion_r${id}`, author: 'reviewer', created_at: '2026-09-20T08:15:00Z', can_delete: canDelete });
const makeThread = (id, side, line) => ({ id, path: 'src/main.mbt', side, line, original_line: line, resolved: false, outdated: false, can_reply: true, can_resolve: true, can_unresolve: false, comments: [makeComment(`${id === 'left' ? 6 : 5}000000001`, side === 'LEFT' ? 'Should we keep the original delay?' : 'Could we add <strong>coverage</strong> for the new limit?')] });

async function openComments(page, { holdReview = false, missingRevision = false, unchangedTail = '' } = {}) {
  const app = new DesktopBrowserHarness(page);
  app.gitFilesByRevision[app.gitBaseline]['src/main.mbt'] = oldSource + unchangedTail;
  app.workingFiles['src/main.mbt'] = newSource + unchangedTail;
  const fixture = { open: true, threads: [makeThread('right', 'RIGHT', 8), makeThread('left', 'LEFT', 3)], failure: undefined };
  fixture.missingRevision = missingRevision;
  if (holdReview) fixture.pendingReview = new Promise(resolve => { fixture.releaseReview = resolve; });
  const fallback = app.replyFor.bind(app);
  app.replyFor = request => {
    if (request.method === 'github.checkout_status') {
      const status = { branch: 'codex/browser-fixture', pull_request_url: prURL, has_open_pull_request: fixture.open };
      return fixture.pendingStatus ? fixture.pendingStatus.then(() => status) : status;
    }
    if (request.method === 'github.list') {
      return { repository: 'owner/project', repository_url: 'https://github.com/owner/project', has_more: false,
        items: request.params.kind === 'issues' ? [] : [{ number: 42, title: 'Current PR', url: prURL, draft: false }] };
    }
    if (request.method === 'github.review') {
      const response = { status: 'ok', review: { url: prURL, head, base: app.gitBaseline, threads: fixture.threads,
        commentable: [{ path: 'src/main.mbt', left_lines: [3, 8], right_lines: Array.from({ length: 9 }, (_, i) => i + 1) }] } };
      return fixture.pendingReview ? fixture.pendingReview.then(() => response) : response;
    }
    if (request.method === 'github.review_file') {
      if (fixture.missingRevision) return { status: 'error', message: 'Could not load this file at the GitHub PR revision. fatal: bad object' };
      const path = request.params.path;
      return { status: 'ok', file: { path, original: app.gitFilesByRevision[app.gitBaseline][path], modified: app.workingFiles[path] } };
    }
    if (request.method === 'github.checkout') {
      const finish = () => {
        if (fixture.checkoutFailure) return { status: 'error', message: fixture.checkoutFailure };
        fixture.missingRevision = false;
        return { status: 'success', branch: 'local-pr' };
      };
      return fixture.pendingCheckout ? fixture.pendingCheckout.then(finish) : finish();
    }
    if (request.method === 'github.review_mutate') {
      if (fixture.failure) return { status: 'error', message: fixture.failure };
      const action = request.params.action;
      if (action.kind === 'reply') fixture.threads.find(t => t.comments[0].id === action.comment).comments.push(makeComment('7000000001', action.body, true));
      if (action.kind === 'post') fixture.threads.push({ ...makeThread('posted', action.side, action.line), comments: [makeComment('8000000001', action.body, true)] });
      if (action.kind === 'delete') fixture.threads.forEach(t => { t.comments = t.comments.filter(c => c.id !== action.comment); });
      if (action.kind === 'resolve') Object.assign(fixture.threads.find(t => t.id === action.thread), { resolved: action.resolved, can_resolve: !action.resolved, can_unresolve: action.resolved });
      return { status: 'ok' };
    }
    return fallback(request);
  };
  await app.install();
  await app.goto();
  await app.openSession();
  await app.openReview();
  await page.getByRole('button', { name: 'Expand panel', exact: true }).click();
  await page.locator('#review-changes-body').getByRole('treeitem', { name: /View diff: src\/main\.mbt/ }).click();
  await page.getByRole('button', { name: 'Line diff', exact: true }).click();
  await page.getByRole('switch', { name: 'GitHub comments' }).click();
  if (!holdReview && !missingRevision) await expect(page.locator('.github-review-inline-block [data-thread-id="right"]')).toBeVisible();
  return { app, fixture };
}

test('mounted GitHub comments, draft failures and focus follow live language changes', async ({ page }, testInfo) => {
  const { app } = await openComments(page);
  const right = page.locator('.github-review-inline-block [data-thread-id="right"]');
  const draft = 'Keep this unsaved draft in its original language.';
  await page.evaluate(() => {
    const setItem = Storage.prototype.setItem;
    Storage.prototype.setItem = function (key, value) {
      if (key.startsWith('seekmoon.github-comment-drafts.v1:')) throw new Error('quota test');
      return setItem.call(this, key, value);
    };
  });
  await right.getByRole('textbox', { name: 'Reply', exact: true }).fill(draft);
  const languages = [
    { tag: 'zh-Hans', label: 'GitHub 评论', reply: '回复', send: '发送', resolve: '解决讨论', line: '第 8 行', error: '草稿仍保留在此窗口中，但无法保存到本地：', mode: 'token' },
    { tag: 'zh-Hant', label: 'GitHub 留言', reply: '回覆', send: '傳送', resolve: '解決討論', line: '第 8 行', error: '草稿仍保留在此視窗中，但無法儲存至本機：', mode: 'tree' },
    { tag: 'ja', label: 'GitHub コメント', reply: '返信', send: '送信', resolve: 'ディスカッションを解決', line: '8 行目', error: '下書きはこのウィンドウに残っていますが、ローカルに保存できませんでした：', mode: 'line' },
    { tag: 'es', label: 'Comentarios de GitHub', reply: 'Responder', send: 'Enviar', resolve: 'Resolver discusión', line: 'Línea 8', error: 'El borrador sigue en esta ventana, pero no se pudo guardar localmente:', mode: 'token' },
    { tag: 'en', label: 'GitHub comments', reply: 'Reply', send: 'Send', resolve: 'Resolve conversation', line: 'Line 8', error: 'Your draft remains in this window, but could not be saved locally:', mode: 'line' },
  ];
  for (const locale of languages) {
    await right.locator('textarea').focus();
    await page.evaluate(tag => {
      Object.defineProperty(navigator, 'languages', { configurable: true, value: [tag] });
      window.dispatchEvent(new Event('languagechange'));
    }, locale.tag);
    await expect(page.getByRole('switch', { name: locale.label, exact: true })).toHaveAttribute('aria-checked', 'true');
    const reply = right.getByRole('textbox', { name: locale.reply, exact: true });
    await expect(reply).toBeFocused();
    await expect(reply).toHaveValue(draft);
    await expect(reply).toHaveAttribute('placeholder', `${locale.reply}…`);
    await expect(right.getByRole('button', { name: locale.send, exact: true })).toBeVisible();
    await expect(right.getByRole('button', { name: locale.resolve, exact: true })).toBeVisible();
    await expect(right.locator('.github-review-thread-location')).toHaveText(locale.line);
    await expect(page.locator('.github-review-error')).toContainText(locale.error);
    await expect(page.locator('.github-review-error')).toContainText('quota test');
    await page.locator(`[data-diff-mode="${locale.mode}"]`).click();
    await expect(right).toBeVisible();
    await expect(reply).toHaveValue(draft);
    await expect(right.locator('.github-review-markdown')).toContainText('Could we add coverage for the new limit?');
    if (locale.tag === 'zh-Hans') await page.screenshot({ path: testInfo.outputPath('github-comments-zh.png') });
  }
  expect(app.requests.filter(request => request.method === 'github.review_mutate')).toHaveLength(0);
  expect(app.pageErrors).toEqual([]);
});

test('inline Review comments render HTML and media and preserve disclosure state across edits', async ({ page }, testInfo) => {
  const requests = [];
  await page.route('https://**/*', route => {
    requests.push(route.request().url());
    return route.fulfill({ contentType: 'image/svg+xml', body: '<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"/>' });
  });
  const { app, fixture } = await openComments(page, { holdReview: true });
  fixture.threads[0].comments[0].body_html = htmlFixture('mixed') + '<p><a href="../blob/main/README.md">Guide</a></p><img alt="Screenshot" src="https://image.example.test/comment.png">';
  fixture.threads[0].comments[0].body = 'Legacy inline Markdown must not be displayed';
  fixture.releaseReview();
  const comment = page.locator('.github-review-inline-block [data-thread-id="right"] .markdown');
  await expect(comment.getByRole('link', { name: 'Guide', exact: true }))
    .toHaveAttribute('href', 'https://github.com/owner/project/blob/main/README.md');
  await expect(comment.getByRole('img', { name: 'Screenshot', exact: true }))
    .toHaveAttribute('src', 'https://image.example.test/comment.png');
  await expect(comment.locator('markdown-accessiblity-table table')).toHaveCount(1);
  await expect(comment.locator('pre.notranslate code.notranslate')).toHaveText('<script>literal code</script>');
  await expect(comment).not.toContainText('Legacy inline Markdown');
  await expect(comment.locator('.transcript-image')).toHaveCount(0);
  await expect.poll(() => comment.locator('img').evaluate(img => img.naturalWidth)).toBe(32);
  expect([...new Set(requests)]).toEqual(['https://image.example.test/comment.png']);
  await expect(comment.locator('details')).toHaveCount(2);
  await expect(comment.locator('table')).toHaveCount(1);
  await expect(comment).not.toContainText('seekmoon-hidden-comment');
  const outer = comment.locator('details').first();
  await outer.locator(':scope > summary').focus();
  await page.keyboard.press('Enter');
  await expect(outer.getByText('Final paragraph still inside', { exact: false })).toBeVisible();
  const handle = await outer.elementHandle();
  await page.locator('.github-review-inline-block [data-thread-id="right"]').getByRole('textbox', { name: 'Reply', exact: true }).fill('Local draft triggers a render');
  await expect.poll(() => handle.evaluate(el => el.isConnected && el.open)).toBe(true);
  await expect.poll(() => comment.locator('relative-time').evaluate(el => Boolean(el.shadowRoot?.textContent))).toBe(true);
  await comment.screenshot({ path: testInfo.outputPath('review-html-comment.png') });
  expect(app.pageErrors).toEqual([]);
});

test('missing PR commits recover from Update checkout with retry, pending feedback and preserved drafts', async ({ page }) => {
  const { app, fixture } = await openComments(page, { missingRevision: true });
  const update = page.getByRole('button', { name: 'Update checkout', exact: true });
  await expect(update).toBeVisible();
  await page.locator('.github-review-unplaced summary').click();
  const reply = page.locator('.github-review-unplaced [data-thread-id="right"]').getByRole('textbox', { name: 'Reply', exact: true });
  await reply.fill('Keep this draft while updating.');
  const activeTab = await page.locator('.editor-tab.active').textContent();
  fixture.checkoutFailure = 'Could not fetch the PR. Check your connection and retry.';
  await update.click();
  await expect(page.locator('.github-checkout-notification')).toContainText(fixture.checkoutFailure);
  await expect(update).toBeEnabled();
  await expect(reply).toHaveValue('Keep this draft while updating.');
  fixture.checkoutFailure = undefined;
  fixture.pendingCheckout = new Promise(resolve => { fixture.releaseCheckout = resolve; });
  const reviews = app.requests.filter(r => r.method === 'github.review').length;
  const changes = app.requests.filter(r => r.method === 'git.changes').length;
  await update.click();
  await expect(page.getByRole('button', { name: 'Updating checkout…', exact: true })).toBeDisabled();
  fixture.releaseCheckout();
  await expect(page.locator('.github-review-error')).toHaveCount(0);
  await expect(update).toHaveCount(0);
  const inline = page.locator('.github-review-inline-block [data-thread-id="right"]');
  await expect(inline).toBeVisible();
  await expect(inline.getByRole('textbox', { name: 'Reply', exact: true })).toHaveValue('Keep this draft while updating.');
  await expect(page.locator('.editor-tab.active')).toHaveText(activeTab);
  expect(app.requests.filter(r => r.method === 'github.review').length).toBeGreaterThan(reviews);
  expect(app.requests.filter(r => r.method === 'git.changes').length).toBeGreaterThan(changes);
  expect(app.requests.filter(r => r.method === 'github.checkout').map(r => r.params)).toEqual([1, 2].map(() => ({
    cwd: '/workspace', repository_url: 'https://github.com/owner/project', number: 42, changes: 'ask', update: true,
  })));
  expect(app.pageErrors).toEqual([]);
});

test('inline discussions work across Line, Token and Tree with shared reply, resolve and delete actions', async ({ page }) => {
  const { app } = await openComments(page);
  const right = page.locator('.github-review-inline-block [data-thread-id="right"]');
  await expect(right.locator('strong').filter({ hasText: 'coverage' })).toBeVisible();
  for (const mode of ['Line', 'Token', 'Tree']) {
    await page.getByRole('button', { name: `${mode} diff`, exact: true }).click();
    const editor = page.locator(mode === 'Line' ? '#diff-editor-host' : `.semantic-review[data-mode="${mode.toLowerCase()}"]`);
    await expect(editor).toBeVisible();
    await expect(right).toBeVisible();
    await expect(page.locator('.github-review-inline-block [data-thread-id="left"]')).toBeVisible();
    const changedLine = editor.locator('.moonbit-diff-editor-modified .view-line').filter({ hasText: /250.*attempt/ });
    await changedLine.hover();
    const pane = changedLine.locator('xpath=ancestor::*[contains(@class,"moonbit-diff-editor-modified")]');
    const feedbackGlyph = pane.locator('.agent-feedback-glyph.line-hover');
    await expect(feedbackGlyph).toBeHidden();
    const toggle = page.getByRole('switch', { name: 'GitHub comments' });
    await toggle.click();
    await expect(right).toHaveCount(0);
    await changedLine.hover();
    await expect(feedbackGlyph).toBeVisible();
    await feedbackGlyph.click();
    const feedback = pane.getByRole('textbox', { name: 'Feedback', exact: true });
    await expect(feedback).toBeVisible();
    await feedback.fill('Local feedback is available with GitHub comments off.');
    await feedback.press('Escape');
    await changedLine.click();
    await toggle.click();
    await expect(right).toBeVisible();
    await changedLine.hover();
    await expect(feedbackGlyph).toBeHidden();
  }
  const reply = right.getByRole('textbox', { name: 'Reply', exact: true });
  await reply.click();
  await reply.pressSequentially('I will cover the last attempt.');
  await expect(reply).toBeFocused();
  expect(app.requests.filter(r => r.method === 'github.review_mutate')).toHaveLength(0);
  await expect.poll(() => page.evaluate(url => JSON.parse(localStorage.getItem(`seekmoon.github-comment-drafts.v1:${url}`) || '[]')[0]?.body, prURL)).toBe('I will cover the last attempt.');
  await right.getByRole('button', { name: 'Send', exact: true }).click();
  await expect(right.getByText('I will cover the last attempt.', { exact: true })).toBeVisible();
  await expect(reply).toHaveValue('');
  await right.getByRole('button', { name: 'Resolve conversation', exact: true }).click();
  await expect(right.getByRole('button', { name: 'Resolved · Show conversation' })).toBeVisible();
  await right.getByRole('button', { name: 'Resolved · Show conversation' }).click();
  await right.getByRole('button', { name: 'Unresolve conversation', exact: true }).click();
  const own = right.locator('[data-comment-id="7000000001"]');
  await own.getByRole('button', { name: 'Delete comment', exact: true }).click();
  await own.getByRole('button', { name: 'Delete', exact: true }).click();
  await expect(own).toHaveCount(0);
  expect(app.requests.filter(r => r.method === 'github.review_mutate').map(r => r.params.action.kind)).toEqual(['reply', 'resolve', 'resolve', 'delete']);
  expect(app.pageErrors).toEqual([]);
});

test('local line draft survives reload, failures and layout changes; Send publishes the anchored revision', async ({ page }) => {
  const { app, fixture } = await openComments(page);
  const editor = page.locator('#diff-editor-host');
  const modified = editor.locator('.moonbit-diff-editor-modified');
  await modified.locator('.view-line').filter({ hasText: /250.*attempt/ }).hover();
  const add = editor.getByRole('button', { name: 'Add line comment', exact: true });
  await expect(add).toBeVisible();
  await add.click();
  let input = page.getByRole('textbox', { name: 'Write a comment' });
  await expect(input).toBeVisible();
  await expect(input).toBeFocused();
  await input.fill('Please test the delay too.');
  const draft = page.locator('.github-review-inline-block').filter({ has: input });
  fixture.failure = 'GitHub rejected this request. Your draft is kept.';
  await draft.getByRole('button', { name: 'Send', exact: true }).click();
  await expect(page.getByRole('alert').filter({ hasText: fixture.failure })).toBeVisible();
  await expect(input).toHaveValue('Please test the delay too.');
  await page.getByRole('button', { name: /Unified diff|Unified layout|Unified/, exact: false }).click();
  await expect(input).toHaveValue('Please test the delay too.');
  await page.reload();
  await app.openSession();
  await app.openReview();
  await page.locator('#review-changes-body').getByRole('treeitem', { name: /View diff: src\/main\.mbt/ }).click();
  await page.getByRole('button', { name: 'Line diff', exact: true }).click();
  await page.getByRole('switch', { name: 'GitHub comments' }).click();
  input = page.getByRole('textbox', { name: 'Write a comment' });
  await expect(input).toHaveValue('Please test the delay too.');
  fixture.failure = undefined;
  await page.locator('.github-review-inline-block').filter({ has: input }).getByRole('button', { name: 'Send', exact: true }).click();
  await expect(page.getByText('Please test the delay too.', { exact: true })).toBeVisible();
  const posted = app.requests.filter(r => r.method === 'github.review_mutate').at(-1).params;
  expect(posted.url).toBe(prURL);
  expect(posted.action).toEqual({ kind: 'post', path: 'src/main.mbt', side: 'RIGHT', line: 3, body: 'Please test the delay too.', head });
  expect(await page.evaluate(url => localStorage.getItem(`seekmoon.github-comment-drafts.v1:${url}`), prURL)).toBeNull();
  expect(app.pageErrors).toEqual([]);
});

test('GitHub comments disable feedback during loading; file switches and refresh do not hide ready comment actions', async ({ page }) => {
  const { app, fixture } = await openComments(page, { holdReview: true });
  const modified = page.locator('#diff-editor-host .moonbit-diff-editor-modified');
  const line = modified.locator('.view-line').filter({ hasText: /250.*attempt/ });
  await line.hover();
  const glyph = modified.locator('.agent-feedback-glyph.line-hover');
  await expect(glyph).toBeHidden();
  const toggle = page.getByRole('switch', { name: 'GitHub comments' });
  await toggle.click();
  await line.hover();
  await expect(glyph).toBeVisible();
  await glyph.click();
  const feedback = modified.getByRole('textbox', { name: 'Feedback', exact: true });
  await expect(feedback).toBeVisible();
  await feedback.fill('Local feedback after turning GitHub comments off.');
  expect(app.requests.filter(r => r.method === 'github.review_mutate')).toHaveLength(0);
  await feedback.press('Escape');
  await toggle.click();
  await line.hover();
  await expect(glyph).toBeHidden();
  fixture.releaseReview();
  fixture.pendingReview = undefined;
  await expect(page.locator('.github-review-inline-block [data-thread-id="right"]')).toBeVisible();
  fixture.pendingReview = new Promise(resolve => { fixture.releaseReview = resolve; });
  await page.getByTitle('Refresh GitHub comments', { exact: true }).click();
  await line.hover();
  const add = page.locator('#diff-editor-host').getByRole('button', { name: 'Add line comment', exact: true });
  await expect(add).toBeVisible();
  await add.click();
  const input = page.getByRole('textbox', { name: 'Write a comment', exact: true });
  await expect(input).toBeFocused();
  await input.fill('Draft without waiting for refreshed discussions.');
  const reads = app.requests.filter(r => r.method === 'github.review').length;
  const files = app.requests.filter(r => r.method === 'github.review_file').length;
  const changes = page.locator('#review-changes-body');
  await changes.getByRole('treeitem', { name: /View diff: src\/lib\.mbt/ }).click();
  await expect.poll(() => app.requests.filter(r => r.method === 'github.review_file').length).toBe(files + 1);
  await changes.getByRole('treeitem', { name: /View diff: src\/main\.mbt/ }).click();
  await expect(input).toHaveValue('Draft without waiting for refreshed discussions.');
  expect(app.requests.filter(r => r.method === 'github.review_file')).toHaveLength(files + 1);
  expect(app.requests.filter(r => r.method === 'github.review')).toHaveLength(reads);
  fixture.releaseReview();
  fixture.pendingReview = undefined;
  await expect(page.getByTitle('Refresh GitHub comments', { exact: true })).toBeEnabled();
  await expect(input).toHaveValue('Draft without waiting for refreshed discussions.');
  expect(app.pageErrors).toEqual([]);
});


test('Panel and Review share PR discovery and a pending refresh closes comments in both surfaces', async ({ page }) => {
  const { app, fixture } = await openComments(page);
  const statusReads = () => app.requests.filter(r => r.method === 'github.checkout_status').length;
  const initial = statusReads();
  await page.getByTitle('New tab', { exact: true }).click();
  await page.getByRole('menu', { name: 'New tab', exact: true }).getByRole('menuitem', { name: 'GitHub', exact: true }).click();
  const panel = page.locator('.github-panel');
  await expect(panel.getByRole('button', { name: 'Update checkout for PR #42', exact: true })).toBeVisible();
  expect(statusReads()).toBe(initial);
  fixture.open = false;
  fixture.pendingStatus = new Promise(resolve => { fixture.releaseStatus = resolve; });
  await panel.getByRole('button', { name: 'Refresh GitHub', exact: true }).click();
  await expect.poll(statusReads).toBe(initial + 1);
  await page.locator('.editor-tab').filter({ hasText: 'main.mbt' }).click();
  await expect(page.locator('#diff-editor-host')).toBeVisible();
  expect(statusReads()).toBe(initial + 1);
  fixture.releaseStatus();
  fixture.pendingStatus = undefined;
  await expect(page.getByRole('switch', { name: 'GitHub comments' })).toHaveCount(0);
  await expect(page.locator('.github-review-inline-block [data-thread-id="right"]')).toHaveCount(0);
  expect(statusReads()).toBe(initial + 1);
  expect(app.pageErrors).toEqual([]);
});

test('comment actions use GitHub patch lines and exclude missing or unchanged sides', async ({ page }) => {
  const { app } = await openComments(page, { unchangedTail: Array.from({ length: 24 }, (_, i) => `// untouched ${i + 1}\n`).join('') });
  const editor = page.locator('#diff-editor-host');
  const action = editor.getByRole('button', { name: 'Add line comment', exact: true });
  await editor.locator('.moonbit-diff-editor-original .view-line').filter({ hasText: /pub.*fn.*retry_delay/ }).hover();
  await expect(action).toBeHidden();
  await editor.locator('.moonbit-diff-editor-original .view-line').filter({ hasText: /500.*attempt/ }).hover();
  await expect(action).toBeVisible();
  await editor.locator('.moonbit-diff-editor-modified .view-line').filter({ hasText: /pub.*fn.*retry_delay/ }).hover();
  await expect(action).toBeVisible();
  await page.mouse.wheel(0, 1200);
  await editor.locator('.moonbit-diff-editor-modified .view-line').filter({ hasText: /^\/\/\s+untouched\s+24$/ }).hover();
  await expect(action).toBeHidden();
  expect(app.requests.filter(r => r.method === 'github.review_mutate')).toEqual([]);
  expect(app.pageErrors).toEqual([]);
});

test('semantic comment actions preserve the full-file coordinate allowed by GitHub', async ({ page }) => {
  const { app } = await openComments(page);
  for (const mode of ['Token', 'Tree']) {
    await page.getByRole('button', { name: `${mode} diff`, exact: true }).click();
    const surface = page.locator(`.semantic-review[data-mode="${mode.toLowerCase()}"]`);
    await surface.locator('.moonbit-diff-editor-original .view-line').filter({ hasText: /^\s*3\s*$/ }).hover();
    await surface.getByRole('button', { name: 'Add line comment', exact: true }).click();
    const input = page.getByRole('textbox', { name: 'Write a comment', exact: true });
    await input.fill(`Coordinate QA in ${mode}`);
    await expect.poll(() => page.evaluate(url => JSON.parse(localStorage.getItem(`seekmoon.github-comment-drafts.v1:${url}`) || '[]'), prURL))
      .toEqual([{ target: { kind: 'line', path: 'src/main.mbt', side: 'LEFT', line: 8, head }, body: `Coordinate QA in ${mode}` }]);
    await page.locator('.github-review-inline-block').filter({ has: input }).getByRole('button', { name: 'Cancel', exact: true }).click();
  }
  expect(app.requests.filter(r => r.method === 'github.review_mutate')).toEqual([]);
  expect(app.pageErrors).toEqual([]);
});

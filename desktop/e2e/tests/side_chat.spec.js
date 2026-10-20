import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

// A side chat is the record `<conversation>-sc-N`: shown in its
// conversation's dock with its own transcript and composer, never as a
// sidebar row, and never reaching into the column beside it.

const event = (sequence, kind, payload) => ({ sequence, item: { kind, payload } });
const mainHistory = [
  event(1, 'user', { content: 'Explain the parser.' }),
  event(2, 'terminal', { kind: 'finished', message: 'The parser reads tokens.' }),
];
const sideHistory = [
  ...mainHistory,
  event(3, 'user', { content: 'An aside about tokens.' }),
  event(4, 'terminal', { kind: 'finished', message: 'Tokens are lexemes.' }),
];

async function setup(page, { questions = [] } = {}) {
  const app = new DesktopBrowserHarness(page);
  let questionGeneration = 1;
  let questionRequests = questions;
  const questionSnapshot = () => ({ generation: questionGeneration, requests: questionRequests });
  app.liveSessions.push({ id: 'session-1-sc-0a1b2c3d', title: 'Rabbita browser fixture', updated_at_ms: 2 });
  app.sessionEvents = mainHistory;
  const original = app.replyFor.bind(app);
  app.replyFor = request => {
    if (request.method === 'user_questions.list') return questionSnapshot();
    if (request.method === 'user_questions.answer') {
      questionRequests = questionRequests.filter(item => item.id !== request.params.id);
      questionGeneration++;
      app.notify('user_questions.changed', questionSnapshot());
      return questionSnapshot();
    }
    if (request.method === 'session.load' && request.params.session === 'session-1-sc-0a1b2c3d') {
      return {
        session: { version: 1, id: 'session-1-sc-0a1b2c3d', events: sideHistory },
        watermark: sideHistory.at(-1).sequence,
        prediction: null,
      };
    }
    return original(request);
  };
  await app.install();
  await app.goto();
  await page.getByText('Rabbita browser fixture', { exact: true }).first().click();
  await expect(page.locator('#transcript')).toContainText('The parser reads tokens.');
  return app;
}

test('a listed side chat is a dock tab beside its conversation, not a sidebar row', async ({ page }) => {
  const app = await setup(page);
  await expect(page.locator('.conversation-row')).toHaveCount(1);
  await page.getByRole('button', { name: 'Show panel', exact: true }).click();
  const tab = page.locator('.editor-tab', { hasText: 'Side chat 1' });
  await expect(tab).toBeVisible();
  await tab.click();
  const side = page.locator('#side-chat-transcript');
  await expect(side).toContainText('Tokens are lexemes.');
  // The column keeps its own conversation and its own scroller.
  await expect(page.locator('#transcript')).not.toContainText('Tokens are lexemes.');
  await expect(page.locator('#transcript')).toHaveCount(1);
  await expect(page.locator('#task')).toHaveCount(1);
  await expect(page.locator('.conversation-row')).toHaveCount(1);
  expect(app.pageErrors).toEqual([]);
});

test('the side chat composer sends to the side chat', async ({ page }) => {
  const app = await setup(page);
  await page.getByRole('button', { name: 'Show panel', exact: true }).click();
  await page.locator('.editor-tab', { hasText: 'Side chat 1' }).click();
  await expect(page.locator('#side-chat-transcript')).toContainText('Tokens are lexemes.');
  const input = page.locator('#side-chat-task');
  await input.fill('One more aside');
  await input.press('Enter');
  await expect.poll(() => app.requests.find(r => r.method === 'agent.start')?.params.session)
    .toBe('session-1-sc-0a1b2c3d');
  // The column's draft and conversation are untouched.
  await expect(page.locator('#task')).toHaveValue('');
  expect(app.pageErrors).toEqual([]);
});

test('a draft typed in the side chat survives hiding the dock', async ({ page }) => {
  const app = await setup(page);
  await page.getByRole('button', { name: 'Show panel', exact: true }).click();
  const tab = page.locator('.editor-tab', { hasText: 'Side chat 1' });
  await tab.click();
  const input = page.locator('#side-chat-task');
  await input.fill('A draft in progress');
  await page.getByRole('button', { name: 'Hide panel', exact: true }).click();
  await expect(input).toHaveCount(0);
  await page.getByRole('button', { name: 'Show panel', exact: true }).click();
  await expect(input).toHaveValue('A draft in progress');
  expect(app.pageErrors).toEqual([]);
});

test('a file mention in a side chat opens in its parent dock without navigating', async ({ page }, testInfo) => {
  const app = await setup(page);
  await page.getByRole('button', { name: 'Show panel', exact: true }).click();
  const sideTab = page.locator('.editor-tab', { hasText: 'Side chat 1' });
  await sideTab.click();
  await expect(page.locator('#side-chat-transcript')).toContainText('Tokens are lexemes.');
  const parentURL = page.url();
  const input = page.locator('#side-chat-task');
  await input.fill('@main');
  await page.locator('.side-chat .completion-item').filter({ hasText: 'src/main.mbt' }).click();
  const mention = page.locator('.side-chat .mention-chip').filter({ hasText: 'src/main.mbt' });
  await expect(mention).toBeVisible();
  await mention.locator('.mention-jump').click();

  // The side chat remains the source of the host request; its parent's
  // visible dock owns the file tab that receives the resolved path.
  await expect.poll(() => app.requests.find(request =>
    request.method === 'host.open_path' || request.method === 'host.open_path_preview')?.params)
    .toMatchObject({ session: 'session-1-sc-0a1b2c3d', cwd: '/workspace', path: 'src/main.mbt' });
  const fileTab = page.locator('.editor-tab.active', { hasText: 'main.mbt' });
  await expect(fileTab).toBeVisible();
  await expect(page.locator('#viewer-host')).toBeVisible();
  await expect(page.locator('#viewer-host')).toContainText(/fn\s+main/);
  await expect(page.locator('#transcript')).toHaveAttribute('data-transcript-session', 'session-1');
  await expect(page.locator('#task')).toHaveValue('');
  await expect(page).toHaveURL(parentURL);
  await page.locator('.app').screenshot({ path: testInfo.outputPath('side-chat-file-in-parent-dock.png') });

  // Both tabs remain in the same strip, and the side chat keeps its draft.
  await sideTab.click();
  await expect(page.locator('#side-chat-task')).toBeVisible();
  await expect(mention).toBeVisible();
  await expect(page.locator('#transcript')).toHaveAttribute('data-transcript-session', 'session-1');
  expect(app.pageErrors).toEqual([]);
});

test('a side chat first restored after its worktree registry reads relative images from the shared checkout', async ({ page }, testInfo) => {
  const app = new DesktopBrowserHarness(page);
  const sideSession = 'session-1-sc-0a1b2c3d';
  const checkout = '/workspace/.worktrees/side-chat-shared';
  const png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aCfoAAAAASUVORK5CYII=';
  const events = [
    ...mainHistory,
    event(3, 'user', { content: 'Show the shared checkout diagram.' }),
    event(4, 'terminal', { kind: 'finished', message: '![Shared checkout diagram](side-diagram.png)' }),
  ];
  app.sessionEvents = mainHistory;
  app.binaryFiles['side-diagram.png'] = { data_base64: png, media_type: 'image/png' };
  const original = app.replyFor.bind(app);
  app.replyFor = request => {
    if (request.method === 'worktree.list') {
      return { worktrees: [{
        name: 'side-chat-shared', sessions: ['session-1', sideSession],
        path: checkout, present: true, branch: 'side-chat-shared', base: 'main', codex_thread: null,
      }] };
    }
    if (request.method === 'session.load' && request.params.session === sideSession) {
      return {
        session: { version: 1, id: sideSession, events },
        watermark: events.at(-1).sequence, prediction: null,
      };
    }
    return original(request);
  };
  await app.install();
  await app.goto();
  await page.getByText('Rabbita browser fixture', { exact: true }).first().click();
  await expect(page.locator('#transcript')).toContainText('The parser reads tokens.');
  // The tooltip is derived from the accepted registry. The side chat is not
  // listed yet, so no earlier load can have supplied its checkout placement.
  await expect(page.locator('.conversation-row.active')).toHaveAttribute('title', /side-chat-shared/);
  expect(app.requests.some(request => request.method === 'session.load' && request.params.session === sideSession)).toBe(false);
  app.liveSessions.push({ id: sideSession, title: 'Rabbita browser fixture', updated_at_ms: 2 });
  app.notify('session.changed', { change: 'created', session: sideSession, workspace: '/workspace' });
  await page.getByRole('button', { name: 'Show panel', exact: true }).click();
  await page.locator('.editor-tab', { hasText: 'Side chat 1' }).click();

  const image = page.locator('#side-chat-transcript img[alt="Shared checkout diagram"]');
  await expect.poll(() => app.requests.find(request =>
    request.method === 'fs.read_file' && request.params?.path === 'side-diagram.png'))
    .toMatchObject({ params: { root: checkout } });
  await expect(image).toHaveAttribute('src', `data:image/png;base64,${png}`);
  expect(app.requests.filter(request => request.method === 'fs.read_file' &&
    request.params?.path === 'side-diagram.png').map(request => request.params.root)).toEqual([checkout]);
  await expect(page.locator('#transcript')).toHaveAttribute('data-transcript-session', 'session-1');
  await page.locator('.app').screenshot({ path: testInfo.outputPath('side-chat-restored-shared-checkout.png') });
  expect(app.pageErrors).toEqual([]);
});

async function selectIn(page, container, text) {
  const paragraph = page.locator(`${container} .msg-content`).getByText(text, { exact: true }).first();
  await paragraph.dblclick({ position: { x: 8, y: 8 } });
}

test('a reply to text selected in the side chat goes into its own composer', async ({ page }) => {
  const app = await setup(page);
  await page.getByRole('button', { name: 'Show panel', exact: true }).click();
  await page.locator('.editor-tab', { hasText: 'Side chat 1' }).click();
  await expect(page.locator('#side-chat-transcript')).toContainText('Tokens are lexemes.');
  await selectIn(page, '#side-chat-transcript', 'Tokens are lexemes.');
  const toolbar = page.getByRole('toolbar', { name: 'Selection actions' });
  await toolbar.getByRole('button', { name: 'Reply', exact: true }).click();
  const reply = page.getByRole('dialog', { name: 'Reply to selection' });
  await expect(reply.locator('blockquote')).toHaveText('Tokens');
  await reply.getByRole('textbox', { name: 'Reply', exact: true }).fill('Quoted reply');
  await reply.getByRole('checkbox', { name: 'Batch', exact: true }).check();
  await reply.getByRole('button', { name: 'Add to message', exact: true }).click();
  await expect(reply).toBeHidden();
  await expect(page.locator('#side-chat-task')).toHaveValue('> Tokens\n\nQuoted reply\n\n');
  // The column's draft is untouched.
  await expect(page.locator('#task')).toHaveValue('');
  expect(app.pageErrors).toEqual([]);
});

test('closing a side chat tab deletes the side chat', async ({ page }) => {
  const app = await setup(page);
  await page.getByRole('button', { name: 'Show panel', exact: true }).click();
  const tab = page.locator('.editor-tab', { hasText: 'Side chat 1' });
  await tab.click();
  await expect(page.locator('#side-chat-transcript')).toContainText('Tokens are lexemes.');
  await tab.locator('.tab-close').click();
  await expect.poll(() => app.requests.find(r => r.method === 'session.delete')?.params.session)
    .toBe('session-1-sc-0a1b2c3d');
  await expect(tab).toHaveCount(0);
  await expect(page.locator('#side-chat-transcript')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('a question asked in the side chat is answered in its pane', async ({ page }) => {
  const app = await setup(page, {
    questions: [{
      id: 'question-1',
      session: 'session-1-sc-0a1b2c3d',
      questions: [{ id: 'scope', title: 'Which scope?', options: ['Keep scope', 'Expand scope'] }],
    }],
  });
  // The column's conversation asked nothing.
  await expect(page.locator('#transcript ~ .user-question-region .user-question-card')).toHaveCount(0);
  await page.getByRole('button', { name: 'Show panel', exact: true }).click();
  await page.locator('.editor-tab', { hasText: 'Side chat 1' }).click();
  const card = page.locator('.side-chat .user-question-card');
  await expect(card).toContainText('Which scope?');
  await card.getByRole('button', { name: 'Keep scope', exact: true }).click();
  await card.getByRole('button', { name: 'Send', exact: true }).click();
  await expect.poll(() => app.requests.find(r => r.method === 'user_questions.answer')?.params)
    .toMatchObject({ session: 'session-1-sc-0a1b2c3d', id: 'question-1', answers: { scope: 'Keep scope' } });
  await expect(card).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

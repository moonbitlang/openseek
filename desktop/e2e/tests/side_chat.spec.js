import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

// A side chat is the record `<conversation>-sc-<token>`, opened from text
// selected in its conversation: shown in that conversation's dock with its
// own transcript and composer, never as a sidebar row, and never reaching
// into the column beside it. It lives only in the page that opened it.

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

async function selectIn(page, container, text) {
  const paragraph = page.locator(`${container} .msg-content`).getByText(text, { exact: true }).first();
  await paragraph.dblclick({ position: { x: 8, y: 8 } });
}

// The conversation in the column, its host forking a side chat of it on
// request. Unless `open` is false, a side chat is opened the way a reader
// opens one, from text selected in the column's transcript.
async function setup(page, {
  questions = [], open = true, main = mainHistory, side = sideHistory, configure = () => {},
} = {}) {
  const app = new DesktopBrowserHarness(page);
  configure(app);
  let questionGeneration = 1;
  let questionRequests = questions;
  const questionSnapshot = () => ({ generation: questionGeneration, requests: questionRequests });
  app.sessionEvents = main;
  const original = app.replyFor.bind(app);
  app.replyFor = request => {
    if (request.method === 'user_questions.list') return questionSnapshot();
    if (request.method === 'user_questions.answer') {
      questionRequests = questionRequests.filter(item => item.id !== request.params.id);
      questionGeneration++;
      app.notify('user_questions.changed', questionSnapshot());
      return questionSnapshot();
    }
    if (request.method === 'session.fork' && request.params.side_chat === true) {
      app.liveSessions.push({ id: 'session-1-sc-0a1b2c3d', title: request.params.source_title, updated_at_ms: 3 });
      return { session: 'session-1-sc-0a1b2c3d', title: request.params.source_title };
    }
    if (request.method === 'session.load' && request.params.session === 'session-1-sc-0a1b2c3d') {
      return {
        session: { version: 1, id: 'session-1-sc-0a1b2c3d', events: side },
        watermark: side.at(-1).sequence,
        prediction: null,
      };
    }
    return original(request);
  };
  await app.install();
  await app.goto();
  await page.getByText('Rabbita browser fixture', { exact: true }).first().click();
  await expect(page.locator('#transcript')).toContainText('The parser reads tokens.');
  if (open) {
    await selectIn(page, '#transcript', 'The parser reads tokens.');
    await page.getByRole('toolbar', { name: 'Selection actions' })
      .getByRole('button', { name: 'Side chat', exact: true }).click();
    await expect(page.locator('#side-chat-transcript')).toContainText('Tokens are lexemes.');
  }
  return app;
}

test('an opened side chat is a dock tab beside its conversation, not a sidebar row', async ({ page }) => {
  const app = await setup(page);
  await expect(page.locator('.conversation-row')).toHaveCount(1);
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

test('a reply to text selected in the side chat goes into its own composer', async ({ page }) => {
  const app = await setup(page);
  await page.locator('.editor-tab', { hasText: 'Side chat 1' }).click();
  await expect(page.locator('#side-chat-transcript')).toContainText('Tokens are lexemes.');
  // Start from an empty draft rather than the quote it opened with.
  await page.locator('#side-chat-task').fill('');
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

test('a selection opens a side chat beside the conversation with the selection quoted', async ({ page }) => {
  const app = await setup(page, { open: false });
  await selectIn(page, '#transcript', 'The parser reads tokens.');
  const toolbar = page.getByRole('toolbar', { name: 'Selection actions' });
  await expect(toolbar.getByRole('button')).toHaveText(['Copy', 'Reply', 'Side chat']);
  await toolbar.getByRole('button', { name: 'Side chat', exact: true }).click();
  await expect.poll(() => app.requests.find(r => r.method === 'session.fork')?.params)
    .toMatchObject({ session: 'session-1', through: 2, side_chat: true });
  const tab = page.locator('.editor-tab', { hasText: 'Side chat 1' });
  await expect(tab).toBeVisible();
  await expect(page.locator('#side-chat-transcript')).toContainText('The parser reads tokens.');
  const input = page.locator('#side-chat-task');
  await expect(input).toHaveValue(/^> The\n\n$/);
  await expect(input).toBeFocused();
  // The column did not move, and the side chat has no sidebar row.
  await expect(page.locator('#transcript')).toContainText('The parser reads tokens.');
  await expect(page.locator('.conversation-row')).toHaveCount(1);
  // A selection inside the side chat replies there, and opens no other.
  await selectIn(page, '#side-chat-transcript', 'The parser reads tokens.');
  await expect(toolbar.getByRole('button')).toHaveText(['Copy', 'Reply']);
  await page.keyboard.press('Escape');
  // Closing the tab deletes the side chat.
  await tab.locator('.tab-close').click();
  await expect.poll(() => app.requests.find(r => r.method === 'session.delete')?.params.session)
    .toBe('session-1-sc-0a1b2c3d');
  await expect(tab).toHaveCount(0);
  await expect(page.locator('#side-chat-transcript')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('a side chat lives only in the page that opened it', async ({ page }) => {
  const app = await setup(page);
  await expect(page.locator('.editor-tab', { hasText: 'Side chat 1' })).toBeVisible();
  // Its record is still listed after a reload, but nothing brings it back.
  await page.reload();
  await page.getByText('Rabbita browser fixture', { exact: true }).first().click();
  await expect(page.locator('#transcript')).toContainText('The parser reads tokens.');
  await expect(page.locator('.conversation-row')).toHaveCount(1);
  // Look in the dock itself, not just a hidden one.
  const show = page.getByRole('button', { name: 'Show panel', exact: true });
  if (await show.count() > 0) await show.click();
  await expect(page.getByRole('button', { name: 'Hide panel', exact: true })).toBeVisible();
  await expect(page.locator('.editor-tab', { hasText: 'Side chat' })).toHaveCount(0);
  expect(app.requests.filter(r => r.method === 'session.load' &&
    r.params.session === 'session-1-sc-0a1b2c3d')).toHaveLength(1);
  expect(app.pageErrors).toEqual([]);
});

test('both running composers keep their own follow-up menus', async ({ page }) => {
  const app = await setup(page, { configure: app => { app.hostSettings.followup_behavior = 'queue'; } });
  const column = page.locator('#task');
  await column.fill('Start a turn');
  await column.press('Enter');
  const sideInput = page.locator('#side-chat-task');
  await sideInput.fill('Start an aside');
  await sideInput.press('Enter');
  await expect.poll(() => app.requests.filter(r => r.method === 'agent.start').map(r => r.params.session).sort())
    .toEqual(['session-1', 'session-1-sc-0a1b2c3d']);
  const sideChoice = page.locator('.side-chat').getByRole('button', { name: 'Follow-up action', exact: true });
  const columnChoice = page.locator('button[aria-label="Follow-up action"]:not(.side-chat *)');
  await expect(sideChoice).toContainText('Queue next');
  await expect(columnChoice).toContainText('Queue next');
  // Choosing in the dock's menu settles the dock's choice alone.
  await sideInput.fill('Correct the aside');
  await sideChoice.focus();
  await sideChoice.press('ArrowDown');
  const sideMenu = page.locator('.side-chat').getByRole('listbox', { name: 'Follow-up action' });
  // Focus moving into the dock's own options keeps its menu open.
  await expect(sideMenu.getByRole('option', { name: /Queue next/ })).toBeFocused();
  await expect(sideMenu).toBeVisible();
  await page.keyboard.press('Home');
  await expect(sideMenu.getByRole('option', { name: 'Steer now', exact: true })).toBeFocused();
  await page.keyboard.press('Enter');
  await expect(sideChoice).toContainText('Steer now');
  await expect(sideChoice).toBeFocused();
  await expect(columnChoice).toContainText('Queue next');
  expect(app.pageErrors).toEqual([]);
});

test('a copied tool call keeps its own tab choice in each transcript', async ({ page }) => {
  await page.addInitScript(() => localStorage.setItem('openseek.minimal_transcript', 'false'));
  const call = { id: 'copied-call', name: 'mbtx', arguments: JSON.stringify({ source: 'fn main { () }', description: 'Copied check' }) };
  const main = [
    event(1, 'user', { content: 'Explain the parser.' }),
    { sequence: 2, item: { kind: 'assistant', payload: { content: '', tool_calls: [call] } } },
    event(3, 'terminal', { kind: 'finished', message: 'The parser reads tokens.' }),
  ];
  const side = [
    ...main,
    event(4, 'user', { content: 'An aside about tokens.' }),
    event(5, 'terminal', { kind: 'finished', message: 'Tokens are lexemes.' }),
  ];
  await setup(page, { main, side });
  const columnCall = page.locator('#transcript details.tool-call');
  const sideCall = page.locator('#side-chat-transcript details.tool-call');
  await columnCall.locator('.tool-call-summary').click();
  await sideCall.locator('.tool-call-summary').click();
  const original = locator => locator.getByRole('radio', { name: 'Original JSON', exact: true });
  // The side chat's label selects the side chat's view, not the column's.
  await sideCall.getByText('Original JSON', { exact: true }).click();
  await expect(original(sideCall)).toBeChecked();
  await expect(original(columnCall)).not.toBeChecked();
  // And the column's choice leaves the side chat's alone.
  await columnCall.getByText('Original JSON', { exact: true }).click();
  await expect(original(columnCall)).toBeChecked();
  await expect(original(sideCall)).toBeChecked();
});

test('a copied message keeps its own changes popup in the side chat', async ({ page }) => {
  const selection = `<file path="src/main.mbt" version="saved-comparison">\n<hunk>\n<original lines="8">\nlet old_value = 1\n</original>\n<modified lines="9">\nlet saved_value = 2\n</modified>\n</hunk>\n</file>`;
  const ask = `Explain the parser.\n\n<user_mentions>\n<review_changes workspace="/workspace">\n${selection}\n</review_changes>\n</user_mentions>`;
  const main = [
    event(1, 'user', { content: ask }),
    event(2, 'terminal', { kind: 'finished', message: 'The parser reads tokens.' }),
  ];
  const side = [
    ...main,
    event(3, 'user', { content: 'An aside about tokens.' }),
    event(4, 'terminal', { kind: 'finished', message: 'Tokens are lexemes.' }),
  ];
  const app = await setup(page, { main, side });
  const sideChip = page.locator('#side-chat-transcript .user-bubble .changes-chip .mention-jump');
  await sideChip.click();
  const popup = page.locator('.side-chat').getByRole('dialog', { name: 'Selected changes' });
  await expect(popup).toContainText('let saved_value = 2');
  // Working inside the dock's popup does not count as leaving it.
  await popup.getByTitle('src/main.mbt', { exact: true }).click();
  await expect(popup).toBeVisible();
  await expect(popup.locator('.changes-preview')).toHaveCount(0);
  await popup.getByTitle('src/main.mbt', { exact: true }).click();
  await expect(popup.locator('.changes-preview')).toContainText('let saved_value = 2');
  expect(app.pageErrors).toEqual([]);
});

test('a file link in the side chat transcript opens as the side chat, in its parent dock', async ({ page }) => {
  const side = [
    ...mainHistory,
    event(3, 'user', { content: 'Where is the entry point?' }),
    event(4, 'terminal', { kind: 'finished', message: 'Tokens are lexemes. See [the entry](src/main.mbt).' }),
  ];
  const app = await setup(page, { side });
  await page.locator('#side-chat-transcript').getByRole('button', { name: 'the entry', exact: true }).click();
  // The host resolves the path for the side chat, whose tools then reach
  // what opens; the tab shows in the conversation's dock beside it.
  await expect.poll(() => app.requests.find(request =>
    request.method === 'host.open_path' || request.method === 'host.open_path_preview')?.params)
    .toMatchObject({ session: 'session-1-sc-0a1b2c3d', path: 'src/main.mbt' });
  await expect(page.locator('.editor-tab.active', { hasText: 'main.mbt' })).toBeVisible();
  await expect(page.locator('#transcript')).toHaveAttribute('data-transcript-session', 'session-1');
  expect(app.pageErrors).toEqual([]);
});

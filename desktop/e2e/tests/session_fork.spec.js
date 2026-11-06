import { test, expect } from './support/test.js';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

const event = (sequence, kind, payload) => ({ sequence, item: { kind, payload } });
const history = [
  event(1, 'user', { content: 'Explore the first approach.' }),
  event(2, 'assistant', { content: 'First answer.' }),
  event(3, 'terminal', { kind: 'finished', message: 'First answer.' }),
  event(4, 'user', { content: 'Explore another approach.' }),
  event(5, 'assistant', { content: 'Let me investigate.' }),
  event(6, 'terminal', { kind: 'finished', message: 'Second answer.' }),
  event(7, 'user', { content: 'Continue working.' }),
  event(8, 'assistant', { content: 'Still working.' }),
];

async function setup(page, minimal, child = false, events = history) {
  await page.addInitScript(value => localStorage.setItem('openseek.minimal_transcript', String(value)), minimal);
  const app = new DesktopBrowserHarness(page);
  app.liveSessions.push({ id: 'session-other', title: 'Other conversation', updated_at_ms: 2 });
  if (child) app.liveSessions.push({ id: 'session-1-sr-1', title: 'Subtask answer', updated_at_ms: 3 });
  app.sessionEvents = events;
  const sourceSessions = new Set(app.liveSessions.map(session => session.id));
  const replies = new Map();
  const original = app.replyFor.bind(app);
  app.replyFor = request => {
    if (request.method === 'session.fork' || request.method === 'session.edit') {
      const session = 'fork-session';
      const title = request.params.source_title;
      const copied = events.filter(e => request.params.through != null && e.sequence <= request.params.through);
      if (request.method === 'session.edit') {
        copied.push(event((copied.at(-1)?.sequence ?? 0) + 1, 'user', { content: request.params.task }));
      }
      replies.set(session, copied);
      app.liveSessions.push({ id: session, title, updated_at_ms: 10 });
      if (request.method === 'session.edit') {
        app.liveSessions = app.liveSessions.filter(row => row.id !== request.params.session);
        app.notify('session.changed', { change: 'deleted', session: request.params.session, workspace: '/workspace' });
      }
      return { session, title };
    }
    if (request.method === 'session.load') {
      // A newly created chat has no source history, including when the
      // post-send reload races the first render.
      const events = replies.get(request.params.session)
        ?? (sourceSessions.has(request.params.session) ? app.sessionEvents : []);
      return { session: { version: 1, id: request.params.session, events }, watermark: events.at(-1)?.sequence ?? 0, prediction: null };
    }
    return original(request);
  };
  await app.install();
  await app.goto();
  await app.sessionButton().click();
  await expect(page.locator('#transcript')).toContainText('First answer.');
  return app;
}

for (const minimal of [false, true]) {
  test(`${minimal ? 'minimal' : 'detailed'} Fork uses the terminal boundary and opens an idle copy`, async ({ page }) => {
    const app = await setup(page, minimal);
    expect(await page.locator('[data-testid="message-fork"][data-fork-through="3"]').textContent()).toBe('');
    app.rpcDelays.set('session.fork', 500);
    await page.locator('[data-testid="message-fork"][data-fork-through="3"]').focus();
    await page.keyboard.press('Enter');
    await expect(page.locator('[data-testid="message-fork"][data-fork-through="3"]')).toBeDisabled();
    await expect(page.locator('[data-testid="message-fork"][data-fork-through="6"]')).toBeDisabled();
    await expect(page.locator('.message-fork-spinner')).toHaveCount(1);
    await expect(app.sessionRow('fork-session')).toHaveClass(/active/);
    await expect(page.locator('[data-testid="message-fork"]')).toHaveCount(1);
    await expect(page.locator('#transcript')).not.toContainText('Second answer.');
    await expect(page.locator('#transcript')).not.toContainText('Still working.');
    await expect(page.locator('#task')).toBeFocused();
    expect(app.requests.filter(r => r.method === 'session.fork').map(r => r.params.through)).toEqual([3]);
    expect(app.requests.find(r => r.method === 'session.fork').params.source_title).toBe('Rabbita browser fixture');
    await expect(app.sessionButton().or(app.sessionButton('fork-session'))).toHaveCount(2);
    expect(app.requests.filter(r => r.method === 'agent.start')).toEqual([]);
    expect(app.pageErrors).toEqual([]);
  });
}

test('a delayed fork cannot replace a newer missing destination', async ({ page }) => {
  const app = await setup(page, false);
  await app.sessionButton('session-other').click();
  await expect(page).toHaveURL(/\/chat\/session\/session-other$/);
  await app.sessionRow('session-1').click();
  await expect(page).toHaveURL(/\/chat\/session\/session-1$/);
  const pending = Promise.withResolvers();
  const reply = app.replyFor.bind(app);
  app.replyFor = request => request.method === 'session.fork' ? pending.promise : reply(request);
  await page.locator('[data-testid="message-fork"][data-fork-through="3"]').click();
  await expect.poll(() => app.requests.some(r => r.method === 'session.fork')).toBe(true);
  app.liveSessions = app.liveSessions.filter(row => row.id !== 'session-other');
  app.notify('session.changed', { change: 'deleted', session: 'session-other', workspace: '/workspace' });
  await expect(app.sessionRow('session-other')).toHaveCount(0);
  await page.goBack();
  await expect(page).toHaveURL(/\/chat\/session\/session-other$/);
  const unavailable = page.locator('.navigation-notice');
  await expect(unavailable).toBeVisible();
  pending.resolve(reply(app.requests.find(r => r.method === 'session.fork')));
  const fork = app.sessionRow('fork-session');
  await expect(fork).toBeVisible();
  await expect(fork).not.toHaveClass(/active/);
  await expect(unavailable).toBeVisible();
  await expect(page).toHaveURL(/\/chat\/session\/session-other$/);
  expect(app.pageErrors).toEqual([]);
});

for (const minimal of [false, true]) {

  // Rendering differs by layout; completion handling is shared.
  const failed = minimal;
  test(`${minimal ? 'minimal' : 'detailed'} Fork disables other conversations until ${failed ? 'failure' : 'success'}`, async ({ page }) => {
    const app = await setup(page, minimal);
    app.rpcDelays.set('session.fork', 2500);
    if (failed) app.rpcErrors.set('session.fork', 'Fork fixture unavailable');
    const buttons = page.locator('[data-testid="message-fork"]');
    await page.locator('[data-testid="message-fork"][data-fork-through="3"]').click();
    await expect(page.locator('.message-fork-spinner')).toHaveCount(1);
    await app.sessionButton('session-other').click();
    await expect(app.sessionRow('session-other')).toHaveClass(/active/);
    await expect(buttons).toHaveCount(2);
    await expect(page.locator('[data-testid="message-fork"][data-fork-through="3"]')).toBeDisabled();
    await expect(page.locator('[data-testid="message-fork"][data-fork-through="6"]')).toBeDisabled();
    await expect(page.locator('.message-fork-spinner')).toHaveCount(0);
    expect(app.requests.filter(r => r.method === 'session.fork')).toHaveLength(1);
    if (failed) {
      await expect(page.locator('.notifications')).toContainText('Fork fixture unavailable');
    } else {
      await expect(app.sessionRow('fork-session')).toBeVisible();
      await expect(app.sessionRow('fork-session')).not.toHaveClass(/active/);
    }
    await expect(page.locator('[data-testid="message-fork"][data-fork-through="3"]')).toBeEnabled();
    await expect(page.locator('[data-testid="message-fork"][data-fork-through="6"]')).toBeEnabled();
    await expect(app.sessionRow('session-other')).toHaveClass(/active/);
    if (failed) {
      app.rpcErrors.delete('session.fork');
      app.rpcDelays.delete('session.fork');
      await page.locator('[data-testid="message-fork"][data-fork-through="3"]').click();
      await expect(app.sessionRow('fork-session')).toHaveClass(/active/);
      expect(app.requests.filter(r => r.method === 'session.fork')).toHaveLength(2);
    }
    expect(app.pageErrors).toEqual([]);
  });
}

test('a streamed answer gains Fork only when its terminal is committed', async ({ page }) => {
  const app = await setup(page, true);
  const committed = event(9, 'terminal', { kind: 'finished', message: 'Still working.' });
  app.sessionEvents = [...history, committed];
  app.notify('session.event', { session: 'session-1', session_root: '/workspace/.openseek', sequence: 9, event: committed });
  await expect(page.locator('[data-testid="message-fork"]')).toHaveCount(3);
  await page.locator('[data-testid="message-fork"][data-fork-through="9"]').click();
  await expect.poll(() => app.requests.filter(r => r.method === 'session.fork').map(r => r.params.through)).toEqual([9]);
  expect(app.pageErrors).toEqual([]);
});

{
  const minimal = true;

  test(`${minimal ? 'minimal' : 'detailed'} edit stays inline until Send and preserves the original composer`, async ({ page }) => {
    const app = await setup(page, minimal);
    await page.locator('#task').fill('Keep my original draft');
    const original = app.sessionRow('session-1');
    const target = page.locator('#turn-s4');
    await target.locator('[id^="user-message-edit-trigger-"]').click();
    const editor = page.locator('.message-editor');
    const input = editor.locator('textarea');
    await expect(input).toHaveValue('Explore another approach.');
    await expect(input).toBeFocused();
    await expect(original).toHaveClass(/active/);
    await expect(page.locator('#transcript')).toContainText('Second answer.');
    await expect(page.locator('#transcript')).toContainText('Still working.');
    await expect(page.locator('#task')).toHaveValue('Keep my original draft');
    expect(app.requests.filter(r => r.method === 'session.edit')).toHaveLength(0);
    await input.fill('Try my revised approach.');
    await input.press('End');
    await input.press('Shift+Enter');
    await input.press('x');
    await expect(input).toHaveValue('Try my revised approach.\nx');
    await expect(input).toBeFocused();
    await input.dispatchEvent('keydown', { key: 'Enter', isComposing: true });
    expect(app.requests.filter(r => r.method === 'session.edit')).toHaveLength(0);
    app.rpcDelays.set('session.edit', 500);
    // Use the same Enter-to-send contract as the bottom composer.
    await input.press('Enter');
    await expect(input).toBeDisabled();
    await expect(page.locator('#transcript')).toContainText('Second answer.');
    await expect(app.sessionRow('fork-session')).toHaveClass(/active/);
    await expect.poll(() => app.requests.filter(r => r.method === 'session.edit').length).toBe(1);
    expect(app.requests.filter(r => r.method === 'session.edit').map(r => r.params.through)).toEqual([3]);
    const sent = app.requests.find(r => r.method === 'session.edit');
    expect(sent.params.session).toBe('session-1');
    expect(sent.params.task).toBe('Try my revised approach.\nx');
    await expect(original).toHaveCount(0);
    await expect(page.locator('#task')).toHaveValue('');
    expect(app.requests.filter(r => r.method === 'agent.start')).toHaveLength(0);
    expect(app.pageErrors).toEqual([]);
  });

  test(`${minimal ? 'minimal' : 'detailed'} first-message edit creates a new chat only on Send`, async ({ page }) => {
    const app = await setup(page, minimal);
    await page.locator('#user-message-edit-trigger-1').click();
    const editor = page.locator('.message-editor');
    await expect(editor.locator('textarea')).toHaveValue('Explore the first approach.');
    await expect(page.locator('#transcript')).toContainText('First answer.');
    await expect(app.sessionRow('session-1')).toHaveClass(/active/);
    expect(app.requests.filter(r => r.method === 'session.edit')).toHaveLength(0);
    await editor.locator('textarea').fill('Start with a different question.');
    await editor.getByTestId('message-edit-send').click();
    await expect.poll(() => app.requests.filter(r => r.method === 'session.edit').length).toBe(1);
    expect(app.requests.find(r => r.method === 'session.edit').params.through).toBeUndefined();
    expect(app.requests.find(r => r.method === 'session.edit').params.task).toBe('Start with a different question.');
    expect(app.requests.filter(r => r.method === 'session.fork')).toHaveLength(0);
    await expect(page.locator('#transcript')).not.toContainText('First answer.');
    await expect(page).toHaveURL(/\/chat\/session\/fork-session$/);
    expect(app.pageErrors).toEqual([]);
  });
}

test('cancel and Escape restore the original bubble without creating a conversation', async ({ page }) => {
  const app = await setup(page, true);
  await page.locator('#task').fill('My separate draft');
  for (const escape of [false, true]) {
    await page.locator('#user-message-edit-trigger-4').click();
    const editor = page.locator('.message-editor');
    await editor.locator('textarea').fill('Unsent changes');
    if (escape) await editor.locator('textarea').press('Escape');
    else await editor.getByTestId('message-edit-cancel').click();
    await expect(editor).toHaveCount(0);
    await expect(page.locator('#turn-s4')).toBeVisible();
    await expect(page.locator('#task')).toHaveValue('My separate draft');
  }
  expect(app.requests.filter(r => r.method === 'session.edit')).toHaveLength(0);
  expect(app.pageErrors).toEqual([]);
});

test('expanding an older message keeps the reader in place while later answers stream', async ({ page }) => {
  const events = [...history];
  for (let turn = 0; turn < 12; turn += 1) {
    const sequence = 9 + turn * 3;
    events.push(event(sequence, 'terminal', { kind: 'finished', message: `Later answer ${turn}` }));
    events.push(event(sequence + 1, 'user', { content: `Later question ${turn}` }));
    events.push(event(sequence + 2, 'assistant', { content: `Later response ${turn}` }));
  }
  const app = await setup(page, true, false, events);
  const transcript = page.locator('#transcript');
  await transcript.evaluate(node => { node.scrollTop = 0; });
  const target = page.locator('#turn-s4');
  const edit = target.locator('[id^="user-message-edit-trigger-"]');
  await edit.click();
  const editor = page.locator('.message-editor');
  await expect(editor.locator('textarea')).toBeFocused();
  await expect.poll(() => transcript.evaluate(node => node.scrollTop)).toBe(0);
  const streamed = event(45, 'terminal', { kind: 'finished', message: 'New answer while editing' });
  app.sessionEvents = [...events, streamed];
  app.notify('session.event', { session: 'session-1', session_root: '/workspace/.openseek', sequence: 45, event: streamed });
  await expect(transcript).toContainText('New answer while editing');
  await expect(editor.locator('textarea')).toBeFocused();
  await expect.poll(() => transcript.evaluate(node => node.scrollTop)).toBe(0);
  expect(app.requests.filter(r => r.method === 'session.edit')).toHaveLength(0);
  expect(app.pageErrors).toEqual([]);
});

test('failed fork retains the edited text and later transcript for retry', async ({ page }) => {
  const app = await setup(page, true);
  app.rpcErrors.set('session.edit', 'Fork temporarily unavailable');
  await page.locator('#user-message-edit-trigger-4').click();
  const editor = page.locator('.message-editor');
  await editor.locator('textarea').fill('Retry this edited request');
  await editor.getByTestId('message-edit-send').click();
  await expect(page.locator('.notifications')).toContainText('Fork temporarily unavailable');
  await expect(editor.locator('textarea')).toHaveValue('Retry this edited request');
  await expect(editor.locator('textarea')).toBeEnabled();
  await expect(page.locator('#transcript')).toContainText('Second answer.');
  expect(app.requests.filter(r => r.method === 'session.edit')).toHaveLength(1);
  app.rpcErrors.delete('session.edit');
  await editor.getByTestId('message-edit-send').click();
  await expect.poll(() => app.requests.filter(r => r.method === 'session.edit').length).toBe(2);
  await expect(app.sessionRow('fork-session')).toHaveClass(/active/);
  expect(app.requests.find(r => r.method === 'session.edit').params.task).toBe('Retry this edited request');
  expect(app.pageErrors).toEqual([]);
});

for (const navigate of [false, true]) {
  test(`an edit error after another client deletes its source ${navigate ? 'preserves the other conversation' : 'retires the deleted conversation'}`, async ({ page }) => {
    const app = await setup(page, true);
    const error = 'The original conversation was deleted by another client';
    app.rpcErrors.set('session.edit', error);
    app.rpcDelays.set('session.edit', 2000);
    const originalReply = app.replyFor.bind(app);
    app.replyFor = request => {
      if (request.method === 'session.load' && request.params.session === 'session-other') {
        const events = [event(1, 'user', { content: 'An unrelated conversation' })];
        return { session: { version: 1, id: 'session-other', events }, watermark: 1, prediction: null };
      }
      return originalReply(request);
    };
    await page.locator('#user-message-edit-trigger-4').click();
    const editor = page.locator('.message-editor');
    await editor.locator('textarea').fill('An edit overtaken by deletion');
    await editor.getByTestId('message-edit-send').click();
    await expect.poll(() => app.requests.filter(request => request.method === 'session.edit').length).toBe(1);

    // The same authoritative notification reaches this client when another
    // browser uses Delete. The edit reply is still pending at this point.
    const lists = app.requests.filter(request => request.method === 'session.list').length;
    app.liveSessions = app.liveSessions.filter(row => row.id !== 'session-1');
    app.notify('session.changed', { change: 'deleted', session: 'session-1', workspace: '/workspace' });
    await expect.poll(() => app.requests.filter(request => request.method === 'session.list').length).toBeGreaterThan(lists);
    await expect(editor.locator('textarea')).toBeDisabled();
    await expect(page.locator('#transcript')).toContainText('Second answer.');
    if (navigate) {
      await app.sessionButton('session-other').click();
      await expect(page.locator('#transcript')).toContainText('An unrelated conversation');
      await page.locator('#task').fill('Keep this unrelated draft');
    }

    await expect(page.locator('.notifications')).toContainText(error);
    await expect(app.sessionRow('session-1')).toHaveCount(0);
    await expect(editor).toHaveCount(0);
    if (!navigate) {
      await expect(page.locator('#transcript')).toHaveCount(0);
      await expect(page.locator('.navigation-notice')).toBeVisible();
      await expect(page).toHaveURL(/\/chat\/session\/session-1$/);
    }
    if (navigate) {
      await expect(page.locator('#transcript')).not.toContainText('Second answer.');
      await expect(app.sessionRow('session-other')).toHaveClass(/active/);
      await expect(page.locator('#transcript')).toContainText('An unrelated conversation');
      await expect(page.locator('#task')).toHaveValue('Keep this unrelated draft');
    }
    expect(app.requests.filter(request => ['session.edit', 'session.fork', 'agent.start', 'session.delete'].includes(request.method)).map(request => request.method)).toEqual(['session.edit']);
    expect(app.pageErrors).toEqual([]);
  });
}

test('Send completes in its fork after navigation without replacing the other composer', async ({ page }) => {
  const app = await setup(page, true);
  app.rpcDelays.set('session.edit', 1200);
  await page.locator('#user-message-edit-trigger-4').click();
  await page.locator('.message-editor textarea').fill('Edited in the source');
  await page.locator('.message-editor').getByTestId('message-edit-send').click();
  await app.sessionButton('session-other').click();
  await page.locator('#task').fill('Unrelated draft');
  await expect.poll(() => app.requests.find(r => r.method === 'session.edit')?.params.task).toBe('Edited in the source');
  expect(app.requests.find(r => r.method === 'session.edit').params.session).toBe('session-1');
  await expect(app.sessionRow('session-other')).toHaveClass(/active/);
  await expect(page.locator('#task')).toHaveValue('Unrelated draft');
  expect(app.pageErrors).toEqual([]);
});

test('inline edit preserves image attachments and mention chips on Send', async ({ page }) => {
  const image = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6z1kAAAAASUVORK5CYII=';
  const events = history.map(e => e.sequence === 4 ? event(4, 'user', { content: [
    { type: 'text', text: 'Explain this image.\n\n<user_mentions>\n<file path="src/main.mbt"/>\n</user_mentions>' },
    { type: 'image', media_type: 'image/png', data: image.split(',')[1] },
  ] }) : e);
  const app = await setup(page, true, false, events);
  await page.locator('#user-message-edit-trigger-4').click();
  const editor = page.locator('.message-editor');
  await expect(editor.locator('textarea')).toHaveValue('Explain this image.');
  await expect(editor.locator('img')).toHaveAttribute('src', image);
  await expect(editor).toContainText('main.mbt');
  await editor.locator('textarea').fill('Explain the revised image request.');
  await editor.getByTestId('message-edit-send').click();
  await expect.poll(() => app.requests.find(r => r.method === 'session.edit')?.params.images).toEqual([image]);
  expect(app.requests.find(r => r.method === 'session.edit').params.task).toContain('<file path="src/main.mbt"/>');
  expect(app.pageErrors).toEqual([]);
});

test('edit never skips an intervening user input without a forkable answer', async ({ page }) => {
  const events = history.map(e => e.sequence === 6
    ? event(6, 'terminal', { kind: 'failed', message: 'Failed to finish.' }) : e);
  const app = await setup(page, true, false, events);
  await expect(page.locator('[id^="user-message-edit-trigger-"]')).toHaveCount(2);
  await expect(page.locator('#turn-s7').locator('[id^="user-message-edit-trigger-"]')).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

for (const first of [false, true]) {
  test(`single edit replaces the ${first ? 'first' : 'later'} message without client-side cleanup calls`, async ({ page }) => {
    const app = await setup(page, true);
    await page.locator(`#user-message-edit-trigger-${first ? 1 : 4}`).click();
    await page.locator('.message-editor textarea').fill('Revised question');
    await page.locator('.message-editor').getByTestId('message-edit-send').click();
    await expect(app.sessionRow('session-1')).toHaveCount(0);
    await expect(app.sessionRow('fork-session')).toHaveClass(/active/);
    await expect(page.locator('#transcript')).toContainText('Revised question');
    expect(app.requests.filter(r => r.method === 'session.edit')).toHaveLength(1);
    expect(app.requests.find(r => r.method === 'session.edit').params).toMatchObject({ session: 'session-1', source_sequence: 8 });
    expect(app.requests.filter(r => ['agent.start', 'session.edit_prepare', 'session.edit_commit'].includes(r.method))).toHaveLength(0);
    expect(app.pageErrors).toEqual([]);
  });
}

test('running and compacting chats disable editing without interrupting the run', async ({ page }) => {
  const app = await setup(page, true);
  const edit = page.locator('#user-message-edit-trigger-4');
  await expect(edit).toBeEnabled();
  app.notify('agent.started', { session: 'session-1', run_id: 'busy-edit', session_root: '/workspace/.openseek', model: 'deepseek-flash', max_steps: 1000 });
  await expect(edit).toBeDisabled();
  await expect(page.locator('[data-testid="message-fork"][data-fork-through="3"]')).toBeEnabled();
  app.notify('agent.finished', { session: 'session-1', run_id: 'busy-edit', status: 'finished', answer: 'Done', exit_code: 0 });
  await expect(edit).toBeEnabled();
  app.notify('agent.event', { session: 'session-1', event: { event: 'compaction_started', from_sequence: 1, to_sequence: 8 } });
  await expect(edit).toBeDisabled();
  app.notify('agent.event', { session: 'session-1', event: { event: 'compaction_failed', error: 'Cancelled' } });
  await expect(edit).toBeEnabled();
  expect(app.requests.filter(r => ['agent.cancel', 'session.edit'].includes(r.method))).toHaveLength(0);
  expect(app.pageErrors).toEqual([]);
});

test('a run starting during inline editing disables Send but keeps the draft and Cancel', async ({ page }) => {
  const app = await setup(page, true);
  await page.locator('#user-message-edit-trigger-4').click();
  const editor = page.locator('.message-editor');
  await editor.locator('textarea').fill('Keep my edit');
  app.notify('agent.started', { session: 'session-1', run_id: 'busy-edit', session_root: '/workspace/.openseek', model: 'deepseek-flash', max_steps: 1000 });
  await expect(editor.getByTestId('message-edit-send')).toBeDisabled();
  await expect(editor.locator('textarea')).toHaveValue('Keep my edit');
  await expect(editor.locator('textarea')).toBeDisabled();
  app.notify('agent.finished', { session: 'session-1', run_id: 'busy-edit', status: 'finished', answer: 'Done', exit_code: 0 });
  await expect(editor.getByTestId('message-edit-send')).toBeEnabled();
  await expect(editor.locator('textarea')).toHaveValue('Keep my edit');
  app.notify('agent.started', { session: 'session-1', run_id: 'busy-edit-2', session_root: '/workspace/.openseek', model: 'deepseek-flash', max_steps: 1000 });
  await expect(editor.getByTestId('message-edit-send')).toBeDisabled();
  await editor.getByTestId('message-edit-cancel').click();
  await expect(editor).toHaveCount(0);
  expect(app.requests.filter(r => ['agent.cancel', 'session.edit'].includes(r.method))).toHaveLength(0);
  expect(app.pageErrors).toEqual([]);
});

test('typing and an external run in the same render keep the draft and disable inline editing', async ({ page }) => {
  // Hold rendering, not message handling: both independent state changes must
  // reach the incremental graph before its next read, without timing sleeps.
  await page.addInitScript(() => {
    const frame = window.requestAnimationFrame.bind(window);
    const queued = [];
    window.__holdEditFrame = false;
    window.requestAnimationFrame = callback => frame(time => {
      if (window.__holdEditFrame) queued.push([callback, time]);
      else callback(time);
    });
    window.__releaseEditFrame = () => new Promise(resolve => frame(() => {
      window.__holdEditFrame = false;
      for (const [callback, time] of queued.splice(0)) callback(time);
      resolve();
    }));
  });
  const app = await setup(page, true);
  await page.locator('#user-message-edit-trigger-4').click();
  const editor = page.locator('.message-editor');
  await expect(editor.locator('textarea')).toBeVisible();
  const probes = app.requests.filter(request => request.method === 'git.branch').length;
  await page.evaluate(() => { window.__holdEditFrame = true; });
  await editor.locator('textarea').fill('Keep my simultaneous edit');
  app.notify('agent.started', { session: 'session-1', run_id: 'same-frame-edit', session_root: '/workspace/.openseek', model: 'deepseek-flash', max_steps: 1000 });
  // Started emits a branch probe after installing its running state.
  await expect.poll(() => app.requests.filter(request => request.method === 'git.branch').length).toBeGreaterThan(probes);
  await page.evaluate(() => window.__releaseEditFrame());
  await expect(editor.locator('textarea')).toHaveValue('Keep my simultaneous edit');
  await expect(editor.locator('textarea')).toBeDisabled();
  await expect(editor.getByTestId('message-edit-send')).toBeDisabled();
  await expect(editor.getByTestId('message-edit-cancel')).toBeEnabled();
  await editor.getByTestId('message-edit-cancel').click();
  await expect(editor).toHaveCount(0);
  expect(app.requests.filter(r => ['agent.cancel', 'session.edit'].includes(r.method))).toHaveLength(0);
  expect(app.pageErrors).toEqual([]);
});

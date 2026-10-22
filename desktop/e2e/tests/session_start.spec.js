import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

const source = 'session-1';
const target = 'focus-helper-session';
const requestId = 'start-focus-helper';
const title = 'Extract a shared after-render focus helper';
const task = 'Extract one shared after-render focus helper and replace the three hand-rolled copies.';
const event = (sequence, kind, payload) => ({ sequence, item: { kind, payload } });
const sourceRoute = /\/chat\/session\/session-1$/;
const targetRoute = /\/chat\/session\/focus-helper-session$/;
const cardFor = page => page.locator('#transcript .session-start-card');
const foldedFor = page => page.locator('#transcript .session-start-folded');

// Replace transport data only. The proposal belongs to a committed tool call,
// and its host snapshot outlives both turn completion and browser reloads.
async function setup(page, { minimal = true, live = false, readError, model, followupBehavior = 'steer' } = {}) {
  await page.addInitScript(value => localStorage.setItem('openseek.minimal_transcript', String(value)), minimal);
  const app = new DesktopBrowserHarness(page);
  app.hostSettings.followup_behavior = followupBehavior;
  if (readError) app.rpcErrors.set('session.starts_list', readError);
  let generation = 1;
  let proposal = {
    id: 'proposal-focus-helper', request_id: requestId, title, task, workspace: '/workspace',
    workspace_mode: 'worktree', status: 'pending',
    ...(model !== undefined ? { model } : {}),
  };
  const args = {
    action: 'start', request_id: requestId, title, task,
    workspace: '/workspace', workspace_mode: 'worktree',
    ...(model !== undefined ? { model } : {}),
  };
  const history = [
    event(1, 'user', { content: 'Suggest a separate session for this refactor.' }),
    event(2, 'assistant', { content: 'I suggest starting the following session.' }),
    event(3, 'assistant', { content: '', tool_calls: [{
      id: 'tool-start-focus-helper', name: 'mcp__seekmoon__session', arguments: JSON.stringify(args),
    }] }),
    event(4, 'tool_result', {
      tool_call_id: 'tool-start-focus-helper', tool_name: 'mcp__seekmoon__session',
      content: JSON.stringify(proposal), is_error: false,
    }),
    event(5, 'terminal', { kind: 'finished', message: 'I suggest starting the following session.' }),
  ];
  app.sessionEvents = live ? history.slice(0, 2) : history;
  let published = !live;
  const sessions = new Map([[source, app.sessionEvents]]);
  const snapshot = session => ({
    session, generation, proposals: session === source && published ? [{ ...proposal }] : [],
  });
  const original = app.replyFor.bind(app);
  app.replyFor = request => {
    if (request.method === 'session.load' || request.method === 'session.load_archived') {
      const events = sessions.get(request.params.session) ?? [];
      return {
        session: { version: 1, id: request.params.session, events },
        watermark: events.at(-1)?.sequence ?? 0, prediction: null,
      };
    }
    if (request.method === 'session.starts_list') return snapshot(request.params.session);
    if (request.method === 'session.starts_decide') {
      expect(request.params.session).toBe(source);
      expect(request.params.request_id).toBe(requestId);
      const action = request.params.action;
      if (action === 'start') {
        proposal = {
          ...proposal, status: 'started', target_session: target,
          workspace_mode: request.params.workspace_mode ?? proposal.workspace_mode,
        };
        if (request.params.model === null) delete proposal.model;
        else if (request.params.model !== undefined) proposal.model = request.params.model;
        if (!app.liveSessions.some(row => row.id === target)) {
          app.liveSessions.push({ id: target, title, updated_at_ms: 2 });
        }
        sessions.set(target, [event(1, 'user', { content: task })]);
        app.notify('session.changed', { change: 'created', session: target, workspace: '/workspace' });
      } else if (action === 'here') {
        proposal = { ...proposal, status: 'here', target_session: source };
        const events = sessions.get(source);
        const next = event(events.at(-1).sequence + 1, 'user', { content: task });
        events.push(next);
        app.notify('session.event', {
          session: source, session_root: '/workspace/.openseek', sequence: next.sequence, event: next,
        });
      } else if (action === 'dismiss') {
        proposal = { ...proposal, status: 'dismissed' };
      } else {
        throw new Error(`Unexpected proposal action: ${action}`);
      }
      generation++;
      return snapshot(source);
    }
    return original(request);
  };
  await app.install();
  await app.goto();
  await page.getByRole('button', { name: 'Rabbita browser fixture', exact: true }).click();
  await expect(page).toHaveURL(sourceRoute);
  if (!live) await expect(cardFor(page)).toBeVisible();
  const publish = () => {
    published = true;
    generation++;
    // A host proposal notification can arrive before the engine commits the
    // tool result that anchors it in the transcript.
    app.notify('session.starts_changed', snapshot(source));
    for (const next of history.slice(2)) {
      app.sessionEvents.push(next);
      app.notify('session.event', {
        session: source, session_root: '/workspace/.openseek', sequence: next.sequence, event: next,
      });
    }
  };
  const transitionTarget = change => {
    const removed = app.liveSessions.filter(row => row.id === target);
    app.liveSessions = app.liveSessions.filter(row => row.id !== target);
    if (change === 'archived') app.archivedSessions.push(...removed);
    else sessions.delete(target);
    app.notify('session.changed', { change, session: target, workspace: '/workspace' });
  };
  return { app, publish, transitionTarget };
}

test('a live host proposal appears once when its tool call is committed and can start', async ({ page }) => {
  const { app, publish } = await setup(page, { live: true });
  await expect(page.locator('#transcript')).toContainText('I suggest starting the following session.');
  await expect(cardFor(page)).toHaveCount(0);
  publish();
  const card = cardFor(page);
  await expect(card).toHaveCount(1);
  await expect(card).toContainText(title);
  await card.getByRole('button', { name: 'Start', exact: true }).click();
  await expect(foldedFor(page)).toContainText(title);
  await expect(page).toHaveURL(sourceRoute);
  expect(app.requests.filter(request => request.method === 'session.starts_decide')).toHaveLength(1);
  await page.reload();
  await expect(foldedFor(page)).toHaveCount(1);
  expect(app.pageErrors).toEqual([]);
});

for (const minimal of [false, true]) {
  test(`${minimal ? 'minimal' : 'detailed'} session proposal starts only on click, folds and uses existing navigation`, async ({ page }, testInfo) => {
    const { app } = await setup(page, { minimal });
    const card = cardFor(page);
    await expect(card).toContainText(title);
    await expect(card).toContainText(task);
    expect(app.requests.filter(request => request.method === 'session.starts_decide')).toEqual([]);
    expect(app.requests.filter(request => request.method === 'agent.start')).toEqual([]);
    if (minimal) {
      const screenshot = testInfo.outputPath('session-start-pending.png');
      await page.screenshot({ path: screenshot, animations: 'disabled' });
      await testInfo.attach('Suggested session in the transcript', { path: screenshot, contentType: 'image/png' });
    }

    app.rpcDelays.set('session.starts_decide', 350);
    await card.getByRole('button', { name: 'Start', exact: true }).click();
    await expect(card.getByRole('button', { name: 'Starting…', exact: true })).toBeDisabled();
    const folded = foldedFor(page);
    await expect(folded).toContainText(title);
    await expect(page).toHaveURL(sourceRoute);
    await expect(card).toHaveCount(0);
    expect(app.requests.filter(request => request.method === 'session.starts_decide').map(request => request.params)).toEqual([
      { session: source, request_id: requestId, action: 'start', model: null, workspace_mode: 'worktree' },
    ]);
    if (minimal) {
      const screenshot = testInfo.outputPath('session-start-folded.png');
      await page.screenshot({ path: screenshot, animations: 'disabled' });
      await testInfo.attach('Started session folded to its title', { path: screenshot, contentType: 'image/png' });
    }
    await folded.click();
    await expect(page).toHaveURL(targetRoute);
    await expect(page.locator('main > .topbar h1')).toHaveText(title);
    await expect(page.locator('#transcript .msg.user')).toContainText(task);
    await page.getByRole('button', { name: 'Back', exact: true }).click();
    await expect(page).toHaveURL(sourceRoute);
    await expect(folded).toContainText(title);
    await page.reload();
    await expect(folded).toContainText(title);
    await folded.focus();
    await page.keyboard.press('Enter');
    await expect(page).toHaveURL(targetRoute);
    expect(app.requests.filter(request => request.method === 'session.starts_decide')).toHaveLength(1);
    expect(app.pageErrors).toEqual([]);
  });
}

test('session proposal options apply to the new session without changing the suggestion', async ({ page }) => {
  const { app } = await setup(page);
  const card = cardFor(page);
  await card.getByRole('button', { name: 'Options', exact: true }).click();
  const options = page.locator('.session-start-options');
  await expect(options).toBeVisible();
  await options.getByRole('button', { name: 'Model', exact: true }).click();
  await options.getByRole('option', { name: 'DS Flash', exact: true }).click();
  await options.getByRole('button', { name: 'Workspace mode', exact: true }).click();
  await options.getByRole('option', { name: 'Local', exact: true }).click();
  await card.getByRole('button', { name: 'Start', exact: true }).click();
  await expect(foldedFor(page)).toContainText(title);
  expect(app.requests.find(request => request.method === 'session.starts_decide').params).toEqual({
    session: source, request_id: requestId, action: 'start', model: 'deepseek-flash', workspace_mode: 'local',
  });
  expect(app.pageErrors).toEqual([]);
});

test('Project default clears the model originally suggested by the agent', async ({ page }) => {
  const { app } = await setup(page, { model: 'glm-5.3' });
  const card = cardFor(page);
  await card.getByRole('button', { name: 'Options', exact: true }).click();
  const options = page.locator('.session-start-options');
  await options.getByRole('button', { name: 'Model', exact: true }).click();
  await options.getByRole('option', { name: 'Project default', exact: true }).click();
  await expect(options.getByRole('button', { name: 'Model', exact: true })).toContainText('Project default');
  await card.getByRole('button', { name: 'Start', exact: true }).click();
  await expect(foldedFor(page)).toContainText(title);
  expect(app.requests.find(request => request.method === 'session.starts_decide').params).toEqual({
    session: source, request_id: requestId, action: 'start', model: null, workspace_mode: 'worktree',
  });
  expect(app.pageErrors).toEqual([]);
});

test('Do it here submits to the current conversation and consumes the card across reload', async ({ page }) => {
  const { app } = await setup(page);
  const card = cardFor(page);
  await card.getByRole('button', { name: 'Do it here', exact: true }).click();
  await expect(card).toHaveCount(0);
  await expect(page).toHaveURL(sourceRoute);
  await expect(page.locator('#transcript .msg.user').last()).toContainText(task);
  expect(app.liveSessions.map(row => row.id)).toEqual([source]);
  expect(app.requests.find(request => request.method === 'session.starts_decide').params).toEqual({
    session: source, request_id: requestId, action: 'here',
    here: { model: 'deepseek-flash', thinking: 'high', approval: 'ask', max_steps: 1000, followup_behavior: 'steer' },
  });
  await page.reload();
  await expect(page.locator('#transcript .msg.user').last()).toContainText(task);
  await expect(card).toHaveCount(0);
  expect(app.pageErrors).toEqual([]);
});

test('Do it here carries current source settings and keeps the unsent composer draft', async ({ page }) => {
  const { app } = await setup(page, { model: 'glm-5.3', followupBehavior: 'queue' });
  await page.getByRole('button', { name: 'Model', exact: true }).click();
  await page.getByRole('option', { name: 'DS Pro', exact: true }).click();
  await page.getByRole('button', { name: 'Reasoning effort', exact: true }).click();
  await page.getByRole('option', { name: 'Max', exact: true }).click();
  const approval = page.locator('.composer').getByRole('button', { name: 'Approve for me', exact: true });
  await approval.click();
  await expect(approval).toHaveAttribute('aria-pressed', 'true');
  await page.locator('#task').fill('Keep my unsent draft');
  await cardFor(page).getByRole('button', { name: 'Do it here', exact: true }).click();
  await expect(cardFor(page)).toHaveCount(0);
  await expect(page.locator('#task')).toHaveValue('Keep my unsent draft');
  expect(app.requests.find(request => request.method === 'session.starts_decide').params).toEqual({
    session: source, request_id: requestId, action: 'here',
    here: { model: 'deepseek-v4-pro', thinking: 'max', approval: 'review', max_steps: 1000, followup_behavior: 'queue' },
  });
  expect(app.liveSessions.map(row => row.id)).toEqual([source]);
  expect(app.pageErrors).toEqual([]);
});

test('cached suggestions have disabled actions in an archived source transcript', async ({ page }) => {
  const { app } = await setup(page);
  const row = page.locator(`.conversation-row[title="${source}"]`);
  await row.hover();
  await row.getByRole('button', { name: 'Conversation actions', exact: true }).click();
  await page.getByRole('menuitem', { name: 'Archive', exact: true }).click();
  await page.locator('.section-heading', { hasText: 'Archived chats (1)' }).click();
  await row.click();
  await expect(page.getByText('Archived conversation · Read only', { exact: true })).toBeVisible();
  const card = cardFor(page);
  await expect(card).toBeVisible();
  await expect(card.getByRole('button', { name: 'Start', exact: true })).toBeDisabled();
  await expect(card.getByRole('button', { name: 'Do it here', exact: true })).toBeDisabled();
  await expect(card.getByRole('button', { name: 'Dismiss suggestion', exact: true })).toBeDisabled();
  expect(app.requests.filter(request => request.method === 'session.starts_decide')).toEqual([]);
  expect(app.pageErrors).toEqual([]);
});

for (const change of ['archived', 'deleted']) {
  test(`a started title resolves its ${change} target after the source is refreshed`, async ({ page }) => {
    const { app, transitionTarget } = await setup(page);
    await cardFor(page).getByRole('button', { name: 'Start', exact: true }).click();
    await expect(foldedFor(page)).toContainText(title);
    transitionTarget(change);
    await page.reload();
    const folded = foldedFor(page);
    await expect(folded).toContainText(title);
    await folded.click();
    await expect(page).toHaveURL(targetRoute);
    if (change === 'archived') {
      await expect(page.getByText('Archived conversation · Read only', { exact: true })).toBeVisible();
      await expect(page.locator('#transcript .msg.user')).toContainText(task);
      expect(app.requests.some(request => request.method === 'session.load_archived' && request.params.session === target)).toBe(true);
    } else {
      await expect(page.locator('.navigation-notice')).toContainText('no longer exists');
    }
    await page.getByRole('button', { name: 'Back', exact: true }).click();
    await expect(page).toHaveURL(sourceRoute);
    await expect(folded).toContainText(title);
    expect(app.requests.filter(request => request.method === 'session.starts_decide')).toHaveLength(1);
    expect(app.pageErrors).toEqual([]);
  });
}

test('reconnection clears an unaccepted local Sending state before retrying a pending proposal', async ({ page }) => {
  const { app } = await setup(page);
  const original = app.replyFor.bind(app);
  let blockFirstDecision = true;
  app.replyFor = request => {
    if (request.method === 'session.starts_decide' && blockFirstDecision) {
      blockFirstDecision = false;
      // The connection is lost before this command reaches host admission.
      return new Promise(() => {});
    }
    return original(request);
  };
  const card = cardFor(page);
  await card.getByRole('button', { name: 'Start', exact: true }).click();
  await expect(card.getByRole('button', { name: 'Starting…', exact: true })).toBeDisabled();
  app.socket.close({ code: 1001, reason: 'fixture host restart' });
  await expect.poll(() => app.socketURLs.length, { timeout: 15000 }).toBeGreaterThan(1);
  await expect(card.getByRole('button', { name: 'Start', exact: true })).toBeEnabled();
  await card.getByRole('button', { name: 'Start', exact: true }).click();
  await expect(foldedFor(page)).toContainText(title);
  expect(app.requests.filter(request => request.method === 'session.starts_decide')).toHaveLength(2);
  expect(app.pageErrors).toEqual([]);
});

test('a failed start keeps the suggestion available for retry', async ({ page }) => {
  const { app } = await setup(page);
  const card = cardFor(page);
  app.rpcErrors.set('session.starts_decide', 'Could not create the session. Try again.');
  await card.getByRole('button', { name: 'Start', exact: true }).click();
  await expect(card).toContainText('Could not create the session. Try again.');
  await expect(card.getByRole('button', { name: 'Start', exact: true })).toBeEnabled();
  expect(app.liveSessions.map(row => row.id)).toEqual([source]);
  app.rpcErrors.delete('session.starts_decide');
  await card.getByRole('button', { name: 'Start', exact: true }).click();
  await expect(foldedFor(page)).toContainText(title);
  expect(app.requests.filter(request => request.method === 'session.starts_decide')).toHaveLength(2);
  expect(app.pageErrors).toEqual([]);
});

test('a failed proposal read can retry before presenting session actions', async ({ page }) => {
  const { app } = await setup(page, { readError: 'The host could not read the saved suggestion.' });
  const card = cardFor(page);
  await expect(card).toContainText('The host could not read the saved suggestion.');
  await expect(card.getByRole('button', { name: 'Start', exact: true })).toHaveCount(0);
  app.rpcErrors.delete('session.starts_list');
  await card.getByRole('button', { name: 'Retry', exact: true }).click();
  await expect(card.getByRole('button', { name: 'Start', exact: true })).toBeEnabled();
  expect(app.requests.filter(request => request.method === 'session.starts_decide')).toEqual([]);
  expect(app.pageErrors).toEqual([]);
});

test('closing a suggestion dismisses it durably without starting a session', async ({ page }) => {
  const { app } = await setup(page);
  await cardFor(page).getByRole('button', { name: 'Dismiss suggestion', exact: true }).click();
  await expect(cardFor(page)).toHaveCount(0);
  await page.reload();
  await expect(page.locator('#transcript')).toContainText('I suggest starting the following session.');
  await expect(cardFor(page)).toHaveCount(0);
  expect(app.requests.filter(request => request.method === 'session.starts_decide').map(request => request.params)).toEqual([
    { session: source, request_id: requestId, action: 'dismiss' },
  ]);
  expect(app.liveSessions.map(row => row.id)).toEqual([source]);
  expect(app.pageErrors).toEqual([]);
});

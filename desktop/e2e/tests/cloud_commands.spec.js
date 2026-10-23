import { test, expect } from '@playwright/test';
import { CloudHarness, cloudOrigin, sessionA, sessionB, sessionC } from './support/cloud_harness.js';

const commands = app => app.requests.filter(request => request.method === 'POST' && request.path.endsWith('/commands')).map(request => JSON.parse(request.body));

async function open(page) {
  const app = new CloudHarness(page);
  await app.install();
  await app.goto();
  await app.open();
  return app;
}

test('Cloud goals use the shared editor and settle on goal_updated without creating a task', async ({ page }, testInfo) => {
  const app = await open(page);
  const task = page.locator('#task');
  await task.fill('/goal');
  await expect(page.locator('.completion-item').filter({ hasText: '/goal' })).toBeVisible();
  await task.press('Enter');
  await expect(page.locator('#goal-set')).toBeVisible();
  await task.fill('Ship the feature');
  await page.locator('#goal-set').click();
  await expect.poll(() => commands(app)).toEqual([{ command: { command: 'goal', action: 'set', text: 'Ship the feature' } }]);
  await expect(page.locator('.composer-goal')).toContainText('Setting goal');
  await expect(page.locator('#stop')).toHaveCount(0);
  expect(app.controlState(sessionA).data.active_task_id).toBeNull();
  await app.emitSessionEvent(sessionA, 'goal_updated', { goal: 'Ship the feature' }, { task: null });
  await expect(page.locator('.composer-goal')).toContainText('Goal: Ship the feature');
  await expect(page.locator('.composer-goal.pending')).toHaveCount(0);
  await task.fill('Keep this prompt');
  await page.locator('.composer-goal').getByRole('button', { name: 'Edit', exact: true }).click();
  await expect(task).toHaveValue('Ship the feature');
  await task.fill('A revised goal');
  await page.locator('#goal-cancel').click();
  await expect(task).toHaveValue('Keep this prompt');
  await page.screenshot({ path: testInfo.outputPath('cloud-goal.png') });
  await app.open(sessionB);
  await app.open(sessionA);
  await expect(page.locator('.composer-goal')).toContainText('Goal: Ship the feature');
  await page.locator('.composer-goal').getByRole('button', { name: 'Clear the standing goal', exact: true }).click();
  await expect.poll(() => commands(app)).toHaveLength(2);
  expect(commands(app)[1]).toEqual({ command: { command: 'goal', action: 'clear' } });
  await expect(page.locator('.composer-goal')).toContainText('Clearing goal');
  await app.emitSessionEvent(sessionA, 'goal_updated', { goal: null }, { task: null });
  await expect(page.locator('.composer-goal:not(.hidden)')).toHaveCount(0);
  await expect(task).toHaveValue('Keep this prompt');
  expect(app.postCount).toBe(0);
  expect(app.requests.filter(request => request.method === 'POST' && request.path === '/v1/sessions')).toHaveLength(0);
  expect(app.device.pageErrors).toEqual([]);
});

for (const [name, workflow] of [['simplify', 'simplify.mbtx'], ['ultrareview', 'review.mbtx']]) {
  for (const fresh of [false, true]) {
    test(`Cloud ${name} shares prompt expansion in ${fresh ? 'a new' : 'an existing'} session`, async ({ page }, testInfo) => {
      const app = await open(page);
      if (fresh) await app.create();
      const task = page.locator('#task');
      await task.fill(`/${name}`);
      await expect(page.locator('.completion-item').filter({ hasText: `/${name}` })).toBeVisible();
      if (!fresh && name === 'simplify') {
        await task.fill('/');
        await expect(page.locator('.completion-item')).toHaveCount(4);
        await page.screenshot({ path: testInfo.outputPath('cloud-shared-slash-menu.png') });
        await task.fill(`/${name}`);
      }
      await task.press('Enter');
      await expect(task).toHaveValue(`/${name} `);
      await page.keyboard.type('the parser');
      expect(commands(app)).toEqual([]);
      expect(app.requests.filter(request => request.method === 'POST' && request.path === '/v1/sessions')).toHaveLength(0);
      await page.locator('#send').click();
      await expect.poll(() => commands(app).length).toBe(1);
      const command = commands(app)[0].command;
      expect(command.command).toBe('prompt');
      const content = typeof command.content === 'string' ? command.content : command.content.filter(part => part.type === 'text').map(part => part.text).join('');
      expect(content).toContain(`"@builtin/${workflow}"`);
      expect(content).toContain('Focus: the parser');
      if (name === 'ultrareview') expect(content).toContain('"--swarm"');
      await expect(task).toHaveValue('');
      expect(app.requests.filter(request => request.method === 'POST' && request.path === '/v1/sessions')).toHaveLength(fresh ? 1 : 0);
      expect(app.device.pageErrors).toEqual([]);
    });
  }
}

for (const name of ['goal', 'compact']) {
  test(`first Cloud ${name} creates once, observes before sending, and keeps later typing`, async ({ page }, testInfo) => {
    const app = await open(page);
    await app.create();
    let create;
    let observe;
    app.pauseCreate = new Promise(resolve => { create = resolve; });
    app.pauseSessionEvents = new Promise(resolve => { observe = resolve; });
    const task = page.locator('#task');
    await task.fill(`/${name}`);
    await expect(page.locator('.completion-item').filter({ hasText: `/${name}` })).toBeVisible();
    await task.press('Enter');
    if (name === 'goal') {
      expect(app.requests.filter(request => request.method === 'POST' && request.path === '/v1/sessions')).toHaveLength(0);
      await task.fill('A goal before the first prompt');
      await page.locator('#goal-set').click();
    }
    await expect.poll(() => app.requests.filter(request => request.method === 'POST' && request.path === '/v1/sessions').length).toBe(1);
    await expect(task).toBeDisabled();
    expect(commands(app)).toEqual([]);
    create();
    await expect(app.row(sessionC)).toHaveAttribute('aria-current', 'true');
    await expect(task).toBeEnabled();
    await task.fill('Keep this unsent prompt');
    expect(commands(app)).toEqual([]);
    if (name === 'compact') await app.open(sessionB);
    observe();
    await expect.poll(() => commands(app)).toEqual([{ command: name === 'goal'
      ? { command: 'goal', action: 'set', text: 'A goal before the first prompt' }
      : { command: 'compact' } }]);
    if (name === 'goal') {
      await app.emitSessionEvent(sessionC, 'goal_updated', { goal: 'A goal before the first prompt' }, { task: null });
      await expect(page.locator('.composer-goal')).toContainText('Goal: A goal before the first prompt');
    } else {
      await app.emitSessionEvent(sessionC, 'compaction_started', { from_sequence: 1, to_sequence: 1 }, { task: null });
      await app.emitSessionEvent(sessionC, 'compaction_finished', { from_sequence: 1, to_sequence: 1, summary: 'Empty fixture' }, { task: null });
      await app.publishControl(sessionC, { compact_queued: false, compacting: false });
      await app.open(sessionC);
      await expect(page.locator('.composer-notice-text')).toHaveCount(0);
    }
    await expect(task).toHaveValue('Keep this unsent prompt');
    await expect(page.locator('#stop')).toHaveCount(0);
    expect(app.postCount).toBe(0);
    await app.open(sessionB);
    await app.open(sessionC);
    await expect(task).toHaveValue('Keep this unsent prompt');
    expect(app.requests.filter(request => request.method === 'POST' && request.path === '/v1/sessions')).toHaveLength(1);
    expect(commands(app)).toHaveLength(1);
    await page.screenshot({ path: testInfo.outputPath(`cloud-first-${name}.png`) });
    expect(app.device.pageErrors).toEqual([]);
  });
}

test('first Cloud goal creation failure retains its editor and command rejection reuses the created session', async ({ page }) => {
  const app = await open(page);
  await app.create();
  app.createStatus = 503;
  const task = page.locator('#task');
  await task.fill('/goal');
  await expect(page.locator('.completion-item').filter({ hasText: '/goal' })).toBeVisible();
  await task.press('Enter');
  await expect(page.locator('#goal-set')).toBeVisible();
  await task.fill('Retain this goal');
  await page.locator('#goal-set').click();
  await expect(page.getByRole('main')).toContainText('Error');
  await expect(task).toHaveValue('Retain this goal');
  await expect(page.locator('#goal-set')).toBeEnabled();
  expect(commands(app)).toEqual([]);
  app.createStatus = 201;
  let releaseHistory;
  app.pauseHistory = new Promise(resolve => { releaseHistory = resolve; });
  app.controlRejected = 'Model is unavailable';
  await page.locator('#goal-set').click();
  await expect(page.getByRole('main')).toContainText('Model is unavailable');
  const history = page.waitForResponse(response => response.request().method() === 'GET' && response.url().endsWith(`/${sessionC}/messages`));
  releaseHistory();
  await (await history).finished();
  await expect(page.getByRole('main')).toContainText('Model is unavailable');
  await expect(task).toHaveValue('Retain this goal');
  await expect(page.locator('.composer-goal.pending')).toHaveCount(0);
  app.controlRejected = null;
  await page.locator('#goal-set').click();
  await expect.poll(() => commands(app).length).toBe(2);
  expect(app.requests.filter(request => request.method === 'POST' && request.path === '/v1/sessions')).toHaveLength(2);
  expect(commands(app)[1]).toEqual({ command: { command: 'goal', action: 'set', text: 'Retain this goal' } });
  expect(app.device.pageErrors).toEqual([]);
});

async function compact(page) {
  await page.locator('#task').fill('/compact');
  await expect(page.locator('.completion-item').filter({ hasText: '/compact' })).toBeVisible();
  await page.locator('#task').press('Enter');
}

test('Cloud queues native compaction during a turn and restores it across navigation and reconnect', async ({ page }, testInfo) => {
  const app = await open(page);
  app.manualTasks = true;
  await page.locator('#task').fill('Start work');
  await page.locator('#send').click();
  await expect(page.locator('#stop')).toBeEnabled();
  const task = app.controlState(sessionA).task_id;
  await compact(page);
  await expect.poll(() => commands(app).filter(value => value.command.command === 'compact')).toEqual([
    { command: { command: 'compact' }, task_id: task },
  ]);
  const notice = page.locator('.composer-notice-text');
  await expect(notice).toContainText('queued');
  await page.locator('#task').fill('Keep editing this draft');
  await app.emitSessionEvent(sessionA, 'auto_compaction_started', { from_sequence: 1, to_sequence: 2 });
  await expect(notice).toContainText('Compacting context');
  await app.emitSessionEvent(sessionA, 'auto_compaction_finished', { from_sequence: 1, to_sequence: 2, summary: 'Automatic context' });
  await expect(notice).toContainText('queued');
  await app.emitSessionEvent(sessionA, 'task_finished', { status: 'completed' });
  await expect(page.locator('#stop')).toHaveCount(0);
  await expect(notice).toContainText('queued');
  await app.open(sessionB);
  await app.open(sessionA);
  await expect(notice).toContainText('queued');
  await app.disconnectSession(sessionA);
  await expect.poll(() => app.requests.filter(value => value.path.endsWith('/events') && !value.path.endsWith('/files/events')).length).toBeGreaterThan(3);
  await expect(notice).toContainText('queued');
  await expect(page.locator('#task')).toHaveValue('Keep editing this draft');
  await page.screenshot({ path: testInfo.outputPath('cloud-compaction-queued.png') });
  await app.emitSessionEvent(sessionA, 'compaction_started', { from_sequence: 1, to_sequence: 2 }, { task: null });
  await expect(notice).toContainText('Compacting context');
  await app.emitSessionEvent(sessionA, 'compaction_finished', { from_sequence: 1, to_sequence: 2, summary: 'Manual context' }, { task: null });
  await expect(notice).toHaveCount(0);
  await expect(page.locator('#task')).toHaveValue('Keep editing this draft');
  expect(commands(app).filter(value => value.command.command === 'compact')).toHaveLength(1);
  expect(app.device.pageErrors).toEqual([]);
});

test('Cloud idle compaction settles without an assistant or a task and reports failure', async ({ page }) => {
  const app = await open(page);
  await compact(page);
  await expect.poll(() => commands(app)).toEqual([{ command: { command: 'compact' } }]);
  await expect(page.locator('.composer-notice-text')).toContainText('queued');
  await expect(page.locator('#stop')).toHaveCount(0);
  await app.emitSessionEvent(sessionA, 'compaction_started', { from_sequence: 1, to_sequence: 2 }, { task: null });
  await app.emitSessionEvent(sessionA, 'compaction_failed', { error: 'Fixture compaction failed' }, { task: null });
  await expect(page.locator('.composer-notice-text')).toHaveCount(0);
  await expect(page.getByText('Fixture compaction failed', { exact: true })).toBeVisible();
  expect(app.controlState(sessionA).data.active_task_id).toBeNull();
  expect(app.postCount).toBe(0);
});

test('Cloud reload restores the goal and summary from the native session document', async ({ page }) => {
  const app = new CloudHarness(page);
  app.histories.set(sessionA, {
    messages: [], generating: false,
    session: { events: [
      { sequence: 1, item: { kind: 'runtime_notice', payload: { content: '[goal]\nFinish the release' } } },
      { sequence: 2, item: { kind: 'summary', payload: { content: 'Earlier release work', from_sequence: 0, to_sequence: 1 } } },
    ] },
  });
  await app.install();
  await app.goto();
  await app.open();
  await expect(page.locator('.composer-goal')).toContainText('Finish the release');
  await expect(page.getByText('Earlier release work', { exact: true })).toHaveCount(1);
  await page.reload();
  await app.open();
  await expect(page.locator('.composer-goal')).toContainText('Finish the release');
  await expect(page.getByText('Earlier release work', { exact: true })).toHaveCount(1);
  expect(commands(app)).toHaveLength(0);
});

test('Cloud preserves a service-only prompt and startup failure across reopen and reload', async ({ page }) => {
  const app = new CloudHarness(page);
  app.histories.set(sessionA, {
    generating: false,
    session: { events: [] },
    messages: [
      { task_id: 'failed-start', kind: 'user', data: { content: 'Please check the build' }, created_at: 1000 },
      { task_id: 'failed-start', kind: 'task_finished', data: { status: 'failed', reason: 'Fixture engine could not start' }, created_at: 1001 },
    ],
  });
  await app.install();
  await app.goto();
  await app.open();
  const check = async () => {
    await expect(page.locator('#transcript').getByText('Please check the build', { exact: true })).toHaveCount(1);
    await expect(page.locator('#transcript').getByText('Fixture engine could not start', { exact: true })).toHaveCount(1);
  };
  await check();
  await app.open(sessionB);
  await app.open(sessionA);
  await check();
  await page.reload();
  await app.open();
  await check();
  // The same saved native items arriving later replace the supplements.
  app.histories.get(sessionA).messages[0].engine_sequence = 1;
  app.histories.get(sessionA).session.events = [
    { sequence: 1, item: { kind: 'user', payload: { content: 'Please check the build' } } },
    { sequence: 2, item: { kind: 'terminal', payload: { kind: 'failed', message: 'Fixture engine could not start' } } },
  ];
  await app.open(sessionB);
  await app.open(sessionA);
  await check();
  expect(commands(app)).toHaveLength(0);
  expect(app.device.pageErrors).toEqual([]);
});

for (const { status, body, notice, label } of [
  { status: 503, body: 'server model credentials are not configured', notice: 'Cloud model credentials are not configured', label: 'model credentials are explicitly missing' },
  { status: 409, body: JSON.stringify({accepted: false, error: 'Cannot accept this command while compaction is pending.'}), notice: 'Cannot accept this command while compaction is pending.', label: 'the command is rejected with JSON' },
]) {
  for (const command of ['compact', 'goal']) {
    test(`Cloud ${command} clears pending state when ${label}`, async ({ page }) => {
      const app = await open(page);
      await page.route('**/v1/sessions/*/commands', async route => {
        if (route.request().method() !== 'POST') return route.fallback();
        const request = route.request().postDataJSON();
        if (request.command.command !== command) return route.fallback();
        await route.fulfill({ status, headers: { 'Access-Control-Allow-Origin': '*' }, contentType: 'text/plain', body });
      });
      if (command === 'compact') {
        await compact(page);
        await expect(page.locator('.composer-notice-text')).toHaveCount(0);
        await page.locator('#task').fill('Keep this editable prompt');
        await expect(page.locator('#send')).toBeEnabled();
      } else {
        await page.locator('#task').fill('/goal');
        await expect(page.locator('.completion-item').filter({ hasText: '/goal' })).toBeVisible();
        await page.locator('#task').press('Enter');
        await expect(page.locator('#goal-set')).toBeVisible();
        await page.locator('#task').fill('Keep this goal');
        await page.locator('#goal-set').click();
        await expect(page.locator('#goal-set')).toBeVisible();
        await expect(page.locator('#task')).toHaveValue('Keep this goal');
        await expect(page.locator('.composer-goal.pending')).toHaveCount(0);
      }
      await expect(page.locator('#transcript')).toContainText(notice);
      if (command === 'goal') {
        await expect(page.locator('#goal-set')).toBeVisible();
        await expect(page.locator('#task')).toHaveValue('Keep this goal');
        await expect(page.locator('.composer-goal.pending')).toHaveCount(0);
      }
      expect(app.device.pageErrors).toEqual([]);
    });
  }
}


test('Cloud keeps failed and successful identical prompts in task order live and after reload', async ({ page }) => {
  const app = new CloudHarness(page);
  app.manualTasks = true;
  let successfulTask = null;
  let nativeUserSaved = false;
  await app.install();
  await page.route(`${cloudOrigin}/v1/sessions/${sessionA}/messages`, async route => {
    if (route.request().method() !== 'GET') return route.fallback();
    const history = app.histories.get(sessionA) || { messages: [], generating: false };
    const current = history.messages.filter(record => record.task_id === successfulTask);
    const items = [];
    const user = current.find(record => record.kind === 'user');
    if (nativeUserSaved && user) items.push({ kind: 'user', payload: user.data });
    const assistant = current.find(record => record.kind === 'assistant_message');
    if (assistant) items.push({ kind: 'assistant', payload: assistant.data });
    if (current.some(record => record.kind === 'task_finished')) items.push({ kind: 'terminal', payload: { kind: 'finished', message: 'Successful answer' } });
    const messages = history.messages.map(record => nativeUserSaved && record.task_id === successfulTask && record.kind === 'user' ? { ...record, engine_sequence: 1 } : record);
    await route.fulfill({ headers: { 'Access-Control-Allow-Origin': '*' }, contentType: 'application/json', body: JSON.stringify({ ...history, messages, session: { events: items.map((item, index) => ({ sequence: index + 1, item })) } }) });
  });
  await app.goto();
  await app.open();
  const transcript = page.locator('#transcript');
  await page.locator('#task').fill('Same question');
  await page.locator('#send').click();
  await expect(page.locator('#stop')).toBeEnabled();
  await app.emitSessionEvent(sessionA, 'task_finished', { status: 'failed', reason: 'Engine could not start' });
  await expect(transcript).toContainText('Engine could not start');
  await expect(page.locator('#stop')).toHaveCount(0);
  await page.locator('#task').fill('Same question');
  await page.locator('#send').click();
  await expect(page.locator('#stop')).toBeEnabled();
  successfulTask = app.controlState(sessionA).task_id;
  await expect(transcript.getByText('Same question', { exact: true })).toHaveCount(2);
  await expect(transcript).toContainText(/Same question[\s\S]*Engine could not start[\s\S]*Same question/);
  nativeUserSaved = true;
  await app.emitSessionEvent(sessionA, 'assistant_message', { content: 'Successful answer' });
  await app.emitSessionEvent(sessionA, 'task_finished', { status: 'completed', result: { output: { answer: 'Successful answer' } } });
  const check = async () => {
    await expect(transcript.getByText('Same question', { exact: true })).toHaveCount(2);
    await expect(transcript.getByText('Successful answer', { exact: true })).toHaveCount(1);
    await expect(transcript).toContainText(/Same question[\s\S]*Engine could not start[\s\S]*Same question[\s\S]*Successful answer/);
  };
  await check();
  await app.open(sessionB);
  await app.open(sessionA);
  await check();
  await page.reload();
  await app.open();
  await check();
  expect(app.postCount).toBe(2);
  expect(app.device.pageErrors).toEqual([]);
});

for (const command of ['goal', 'compact']) {
  test(`Cloud ${command} recovers from host failure and keeps observing`, async ({ page }) => {
    const app = await open(page);
    if (command === 'compact') await compact(page);
    else {
      await page.locator('#task').fill('/goal');
      await expect(page.locator('.completion-item').filter({hasText: '/goal'})).toBeVisible();
      await page.locator('#task').press('Enter');
      await expect(page.locator('#goal-set')).toBeVisible();
      await page.locator('#task').fill('Recover this goal');
      await page.locator('#goal-set').click();
    }
    await expect.poll(() => commands(app).length).toBe(1);
    await app.emitSessionEvent(sessionA, 'engine_failed', {error: 'Fixture host could not start'}, {task: null});
    await app.publishControl(sessionA, {active_task_id: null, status: 'idle', compacting: false, compact_queued: false, paused: true});
    await expect(page.locator('#transcript')).toContainText('Fixture host could not start');
    await expect(page.locator('.composer-notice-text')).toHaveCount(0);
    if (command === 'goal') {
      await expect(page.locator('#goal-set')).toBeVisible();
      await expect(page.locator('#task')).toHaveValue('Recover this goal');
      await page.locator('#goal-cancel').click();
    }
    await app.emitSessionEvent(sessionA, 'goal_updated', {goal: 'Observation still works'}, {task: null});
    await expect(page.locator('.composer-goal')).toContainText('Observation still works');
    expect(commands(app)).toHaveLength(1);
    expect(app.device.pageErrors).toEqual([]);
  });
}

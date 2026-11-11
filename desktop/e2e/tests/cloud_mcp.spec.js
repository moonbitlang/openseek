import { test, expect } from './support/test.js';
import { CloudHarness, sessionA, sessionB } from './support/cloud_harness.js';

function clientTools(app) {
  let generation = 0;
  let questions = [];
  const waiting = new Map();
  const snapshot = () => ({ generation, requests: questions });
  const publish = event => app.page.evaluate(event => window.desktopEvent('openseek.cloud.mcp.event', event), event);
  app.clientMcp = async request => {
    expect(request.account).toBe(app.userId);
    if (request.action === 'questions') return snapshot();
    if (request.action === 'detach') {
      for (const q of questions.filter(q => q.session === request.session)) {
        waiting.get(q.id)?.({ id: q.id, status: 'pending', answers: null });
        waiting.delete(q.id);
      }
      return null;
    }
    if (request.action === 'answer') {
      const answer = request.answer;
      const pending = questions.find(q => q.id === answer.id && q.session === answer.session);
      expect(pending).toBeTruthy();
      questions = questions.filter(q => q !== pending);
      generation++;
      const finish = waiting.get(answer.id);
      if (finish) {
        waiting.delete(answer.id);
        finish({ id: answer.id, status: 'answered', answers: answer.answers });
      } else {
        await publish({ kind: 'input', account: app.userId, session: answer.session, id: answer.id + '-result', text: '<user_question_response request_id="question" status="answered">\n<question id="plan">\n<title>Which plan?</title>\n<answer>' + answer.answers.plan + '</answer>\n</question>\n</user_question_response>' });
      }
      await publish({ kind: 'questions', account: app.userId, snapshot: snapshot() });
      return snapshot();
    }
    const { message, session } = request;
    const result = value => ({ jsonrpc: '2.0', id: message.id, result: value });
    if (message.method === 'initialize') return result({ serverInfo: { name: 'seekmoon', version: 'test' }, capabilities: { tools: {} }, protocolVersion: '2025-11-25' });
    if (message.method === 'tools/list') return result({ tools: [{ name: 'browser_open' }, { name: 'ask_user' }] });
    if (message.method === 'tools/call' && message.params.name === 'browser_open') {
      await app.page.evaluate(({ session, url, account }) => window.desktopEvent('openseek.browser.event', { kind: 'cloud_open_requested', account, request: 'open-test', session, url }), { session, account: app.userId, url: message.params.arguments.url });
      return result({ content: [{ type: 'text', text: 'opened' }], isError: false });
    }
    if (message.method === 'tools/call' && message.params.name === 'ask_user') {
      const id = `question-${message.id}`;
      questions.push({ id, session, questions: message.params.arguments.questions });
      generation++;
      await publish({ kind: 'questions', account: app.userId, snapshot: snapshot() });
      const answer = await new Promise(resolve => waiting.set(id, resolve));
      return result({ content: [{ type: 'text', text: JSON.stringify(answer) }], isError: false });
    }
    return result({});
  };
  return {
    detach(id) { waiting.get(id)?.({ id, status: 'pending', answers: null }); waiting.delete(id); },
    publish,
  };
}

function request(app, session, id, method, params = {}) {
  app.mcpSockets.get(session).send(JSON.stringify({ jsonrpc: '2.0', id, method, params }));
}

async function connected(app, session = sessionA) {
  await expect.poll(() => app.mcpFrames.filter(f => f.session === session && f.frame.type === 'auth').length).toBe(1);
  expect(app.mcpFrames.find(f => f.session === session).frame).toEqual({ type: 'auth', token: `ts_fixture-${app.userId}` });
}

test('client MCP authenticates before discovery, opens a visible Cloud pane, and retains connections across sessions', async ({ page }) => {
  const app = new CloudHarness(page, { desktop: true });
  clientTools(app);
  const nativeRequests = [];
  const reply = app.device.replyFor.bind(app.device);
  app.device.replyFor = request => {
    if (request.method.startsWith('browser.')) { nativeRequests.push(request); return {}; }
    return reply(request);
  };
  await app.install();
  await app.goto();
  await app.open();
  await connected(app);
  request(app, sessionA, 1, 'initialize');
  request(app, sessionA, 2, 'tools/list');
  await expect.poll(() => app.mcpFrames.some(f => f.frame.id === 2)).toBe(true);
  expect(app.mcpFrames.find(f => f.frame.id === 2).frame.result.tools.map(t => t.name)).toEqual(['browser_open', 'ask_user']);
  request(app, sessionA, 3, 'tools/call', { name: 'browser_open', arguments: { url: 'https://example.test/demo' } });
  await expect(page.locator('.browser-address')).toHaveValue('https://example.test/demo');
  await expect.poll(() => nativeRequests.some(r => r.method === 'browser.set_bounds' && r.params.width > 0)).toBe(true);
  await expect.poll(() => nativeRequests.some(r => r.method === 'browser.set_visible' && r.params.visible)).toBe(true);
  await app.open(sessionB);
  await connected(app, sessionB);
  expect(app.mcpSockets.has(sessionA)).toBe(true);
  await expect.poll(() => nativeRequests.filter(r => r.method === 'browser.set_visible').at(-1)?.params.visible).toBe(false);
  await app.open(sessionA);
  await expect.poll(() => nativeRequests.filter(r => r.method === 'browser.set_visible').at(-1)?.params.visible).toBe(true);
  await page.screenshot({ path: 'test-results/cloud-client-mcp-browser.png' });
});

test('Cloud questions use the existing card and route immediate and delayed answers to their original session', async ({ page }) => {
  const app = new CloudHarness(page, { desktop: true });
  const tools = clientTools(app);
  await app.install();
  await app.goto();
  await app.open();
  await connected(app);
  const questions = [{ id: 'plan', title: 'Which plan?', options: ['Small change', 'Full redesign'] }];
  request(app, sessionA, 10, 'tools/call', { name: 'ask_user', arguments: { questions } });
  const card = page.locator('.user-question-card');
  await expect(card).toContainText('Which plan?');
  await page.screenshot({ path: 'test-results/cloud-client-mcp-question.png' });
  await card.getByRole('button', { name: 'Small change', exact: true }).click();
  await card.getByRole('button', { name: 'Send', exact: true }).click();
  await expect(card).toHaveCount(0);
  await expect.poll(() => app.mcpFrames.some(f => f.frame.id === 10)).toBe(true);
  expect(JSON.parse(app.mcpFrames.find(f => f.frame.id === 10).frame.result.content[0].text).answers).toEqual({ plan: 'Small change' });
  expect(app.requests.filter(r => r.path.endsWith('/commands'))).toHaveLength(0);
  request(app, sessionA, 11, 'tools/call', { name: 'ask_user', arguments: { questions } });
  await expect(card).toBeVisible();
  tools.detach('question-11');
  await app.open(sessionB);
  await expect(card).toHaveCount(0);
  await app.open(sessionA);
  await expect(card).toContainText('Which plan?');
  await card.locator('textarea').fill('Keep the keyboard workflow');
  await card.getByRole('button', { name: 'Send', exact: true }).click();
  await expect.poll(() => app.requests.filter(r => r.path === `/v1/sessions/${sessionA}/commands` && r.method === 'POST').length).toBe(1);
  const command = JSON.parse(app.requests.find(r => r.path.endsWith('/commands')).body).command;
  expect(command.command).toBe('prompt');
  expect(command.submission_id).toBe('question-11-result');
  expect(JSON.stringify(command.content)).toContain('Keep the keyboard workflow');
  expect(app.requests.some(r => r.path === `/v1/sessions/${sessionB}/commands`)).toBe(false);
  expect(app.hostRequests.some(r => r.method === 'session.load' && [sessionA, sessionB].includes(r.params.session))).toBe(false);
});

test('desktop sends wait for MCP ready and logout closes every connection', async ({ page }) => {
  const app = new CloudHarness(page, { desktop: true });
  clientTools(app);
  let allow;
  app.pauseMcpReady = new Promise(resolve => { allow = resolve; });
  await app.install();
  await app.goto();
  await app.open();
  await connected(app);
  await page.locator('#task').fill('Please inspect this project');
  await page.locator('#send').click();
  expect(app.requests.filter(r => r.path.endsWith('/commands'))).toHaveLength(0);
  allow();
  await expect.poll(() => app.requests.filter(r => r.path.endsWith('/commands')).length).toBe(1);
  await app.open(sessionB);
  await connected(app, sessionB);
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await page.getByRole('tab', { name: 'Account', exact: true }).click();
  await page.getByRole('button', { name: 'Sign out', exact: true }).click();
  await expect.poll(() => app.mcpSockets.size).toBe(0);
});


test('reconnect does not replay calls and answers to detached questions use Cloud input', async ({ page }) => {
  const app = new CloudHarness(page, { desktop: true });
  clientTools(app);
  await app.install();
  await app.goto();
  await app.open();
  await connected(app);
  request(app, sessionA, 40, 'tools/call', { name: 'ask_user', arguments: { questions: [{ id: 'plan', title: 'Which plan?' }] } });
  const card = page.locator('.user-question-card');
  await expect(card).toBeVisible();
  app.mcpSockets.get(sessionA).close({ code: 1012, reason: 'fixture restart' });
  await expect.poll(() => app.mcpFrames.filter(f => f.session === sessionA && f.frame.type === 'auth').length).toBe(2);
  await card.locator('textarea').fill('Keep the same question');
  await card.getByRole('button', { name: 'Send', exact: true }).click();
  await expect.poll(() => app.requests.filter(r => r.method === 'POST' && r.path.endsWith('/commands')).length).toBe(1);
  expect(app.mcpFrames.filter(f => f.frame.id === 40)).toHaveLength(0);
  expect(app.hostRequests.filter(r => r.method === 'cloud.mcp' && r.params.action === 'dispatch' && r.params.message.id === 40)).toHaveLength(1);
});

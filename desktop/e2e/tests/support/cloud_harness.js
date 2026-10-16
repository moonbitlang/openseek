import { readFile } from 'node:fs/promises';
import { expect } from '@playwright/test';
import { DesktopBrowserHarness } from './desktop_browser_harness.js';

export const authOrigin = 'https://openseek-api.moonbitlang.cn';
export const cloudOrigin = 'https://cloud.moonbitlang.cn';
export const sessionA = '11111111-1111-4111-8111-111111111111';
export const sessionB = '22222222-2222-4222-8222-222222222222';
export const sessionC = '33333333-3333-4333-8333-333333333333';
const bundle = new URL('../../../dist/browser/', import.meta.url);

export class CloudHarness {
  constructor(page, { desktop = false, cached = true } = {}) {
    this.page = page;
    this.desktop = desktop;
    this.cached = cached;
    this.accountSignedIn = cached;
    this.device = new DesktopBrowserHarness(page);
    this.requests = [];
    this.hostRequests = [];
    this.codes = new Map();
    this.userId = '123';
    this.apiStatus = 200;
    this.meStatus = 401;
    this.listStatus = 200;
    this.historyStatus = 200;
    this.createStatus = 201;
    this.sendStatus = 200;
    this.shareStatus = 200;
    this.disconnectShare = false;
    this.logoutStatus = 204;
    this.apiOffline = false;
    this.listOffline = false;
    this.disconnectSend = false;
    this.rejectStreamCancel = false;
    this.streamCancellations = 0;
    this.pauseCreate = null;
    this.pauseSend = null;
    this.pauseHistory = null;
    this.pauseStream = null;
    this.sessionIds = [sessionA, sessionB];
    this.histories = new Map();
    this.titles = new Map([[sessionA, 'Cloud fixture A'], [sessionB, 'Cloud fixture B']]);
    this.postCount = 0;
    this.exchangeCount = 0;
    this.taskCount = 0;
  }

  async install() {
    await this.device.install();
    await this.page.exposeFunction('cloudWaitForStream', () => this.pauseStream);
    await this.page.exposeFunction('cloudWaitForEvent', index => this.eventPauses?.get(index));
    await this.page.exposeFunction('cloudStreamCancelled', () => this.streamCancellations++);
    await this.page.addInitScript(({ cached, authOrigin, cloudOrigin, rejectStreamCancel }) => {
      window.cloudUnhandledRejections = [];
      window.addEventListener('unhandledrejection', event => window.cloudUnhandledRejections.push(String(event.reason)));
      const key = 'seekmoon.cloud.token.v1';
      if (cached && !sessionStorage.getItem('fixture-cloud-seeded')) {
        sessionStorage.setItem('fixture-cloud-seeded', 'true');
        localStorage.setItem(key, JSON.stringify({ auth_origin: authOrigin, cloud_origin: cloudOrigin, user_id: '123', token: 'legacy-cloud-token' }));
        localStorage.setItem('seekmoon.account.v1', JSON.stringify({ token: 'ts_fixture-123', user: { user_id: '123', login: 'octocat', avatar_url: '' } }));
      }
      const original = window.fetch;
      window.fetch = async (...args) => {
        const response = await original(...args);
        if (String(args[0]).startsWith(cloudOrigin) && response.headers.get('content-type')?.startsWith('text/event-stream')) {
          const bytes = new TextEncoder().encode(await response.text());
          let cancelled = false;
          return new Response(new ReadableStream({ async start(controller) {
            // Every byte is a separate chunk, splitting UTF-8 and SSE fields.
            const boundary = response.headers.get('x-fixture-admission-bytes');
            const boundaries = JSON.parse(response.headers.get('x-fixture-event-boundaries') || '[]');
            const disconnectAfter = response.headers.get('x-fixture-disconnect-after');
            let eventIndex = 0;
            for (let i = 0; i < bytes.length; i++) {
              if (cancelled) return;
              controller.enqueue(new Uint8Array([bytes[i]]));
              if (i + 1 === Number(boundary)) await window.cloudWaitForStream();
              if (i + 1 === boundaries[eventIndex]) {
                await window.cloudWaitForEvent(eventIndex);
                if (disconnectAfter !== null && eventIndex === Number(disconnectAfter)) {
                  controller.error(new Error('Fixture stream disconnected'));
                  return;
                }
                eventIndex++;
              }
            }
            if (!cancelled) controller.close();
          }, cancel() {
            cancelled = true;
            window.cloudStreamCancelled();
            if (rejectStreamCancel) return Promise.reject(new Error('Fixture cancellation rejected'));
          } }), { status: response.status, headers: response.headers });
        }
        return response;
      };
    }, { cached: this.cached, authOrigin, cloudOrigin, rejectStreamCancel: this.rejectStreamCancel });
    await this.page.route(`${authOrigin}/console/**`, async route => {
      const path = new URL(route.request().url()).pathname.replace(/^\/console\/(?:releases\/v[^/]+\/)?/, '') || 'index.html';
      const contentType = path.endsWith('.js') ? 'text/javascript' : path.endsWith('.css') ? 'text/css' : path.endsWith('.html') ? 'text/html' : 'application/octet-stream';
      await route.fulfill({ contentType, body: await readFile(new URL(path, bundle)) });
    });
    // Intercept legacy requests too, so accidental downgrades fail locally.
    await this.page.route(`${authOrigin}/{v1,v2}/auth/**`, async route => {
      const request = route.request();
      const path = new URL(request.url()).pathname;
      this.requests.push({ side: 'api', path, method: request.method(), body: request.postData(), headers: await request.allHeaders() });
      if (this.apiOffline) return route.abort('failed');
      if (path === '/v2/auth/me') {
        const signed = this.accountSignedIn || (request.headers().cookie || '').includes('fixture-account');
        return route.fulfill({ status: signed ? 200 : this.meStatus, contentType: 'application/json', body: JSON.stringify({ user_id: this.userId, login: 'octocat', avatar_url: '' }) });
      }
      if (path === '/v2/auth/session') {
        this.accountSignedIn = true;
        return route.fulfill({ status: this.apiStatus, contentType: 'application/json', body: JSON.stringify(this.account()) });
      }
      if (path === '/v2/auth/logout') {
        this.accountSignedIn = false;
        return route.fulfill({ status: this.logoutStatus, contentType: 'application/json', body: '{"error":"Fixture logout failed"}' });
      }
      if (path === '/v2/auth/login') {
        if (new URL(request.url()).searchParams.get('prompt') !== 'select_account') throw new Error('Explicit login must allow account selection');
        this.accountSignedIn = true;
        const destination = new URL(request.url()).searchParams.get('return_to') || '/console/';
        // Start a fresh navigation: HTTP redirects can bypass page-scoped mocks.
        return route.fulfill({ contentType: 'text/html', body: `<script>location.replace(${JSON.stringify(destination)})</script>` });
      }
      throw new Error(`Unexpected account request: ${path}`);
    });
    await this.page.route(`${cloudOrigin}/**`, route => this.cloudRequest(route));
    if (this.desktop) await this.installDesktopBridge();
  }

  account() { return { token: `ts_fixture-${this.userId}`, user: { user_id: this.userId, login: 'octocat', avatar_url: '' } }; }

  async installDesktopBridge() {
    await this.page.exposeFunction('cloudHostRequest', async request => {
      this.hostRequests.push(request);
      if (request.method === 'app.system_appearance') return { dark: false };
      if (request.method === 'auth.status') return { connected: false, server_url: authOrigin };
      if (request.method === 'account.session') return this.accountSignedIn ? { session: this.account() } : {};
      if (request.method === 'auth.connect') {
        if (this.authorizationError) throw new Error(this.authorizationError);
        this.accountSignedIn = true;
        return { connected: false, server_url: authOrigin, user: { login: 'octocat', avatar_url: '' } };
      }
      if (request.method === 'auth.disconnect') { this.accountSignedIn = false; return { connected: false, server_url: authOrigin }; }
      if (request.method === 'remote.access_set') return { connected: false, server_url: authOrigin };
      if (request.method === 'cloud.key') throw new Error('Cloud must not read local credentials');
      return this.device.replyFor(request);
    });
    await this.page.addInitScript(() => {
      const listeners = new Map();
      const events = { on(name, callback) {
        const callbacks = listeners.get(name) || new Set();
        listeners.set(name, callbacks);
        callbacks.add(callback);
        return () => callbacks.delete(callback);
      } };
      window.desktopEvent = (name, payload) => {
        for (const callback of listeners.get(name) || []) callback({ payload });
      };
      window.__MoonBit__ = { getTitlebarArea: async () => null, app: events, events,
        openseek: new Proxy({}, { get: (_, method) => async params => {
          if (method === 'host.connect') for (const callback of listeners.get('openseek.agent.connected') || []) callback({ payload: { stage: 'serving' } });
          return window.cloudHostRequest({ method, params });
        } }),
      };
    });
  }

  async cloudRequest(route) {
    const request = route.request();
    const path = new URL(request.url()).pathname;
    const headers = { 'Access-Control-Allow-Origin': authOrigin, 'Access-Control-Allow-Headers': 'Authorization, Content-Type', 'Access-Control-Allow-Methods': 'GET, POST, OPTIONS', 'Access-Control-Expose-Headers': 'x-fixture-admission-bytes, x-fixture-event-boundaries, x-fixture-disconnect-after' };
    if (request.method() === 'OPTIONS') return route.fulfill({ status: 204, headers });
    this.requests.push({ side: 'cloud', path, method: request.method(), body: request.postData(), headers: await request.allHeaders() });
    const json = (data, status = 200) => route.fulfill({ status, headers, contentType: 'application/json', body: JSON.stringify(data) });
    if (path === '/v1/sessions') {
      if (request.method() === 'POST') {
        const finish = this.pauseCreate;
        if (finish) await finish;
        if (this.createStatus !== 201) return json({}, this.createStatus);
        this.sessionIds = [sessionC, ...this.sessionIds.filter(id => id !== sessionC)];
        return json({ id: sessionC }, 201);
      }
      if (this.listOffline) return route.abort('failed');
      const status = this.listStatus;
      if (status === 401) this.listStatus = 200;
      return json({ sessions: this.sessionIds.map(id => ({ id, title: this.titles.get(id) ?? null, updated_at: 1000, generating: false })) }, status);
    }
    if (/^\/v1\/sessions\/[^/]+\/share$/.test(path)) {
      const body = request.postDataJSON();
      if (Object.keys(body).join(',') !== 'idempotency_key') throw new Error('Share accepts only the operation key');
      if (this.disconnectShare) return route.abort('failed');
      return json({ url: `${authOrigin}/v1/shares/sh_fixture` }, this.shareStatus);
    }
    const match = path.match(/^\/v1\/sessions\/([^/]+)\/messages$/);
    if (!match) throw new Error(`Unexpected Cloud request: ${path}`);
    const session = match[1];
    if (request.method() === 'GET') {
      const history = this.histories.get(session) || { messages: [], generating: false, outcome: null };
      if (this.pauseHistory) await this.pauseHistory;
      return json(history, this.historyStatus);
    }
    this.postCount++;
    const body = request.postDataJSON();
    if (Object.keys(body).join(',') !== 'content') throw new Error('Cloud must send content without a model key');
    if (this.sendStatus !== 200) return this.sendErrorBody ? route.fulfill({ status: this.sendStatus, headers, contentType: 'text/plain', body: this.sendErrorBody }) : json({}, this.sendStatus);
    if (!this.titles.get(session)) this.titles.set(session, body.content.trim().split('\n')[0].trim());
    const task = `fixture-task-${++this.taskCount}`;
    const data = this.streamEvents || [
      ['task_started', {}],
      ['tool_call', { id: `calc-${task}`, name: 'mbtx', arguments: '{"source":"println(2)"}' }],
      ['tool_result', { tool_call_id: `calc-${task}`, tool_name: 'mbtx', content: '2', is_error: false }],
      ['assistant_message', { content: '您好 🌙 — calculation complete.' }],
      ['task_finished', { status: 'completed', result: { output: { answer: '您好 🌙 — calculation complete.' } } }],
    ];
    const previous = this.histories.get(session)?.messages || [];
    const messages = [...previous, { id: previous.length + 70, task_id: task, kind: 'user', data: { content: body.content }, created_at: 1000 },
      ...data.slice(1).filter(([kind]) => !['assistant_delta', 'stream_retry', 'step'].includes(kind)).map(([kind, value], i) => ({ id: previous.length + i + 71, task_id: task, kind, data: value, created_at: 1001 + i }))];
    this.histories.set(session, { messages, generating: false, outcome: { status: 'completed' } });
    if (this.pauseSend) await this.pauseSend;
    if (this.disconnectSend) return route.abort('failed');
    const chunks = data.map(([kind, value], i) => `event: ${kind}\r\ndata: ${JSON.stringify({ session_id: session, task_id: task, seq: i + 1, kind, data: value })}\r\n\r\n`);
    let bytes = 0;
    const boundaries = chunks.map(chunk => bytes += Buffer.byteLength(chunk));
    const streamHeaders = { ...headers, 'x-fixture-admission-bytes': String(boundaries[0]), 'x-fixture-event-boundaries': JSON.stringify(boundaries) };
    if (this.disconnectStreamAfter !== undefined) streamHeaders['x-fixture-disconnect-after'] = String(this.disconnectStreamAfter);
    return route.fulfill({ headers: streamHeaders, contentType: 'text/event-stream', body: chunks.join('') });
  }

  async goto() {
    await this.page.goto(`${authOrigin}/console/index.html?device=device-a`);
    const dismiss = this.page.getByRole('button', { name: 'Not now', exact: true });
    const hasCookie = (await this.page.context().cookies(authOrigin)).some(cookie => cookie.name === 'session');
    if (!this.device.hostSettings.has_deepseek_key && (this.desktop || this.accountSignedIn || this.meStatus === 200 || hasCookie)) {
      await expect(dismiss).toBeVisible();
      await dismiss.click();
    } else {
      await expect(dismiss).toHaveCount(0);
    }
    await this.page.getByRole('button', { name: 'Chat', exact: true }).click();
    if (this.cached) await this.row(sessionA).waitFor();
  }

  row(id) {
    return this.page.locator(`[id="conversation:cloud.live:${this.userId}:${id}::open"]`);
  }

  async open(id = sessionA) {
    await this.row(id).click();
    await expect(this.row(id)).toHaveAttribute('aria-current', 'true');
    await expect(this.page.locator('main .topbar-title')).toHaveText(this.titles.get(id) || 'New chat');
    await this.page.locator('#task').waitFor();
  }

  async create() {
    await this.page.locator('.section-primary-action[aria-label="New chat"]').click();
    await this.row(sessionC).waitFor();
    await this.page.waitForFunction(() => document.querySelector('.conversation-open[aria-current="true"]')?.textContent.includes('New chat'));
    await this.page.locator('#task').waitFor();
  }

}

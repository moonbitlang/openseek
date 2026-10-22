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
    this.exportStatus = 200;
    this.exportSnapshots = new Map();
    this.exportOffline = false;
    this.deleteStatus = 204;
    this.patchStatus = 204;
    this.patchOffline = false;
    this.pausePatch = null;
    this.deleteOffline = false;
    this.pauseDelete = null;
    this.disconnectShare = false;
    this.logoutStatus = 204;
    this.apiOffline = false;
    this.listOffline = false;
    this.disconnectSend = false;
    this.rejectStreamCancel = false;
    this.streamCancellations = 0;
    this.fileStreamCancellations = 0;
    this.sessionStreamCancellations = 0;
    this.sessionEventStatus = 200;
    this.pauseSessionEvents = null;
    this.controlSnapshots = new Map();
    this.manualTasks = false;
    this.pauseControl = null;
    this.controlRejected = null;
    this.controlOffline = false;
    this.fileEventStatus = 200;
    this.pauseCreate = null;
    this.pauseSend = null;
    this.pauseHistory = null;
    this.pauseStream = null;
    this.sessionIds = [sessionA, sessionB];
    this.generating = new Set();
    this.archived = new Set();
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
    await this.page.exposeFunction('cloudFileStreamCancelled', () => this.fileStreamCancellations++);
    await this.page.exposeFunction('cloudSessionStreamCancelled', () => { this.sessionStreamCancellations++; this.streamCancellations++; });
    await this.page.addInitScript(({ cached, authOrigin, cloudOrigin, rejectStreamCancel, streamChunkSize }) => {
      window.cloudUnhandledRejections = [];
      window.addEventListener('unhandledrejection', event => window.cloudUnhandledRejections.push(String(event.reason)));
      const key = 'seekmoon.cloud.token.v1';
      if (cached && !sessionStorage.getItem('fixture-cloud-seeded')) {
        sessionStorage.setItem('fixture-cloud-seeded', 'true');
        localStorage.setItem(key, JSON.stringify({ auth_origin: authOrigin, cloud_origin: cloudOrigin, user_id: '123', token: 'legacy-cloud-token' }));
        localStorage.setItem('seekmoon.account.v1', JSON.stringify({ token: 'ts_fixture-123', user: { user_id: '123', login: 'octocat', avatar_url: '' } }));
      }
      const original = window.fetch;
      window.cloudSessionStreams = new Map();
      window.cloudSessionEvent = (session, frame) => {
        for (const controller of window.cloudSessionStreams.get(session) || []) {
          controller.enqueue(new TextEncoder().encode(frame));
        }
      };
      window.cloudFileStreams = new Map();
      window.cloudInvalidateFiles = session => {
        for (const controller of window.cloudFileStreams.get(session) || []) {
          controller.enqueue(new TextEncoder().encode('event: workspace_invalidated\ndata: {}\n\n'));
        }
      };
      window.cloudCloseFileEvents = session => {
        for (const controller of window.cloudFileStreams.get(session) || []) controller.close();
        window.cloudFileStreams.delete(session);
      };
      window.fetch = async (...args) => {
        const response = await original(...args);
        const sessionEvents = String(args[0]).match(/\/v1\/sessions\/([^/]+)\/events$/);
        if (String(args[0]).startsWith(cloudOrigin) && sessionEvents && response.ok) {
          const initial = new TextEncoder().encode(await response.text());
          const session = decodeURIComponent(sessionEvents[1]);
          let current;
          return new Response(new ReadableStream({ start(controller) {
            current = controller;
            const streams = window.cloudSessionStreams.get(session) || new Set();
            streams.add(controller);
            window.cloudSessionStreams.set(session, streams);
            controller.enqueue(initial);
          }, cancel() {
            window.cloudSessionStreams.get(session)?.delete(current);
            window.cloudSessionStreamCancelled();
            if (rejectStreamCancel) return Promise.reject(new Error('Fixture cancellation rejected'));
          } }), { status: response.status, headers: response.headers });
        }
        const fileEvents = String(args[0]).match(/\/v1\/sessions\/([^/]+)\/files\/events$/);
        if (String(args[0]).startsWith(cloudOrigin) && fileEvents && response.ok) {
          const initial = new TextEncoder().encode(await response.text());
          const session = decodeURIComponent(fileEvents[1]);
          let current;
          return new Response(new ReadableStream({ start(controller) {
            current = controller;
            const streams = window.cloudFileStreams.get(session) || new Set();
            streams.add(controller);
            window.cloudFileStreams.set(session, streams);
            controller.enqueue(initial);
          }, cancel() {
            window.cloudFileStreams.get(session)?.delete(current);
            window.cloudFileStreamCancelled();
          } }), { status: response.status, headers: response.headers });
        }
        if (String(args[0]).startsWith(cloudOrigin) && response.headers.get('content-type')?.startsWith('text/event-stream')) {
          const bytes = new TextEncoder().encode(await response.text());
          let cancelled = false;
          return new Response(new ReadableStream({ async start(controller) {
            // Default to byte-sized chunks to split UTF-8 and SSE fields.
            // Large fixtures can use normal network-sized chunks.
            const boundary = response.headers.get('x-fixture-admission-bytes');
            const boundaries = JSON.parse(response.headers.get('x-fixture-event-boundaries') || '[]');
            const disconnectAfter = response.headers.get('x-fixture-disconnect-after');
            let eventIndex = 0;
            for (let i = 0; i < bytes.length;) {
              if (cancelled) return;
              const end = [Number(boundary), boundaries[eventIndex]]
                .filter(value => value > i)
                .reduce((end, value) => Math.min(end, value), Math.min(bytes.length, i + streamChunkSize));
              controller.enqueue(bytes.slice(i, end));
              i = end;
              if (i === Number(boundary)) await window.cloudWaitForStream();
              if (i === boundaries[eventIndex]) {
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
    }, { cached: this.cached, authOrigin, cloudOrigin, rejectStreamCancel: this.rejectStreamCancel, streamChunkSize: this.streamChunkSize ?? 1 });
    await this.page.route(`${authOrigin}/console/**`, async route => {
      const path = new URL(route.request().url()).pathname.replace(/^\/console\/(?:releases\/v[^/]+\/)?/, '') || 'index.html';
      const contentType = path.endsWith('.js') ? 'text/javascript' : path.endsWith('.css') ? 'text/css' : path.endsWith('.html') ? 'text/html' : 'application/octet-stream';
      await route.fulfill({ contentType, body: await readFile(new URL(path, bundle)) });
    });
    await this.page.route(`${authOrigin}/assets/**`, async route => {
      const path = new URL(route.request().url()).pathname.slice(1);
      const contentType = path.endsWith('.js') || path.endsWith('.mjs') ? 'text/javascript' : path.endsWith('.css') ? 'text/css' : path.endsWith('.html') ? 'text/html' : 'application/octet-stream';
      await route.fulfill({ contentType, body: await readFile(new URL(path, bundle)) });
    });
    await this.page.route(url => url.origin === authOrigin && (url.pathname.startsWith('/device/') || url.pathname === '/cloud' || url.pathname.startsWith('/cloud/')), async route => {
      if (!route.request().isNavigationRequest()) return route.continue();
      const html = await readFile(new URL('index.html', bundle), 'utf8');
      await route.fulfill({ contentType: 'text/html', body: html });
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
          if (method === 'host.connect') for (const callback of listeners.get('openseek.agent.connected') || []) callback({ payload: { protocol: 1 } });
          return window.cloudHostRequest({ method, params });
        } }),
      };
    });
  }

  async cloudRequest(route) {
    const request = route.request();
    const path = new URL(request.url()).pathname;
    const headers = { 'Access-Control-Allow-Origin': authOrigin, 'Access-Control-Allow-Headers': 'Authorization, Content-Type', 'Access-Control-Allow-Methods': 'GET, POST, PATCH, DELETE, OPTIONS', 'Access-Control-Expose-Headers': 'x-fixture-admission-bytes, x-fixture-event-boundaries, x-fixture-disconnect-after' };
    if (request.method() === 'OPTIONS') return route.fulfill({ status: 204, headers });
    this.requests.push({ side: 'cloud', path, method: request.method(), body: request.postData(), headers: await request.allHeaders() });
    const json = (data, status = 200) => route.fulfill({ status, headers, contentType: 'application/json', body: JSON.stringify(data) });
    if (/^\/v1\/sessions\/[^/]+\/files\/events$/.test(path)) {
      return route.fulfill({ status: this.fileEventStatus, headers, contentType: 'text/event-stream', body: 'event: workspace_invalidated\ndata: {}\n\n' });
    }
    const control = path.match(/^\/v1\/sessions\/([^/]+)\/(control|events|stop|steer|queue)$/);
    if (control) {
      const session = decodeURIComponent(control[1]);
      const operation = control[2];
      const snapshot = this.controlState(session);
      if (operation === 'control') return json(snapshot);
      if (operation === 'events') {
        if (this.pauseSessionEvents) await this.pauseSessionEvents;
        return route.fulfill({ status: this.sessionEventStatus, headers, contentType: 'text/event-stream', body: this.sseFrame('control_state', this.controlState(session)) });
      }
      const body = request.postDataJSON();
      if (this.pauseControl) await this.pauseControl;
      if (this.controlOffline) return route.abort('failed');
      const current = this.controlState(session);
      const idleQueueEdit = operation === 'queue' && ['edit', 'withdraw'].includes(body.action)
        && current.data.status === 'idle' && current.data.paused;
      const rejected = this.controlRejected
        || (current.task_id !== body.task_id ? 'task_mismatch' : null)
        || (!current.data.active_task_id && !idleQueueEdit ? 'task_not_running' : null)
        || (operation !== 'stop' && current.data.status === 'stopping' ? 'task_stopping' : null);
      if (rejected) return json({ accepted: false, error: rejected, task_id: body.task_id }, 409);
      if (operation === 'stop') {
        await this.publishControl(session, { status: 'stopping' });
        return json({ accepted: true, task_id: body.task_id }, 202);
      }
      if (operation === 'steer') {
        if (!current.data.steers.some(item => item.submission_id === body.submission_id)) {
          await this.publishControl(session, { steers: [...current.data.steers, { submission_id: body.submission_id, status: 'pending' }] });
        }
        return json({ accepted: true, task_id: body.task_id, submission_id: body.submission_id }, 202);
      }
      const index = current.data.queue.findIndex(item => item.id === body.id);
      if (body.action !== 'add' && index < 0) return json({ accepted: false, error: 'queue_item_missing', task_id: body.task_id }, 409);
      const queue = current.data.queue.slice();
      const steers = current.data.steers.slice();
      if (body.action === 'add') {
        if (index < 0) queue.push({ id: body.id, content: body.content });
        else if (JSON.stringify(queue[index].content) !== JSON.stringify(body.content)) return json({ accepted: false, error: 'input_id_conflict', task_id: body.task_id }, 409);
      } else if (body.action === 'edit') queue[index] = { id: body.id, content: body.content };
      else {
        queue.splice(index, 1);
        if (body.action === 'steer') steers.push({ submission_id: body.id, status: 'pending' });
      }
      await this.publishControl(session, { queue, steers });
      return json({ accepted: true, task_id: body.task_id, action: body.action, id: body.id });
    }
    if (path === '/v1/sessions') {
      if (request.method() === 'POST') {
        const finish = this.pauseCreate;
        if (finish) await finish;
        if (this.createStatus !== 201) return json({}, this.createStatus);
        this.sessionIds = [sessionC, ...this.sessionIds.filter(id => id !== sessionC)];
        return json({ id: sessionC }, 201);
      }
      if (this.listOffline) return route.abort('failed');
      if (this.pauseList) await this.pauseList;
      const status = this.listStatus;
      if (status === 401) this.listStatus = 200;
      return json({ sessions: this.sessionIds.map(id => ({ id, title: this.titles.get(id) ?? null, updated_at: 1000, generating: this.generating.has(id), archived: this.archived.has(id) })) }, status);
    }
    if (request.method() === 'PATCH' && /^\/v1\/sessions\/[^/]+$/.test(path)) {
      const body = request.postDataJSON();
      const session = decodeURIComponent(path.split('/').pop());
      if (this.pausePatch) await this.pausePatch;
      if (this.patchOffline) return route.abort('failed');
      if (this.patchStatus !== 204) return json({}, this.patchStatus);
      if (body.title !== undefined) this.titles.set(session, body.title);
      if (body.archived === true) this.archived.add(session);
      if (body.archived === false) this.archived.delete(session);
      return route.fulfill({ status: 204, headers });
    }
    if (request.method() === 'DELETE' && /^\/v1\/sessions\/[^/]+$/.test(path)) {
      if (this.pauseDelete) await this.pauseDelete;
      if (this.deleteOffline) return route.abort('failed');
      if (![204, 404].includes(this.deleteStatus)) return json({}, this.deleteStatus);
      const session = decodeURIComponent(path.split('/').pop());
      this.sessionIds = this.sessionIds.filter(id => id !== session);
      this.histories.delete(session);
      return route.fulfill({ status: this.deleteStatus, headers });
    }
    if (/^\/v1\/sessions\/[^/]+\/export$/.test(path)) {
      if (this.exportOffline) return route.abort('failed');
      const session = decodeURIComponent(path.split('/')[3]);
      return json(this.exportSnapshots.get(session), this.exportStatus);
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
    const text = typeof body.content === 'string' ? body.content : body.content.filter(part => part.type === 'text').map(part => part.text).join('');
    if (!this.titles.get(session) && text.trim()) this.titles.set(session, text.trim().split('\n')[0].trim());
    const task = `fixture-task-${++this.taskCount}`;
    const data = this.manualTasks ? [['task_started', {}]] : this.streamEvents || [
      ['task_started', {}],
      ['tool_call', { id: `calc-${task}`, name: 'mbtx', arguments: '{"source":"println(2)"}' }],
      ['tool_result', { tool_call_id: `calc-${task}`, tool_name: 'mbtx', content: '2', is_error: false }],
      ['assistant_message', { content: '您好 🌙 — calculation complete.' }],
      ['task_finished', { status: 'completed', result: { output: { answer: '您好 🌙 — calculation complete.' } } }],
    ];
    const previous = this.histories.get(session)?.messages || [];
    const messages = [...previous, { task_id: task, kind: 'user', data: { content: body.content }, created_at: 1000 }];
    this.histories.set(session, { messages, generating: true, outcome: null });
    if (this.pauseSend) await this.pauseSend;
    if (this.disconnectSend) return route.abort('failed');
    const chunks = data.map(([kind, value], i) => `event: ${kind}\r\ndata: ${JSON.stringify({ session_id: session, task_id: task, seq: i + 1, kind, data: value })}\r\n\r\n`);
    let bytes = 0;
    const boundaries = chunks.map(chunk => bytes += Buffer.byteLength(chunk));
    const streamHeaders = { ...headers, 'x-fixture-admission-bytes': String(boundaries[0]), 'x-fixture-event-boundaries': JSON.stringify(boundaries) };
    if (this.disconnectStreamAfter !== undefined) streamHeaders['x-fixture-disconnect-after'] = String(this.disconnectStreamAfter);
    await route.fulfill({ headers: streamHeaders, contentType: 'text/event-stream', body: chunks.join('') });
    // The session subscription is the source of live UI events. Keep the old
    // POST body realistic too, so consuming both streams would duplicate data.
    await this.publishTaskStream(session, task, data);
  }

  controlState(session) {
    return this.controlSnapshots.get(session) || {
      session_id: session, task_id: null, seq: 0,
      data: { active_task_id: null, status: 'idle', paused: false, queue: [], steers: [] },
    };
  }

  sseFrame(kind, value) {
    return `event: ${kind}\ndata: ${JSON.stringify(value)}\n\n`;
  }

  async disconnectSession(session, { error = false } = {}) {
    await this.page.evaluate(({ session, error }) => {
      for (const controller of window.cloudSessionStreams.get(session) || []) {
        if (error) controller.error(new Error('Fixture session stream disconnected'));
        else controller.close();
      }
      window.cloudSessionStreams.delete(session);
    }, { session, error });
  }

  async publishControl(session, change = {}, { kind = 'queue_changed' } = {}) {
    const old = this.controlState(session);
    const snapshot = { ...old, seq: old.seq + 1, kind, data: { ...old.data, ...change } };
    this.controlSnapshots.set(session, snapshot);
    await this.page.evaluate(({ session, frame }) => window.cloudSessionEvent(session, frame), { session, frame: this.sseFrame(kind, snapshot) });
    return snapshot;
  }

  async emitSessionEvent(session, kind, data, { task, seq, silent = false } = {}) {
    const old = this.controlState(session);
    task ??= old.task_id;
    const event = { session_id: session, task_id: task, seq: seq ?? old.seq + 1, kind, data };
    let queueAdvanced = false;
    if (kind === 'task_started') {
      const queued = old.data.queue.find(item => item.id === data.submission_id);
      if (queued) {
        queueAdvanced = true;
        const history = this.histories.get(session) || { messages: [] };
        this.histories.set(session, { ...history, generating: true, messages: [...history.messages, { task_id: task, kind: 'user', data: { content: queued.content }, created_at: 1010 }] });
      }
      this.generating.add(session);
      this.controlSnapshots.set(session, { session_id: session, task_id: task, seq: event.seq,
        data: { active_task_id: task, status: 'running', paused: false, queue: old.data.queue.filter(item => item.id !== data.submission_id), steers: [] } });
    } else if (task === old.task_id && event.seq > old.seq) {
      const state = { ...old.data };
      if (kind === 'task_finished') {
        this.generating.delete(session);
        state.active_task_id = null;
        state.status = 'idle';
        state.paused = old.data.paused || data.status !== 'completed' || old.data.status === 'stopping';
      }
      if (kind === 'steer_applied' || kind === 'steer_dropped') {
        state.steers = state.steers.filter(item => item.submission_id !== data.submission_id);
        state.steers.push({ submission_id: data.submission_id, status: kind === 'steer_applied' ? 'applied' : 'dropped' });
      }
      this.controlSnapshots.set(session, { ...old, seq: event.seq, data: state });
    }
    const history = this.histories.get(session) || { messages: [], generating: false };
    const transient = ['task_started', 'assistant_delta', 'reasoning_delta', 'reasoning_message', 'stream_retry', 'step', 'usage', 'compaction_started', 'compaction_finished', 'auto_compaction_started', 'auto_compaction_finished', 'steer_applied', 'steer_dropped'];
    if (!transient.includes(kind)) {
      this.histories.set(session, { ...history,
        messages: [...history.messages, { task_id: task, kind, data, created_at: 1000 + event.seq }],
        generating: kind !== 'task_finished', outcome: kind === 'task_finished' ? data : history.outcome });
    }
    if (!silent) {
      await this.page.evaluate(({ session, frame }) => window.cloudSessionEvent(session, frame), { session, frame: this.sseFrame(kind, event) });
      if (queueAdvanced) await this.publishControl(session);
    }
    return event;
  }

  async publishTaskStream(session, task, events) {
    for (let index = 0; index < events.length; index++) {
      const [kind, data] = events[index];
      await this.emitSessionEvent(session, kind, data, { task, seq: index + 1 });
      if (index === 0 && this.pauseStream) await this.pauseStream;
      if (this.eventPauses?.get(index)) await this.eventPauses.get(index);
      if (this.disconnectStreamAfter === index) {
        // The reader disconnects independently of the server task. Complete
        // this fixture's work so the history read sees the durable result.
        for (let remaining = index + 1; remaining < events.length; remaining++) {
          const [kind, data] = events[remaining];
          await this.emitSessionEvent(session, kind, data, { task, seq: remaining + 1, silent: true });
        }
        await this.page.evaluate(session => {
          for (const controller of window.cloudSessionStreams.get(session) || []) controller.error(new Error('Fixture stream disconnected'));
          window.cloudSessionStreams.delete(session);
        }, session);
        return;
      }
    }
  }

  async finishTask(session = sessionA, status = 'completed') {
    const snapshot = this.controlState(session);
    const task = snapshot.task_id;
    await this.publishControl(session, {
      active_task_id: null, status: 'idle',
      paused: status !== 'completed' || snapshot.data.status === 'stopping',
    });
    const result = { version: 1, request_id: task, session, status: status === 'completed' ? 'ok' : 'aborted', reason: status === 'completed' ? undefined : 'interrupted', usage: {}, steps: 1 };
    const data = { status, result };
    await this.emitSessionEvent(session, 'task_finished', data);
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
    if (this.cached && !this.archived.has(sessionA)) await this.row(sessionA).waitFor();
  }

  row(id) {
    return this.page.locator(`[id="conversation:cloud.live:${this.userId}:${id}::open"], [id="conversation:cloud.archived:${this.userId}:${id}::open"]`);
  }

  async open(id = sessionA) {
    await this.row(id).click();
    await expect(this.row(id)).toHaveAttribute('aria-current', 'true');
    await expect(this.page.locator('main .topbar-title')).toHaveText(this.titles.get(id) || 'New chat');
    await this.page.locator('#task').waitFor();
  }

  async create() {
    await this.page.locator('.section-primary-action[aria-label="New chat"]').click();
    await expect(this.page.locator('main .topbar-title')).toHaveText('New chat');
    await expect(this.page.locator('main [title="Export conversation"]')).toHaveCount(0);
    await expect(this.page.getByRole('button', { name: 'Model', exact: true })).toBeDisabled();
    await expect(this.page.locator('#task')).toBeEnabled();
  }

}

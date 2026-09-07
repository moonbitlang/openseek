// Throwaway host boundary. Reuse the existing fixture inventory and RPC
// responses; never assign frontend state, sidebar marks, or DOM contents.
import { DesktopBrowserHarness } from '../../e2e/tests/support/desktop_browser_harness.js';

const host = new DesktopBrowserHarness(null);
const openseek = new URLSearchParams(location.search).get('provider') === 'openseek';
host.liveSessions = openseek ? [{id:'replay-a', title:'Task A', updated_at_ms:2}, {id:'replay-b', title:'Task B', updated_at_ms:1}] : [];
let openRun = null;
let openApproval = null;
const outcomes = new Map();
const sessionEvents = id => [{sequence:1,item:{kind:'user',payload:{content: id === 'replay-a' ? 'Task A: run project checks.' : 'Task B: keep reading here while A runs.'}}}, ...(outcomes.has(id) ? [outcomes.get(id)] : [])];
const threads = [
  { id: 'replay-a', name: 'Task A', preview: 'Task A', cwd: '/workspace', projectRoot: '/workspace', updatedAt: 2, status: { type: 'idle' }, turns: [] },
  { id: 'replay-b', name: 'Task B', preview: 'Task B', cwd: '/workspace', projectRoot: '/workspace', updatedAt: 1, status: { type: 'idle' }, turns: [
    { id: 'turn-b', status: 'completed', items: [{ type: 'agentMessage', id: 'answer-b', text: 'You are reading Task B. Keep this conversation open while A waits for approval.' }] },
  ] },
];
let pending = [];
const originalReply = host.replyFor.bind(host);
host.replyFor = request => {
  switch (request.method) {
    case 'session.load': return {session:{version:1,id:request.params.session,events:sessionEvents(request.params.session)},watermark:sessionEvents(request.params.session).length};
    case 'agent.runs': return {runs:openRun ? [openRun] : [],settled:[],approvals:openApproval ? [openApproval] : []};
    case 'agent.approval': {
      const approval = openApproval;
      openApproval = null;
      if (approval) queueMicrotask(() => socket.receive({jsonrpc:'2.0',method:'agent.event',params:{run_id:'run-a',session:'replay-a',event:{event:'approval_resolved',id:approval.id,outcome:request.params.allow ? 'allowed' : 'denied'}}}));
      return {delivered:true};
    }
    case 'codex.server_request.list': return { data: pending, generation };
    case 'codex.server_request.respond': {
      pending = pending.filter(item => item.request_id !== request.params.request_id);
      threads[0].status = { type: 'active', activeFlags: [] };
      queueMicrotask(() => {
        socket.receive({ jsonrpc: '2.0', method: 'codex.notification', params: { method: 'serverRequest/resolved', params: { requestId: request.params.request_id }, generation: ++generation } });
        socket.receive({ jsonrpc: '2.0', method: 'codex.notification', params: { method: 'thread/status/changed', params: { threadId: threads[0].id, status: threads[0].status }, generation: ++generation } });
      });
      return {};
    }
    case 'codex.thread.list': return { data: openseek || request.params?.archived ? [] : threads };
    case 'codex.thread.history.read': {
      const thread = threads.find(t => t.id === request.params?.threadId);
      if (!thread) throw new Error('Unknown replay thread');
      return { thread };
    }
    default: return originalReply(request);
  }
};

const realFetch = globalThis.fetch.bind(globalThis);
globalThis.fetch = async (input, options) => {
  const url = new URL(typeof input === 'string' ? input : input.url, location.href);
  if (url.pathname === '/v1/auth/me') return Response.json({ login: 'Replay', avatar_url: '' });
  if (url.pathname === '/v1/devices') return Response.json({ devices: [{ id: 'device-a', name: 'Replay host', hostname: 'fixture', online: true }] });
  if (url.pathname.startsWith('/v1/')) throw new Error('Unmodeled replay request: ' + url.pathname);
  return realFetch(input, options);
};
let socket = null;
let generation = 1;
globalThis.WebSocket = class {
  constructor() {
    socket = this;
    this.readyState = 0;
    queueMicrotask(() => {
      this.readyState = 1;
      this.onopen?.({});
      this.receive({ jsonrpc: '2.0', method: 'agent.connected', params: { stage: 'serving' } });
    });
  }
  receive(value) { this.onmessage?.({ data: JSON.stringify(value) }); }
  send(text) {
    const request = JSON.parse(text);
    host.requests.push(request);
    if (request.id === undefined) return;
    queueMicrotask(() => {
      try {
        this.receive({ jsonrpc: '2.0', id: request.id, result: host.replyFor(request) });
      } catch (error) {
        this.receive({ jsonrpc: '2.0', id: request.id, error: { code: -32000, message: error.message } });
      }
    });
  }
  close() { this.readyState = 3; this.onclose?.({}); }
};
globalThis.__desktopReplay = {
  deliver(event) {
    if (!socket || socket.readyState !== 1) return false;
    if (openseek) {
      if (event.method === 'agent.started') openRun = event.params;
      if (event.method === 'agent.event') openApproval = {...event.params.event,session:'replay-a',run_id:'run-a'};
      if (event.method === 'agent.finished') {
        openRun = null; openApproval = null;
        const result = {sequence:2,item:{kind:'terminal',payload:{kind:event.params.status === 'finished' ? 'finished' : 'failed',message:event.params.answer}}};
        outcomes.set('replay-a',result);
        socket.receive({jsonrpc:'2.0',method:'session.event',params:{session:'replay-a',session_root:'/workspace/.openseek',sequence:2,event:result}});
      }
      socket.receive({jsonrpc:'2.0',...event});
      return true;
    }
    const thread = threads.find(t => t.id === event.params.threadId);
    if (!thread) return false;
    if (event.request_id !== undefined) {
      pending = [event];
      thread.status = { type: 'active', activeFlags: ['waitingOnApproval'] };
      socket.receive({ jsonrpc: '2.0', method: 'codex.server_request', params: { ...event, generation: ++generation } });
      socket.receive({ jsonrpc: '2.0', method: 'codex.notification', params: { method: 'thread/status/changed', params: { threadId: thread.id, status: thread.status }, generation: ++generation } });
      return true;
    }
    if (event.method === 'turn/completed') {
      for (const request of pending) socket.receive({ jsonrpc: '2.0', method: 'codex.notification', params: { method: 'serverRequest/resolved', params: { requestId: request.request_id }, generation: ++generation } });
      pending = [];
    }
    thread.turns = [event.params.turn];
    thread.status = { type: event.params.turn.status === 'inProgress' ? 'active' : 'idle' };
    socket.receive({ jsonrpc: '2.0', method: 'codex.notification', params: { ...event, generation: ++generation } });
    socket.receive({ jsonrpc: '2.0', method: 'codex.notification', params: { method: 'thread/status/changed', params: { threadId: thread.id, status: thread.status }, generation: ++generation } });
    return true;
  },
};

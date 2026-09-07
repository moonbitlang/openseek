// Synthetic host protocol, real frontend decoders, updates and components.
import { DesktopBrowserHarness } from '../../e2e/tests/support/desktop_browser_harness.js';
const host = new DesktopBrowserHarness(null);
host.liveSessions = [{id:'replay-a',title:'Transcript review',updated_at_ms:2}];
let openRun = null;
let turn = 0;
let chunk = 0;
const log = [];
const answer = `The transcript now keeps each prompt close to its response. The end line shares the existing copy-action row.

### What changed

- Removed the separator between the prompt and answer.
- Kept the assistant text unboxed so longer explanations have room.
- Left more space before the next user prompt.

\`\`\`css
.assistant-message-actions::after {
  content: "";
  height: 1px;
  flex: 1;
}
\`\`\`

| State | Expected ending |
| --- | --- |
| Streaming | No copy action or end line yet |
| Final answer | Copy action and a quiet line |
| Failure | An error with useful recovery information |

This is a simulated design review, not evidence that project checks passed. Try the narrow viewport to inspect code scrolling and table wrapping.`;
const events = [];
const historyStart = Date.now() - 10 * 60 * 1000;
function record(kind,payload,ts=Date.now()){const row={sequence:events.length+1,ts,item:{kind,payload}};events.push(row);return row;}
record('user',{content:'Could you make the conversation easier to scan without adding more cards?'},historyStart + 0);
record('terminal',{kind:'finished',message:'Yes. I would keep each prompt and answer together, then mark the end of the exchange with a thin line beside the copy action.'},historyStart + 120000);
record('user',{content:'Show me how that works with a longer explanation, code, and a table.'},historyStart + 240000);
record('terminal',{kind:'finished',message:answer},historyStart + 360000);
const originalReply=host.replyFor.bind(host);
host.replyFor=request=>{
  switch(request.method){
    case 'session.load':return {session:{version:1,id:'replay-a',events},watermark:events.length};
    case 'agent.runs':return {runs:openRun?[openRun]:[],settled:[],approvals:[]};
    case 'codex.thread.list':return {data:[]};
    default:return originalReply(request);
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

function send(method,params){log.push({method,params});socket.receive({jsonrpc:'2.0',method,params});}
function commit(kind,payload){const row=record(kind,payload);send('session.event',{session:'replay-a',session_root:'/workspace/.openseek',sequence:row.sequence,event:row});}
function engine(event){send('agent.event',{run_id:openRun.run_id,session:'replay-a',event});}
globalThis.__desktopReplay = {
  act(action){
    if(!socket || socket.readyState!==1)return 'Wait for the host connection, then retry.';
    if(action==='start'){
      turn++;chunk=0;
      commit('user',{content:turn===1?'Inspect the stylesheet and check whether this holds up in a narrow panel.':'Try that check again and explain anything that remains uncertain.'});
      openRun={run_id:'run-'+turn,session:'replay-a',session_root:'/workspace/.openseek',model:'deepseek-v4-pro',max_steps:1000};
      send('agent.started',openRun);
      engine({event:'agent_step',step:1});
    }else if(action==='tool'){
      commit('assistant',{content:'I’ll inspect the transcript styles before checking the layout.',tool_calls:[{id:'read-'+turn,name:'read',arguments:JSON.stringify({path:'desktop/styles/transcript.css'})}]});
      commit('tool_result',{tool_call_id:'read-'+turn,tool_name:'read',content:'.stream { gap: 14px; }\n.assistant-message-actions { display: flex; }',brief:'Read transcript.css',is_error:false});
      engine({event:'agent_step',step:2});
    }else if(action==='stream'){
      const chunks=['The prompt and answer remain grouped. ', 'The code block should scroll within the message, while ordinary prose wraps. ', '\n\nThe ending is still provisional while this response is streaming.'];
      engine({event:'assistant_delta',content:chunks[chunk%chunks.length]});chunk++;
    }else if(action==='finish'||action==='fail'){
      const success=action==='finish';
      const message=success?'The layout review is ready. The code and table above are available for inspection.\n\n**Still to check:** dark theme and a real long-running conversation. These fixture events did not execute a command.':'Could not read `desktop/styles/transcript.css`: permission denied. The layout check did not run. Check file access and retry; earlier messages remain available.';
      commit('terminal',{kind:success?'finished':'failed',message});
      send('agent.finished',{run_id:openRun.run_id,status:success?'finished':'failed',answer:message});openRun=null;
    }
    return JSON.stringify(log,null,2);
  }
};

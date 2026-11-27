import path from 'node:path';

/// Build the document `/api/trajectory/<root>` serves, from the compact fixture
/// shape a test wants to read: absolute milliseconds, and only the fields that
/// case is about. Everything the viewer needs but the test does not state
/// (span ids, the stats block) is filled in here.
export function traceDocument({
  rootId = 'viz-1',
  t0 = 0,
  tEnd = 10_000,
  live = false,
  sessions = [],
  spans = [],
  stats = {},
} = {}) {
  const lanes = sessions.length > 0
    ? sessions
    : [{ session_id: rootId, title: 'main', depth: 0, start: t0 }];
  const build = span => ({
    id: span.id,
    session_id: span.session_id ?? rootId,
    title: span.title ?? 'main',
    depth: span.depth ?? 0,
    kind: span.kind,
    status: span.status ?? 'succeeded',
    label: span.label ?? span.kind,
    started_at_ms: span.start,
    ...(span.end === undefined ? {} : { ended_at_ms: span.end }),
    ...(span.parent === undefined ? {} : { parent_id: span.parent }),
    ...(span.job === undefined ? {} : { job_id: span.job }),
    ...(span.jobs === undefined ? {} : { job_ids: span.jobs }),
    ...(span.tag === undefined ? {} : { tag: span.tag }),
    ...(span.sequence === undefined ? {} : { sequence: span.sequence }),
    metadata: span.metadata ?? {},
  });
  const sum = kind => spans
    .filter(span => span.kind === kind && span.end !== undefined)
    .reduce((ms, span) => ms + (span.end - span.start), 0);
  const totals = (kind, key) => ({ [key]: sum(kind) });
  return {
    root_session_id: rootId,
    t0_ms: t0,
    t_end_ms: tEnd,
    live,
    sessions: lanes.map(lane => ({
      session_id: lane.session_id,
      title: lane.title ?? 'main',
      depth: lane.depth ?? 0,
      started_at_ms: lane.start,
      ...(lane.end === undefined ? {} : { ended_at_ms: lane.end }),
      ...(lane.parent === undefined ? {} : { parent_session_id: lane.parent }),
    })),
    spans: spans.map(build),
    stats: {
      wall_ms: Math.max(0, tEnd - t0),
      ...totals('llm', 'llm_ms'),
      ...totals('tool', 'tool_ms'),
      ...totals('wait', 'wait_ms'),
      ...totals('job', 'job_ms'),
      prompt_tokens: 0,
      completion_tokens: 0,
      critical_path_ms: 0,
      critical_path: [],
      span_count: spans.length,
      turn_count: spans.filter(span => span.kind === 'turn').length,
      session_count: lanes.length,
      ...stats,
    },
  };
}

export class VizBrowserHarness {
  constructor(page) {
    this.page = page;
    this.pageErrors = [];
    this.apiRequests = [];
    // Every `/api/...` path the page actually requested. A baked export must
    // leave this empty: it answers from its own document.
    this.apiCalls = [];
    this.sessionId = 'viz-1';
    this.extraSessionRows = [];
    this.childEvents = new Map();
    // The trace `/api/trajectory/<root>` serves; `null` answers 404, which is
    // what a session with no sub-runs and no spans looks like.
    this.trajectory = null;
    // The cursor the server would put in the document. When set, a poll that
    // sends it back gets `unchanged`, like the real route.
    this.trajectoryCursor = null;
    this.trajectoryRequests = [];
    // Background jobs the server would answer for, keyed `<session>/<job>`:
    // the record plus a page of the file the job wrote. A missing key is a
    // session with no such record.
    this.jobLogs = new Map();
    // Every job request the page made, path and query included, so a test can
    // see which job was asked for and from which cursor.
    this.jobRequests = [];
    this.events = [
      JSON.stringify({
        version: 1,
        id: 'viz-1',
        system_prompt: 'You are a browser fixture.',
      }),
      JSON.stringify({
        sequence: 1,
        ts: 1_000,
        item: {
          kind: 'user',
          payload: { content: 'Inspect the session viewer' },
        },
      }),
      JSON.stringify({
        sequence: 2,
        ts: 2_000,
        item: {
          kind: 'assistant',
          payload: {
            content: 'Running the browser fixture.',
            tool_calls: [
              {
                id: 'shell-1',
                name: 'shell',
                arguments: JSON.stringify({ cmd: 'moon test', escalated: true }),
              },
            ],
          },
        },
      }),
      JSON.stringify({
        sequence: 3,
        ts: 3_000,
        item: {
          kind: 'tool_result',
          payload: {
            tool_call_id: 'shell-1',
            tool_name: 'shell',
            content: 'fixture failure',
            is_error: true,
            brief: 'tests failed',
          },
        },
      }),
      JSON.stringify({
        sequence: 4,
        ts: 4_000,
        item: {
          kind: 'assistant',
          payload: {
            content: '',
            tool_calls: [
              {
                id: 'mbtx-build',
                name: 'mbtx',
                arguments: JSON.stringify({ source: 'fn main { compile_error }', description: 'Check <compiler> diagnostics' }),
              },
              {
                id: 'mbtx-run',
                name: 'mbtx',
                arguments: JSON.stringify({ source: 'fn main { abort("runtime") }' }),
              },
            ],
          },
        },
      }),
      JSON.stringify({
        sequence: 5,
        ts: 5_000,
        item: {
          kind: 'tool_result',
          payload: {
            tool_call_id: 'mbtx-build',
            tool_name: 'mbtx',
            content: 'type mismatch',
            is_error: true,
            brief: 'mbtx build',
          },
        },
      }),
      JSON.stringify({
        sequence: 6,
        ts: 6_000,
        item: {
          kind: 'tool_result',
          payload: {
            tool_call_id: 'mbtx-run',
            tool_name: 'mbtx',
            content: 'runtime trap',
            is_error: true,
            brief: 'mbtx run',
          },
        },
      }),
      JSON.stringify({
        sequence: 7,
        ts: 7_000,
        item: {
          kind: 'terminal',
          payload: { kind: 'failed', message: 'Browser fixture completed.' },
        },
      }),
    ].join('\n') + '\n';
  }

  sessionRows() {
    return [
      {
        key: this.sessionId,
        id: this.sessionId,
        root_label: '/workspace/.openseek',
        is_marker: true,
        last_active: 1,
        first_prompt: 'Inspect the session viewer',
      },
      ...this.extraSessionRows,
    ];
  }

  eventLog(items, { id = 'viz-1', systemPrompt = 'You are a browser fixture.' } = {}) {
    // Build the same newline-delimited file the server streams. Keeping this
    // on the harness makes custom edge cases readable without inventing a
    // second parser or a test-only model representation.
    return [
      JSON.stringify({ version: 1, id, system_prompt: systemPrompt }),
      // The durable wire always carries `ts`; zero is its legacy spelling for
      // an unstamped event. Make omission in a test case mean that exact wire
      // value instead of producing an invalid JSONL line.
      ...items.map(item => JSON.stringify({ ts: 0, ...item })),
    ].join('\n') + '\n';
  }

  sessionEnvelope(id = this.sessionId) {
    if (this.childEvents.has(id)) {
      const events = this.childEvents.get(id);
      return { found: true, events, events_bytes: events.length };
    }
    if (id !== this.sessionId) {
      return { found: false, events: '', events_bytes: 0 };
    }
    return {
      found: true,
      events: this.events,
      events_bytes: this.events.length,
    };
  }

  async install({ standalone = false, watchMs = 0, artifacts = {} } = {}) {
    this.page.on('pageerror', error => this.pageErrors.push(error.message));
    if (watchMs > 0) {
      // What `inspect --watch` injects into the shell it serves.
      await this.page.addInitScript(ms => {
        window.__OPENSEEK_WATCH_MS__ = ms;
      }, watchMs);
    }
    this.page.on('request', request => {
      const pathname = new URL(request.url()).pathname;
      if (pathname.startsWith('/api/')) {
        this.apiCalls.push(pathname);
      }
      if (pathname.startsWith('/api/sessions')) {
        this.apiRequests.push(request.url());
      }
    });
    if (standalone) {
      await this.page.addInitScript(data => {
        window.__OPENSEEK_DATA__ = data;
      }, {
        '/api/sessions': JSON.stringify(this.sessionRows()),
        [`/api/sessions/${this.sessionId}`]: JSON.stringify(this.sessionEnvelope()),
        // `inspect --export` bakes one trajectory document per run it holds;
        // a harness run stands in for the root the page was opened at.
        ...(this.trajectory === null
          ? {}
          : { [`/api/trajectory/${this.sessionId}`]: JSON.stringify(this.trajectory) }),
        ...artifacts,
      });
    }
    await this.page.route('**/viz_app.js', route => route.fulfill({
      contentType: 'text/javascript',
      path: path.resolve(
        '../../..',
        '_build/js/debug/build/moonbitlang/openseek-viz-app/openseek-viz-app.js',
      ),
    }));
    if (standalone) {
      return;
    }
    await this.page.route('**/api/trajectory/**', route => {
      const url = new URL(route.request().url());
      this.trajectoryRequests.push(url.pathname + url.search);
      const cursor = url.searchParams.get('cursor');
      if (cursor && cursor === this.trajectoryCursor) {
        return route.fulfill({
          contentType: 'application/json',
          body: JSON.stringify({ unchanged: true, cursor }),
        });
      }
      if (this.trajectory === null) {
        return route.fulfill({ status: 404, contentType: 'text/plain', body: 'not found' });
      }
      const document = typeof this.trajectory === 'string'
        ? this.trajectory
        : JSON.stringify({
            ...this.trajectory,
            ...(this.trajectoryCursor ? { cursor: this.trajectoryCursor } : {}),
          });
      return route.fulfill({
        contentType: 'application/json',
        body: document,
      });
    });
    await this.page.route('**/api/sessions**', route => {
      const url = new URL(route.request().url());
      if (url.pathname === '/api/sessions') {
        return route.fulfill({
          contentType: 'application/json',
          body: JSON.stringify(this.sessionRows()),
        });
      }
      const id = decodeURIComponent(url.pathname.slice('/api/sessions/'.length));
      const envelope = this.sessionEnvelope(id);
      // Like the server: a watch poll for a log that has not grown gets the
      // cheap `unchanged` reply instead of the whole log.
      const known = url.searchParams.get('known_bytes');
      const body = envelope.found && known === String(envelope.events_bytes)
        ? { found: true, unchanged: true, events_bytes: envelope.events_bytes }
        : envelope;
      return route.fulfill({
        contentType: 'application/json',
        body: JSON.stringify(body),
      });
    });
    await this.page.route('**/api/sessions/*/jobs/**', route => {
      const url = new URL(route.request().url());
      this.jobRequests.push(url.pathname + url.search);
      const match = url.pathname.match(/\/api\/sessions\/([^/]+)\/jobs\/([^/]+)$/);
      const key = match === null
        ? ''
        : `${decodeURIComponent(match[1])}/${decodeURIComponent(match[2])}`;
      const stored = this.jobLogs.get(key);
      // A function answers per request, which is how a test follows a running
      // job page by page.
      const body = typeof stored === 'function' ? stored(url) : stored;
      if (body === undefined) {
        return route.fulfill({
          contentType: 'application/json',
          body: JSON.stringify({
            found: false,
            error: `no saved record for job ${key}`,
          }),
        });
      }
      return route.fulfill({
        contentType: 'application/json',
        body: JSON.stringify(body),
      });
    });
  }

  async goto(hash = '') {
    await this.page.goto(`/web/index.html${hash}`);
    await this.page.getByRole('heading', { name: 'OpenSeek sessions' }).waitFor();
  }

  async openSession() {
    await this.page.locator('.session-item', {
      hasText: 'Inspect the session viewer',
    }).click();
    await this.page.locator('.header-id', { hasText: this.sessionId }).waitFor();
  }
}

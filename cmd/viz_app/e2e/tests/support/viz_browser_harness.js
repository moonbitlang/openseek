import path from 'node:path';

export class VizBrowserHarness {
  constructor(page) {
    this.page = page;
    this.pageErrors = [];
    this.apiRequests = [];
    this.sessionId = 'viz-1';
    this.extraSessionRows = [];
    this.childEvents = new Map();
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
                arguments: JSON.stringify({ source: 'fn main { compile_error }' }),
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
            brief: 'mbtx (build failed, exit=1)',
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
            brief: 'mbtx (exit=1)',
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

  async install({ standalone = false } = {}) {
    this.page.on('pageerror', error => this.pageErrors.push(error.message));
    this.page.on('request', request => {
      if (new URL(request.url()).pathname.startsWith('/api/sessions')) {
        this.apiRequests.push(request.url());
      }
    });
    if (standalone) {
      await this.page.addInitScript(data => {
        window.__OPENSEEK_DATA__ = data;
      }, {
        '/api/sessions': JSON.stringify(this.sessionRows()),
        [`/api/sessions/${this.sessionId}`]: JSON.stringify(this.sessionEnvelope()),
      });
    }
    await this.page.route('**/viz_app.js', route => route.fulfill({
      contentType: 'text/javascript',
      path: path.resolve(
        '../../..',
        '_build/js/debug/build/bobzhang/openseek-viz-app/openseek-viz-app.js',
      ),
    }));
    if (standalone) {
      return;
    }
    await this.page.route('**/api/sessions**', route => {
      const url = new URL(route.request().url());
      if (url.pathname === '/api/sessions') {
        return route.fulfill({
          contentType: 'application/json',
          body: JSON.stringify(this.sessionRows()),
        });
      }
      const id = decodeURIComponent(url.pathname.slice('/api/sessions/'.length));
      return route.fulfill({
        contentType: 'application/json',
        body: JSON.stringify(this.sessionEnvelope(id)),
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

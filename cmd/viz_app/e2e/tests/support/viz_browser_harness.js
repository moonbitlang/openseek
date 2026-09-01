import path from 'node:path';

export class VizBrowserHarness {
  constructor(page) {
    this.page = page;
    this.pageErrors = [];
    this.apiRequests = [];
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
                id: 'plan-1',
                name: 'plan',
                arguments: JSON.stringify({
                  steps: [
                    { title: 'Inspect DOM', status: 'in_progress' },
                    { title: 'Run browser tests', status: 'pending' },
                  ],
                }),
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
            tool_call_id: 'plan-1',
            tool_name: 'plan',
            content: 'Plan accepted.',
            is_error: false,
          },
        },
      }),
      JSON.stringify({
        sequence: 6,
        ts: 6_000,
        item: {
          kind: 'assistant',
          payload: {
            content: '',
            tool_calls: [
              {
                id: 'plan-2',
                name: 'plan',
                arguments: JSON.stringify({
                  steps: [
                    { title: 'Inspect DOM', status: 'completed' },
                    { title: 'Run browser tests', status: 'in_progress' },
                    { title: 'Review layout', status: 'pending' },
                  ],
                }),
              },
            ],
          },
        },
      }),
      JSON.stringify({
        sequence: 7,
        ts: 7_000,
        item: {
          kind: 'tool_result',
          payload: {
            tool_call_id: 'plan-2',
            tool_name: 'plan',
            content: 'Plan updated.',
            is_error: false,
          },
        },
      }),
      JSON.stringify({
        sequence: 8,
        ts: 8_000,
        item: {
          kind: 'runtime_notice',
          payload: { content: '[goal]\nShip the Playwright migration' },
        },
      }),
      JSON.stringify({
        sequence: 9,
        ts: 9_000,
        item: {
          kind: 'runtime_notice',
          payload: { content: '[goal blocked]\nwaiting for fixture data' },
        },
      }),
      JSON.stringify({
        sequence: 10,
        ts: 10_000,
        item: {
          kind: 'runtime_notice',
          payload: { content: '[goal cleared]' },
        },
      }),
      JSON.stringify({
        sequence: 11,
        ts: 11_000,
        item: {
          kind: 'assistant',
          payload: {
            content: '',
            tool_calls: [
              {
                id: 'explore-1',
                name: 'explore',
                arguments: JSON.stringify({ query: 'find the renderer' }),
              },
            ],
          },
        },
      }),
      JSON.stringify({
        sequence: 12,
        ts: 12_000,
        item: {
          kind: 'tool_result',
          payload: {
            tool_call_id: 'explore-1',
            tool_name: 'explore',
            content: 'Answer: render it in Chromium.',
            is_error: false,
            brief: 'explore sr-2 (1 citation(s), 7 step(s))',
          },
        },
      }),
      JSON.stringify({
        sequence: 13,
        ts: 13_000,
        item: {
          kind: 'assistant',
          payload: {
            content: '',
            tool_calls: [
              {
                id: 'read-1',
                name: 'read',
                arguments: JSON.stringify({ path: 'src/main.mbt' }),
              },
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
              {
                id: 'mbtx-js',
                name: 'mbtx',
                arguments: JSON.stringify({
                  source: 'fn main { abort("single shot") }',
                  target: 'js',
                }),
              },
            ],
          },
        },
      }),
      JSON.stringify({
        sequence: 14,
        ts: 14_000,
        item: {
          kind: 'tool_result',
          payload: {
            tool_call_id: 'read-1',
            tool_name: 'read',
            content: [
              ' 9 |fn main {',
              '10 |  println("hi")',
              '11 |}',
              '<system>start_line=9 shown_lines=3 total_lines=20 truncated=false</system>',
            ].join('\n'),
            is_error: false,
            brief: 'read main.mbt (truncated)',
          },
        },
      }),
      JSON.stringify({
        sequence: 15,
        ts: 15_000,
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
        sequence: 16,
        ts: 16_000,
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
        sequence: 17,
        ts: 17_000,
        item: {
          kind: 'tool_result',
          payload: {
            tool_call_id: 'mbtx-js',
            tool_name: 'mbtx',
            content: 'single-shot diagnostic',
            is_error: true,
            brief: 'mbtx (exit=1)',
          },
        },
      }),
      JSON.stringify({
        sequence: 18,
        ts: 18_000,
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
        key: 'viz-1',
        id: 'viz-1',
        root_label: '/workspace/.openseek',
        is_marker: true,
        last_active: 1,
        first_prompt: 'Inspect the session viewer',
      },
    ];
  }

  sessionEnvelope() {
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
        '/api/sessions/viz-1': JSON.stringify(this.sessionEnvelope()),
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
      return route.fulfill({
        contentType: 'application/json',
        body: JSON.stringify(this.sessionEnvelope()),
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
    await this.page.locator('.header-id', { hasText: 'viz-1' }).waitFor();
  }
}

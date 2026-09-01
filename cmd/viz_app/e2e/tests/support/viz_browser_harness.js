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

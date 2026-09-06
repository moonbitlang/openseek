export class DesktopBrowserHarness {
  constructor(page) {
    this.page = page;
    this.socket = null;
    this.requests = [];
    this.pageErrors = [];
    // Error and delay controls let tests exercise the product's real pending,
    // failed, and retry states without replacing its Rabbita update logic.
    this.rpcErrors = new Map();
    this.rpcDelays = new Map();
    this.textSearchMatches = [];
    this.textSearchMatchCount = undefined;
    this.textSearchLimitHit = false;
    this.directoryEntries = {};
    this.workspaces = ['/workspace'];
    // Per-workspace settings the Workspace Settings page reads and patches,
    // mirroring the host's `.openseek/settings.json` store. Keyed by
    // workspace path so a second project can never inherit another's
    // snapshot or overwrite its identity.
    this.workspaceSettings = {
      '/workspace': {
        workspace: '/workspace',
        worktree_mode: false,
        checkout_submodules: false,
        submodule_checkout_timeout_seconds: 30,
      },
    };
    // Requests mutate the same fixture snapshots a real Desktop host would
    // return on the next list/read. That lets browser tests verify complete
    // UI -> RPC -> refreshed-DOM flows instead of stopping at button clicks.
    this.liveSessions = [
      {
        id: 'session-1',
        title: 'Rabbita browser fixture',
        updated_at_ms: 1,
      },
    ];
    this.archivedSessions = [];
    this.hostSettings = {
      revision: 1,
      provider: 'deepseek',
      custom_api_url: '',
      has_deepseek_key: true,
      has_glm_key: false,
      has_custom_key: false,
      followup_behavior: 'steer',
    };
    this.installedSkills = [
      {
        id: 'moonbit',
        name: 'MoonBit',
        description: 'Authoritative MoonBit guidance',
        source: '',
      },
    ];
    this.codexRequiresAuth = false;
    this.codexModels = [];
    // Review and Git Graph share these immutable commit identities. Keeping
    // the file snapshots beside the graph data makes every fixture response
    // describe one coherent repository instead of isolated RPC examples.
    this.gitBaseline = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    this.gitParent = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    this.gitHead = 'cccccccccccccccccccccccccccccccccccccccc';
    this.gitMerge = 'dddddddddddddddddddddddddddddddddddddddd';
    // Tests may replace this inventory together with workingFiles and the
    // baseline snapshot to exercise repository states that the default Review
    // flow does not contain. The RPC still returns ordinary product data.
    this.gitChanges = [
      {
        path: 'src/main.mbt',
        index_status: ' ',
        worktree_status: 'M',
        kind: 'modified',
      },
      {
        path: 'src/lib.mbt',
        index_status: 'M',
        worktree_status: ' ',
        kind: 'modified',
      },
    ];
    this.workingFiles = {
      'src/main.mbt': [
        'fn main {',
        '  println("working tree")',
        '}',
        '',
      ].join('\n'),
      'src/lib.mbt': [
        'pub fn answer() -> Int {',
        '  43',
        '}',
        '',
      ].join('\n'),
    };
    this.searchFiles = ['src/main.mbt', 'README.md'];
    // Transcript images use the same fs.read_file RPC as text files, but the
    // real host returns bytes plus a verified media type. Tests opt into that
    // response per path instead of bypassing the product image loader.
    this.binaryFiles = {};
    this.gitFilesByRevision = {
      [this.gitBaseline]: {
        'src/main.mbt': [
          'fn main {',
          '  println("baseline")',
          '}',
          '',
        ].join('\n'),
        'src/lib.mbt': [
          'pub fn answer() -> Int {',
          '  41',
          '}',
          '',
        ].join('\n'),
      },
      [this.gitParent]: {
        'src/main.mbt': [
          'fn main {',
          '  println("history parent")',
          '}',
          '',
        ].join('\n'),
        'src/lib.mbt': [
          'pub fn answer() -> Int {',
          '  42',
          '}',
          '',
        ].join('\n'),
      },
      [this.gitHead]: {
        'src/main.mbt': [
          'fn main {',
          '  println("history commit")',
          '}',
          '',
        ].join('\n'),
        'src/lib.mbt': [
          'pub fn answer() -> Int {',
          '  43',
          '}',
          '',
        ].join('\n'),
      },
      [this.gitMerge]: {
        'src/main.mbt': [
          'fn main {',
          '  println("history merge")',
          '}',
          '',
        ].join('\n'),
        'src/lib.mbt': [
          'pub fn answer() -> Int {',
          '  42',
          '}',
          '',
        ].join('\n'),
      },
    };
    this.sessionEvents = [
      {
        sequence: 1,
        item: {
          kind: 'user',
          payload: {
            content: 'Show the browser fixture at https://example.test/docs but keep `https://inside.example.test` inert.',
          },
        },
      },
      {
        sequence: 2,
        item: {
          kind: 'assistant',
          payload: {
            content: '# Browser result\n\nRendered **successfully** with `Rabbita 0.15`.',
          },
        },
      },
      {
        sequence: 3,
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
                    { title: 'Inspect DOM', status: 'completed' },
                    { title: 'Run Playwright', status: 'in_progress' },
                    { title: 'Review layout', status: 'pending' },
                  ],
                }),
              },
            ],
          },
        },
      },
      {
        sequence: 4,
        item: {
          kind: 'tool_result',
          payload: {
            tool_call_id: 'plan-1',
            tool_name: 'plan',
            content: 'Plan updated.',
            is_error: false,
            brief: 'plan 1/3',
          },
        },
      },
      {
        sequence: 5,
        item: {
          kind: 'runtime_notice',
          payload: { content: '[goal]\nShip Rabbita 0.15 browser tests' },
        },
      },
      {
        sequence: 6,
        item: {
          kind: 'assistant',
          payload: {
            content: '',
            tool_calls: [
              {
                id: 'mbtx-1',
                name: 'mbtx',
                arguments: JSON.stringify({ source: 'fn main { println(42) }' }),
              },
            ],
          },
        },
      },
      {
        sequence: 7,
        item: {
          kind: 'tool_result',
          payload: {
            tool_call_id: 'mbtx-1',
            tool_name: 'mbtx',
            content: '42',
            is_error: false,
            brief: 'completed',
          },
        },
      },
      {
        sequence: 8,
        item: {
          kind: 'assistant',
          payload: {
            content: '',
            tool_calls: [
              {
                id: 'shell-1',
                name: 'shell',
                arguments: JSON.stringify({
                  cmd: 'moon test',
                  options: { cwd: '/workspace', targets: ['js', 'native'] },
                }),
              },
            ],
          },
        },
      },
      {
        sequence: 9,
        item: {
          kind: 'tool_result',
          payload: {
            tool_call_id: 'shell-1',
            tool_name: 'shell',
            content: 'all targets passed',
            is_error: false,
            brief: 'tests passed',
          },
        },
      },
      {
        sequence: 10,
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
            ],
          },
        },
      },
      {
        sequence: 11,
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
      },
      {
        sequence: 12,
        item: {
          kind: 'assistant',
          payload: {
            content: '',
            tool_calls: [
              {
                id: 'review-1',
                name: 'review',
                arguments: JSON.stringify({ focus: 'find the API' }),
              },
            ],
          },
        },
      },
      {
        sequence: 13,
        item: {
          kind: 'tool_result',
          payload: {
            tool_call_id: 'review-1',
            tool_name: 'review',
            content: 'Answer: use the browser fixture.',
            is_error: false,
            brief: 'review sr-2 (2 finding(s), 7 step(s))',
          },
        },
      },
      {
        sequence: 14,
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
      },
      {
        sequence: 15,
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
      },
      {
        sequence: 16,
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
      },
      {
        sequence: 17,
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
      },
    ];
  }

  sessionGroups(sessions) {
    return {
      groups: [
        {
          workspace: '/workspace',
          name: 'Fixture',
          session_root: '/workspace/.openseek',
          sessions,
          error: '',
        },
      ],
    };
  }

  async install() {
    this.page.on('pageerror', error => this.pageErrors.push(error.message));

    await this.page.route('**/v1/auth/me', route => route.fulfill({
      contentType: 'application/json',
      body: JSON.stringify({ login: 'octocat', avatar_url: '' }),
    }));
    await this.page.route('**/v1/devices', route => route.fulfill({
      contentType: 'application/json',
      body: JSON.stringify({
        devices: [
          {
            id: 'device-a',
            name: 'Test Mac',
            hostname: 'test.local',
            online: true,
          },
        ],
      }),
    }));

    // The product browser bundle normally talks to a selected Desktop host.
    // This route replaces only that transport and leaves Rabbita, the views,
    // browser layout, DOM events, and focus behavior running unchanged.
    await this.page.routeWebSocket('**/v1/devices/device-a/ws', socket => {
      this.socket = socket;
      socket.onMessage(message => {
        const request = JSON.parse(message.toString());
        this.requests.push(request);
        if (request.id === undefined) {
          return;
        }
        const errorMessage = this.rpcErrors.get(request.method);
        const response = errorMessage === undefined
          ? {
              jsonrpc: '2.0',
              id: request.id,
              result: this.replyFor(request),
            }
          : {
              jsonrpc: '2.0',
              id: request.id,
              error: { code: -32000, message: errorMessage },
            };
        const delay = this.rpcDelays.get(request.method) || 0;
        if (delay > 0) {
          setTimeout(() => socket.send(JSON.stringify(response)), delay);
        } else {
          socket.send(JSON.stringify(response));
        }
      });
      socket.send(JSON.stringify({
        jsonrpc: '2.0',
        method: 'agent.connected',
        params: { stage: 'serving' },
      }));
    });
  }

  replyFor(request) {
    switch (request.method) {
      case 'session.list':
        return this.sessionGroups(this.liveSessions);
      case 'session.list_archived':
        return this.sessionGroups(this.archivedSessions);
      case 'session.load':
      case 'session.load_archived':
        return {
          session: {
            version: 1,
            id: 'session-1',
            events: this.sessionEvents,
          },
          watermark: this.sessionEvents.at(-1)?.sequence || 0,
        };
      case 'agent.runs':
        return { runs: [], settled: [], approvals: [] };
      case 'workspace.list':
        return { workspaces: [...this.workspaces] };
      case 'workspace.add': {
        const path = request.params?.path;
        if (path && !this.workspaces.includes(path)) {
          this.workspaces.push(path);
        }
        return { workspaces: [...this.workspaces] };
      }
      case 'settings.get':
        return this.hostSettings;
      case 'settings.set': {
        const patch = request.params || {};
        for (const key of [
          'provider',
          'custom_api_url',
          'deepseek_api_key',
          'glm_api_key',
          'custom_api_key',
        ]) {
          if (patch[key] === undefined) {
            continue;
          }
          if (key === 'provider' || key === 'custom_api_url') {
            this.hostSettings[key] = patch[key];
          } else {
            const savedKey = `has_${key.replace('_api_key', '')}_key`;
            this.hostSettings[savedKey] = patch[key].trim().length > 0;
          }
        }
        this.hostSettings.revision += 1;
        return this.hostSettings;
      }
      case 'skills.installed':
        return { skills: this.installedSkills };
      case 'skills.catalog':
        return {
          skills: [
            {
              name: 'rabbita',
              module_name: 'rabbita',
              package_path: 'moonbitlang/rabbita',
              version: '0.15.4',
              description: 'Elm-style browser UI',
              author: 'MoonBit',
              repository: 'https://github.com/moonbit-community/rabbita',
            },
          ],
        };
      case 'skills.content':
        return {
          kind: 'content',
          content: '---\nname: rabbita\n---\n\n# Rabbita\n\nBrowser UI guidance.',
          absolute: '/fixture/rabbita/SKILL.md',
          sig: 'catalog-fixture',
        };
      case 'skills.installed_content':
        return {
          kind: 'content',
          content: '# MoonBit\n\nAuthoritative MoonBit guidance.',
          absolute: '/fixture/moonbit/SKILL.md',
          sig: 'installed-fixture',
        };
      case 'skills.install': {
        const installed = {
          id: 'rabbita',
          name: 'Rabbita',
          description: 'Elm-style browser UI',
          source: 'rabbita@0.15.4/moonbitlang/rabbita',
        };
        if (!this.installedSkills.some(skill => skill.id === installed.id)) {
          this.installedSkills.push(installed);
        }
        return { installed };
      }
      case 'skills.uninstall':
        this.installedSkills = this.installedSkills.filter(
          skill => skill.id !== request.params?.id,
        );
        return { removed: true };
      case 'agent.start':
        return { run_id: 'run-e2e', status: 'accepted', exit_code: 0 };
      case 'agent.cancel':
        return { run_id: request.params?.run_id || 'run-e2e' };
      case 'session.archive': {
        const index = this.liveSessions.findIndex(
          session => session.id === request.params?.session,
        );
        if (index >= 0) {
          this.archivedSessions.push(...this.liveSessions.splice(index, 1));
        }
        return this.sessionGroups(this.archivedSessions);
      }
      case 'session.unarchive': {
        const index = this.archivedSessions.findIndex(
          session => session.id === request.params?.session,
        );
        if (index >= 0) {
          this.liveSessions.push(...this.archivedSessions.splice(index, 1));
        }
        return this.sessionGroups(this.archivedSessions);
      }
      case 'codex.status':
        return { status: 'ready' };
      case 'codex.account.read':
        return { requiresOpenaiAuth: this.codexRequiresAuth };
      case 'codex.account.login.start':
        return {
          loginId: 'login-e2e',
          authUrl: 'https://example.test/codex-login',
        };
      case 'codex.account.login.cancel':
      case 'codex.config.open':
        return {};
      case 'codex.server_request.list':
        return { data: [], generation: 1 };
      case 'codex.model.list':
        return { data: this.codexModels };
      case 'codex.thread.list':
        return { data: [] };
      case 'codex.draft.open':
        return {
          draftId: request.params?.draft_id,
          cwd: request.params?.cwd,
          projectRoot: request.params?.cwd,
        };
      case 'codex.draft.close':
        return {};
      case 'codex.thread.start':
        return {
          thread: {
            id: 'codex-thread-e2e',
            cwd: request.params?.cwd,
            projectRoot: request.params?.cwd,
            preview: 'Codex browser fixture',
            updatedAt: 2,
            turns: [],
          },
        };
      case 'codex.turn.start':
        return {
          turn: {
            id: 'codex-turn-e2e',
            status: 'inProgress',
            items: [],
          },
        };
      case 'codex.turn.interrupt':
        return {};
      case 'worktree.list':
        return { worktrees: [] };
      case 'workspace.settings_get':
        return { ...this.workspaceSettingsFor(request.params?.workspace) };
      case 'workspace.settings_set': {
        const patch = request.params || {};
        const snapshot = this.workspaceSettingsFor(patch.workspace);
        for (const key of [
          'worktree_mode',
          'checkout_submodules',
          'submodule_checkout_timeout_seconds',
        ]) {
          if (patch[key] !== undefined) {
            snapshot[key] = patch[key];
          }
        }
        this.workspaceSettings[patch.workspace] = snapshot;
        return { ...snapshot };
      }
      case 'git.branch':
        return {};
      case 'git.changes':
        return {
          repository: true,
          head: this.gitHead,
          baseline: this.gitBaseline,
          changes: this.gitChanges,
        };
      case 'git.history':
        return {
          repository: true,
          snapshot: {
            head: this.gitHead,
            branch: 'codex/browser-fixture',
            refs: [
              {
                name: 'codex/browser-fixture',
                revision: this.gitHead,
                kind: 'current',
              },
              {
                name: 'origin/main',
                revision: this.gitParent,
                kind: 'base',
              },
            ],
            tips: [this.gitHead, this.gitParent],
          },
          commits: [
            {
              id: this.gitHead,
              parent_ids: [this.gitMerge],
              subject: 'Cover Desktop Git flows',
              author: 'OpenSeek fixture',
              authored_at: '2026-09-01T09:30:00+08:00',
            },
            {
              id: this.gitMerge,
              parent_ids: [this.gitParent, this.gitBaseline],
              subject: 'Merge fixture lanes',
              author: 'OpenSeek fixture',
              authored_at: '2026-09-01T08:00:00+08:00',
            },
            {
              id: this.gitParent,
              parent_ids: [this.gitBaseline],
              subject: 'Add Review surface',
              author: 'OpenSeek fixture',
              authored_at: '2026-08-31T18:00:00+08:00',
            },
            {
              id: this.gitBaseline,
              parent_ids: [],
              subject: 'Initialize browser fixture',
              author: 'OpenSeek fixture',
              authored_at: '2026-08-30T10:00:00+08:00',
            },
          ],
          has_more: false,
        };
      case 'git.commit_changes':
        return {
          commit: request.params?.commit,
          parent: request.params?.commit === this.gitHead
            ? this.gitMerge
            : request.params?.commit === this.gitMerge
              ? this.gitParent
              : this.gitBaseline,
          changes: request.params?.commit === this.gitHead
            ? [
                {
                  path: 'src/main.mbt',
                  status: 'modified',
                  kind: 'file',
                },
                {
                  path: 'src/lib.mbt',
                  status: 'modified',
                  kind: 'file',
                },
              ]
            : [
                {
                  path: 'src/lib.mbt',
                  status: 'modified',
                  kind: 'file',
                },
              ],
        };
      case 'git.original_file':
        return this.gitOriginalFile(request.params || {});
      case 'fs.read_directory':
        return { entries: this.directoryEntries[request.params?.path] || [] };
      case 'fs.read_file':
        return this.readWorkingFile(request.params || {});
      case 'fs.browse':
        return {
          path: '/Users/test',
          parent: '/Users',
          entries: ['Projects', 'Workspace'],
        };
      case 'fs.search_files':
        return {
          files: [...this.searchFiles],
          from_cache: false,
          limit_hit: false,
          cancelled: false,
        };
      case 'fs.search_text':
        return {
          root: request.params?.root,
          generation: request.params?.generation,
          matches: this.textSearchMatches,
          match_count: this.textSearchMatchCount ?? this.textSearchMatches.length,
          file_count: new Set(this.textSearchMatches.map(match => match.path)).size,
          limit_hit: this.textSearchLimitHit,
          cancelled: false,
        };
      case 'agent.approval':
        return { delivered: true };
      default:
        return {};
    }
  }

  async goto() {
    await this.page.goto('/dist/browser/index.html?device=device-a');
    await this.page.getByRole('main').waitFor();
  }

  async openSession() {
    await this.page.getByText('Rabbita browser fixture', { exact: true }).first().click();
    await this.page.locator('.transcript .msg-content', {
      hasText: 'Show the browser fixture',
    }).waitFor();
  }

  async openQuickOpen() {
    const shortcut = await this.page.evaluate(() =>
      navigator.platform.includes('Mac') ? 'Meta+P' : 'Control+P');
    await this.page.keyboard.press(shortcut);
    await this.page.locator('#quick-open-input').waitFor();
  }

  async openReview({ waitForHistory = true } = {}) {
    // Review has no global shortcut of its own. Open the real right-panel
    // picker through Search, then use the product's Changes tab so the test
    // exercises the same Rabbita messages as a pointer-driven Review launch.
    const shortcut = await this.page.evaluate(() =>
      navigator.platform.includes('Mac') ? 'Meta+Shift+F' : 'Control+Shift+F');
    await this.page.keyboard.press(shortcut);
    const tabs = this.page.getByRole('tablist', { name: 'Explorer views' });
    await tabs.getByRole('tab', { name: /Changes/ }).click();
    if (waitForHistory) {
      await this.page.getByRole('tree', { name: 'Git commit history' }).waitFor();
    }
  }

  readWorkingFile(params) {
    const absolute = params.path;
    const prefix = '/workspace/';
    const path = absolute?.startsWith(prefix) ? absolute.slice(prefix.length) : absolute;
    const binary = this.binaryFiles[path];
    if (binary !== undefined) {
      return {
        kind: 'binary_content',
        data_base64: binary.data_base64,
        media_type: binary.media_type,
      };
    }
    const content = this.workingFiles[path];
    if (content === undefined) {
      return { kind: 'binary' };
    }
    return {
      kind: 'content',
      content,
      absolute,
      sig: `working:${path}`,
    };
  }

  gitOriginalFile(params) {
    const revision = params.revision || this.gitBaseline;
    const content = this.gitFilesByRevision[revision]?.[params.path];
    if (content === undefined) {
      return { kind: 'missing' };
    }
    return { kind: 'content', content };
  }

  workspaceSettingsFor(path = '/workspace') {
    return this.workspaceSettings[path] ?? {
      workspace: path,
      worktree_mode: false,
      checkout_submodules: false,
      submodule_checkout_timeout_seconds: 30,
    };
  }

  notify(method, params) {
    this.socket.send(JSON.stringify({ jsonrpc: '2.0', method, params }));
  }
}

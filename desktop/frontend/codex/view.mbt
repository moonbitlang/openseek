// Dedicated Codex app-server page. It renders Codex's semantic items and
// reverse requests directly; no raw JSON-RPC method editor is exposed.

///|
fn State::connection_label(self : State) -> String {
  match self.connection {
    CodexStarting => "Starting Codex…"
    CodexReady => if self.is_running() { "Running" } else { "Connected" }
    CodexUnavailable(message) => message
  }
}

///|
fn State::account_label(self : State) -> String {
  match self.account {
    CodexAccountUnknown => "Checking account…"
    CodexSignedOut(requires_auth) =>
      if requires_auth {
        "Sign in required"
      } else {
        "No account required"
      }
    CodexSignedIn(kind~, plan~) =>
      match plan {
        Some(plan) => "\{kind} · \{plan}"
        None => kind
      }
  }
}

///|
fn CodexPendingRequest::view(
  self : CodexPendingRequest,
  dispatch : @cmd.Emit[Msg],
) -> @html.Html {
  let key = self.request_id.stringify()
  let body : Array[@html.Html] = [
    @html.div(
      class="codex-request-title",
      match self.method_ {
        "item/commandExecution/requestApproval" => "Command approval"
        "item/fileChange/requestApproval" => "File change approval"
        "item/permissions/requestApproval" => "Permission request"
        "item/tool/requestUserInput" => "Codex needs your input"
        "mcpServer/elicitation/request" => "Tool request"
        other => other
      },
    ),
  ]
  if self.params is Object(fields) &&
    @jsonx.json_text(fields, "reason") is Some(reason) &&
    !reason.is_empty() {
    body.push(@html.p(class="codex-request-reason", reason))
  }
  match self.method_ {
    "item/commandExecution/requestApproval"
    | "item/fileChange/requestApproval" => {
      body.push(@html.pre(class="codex-raw", self.params.stringify()))
      body.push(
        @html.div(class="codex-request-actions", [
          @html.button(
            class="primary",
            on_click=dispatch(Respond(request_key=key, decision="accept")),
            "Approve once",
          ),
          @html.button(
            on_click=dispatch(
              Respond(request_key=key, decision="acceptForSession"),
            ),
            "Approve for session",
          ),
          @html.button(
            class="danger-button",
            on_click=dispatch(Respond(request_key=key, decision="decline")),
            "Decline",
          ),
        ]),
      )
    }
    "item/permissions/requestApproval" => {
      body.push(@html.pre(class="codex-raw", self.params.stringify()))
      body.push(
        @html.div(class="codex-request-actions", [
          @html.button(
            class="primary",
            on_click=dispatch(Respond(request_key=key, decision="accept")),
            "Grant for turn",
          ),
          @html.button(
            on_click=dispatch(
              Respond(request_key=key, decision="acceptForSession"),
            ),
            "Grant for session",
          ),
          @html.button(
            class="danger-button",
            on_click=dispatch(Respond(request_key=key, decision="decline")),
            "Deny",
          ),
        ]),
      )
    }
    "item/tool/requestUserInput" => {
      for question in self.questions() {
        let answer = self.answers.get(question.id).unwrap_or("")
        let controls : Array[@html.Html] = [
          @html.div(class="codex-question-header", question.header),
          @html.div(class="codex-question-text", question.question),
        ]
        if !question.options.is_empty() {
          let options : Array[@html.Html] = []
          for option in question.options {
            options.push(
              @html.button(
                class=if answer == option.0 {
                  "codex-option selected"
                } else {
                  "codex-option"
                },
                on_click=dispatch(
                  RequestAnswer(
                    request_key=key,
                    question_id=question.id,
                    answer=option.0,
                  ),
                ),
                [
                  @html.span(class="codex-option-label", option.0),
                  @html.span(class="codex-option-desc", option.1),
                ],
              ),
            )
          }
          controls.push(@html.div(class="codex-options", options))
        }
        controls.push(
          @html.input(
            value=answer,
            placeholder="Type an answer",
            on_input=dispatch.map(value => {
              RequestAnswer(
                request_key=key,
                question_id=question.id,
                answer=value,
              )
            }),
          ),
        )
        body.push(@html.div(class="codex-question", controls))
      }
      body.push(
        @html.div(class="codex-request-actions", [
          @html.button(
            class="primary",
            on_click=dispatch(Respond(request_key=key, decision="accept")),
            "Submit answers",
          ),
        ]),
      )
    }
    "mcpServer/elicitation/request" => {
      body.push(@html.pre(class="codex-raw", self.params.stringify()))
      body.push(
        @html.textarea(
          value=self.answers.get("__content").unwrap_or("{}"),
          placeholder="JSON content required by the tool",
          on_input=dispatch.map(value => {
            RequestAnswer(
              request_key=key,
              question_id="__content",
              answer=value,
            )
          }),
          "",
        ),
      )
      body.push(
        @html.div(class="codex-request-actions", [
          @html.button(
            class="primary",
            on_click=dispatch(Respond(request_key=key, decision="accept")),
            "Submit JSON",
          ),
          @html.button(
            class="danger-button",
            on_click=dispatch(Respond(request_key=key, decision="decline")),
            "Decline",
          ),
        ]),
      )
    }
    _ =>
      body.push(
        @html.pre(
          class="codex-raw danger",
          "Unsupported app-server request:\n" + self.params.stringify(),
        ),
      )
  }
  @html.section(class="codex-request", body)
}

///|
/// Plain root context for projecting Codex catalog data into the shared
/// sidebar components. Commands stay in the root sidebar dispatcher; this
/// value only identifies the selected channel and its registered projects.
pub(all) struct SidebarContext {
  channel : @interop.ChannelId
  selected : Bool
  registered_projects : Array[String]
}

///|
fn SidebarContext::project_registered(
  self : SidebarContext,
  path : String,
) -> Bool {
  self.registered_projects.contains(path)
}

///|
fn SidebarContext::project_label(
  self : SidebarContext,
  path : String,
) -> String {
  @resource.of_path(self.channel, path)
  .map(project => @resource.label(project))
  .unwrap_or(path)
}

///|
fn SidebarContext::draft_input(
  self : SidebarContext,
  draft : CodexDraftTask,
  nested : Bool,
) -> @conversation.Input {
  let root = draft.project_root.unwrap_or(draft.cwd).trim().to_owned()
  {
    id: @conversation.Id(
      source="codex.draft",
      channel=self.channel.uri_authority(),
      conversation=draft.id,
      root?=if root.is_empty() { None } else { Some(root) },
    ),
    title: draft.cwd,
    label: "New Codex thread",
    nested,
    subrun: false,
    active: self.selected,
    running: false,
    openable: true,
    worktree: None,
    run_mark: @conversation.NoRunMark,
    trailing: [],
    children: [],
  }
}

///|
/// The native Codex boundary resolves every linked worktree to its main local
/// checkout. That project root, never the exact thread cwd, is the grouping
/// identity used by the sidebar.
priv struct CodexProject(String) derive(Debug, Eq)

///|
/// Keep the short basename when it is unique. When several project roots share
/// it, add the parent directory so the sidebar does not show multiple
/// indistinguishable "openseek" folders; the full path remains the tooltip.
fn CodexProject::display_label(
  self : CodexProject,
  projects : Array[CodexProject],
  context : SidebarContext,
) -> String {
  let short = context.project_label(self.0)
  let duplicate = projects
    .iter()
    .any(project => project != self && context.project_label(project.0) == short)
  if !duplicate {
    return short
  }
  let mut end = self.0.length()
  while end > 0 && self.is_separator(end - 1) {
    end = end - 1
  }
  let mut start = end
  while start > 0 && !self.is_separator(start - 1) {
    start = start - 1
  }
  let mut parent_end = start
  while parent_end > 0 && self.is_separator(parent_end - 1) {
    parent_end = parent_end - 1
  }
  if parent_end == 0 {
    return self.0
  }
  let parent = self.0.view(end_offset=parent_end).to_owned()
  context.project_label(parent) + " / " + short
}

///|
fn CodexProject::is_separator(self : CodexProject, index : Int) -> Bool {
  let unit = self.0.code_unit_at(index)
  unit == 47 || unit == 92 // '/' or '\\'
}

///|
/// Codex contributes one plain Section input to the shared sidebar component.
/// Registered project roots become project inputs; standalone cwds remain
/// direct conversation inputs. The project and section components own fold,
/// menu, and compact-preview state, so Codex never keeps a parallel UI state.
pub fn State::sidebar_section(
  self : State,
  context : SidebarContext,
) -> @section.Input {
  let entries : Array[@section.Entry] = []
  let projects : Array[CodexProject] = []
  for thread in self.threads {
    if thread.project_key() is Some(project) &&
      context.project_registered(project.0) &&
      !projects.contains(project) {
      // Preserve app-server list order: the project containing the newest
      // visible thread appears first, and threads stay newest-first inside it.
      projects.push(project)
    }
  }
  if self.active_draft() is Some(draft) {
    let root = draft.project_root.unwrap_or(draft.cwd).trim().to_owned()
    let project = CodexProject(root)
    if !root.is_empty() &&
      context.project_registered(root) &&
      !projects.contains(project) {
      projects.push(project)
    }
  }
  for project in projects {
    let active = context.selected &&
      (match self.selection {
        CodexDraftTask(draft) =>
          CodexProject(
            draft.project_root.unwrap_or(draft.cwd).trim().to_owned(),
          ) ==
          project
        CodexStoredTask(thread) =>
          thread.project_root
          .map(root => CodexProject(root.trim().to_owned()) == project)
          .unwrap_or(false)
        CodexNoTask => false
      })
    let conversations : Array[@conversation.Input] = []
    if self.active_draft() is Some(draft) &&
      CodexProject(draft.project_root.unwrap_or(draft.cwd).trim().to_owned()) ==
      project {
      conversations.push(context.draft_input(draft, true))
    }
    for thread in self.threads {
      if thread.project_key() == Some(project) {
        conversations.push(thread.sidebar_input(self, context, true))
      }
    }
    entries.push(
      @section.Project({
        id: @project.Id(
          source="codex.projects",
          channel=context.channel.uri_authority(),
          root=project.0,
        ),
        title: project.0,
        label: project.display_label(projects, context),
        activation: if active {
          self.active_id()
        } else {
          None
        },
        can_start: self.can_start_thread(),
        // Only registered OpenSeek projects reach this branch, so the shared
        // settings and detach menu is valid for a Codex project row too.
        managed: true,
        conversations,
        empty_label: None,
      }),
    )
  }
  let loose = self.threads.filter(thread => {
    thread
    .project_key()
    .map(project => !context.project_registered(project.0))
    .unwrap_or(true)
  })
  let loose_draft = self
    .active_draft()
    .filter(draft => {
      let root = draft.project_root.unwrap_or(draft.cwd).trim().to_owned()
      root.is_empty() || !context.project_registered(root)
    })
  if loose_draft is Some(draft) {
    entries.push(@section.Conversation(context.draft_input(draft, false)))
  }
  for thread in loose {
    entries.push(
      @section.Conversation(thread.sidebar_input(self, context, false)),
    )
  }
  if self.threads.is_empty() && self.active_draft() is None {
    let empty = match self.connection {
      CodexStarting => "Loading Codex conversations…"
      CodexUnavailable(_) => "Codex is unavailable"
      CodexReady =>
        if self.account is CodexSignedOut(_) {
          "Sign in to list Codex conversations"
        } else {
          "No Codex conversations yet"
        }
    }
    entries.push(
      @section.Placeholder({
        id: "codex.open",
        label: empty,
        class_name: "codex-placeholder",
        nested: false,
        openable: true,
      }),
    )
  }
  {
    id: @section.Id(source="codex", channel=context.channel.uri_authority()),
    label: "Codex",
    initially_collapsed: false,
    activation: if context.selected {
      self.active_id()
    } else {
      None
    },
    action: Some({
      title: "New Codex conversation",
      disabled: !self.can_start_thread(),
    }),
    entries,
  }
}

///|
/// Codex archived tasks join OpenSeek's existing Archived chats section. They
/// stay non-selectable until restored because the live Codex page owns writer
/// and composer state only for active app-server threads.
pub fn State::archived_sidebar_entries(
  self : State,
  channel : @interop.ChannelId,
) -> Array[@section.Entry] {
  self.archived_threads.map(thread => {
    @section.Conversation(thread.archived_sidebar_input(channel))
  })
}

///|
fn CodexThreadRow::archived_sidebar_input(
  self : CodexThreadRow,
  channel : @interop.ChannelId,
) -> @conversation.Input {
  {
    id: @conversation.Id(
      source="codex.archived",
      channel=channel.uri_authority(),
      conversation=self.id,
      root?=self.project_root,
    ),
    title: self.cwd.unwrap_or(self.title),
    label: self.title,
    nested: false,
    subrun: false,
    active: false,
    running: false,
    openable: false,
    worktree: None,
    run_mark: @conversation.NoRunMark,
    trailing: [
      @conversation.Restore(
        title="Restore this Codex conversation to the sidebar",
      ),
    ],
    children: [],
  }
}

///|
/// A missing project root means the thread cwd was absent or its deleted
/// worktree could no longer be resolved. Keep those records together instead
/// of promoting an opaque worktree directory into a project row.
fn CodexThreadRow::project_key(self : CodexThreadRow) -> CodexProject? {
  match self.project_root {
    Some(root) => {
      let project = root.trim().to_owned()
      if project.is_empty() {
        None
      } else {
        Some(CodexProject(project))
      }
    }
    None => None
  }
}

///|
/// Supply one Codex task's state to the shared conversation component. The
/// root dispatcher translates the stable id into open/archive messages; this
/// adapter contains no commands and keeps the component input comparable.
fn CodexThreadRow::sidebar_input(
  self : CodexThreadRow,
  state : State,
  context : SidebarContext,
  nested : Bool,
) -> @conversation.Input {
  let selected = context.selected &&
    state.active_thread().map(item => item.id == self.id).unwrap_or(false)
  let running = selected && state.is_running()
  {
    id: @conversation.Id(
      source="codex.live",
      channel=context.channel.uri_authority(),
      conversation=self.id,
      root?=self.project_root,
    ),
    title: self.cwd.unwrap_or(self.title),
    label: self.title,
    nested,
    subrun: false,
    active: selected,
    running,
    openable: true,
    worktree: self.worktree
    .filter(worktree => worktree.present)
    .map(worktree => worktree.name),
    run_mark: if running {
      @conversation.RunningMark
    } else {
      @conversation.NoRunMark
    },
    trailing: if running {
      []
    } else {
      [@conversation.Archive(title="Archive Codex conversation")]
    },
    children: [],
  }
}

///|
/// Translate app-server Git data once at the package boundary. The shared
/// presentation owns every label, tone, tooltip, row, and link after this.
fn CodexGitStatus::presentation(
  self : CodexGitStatus,
) -> @composer.GitPresentation? {
  // App-server normally returns the branch beside a pull request. Preserve
  // the older UI's fallback if that partial reply ever omits it: the PR is
  // still useful, and its details can name the branch as unknown.
  let branch = match self.branch {
    Some(branch) if !branch.is_empty() => branch
    _ if self.pull_request is Some(_) => "Unknown"
    _ => return None
  }
  Some(
    @composer.GitPresentation(
      branch~,
      pull_request?=self.pull_request.map(pull_request => {
        @composer.GitPullRequest(
          number=pull_request.number,
          title=pull_request.title,
          state=pull_request.state,
          draft=pull_request.draft,
          url=pull_request.url,
          checks?=pull_request.checks.map(checks => {
            @composer.GitChecks(
              passed=checks.passed,
              failed=checks.failed,
              pending=checks.pending,
            )
          }),
        )
      }),
      compare_url?=self.compare_url,
      missing_pull_request?=if self.pull_request is None &&
        self.compare_url is None {
        Some("No matching pull request")
      } else {
        None
      },
    ),
  )
}

///|
/// Shell-owned controls embedded in the Codex topbar. Passing commands keeps
/// terminal, file-editor, sidebar, and external-link policy in the root shell.
pub(all) struct PageActions {
  toggle_sidebar : @cmd.Cmd
  toggle_terminal : @cmd.Cmd
  toggle_files : @cmd.Cmd
  open_external : (String) -> @cmd.Cmd
  workspace_label : (@common.Uri) -> String
  // The root shell supplies the one transcript view shared with OpenSeek.
  // Codex owns the normalized items, but no parallel message/activity DOM.
  transcript : @html.Html
  // Codex and OpenSeek each instantiate the same composer component with
  // source-specific Input; the page only places the rendered component.
  composer : @html.Html
}

///|
/// The Codex conversation uses the same three-row main-column shape as an
/// OpenSeek conversation: one compact topbar, one transcript, one composer.
/// Conversation switching belongs to the global sidebar, not inside here.
pub fn State::page(
  self : State,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  sidebar_open : Bool,
  terminal_open : Bool,
  file_panel_open : Bool,
  actions : PageActions,
) -> Array[@html.Html] {
  let account_actions : Array[@html.Html] = []
  match self.account {
    CodexSignedOut(true) =>
      account_actions.push(
        @html.button(
          class="primary",
          disabled=self.loading,
          on_click=dispatch(Login),
          "Sign in with ChatGPT",
        ),
      )
    CodexSignedIn(..) =>
      account_actions.push(
        @html.button(
          disabled=self.loading,
          on_click=dispatch(Logout),
          "Sign out",
        ),
      )
    _ => ()
  }
  if self.auth_url is Some(url) {
    account_actions.push(
      @html.button(on_click=(actions.open_external)(url), "Open sign-in page"),
    )
    account_actions.push(
      @html.button(
        disabled=self.loading,
        on_click=dispatch(CancelLogin),
        "Cancel sign-in",
      ),
    )
  }
  let topbar : Array[@html.Html] = []
  if !sidebar_open {
    topbar.push(
      @html.button(
        class="topbar-toggle",
        title="Show sidebar",
        on_click=actions.toggle_sidebar,
        icon(icon_layout_sidebar_left),
      ),
    )
  }
  let title = match self.selection {
    CodexDraftTask(_) => "New Codex thread"
    CodexStoredTask(thread) => thread.title
    CodexNoTask => "Codex"
  }
  let placement = self.active_placement(channel)
  let workspace = placement.bind(placement => placement.checkout_root())
  let terminal_available = self.terminal_available(channel)
  let tooltip = match self.selection {
    CodexDraftTask(draft) => draft.cwd
    CodexStoredTask(thread) => thread.cwd.unwrap_or(thread.id)
    CodexNoTask => "Codex app-server"
  }
  topbar.push(
    // Source selection already lives in the global sidebar. The conversation
    // title occupies the same topbar slot as an OpenSeek title instead of
    // growing a second product header inside the shared shell.
    @html.span(class="topbar-title", title=tooltip, title),
  )
  if workspace is Some(workspace) {
    topbar.push(
      @html.span(class="topbar-workspace", title=workspace.path, [
        icon(icon_folder),
        @html.text((actions.workspace_label)(workspace)),
      ]),
    )
  }
  topbar.push(
    @html.div(
      class=if self.is_running() { "run-status accent" } else { "run-status" },
      [
        if self.is_running() {
          @html.span(class="run-dot accent pulse", "")
        } else {
          @html.span(class="run-dot", "")
        },
        @html.span(class="run-text", [
          @html.span(class="codex-connection", self.connection_label()),
          @html.span(class="codex-account-label", " · " + self.account_label()),
          if self.is_active_elsewhere() {
            @html.span(
              class="codex-writer-status",
              title="Another Codex client owned this task's writer; Send retries acquisition",
              " · Writer unavailable",
            )
          } else {
            @html.nothing
          },
        ]),
      ],
    ),
  )
  for action in account_actions {
    topbar.push(action)
  }
  // These are OpenSeek's existing host panels, re-rooted by `file_ctx` and
  // `terminal_ctx` to the selected app-server thread. They stay in this one
  // topbar instead of creating a nested Codex application frame.
  topbar.push(
    @html.button(
      class=if terminal_open { "panel-toggle active" } else { "panel-toggle" },
      disabled=!terminal_available,
      title=if terminal_open {
        "Hide terminal"
      } else if terminal_available {
        "Show terminal"
      } else {
        "Terminal requires an available Codex task placement"
      },
      on_click=actions.toggle_terminal,
      icon(icon_terminal),
    ),
  )
  // An open file panel carries its close toggle in the breadcrumb, matching
  // the OpenSeek conversation topbar. Without a cwd there is no safe root to
  // list, so the disabled button explains why no guessed directory is opened.
  if !file_panel_open {
    topbar.push(
      @html.button(
        class="panel-toggle",
        disabled=workspace is None,
        title=if workspace is Some(_) {
          "Show files"
        } else {
          "Files require a Codex working directory"
        },
        on_click=actions.toggle_files,
        icon(icon_layout_sidebar_right),
      ),
    )
  }
  let page : Array[@html.Html] = [
    @html.div(class="topbar codex-topbar", topbar),
    actions.transcript,
    actions.composer,
  ]
  if self.archive_confirm is Some(confirm) {
    page.push(
      @composer.WorktreeArchiveDialog::{
        refusal: confirm.refusal,
        conversation_noun: "task",
        cancel: dispatch(CancelArchiveDiscard),
        confirm: dispatch(ConfirmArchiveDiscard),
      }.render(),
    )
  }
  page
}

///|
test "Codex archived catalog contributes restore inputs" {
  let state = State().with_threads(
    { "data": [{ "id": "thread-archived", "preview": "Archived task" }] },
    true,
  )
  let entries = state.archived_sidebar_entries(@interop.ChannelId::Local)
  assert_eq(entries.length(), 1)
  guard entries[0] is @section.Conversation(row) else {
    fail("expected an archived conversation input")
  }
  assert_false(row.openable)
  assert_true(row.trailing is [@conversation.Restore(..)])
}

///|
test "Codex projects feed every conversation to the shared project component" {
  let data : Array[Json] = []
  for number = 1; number <= 6; number = number + 1 {
    data.push({
      "id": "thread-\{number}",
      "projectRoot": "/work/openseek",
      "cwd": "/work/openseek",
      "preview": "Codex task \{number}",
    })
  }
  let state = State().with_threads({ "data": data }, false)
  let section = state.sidebar_section({
    channel: @interop.ChannelId::Local,
    selected: true,
    registered_projects: ["/work/openseek"],
  })
  assert_eq(section.entries.length(), 1)
  guard section.entries[0] is @section.Project(project) else {
    fail("expected a Codex project input")
  }
  assert_true(project.managed)
  assert_eq(project.conversations.length(), 6)
}

// Dedicated Codex app-server page. Reverse requests enter the shared composer
// as typed context state; no caller-rendered HTML or raw method editor crosses
// that component boundary.

///|
/// Display strings for the topbar status and the Settings page's Codex
/// account group; both render the same connection and account facts.
pub fn State::connection_label(self : State) -> String {
  match self.connection {
    CodexStarting => "Starting Codex…"
    CodexReady => if self.is_running() { "Running" } else { "Connected" }
    CodexUnavailable(message) => message
  }
}

///|
pub fn State::account_label(self : State) -> String {
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
/// The selected model's catalog-backed reasoning control. Older app-server
/// catalogs omit effort metadata; in that case there is no honest selector to
/// render and ordinary turns keep inheriting Codex's own configuration.
pub fn State::reasoning_effort_chip(
  self : State,
  open : Bool,
) -> @composer.ReasoningSelect? {
  guard self.selected_model_option() is Some(model) &&
    !model.reasoning_efforts.is_empty() else {
    return None
  }
  let selected = model.reasoning_effort(self.selected_effort)
  guard !selected.is_empty() else { return None }
  let options : Array[@composer.ModelOption] = []
  for option in model.reasoning_efforts {
    options.push({ value: option.value, label: option.value, })
  }
  let description = model.reasoning_efforts
    .iter()
    .find_first(option => option.value == selected)
    .map(option => option.description)
    .unwrap_or("")
  Some({
    id: "codex-reasoning-picker",
    options,
    selected,
    disabled: options.length() <= 1,
    open,
    title: if description.is_empty() {
      "Reasoning effort: " + selected
    } else {
      "Reasoning effort: \{selected} — \{description}"
    },
  })
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
fn SidebarContext::draft_input(
  self : SidebarContext,
  draft : CodexDraftTask,
  nested : Bool,
) -> @conversation.Input {
  let root = draft.project_root.unwrap_or(draft.cwd).trim().to_owned()
  {
    id: @conversation.Id(
      source=@conversation.CodexDraft,
      channel=self.channel.uri_authority(),
      conversation=draft.id,
      root?=if root.is_empty() { None } else { Some(root) },
    ),
    title: draft.cwd,
    // The same label an unsent OpenSeek chat's row carries: the two agents'
    // composing rows are one concept in the shared sidebar, and the model
    // chip already names which agent the chat will start with.
    label: "New chat",
    nested,
    subrun: false,
    active: self.selected,
    loading: false,
    load_failed: false,
    running: false,
    openable: true,
    worktree: None,
    run_mark: @conversation.NoRunMark,
    trailing: [],
    rename: None,
    children: [],
  }
}

///|
/// The native Codex boundary resolves every linked worktree to its main local
/// checkout. That project root, never the exact thread cwd, is the grouping
/// identity used by the sidebar.
priv struct CodexProject(String) derive(Debug, Eq)

///|
fn CodexDraftTask::grouping_root(self : CodexDraftTask) -> String {
  self.project_root.unwrap_or(self.cwd).trim().to_owned()
}

///|
/// One Codex thread's contribution to a shared project row: the component
/// input plus the app-server activity stamp the root needs to interleave it
/// with OpenSeek's own conversations by recency.
pub(all) struct CodexProjectRow {
  input : @conversation.Input
  updated_at_ms : Double?
}

///|
/// A recoverable composing draft's row when it belongs to this registered
/// project but the Codex page is not on screen. While selected, the draft is
/// represented by the project's activation instead of a redundant "New chat"
/// child row. The root pins an off-screen draft with the other this-session
/// rows instead of ranking it by a stamp it cannot have yet.
pub fn State::project_draft(
  self : State,
  context : SidebarContext,
  root : String,
) -> @conversation.Input? {
  guard !context.selected &&
    context.project_registered(root) &&
    self.active_draft() is Some(draft) &&
    CodexProject(draft.grouping_root()) == CodexProject(root) else {
    return None
  }
  Some(context.draft_input(draft, true))
}

///|
/// This registered project's Codex threads, in app-server order. Codex no
/// longer owns a sidebar section — its conversations live beside OpenSeek's
/// in the shared Projects section, distinguished only by their row identity.
pub fn State::project_conversations(
  self : State,
  context : SidebarContext,
  root : String,
) -> Array[CodexProjectRow] {
  // A thread is either nested here or a loose top-level row — never both.
  // `loose_entries` claims every unregistered root, so this side must refuse
  // them even if a caller passes one.
  guard context.project_registered(root) else { return [] }
  let project = CodexProject(root)
  let conversations : Array[CodexProjectRow] = []
  for thread in self.threads {
    if thread.project_key() == Some(project) {
      conversations.push({
        input: thread.sidebar_input(self, context, true),
        updated_at_ms: thread.updated_at_ms,
      })
    }
  }
  conversations
}

///|
/// Which conversation id activates a project row on the Codex side: the
/// active draft or thread while the Codex page is on screen. The shared
/// section component uses activation to reveal a folded branch when a new
/// conversation lands in it.
pub fn State::project_activation(
  self : State,
  context : SidebarContext,
  root : String,
) -> String? {
  guard context.selected else { return None }
  let project = CodexProject(root)
  let holds = match self.selection {
    CodexDraftTask(draft) => CodexProject(draft.grouping_root()) == project
    CodexStoredTask(thread) =>
      thread.project_root
      .map(root => CodexProject(root.trim().to_owned()) == project)
      .unwrap_or(false)
    CodexNoTask => false
  }
  if holds {
    self.active_id()
  } else {
    None
  }
}

///|
/// Codex conversations whose project root is missing or not a registered
/// project. They keep top-level rows at the end of the shared Projects
/// section, exactly as they did in the retired Codex section.
pub fn State::loose_entries(
  self : State,
  context : SidebarContext,
) -> Array[@section.Entry] {
  let entries : Array[@section.Entry] = []
  let loose_draft = self
    .active_draft()
    .filter(draft => {
      let root = draft.grouping_root()
      root.is_empty() || !context.project_registered(root)
    })
  if loose_draft is Some(draft) {
    entries.push(@section.Conversation(context.draft_input(draft, false)))
  }
  for thread in self.threads {
    if thread
      .project_key()
      .map(project => !context.project_registered(project.0))
      .unwrap_or(true) {
      entries.push(
        @section.Conversation(thread.sidebar_input(self, context, false)),
      )
    }
  }
  entries
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
      source=@conversation.CodexArchived,
      channel=channel.uri_authority(),
      conversation=self.id,
      root?=self.project_root,
    ),
    title: self.cwd.unwrap_or(self.title),
    label: self.title,
    nested: false,
    subrun: false,
    active: false,
    loading: false,
    load_failed: false,
    running: false,
    openable: false,
    worktree: None,
    run_mark: @conversation.NoRunMark,
    trailing: [
      @conversation.Restore(
        title="Restore this Codex conversation to the sidebar",
      ),
    ],
    rename: None,
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
  let run_mark = state.activity.presentation(self.id)
  {
    id: @conversation.Id(
      source=@conversation.CodexLive,
      channel=context.channel.uri_authority(),
      conversation=self.id,
      root?=self.project_root,
    ),
    title: self.cwd.unwrap_or(self.title),
    label: self.title,
    nested,
    subrun: false,
    active: selected,
    loading: false,
    load_failed: false,
    running: run_mark is @conversation.RunningMark,
    openable: true,
    worktree: self.worktree
    .filter(worktree => worktree.present)
    .map(worktree => worktree.name),
    run_mark,
    trailing: [@conversation.Archive(title="Archive Codex conversation")],
    rename: None,
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
  // Account actions (sign in/out, the pending sign-in page) live in the
  // Settings page's Codex group; the topbar keeps only the status label.
  let topbar : Array[@html.Html] = []
  let sidebar_toggle_label = if sidebar_open {
    "Hide sidebar"
  } else {
    "Show sidebar"
  }
  topbar.push(
    @html.button(
      class="topbar-toggle sidebar-boundary-toggle",
      title=sidebar_toggle_label,
      on_click=actions.toggle_sidebar,
      attrs=@html.Attrs::build().aria_label(sidebar_toggle_label),
      icon(icon_layout_sidebar_left),
    ),
  )
  let title = match self.selection {
    CodexDraftTask(_) => "New chat"
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
        ]),
      ],
    ),
  )
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
  if self.permission_picker.confirmation_dialog(dispatch) is Some(dialog) {
    page.push(dialog)
  }
  page
}

///|
test "Codex archived catalog contributes restore inputs" {
  let state = State().with_threads(
    { "data": [{ "id": "thread-archived", "preview": "Archived task" }] },
    true,
    State().activity.frontier(),
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
test "Codex threads join their registered project's shared row" {
  let data : Array[Json] = []
  for number = 1; number <= 6; number = number + 1 {
    data.push({
      "id": "thread-\{number}",
      "projectRoot": "/work/openseek",
      "cwd": "/work/openseek",
      "preview": "Codex task \{number}",
    })
  }
  let state = State().with_threads(
    { "data": data },
    false,
    State().activity.frontier(),
  )
  let context : SidebarContext = {
    channel: @interop.ChannelId::Local,
    selected: true,
    registered_projects: ["/work/openseek"],
  }
  let conversations = state.project_conversations(context, "/work/openseek")
  assert_eq(conversations.length(), 6)
  assert_true(conversations[0].input.nested)
  assert_eq(state.project_conversations(context, "/work/other").length(), 0)
  assert_eq(state.loose_entries(context).length(), 0)
}

///|
test "Codex snapshots preserve running activity across task switches" {
  let context : SidebarContext = {
    channel: @interop.ChannelId::Local,
    selected: true,
    registered_projects: ["/work/openseek"],
  }
  let listed = State().with_threads(
    {
      "data": [
        {
          "id": "thread-running",
          "projectRoot": "/work/openseek",
          "cwd": "/work/openseek",
          "preview": "Running task",
          "status": { "type": "active", "activeFlags": [] },
        },
        {
          "id": "thread-selected",
          "projectRoot": "/work/openseek",
          "cwd": "/work/openseek",
          "preview": "Selected task",
          "status": { "type": "idle" },
        },
      ],
    },
    false,
    State().activity.frontier(),
  )
  let listed_rows = listed.project_conversations(context, "/work/openseek")
  assert_true(listed_rows[0].input.run_mark is @conversation.RunningMark)
  assert_true(listed_rows[0].input.trailing is [@conversation.Archive(..)])

  // Older app-server snapshots may omit thread status. A full read still
  // carries the active turn and must survive after another task is selected.
  let read = State()
    .with_threads(
      {
        "data": [
          {
            "id": "thread-running",
            "projectRoot": "/work/openseek",
            "cwd": "/work/openseek",
            "preview": "Running task",
          },
          {
            "id": "thread-selected",
            "projectRoot": "/work/openseek",
            "cwd": "/work/openseek",
            "preview": "Selected task",
          },
        ],
      },
      false,
      State().activity.frontier(),
    )
    .with_thread_reply(
      {
        "thread": {
          "id": "thread-running",
          "projectRoot": "/work/openseek",
          "cwd": "/work/openseek",
          "preview": "Running task",
          "turns": [{ "id": "turn-1", "status": "inProgress", "items": [] }],
        },
      },
      CodexHistoryRead("thread-running", State().activity.frontier()),
    )
  assert_true(
    read.activity.presentation("thread-running") is @conversation.RunningMark,
  )
  let switched = read.with_thread_reply(
    {
      "thread": {
        "id": "thread-selected",
        "projectRoot": "/work/openseek",
        "cwd": "/work/openseek",
        "preview": "Selected task",
        "turns": [],
      },
    },
    CodexHistoryRead("thread-selected", read.activity.frontier()),
  )
  let switched_rows = switched.project_conversations(context, "/work/openseek")
  assert_true(switched_rows[0].input.run_mark is @conversation.RunningMark)
  assert_true(switched_rows[0].input.trailing is [@conversation.Archive(..)])

  let notified = State().with_notification(
    "thread/status/changed",
    {
      "threadId": "thread-running",
      "status": { "type": "active", "activeFlags": [] },
    },
    1,
  )
  assert_true(
    notified.activity.presentation("thread-running")
    is @conversation.RunningMark,
  )
  let idle = notified.with_notification(
    "thread/status/changed",
    { "threadId": "thread-running", "status": { "type": "idle" } },
    2,
  )
  assert_true(
    idle.activity.presentation("thread-running") is @conversation.NoRunMark,
  )
}

///|
test "background Codex activity follows its thread instead of selection" {
  let state = State()
    .with_threads(
      {
        "data": [
          {
            "id": "thread-background",
            "projectRoot": "/work/openseek",
            "cwd": "/work/openseek",
            "preview": "Background task",
          },
          {
            "id": "thread-selected",
            "projectRoot": "/work/openseek",
            "cwd": "/work/openseek",
            "preview": "Selected task",
          },
        ],
      },
      false,
      State().activity.frontier(),
    )
    .with_thread_reply(
      {
        "thread": {
          "id": "thread-selected",
          "projectRoot": "/work/openseek",
          "cwd": "/work/openseek",
          "preview": "Selected task",
          "turns": [],
        },
      },
      CodexHistoryRead("thread-selected", State().activity.frontier()),
    )
  let running = state.with_notification(
    "turn/started",
    {
      "threadId": "thread-background",
      "turn": { "id": "turn-1", "status": "inProgress", "items": [] },
    },
    1,
  )
  assert_eq(running.active_id(), Some("thread-selected"))
  let context : SidebarContext = {
    channel: @interop.ChannelId::Local,
    selected: true,
    registered_projects: ["/work/openseek"],
  }
  let rows = running.project_conversations(context, "/work/openseek")
  assert_eq(rows.length(), 2)
  assert_true(rows[0].input.run_mark is @conversation.RunningMark)
  assert_true(rows[0].input.trailing is [@conversation.Archive(..)])
  assert_true(rows[1].input.run_mark is @conversation.NoRunMark)

  let completed = running.with_notification(
    "turn/completed",
    {
      "threadId": "thread-background",
      "turn": { "id": "turn-1", "status": "completed", "items": [] },
    },
    2,
  )
  let settled = completed.project_conversations(context, "/work/openseek")
  assert_true(settled[0].input.run_mark is @conversation.NoRunMark)
  assert_true(settled[0].input.trailing is [@conversation.Archive(..)])
}

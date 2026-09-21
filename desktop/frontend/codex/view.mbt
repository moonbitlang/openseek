// Dedicated Codex app-server page. Reverse requests enter the shared composer
// as typed context state; no caller-rendered HTML or raw method editor crosses
// that component boundary.

///|
/// Display strings for the topbar status and the Settings page's Codex
/// account group; both render the same connection and account facts.
pub fn State::connection_label(
  self : State,
  locale? : @i18n.Locale = English,
) -> String {
  match self.connection {
    CodexStarting => status_text(locale, Starting)
    CodexReady =>
      if self.is_running() {
        status_text(locale, Running)
      } else {
        status_text(locale, Connected)
      }
    CodexUnavailable(message) => message
  }
}

///|
pub fn State::account_label(
  self : State,
  locale? : @i18n.Locale = English,
) -> String {
  match self.account {
    CodexAccountUnknown => status_text(locale, CheckingAccount)
    CodexSignedOut(requires_auth) =>
      if requires_auth {
        status_text(locale, SignInRequired)
      } else {
        status_text(locale, NoAccountRequired)
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
  locale? : @i18n.Locale = English,
  self : State,
  open : Bool,
) -> @composer.ReasoningSelect? {
  guard self.selected_model_option() is Some(model) &&
    !model.reasoning_efforts.is_empty() else {
    return None
  }
  let selected = model.reasoning_effort(self.selected_effort)
  guard !selected.is_empty() else { return None }
  let options = model.reasoning_efforts.map(option => @composer.ModelOption::{
    value: option.value,
    label: reasoning_label(locale, option.value),
  })
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
      ui(locale, ReasoningPrefix) + reasoning_label(locale, selected)
    } else {
      ui(locale, ReasoningPrefix) +
      reasoning_label(locale, selected) +
      " — " +
      description
    },
  })
}

///|
fn reasoning_label(locale : @i18n.Locale, value : String) -> String {
  match locale {
    English => value
    Spanish =>
      match value {
        "none" => "Ninguno"
        "minimal" => "Mínimo"
        "low" => "Bajo"
        "medium" => "Medio"
        "high" => "Alto"
        "xhigh" => "Muy alto"
        "max" => "Máximo"
        "ultra" => "Ultra"
        _ => value
      }
    Japanese =>
      match value {
        "none" => "なし"
        "minimal" => "最小"
        "low" => "低"
        "medium" => "中"
        "high" => "高"
        "xhigh" => "非常に高い"
        "max" => "最大"
        "ultra" => "超高"
        _ => value
      }
    SimplifiedChinese =>
      match value {
        "none" => "无"
        "minimal" => "最低"
        "low" => "低"
        "medium" => "中"
        "high" => "高"
        "xhigh" => "极高"
        "max" => "最高"
        "ultra" => "超高"
        _ => value
      }
    TraditionalChinese =>
      match value {
        "none" => "無"
        "minimal" => "最低"
        "low" => "低"
        "medium" => "中"
        "high" => "高"
        "xhigh" => "極高"
        "max" => "最高"
        "ultra" => "超高"
        _ => value
      }
  }
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
  locale? : @i18n.Locale = English,
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
    label: ui(locale, NewChat),
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
/// represented by the project's activation instead of a redundant ui(locale, NewChat)
/// child row. The root pins an off-screen draft with the other this-session
/// rows instead of ranking it by a stamp it cannot have yet.
pub fn State::project_draft(
  locale? : @i18n.Locale = English,
  self : State,
  context : SidebarContext,
  root : String,
  include_selected? : Bool = false,
) -> @conversation.Input? {
  guard (include_selected || !context.selected) &&
    context.project_registered(root) &&
    self.active_draft() is Some(draft) &&
    CodexProject(draft.grouping_root()) == CodexProject(root) else {
    return None
  }
  Some(context.draft_input(locale~, draft, true))
}

///|
/// This registered project's Codex threads, in app-server order. Codex no
/// longer owns a sidebar section — its conversations live beside OpenSeek's
/// in the shared Projects section, distinguished only by their row identity.
pub fn State::project_conversations(
  locale? : @i18n.Locale = English,
  self : State,
  context : SidebarContext,
  root : String,
) -> Array[CodexProjectRow] {
  // A thread is either nested here or a loose top-level row — never both.
  // `loose_entries` claims every unregistered root, so this side must refuse
  // them even if a caller passes one.
  guard context.project_registered(root) else { return [] }
  let project = CodexProject(root)
  [
    for thread in self.threads if thread.project_key() is Some(thread_project) &&
    thread_project == project => {
      CodexProjectRow::{
        input: thread.sidebar_input(locale~, self, context, true),
        updated_at_ms: thread.updated_at_ms,
      }
    }
  ]
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
  locale? : @i18n.Locale = English,
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
    entries.push(
      @section.Conversation(context.draft_input(locale~, draft, false)),
    )
  }
  for thread in self.threads {
    if thread
      .project_key()
      .map(project => !context.project_registered(project.0))
      .unwrap_or(true) {
      entries.push(
        @section.Conversation(
          thread.sidebar_input(locale~, self, context, false),
        ),
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
  locale? : @i18n.Locale = English,
  self : State,
  channel : @interop.ChannelId,
) -> Array[@section.Entry] {
  self.archived_threads.map(thread => {
    @section.Conversation(thread.archived_sidebar_input(locale~, channel))
  })
}

///|
fn CodexThreadRow::archived_sidebar_input(
  locale? : @i18n.Locale = English,
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
    title: self.cwd.unwrap_or(self.title.unwrap_or(ui(locale, NewChat))),
    label: self.title.unwrap_or(ui(locale, NewChat)),
    nested: false,
    subrun: false,
    active: false,
    loading: false,
    load_failed: false,
    running: false,
    openable: false,
    worktree: None,
    run_mark: @conversation.NoRunMark,
    trailing: [@conversation.Restore(title=ui(locale, RestoreCodex))],
    children: [],
  }
}

///|
/// A missing project root means the thread cwd was absent or its deleted
/// worktree could no longer be resolved. Keep those records together instead
/// of promoting an opaque worktree directory into a project row.
fn CodexThreadRow::project_key(self : CodexThreadRow) -> CodexProject? {
  self.project_root
  .map(root => root.trim().to_owned())
  .filter(project => !project.is_empty())
  .map(project => CodexProject(project))
}

///|
/// Supply one Codex task's state to the shared conversation component. The
/// root dispatcher translates the stable id into open/archive messages; this
/// adapter contains no commands and keeps the component input comparable.
fn CodexThreadRow::sidebar_input(
  locale? : @i18n.Locale = English,
  self : CodexThreadRow,
  state : State,
  context : SidebarContext,
  nested : Bool,
) -> @conversation.Input {
  let selected = context.selected &&
    state.active_thread().map(item => item.id == self.id).unwrap_or(false)
  let activity = state.activity.entry(self.id)
  let needs_input = state.pending_requests.any(request => {
    request.thread_id == self.id
  })
  let running = activity.running || needs_input
  let run_mark = @conversation.RunMark::for_task(
    running~,
    needs_input~,
    unseen_outcome=activity.unseen_outcome.map(outcome => outcome.1),
  )
  {
    id: @conversation.Id(
      source=@conversation.CodexLive,
      channel=context.channel.uri_authority(),
      conversation=self.id,
      root?=self.project_root,
    ),
    title: self.cwd.unwrap_or(self.title.unwrap_or(ui(locale, NewChat))),
    label: self.title.unwrap_or(ui(locale, NewChat)),
    nested,
    subrun: false,
    active: selected,
    loading: false,
    load_failed: false,
    running,
    openable: true,
    worktree: self.worktree
    .filter(worktree => worktree.present)
    .map(worktree => worktree.name),
    run_mark,
    trailing: [@conversation.Archive(title=ui(locale, ArchiveCodex))],
    children: [],
  }
}

///|
/// Translate app-server Git data once at the package boundary. The shared
/// presentation owns every label, tone, tooltip, row, and link after this.
fn CodexGitStatus::presentation(
  locale? : @i18n.Locale = English,
  self : CodexGitStatus,
) -> @composer.GitPresentation? {
  // App-server normally returns the branch beside a pull request. Preserve
  // the older UI's fallback if that partial reply ever omits it: the PR is
  // still useful, and its details can name the branch as unknown.
  let branch = match self.branch {
    Some(branch) if !branch.is_empty() => branch
    _ if self.pull_request is Some(_) => ui(locale, UnknownLabel)
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
        Some(ui(locale, NoMatchingPr))
      } else {
        None
      },
    ),
  )
}

///|
/// Shell-owned controls embedded in the Codex topbar. Passing commands keeps
/// terminal, file-editor, and external-link policy in the root shell.
pub(all) struct PageActions {
  toggle_terminal : @cmd.Cmd
  workspace_label : (@common.Uri) -> String
  // The root shell supplies the one transcript view shared with OpenSeek.
  // Codex owns the normalized items, but no parallel message/activity DOM.
  transcript : @html.Html
  // Codex and OpenSeek each instantiate the same composer component with
  // source-specific Input; the page only places the rendered component.
  composer : @html.Html
  // The same global display preference and control serve both sources.
  detail_toggle : @html.Html
}

///|
/// The Codex conversation uses the same three-row main-column shape as an
/// OpenSeek conversation: one compact topbar, one transcript, one composer.
/// Conversation switching belongs to the global sidebar, not inside here.
pub fn State::page(
  locale? : @i18n.Locale = English,
  self : State,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  terminal_open~ : Bool,
  narrow~ : Bool,
  actions : PageActions,
) -> Array[@html.Html] {
  // Account actions (sign in/out, the pending sign-in page) live in the
  // Settings page's Codex group; the topbar keeps only the status label.
  let topbar : Array[@html.Html] = []
  let title = match self.selection {
    CodexDraftTask(_) => ui(locale, NewChat)
    CodexStoredTask(thread) => thread.title.unwrap_or(ui(locale, NewChat))
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
          @html.span(class="codex-connection", self.connection_label(locale~)),
          @html.span(class="codex-account-label", " · " + self.account_label()),
        ]),
      ],
    ),
  )
  // The narrow titlebar carries no conversation controls, matching OpenSeek.
  if !narrow {
    topbar.push(actions.detail_toggle)
  }
  // These are OpenSeek's existing host panels, re-rooted by `file_ctx` and
  // `terminal_ctx` to the selected app-server thread. They stay in this one
  // topbar instead of creating a nested Codex application frame.
  // A newly loaded workspace inserts a label before these controls, so
  // Rabbita can reuse this button's DOM for the detail toggle. Use an
  // attribute for disabled: removing the boolean DOM property is a no-op
  // and would leave the detail toggle disabled after the slot changes.
  if !narrow {
    topbar.push(
      @html.button(
        class=if terminal_open { "panel-toggle active" } else { "panel-toggle" },
        attrs=@html.Attrs::build().disabled(!terminal_available),
        title=if terminal_open {
          ui(locale, HideTerminal)
        } else if terminal_available {
          ui(locale, ShowTerminal)
        } else {
          ui(locale, TerminalPlacement)
        },
        on_click=actions.toggle_terminal,
        icon(icon_terminal),
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
  if self.permission_picker.confirmation_dialog(locale~, dispatch)
    is Some(dialog) {
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

  for
    outcome in [
      ("completed", @conversation.CompletedMark),
      ("failed", @conversation.FailedMark),
    ] {
    let (wire_status, expected) = outcome
    let stale_frontier = running.activity.frontier()
    let turn : Json = { "id": "turn-1", "status": wire_status, "items": [] }
    let completed = running.with_notification(
      "turn/completed",
      { "threadId": "thread-background", "turn": turn },
      2,
    )
    // Reading B must not acknowledge A. Neither a delayed active snapshot nor
    // a fresh idle snapshot can erase A's unread outcome.
    let retained = completed.mark_visible_read()
    let stale = {
      ..retained,
      activity: retained.activity.reconcile_snapshot(
        [("thread-background", Some(ThreadActive))],
        stale_frontier,
      ),
    }
    let idle = {
      ..stale,
      activity: stale.activity.reconcile_snapshot(
        [("thread-background", Some(ThreadInactive))],
        stale.activity.frontier(),
      ),
    }
    assert_eq(idle.active_id(), Some("thread-selected"))
    let settled = idle.project_conversations(context, "/work/openseek")
    assert_eq(settled[0].input.run_mark, expected)
    assert_false(settled[0].input.running)
    assert_true(settled[0].input.trailing is [@conversation.Archive(..)])
    // Selecting A acknowledges only after the terminal turn is loaded.
    let opened = idle
      .with_thread_reply(
        {
          "thread": {
            "id": "thread-background",
            "cwd": "/work/openseek",
            "projectRoot": "/work/openseek",
            "turns": [turn],
          },
        },
        CodexHistoryRead("thread-background", idle.activity.frontier()),
      )
      .mark_visible_read()
    let read = opened.project_conversations(context, "/work/openseek")
    assert_true(read[0].input.run_mark is @conversation.NoRunMark)
  }
}

///|
/// Label for the shell-owned file panel control, including unavailable roots.
pub fn State::files_toggle_label(
  self : State,
  channel : @interop.ChannelId,
  locale? : @i18n.Locale = English,
) -> String {
  let workspace = self
    .active_placement(channel)
    .bind(placement => placement.checkout_root())
  ui(locale, if workspace is Some(_) { ShowFiles } else { FilesDirectory })
}

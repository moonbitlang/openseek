// Dedicated Codex app-server page. It renders Codex's semantic items and
// reverse requests directly; no raw JSON-RPC method editor is exposed.

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
  change : @cmd.Emit[String],
) -> @html.Html? {
  guard self.selected_model_option() is Some(model) &&
    !model.reasoning_efforts.is_empty() else {
    return None
  }
  let selected = model.reasoning_effort(self.selected_effort)
  guard !selected.is_empty() else { return None }
  let options : Array[@composer.ModelOption] = []
  for option in model.reasoning_efforts {
    options.push({ value: option.value, label: "Reasoning · " + option.value })
  }
  let description = model.reasoning_efforts
    .iter()
    .find_first(option => option.value == selected)
    .map(option => option.description)
    .unwrap_or("")
  Some(
    @composer.ReasoningSelect::{
      options,
      selected,
      disabled: options.length() <= 1,
      change,
      title: if description.is_empty() {
        "Reasoning effort: " + selected
      } else {
        "Reasoning effort: \{selected} — \{description}"
      },
    }.render(),
  )
}

///|
/// Render only the approval facts a person needs to make the decision. The
/// full request remains available in a disclosure below for diagnostics and
/// forward-compatible fields this client does not know yet.
fn CodexPendingRequest::approval_details(
  self : CodexPendingRequest,
) -> Array[@html.Html] {
  guard self.params is Object(fields) else { return [] }
  let details : Array[@html.Html] = []
  let network_request = fields.get("networkApprovalContext") is Some(Object(_))
  if network_request &&
    fields.get("networkApprovalContext") is Some(Object(network)) &&
    @jsonx.json_text(network, "host") is Some(host) {
    let protocol = @jsonx.json_text(network, "protocol")
    let port = network
      .get("port")
      .bind(value => {
        match value {
          String(port) => Some(port)
          Number(_) => Some(value.stringify())
          _ => None
        }
      })
    let destination = if protocol is Some(protocol) && port is Some(port) {
      "\{protocol}://\{host}:\{port}"
    } else if protocol is Some(protocol) {
      "\{protocol}://\{host}"
    } else if port is Some(port) {
      "\{host}:\{port}"
    } else {
      host
    }
    details.push(
      @html.div(class="codex-request-detail", [
        @html.div(class="codex-request-detail-label", "Network destination"),
        @html.code(class="codex-request-value", destination),
      ]),
    )
  }
  if !network_request {
    let commands : Array[String] = []
    if @jsonx.json_text(fields, "command") is Some(command) {
      commands.push(command)
    } else if fields.get("commandActions") is Some(Array(actions)) {
      for action in actions {
        if action is Object(action_fields) &&
          @jsonx.json_text(action_fields, "command") is Some(command) {
          commands.push(command)
        }
      }
    }
    if !commands.is_empty() {
      details.push(
        @html.div(class="codex-request-detail", [
          @html.div(class="codex-request-detail-label", "Command"),
          @html.pre(class="codex-request-command", commands.join("\n")),
        ]),
      )
    }
  }
  if @jsonx.json_text(fields, "cwd") is Some(cwd) && !cwd.is_empty() {
    details.push(
      @html.div(class="codex-request-detail", [
        @html.div(class="codex-request-detail-label", "Working directory"),
        @html.code(class="codex-request-value", cwd),
      ]),
    )
  }
  if fields.get("proposedExecpolicyAmendment") is Some(Array(values)) {
    let parts : Array[String] = []
    for value in values {
      if value is String(part) {
        parts.push(part)
      }
    }
    if !parts.is_empty() {
      details.push(
        @html.div(class="codex-request-detail", [
          @html.div(class="codex-request-detail-label", "Requested rule"),
          @html.code(class="codex-request-value", parts.join(" ")),
        ]),
      )
    }
  }
  if @jsonx.json_text(fields, "grantRoot") is Some(grant_root) &&
    !grant_root.is_empty() {
    details.push(
      @html.div(class="codex-request-detail", [
        @html.div(class="codex-request-detail-label", "Allowed path"),
        @html.code(class="codex-request-value", grant_root),
      ]),
    )
  }
  if fields.get("additionalPermissions") is Some(additional_permissions) &&
    !(additional_permissions is Null) {
    details.push(
      @html.div(class="codex-request-detail", [
        @html.div(class="codex-request-detail-label", "Additional permissions"),
        @html.pre(
          class="codex-request-command",
          additional_permissions.stringify(indent=2),
        ),
      ]),
    )
  }
  details
}

///|
/// Name the execution-policy choice with its concrete command prefix. The
/// server-provided decision is authoritative; the top-level proposal is only
/// a compatibility fallback for older payloads.
fn CodexPendingRequest::execpolicy_label(
  self : CodexPendingRequest,
  decision : Json,
) -> String {
  let parts : Array[String] = []
  if decision is Object(decision_fields) &&
    decision_fields.get("acceptWithExecpolicyAmendment")
    is Some(Object(amendment)) &&
    amendment.get("execpolicy_amendment") is Some(Array(values)) {
    for value in values {
      if value is String(part) {
        parts.push(part)
      }
    }
  }
  if parts.is_empty() &&
    self.params is Object(fields) &&
    fields.get("proposedExecpolicyAmendment") is Some(Array(values)) {
    for value in values {
      if value is String(part) {
        parts.push(part)
      }
    }
  }
  if parts.is_empty() {
    "Allow by rule"
  } else {
    "Allow by rule: \{parts.join(" ")}"
  }
}

///|
/// Build controls from `availableDecisions` instead of offering choices the
/// current approval request may reject.
fn CodexPendingRequest::approval_actions(
  self : CodexPendingRequest,
  dispatch : @cmd.Emit[Msg],
  request_key : String,
) -> @html.Html {
  let controls : Array[@html.Html] = []
  for decision in self.approval_decisions() {
    match decision {
      String("accept") =>
        controls.push(
          @html.button(
            class="codex-request-action codex-request-action-primary",
            on_click=dispatch(Respond(request_key~, decision~)),
            "Approve once",
          ),
        )
      String("acceptForSession") =>
        controls.push(
          @html.button(
            class="codex-request-action",
            on_click=dispatch(Respond(request_key~, decision~)),
            "Approve for session",
          ),
        )
      String("decline") =>
        controls.push(
          @html.button(
            class="codex-request-action codex-request-action-danger",
            on_click=dispatch(Respond(request_key~, decision~)),
            "Decline",
          ),
        )
      String("cancel") =>
        controls.push(
          @html.button(
            class="codex-request-action codex-request-action-danger",
            on_click=dispatch(Respond(request_key~, decision~)),
            "Cancel",
          ),
        )
      Object(fields) if fields.get("acceptWithExecpolicyAmendment") is Some(_) =>
        controls.push(
          @html.button(
            class="codex-request-action",
            on_click=dispatch(Respond(request_key~, decision~)),
            self.execpolicy_label(decision),
          ),
        )
      _ => ()
    }
  }
  if controls.is_empty() {
    controls.push(
      @html.span(
        class="codex-request-unsupported",
        "This app version cannot answer the advertised approval choices.",
      ),
    )
  }
  @html.div(class="codex-request-actions", controls)
}

///|
fn CodexPendingRequest::raw_details(
  self : CodexPendingRequest,
  open~ : Bool,
) -> @html.Html {
  @html.details(class="codex-request-raw", open~, [
    @html.summary(class="codex-request-raw-summary", "Show details"),
    @html.pre(class="codex-raw", self.params.stringify(indent=2)),
  ])
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
        "item/commandExecution/requestApproval" =>
          if self.params is Object(fields) &&
            fields.get("networkApprovalContext") is Some(Object(_)) {
            "Network access approval"
          } else {
            "Command approval"
          }
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
      let details = self.approval_details()
      if !details.is_empty() {
        body.push(@html.div(class="codex-request-details", details))
      }
      body.push(self.raw_details(open=details.is_empty()))
      body.push(self.approval_actions(dispatch, key))
    }
    "item/permissions/requestApproval" => {
      body.push(@html.pre(class="codex-raw", self.params.stringify(indent=2)))
      body.push(
        @html.div(class="codex-request-actions", [
          @html.button(
            class="codex-request-action codex-request-action-primary",
            on_click=dispatch(
              Respond(request_key=key, decision=Json::string("accept")),
            ),
            "Grant for turn",
          ),
          @html.button(
            class="codex-request-action",
            on_click=dispatch(
              Respond(
                request_key=key,
                decision=Json::string("acceptForSession"),
              ),
            ),
            "Grant for session",
          ),
          @html.button(
            class="codex-request-action codex-request-action-danger",
            on_click=dispatch(
              Respond(request_key=key, decision=Json::string("decline")),
            ),
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
            class="codex-request-action codex-request-action-primary",
            on_click=dispatch(
              Respond(request_key=key, decision=Json::string("accept")),
            ),
            "Submit answers",
          ),
        ]),
      )
    }
    "mcpServer/elicitation/request" => {
      body.push(@html.pre(class="codex-raw", self.params.stringify(indent=2)))
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
            class="codex-request-action codex-request-action-primary",
            on_click=dispatch(
              Respond(request_key=key, decision=Json::string("accept")),
            ),
            "Submit JSON",
          ),
          @html.button(
            class="codex-request-action codex-request-action-danger",
            on_click=dispatch(
              Respond(request_key=key, decision=Json::string("decline")),
            ),
            "Decline",
          ),
        ]),
      )
    }
    _ =>
      body.push(
        @html.pre(
          class="codex-raw danger",
          "Unsupported app-server request:\n" + self.params.stringify(indent=2),
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
    // The same label an unsent OpenSeek chat's row carries: the two agents'
    // composing rows are one concept in the shared sidebar, and the model
    // chip already names which agent the chat will start with.
    label: "New chat",
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
/// The composing draft's row when it belongs to this registered project.
/// The root pins it with the other this-session composing rows instead of
/// ranking it by a stamp it cannot have yet.
pub fn State::project_draft(
  self : State,
  context : SidebarContext,
  root : String,
) -> @conversation.Input? {
  guard context.project_registered(root) &&
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
  let state = State().with_threads({ "data": data }, false)
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

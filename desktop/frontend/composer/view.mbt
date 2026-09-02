///|
/// The primary action at the right edge of a conversation composer. The caller
/// decides whether the action sends, steers, or stops; this package
/// owns the button DOM so those states retain identical geometry.
priv struct ActionButton {
  id : String
  class_name : String
  title : String
  disabled : Bool
  command : @cmd.Cmd
  content : @html.Html
}

///|
fn ActionButton::render(self : ActionButton) -> @html.Html {
  @html.button(
    id=self.id,
    class=self.class_name,
    type_="button",
    title=self.title,
    disabled=self.disabled,
    on_click=self.command,
    self.content,
  )
}

///|
/// One option in the composer's model selector. The value remains protocol
/// data; the label is the text the shared custom menu presents.
pub(all) struct ModelOption {
  value : String
  label : String
} derive(Eq)

///|
/// One provider's model options. This typed composer state stays comparable
/// even though the lower-level menu component intentionally has no Eq API.
pub(all) struct ModelGroup {
  label : String
  options : Array[ModelOption]
} derive(Eq)

///|
/// Convert at the package boundary; callers never depend on select-control
/// representation and the composer contract remains plain comparable data.
fn ModelGroup::select_group(self : ModelGroup) -> @select_control.Group {
  {
    label: self.label,
    options: self.options.map(option => {
      value: option.value,
      label: option.label,
    }),
  }
}

///|
/// A compact model pill backed by the composer's custom popup.
pub(all) struct ModelSelect {
  id : String
  groups : Array[ModelGroup]
  selected : String
  disabled : Bool
  open : Bool
  title : String
} derive(Eq)

///|
fn ModelSelect::render(
  self : ModelSelect,
  identity : Identity,
  action_emit : @cmd.Emit[Action],
) -> @html.Html {
  @select_control.Control::{
    id: self.id,
    groups: self.groups.map(group => group.select_group()),
    selected: self.selected,
    disabled: self.disabled,
    open: self.open,
    toggle: action_emit(ModelMenuToggled(identity~)),
    dismiss: action_emit(SelectMenuDismissed(identity~)),
    change: action_emit.map(value => ModelSelected(identity~, value~)),
    title: self.title,
    aria_label: "Model",
    presentation: Composer("✦", false),
  }.render()
}

///|
/// The shared reasoning selector used by both OpenSeek and Codex composers.
/// Each caller owns its supported values; this type owns their identical
/// placement, accessibility label, and custom-menu presentation.
pub(all) struct ReasoningSelect {
  id : String
  options : Array[ModelOption]
  selected : String
  disabled : Bool
  open : Bool
  title : String
} derive(Eq)

///|
fn ReasoningSelect::render(
  self : ReasoningSelect,
  identity : Identity,
  action_emit : @cmd.Emit[Action],
) -> @html.Html {
  @select_control.Control::{
    id: self.id,
    groups: [
      {
        label: "Reasoning effort",
        options: self.options.map(option => {
          value: option.value,
          label: option.label,
        }),
      },
    ],
    selected: self.selected,
    disabled: self.disabled,
    open: self.open,
    toggle: action_emit(ReasoningMenuToggled(identity~)),
    dismiss: action_emit(SelectMenuDismissed(identity~)),
    change: action_emit.map(value => ReasoningSelected(identity~, value~)),
    title: self.title,
    aria_label: "Reasoning effort",
    presentation: Composer("◐", true),
  }.render()
}

///|
/// Placement of a conversation before and after its first workspace-bound
/// operation. The application keeps this value in its own model; the composer
/// owns the labels, tooltips, and control shape.
pub(all) enum WorktreeChoice {
  LocalCheckout
  FreshWorktree
  BoundWorktree(String)
} derive(Debug, Eq)

///|
pub fn WorktreeChoice::toggled(self : WorktreeChoice) -> WorktreeChoice {
  match self {
    LocalCheckout => FreshWorktree
    FreshWorktree => LocalCheckout
    BoundWorktree(_) => self
  }
}

///|
pub fn WorktreeChoice::wants_fresh(self : WorktreeChoice) -> Bool {
  self is FreshWorktree
}

///|
pub(all) struct WorktreeControl {
  choice : WorktreeChoice
  enabled : Bool
} derive(Eq)

///|
/// Render a Local/Worktree chip. `enabled=false`
/// keeps the selected mode visible while its first operation is in flight,
/// but turns it into a statement so a click cannot disagree with that work.
fn WorktreeControl::render(
  self : WorktreeControl,
  identity : Identity,
  action_emit : @cmd.Emit[Action],
) -> @html.Html {
  let (class_name, label, title) = match self.choice {
    LocalCheckout =>
      (
        "composer-worktree", "Local", "Runs in the workspace itself — click to run in a fresh git worktree",
      )
    FreshWorktree =>
      (
        "composer-worktree on", "Worktree", "First prompt creates a git worktree and runs there — click for local",
      )
    BoundWorktree(name) =>
      ("composer-worktree on", name, "This chat runs in worktree \{name}")
  }
  let body = [@icons.icon(@icons.icon_worktree), @html.span(label)]
  if self.enabled && !(self.choice is BoundWorktree(_)) {
    @html.button(
      class=class_name,
      type_="button",
      title~,
      on_click=action_emit(WorktreeModeToggled(identity~)),
      body,
    )
  } else {
    @html.span(class=class_name, title~, body)
  }
}

///|
/// A recovery banner for a conversation whose registered worktree
/// checkout is absent. Each backend supplies its own rebuild and archive
/// commands; the composer keeps the wording and control geometry identical.
pub(all) struct MissingWorktreeNotice {
  name : String
  conversation_noun : String
} derive(Eq)

///|
fn MissingWorktreeNotice::render(
  self : MissingWorktreeNotice,
  identity : Identity,
  action_emit : @cmd.Emit[Action],
) -> @html.Html {
  @html.div(class="composer-notice", [
    @html.span(
      class="composer-notice-text",
      "Worktree \{self.name} has no checkout. Rebuild it to continue; commits on its branch are safe.",
    ),
    @html.button(
      class="composer-notice-btn",
      type_="button",
      title="Check the branch out again at .worktrees/\{self.name}",
      on_click=action_emit(MissingWorktreeRebuildRequested(identity~)),
      "Rebuild it",
    ),
    @html.button(
      class="composer-notice-btn",
      type_="button",
      title="Archive this \{self.conversation_noun} without rebuilding its worktree",
      on_click=action_emit(MissingWorktreeArchiveRequested(identity~)),
      "Archive \{self.conversation_noun}",
    ),
  ])
}

///|
/// Render the permission question the engine is blocked on. The root sends
/// only the verbatim question state; this package owns its DOM and returns an
/// identity-scoped decision, so arbitrary HTML and commands never cross the
/// composer boundary.
fn ApprovalNotice::render(
  self : ApprovalNotice,
  identity : Identity,
  action_emit : @cmd.Emit[Action],
) -> @html.Html {
  let actions : Array[@html.Html] = if self.answered {
    [@html.span(class="composer-approval-state", "Sending…")]
  } else {
    [
      @html.button(
        class="composer-approval-action composer-approval-deny",
        type_="button",
        title="Refuse this request; the tool reports the refusal and keeps working inside the sandbox",
        on_click=action_emit(ApprovalAnswered(identity~, allow=false)),
        "Deny",
      ),
      @html.button(
        class="composer-approval-action composer-approval-allow",
        type_="button",
        title="Allow this one run; nothing beyond it is granted",
        on_click=action_emit(ApprovalAnswered(identity~, allow=true)),
        "Allow once",
      ),
    ]
  }
  let question = @html.div(
    class="composer-approval-question",
    [
      @html.span(class="composer-notice-icon", @icons.icon(@icons.icon_key)),
      @html.span(class="composer-notice-text", [
        // A tool name is code, not a decorative text pill.
        @html.code(class="composer-approval-tool", self.tool_name),
        @html.span(" wants to \{self.detail}"),
      ]),
      ..actions,
    ],
  )
  if self.body is Some(body) {
    @html.div(
      class="composer-notice composer-approval composer-approval-full",
      [
        question,
        // Never truncate the exact program whose one-shot permission is being
        // decided. The shared syntax renderer tokenizes it exactly as its later
        // transcript representation, but without that card's line numbers:
        // there are no diagnostics to match yet, and gutter chrome is noise in
        // a permission prompt.
        @html.pre(class="composer-approval-body", [
          @syntax_html.moonbit_source_code(body),
        ]),
      ],
    )
  } else {
    @html.div(class="composer-notice composer-approval", [question])
  }
}

///|
/// Render one caller-supplied context state. Keeping this method in the
/// composer package prevents callers from smuggling arbitrary DOM into the
/// stable context column. It is public so callers and tests can render the
/// typed component without reaching through the stateful composer shell.
pub fn ContextComponent::render(
  self : ContextComponent,
  identity : Identity,
  action_emit : @cmd.Emit[Action],
) -> @html.Html {
  match self {
    ConnectionBanner(device_name~) =>
      match device_name {
        Some(name) =>
          @html.div(
            class="composer-banner",
            "Can't reach \{name} — reconnecting…",
          )
        None => @html.div(class="composer-banner hidden", "")
      }
    SubrunDock(lanes~) => @subrun.dock(lanes)
    ApiSetupNotice(text~) =>
      @html.div(class="composer-notice", [
        @html.span(class="composer-notice-text", text),
        @html.button(
          class="composer-notice-btn",
          type_="button",
          title="Configure the API endpoint",
          on_click=action_emit(ApiSetupRequested(identity~)),
          "Set up",
        ),
      ])
    ApprovalRequest(approval) => approval.render(identity, action_emit)
    CodexRequests(requests~) => {
      let rendered : Array[@html.Html] = []
      for request in requests {
        rendered.push(request.render(identity, action_emit))
      }
      @html.div(class="codex-pending", rendered)
    }
    ArchivedInputNotice(text~) =>
      @html.div(class="composer-notice", [
        @html.span(class="composer-notice-text", text),
        @html.button(
          class="composer-notice-btn",
          type_="button",
          title="Dismiss this notice",
          on_click=action_emit(ArchivedInputDismissed(identity~)),
          "Got it",
        ),
      ])
    PendingSteerPanel(items~) => {
      let rows : Array[@html.Html] = []
      for shown in items {
        rows.push(
          @html.div(class="pending-steer-row", title=shown, [
            @html.span(class="pending-steer-icon", "⤷"),
            @html.span(class="pending-steer-text", shown),
            @html.span(class="pending-steer-state", "steering…"),
          ]),
        )
      }
      @html.div(class="pending-steers", rows)
    }
    CompactionNotice(queued~) =>
      @html.div(class="composer-notice", [
        @html.span(class="composer-notice-icon", @icons.icon(@icons.icon_fold)),
        @html.span(
          class="composer-notice-text",
          if queued {
            "Compaction queued — starts when the current turn ends"
          } else {
            "Compacting context…"
          },
        ),
      ])
    WorktreePlacementNotice =>
      @html.div(class="composer-notice", [
        @html.span(
          class="composer-notice-text",
          "Waiting for workspace placement…",
        ),
        @html.button(
          class="composer-notice-btn",
          type_="button",
          title="Request this workspace's worktree list again",
          on_click=action_emit(WorktreePlacementRetried(identity~)),
          "Retry",
        ),
      ])
    MissingWorktreeNoticeComponent(notice) =>
      notice.render(identity, action_emit)
  }
}

///|
fn @protocol.CodexPermissionMode::short_label(
  self : @protocol.CodexPermissionMode,
) -> String {
  match self {
    @protocol.RequestApproval => "Ask"
    @protocol.AutoReview => "Approve for me"
    @protocol.FullAccess => "Full access"
  }
}

///|
fn @protocol.CodexPermissionMode::title(
  self : @protocol.CodexPermissionMode,
) -> String {
  match self {
    @protocol.RequestApproval => "Request approval"
    @protocol.AutoReview => "Approve for me"
    @protocol.FullAccess => "Full access"
  }
}

///|
fn @protocol.CodexPermissionMode::description(
  self : @protocol.CodexPermissionMode,
) -> String {
  match self {
    @protocol.RequestApproval =>
      "Always ask before editing outside the workspace or using the internet"
    @protocol.AutoReview =>
      "Ask only when the reviewer detects a risky operation"
    @protocol.FullAccess =>
      "Unrestricted internet access and access to any file on this computer"
  }
}

///|
fn @protocol.CodexPermissionMode::glyph(
  self : @protocol.CodexPermissionMode,
) -> String {
  match self {
    @protocol.RequestApproval => "✋"
    @protocol.AutoReview => ">_"
    @protocol.FullAccess => "!"
  }
}

///|
fn @protocol.CodexPermissionMode::render_option(
  self : @protocol.CodexPermissionMode,
  selected : @protocol.CodexPermissionMode,
  identity : Identity,
  action_emit : @cmd.Emit[Action],
) -> @html.Html {
  let class_name = if self is @protocol.FullAccess {
    "codex-permission-option danger"
  } else {
    "codex-permission-option"
  }
  @html.button(
    class=if self == selected { class_name + " selected" } else { class_name },
    type_="button",
    on_click=action_emit(PermissionSelected(identity~, mode=self)),
    [
      @html.span(class="codex-permission-option-glyph", self.glyph()),
      @html.span(class="codex-permission-copy", [
        @html.span(class="codex-permission-option-title", self.title()),
        @html.span(class="codex-permission-option-desc", self.description()),
      ]),
      @html.span(
        class="codex-permission-check",
        if self == selected {
          "✓"
        } else {
          ""
        },
      ),
    ],
  )
}

///|
fn PermissionControl::render(
  self : PermissionControl,
  identity : Identity,
  action_emit : @cmd.Emit[Action],
) -> @html.Html {
  let class_name = if self.mode is @protocol.FullAccess {
    "codex-permission-control danger"
  } else {
    "codex-permission-control"
  }
  let children : Array[@html.Html] = [
    @html.button(
      class="codex-permission-button",
      type_="button",
      disabled=!self.enabled,
      title=if self.enabled {
        "Choose how Codex handles approval requests"
      } else {
        "Permission mode cannot change while Codex is running"
      },
      on_click=action_emit(PermissionMenuToggled(identity~)),
      [
        @html.span(class="codex-permission-button-glyph", self.mode.glyph()),
        @html.span(
          class="codex-permission-button-label",
          self.mode.short_label(),
        ),
        @html.span(class="codex-permission-chevron", "⌄"),
      ],
    ),
  ]
  if self.open {
    children.push(
      @html.div(
        class="codex-permission-dismiss",
        on_click=action_emit(PermissionMenuDismissed(identity~)),
        ([] : Array[@html.Html]),
      ),
    )
    children.push(
      @html.div(class="codex-permission-menu", [
        @html.div(
          class="codex-permission-menu-title",
          "How should Codex approve operations?",
        ),
        @protocol.RequestApproval.render_option(
          self.mode,
          identity,
          action_emit,
        ),
        @protocol.AutoReview.render_option(self.mode, identity, action_emit),
        @protocol.FullAccess.render_option(self.mode, identity, action_emit),
      ]),
    )
  }
  @html.div(class=class_name, children)
}

///|
fn StatusComponent::render(
  self : StatusComponent,
  identity : Identity,
  action_emit : @cmd.Emit[Action],
) -> @html.Html {
  match self {
    ModelStatus(control) => control.render(identity, action_emit)
    ReasoningStatus(control) => control.render(identity, action_emit)
    PermissionStatus(control) => control.render(identity, action_emit)
    GitStatus(control) =>
      control.presentation.render(
        open=control.open,
        toggle=action_emit(GitDetailsToggled(identity~)),
      )
    WorktreeStatus(control) => control.render(identity, action_emit)
  }
}

///|
/// A destructive confirmation for archiving a conversation with a
/// dirty worktree. The owner supplies commands, while this value owns the
/// complete path preview and the explicit data-loss warning.
pub(all) struct WorktreeArchiveDialog {
  refusal : @protocol.ArchiveNeedsForceReply
  conversation_noun : String
  cancel : @cmd.Cmd
  confirm : @cmd.Cmd
}

///|
pub fn WorktreeArchiveDialog::message(self : WorktreeArchiveDialog) -> String {
  let refusal = self.refusal
  let preview = if refusal.dirty_paths.is_empty() {
    ""
  } else {
    let remaining = refusal.dirty_path_count - refusal.dirty_paths.length()
    let suffix = if remaining > 0 { ", and \{remaining} more" } else { "" }
    " Changed paths: \{refusal.dirty_paths.join(", ")}\{suffix}."
  }
  "Worktree \{refusal.worktree} has uncommitted changes.\{preview} Archiving deletes this checkout and permanently discards its uncommitted, untracked, and ignored files. Committed work and the branch remain."
}

///|
pub fn WorktreeArchiveDialog::render(
  self : WorktreeArchiveDialog,
) -> @html.Html {
  @html.div(class="modal-backdrop", on_click=self.cancel, [
    @html.div(class="modal", [
      @html.div(class="modal-title", "Archive this \{self.conversation_noun}?"),
      @html.div(class="modal-body", self.message()),
      @html.div(class="modal-actions", [
        @html.button(on_click=self.cancel, "Keep working"),
        @html.button(
          class="primary",
          on_click=self.confirm,
          "Discard local changes and archive",
        ),
      ]),
    ]),
  ])
}

///|
/// One removable context chip. The caller supplies meaning and commands; this
/// package owns the exact DOM shape.
priv struct MentionChip {
  glyph : String
  label : String
  title : String
  jump : @cmd.Cmd?
  remove : (@cmd.Cmd, @html.Html)?
}

///|
fn MentionChip::render(self : MentionChip) -> @html.Html {
  let glyph = @html.span(class="mention-glyph", self.glyph)
  let label = @html.span(class="mention-label", self.label)
  let body = match self.jump {
    Some(command) =>
      @html.button(
        class="mention-jump",
        type_="button",
        title=self.title,
        on_click=command,
        [glyph, label],
      )
    None => @html.span(class="mention-body", title=self.title, [glyph, label])
  }
  let children : Array[@html.Html] = [body]
  if self.remove is Some((command, content)) {
    children.push(
      @html.button(
        class="mention-remove",
        type_="button",
        title="Remove",
        on_click=command,
        content,
      ),
    )
  }
  @html.div(class="mention-chip", children)
}

///|
/// The component's final renderer-local view. It owns the textarea, mention
/// tray, toolbar, action group, stable DOM order, and surrounding chrome;
/// callers cannot construct it or pass rendered fragments through it.
priv struct View {
  before_inner : Array[@html.Html]
  mentions : Array[@html.Html]
  value : String
  placeholder : String
  disabled : Bool
  input : @cmd.Emit[String]
  keyboard : KeyboardActions
  status : Array[@html.Html]
  actions : Array[ActionButton]
  overlay : @html.Html?
}

///|
fn View::render(self : View) -> @html.Html {
  let inner : Array[@html.Html] = [
    // Keep the input wrapper and its two children permanently mounted. Rabbita
    // diffs array children by position, so chips appearing must not replace
    // the focus-holding textarea subtree.
    @html.div(class="composer-input", [
      @html.div(class="mention-tray", self.mentions),
      @html.textarea(
        id="task",
        value=self.value,
        placeholder=self.placeholder,
        disabled=self.disabled,
        on_input=self.input,
        // The surrounding card owns the visible focus frame; this marker lets
        // the global focus styling find the textarea without drawing a second
        // border around the control itself.
        attrs=self.keyboard.attrs().data_set("focus-target", ""),
        "",
      ),
    ]),
    @html.div(class="composer-toolbar", [
      @html.div(class="composer-controls", [
        @html.div(class="composer-status", self.status),
        @html.div(
          class="composer-actions",
          self.actions.map(action => action.render()),
        ),
      ]),
    ]),
  ]
  // Keep the stable input wrapper and toolbar first; transient overlays are
  // always appended.
  if self.overlay is Some(overlay) {
    inner.push(overlay)
  }
  // The context is one permanent sibling even when caller-specific panels
  // appear or disappear. This prevents their count from changing the inner
  // card's index and destroying textarea focus.
  @html.section(class="composer", [
    @html.div(class="composer-context", self.before_inner),
    @html.div(
      class="composer-inner",
      attrs=@html.Attrs::build().data_set("focus-owner", ""),
      inner,
    ),
  ])
}

///|
/// The open turn's heartbeat, docked directly above the textarea: what it is
/// doing, how long it has been at it, and what it has spent.
///
/// A model call is silent for as long as it thinks — no delta, no tool
/// result, no commit — so without this the window is indistinguishable from a
/// hung one. Deliberately lighter than a `composer-notice`: this is the only
/// row here that repaints every second, and a bordered card doing that reads
/// as an alarm rather than a heartbeat.
///
/// Always a slot, empty when idle and collapsed by `.composer-running:empty`,
/// the same shape as the plan panel's and for the same reason: the context
/// column is diffed by position, so a row that came and went would shift the
/// goal row below it on every run start and end.
fn running_row(run : RunHeartbeat?, clock_ms~ : Double) -> @html.Html {
  guard run is Some(run) else {
    return @html.div(class="composer-running", ([] : Array[@html.Html]))
  }
  @html.div(class="composer-running", [
    @html.span(class="composer-running-mark", ""),
    @html.span(class="composer-running-text", run.label(clock_ms~)),
  ])
}

///|
/// The heartbeat as one line. Each half of the detail is reported only when
/// genuinely known — an adopted run has no start this page witnessed, and a
/// turn before its first usage report has no count — so both absent leaves
/// the bare stage, which is still the one thing worth saying.
fn RunHeartbeat::label(self : RunHeartbeat, clock_ms~ : Double) -> String {
  let stage = match self.stage {
    Starting => "Starting…"
    Thinking => "Thinking…"
    AtStep(step) => "Working · step \{step}"
    Working => "Working…"
    Stopping => "Stopping…"
  }
  let detail : Array[String] = []
  if self.started_ms is Some(started) && clock_ms > started {
    detail.push(elapsed_label(clock_ms - started))
  }
  if self.tokens > 0 {
    detail.push("\{@labels.compact_count(self.tokens)} tokens")
  }
  if detail.is_empty() {
    stage
  } else {
    "\{stage} (\{detail.join(" · ")})"
  }
}

///|
/// A running span, coarsened the way a person reads a wait: seconds under a
/// minute, minutes and seconds under an hour, hours and minutes beyond. The
/// units never go finer than the span's own scale — nobody waiting twenty
/// minutes is reading the seconds column.
fn elapsed_label(span_ms : Double) -> String {
  let total_seconds = (span_ms / 1000.0).to_int()
  if total_seconds < 60 {
    return "\{total_seconds}s"
  }
  let minutes = total_seconds / 60
  if minutes < 60 {
    return "\{minutes}m \{total_seconds % 60}s"
  }
  "\{minutes / 60}h \{minutes % 60}m"
}

///|
/// One caller-owned completion row rendered inside the composer popup. The
/// caller keeps the row's action and payload; this view-only value contains
/// only its two visible strings.
priv struct CompletionRow {
  label : String
  detail : String
}

///|
/// A reusable completion popup. `empty` describes a caller-specific
/// empty/loading state such as "Searching..." or "No files".
priv struct CompletionView {
  rows : Array[CompletionRow]
  selected : Int
  hint : String
  empty : String
}

///|
/// Render one completion popup. A row uses `mousedown` so choosing it keeps
/// focus in the textarea while the owning source updates its draft.
fn CompletionView::render(
  self : CompletionView,
  pick : (Int) -> @cmd.Cmd,
) -> @html.Html {
  let rows : Array[@html.Html] = []
  for index, item in self.rows {
    rows.push(
      @html.div(
        class=if index == self.selected {
          "completion-item selected"
        } else {
          "completion-item"
        },
        attrs=@html.Attrs::build().on_mousedown(event => {
          event.prevent_default()
          pick(index)
        }),
        [
          @html.span(class="completion-label", item.label),
          @html.span(class="completion-detail", item.detail),
        ],
      ),
    )
  }
  if rows.is_empty() {
    rows.push(@html.div(class="completion-empty", self.empty))
  }
  @html.div(class="completion-menu", [
    @html.div(class="completion-hint", self.hint),
    @html.div(class="completion-list", rows),
  ])
}

///|
/// Caller-owned commands for a composer's keyboard behavior.
/// When the menu is open it captures navigation and acceptance; otherwise
/// Enter follows the ordinary submit rule below.
priv struct KeyboardActions {
  menu_open : Bool
  navigate : (Int) -> @cmd.Cmd
  accept : @cmd.Cmd
  dismiss : @cmd.Cmd
  submit : @cmd.Cmd
  cancel : @cmd.Cmd?
}

///|
fn KeyboardActions::attrs(self : KeyboardActions) -> @html.Attrs {
  @html.Attrs::build().on_keydown(event => {
    if self.menu_open {
      match event.key() {
        "ArrowDown" => {
          event.prevent_default()
          (self.navigate)(1)
        }
        "ArrowUp" => {
          event.prevent_default()
          (self.navigate)(-1)
        }
        "Tab" => {
          event.prevent_default()
          self.accept
        }
        "Enter" =>
          if !event.shift_key() && !event.is_composing() {
            event.prevent_default()
            self.accept
          } else {
            @cmd.none
          }
        "Escape" => {
          event.prevent_default()
          self.dismiss
        }
        _ => @cmd.none
      }
    } else if event.key() == "Escape" && self.cancel is Some(cancel) {
      event.prevent_default()
      cancel
    } else if is_submit_shortcut(event) {
      event.prevent_default()
      self.submit
    } else {
      @cmd.none
    }
  })
}

///|
/// Enter submits a composer unless Shift requests a newline or an IME is
/// still composing text. Keeping this rule with the composer makes every
/// caller use the same keyboard contract.
fn is_submit_shortcut(event : @dom.KeyboardEvent) -> Bool {
  event.key() == "Enter" && !event.shift_key() && !event.is_composing()
}

///|
#deprecated("Use `==` or the `Eq` trait directly", skip_current_package=true)
#doc(hidden)
pub extend MissingWorktreeNotice with Eq::{equal, not_equal}

///|
#deprecated("Use `==` or the `Eq` trait directly", skip_current_package=true)
#doc(hidden)
pub extend ModelGroup with Eq::{equal, not_equal}

///|
#deprecated("Use `==` or the `Eq` trait directly", skip_current_package=true)
#doc(hidden)
pub extend ModelOption with Eq::{equal, not_equal}

///|
#deprecated("Use `==` or the `Eq` trait directly", skip_current_package=true)
#doc(hidden)
pub extend ModelSelect with Eq::{equal, not_equal}

///|
#deprecated("Use `==` or the `Eq` trait directly", skip_current_package=true)
#doc(hidden)
pub extend ReasoningSelect with Eq::{equal, not_equal}

///|
pub extend WorktreeChoice with Debug::{to_repr}

///|
pub extend WorktreeChoice with Eq::{equal, not_equal}

///|
#deprecated("Use `==` or the `Eq` trait directly", skip_current_package=true)
#doc(hidden)
pub extend WorktreeControl with Eq::{equal, not_equal}

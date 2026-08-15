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
/// One option in the composer's model selector.
/// The owning source keeps the wire value; the composer owns its presentation.
pub(all) struct ModelOption {
  value : String
  label : String
}

///|
/// A compact model pill. A transparent native
/// select covers the visible label, preserving platform menu behavior without
/// letting the longest option determine the pill's width.
pub(all) struct ModelSelect {
  options : Array[ModelOption]
  selected : String
  disabled : Bool
  change : @cmd.Emit[String]
  title : String
}

///|
pub fn ModelSelect::render(self : ModelSelect) -> @html.Html {
  let choices : Array[@html.Html] = []
  let mut selected_label = self.selected
  for option in self.options {
    if option.value == self.selected {
      selected_label = option.label
    }
    choices.push(
      @html.option(
        value=option.value,
        selected=option.value == self.selected,
        option.label,
      ),
    )
  }
  @html.div(
    class=if self.disabled {
      "composer-model disabled"
    } else {
      "composer-model"
    },
    title=self.title,
    attrs=@html.Attrs::build().data_set("focus-owner", ""),
    [
      @html.span(class="composer-model-glyph", "✦"),
      @html.span(class="composer-model-label", selected_label),
      // CSS draws this chevron from two borders. A font glyph has a descender
      // and sat visibly below the star/label even inside a centered flex row.
      @html.span(class="composer-model-chevron", ""),
      @html.select(
        class="composer-model-native",
        disabled=self.disabled,
        on_change=self.change,
        attrs=@html.Attrs::build()
          .aria_label("Model")
          .data_set("focus-target", ""),
        choices,
      ),
    ],
  )
}

///|
/// The compact branch/PR control used by a conversation composer. Git
/// discovery and click behavior stay caller-owned; the composer owns the one
/// visible DOM shape beside the model selector.
pub(all) struct GitChip {
  tone : String
  title : String
  label : String
  command : @cmd.Cmd
  content : @html.Html
}

///|
pub fn GitChip::render(self : GitChip) -> @html.Html {
  @html.button(
    class="composer-git-button \{self.tone}",
    type_="button",
    title=self.title,
    on_click=self.command,
    [
      @html.span(class="composer-git-glyph", self.content),
      @html.span(class="composer-git-label", self.label),
    ],
  )
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
pub(all) struct WorktreeControl {
  choice : WorktreeChoice
  enabled : Bool
  command : @cmd.Cmd
  content : @html.Html
}

///|
/// Render a Local/Worktree chip. `enabled=false`
/// keeps the selected mode visible while its first operation is in flight,
/// but turns it into a statement so a click cannot disagree with that work.
pub fn WorktreeControl::render(self : WorktreeControl) -> @html.Html {
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
  let body = [self.content, @html.span(label)]
  if self.enabled && !(self.choice is BoundWorktree(_)) {
    @html.button(
      class=class_name,
      type_="button",
      title~,
      on_click=self.command,
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
  rebuild : @cmd.Cmd
  archive : @cmd.Cmd
}

///|
pub fn MissingWorktreeNotice::render(
  self : MissingWorktreeNotice,
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
      on_click=self.rebuild,
      "Rebuild it",
    ),
    @html.button(
      class="composer-notice-btn",
      type_="button",
      title="Archive this \{self.conversation_noun} without rebuilding its worktree",
      on_click=self.archive,
      "Archive \{self.conversation_noun}",
    ),
  ])
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
/// A reusable input composer. The caller owns its draft, completion results,
/// model control, and commands; this view-only
/// value owns the textarea, mention tray, toolbar, primary action, stable DOM
/// order, and all surrounding chrome.
priv struct View {
  before_inner : Array[@html.Html]
  mentions : Array[@html.Html]
  value : String
  placeholder : String
  disabled : Bool
  input : @cmd.Emit[String]
  keyboard : KeyboardActions
  status : Array[@html.Html]
  action : ActionButton
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
        self.action.render(),
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

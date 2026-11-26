///|
/// The durable/UI origin of one sidebar conversation row.
#derive(Debug, Eq, Hash)
pub(all) enum ConversationSource {
  OpenSeekLive
  CloudLive
  CloudArchived
  OpenSeekArchived
  CodexLive
  CodexArchived
  CodexDraft
}

///|
fn ConversationSource::key(self : ConversationSource) -> String {
  match self {
    CloudLive => "cloud.live"
    CloudArchived => "cloud.archived"
    OpenSeekLive => "openseek.live"
    OpenSeekArchived => "openseek.archived"
    CodexLive => "codex.live"
    CodexArchived => "codex.archived"
    CodexDraft => "codex.draft"
  }
}

///|
/// Stable identity for one conversation component. `source` prevents two
/// sidebar sections that list the same channel-local id — a live chat and an
/// archived record, or another conversation source entirely — from sharing
/// Rabbita state.
#derive(Debug, Eq, Hash)
pub(all) struct Id {
  source : ConversationSource
  channel : String
  conversation : String
  root : String?
}

///|
pub fn Id::Id(
  source~ : ConversationSource,
  channel~ : String,
  conversation~ : String,
  root? : String,
) -> Id {
  { source, channel, conversation, root, }
}

///|
pub fn Id::source(self : Id) -> ConversationSource {
  self.source
}

///|
pub fn Id::channel(self : Id) -> String {
  self.channel
}

///|
pub fn Id::conversation(self : Id) -> String {
  self.conversation
}

///|
pub fn Id::root(self : Id) -> String? {
  self.root
}

///|
/// The DOM child key for this conversation's branch. Each parent keys its
/// children so insertion and reorder preserve their DOM and event slots.
pub fn Id::key(self : Id) -> String {
  let root = self.root.unwrap_or("")
  "conversation:\{self.source.key()}:\{self.channel}:\{self.conversation}:\{root}"
}

///|
#derive(Debug, Eq)
pub(all) enum RunMark {
  NoRunMark
  RunningMark
  NeedsInputMark
  CompletedMark
  FailedMark
  StoppedMark
  EndedMark
}

///|
/// Backend adapters supply facts; priority and visual meaning belong here.
#derive(Eq)
pub(all) enum RunOutcome {
  Completed
  Failed
  Stopped
  Ended
}

///|
pub fn RunMark::for_task(
  running~ : Bool,
  needs_input~ : Bool,
  unseen_outcome~ : RunOutcome?,
) -> RunMark {
  if needs_input {
    NeedsInputMark
  } else if running {
    RunningMark
  } else {
    match unseen_outcome {
      Some(Completed) => CompletedMark
      Some(Failed) => FailedMark
      Some(Stopped) => StoppedMark
      Some(Ended) => EndedMark
      None => NoRunMark
    }
  }
}

///|
/// One action a row offers. A live durable conversation offers Archive, and
/// the permanent Delete where its source supports one; an archived record
/// offers Restore and Delete.
#derive(Debug, Eq)
pub(all) enum TrailingAction {
  Archive(title~ : String)
  Restore(title~ : String)
  Delete(title~ : String)
}

///|
/// A row's title while it is edited in place. The root owns the draft and
/// the save; the row only renders the field, locked while a save is pending.
#derive(Debug, Eq)
pub(all) struct Rename {
  draft : String
  saving : Bool
}

///|
/// What the user did in the in-place title field. `Left` is focus moving
/// away, which commits like the Finder's name field.
pub(all) enum RenameEdit {
  Typed(String)
  Submitted
  Cancelled
  Left
}

///|
/// Aggregate state of the pull requests attached to a sidebar conversation.
#derive(Debug, Eq)
pub(all) enum PullRequestTone {
  Open
  Draft
  Merged
  Closed
  Unknown
}

///|
/// Compact PR status badge rendered beside a sidebar conversation's title.
/// `count` is the total number of attached PRs (at least 1); the numeric count
/// is shown beside the icon when `count > 1`.
#derive(Debug, Eq)
pub(all) struct PullRequestBadge {
  tone : PullRequestTone
  count : Int32
  title : String
}

///|
/// Plain, comparable input to one conversation component.
#derive(Debug, Eq)
pub(all) struct Input {
  id : Id
  title : String
  label : String
  nested : Bool
  active : Bool
  loading : Bool
  load_failed : Bool
  running : Bool
  openable : Bool
  rename : Rename?
  run_mark : RunMark
  pull_request : PullRequestBadge?
  trailing : Array[TrailingAction]
}

///|
pub fn Input::id(self : Input) -> Id {
  self.id
}

///|
/// Commands stay outside component input. The root translates the stable id
/// into its navigation message; this package only owns row behavior and
/// local disclosure state.
pub(all) struct Actions {
  open : (Id) -> @cmd.Cmd
  archive : (Id) -> @cmd.Cmd
  restore : (Id) -> @cmd.Cmd
  delete : (Id) -> @cmd.Cmd
  rename : (Id, String) -> @cmd.Cmd
  rename_edit : (Id, RenameEdit) -> @cmd.Cmd
}

///|
/// Search presentation is separate from the row's domain identity and state.
#derive(Eq)
pub(all) struct Search {
  query : String
  selected : Id?
}

///|
fn highlighted(value : String, query : String) -> @html.Html {
  let query = query.trim().to_owned().to_lower()
  let children : Array[@html.Html] = []
  let mut rest = value
  while !query.is_empty() {
    guard rest.to_lower().find(query) is Some(offset) else { break }
    children.push(@html.span(rest.clamped_view(end=offset).to_owned()))
    children.push(
      @html.strong(
        rest.clamped_view(start=offset, end=offset + query.length()).to_owned(),
      ),
    )
    rest = rest.clamped_view(start=offset + query.length()).to_owned()
  }
  children.push(@html.span(rest))
  @html.span(children)
}

///|
fn Actions::command(
  self : Actions,
  action : TrailingAction,
  id : Id,
) -> @cmd.Cmd {
  match action {
    Archive(..) => (self.archive)(id)
    Restore(..) => (self.restore)(id)
    Delete(..) => (self.delete)(id)
  }
}

///|
priv enum MenuKind {
  LiveMenu
  OpenSeekArchivedMenu
  CodexArchivedMenu
}

///|
fn Input::menu_kind(self : Input) -> MenuKind? {
  if self.trailing.is_empty() {
    return None
  }
  match self.id.source() {
    OpenSeekLive | CodexLive | CloudLive => Some(LiveMenu)
    OpenSeekArchived | CloudArchived => Some(OpenSeekArchivedMenu)
    CodexArchived => Some(CodexArchivedMenu)
    CodexDraft => None
  }
}

///|
fn Input::menu_entries_for_kind(
  locale~ : @i18n.Locale = English,
  self : Input,
  actions : Actions,
  kind : MenuKind,
) -> Array[@action_menu.Entry] {
  let delete_enabled = self.trailing.any(action => action is Delete(..))
  match kind {
    LiveMenu => {
      let entries : Array[@action_menu.Entry] = [
        Action({
          label: ui(locale, RenameLabel),
          title: ui(locale, RenameConversation),
          icon: None,
          enabled: true,
          destructive: false,
          command: (actions.rename)(self.id, self.label),
        }),
        Separator,
        Action({
          label: ui(locale, ArchiveLabel),
          // The menu is the row's only Archive control, so it carries the
          // source's own hint about what archiving keeps.
          title: if self.id.source() is CloudLive {
            ui(locale, ArchiveConversation)
          } else if self.trailing is [Archive(title~), ..] {
            title
          } else {
            ui(locale, ArchiveConversation)
          },
          icon: Some(@icons.icon(@icons.icon_archive)),
          enabled: true,
          destructive: false,
          command: (actions.archive)(self.id),
        }),
      ]
      // Only a source with a permanent delete lists it, under its own hint.
      if self.trailing.iter().find_first(action => action is Delete(..))
        is Some(Delete(title~)) {
        entries.push(
          Action({
            label: ui(locale, DeleteLabel),
            title,
            icon: Some(@icons.icon(@icons.icon_close)),
            enabled: delete_enabled,
            destructive: true,
            command: (actions.delete)(self.id),
          }),
        )
      }
      entries
    }
    OpenSeekArchivedMenu =>
      [
        Action({
          label: ui(locale, RestoreLabel),
          title: ui(locale, RestoreConversation),
          icon: Some(@icons.icon(@icons.icon_arrow_up)),
          enabled: true,
          destructive: false,
          command: (actions.restore)(self.id),
        }),
        Separator,
        Action({
          label: ui(locale, DeleteLabel),
          title: if delete_enabled {
            ui(locale, DeletePermanently)
          } else {
            ui(locale, DeleteUnavailable)
          },
          icon: Some(@icons.icon(@icons.icon_close)),
          enabled: delete_enabled,
          destructive: true,
          command: (actions.delete)(self.id),
        }),
      ]
    CodexArchivedMenu =>
      [
        Action({
          label: ui(locale, RestoreLabel),
          title: ui(locale, RestoreConversation),
          icon: Some(@icons.icon(@icons.icon_arrow_up)),
          enabled: true,
          destructive: false,
          command: (actions.restore)(self.id),
        }),
      ]
  }
}

///|
/// Resolve menu contents from the latest row input. `None` means the row has
/// no contextual actions, independent of whether it has visible direct
/// buttons.
pub fn Input::menu_entries(
  locale~ : @i18n.Locale = English,
  self : Input,
  actions : Actions,
) -> Array[@action_menu.Entry]? {
  match self.menu_kind() {
    Some(kind) => Some(self.menu_entries_for_kind(locale~, actions, kind))
    None => None
  }
}

///|
/// The one in-place title field; the root focuses it when a rename starts.
pub const RenameFieldId : String = "conversation-rename-input"

///|
/// The id of a row's title button, where focus returns after a rename.
pub fn open_id(id : Id) -> String {
  id.key() + ":open"
}

///|
/// Whether the field lost focus because the list re-inserted its row, not
/// because the user left it. A reorder moves the row's node, and the browser
/// blurs a focused element that is moved. Every way of leaving looks
/// different: Tab and a click on a control name where focus goes, another
/// window takes the document's focus, and a press on plain content holds an
/// `:active` element.
fn blurred_by_relocation(event : @dom.FocusEvent) -> Bool {
  let related : @js.Value = @js.Value::cast_from(event).get_with_string(
    "relatedTarget",
  )
  let document = @dom.document()
  let has_focus : Bool = @js.Value::cast_from(document).apply_with_string(
    "hasFocus",
    ([] : FixedArray[@js.Value]),
  )
  related.is_null() &&
  has_focus &&
  document.query_selector(":active").to_option() is None
}

///|
fn focus_rename_field() -> Unit {
  if @dom.document().get_element_by_id(RenameFieldId).to_option() is Some(field) &&
    field.to_html_element() is Some(field) {
    field.focus()
  }
}

///|
fn rename_field(
  locale : @i18n.Locale,
  id : Id,
  rename : Rename,
  actions : Actions,
) -> @html.Html {
  @html.input(
    id=RenameFieldId,
    class="sidebar-label conversation-rename-input",
    value=rename.draft,
    read_only=rename.saving,
    on_input=value => (actions.rename_edit)(id, Typed(value)),
    attrs=@html.Attrs::build()
      .aria_label(ui(locale, RenameConversation))
      .on_blur(event => {
        if blurred_by_relocation(event) {
          // The user is still editing: take focus back in the row's new place.
          @cmd.custom_cmd(_ => focus_rename_field(), kind=@cmd.after_render)
        } else {
          (actions.rename_edit)(id, Left)
        }
      })
      .on_keydown(event => {
        // Keys typed into the title never reach the app's shortcuts.
        event.stop_propagation()
        guard !event.is_composing() else { return @cmd.none }
        match event.key() {
          "Enter" => {
            event.prevent_default()
            (actions.rename_edit)(id, Submitted)
          }
          "Escape" => {
            event.prevent_default()
            (actions.rename_edit)(id, Cancelled)
          }
          _ => @cmd.none
        }
      }),
  )
}

///|
fn Input::status_icon(self : Input, locale : @i18n.Locale) -> @html.Html? {
  if self.load_failed && !self.loading {
    return Some(
      @html.span(
        class="conversation-load-failed",
        attrs=@html.Attrs::build().aria_label(
          ui(locale, ConversationLoadFailed),
        ),
        "!",
      ),
    )
  }
  let (message, image, class_name) = match (self.run_mark, self.loading) {
    (NeedsInputMark, _) => (NeedsInput, @icons.icon_question, "needs-input")
    (RunningMark, _) | (_, true) =>
      (
        if self.run_mark is RunningMark {
          RunningLabel
        } else {
          LoadingMessages
        },
        @icons.icon_loading,
        "running",
      )
    (CompletedMark, false) => (CompletedUnread, @icons.icon_check, "completed")
    (FailedMark, false) => (FailedUnread, @icons.icon_error, "failed")
    (StoppedMark, false) => (StoppedUnread, @icons.icon_debug_stop, "completed")
    (EndedMark, false) => (EndedUnread, @icons.icon_circle, "completed")
    (NoRunMark, false) => return None
  }
  let label = ui(locale, message)
  Some(
    @html.span(
      class="sidebar-run-status " + class_name,
      attrs=@html.Attrs::build()
        .role("status")
        .aria_live("polite")
        .aria_label(label)
        .title(label),
      @icons.icon(image),
    ),
  )
}

///|
fn Input::pull_request_badge(
  self : Input,
  locale : @i18n.Locale,
) -> @html.Html? {
  guard self.pull_request is Some(pr) && pr.count > 0 else { return None }
  let (tone_class, image, state_label) = match pr.tone {
    Open => ("open", @icons.icon_git_pull_request, ui(locale, PullRequestOpen))
    Draft =>
      (
        "draft",
        @icons.icon_git_pull_request_draft,
        ui(locale, PullRequestDraft),
      )
    Merged => ("merged", @icons.icon_git_merge, ui(locale, PullRequestMerged))
    Closed =>
      (
        "closed",
        @icons.icon_git_pull_request_closed,
        ui(locale, PullRequestClosed),
      )
    Unknown =>
      ("unknown", @icons.icon_git_pull_request, ui(locale, PullRequestAttached))
  }
  let badge_children : Array[@html.Html] = [
    @html.span(class="row-pr-icon \{tone_class}", @icons.icon(image)),
  ]
  if pr.count > 1 {
    badge_children.push(@html.span(class="row-pr-count", pr.count.to_string()))
  }
  let aria_label = if pr.count > 1 {
    ui(locale, PullRequestSummaryMulti(pr.count, state_label))
  } else {
    state_label
  }
  Some(
    @html.span(
      class="row-pr-status",
      title=pr.title,
      attrs=@html.Attrs::build().aria_label(aria_label),
      badge_children,
    ),
  )
}

///|
/// A real Rabbita component: it is constructed once for an `assoc_by` key,
/// consumes incremental input, and returns an incremental DOM value.
pub fn component(
  locale : @rabbita.Val[@i18n.Locale],
  input : @rabbita.Val[Input],
  actions : Actions,
  search : @rabbita.Val[Search],
) -> @rabbita.Val[(String, @html.Html)] {
  let menu = input
    .map2(locale, (input, locale) => (input, locale))
    .switch_by(
      pair => {
        let (input, locale) = pair
        guard input.menu_kind() is Some(LiveMenu) &&
          input.menu_entries(locale~, actions) is Some(entries) else {
          return @rabbita.Val::constant(@html.nothing)
        }
        @action_menu.dropdown(
          input.id.key(),
          { label: @messages.text(locale, ConversationActions), entries, },
          class="row-archive row-menu-button",
          @icons.icon(@icons.icon_more),
        )
      },
      by=pair => {
        Repr::Repr((pair.0.id, pair.0.label, pair.0.trailing, pair.1)).to_string()
      },
    )
  let input = input.map2(menu, (input, menu) => (input, menu))
  let rendered = input.map3(locale, search, (pair, locale, search) => {
    let (input, menu) = pair
    let mut class = "conversation-row"
    if input.nested {
      class += " nested"
    }
    if input.active {
      class += " active"
    }
    if search.selected is Some(id) && id == input.id {
      class += " search-selected"
    }
    if input.loading {
      class += " loading"
    }
    if input.load_failed {
      class += " load-failed"
    }
    if input.running {
      class += " running"
    }
    let renaming = input.rename is Some(_)
    if renaming {
      class += " renaming"
    }
    let children : Array[@html.Html] = [
      if input.rename is Some(rename) {
        rename_field(locale, input.id, rename, actions)
      } else if input.openable {
        // Keyboard activation and title clicks share the content area's
        // open handler; trailing actions are outside that area.
        @html.button(
          id=open_id(input.id),
          type_="button",
          class="sidebar-label conversation-open",
          attrs=@html.Attrs::build()
            .aria_current(if input.active { "true" } else { "false" })
            // A pointer press must not leave focus on the title. The row
            // reveals its actions on hover and on keyboard focus; a button
            // left focused by a click would keep them pinned open in place of
            // the status. Keyboard activation never fires `mousedown`, so
            // Tab/Enter still reach the row's actions.
            .on_mousedown(event => {
              if event.get_button() == 0 {
                event.prevent_default()
                // That also keeps focus in another row's title field. Let it
                // go, so this click commits that edit like any click away.
                if @dom.document().get_element_by_id(RenameFieldId).to_option()
                  is Some(field) &&
                  field.to_html_element() is Some(field) {
                  field.blur()
                }
              }
              @cmd.none
            }),
          highlighted(input.label, search.query),
        )
      } else {
        @html.span(class="sidebar-label", input.label)
      },
    ]
    let status : Array[@html.Html] = []
    if input.pull_request_badge(locale) is Some(badge) {
      status.push(badge)
    }
    if input.status_icon(locale) is Some(icon) {
      status.push(icon)
    }
    let menu_kind = input.menu_kind()
    // A live row folds its actions behind one overflow trigger, so Rename
    // sits beside Archive and Delete in the menu the row's context click
    // also opens.
    // Archived rows keep their direct Restore and Delete buttons.
    let buttons : Array[@html.Html] = []
    if menu_kind is Some(LiveMenu) {
      buttons.push(menu)
    }
    let trailing_actions = if menu_kind is Some(LiveMenu) {
      []
    } else {
      input.trailing
    }
    let trailing_slot : Array[@html.Html] = []
    // The title field takes the whole row while it is edited.
    if !renaming &&
      (
        !status.is_empty() ||
        !buttons.is_empty() ||
        !trailing_actions.is_empty()
      ) {
      // The status group stays in the slot even when empty: a glyph coming or
      // going must not shift the action group
      // to another child position, which would re-create a focused button.
      let trailing : Array[@html.Html] = [
        @html.span(class="row-status", status),
      ]
      for action in trailing_actions {
        let (title, button_class, image, id_suffix) = match action {
          Archive(title~) =>
            (title, "row-archive", @icons.icon_archive, "archive")
          Restore(title~) =>
            (title, "row-archive", @icons.icon_arrow_up, "restore")
          Delete(title~) =>
            (title, "row-archive row-delete", @icons.icon_close, "delete")
        }
        buttons.push(
          @html.button(
            id=input.id.key() + ":direct:" + id_suffix,
            class=button_class,
            type_="button",
            title~,
            on_click=actions.command(action, input.id),
            @icons.icon(image),
          ),
        )
      }
      if !buttons.is_empty() {
        // Every action belongs to one grid child. Separate row-actions
        // children occupy the same CSS grid area and overlap each other.
        trailing.push(@html.span(class="row-actions", buttons))
      }
      trailing_slot.push(@html.span(class="row-trailing", trailing))
    }
    // A row being renamed is a text field: no row menu over the field's own
    // context menu, and a click places the caret instead of opening the row.
    let content = @html.div(
      class="conversation-content",
      on_click=if input.openable && !renaming {
        (actions.open)(input.id)
      } else {
        @cmd.none
      },
      children,
    )
    let context : @action_menu.RowContext = {
      target: input.id.key(),
      revision: Repr::Repr(
        (
          input.id,
          input.label,
          input.title,
          input.rename,
          input.openable,
          input.active,
          input.trailing,
          locale,
          search.query,
        ),
      ).to_string(),
      content,
      definition: if renaming {
        None
      } else {
        input
        .menu_entries(locale~, actions)
        .map(entries => {
          label: @messages.text(locale, ConversationActions),
          entries,
        })
      },
    }
    (input.id.key(), class, input.title, context, trailing_slot)
  })
  let context = @action_menu.row_context(rendered.map(row => row.3))
  rendered.map2(context, (row, context) => {
    let (id, class, title, _, trailing) = row
    (
      id,
      @html.div(class="sidebar-conversation", [
        @html.div(class~, title~, [context, ..trailing]),
      ]),
    )
  })
}

///|
pub extend ConversationSource with Debug::{to_repr}

///|
pub extend ConversationSource with Eq::{equal, not_equal}

///|
pub extend ConversationSource with Hash::{hash, hash_combine}

///|
pub extend Id with Debug::{to_repr}

///|
pub extend Id with Eq::{equal, not_equal}

///|
pub extend Id with Hash::{hash, hash_combine}

///|
pub extend Rename with Debug::{to_repr}

///|
pub extend Rename with Eq::{equal, not_equal}

///|
pub extend Input with Debug::{to_repr}

///|
pub extend Input with Eq::{equal, not_equal}

///|
pub extend RunMark with Debug::{to_repr}

///|
pub extend RunMark with Eq::{equal, not_equal}

///|
pub extend TrailingAction with Debug::{to_repr}

///|
pub extend TrailingAction with Eq::{equal, not_equal}

///|
pub extend RunOutcome with Eq::{equal, not_equal}

///|
pub extend PullRequestTone with Debug::{to_repr}

///|
pub extend PullRequestTone with Eq::{equal, not_equal}

///|
pub extend PullRequestBadge with Debug::{to_repr}

///|
pub extend PullRequestBadge with Eq::{equal, not_equal}

///|
pub extend Search with Eq::{equal, not_equal}

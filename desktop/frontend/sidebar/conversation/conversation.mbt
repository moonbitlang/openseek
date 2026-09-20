///|
/// The durable/UI origin of one sidebar conversation row.
pub(all) enum ConversationSource {
  OpenSeekLive
  OpenSeekArchived
  CodexLive
  CodexArchived
  CodexDraft
} derive(Debug, Eq, Hash)

///|
fn ConversationSource::key(self : ConversationSource) -> String {
  match self {
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
pub(all) struct Id {
  source : ConversationSource
  channel : String
  conversation : String
  root : String?
} derive(Debug, Eq, Hash)

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
/// The DOM child key for this conversation's row. The whole sidebar renders
/// into one keyed container, so cached component output is re-paired with its
/// own element when neighbouring rows appear or leave — never positionally.
pub fn Id::key(self : Id) -> String {
  let root = self.root.unwrap_or("")
  "conversation:\{self.source.key()}:\{self.channel}:\{self.conversation}:\{root}"
}

///|
pub(all) enum RunMark {
  NoRunMark
  RunningMark
  NeedsInputMark
  CompletedMark
  FailedMark
  StoppedMark
  EndedMark
} derive(Debug, Eq)

///|
/// Backend adapters supply facts; priority and visual meaning belong here.
pub(all) enum RunOutcome {
  Completed
  Failed
  Stopped
  Ended
} derive(Eq)

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
/// One hover-revealed control on the row's trailing edge. A live durable
/// conversation offers Archive; an archived record offers Restore and the
/// permanent Delete.
pub(all) enum TrailingAction {
  Archive(title~ : String)
  Restore(title~ : String)
  Delete(title~ : String)
} derive(Debug, Eq)

///|
/// Plain, comparable input to one conversation component. Child runs are
/// nested data so their lifetime follows the parent branch rather than array
/// position in the global sidebar.
pub(all) struct Input {
  id : Id
  title : String
  label : String
  nested : Bool
  subrun : Bool
  active : Bool
  loading : Bool
  load_failed : Bool
  running : Bool
  openable : Bool
  worktree : String?
  run_mark : RunMark
  trailing : Array[TrailingAction]
  children : Array[Input]
} derive(Debug, Eq)

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
}

///|
priv enum Msg {
  ToggleChildren
}

///|
priv struct State {
  children_open : Bool
} derive(Eq)

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
  if self.subrun || self.trailing.is_empty() {
    return None
  }
  match self.id.source() {
    OpenSeekLive | CodexLive => Some(LiveMenu)
    OpenSeekArchived => Some(OpenSeekArchivedMenu)
    CodexArchived => Some(CodexArchivedMenu)
    CodexDraft => None
  }
}

///|
fn Input::menu_enabled(self : Input) -> (Bool, Bool) {
  (
    self.trailing.any(action => action is Archive(..)) && !self.running,
    self.trailing.any(action => action is Delete(..)),
  )
}

///|
/// Direct row actions remain available alongside the WebView menu. Running
/// conversations keep the menu for discovery but cannot be archived directly.
fn Input::direct_actions(self : Input) -> Array[TrailingAction] {
  self.trailing
}

///|
fn Input::menu_entries_for_kind(
  locale? : @i18n.Locale = English,
  self : Input,
  actions : Actions,
  kind : MenuKind,
) -> Array[@action_menu.Entry] {
  let (archive_enabled, delete_enabled) = self.menu_enabled()
  match kind {
    LiveMenu =>
      [
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
          title: if archive_enabled {
            ui(locale, ArchiveConversation)
          } else {
            ui(locale, StopBeforeArchive)
          },
          icon: Some(@icons.icon(@icons.icon_archive)),
          enabled: archive_enabled,
          destructive: false,
          command: (actions.archive)(self.id),
        }),
      ]
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
  locale? : @i18n.Locale = English,
  self : Input,
  actions : Actions,
) -> Array[@action_menu.Entry]? {
  match self.menu_kind() {
    Some(kind) => Some(self.menu_entries_for_kind(locale~, actions, kind))
    None => None
  }
}

///|
fn Actions::child_component(
  self : Actions,
  locale : @rabbita.Val[@i18n.Locale],
  _id : Id,
  input : @rabbita.Val[Input],
) -> @rabbita.Val[Array[(String, @html.Html)]] {
  component(locale, input, self)
}

///|
/// A real Rabbita component: it is constructed once for an `assoc_by` key,
/// owns its sub-run disclosure state, consumes incremental input, and returns
/// an incremental DOM value. Rows are (key, node) pairs for the sidebar's one
/// keyed container.
pub fn component(
  locale : @rabbita.Val[@i18n.Locale],
  input : @rabbita.Val[Input],
  actions : Actions,
) -> @rabbita.Val[Array[(String, @html.Html)]] {
  let (state, emit) = @rabbita.create_state_with_input(
    input~,
    init=(_, _) => ({ children_open: false, }, @cmd.none),
    update=(state, _, msg, _) => {
      match msg {
        ToggleChildren => ({ children_open: !state.children_open, }, @cmd.none)
      }
    },
  )
  let child_inputs = input.map2(locale, (input, locale) => {
    @vector.from_array(input.children.map(child => (locale, child)))
  })
  let child_rows = child_inputs.assoc_by(
    (id, child) => {
      actions.child_component(
        child.map(pair => pair.0),
        id,
        child.map(pair => pair.1),
      )
    },
    by=child => child.1.id(),
  )
  state.map4(input, child_rows, locale, (state, input, child_rows, locale) => {
    // Opening a workflow child must keep its selected row visible under the parent.
    let children_open = state.children_open ||
      input.children.any(child => child.active || child.loading)
    let mut class = "conversation-row"
    if input.nested {
      class += " nested"
    }
    if input.subrun {
      class += " subrun"
    }
    if input.active {
      class += " active"
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
    let children : Array[@html.Html] = []
    if input.children.is_empty() {
      children.push(@html.span(class="row-twisty spacer", ""))
    } else {
      children.push(
        @html.button(
          class=if children_open { "row-twisty expanded" } else { "row-twisty" },
          type_="button",
          title=ui(locale, SubagentRuns(input.children.length())),
          attrs=@html.Attrs::build().on_click(event => {
            event.stop_propagation()
            emit(ToggleChildren)
          }),
          @icons.icon(@icons.icon_chevron_down),
        ),
      )
    }
    children.push(
      if input.openable {
        // Native keyboard activation bubbles to the row's existing open
        // handler, just like a pointer click on the title.
        @html.button(
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
              }
              @cmd.none
            }),
          input.label,
        )
      } else {
        @html.span(class="sidebar-label", input.label)
      },
    )
    let status : Array[@html.Html] = []
    if input.loading {
      status.push(
        @html.span(
          class="conversation-load-spinner",
          attrs=@html.Attrs::build()
            .role("status")
            .aria_label(ui(locale, LoadingConversation)),
          "",
        ),
      )
    } else if input.load_failed {
      status.push(
        @html.span(
          class="conversation-load-failed",
          attrs=@html.Attrs::build().aria_label(
            ui(locale, ConversationLoadFailed),
          ),
          "!",
        ),
      )
    }
    if input.worktree is Some(name) {
      status.push(
        @html.span(
          class="worktree-mark",
          attrs=@html.Attrs::build().aria_label(
            match locale {
              SimplifiedChinese => "在工作树 \{name} 中运行"
              TraditionalChinese => "在工作樹 \{name} 中執行"
              Japanese => "ワークツリー \{name} で実行"
              English => "Runs in worktree \{name}"
            },
          ),
          @icons.icon(@icons.icon_worktree),
        ),
      )
    }
    match input.run_mark {
      NoRunMark => ()
      RunningMark
      | NeedsInputMark
      | CompletedMark
      | FailedMark
      | StoppedMark
      | EndedMark => {
        let (label, image, class_name) = match input.run_mark {
          RunningMark =>
            (
              ui(locale, RunningLabel),
              @icons.icon_loading,
              "sidebar-run-status running",
            )
          NeedsInputMark =>
            (
              ui(locale, NeedsInput),
              @icons.icon_question,
              "sidebar-run-status needs-input",
            )
          CompletedMark =>
            (
              ui(locale, CompletedUnread),
              @icons.icon_check,
              "sidebar-run-status completed",
            )
          FailedMark =>
            (
              ui(locale, FailedUnread),
              @icons.icon_error,
              "sidebar-run-status failed",
            )
          StoppedMark =>
            (
              ui(locale, StoppedUnread),
              @icons.icon_debug_stop,
              "sidebar-run-status completed",
            )
          _ =>
            (
              ui(locale, EndedUnread),
              @icons.icon_circle,
              "sidebar-run-status completed",
            )
        }
        status.push(
          @html.span(
            class=class_name,
            attrs=@html.Attrs::build()
              .role("status")
              .aria_live("polite")
              .aria_label(label)
              .title(label),
            @icons.icon(image),
          ),
        )
      }
    }
    let menu_kind = input.menu_kind()
    // Direct durable-action shortcuts stay alongside the shared WebView
    // context menu; they remain the one-click path for frequent actions.
    let trailing_actions = input.direct_actions()
    if !status.is_empty() || !trailing_actions.is_empty() {
      let trailing : Array[@html.Html] = []
      if !status.is_empty() {
        trailing.push(@html.span(class="row-status", status))
      }
      let buttons : Array[@html.Html] = []
      for action in trailing_actions {
        let enabled = !(action is Archive(..) && input.running)
        let (title, button_class, image, id_suffix) = match action {
          Archive(title~) =>
            (title, "row-archive", @icons.icon_archive, "archive")
          Restore(title~) =>
            (title, "row-archive", @icons.icon_arrow_up, "restore")
          Delete(title~) =>
            (title, "row-archive row-delete", @icons.icon_close, "delete")
        }
        let command = if enabled {
          actions.command(action, input.id)
        } else {
          @cmd.none
        }
        buttons.push(
          @html.button(
            id=input.id.key() + ":direct:" + id_suffix,
            class=if enabled {
              button_class
            } else {
              button_class + " disabled"
            },
            type_="button",
            title=if enabled { title } else { ui(locale, StopBeforeArchive) },
            attrs=@html.Attrs::build()
              .aria_disabled((!enabled).to_string())
              .on_click(event => {
                event.stop_propagation()
                command
              }),
            @icons.icon(image),
          ),
        )
      }
      if !buttons.is_empty() {
        // Every action belongs to one grid child. Separate row-actions
        // children occupy the same CSS grid area and overlap each other.
        trailing.push(@html.span(class="row-actions", buttons))
      }
      children.push(@html.span(class="row-trailing", trailing))
    }
    let row_attrs = match menu_kind {
      Some(_) => @action_menu.context_attrs(input.id.key())
      None => @html.Attrs::build()
    }
    let row = @html.div(
      class~,
      title=input.title,
      on_click=if input.openable { (actions.open)(input.id) } else { @cmd.none },
      attrs=row_attrs,
      children,
    )
    let rows : Array[(String, @html.Html)] = [(input.id.key(), row)]
    if children_open {
      for group in child_rows {
        for child in group {
          rows.push(child)
        }
      }
    }
    rows
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

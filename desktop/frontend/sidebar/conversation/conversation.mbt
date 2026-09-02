///|
/// Stable identity for one conversation component. `source` prevents two
/// sidebar sections that list the same channel-local id — a live chat and an
/// archived record, or another conversation source entirely — from sharing
/// Rabbita state.
pub(all) struct Id {
  source : String
  channel : String
  conversation : String
  root : String?
} derive(Debug, Eq, Hash)

///|
pub fn Id::Id(
  source~ : String,
  channel~ : String,
  conversation~ : String,
  root? : String,
) -> Id {
  { source, channel, conversation, root, }
}

///|
pub fn Id::source(self : Id) -> String {
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
  "conversation:\{self.source}:\{self.channel}:\{self.conversation}:\{root}"
}

///|
pub(all) enum RunMark {
  NoRunMark
  RunningMark
  CompletedMark
  FailedMark
} derive(Debug, Eq)

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
pub(all) struct RenameInput {
  draft : String
  saving : Bool
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
  running : Bool
  openable : Bool
  worktree : String?
  run_mark : RunMark
  trailing : Array[TrailingAction]
  rename : RenameInput?
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
  native_menu : Bool
  open : (Id) -> @cmd.Cmd
  archive : (Id) -> @cmd.Cmd
  restore : (Id) -> @cmd.Cmd
  delete : (Id) -> @cmd.Cmd
  show_menu : (Id, String, @protocol.ConversationMenuKind, Bool, Bool, Int, Int) -> @cmd.Cmd
  rename_changed : (Id, String) -> @cmd.Cmd
  rename_submit : (Id) -> @cmd.Cmd
  rename_cancel : (Id) -> @cmd.Cmd
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
fn Input::native_menu_kind(self : Input) -> @protocol.ConversationMenuKind? {
  if self.subrun || self.trailing.is_empty() {
    return None
  }
  match self.id.source() {
    "openseek.live" | "codex.live" => Some(LiveConversationMenu)
    "openseek.archived" | "codex.archived" => Some(ArchivedConversationMenu)
    _ => None
  }
}

///|
fn Input::menu_enabled(self : Input) -> (Bool, Bool) {
  let mut archive = false
  let mut delete = false
  for action in self.trailing {
    match action {
      Archive(..) => archive = !(self.run_mark is RunningMark)
      Delete(..) => delete = true
      Restore(..) => ()
    }
  }
  (archive, delete)
}

///|
/// Direct row actions remain available alongside the native menu. Running
/// conversations keep the menu for discovery but cannot be archived directly.
fn Input::direct_actions(self : Input) -> Array[TrailingAction] {
  if self.run_mark is RunningMark {
    []
  } else {
    self.trailing
  }
}

///|
fn Actions::child_component(
  self : Actions,
  _id : Id,
  input : @rabbita.Val[Input],
) -> @rabbita.Val[Array[(String, @html.Html)]] {
  component(input, self)
}

///|
/// A real Rabbita component: it is constructed once for an `assoc_by` key,
/// owns its sub-run disclosure state, consumes incremental input, and returns
/// an incremental DOM value. Rows are (key, node) pairs for the sidebar's one
/// keyed container.
pub fn component(
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
  let child_inputs = input.map(input => @vector.from_array(input.children))
  let child_rows = child_inputs.assoc_by(
    (id, child) => actions.child_component(id, child),
    by=child => child.id(),
  )
  state.map3(input, child_rows, (state, input, child_rows) => {
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
    if input.running {
      class += " running"
    }
    let children : Array[@html.Html] = []
    if input.children.is_empty() {
      children.push(@html.span(class="row-twisty spacer", ""))
    } else {
      children.push(
        @html.button(
          class=if state.children_open {
            "row-twisty expanded"
          } else {
            "row-twisty"
          },
          type_="button",
          title=if input.children.length() == 1 {
            "1 subagent run"
          } else {
            "\{input.children.length()} subagent runs"
          },
          attrs=@html.Attrs::build().on_click(event => {
            event.stop_propagation()
            emit(ToggleChildren)
          }),
          @icons.icon(@icons.icon_chevron_down),
        ),
      )
    }
    match input.rename {
      Some(rename) => {
        let valid = !rename.draft.trim().is_empty() && !rename.saving
        children.push(
          @html.input(
            input_type=@html.InputType::Text,
            class="sidebar-label conversation-rename",
            value=rename.draft,
            autofocus=true,
            on_input=value => (actions.rename_changed)(input.id, value),
            attrs=@html.Attrs::build()
              .aria_label("Rename conversation")
              .disabled(rename.saving)
              .on_click(event => {
                event.stop_propagation()
                @cmd.none
              })
              .on_keydown(event => {
                if event.is_composing() {
                  return @cmd.none
                }
                match event.key() {
                  "Enter" => {
                    event.prevent_default()
                    if valid {
                      (actions.rename_submit)(input.id)
                    } else {
                      @cmd.none
                    }
                  }
                  "Escape" => {
                    event.prevent_default()
                    (actions.rename_cancel)(input.id)
                  }
                  _ => @cmd.none
                }
              }),
          ),
        )
      }
      None => children.push(@html.span(class="sidebar-label", input.label))
    }
    let status : Array[@html.Html] = []
    if input.worktree is Some(name) {
      status.push(
        @html.span(
          class="worktree-mark",
          attrs=@html.Attrs::build().aria_label("Runs in worktree \{name}"),
          @icons.icon(@icons.icon_worktree),
        ),
      )
    }
    match input.run_mark {
      NoRunMark => ()
      RunningMark =>
        status.push(
          @html.span(
            class="run-dot running",
            attrs=@html.Attrs::build()
              .role("status")
              .aria_live("polite")
              .aria_label("Running"),
            "",
          ),
        )
      CompletedMark => status.push(@html.span(class="run-dot accent", ""))
      FailedMark => status.push(@html.span(class="run-dot warn", ""))
    }
    let menu_kind = if actions.native_menu {
      input.native_menu_kind()
    } else {
      None
    }
    // Native and browser rows retain their direct durable-action shortcuts.
    // The native ellipsis and context menu add discoverability and Rename;
    // they do not replace the existing one-click actions.
    let trailing_actions = input.direct_actions()
    if !status.is_empty() ||
      !trailing_actions.is_empty() ||
      menu_kind is Some(_) {
      let trailing : Array[@html.Html] = []
      if !status.is_empty() {
        trailing.push(@html.span(class="row-status", status))
      }
      let buttons : Array[@html.Html] = []
      for action in trailing_actions {
        let (title, button_class, image) = match action {
          Archive(title~) => (title, "row-archive", @icons.icon_archive)
          Restore(title~) => (title, "row-archive", @icons.icon_arrow_up)
          Delete(title~) => (title, "row-archive row-delete", @icons.icon_close)
        }
        let command = actions.command(action, input.id)
        buttons.push(
          @html.button(
            class=button_class,
            type_="button",
            title~,
            attrs=@html.Attrs::build().on_click(event => {
              event.stop_propagation()
              command
            }),
            @icons.icon(image),
          ),
        )
      }
      if menu_kind is Some(kind) {
        let (archive_enabled, delete_enabled) = input.menu_enabled()
        let command = fn(x : Int, y : Int) {
          (actions.show_menu)(
            input.id,
            input.label,
            kind,
            archive_enabled,
            delete_enabled,
            x,
            y,
          )
        }
        buttons.push(
          @html.button(
            class="row-archive row-menu",
            type_="button",
            title="Conversation actions",
            attrs=@html.Attrs::build()
              .aria_label("Conversation actions")
              .on_click(event => {
                event.stop_propagation()
                guard event.target().to_element() is Some(target) &&
                  target.closest(".row-menu") is Some(button) else {
                  return @cmd.none
                }
                let rect = button.get_bounding_client_rect()
                command(rect.get_right().to_int(), rect.get_bottom().to_int())
              }),
            @icons.icon(@icons.icon_more),
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
      Some(kind) => {
        let (archive_enabled, delete_enabled) = input.menu_enabled()
        @html.Attrs::build().on_contextmenu(event => {
          event.prevent_default()
          (actions.show_menu)(
            input.id,
            input.label,
            kind,
            archive_enabled,
            delete_enabled,
            event.get_client_x(),
            event.get_client_y(),
          )
        })
      }
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
    if state.children_open {
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
pub extend RenameInput with Debug::{to_repr}

///|
pub extend RenameInput with Eq::{equal, not_equal}

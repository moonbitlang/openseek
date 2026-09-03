///|
pub(all) struct Id {
  source : String
  channel : String
} derive(Debug, Eq, Hash)

///|
pub fn Id::Id(source~ : String, channel~ : String) -> Id {
  { source, channel, }
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
/// The DOM child key for this section's heading inside the sidebar's one
/// keyed container.
pub fn Id::key(self : Id) -> String {
  "section:\{self.source}:\{self.channel}"
}

///|
pub(all) struct Placeholder {
  id : String
  label : String
  class_name : String
  nested : Bool
  openable : Bool
} derive(Debug, Eq)

///|
pub(all) enum Entry {
  Project(@project.Input)
  Conversation(@conversation.Input)
  Placeholder(Placeholder)
} derive(Debug, Eq)

///|
fn Entry::key(self : Entry) -> String {
  match self {
    Project(project) => project.id().key()
    Conversation(conversation) => conversation.id().key()
    Placeholder(row) => "placeholder:\{row.id}"
  }
}

///|
fn Entry::kind(self : Entry) -> String {
  match self {
    Project(_) => "project"
    Conversation(_) => "conversation"
    Placeholder(_) => "placeholder"
  }
}

///|
pub(all) struct Action {
  title : String
  disabled : Bool
} derive(Debug, Eq)

///|
pub(all) struct Input {
  id : Id
  label : String
  initially_collapsed : Bool
  // The active conversation's session id while this section holds the
  // focused chat; `None` otherwise. Same contract as
  // `@project.Input.activation`.
  activation : String?
  action : Action?
  entries : Array[Entry]
} derive(Debug, Eq)

///|
pub fn Input::id(self : Input) -> Id {
  self.id
}

///|
pub(all) struct Actions {
  primary : (Id) -> @cmd.Cmd
  placeholder : (String) -> @cmd.Cmd
  project : @project.Actions
  conversation : @conversation.Actions
}

///|
priv enum Msg {
  Toggle
}

///|
/// A fold is stamped with the activation it was made under, so revealing is
/// edge-triggered without watching input transitions: only an activation
/// different from the stamped one forces the section open.
priv enum Fold {
  Open
  Folded(during~ : String?)
} derive(Eq)

///|
priv struct State {
  fold : Fold
} derive(Eq)

///|
/// Whether the section renders folded. A stored fold holds — including while
/// its own activation stays current, so the heading's toggle works inside
/// the selected section — and only a new activation reveals it: jumping into
/// a folded section opens it to show where you are.
fn State::folded(self : State, input : Input) -> Bool {
  guard self.fold is Folded(during~) else { return false }
  input.activation is None || input.activation == during
}

///|
fn Actions::placeholder_component(
  self : Actions,
  input : @rabbita.Val[Placeholder],
) -> @rabbita.Val[Array[(String, @html.Html)]] {
  input.map(row => {
    let mut class = "conversation-row placeholder"
    if row.nested {
      class += " nested"
    }
    if !row.class_name.is_empty() {
      class = class + " " + row.class_name
    }
    let children : Array[@html.Html] = []
    if row.nested {
      children.push(@html.span(class="row-twisty spacer", ""))
    }
    children.push(@html.span(class="sidebar-label", row.label))
    [
      (
        "placeholder:\{row.id}",
        @html.div(
          class~,
          on_click=if row.openable {
            (self.placeholder)(row.id)
          } else {
            @cmd.none
          },
          children,
        ),
      ),
    ]
  })
}

///|
fn Actions::entry_component(
  self : Actions,
  _key : String,
  input : @rabbita.Val[Entry],
) -> @rabbita.Val[Array[(String, @html.Html)]] {
  input.switch_by(
    entry => {
      match entry {
        Project(initial) => {
          let project_input = input.map(entry => {
            match entry {
              Project(project) => project
              _ => initial
            }
          })
          @project.component(project_input, self.project)
        }
        Conversation(initial) => {
          let conversation_input = input.map(entry => {
            match entry {
              Conversation(conversation) => conversation
              _ => initial
            }
          })
          @conversation.component(conversation_input, self.conversation)
        }
        Placeholder(initial) => {
          let placeholder_input = input.map(entry => {
            match entry {
              Placeholder(placeholder) => placeholder
              _ => initial
            }
          })
          self.placeholder_component(placeholder_input)
        }
      }
    },
    by=entry => entry.kind(),
  )
}

///|
/// A Section is a keyed Rabbita component, not an array fragment rebuilt by
/// the root view. Its disclosure state survives entry insertion and reorder.
/// Rows are (key, node) pairs for the sidebar's one keyed container.
pub fn component(
  input : @rabbita.Val[Input],
  actions : Actions,
) -> @rabbita.Val[Array[(String, @html.Html)]] {
  let (state, emit) = @rabbita.create_state_with_input(
    input~,
    // A section born collapsed is stamped with the activation current at
    // birth, so the initial fold is not instantly revealed by it.
    init=(_, input) => {
      (
        {
          fold: if input.initially_collapsed {
            Folded(during=input.activation)
          } else {
            Open
          },
        },
        @cmd.none,
      )
    },
    update=(state, input, msg, _) => {
      match msg {
        // Toggle the fold the user sees: a stored fold currently overridden
        // by an activation reveal must fold on click, not silently flip to
        // open.
        Toggle =>
          (
            {
              fold: if state.folded(input) {
                Open
              } else {
                Folded(during=input.activation)
              },
            },
            @cmd.none,
          )
      }
    },
  )
  let entry_inputs = input.map(input => @vector.from_array(input.entries))
  let entry_rows = entry_inputs.assoc_by(
    (key, entry) => actions.entry_component(key, entry),
    by=entry => entry.key(),
  )
  state.map3(input, entry_rows, (state, input, entry_rows) => {
    let collapsed = state.folded(input)
    let mut class = if collapsed {
      "sidebar-heading section-heading collapsible collapsed"
    } else {
      "sidebar-heading section-heading collapsible"
    }
    if input.activation is Some(_) {
      class += " active"
    }
    let heading : Array[@html.Html] = [
      @html.span(class="sidebar-label", input.label),
    ]
    let rows : Array[(String, @html.Html)] = [
      (input.id.key(), @html.div(class~, on_click=emit(Toggle), heading)),
    ]
    if input.action is Some(action) {
      rows.push(
        (
          "\{input.id.key()}:action",
          @html.button(
            class="section-primary-action",
            type_="button",
            title=action.title,
            disabled=action.disabled,
            on_click=(actions.primary)(input.id),
            [
              @html.span(class="sidebar-icon", @icons.icon(@icons.icon_add)),
              @html.span(class="sidebar-label", action.title),
            ],
          ),
        ),
      )
    }
    if !collapsed {
      for group in entry_rows {
        for row in group {
          rows.push(row)
        }
      }
    }
    rows
  })
}

///|
pub extend Action with Debug::{to_repr}

///|
pub extend Action with Eq::{equal, not_equal}

///|
pub extend Entry with Debug::{to_repr}

///|
pub extend Entry with Eq::{equal, not_equal}

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
pub extend Placeholder with Debug::{to_repr}

///|
pub extend Placeholder with Eq::{equal, not_equal}

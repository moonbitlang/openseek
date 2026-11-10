///|
#derive(Debug, Eq, Hash)
pub(all) struct Id {
  source : String
  channel : String
}

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
#derive(Debug, Eq)
pub(all) struct Placeholder {
  id : String
  label : String
  class_name : String
  nested : Bool
  openable : Bool
  action : Action?
}

///|
#derive(Debug, Eq)
pub(all) enum Entry {
  Project(@project.Input)
  Conversation(@conversation.Input)
  Placeholder(Placeholder)
}

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
#derive(Debug, Eq)
pub(all) struct Action {
  title : String
  disabled : Bool
}

///|
#derive(Debug, Eq)
pub(all) enum SecondaryAction {
  ImportConversation
}

///|
fn tool_button(
  action : Action,
  icon : @html.Html,
  command : @cmd.Cmd,
) -> @html.Html {
  @html.button(
    class="sidebar-button sidebar-tool-button",
    type_="button",
    title=action.title,
    disabled=action.disabled,
    attrs=@html.Attrs::build().aria_label(action.title),
    on_click=command,
    [
      @html.span(class="sidebar-icon", icon),
      @html.span(class="sidebar-label", action.title),
    ],
  )
}

///|
fn SecondaryAction::button(
  self : SecondaryAction,
  id : Id,
  actions : Actions,
  locale : @i18n.Locale,
) -> @html.Html {
  match self {
    ImportConversation =>
      tool_button(
        { title: @messages.text(locale, ImportConversation), disabled: false, },
        @icons.icon(@icons.icon_chat_import),
        (actions.secondary)(id, self),
      )
  }
}

///|
#derive(Debug, Eq)
pub(all) struct Input {
  id : Id
  // Unlabeled sections expose their action below the sidebar search instead.
  label : String?
  // The active conversation's session id while this section holds the
  // focused chat; `None` otherwise. Same contract as
  // `@project.Input.activation`.
  activation : String?
  action : Action?
  secondary_actions : Array[SecondaryAction]
  entries : Array[Entry]
}

///|
pub fn Input::id(self : Input) -> Id {
  self.id
}

///|
pub(all) struct Actions {
  primary : (Id) -> @cmd.Cmd
  secondary : (Id, SecondaryAction) -> @cmd.Cmd
  placeholder : (String) -> @cmd.Cmd
  project : @project.Actions
  conversation : @conversation.Actions
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
    children.push(
      @html.span(
        class=if row.action is Some(_) {
          "sidebar-label sidebar-notice"
        } else {
          "sidebar-label"
        },
        row.label,
      ),
    )
    if row.action is Some(action) {
      children.push(
        @html.button(
          class="console-account-action",
          disabled=action.disabled,
          on_click=(self.placeholder)(row.id),
          action.title,
        ),
      )
    }
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
  locale : @rabbita.Val[@i18n.Locale],
  search : @rabbita.Val[@conversation.Search],
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
          @project.component(project_input, self.project, locale, search)
        }
        Conversation(initial) => {
          let conversation_input = input.map(entry => {
            match entry {
              Conversation(conversation) => conversation
              _ => initial
            }
          })
          @conversation.component(
            locale,
            conversation_input,
            self.conversation,
            search,
          )
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
#derive(Eq)
pub(all) struct RenderedSection {
  tools : @html.Html
  rows : Array[(String, @html.Html)]
}

///|
/// Keyed entries retain their component state across insertion and reorder.
pub fn component(
  input : @rabbita.Val[Input],
  actions : Actions,
  locale : @rabbita.Val[@i18n.Locale],
  search : @rabbita.Val[@conversation.Search],
) -> @rabbita.Val[RenderedSection] {
  let entry_inputs = input.map3(locale, search, (input, locale, search) => {
    @vector.from_array(input.entries.map(entry => (locale, entry, search)))
  })
  let entry_rows = entry_inputs.assoc_by(
    (key, entry) => {
      actions.entry_component(
        key,
        entry.map(pair => pair.1),
        entry.map(pair => pair.0),
        entry.map(parts => parts.2),
      )
    },
    by=entry => entry.1.key(),
  )
  input.map3(entry_rows, locale, (input, entry_rows, locale) => {
    let mut class = "sidebar-heading section-heading"
    if input.activation is Some(_) {
      class += " active"
    }
    let heading = if input.label is Some(label) {
      let children : Array[@html.Html] = [
        @html.span(class="sidebar-label section-label", label),
      ]
      if input.action is Some(action) {
        children.push(
          @html.button(
            class="section-primary-action",
            type_="button",
            title=action.title,
            disabled=action.disabled,
            attrs=@html.Attrs::build().aria_label(action.title),
            on_click=(actions.primary)(input.id),
            @icons.icon(@icons.icon_add),
          ),
        )
      }
      @html.div(class~, children)
    } else {
      @html.nothing
    }
    let tools : Array[@html.Html] = []
    if input.label is None && input.action is Some(action) {
      tools.push(
        tool_button(
          action,
          @icons.icon(@icons.icon_add),
          (actions.primary)(input.id),
        ),
      )
    }
    for action in input.secondary_actions {
      tools.push(action.button(input.id, actions, locale))
    }
    let rows : Map[String, @html.Html] = Map([])
    for group in entry_rows {
      for row in group {
        rows[row.0] = row.1
      }
    }
    {
      tools: @html.fragment(tools),
      rows: [
        (
          input.id.key(),
          @html.div(class="sidebar-group", [
            heading,
            @html.div(
              id=input.id.key() + ":content",
              class="sidebar-group-content",
              rows,
            ),
          ]),
        ),
      ],
    }
  })
}

///|
pub extend RenderedSection with Eq::{equal, not_equal}

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
pub extend SecondaryAction with Debug::{to_repr}

///|
pub extend SecondaryAction with Eq::{equal, not_equal}

///|
pub extend Placeholder with Debug::{to_repr}

///|
pub extend Placeholder with Eq::{equal, not_equal}

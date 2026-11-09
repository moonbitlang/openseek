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
/// A secondary section action, listed in the heading's menu.
#derive(Debug, Eq)
pub(all) enum MenuAction {
  ImportConversation
}

///|
fn MenuAction::entry(
  self : MenuAction,
  id : Id,
  actions : Actions,
  locale : @i18n.Locale,
) -> @action_menu.Entry {
  match self {
    ImportConversation =>
      Action({
        label: @messages.text(locale, ImportConversation),
        title: "",
        icon: Some(@icons.icon(@icons.icon_chat_import)),
        enabled: true,
        destructive: false,
        command: (actions.menu)(id, self),
      })
  }
}

///|
#derive(Debug, Eq)
pub(all) struct Input {
  id : Id
  label : String
  // The active conversation's session id while this section holds the
  // focused chat; `None` otherwise. Same contract as
  // `@project.Input.activation`.
  activation : String?
  action : Action?
  // Empty hides the heading's menu.
  menu : Array[MenuAction]
  entries : Array[Entry]
}

///|
pub fn Input::id(self : Input) -> Id {
  self.id
}

///|
pub(all) struct Actions {
  primary : (Id) -> @cmd.Cmd
  menu : (Id, MenuAction) -> @cmd.Cmd
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
/// Keyed entries retain their component state across insertion and reorder.
pub fn component(
  input : @rabbita.Val[Input],
  actions : Actions,
  locale : @rabbita.Val[@i18n.Locale],
  search : @rabbita.Val[@conversation.Search],
) -> @rabbita.Val[Array[(String, @html.Html)]] {
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
  let menu = input
    .map2(locale, (input, locale) => (input, locale))
    .switch_by(
      pair => {
        let (input, locale) = pair
        if input.menu.is_empty() {
          return @rabbita.Val::constant(@html.nothing)
        }
        let label = @messages.text(locale, MoreActions)
        @action_menu.dropdown(
          input.id.key(),
          {
            label,
            entries: input.menu.map(action => {
              action.entry(input.id, actions, locale)
            }),
          },
          class="section-primary-action section-menu-button",
          @icons.icon(@icons.icon_more),
        )
      },
      by=pair => Repr::Repr((pair.0.id, pair.0.menu, pair.1)).to_string(),
    )
  input.map3(entry_rows, menu, (input, entry_rows, menu) => {
    let mut class = "sidebar-heading section-heading"
    if input.activation is Some(_) {
      class += " active"
    }
    let heading : Array[@html.Html] = [
      @html.span(class="sidebar-label section-label", input.label),
    ]
    // Menu first, primary action last, matching project rows.
    if !input.menu.is_empty() {
      heading.push(menu)
    }
    if input.action is Some(action) {
      heading.push(
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
    let rows : Map[String, @html.Html] = Map([])
    for group in entry_rows {
      for row in group {
        rows[row.0] = row.1
      }
    }
    [
      (
        input.id.key(),
        @html.div(class="sidebar-group", [
          @html.div(class~, heading),
          @html.div(
            id=input.id.key() + ":content",
            class="sidebar-group-content",
            rows,
          ),
        ]),
      ),
    ]
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
pub extend MenuAction with Debug::{to_repr}

///|
pub extend MenuAction with Eq::{equal, not_equal}

///|
pub extend Placeholder with Debug::{to_repr}

///|
pub extend Placeholder with Eq::{equal, not_equal}

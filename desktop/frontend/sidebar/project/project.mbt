///|
/// A project component key includes its source. Two sidebar sections may
/// point at the same directory, but they are independent UI branches and
/// must not share disclosure or preview state.
pub(all) struct Id {
  source : String
  channel : String
  root : String
} derive(Debug, Eq, Hash)

///|
pub fn Id::Id(source~ : String, channel~ : String, root~ : String) -> Id {
  { source, channel, root, }
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
pub fn Id::root(self : Id) -> String {
  self.root
}

///|
fn Id::subscription_key(self : Id) -> String {
  "sidebar-project-menu:\{self.source}:\{self.channel}:\{self.root}"
}

///|
/// The DOM child key for this project's folder row inside the sidebar's one
/// keyed container.
pub fn Id::key(self : Id) -> String {
  "project:\{self.source}:\{self.channel}:\{self.root}"
}

///|
pub(all) struct Input {
  id : Id
  title : String
  label : String
  // The active conversation's session id while this project holds the
  // focused chat; `None` otherwise. The value identifies the activation: a
  // fold made during one activation holds until a different one arrives.
  activation : String?
  can_start : Bool
  managed : Bool
  conversations : Array[@conversation.Input]
  empty_label : String?
} derive(Debug, Eq)

///|
pub fn Input::id(self : Input) -> Id {
  self.id
}

///|
pub(all) struct Actions {
  new_conversation : (Id) -> @cmd.Cmd
  open_settings : (Id) -> @cmd.Cmd
  detach : (Id) -> @cmd.Cmd
  conversation : @conversation.Actions
}

///|
priv enum Msg {
  ToggleDisclosure
  ShowMore
  OpenMenu(@action_menu.Anchor)
  CloseMenu
}

///|
/// A fold is stamped with the activation it was made under, so revealing is
/// edge-triggered without watching input transitions: only an activation
/// different from the stamped one forces the branch open.
priv enum Fold {
  Open
  Folded(during~ : String?)
} derive(Eq)

///|
priv struct State {
  fold : Fold
  preview_limit : Int
  menu : @action_menu.Anchor?
} derive(Eq)

///|
const PreviewLimit : Int = 5

///|
const PreviewStep : Int = 7

///|
fn State::update(self : State, input : Input, msg : Msg) -> State {
  match msg {
    ToggleDisclosure =>
      // Toggle the fold the user sees: a stored fold currently overridden by
      // an activation reveal must fold on click, not silently flip to open.
      if self.folded(input) {
        { ..self, fold: Open, menu: None, }
      } else {
        // Folding ends the current preview session. Opening the project again
        // starts from the compact five-chat view, even after several Show
        // more clicks.
        {
          fold: Folded(during=input.activation),
          preview_limit: PreviewLimit,
          menu: None,
        }
      }
    ShowMore => { ..self, preview_limit: self.next_preview_limit(input), }
    OpenMenu(anchor) => { ..self, menu: Some(anchor), }
    CloseMenu => { ..self, menu: None, }
  }
}

///|
/// Whether the branch renders folded. A stored fold holds — including while
/// its own activation stays current, so the disclosure button works inside
/// the active project — and only a new activation reveals the branch:
/// jumping into a folded project opens it to show where you are.
fn State::folded(self : State, input : Input) -> Bool {
  guard self.fold is Folded(during~) else { return false }
  input.activation is None || input.activation == during
}

///|
fn State::conversation_visible(
  self : State,
  index : Int,
  active : Bool,
) -> Bool {
  index < self.preview_limit || active
}

///|
/// Advance past seven conversations that are actually hidden. The active
/// chat may already be visible beyond the compact prefix; skipping it here
/// means one click still reveals seven new rows rather than six.
fn State::next_preview_limit(self : State, input : Input) -> Int {
  let mut limit = self.preview_limit
  let mut revealed = 0
  while limit < input.conversations.length() && revealed < PreviewStep {
    if !input.conversations[limit].active {
      revealed += 1
    }
    limit += 1
  }
  limit
}

///|
fn State::has_hidden_conversation(self : State, input : Input) -> Bool {
  for index = self.preview_limit
      index < input.conversations.length()
      index = index + 1 {
    if !input.conversations[index].active {
      return true
    }
  }
  false
}

///|
fn Input::menu_id(self : Input) -> String {
  self.id.key() + ":actions"
}

///|
fn Input::menu_trigger_id(self : Input) -> String {
  self.id.key() + ":actions-trigger"
}

///|
fn Input::menu_entries(
  self : Input,
  actions : Actions,
) -> Array[@action_menu.Entry] {
  [
    Action({
      label: "Workspace settings",
      title: "Defaults for new chats in this workspace",
      icon: Some(@icons.icon(@icons.icon_settings_gear)),
      enabled: true,
      destructive: false,
      command: (actions.open_settings)(self.id),
    }),
    Action({
      label: "Detach project",
      title: "Detach this project — its files and sessions stay",
      icon: Some(@icons.icon(@icons.icon_close)),
      enabled: true,
      destructive: false,
      command: (actions.detach)(self.id),
    }),
  ]
}

///|
fn Actions::conversation_component(
  self : Actions,
  _id : @conversation.Id,
  input : @rabbita.Val[@conversation.Input],
) -> @rabbita.Val[Array[(String, @html.Html)]] {
  @conversation.component(input, self.conversation)
}

///|
/// One keyed project component owns disclosure, compact-preview, and menu
/// state. Those values therefore cannot leak to an equal path rendered by a
/// different sidebar source. Rows are (key, node) pairs for the sidebar's one
/// keyed container.
pub fn component(
  input : @rabbita.Val[Input],
  actions : Actions,
) -> @rabbita.Val[Array[(String, @html.Html)]] {
  let (state, emit) = @rabbita.create_state_with_input(
    input~,
    init=(_, _) => {
      ({ fold: Open, preview_limit: PreviewLimit, menu: None, }, @cmd.none)
    },
    update=(state, input, msg, _) => (state.update(input, msg), @cmd.none),
    subscriptions=(state, input, emit) => {
      if state.menu is Some(_) {
        @action_menu.dismiss_subscription(
          input.id.subscription_key(),
          input.menu_trigger_id(),
          emit.map((_ : Unit) => CloseMenu),
        )
      } else {
        @sub.none
      }
    },
  )
  let conversation_inputs = input.map(input => {
    @vector.from_array(input.conversations)
  })
  let conversation_rows = conversation_inputs.assoc_by(
    (id, conversation) => actions.conversation_component(id, conversation),
    by=conversation => conversation.id(),
  )
  state.map3(input, conversation_rows, (state, input, conversation_rows) => {
    let collapsed = state.folded(input)
    let mut class = if collapsed {
      "workspace-row collapsible collapsed"
    } else {
      "workspace-row collapsible"
    }
    if input.activation is Some(_) {
      class += " active"
    }
    if state.menu is Some(_) {
      class += " menu-open"
    }
    let row_children : Array[@html.Html] = [
      @html.button(
        class="workspace-disclosure",
        type_="button",
        title=input.title,
        on_click=emit(ToggleDisclosure),
        attrs=@html.Attrs::build().aria_expanded((!collapsed).to_string()),
        [
          @html.span(
            class="sidebar-icon",
            @icons.icon(
              if collapsed {
                @icons.icon_folder
              } else {
                @icons.icon_folder_opened
              },
            ),
          ),
          @html.span(class="sidebar-label", input.label),
        ],
      ),
    ]
    if input.managed {
      row_children.push(
        @html.button(
          class=if state.menu is Some(_) {
            "row-archive workspace-menu-button open"
          } else {
            "row-archive workspace-menu-button"
          },
          type_="button",
          title="More actions",
          attrs=@action_menu.button_attrs(
            input.menu_id(),
            input.menu_trigger_id(),
            state.menu is Some(_),
            emit.map(anchor => OpenMenu(anchor)),
            emit(CloseMenu),
          ).aria_label("Workspace actions"),
          @icons.icon(@icons.icon_more),
        ),
      )
    }
    if input.can_start {
      row_children.push(
        @html.button(
          class="row-archive",
          type_="button",
          title="New conversation in this project",
          attrs=@html.Attrs::build().on_click(event => {
            event.stop_propagation()
            (actions.new_conversation)(input.id)
          }),
          @icons.icon(@icons.icon_add),
        ),
      )
    }
    if input.managed && state.menu is Some(anchor) {
      row_children.push(
        @action_menu.Menu::{
          id: input.menu_id(),
          trigger_id: input.menu_trigger_id(),
          label: "Workspace actions",
          anchor,
          entries: input.menu_entries(actions),
          dismiss: emit(CloseMenu),
        }.render(),
      )
    }
    let rows : Array[(String, @html.Html)] = [
      (input.id.key(), @html.div(class~, title=input.title, row_children)),
    ]
    if collapsed {
      return rows
    }
    if conversation_rows.length() == 0 && input.empty_label is Some(label) {
      rows.push(
        (
          "\{input.id.key()}:empty",
          @html.div(class="conversation-row placeholder nested", [
            @html.span(class="row-twisty spacer", ""),
            @html.span(class="sidebar-label", label),
          ]),
        ),
      )
      return rows
    }
    for index = 0; index < conversation_rows.length(); index = index + 1 {
      let group = conversation_rows[index]
      if state.conversation_visible(index, input.conversations[index].active) {
        for row in group {
          rows.push(row)
        }
      }
    }
    if state.has_hidden_conversation(input) {
      rows.push(
        (
          "\{input.id.key()}:more",
          @html.button(
            class="project-show-more",
            type_="button",
            title="Show more chats in this project",
            on_click=emit(ShowMore),
            "Show more",
          ),
        ),
      )
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

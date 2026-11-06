///|
/// A project component key includes its source. Two sidebar sections may
/// point at the same directory, but they are independent UI branches and
/// must not share disclosure or preview state.
#derive(Debug, Eq, Hash)
pub(all) struct Id {
  source : String
  channel : String
  root : String
}

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
/// The DOM child key for this project's branch.
pub fn Id::key(self : Id) -> String {
  "project:\{self.source}:\{self.channel}:\{self.root}"
}

///|
#derive(Debug, Eq)
pub(all) struct Host {
  name : String
  online : Bool
  details : Bool
}

///|
#derive(Debug, Eq)
pub(all) struct Input {
  id : Id
  title : String
  label : String
  host : Host?
  // The active conversation's session id while this project holds the
  // focused chat; `None` otherwise. The value identifies the activation: a
  // fold made during one activation holds until a different one arrives.
  activation : String?
  can_start : Bool
  managed : Bool
  conversations : Array[@conversation.Input]
}

///|
pub fn Input::id(self : Input) -> Id {
  self.id
}

///|
pub(all) struct Actions {
  new_conversation : (Id) -> @cmd.Cmd
  open_settings : (Id) -> @cmd.Cmd
  detach : (Id) -> @cmd.Cmd
  host_details : (Id) -> @cmd.Cmd
  conversation : @conversation.Actions
}

///|
priv enum Msg {
  ToggleDisclosure
  ShowMore
}

///|
/// A fold is stamped with the activation it was made under, so revealing is
/// edge-triggered without watching input transitions: only an activation
/// different from the stamped one forces the branch open.
#derive(Eq)
priv enum Fold {
  Open
  Folded(during~ : String?, preview_limit~ : Int32)
}

///|
#derive(Eq)
priv struct State {
  fold : Fold
  preview_limit : Int32
}

///|
const PreviewLimit : Int32 = 5

///|
const PreviewStep : Int32 = 7

///|
fn State::update(self : State, input : Input, msg : Msg) -> State {
  match msg {
    ToggleDisclosure =>
      // Toggle the fold the user sees: a stored fold currently overridden by
      // an activation reveal must fold on click, not silently flip to open.
      if self.folded(input) {
        { ..self, fold: Open, }
      } else {
        // Keep the outgoing preview intact throughout the closing animation.
        // The next opening, including an activation reveal, starts at five.
        {
          fold: Folded(
            during=input.activation,
            preview_limit=self.presented_preview_limit(input),
          ),
          preview_limit: PreviewLimit,
        }
      }
    ShowMore => { ..self, preview_limit: self.next_preview_limit(input), }
  }
}

///|
/// Whether the branch renders folded. A stored fold holds — including while
/// its own activation stays current, so the disclosure button works inside
/// the active project — and only a new activation reveals the branch:
/// jumping into a folded project opens it to show where you are.
fn State::folded(self : State, input : Input) -> Bool {
  guard self.fold is Folded(during~, ..) else { return false }
  input.activation is None || input.activation == during
}

///|
/// A row the compact preview must not hide: the conversation on screen, and
/// one whose title is being edited — a refresh can reorder the list under
/// the field.
fn stays_visible(row : @conversation.Input) -> Bool {
  row.active || row.rename is Some(_)
}

///|
fn State::conversation_visible(
  self : State,
  input : Input,
  index : Int32,
  stays_visible : Bool,
) -> Bool {
  index < self.presented_preview_limit(input) || stays_visible
}

///|
fn State::presented_preview_limit(self : State, input : Input) -> Int32 {
  if self.folded(input) && self.fold is Folded(preview_limit~, ..) {
    preview_limit
  } else {
    self.preview_limit
  }
}

///|
/// Advance past seven conversations that are actually hidden. A row may
/// already be visible beyond the compact prefix (`stays_visible`); skipping
/// it here means one click still reveals seven new rows rather than six.
fn State::next_preview_limit(self : State, input : Input) -> Int32 {
  let mut limit = self.preview_limit
  let mut revealed = 0
  while limit < input.conversations.length() && revealed < PreviewStep {
    if !stays_visible(input.conversations[limit]) {
      revealed += 1
    }
    limit += 1
  }
  limit
}

///|
fn State::has_hidden_conversation(self : State, input : Input) -> Bool {
  for index = self.presented_preview_limit(input)
      index < input.conversations.length()
      index = index + 1 {
    if !stays_visible(input.conversations[index]) {
      return true
    }
  }
  false
}

///|
pub fn Input::menu_entries(
  self : Input,
  actions : Actions,
  locale~ : @i18n.Locale = English,
) -> Array[@action_menu.Entry] {
  [
    Action({
      label: @messages.text(locale, WorkspaceSettings),
      title: @messages.text(locale, WorkspaceDefaults),
      icon: Some(@icons.icon(@icons.icon_settings_gear)),
      enabled: true,
      destructive: false,
      command: (actions.open_settings)(self.id),
    }),
    ..if self.host is Some({ details: true, .. }) {
      [
        @action_menu.Action({
          label: "Connection details",
          title: "Connection details",
          icon: Some(@icons.icon(@icons.icon_server)),
          enabled: true,
          destructive: false,
          command: (actions.host_details)(self.id),
        }),
      ]
    } else {
      []
    },
    Separator,
    Action({
      label: @messages.text(locale, DetachProject),
      title: @messages.text(locale, DetachDescription),
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
  locale : @rabbita.Val[@i18n.Locale],
  _id : @conversation.Id,
  input : @rabbita.Val[@conversation.Input],
  search : @rabbita.Val[@conversation.Search],
) -> @rabbita.Val[Array[(String, @html.Html)]] {
  @conversation.component(locale, input, self.conversation, search)
}

///|
/// One keyed project component owns disclosure and compact-preview state.
/// Those values therefore cannot leak to an equal path rendered by a
/// different sidebar source. The shared action-menu component owns the
/// context-menu overlay.
/// Conversations stay mounted inside the branch while it animates closed.
pub fn component(
  input : @rabbita.Val[Input],
  actions : Actions,
  locale : @rabbita.Val[@i18n.Locale],
  search : @rabbita.Val[@conversation.Search],
) -> @rabbita.Val[Array[(String, @html.Html)]] {
  let (state, emit) = @rabbita.create_state_with_input(
    input~,
    init=(_, _) => ({ fold: Open, preview_limit: PreviewLimit, }, @cmd.none),
    update=(state, input, msg, _) => (state.update(input, msg), @cmd.none),
  )
  let conversation_inputs = input.map3(locale, search, (input, locale, search) => {
    @vector.from_array(input.conversations.map(row => (locale, row, search)))
  })
  let conversation_rows = conversation_inputs.assoc_by(
    (id, conversation) => {
      actions.conversation_component(
        conversation.map(pair => pair.0),
        id,
        conversation.map(pair => pair.1),
        conversation.map(parts => parts.2),
      )
    },
    by=conversation => conversation.1.id(),
  )
  let menu = input
    .map2(locale, (input, locale) => (input, locale))
    .switch_by(
      pair => {
        let (input, locale) = pair
        if !input.managed {
          return @rabbita.Val::constant(@html.nothing)
        }
        @action_menu.dropdown(
          input.id.key(),
          {
            label: @messages.text(locale, WorkspaceActions),
            entries: input.menu_entries(actions, locale~),
          },
          class="row-archive workspace-menu-button",
          @icons.icon(@icons.icon_more),
        )
      },
      by=pair => {
        Repr::Repr((pair.0.id, pair.0.managed, pair.0.host, pair.1)).to_string()
      },
    )
  let input = input.map2(menu, (input, menu) => (input, menu))
  let rendered = state.map5(input, conversation_rows, locale, search, (
    state,
    pair,
    conversation_rows,
    locale,
    search,
  ) => {
    let (input, menu) = pair
    let searching = !search.query.is_blank()
    let collapsed = !searching && state.folded(input)
    let mut class = if collapsed {
      "workspace-row collapsible collapsed"
    } else {
      "workspace-row collapsible"
    }
    if input.activation is Some(_) {
      class += " active"
    }
    let row_children : Array[@html.Html] = [
      @html.div(
        class="workspace-content",
        @html.button(
          class="workspace-disclosure",
          type_="button",
          title=input.title,
          on_click=emit(ToggleDisclosure),
          attrs=@html.Attrs::build()
            .aria_expanded((!collapsed).to_string())
            .aria_controls(input.id.key() + ":content")
            // Pointer disclosure should not pin the hover controls open.
            // Keyboard focus still reveals them for Tab navigation.
            .on_mousedown(event => {
              if event.get_button() == 0 {
                event.prevent_default()
                // Preserve click-away saving before folding makes the row inert.
                if @dom.document()
                  .get_element_by_id(@conversation.RenameFieldId)
                  .to_option()
                  is Some(field) &&
                  field.to_html_element() is Some(field) {
                  field.blur()
                }
              }
              @cmd.none
            }),
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
      ),
    ]
    let trailing : Array[@html.Html] = []
    if input.host is Some(host) {
      let status = if host.online { "Connected" } else { "Disconnected" }
      trailing.push(
        @html.span(class="workspace-host", title=host.name + " · " + status, [
          @html.span(class="workspace-host-name", host.name),
          @html.span(
            class=if host.online {
              "workspace-host-status online"
            } else {
              "workspace-host-status offline"
            },
            attrs=@html.Attrs::build().aria_label(status),
            "",
          ),
        ]),
      )
    }
    let controls : Array[@html.Html] = []
    // Keep the action order aligned with the sidebar: menu first, new chat last.
    if input.managed {
      controls.push(menu)
    }
    if input.can_start {
      controls.push(
        @html.button(
          class="row-archive",
          type_="button",
          title=@messages.text(locale, NewProjectConversation),
          on_click=(actions.new_conversation)(input.id),
          attrs=@html.Attrs::build().aria_label(
            @messages.text(locale, NewProjectConversation),
          ),
          @icons.icon(@icons.icon_new_chat),
        ),
      )
    }
    trailing.push(@html.div(class="workspace-actions", controls))
    let context : @action_menu.RowContext = {
      target: input.id.key(),
      revision: Repr::Repr(
        (
          input.id,
          input.label,
          input.title,
          collapsed,
          input.managed,
          input.host,
          locale,
        ),
      ).to_string(),
      content: @html.fragment(row_children),
      definition: if input.managed {
        Some({
          label: @messages.text(locale, WorkspaceActions),
          entries: input.menu_entries(actions, locale~),
        })
      } else {
        None
      },
    }
    let rows : Map[String, @html.Html] = Map([])
    for index = 0; index < conversation_rows.length(); index = index + 1 {
      let group = conversation_rows[index]
      if searching ||
        state.conversation_visible(
          input,
          index,
          stays_visible(input.conversations[index]),
        ) {
        for row in group {
          rows[row.0] = row.1
        }
      }
    }
    if !searching && state.has_hidden_conversation(input) {
      rows["\{input.id.key()}:more"] = @html.button(
        class="project-show-more",
        type_="button",
        title=@messages.text(locale, ShowMoreChats),
        on_click=emit(ShowMore),
        @messages.text(locale, ShowMore),
      )
    }
    (
      input.id.key(),
      class,
      input.title,
      context,
      @html.div(class="workspace-trailing", trailing),
      @html.div(
        id=input.id.key() + ":content",
        class="project-conversations sidebar-branch-content",
        attrs=@html.Attrs::build()
          .aria_hidden(collapsed.to_string())
          .inert(collapsed),
        rows,
      ),
      collapsed,
    )
  })
  let context = @action_menu.row_context(rendered.map(row => row.3))
  rendered.map2(context, (row, context) => {
    let (id, class, title, _, trailing, children, collapsed) = row
    [
      (
        id,
        @html.div(
          class=if collapsed {
            "sidebar-project sidebar-branch collapsed"
          } else {
            "sidebar-project sidebar-branch"
          },
          [@html.div(class~, title~, [context, trailing]), children],
        ),
      ),
    ]
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
pub extend Host with Debug::{to_repr}

///|
pub extend Host with Eq::{equal, not_equal}

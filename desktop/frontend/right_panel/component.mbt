///|
/// Durable dock, document, and browser data stays in its domain package. This
/// value is the complete read-only input needed to render the right panel.
struct Input {
  dock : @dock.State
  file_panel : @fileeditor.State
  preview : @preview.State
  file_ctx : @fileeditor.Ctx
  is_desktop : Bool
  panel_available : Bool
} derive(Eq)

///|
pub fn Input::Input(
  dock~ : @dock.State,
  file_panel~ : @fileeditor.State,
  preview~ : @preview.State,
  file_ctx~ : @fileeditor.Ctx,
  is_desktop~ : Bool,
  panel_available~ : Bool,
) -> Input {
  { dock, file_panel, preview, file_ctx, is_desktop, panel_available }
}

///|
/// The panel reports only the visibility that affects the root layout.
pub struct Visibility {
  open : Bool
  menu_open : Bool
} derive(Eq)

///|
/// Commands owned by other packages are supplied explicitly. The panel never
/// depends on the root application's Model or Msg types.
pub(all) struct Actions {
  dock : @cmd.Emit[@dock.Msg]
  file_editor : @cmd.Emit[@fileeditor.Msg]
  browser_tab : @cmd.Cmd
  files : @cmd.Cmd
  review : @cmd.Cmd
  browser_input : @cmd.Emit[String]
  browser_submit : @cmd.Cmd
  browser_back : @cmd.Cmd
  browser_forward : @cmd.Cmd
  browser_reload : @cmd.Cmd
  browser_open_external : @cmd.Cmd
  external_link : @cmd.Emit[String]
  opened : @cmd.Cmd
  visibility : @cmd.Emit[Visibility]
}

///|
priv struct Model {
  open : Bool
  menu_open : Bool
} derive(Eq)

///|
pub(all) enum Msg {
  TogglePanel
  OpenPanel
  ExternalLink(String)
}

///|
priv enum ComponentMsg {
  External(Msg)
  ToggleMenu
  CloseMenu
}

///|
fn Model::update(
  self : Model,
  msg : ComponentMsg,
  external_opens : Bool,
) -> Model {
  match msg {
    External(TogglePanel) => { open: !self.open, menu_open: false }
    External(OpenPanel) => { open: true, menu_open: false }
    ToggleMenu => { ..self, menu_open: !self.menu_open }
    CloseMenu => { ..self, menu_open: false }
    External(ExternalLink(_)) =>
      if external_opens {
        { open: true, menu_open: false }
      } else {
        self
      }
  }
}

///|
/// Build the local visibility state and return independently updating Html.
pub fn component(
  input : @rabbita.Val[Input],
  actions : Actions,
) -> (@rabbita.Val[@html.Html], @cmd.Emit[Msg]) {
  let initial : Model = { open: false, menu_open: false }
  let (state, component_emit) = @rabbita.create_state_with_input(
    input~,
    init=(_, _) => (initial, @cmd.none),
    update=(state, input, msg, _) => {
      let next = state.update(
        msg,
        input.is_desktop &&
        input.panel_available &&
        msg is External(ExternalLink(url)) &&
        @preview.is_web_url(url),
      )
      let commands : Array[@cmd.Cmd] = []
      if next != state {
        commands.push(
          (actions.visibility)({ open: next.open, menu_open: next.menu_open }),
        )
      }
      if !state.open && next.open {
        commands.push(actions.opened)
      }
      if msg is External(ExternalLink(url)) {
        commands.push((actions.external_link)(url))
      }
      (next, @cmd.batch(commands))
    },
    subscriptions=(state, _, emit) => panel_subscriptions(state, emit),
  )
  (
    state.view2(input, (state, input) => {
      panel_view(input, state, component_emit, actions)
    }),
    component_emit.map(msg => External(msg)),
  )
}

///|
test "right-panel local state opens externally and closes with one toggle" {
  let state : Model = { open: false, menu_open: false }
  let opened = state.update(External(OpenPanel), false)
  let opened_again = state.update(External(OpenPanel), false)
  assert_true(opened.open)
  assert_true(opened_again.open)
  let closed = opened.update(External(TogglePanel), false)
  assert_false(closed.open)
  let menu = opened.update(ToggleMenu, false)
  assert_true(menu.menu_open)
  let menu_closed = menu.update(External(TogglePanel), false)
  assert_false(menu_closed.open)
  assert_false(menu_closed.menu_open)
  let linked = state.update(External(ExternalLink("https://example.com")), true)
  assert_true(linked.open)
}

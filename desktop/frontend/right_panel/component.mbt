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
pub(all) struct Visibility {
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
  ToggleMenu
  CloseMenu
  ExternalLink(String)
}

///|
fn Model::update(self : Model, msg : Msg, external_opens : Bool) -> Model {
  match msg {
    TogglePanel => { open: !self.open, menu_open: false }
    OpenPanel => { open: true, menu_open: false }
    ToggleMenu => { ..self, menu_open: !self.menu_open }
    CloseMenu => { ..self, menu_open: false }
    ExternalLink(_) =>
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
  let (state, emit) = @rabbita.create_state_with_input(
    input~,
    init=(_, _) => (initial, @cmd.none),
    update=(state, input, msg, _) => {
      let next = state.update(
        msg,
        input.is_desktop &&
        input.panel_available &&
        msg is ExternalLink(url) &&
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
      if msg is ExternalLink(url) {
        commands.push((actions.external_link)(url))
      }
      (next, @cmd.batch(commands))
    },
    subscriptions=(state, _, emit) => panel_subscriptions(state, emit),
  )
  (
    state.view2(input, (state, input) => panel_view(input, state, emit, actions)),
    emit,
  )
}

///|
test "right-panel local state closes its menu with the panel" {
  let state : Model = { open: false, menu_open: false }
  let opened = state.update(TogglePanel, false)
  let opened_again = state.update(TogglePanel, false)
  assert_true(opened.open)
  assert_true(opened_again.open)
  let menu = opened.update(ToggleMenu, false)
  assert_true(menu.menu_open)
  let closed = menu.update(TogglePanel, false)
  assert_false(closed.open)
  assert_false(closed.menu_open)
  let linked = state.update(ExternalLink("https://example.com"), true)
  assert_true(linked.open)
}

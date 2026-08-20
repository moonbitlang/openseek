///|
/// Durable dock, document, and browser data stays in its domain package. This
/// value is the complete read-only input needed to render the right panel.
struct Input {
  dock : @dock.State
  file_panel : @fileeditor.State
  preview : @preview.State
  file_ctx : @fileeditor.Ctx
  is_desktop : Bool
  menu_open : Bool
  expanded : Bool
} derive(Eq)

///|
pub fn Input::Input(
  dock~ : @dock.State,
  file_panel~ : @fileeditor.State,
  preview~ : @preview.State,
  file_ctx~ : @fileeditor.Ctx,
  is_desktop~ : Bool,
  menu_open~ : Bool,
  expanded~ : Bool,
) -> Input {
  { dock, file_panel, preview, file_ctx, is_desktop, menu_open, expanded }
}

///|
/// Commands owned by other packages are supplied explicitly. The panel never
/// depends on the root application's Model or Msg types.
pub(all) struct Actions {
  dock : @cmd.Emit[@dock.Msg]
  file_editor : @cmd.Emit[@fileeditor.Msg]
  browser_tab : @cmd.Cmd
  search : @cmd.Cmd
  files : @cmd.Cmd
  review : @cmd.Cmd
  browser_input : @cmd.Emit[String]
  browser_submit : @cmd.Cmd
  browser_back : @cmd.Cmd
  browser_forward : @cmd.Cmd
  browser_reload : @cmd.Cmd
  browser_open_external : @cmd.Cmd
  toggle_panel : @cmd.Cmd
  toggle_menu : @cmd.Cmd
  toggle_expanded : @cmd.Cmd
  close_menu : @cmd.Cmd
}

///|
/// Render the root-owned panel input directly. The panel has no local state or
/// document listeners: app shortcuts, menu dismissal, and URL requests belong
/// to the root application because their messages all change root state.
pub fn component(
  input : @rabbita.Val[Input],
  actions : Actions,
) -> @rabbita.Val[@html.Html] {
  input.map(input => panel_view(input, actions))
}

///|
pub extend Input with Eq::{equal, not_equal}

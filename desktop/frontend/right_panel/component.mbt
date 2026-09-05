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
  // The workflows the active conversation's snippets announced, for the
  // Workflows tab. Live-only state projected from the root's conversation.
  workflows : Array[@workflow.Run]
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
  workflows~ : Array[@workflow.Run],
) -> Input {
  {
    dock,
    file_panel,
    preview,
    file_ctx,
    is_desktop,
    menu_open,
    expanded,
    workflows,
  }
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
  workflows : @cmd.Cmd
  // Open one subagent's transcript: the child's session id, as its row
  // carries it.
  open_child : (String) -> @cmd.Cmd
  browser_input : @cmd.Emit[String]
  browser_submit : @cmd.Cmd
  browser_back : @cmd.Cmd
  browser_forward : @cmd.Cmd
  browser_reload : @cmd.Cmd
  browser_open_external : @cmd.Cmd
  toggle_panel : @cmd.Cmd
  toggle_menu : @cmd.Cmd
  toggle_expanded : @cmd.Cmd
  close_all_tabs : @cmd.Cmd
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
  let semantic_review = input.map(input => {
    @fileeditor.semantic_review_view(actions.file_editor, input.file_panel)
  })
  input.view2(semantic_review, (input, semantic_review) => {
    panel_view(input, actions, semantic_review~)
  })
}

///|
pub extend Input with Eq::{equal, not_equal}

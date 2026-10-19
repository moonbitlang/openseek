///|
/// Durable dock, document, and browser data stays in its domain package. This
/// value is the complete read-only input needed to render the right panel.
struct Input {
  dock : @dock.DockState
  file_panel : @fileeditor.State
  preview : @preview.State
  annotation : @preview.Annotation
  file_ctx : @fileeditor.Ctx
  is_desktop : Bool
  menu_open : Bool
  expanded : Bool
  reveal_label : String?
  github : @github.State
  // Session-scoped jobs, including retained history and the selected log.
  jobs : @jobs.State
  // The workflows the active conversation's snippets announced, for the
  // Workflows tab. Live-only state projected from the root's conversation.
  workflows : Array[@workflow.Run]
  // The strip's side chats, numbered as their tabs are labelled.
  side_chats : Array[SideChatTab]
} derive(Eq)

///|
/// One side chat in the strip. A side chat carries its conversation's title,
/// so its tab is named by its place among the strip's side-chat tabs.
pub(all) struct SideChatTab {
  owner : @interop.ConversationKey
  number : Int32
} derive(Eq)

///|
pub fn Input::Input(
  dock~ : @dock.DockState,
  file_panel~ : @fileeditor.State,
  preview~ : @preview.State,
  annotation~ : @preview.Annotation,
  file_ctx~ : @fileeditor.Ctx,
  is_desktop~ : Bool,
  menu_open~ : Bool,
  expanded~ : Bool,
  reveal_label~ : String?,
  github~ : @github.State,
  jobs~ : @jobs.State,
  workflows~ : Array[@workflow.Run],
  side_chats~ : Array[SideChatTab] = [],
) -> Input {
  {
    dock,
    file_panel,
    preview,
    annotation,
    file_ctx,
    is_desktop,
    menu_open,
    expanded,
    reveal_label,
    workflows,
    jobs,
    github,
    side_chats,
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
  github : @cmd.Cmd
  github_events : @cmd.Emit[@github.Msg]
  open_link : (String) -> @cmd.Cmd
  jobs : @cmd.Cmd
  job_events : @cmd.Emit[@jobs.Msg]
  workflows : @cmd.Cmd
  // Open one subagent's transcript: the child's session id, as its row
  // carries it.
  open_child : (String) -> @cmd.Cmd
  browser_annotation : @cmd.Emit[@preview.AnnotationMsg]
  browser_input : @cmd.Emit[String]
  browser_submit : @cmd.Cmd
  browser_back : @cmd.Cmd
  browser_forward : @cmd.Cmd
  browser_reload : @cmd.Cmd
  browser_open_external : @cmd.Cmd
  reveal_file : (String) -> @cmd.Cmd
  toggle_menu : @cmd.Cmd
  toggle_expanded : @cmd.Cmd
  close_tabs : @cmd.Emit[@dock.CloseSelection]
  close_menu : @cmd.Cmd
  tab_menu_changed : @cmd.Emit[Bool]
}

///|
/// Panel data stays root-owned; the shared action menu owns only its ephemeral
/// opening and focus state, resolving tab commands from the latest input.
pub fn component(
  locale : @rabbita.Val[@i18n.Locale],
  input : @rabbita.Val[Input],
  side_chat~ : @rabbita.Val[@html.Html],
  actions : Actions,
) -> @rabbita.Val[@html.Html] {
  let semantic_review = input.map2(locale, (input, locale) => {
    @fileeditor.semantic_review_view(
      locale~,
      actions.file_editor,
      input.file_panel,
    )
  })
  let localized_input = input.map2(locale, (input, locale) => (input, locale))
  let tab_menu = @action_menu.component(
    localized_input,
    (localized, target) => {
      let (input, locale) = localized
      @dock.tab_menu(
        owner=input.file_ctx.owner,
        locale~,
        input.dock,
        target,
        actions.dock,
        actions.close_tabs,
      )
    },
    on_open_change=actions.tab_menu_changed,
  )
  localized_input.view4(semantic_review, tab_menu, side_chat, (
    localized,
    semantic_review,
    tab_menu,
    side_chat,
  ) => {
    let (input, locale) = localized
    panel_view(locale~, input, actions, semantic_review~, tab_menu~, side_chat~)
  })
}

///|
pub extend Input with Eq::{equal, not_equal}

///|
pub extend SideChatTab with Eq::{equal, not_equal}

///|
const ConversationTransferTarget = "conversation-transfer"

///|
fn Model::session_import_target(self : Model) -> @session_import.Target? {
  let selected = if self.screen is Chat {
    self.conversation_selection()
  } else {
    None
  }
  let workspace = match selected {
    Some(selection) => Some(selection.workspace)
    None =>
      if self.sidebar_mode is WorkMode {
        self.focused_device().bind(dev => dev.active_project)
      } else {
        None
      }
  }
  guard workspace is Some(workspace) &&
    self.focused_device() is Some(dev) &&
    dev.projects.contains(workspace) &&
    !dev.is_chat_workspace(workspace) else {
    return None
  }
  Some({
    channel: self.focused,
    connection_generation: self.focused_connection_generation(),
    workspace: workspace.path,
    worktree_of: selected.map(selection => selection.session),
  })
}

///|
fn Model::conversation_transfer_input(
  self : Model,
) -> (
  @i18n.Locale,
  Bool,
  Bool,
  (@interop.ChannelId, @protocol.SessionExportPayload)?,
) {
  let source = match self.chat_column() {
    Transcript(conversation=conv, ..) if self.screen is Chat &&
      !conv.messages.is_empty() =>
      Some(
        (
          conv.device,
          @protocol.SessionExportPayload::{
            session: conv.session_id,
            workspace: conv.project().path,
            title: self.selected_conversation_title(),
            archived: conv.is_archived_read_only(),
          },
        ),
      )
    _ => None
  }
  (
    self.locale,
    self.screen is Chat,
    self.session_import_target() is Some(_),
    source,
  )
}

///|
fn conversation_transfer_button(locale : @i18n.Locale) -> @html.Html {
  @rui.popover_trigger(
    id=ConversationTransferTarget + ":actions-trigger",
    target_id=ConversationTransferTarget + ":actions-content",
    class="panel-toggle",
    title=shell_text(locale, ConversationTransfer),
    attrs=@action_menu.button_attrs(
      ConversationTransferTarget,
      align_right=false,
    ).aria_label(shell_text(locale, ConversationTransfer)),
    @icons.icon(@icons.icon_more),
  )
}

///|
/// The menu has dismissed before this runs. Focus its durable trigger so the
/// modal can restore focus there when it closes.
fn open_conversation_transfer(command : @cmd.Cmd) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    if @dom.document()
      .get_element_by_id(ConversationTransferTarget + ":actions-trigger")
      .to_option()
      is Some(element) &&
      element.to_html_element() is Some(button) {
      button.focus()
    }
    scheduler.add(command)
  })
}

///|
fn conversation_transfer_menu(
  emit : @cmd.Emit[Msg],
  input : (
    @i18n.Locale,
    Bool,
    Bool,
    (@interop.ChannelId, @protocol.SessionExportPayload)?,
  ),
  target : String,
) -> @action_menu.Definition? {
  let (locale, visible, can_import, source) = input
  guard visible && target == ConversationTransferTarget else { return None }
  let entries : Array[@action_menu.Entry] = []
  entries.push(
    Action({
      label: shell_text(locale, ExportConversation),
      title: "",
      icon: Some(icon(icon_chat_export)),
      enabled: source is Some(_),
      destructive: false,
      command: match source {
        Some((channel, source)) =>
          open_conversation_transfer(emit(OpenExport(channel, source)))
        None => @cmd.none
      },
    }),
  )
  entries.push(
    Action({
      label: shell_text(locale, ImportConversation),
      title: "",
      icon: Some(@icons.icon(@icons.icon_chat_import)),
      enabled: can_import,
      destructive: false,
      command: open_conversation_transfer(emit(OpenSessionImport)),
    }),
  )
  Some({ label: shell_text(locale, ConversationTransfer), entries, })
}

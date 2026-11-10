///|
const ConversationTransferTarget = "conversation-transfer"

///|
fn Model::session_import_target(
  self : Model,
  channel : @interop.ChannelId,
  workspace : @common.Uri,
) -> @session_import.HostTarget? {
  guard self.device_state(channel) is Some(dev) &&
    dev.projects.contains(workspace) &&
    !dev.is_chat_workspace(workspace) else {
    return None
  }
  Some({
    channel,
    connection_generation: dev.connection_generation,
    workspace: workspace.path,
    worktree_of: None,
  })
}

///|
/// The signed-in account whose Cloud chats this page shows.
fn Model::cloud_account(self : Model) -> String? {
  guard self.account is Some(account) &&
    self.cloud.user_id == Some(account.user.user_id) else {
    return None
  }
  self.cloud.user_id
}

///|
#derive(Eq)
priv struct ConversationExportSource {
  channel : @interop.ChannelId
  payload : @protocol.SessionExportPayload
}

///|
#derive(Eq)
priv struct ConversationTransferInput {
  locale : @i18n.Locale
  visible : Bool
  export_source : ConversationExportSource?
}

///|
fn Model::conversation_transfer_input(
  self : Model,
) -> ConversationTransferInput {
  let source = match self.chat_column() {
    Transcript(conversation=conv, ..) if self.screen is Chat &&
      !conv.messages.is_empty() =>
      Some(ConversationExportSource::{
        channel: conv.device,
        payload: {
          session: conv.session_id,
          workspace: conv.project().path,
          title: self.selected_conversation_title(),
          archived: conv.is_archived_read_only(),
        },
      })
    _ => None
  }
  { locale: self.locale, visible: self.screen is Chat, export_source: source, }
}

///|
fn conversation_transfer_button(locale : @i18n.Locale) -> @html.Html {
  @rui.popover_trigger(
    id=ConversationTransferTarget + ":actions-trigger",
    target_id=ConversationTransferTarget + ":actions-content",
    variant=Ghost,
    size=IconXs,
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
  input : ConversationTransferInput,
  target : String,
) -> @action_menu.Definition? {
  let { locale, visible, export_source, } = input
  guard visible && target == ConversationTransferTarget else { return None }
  let entries : Array[@action_menu.Entry] = []
  entries.push(
    Action({
      label: shell_text(locale, ExportConversation),
      title: "",
      icon: Some(icon(icon_chat_export)),
      enabled: export_source is Some(_),
      destructive: false,
      command: match export_source {
        Some({ channel, payload, }) =>
          open_conversation_transfer(emit(OpenExport(channel, payload)))
        None => @cmd.none
      },
    }),
  )
  Some({ label: shell_text(locale, ConversationTransfer), entries, })
}

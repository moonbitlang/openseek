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
fn Conversation::export_source(
  self : Conversation,
  title : String,
) -> @protocol.SessionExportPayload {
  {
    session: self.session_id,
    workspace: self.project().path,
    title,
    archived: self.is_archived_read_only(),
  }
}

///|
fn Model::conversation_export_button(
  self : Model,
  dispatch : @cmd.Emit[Msg],
) -> @html.Html {
  let command = match self.chat_column() {
    Transcript(conversation=conv, ..) if self.screen is Chat &&
      !conv.messages.is_empty() =>
      Some(
        dispatch(
          OpenExport(
            conv.device,
            conv.export_source(self.selected_conversation_title()),
          ),
        ),
      )
    _ => None
  }
  @html.button(
    class="panel-toggle",
    title=shell_text(self.locale, ExportConversation),
    attrs=@html.Attrs::build().aria_label(
      shell_text(self.locale, ExportConversation),
    ),
    disabled=command is None,
    on_click=command.unwrap_or(@cmd.none),
    icon(icon_chat_export),
  )
}

///|
/// Every load state uses the same catalog label as the sidebar. Only an
/// unlisted conversation needs a temporary label from its local state. Fresh
/// chats keep the same default title before typing and until the first send.
fn Model::selected_conversation_title(self : Model) -> String {
  guard self.conversation_selection() is Some(selected) else {
    return "SeekMoon"
  }
  if self.device_state(selected.channel) is Some(device) {
    let items = match selected.record {
      LiveRecord => device.sessions
      ArchivedRecord => device.archived
    }
    for item in items {
      if item.id == selected.session && item.workspace == selected.workspace {
        return session_item_label(item)
      }
    }
  }
  if self.find_conversation(selected.channel, selected.session) is Some(conv) &&
    conv.project() == selected.workspace &&
    conv.record == selected.record {
    return if self.conversation_is_new_chat(conv) {
      shell_text(self.locale, NewChatLabel)
    } else {
      unlisted_conversation_label(locale=self.locale, conv)
    }
  }
  selected.session
}

///|
/// Work conversations show their project before the title. Managed Chats
/// omit the storage workspace; classification follows the conversation,
/// independent of which sidebar list the user is browsing.
fn Model::conversation_heading(
  self : Model,
  channel : @interop.ChannelId,
  title : String,
  tooltip : String,
  workspace : @common.Uri?,
) -> Array[@html.Html] {
  let items : Array[@html.Html] = []
  if workspace is Some(workspace) &&
    !self
    .device_state(channel)
    .map_or(false, dev => dev.is_chat_workspace(workspace)) {
    items.push(
      @html.span(class="topbar-workspace", title=workspace.path, [
        icon(icon_folder),
        @html.span(class="topbar-workspace-label", @resource.label(workspace)),
        @html.span(
          class="topbar-workspace-separator",
          attrs=@html.Attrs::build().aria_hidden("true"),
          "/",
        ),
      ]),
    )
  }
  items.push(@html.h1(class="topbar-title", title=tooltip, title))
  items
}

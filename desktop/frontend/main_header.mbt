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

///|
/// Loading and failed views identify the selected conversation, never the
/// previously mounted transcript. Use the same catalog label as the sidebar.
fn Model::pending_conversation_title(self : Model) -> String {
  guard self.selected_conversation is Some(selected) else { return "SeekMoon" }
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
    conv.project() == selected.workspace {
    return conversation_title(locale=self.locale, conv)
  }
  selected.session
}

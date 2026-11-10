// Settings' archived-conversations page. Archived records live in each
// store's `archived` twin and arrive with the host's archived reply, not the
// live list; Codex keeps its own archived tasks and Cloud its archived chats.
// The page groups all of them the way the sidebar groups live conversations.

///|
/// Every archived conversation this window can reach: Cloud chats first, then
/// one group per project, then rows whose project could not be resolved. A parent
/// and its archived sub-run records are one conversation, so only roots get a
/// row; restoring or deleting one moves the complete family together. An old
/// orphan child still owns a row and can therefore be restored. Side chats
/// are archived with their conversation and come back with it, so they are
/// not rows either. The desktop
/// window lists every device, as its sidebar does; a browser page lists its
/// own.
fn Model::archived_chat_groups(self : Model) -> Array[@archived_chats.Group] {
  let chats : Array[@conversation.Input] = []
  let other : Array[@conversation.Input] = []
  let projects : Array[(String, String, Array[@conversation.Input])] = []
  let place = (dev : DeviceState, row : @conversation.Input) => {
    let workspace = row.id
      .root()
      .bind(path => @resource.of_path(dev.channel, path))
    guard workspace is Some(workspace) else {
      other.push(row)
      return
    }
    // Retired standalone chats stay on disk but out of every catalog.
    if dev.is_chat_workspace(workspace) {
      return
    }
    let key = dev.channel.uri_authority() + "\n" + workspace.path
    match projects.search_by(entry => entry.0 == key) {
      Some(index) => projects[index].2.push(row)
      None => {
        let label = @resource.label(workspace)
        // The desktop window lists several devices together; a browser page
        // shows only its own.
        let label = if !self.is_desktop || dev.channel == Local {
          label
        } else {
          self.console.roster
          .iter()
          .find_first(host => host.id == dev.channel.device_id())
          .map_or(label, host => host.name + " · " + label)
        }
        projects.push((key, label, [row]))
      }
    }
  }
  let devices = if self.is_desktop && !self.devices.is_empty() {
    self.devices
  } else {
    self.focused_device().map_or([], dev => [dev])
  }
  for dev in devices {
    let channel = dev.channel.uri_authority()
    let archived = dev.archived.filter(item => {
      @protocol.side_chat_parent(item.id) is None
    })
    for tree in @transcript.session_tree(archived) {
      let item = tree.item
      place(dev, {
        id: @conversation.Id(
          source=@conversation.OpenSeekArchived,
          channel~,
          conversation=item.id,
          root=item.workspace.path,
        ),
        title: item.id,
        label: session_item_label(item),
        nested: false,
        subrun: false,
        active: false,
        loading: false,
        load_failed: false,
        running: false,
        openable: true,
        rename: None,
        run_mark: @conversation.NoRunMark,
        trailing: [
          @conversation.Restore(title=shell_text(self.locale, RestoreHint)),
          @conversation.Delete(
            title=shell_text(self.locale, DeleteArchivedHint),
          ),
        ],
        children: [],
      })
    }
    // Codex state mirrors the focused device only.
    if dev.channel == self.focused {
      for
        entry in self.codex.archived_sidebar_entries(
          locale=self.locale,
          dev.channel,
        ) {
        if entry is @section.Conversation(row) {
          place(dev, row)
        }
      }
    }
  }
  // Cloud chats belong to the signed-in account rather than to a device.
  for row in ordered_by_recency(self.cloud_chat_rows(archived=true)) {
    chats.push(row)
  }
  let groups : Array[@archived_chats.Group] = []
  if !chats.is_empty() {
    groups.push({ kind: Chats, rows: chats, })
  }
  for project in projects {
    groups.push({ kind: Project(project.1), rows: project.2, })
  }
  if !other.is_empty() {
    groups.push({ kind: Other, rows: other, })
  }
  groups
}

///|
/// Archived rows route through the same dispatcher as sidebar conversations.
fn archived_chats_actions(dispatch : @cmd.Emit[Msg]) -> @archived_chats.Actions {
  let sidebar = SidebarDispatcher::{ emit: dispatch, }
  {
    open: id => sidebar.conversation_open(id),
    restore: id => sidebar.conversation_restore(id),
    delete: id => sidebar.conversation_delete(id),
  }
}

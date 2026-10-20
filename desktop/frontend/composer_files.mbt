///|
/// Open editor tabs that still name a usable file. A deleted tab remains a
/// bookmark in the editor strip, but neither Quick Open nor a composer mention
/// may offer it as a destination.
fn Model::live_editor_files(self : Model) -> Array[@pathx.Relative] {
  @dock.file_paths(self.dock)
  .filter(path => {
    !(self.file_panel.docs.get(path) is Some(doc) &&
    doc.state is @fileeditor.TabDeleted)
  })
  .filter_map(path => self.workspace_relative(path))
}

///|
/// Build the bounded workspace-file candidate set supplied to `@composer`.
/// The shared index provides paths while open tabs remain immediately useful
/// during index refreshes.
fn Model::file_search(self : Model) -> @files.Search {
  if self.cloud_selected() && self.file_panel.owner != self.cloud_identity() {
    return @files.Search([], [], None)
  }
  let indexed = match self.file_panel.index {
    @fileeditor.IndexReady(files~, ..) => files
    _ => []
  }
  @files.Search(indexed, self.live_editor_files(), self.active_workspace_file())
}

///|
/// Project-only consumers derive a relative name without restricting document opens.
fn Model::workspace_relative(
  self : Model,
  file : @common.Uri,
) -> @pathx.Relative? {
  if self.cloud_selected() {
    return file_ctx(self).root().bind(root => @resource.relative_to(file, root))
  }
  self
  .active_checkout()
  .bind(active => active.placement)
  .bind(placement => placement.checkout_root())
  .bind(root => @resource.relative_to(file, root))
}

///|
fn Model::workspace_resource(
  self : Model,
  path : @pathx.Relative,
) -> @common.Uri? {
  self
  .active_checkout()
  .bind(active => active.placement)
  .bind(placement => placement.checkout_root())
  .map(root => @resource.join_relative(root, path))
}

///|
fn Model::active_workspace_file(self : Model) -> @pathx.Relative? {
  @dock.active_file(self.dock).bind(file => self.workspace_relative(file))
}

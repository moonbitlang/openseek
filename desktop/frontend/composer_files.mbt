///|
/// Build the bounded workspace-file candidate set supplied to `@composer`.
/// The shared index provides paths while open tabs remain immediately useful
/// during index refreshes.
fn Model::file_search(self : Model) -> @files.Search {
  let indexed = match self.file_panel.index {
    @fileeditor.IndexReady(files~, ..) => files
    _ => []
  }
  @files.Search(
    indexed,
    quick_open_open_files(self),
    @dock.active_file(self.dock),
  )
}

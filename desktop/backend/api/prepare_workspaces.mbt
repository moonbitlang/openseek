///|
/// First-launch and migration work on the workspace registry.
/// `ApiState::start_services` runs this before it starts anything that can
/// serve a client, so the first `workspace.list` a page sees already reflects
/// it.
async fn prepare_workspaces() -> Unit {
  // A fresh install has no workspaces at all. Attach the default one before
  // anything can serve a workspace list, so the first page to connect
  // already has somewhere to work. This runs exactly once per registry: a
  // user who later detaches it does not get it back.
  let default_workspace = @workspaces.initialize() catch {
    error => {
      // An unwritable Documents folder must not stop the app — the user can
      // still attach a project by hand.
      if @xlog.error() is Some(event) {
        event
        ..write_object_begin()
        ..write_object_field("message", "default workspace setup failed")
        ..write_object_field("error", @debug.render(Repr(error)))
        .write_object_end()
      }
      None
    }
  }
  if default_workspace is Some(dir) {
    if @xlog.info() is Some(event) {
      event
      ..write_object_begin()
      ..write_object_field("message", "default workspace attached")
      ..write_object_field("path", dir.to_string())
      .write_object_end()
    }
  }
  // Conversations the desktop used to keep in the global store predate
  // workspaces owning every record. Move them into the default workspace so
  // they stay listed; a failure leaves them where they are for a later launch.
  let migrated = @engine.migrate_global_store() catch {
    error => {
      if @xlog.error() is Some(event) {
        event
        ..write_object_begin()
        ..write_object_field("message", "global store migration failed")
        ..write_object_field("error", @debug.render(Repr(error)))
        .write_object_end()
      }
      0
    }
  }
  if migrated > 0 {
    if @xlog.info() is Some(event) {
      event
      ..write_object_begin()
      ..write_object_field(
        "message", "migrated conversations from the global store",
      )
      ..write_object_field("count", migrated)
      .write_object_end()
    }
  }
}

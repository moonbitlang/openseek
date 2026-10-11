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
      @xlog.error() <?
        {
          "message": "default workspace setup failed",
          "error": @debug.render(Repr(error)),
        }
      None
    }
  }
  if default_workspace is Some(dir) {
    @xlog.info() <?
      { "message": "default workspace attached", "path": dir.to_string() }
  }
  // Conversations the desktop used to keep in the global store predate
  // workspaces owning every record. Move them into the default workspace so
  // they stay listed; a failure leaves them where they are for a later launch.
  let migrated = @engine.migrate_global_store() catch {
    error => {
      @xlog.error() <?
        {
          "message": "global store migration failed",
          "error": @debug.render(Repr(error)),
        }
      0
    }
  }
  if migrated > 0 {
    @xlog.info() <?
      {
        "message": "migrated conversations from the global store",
        "count": migrated,
      }
  }
}

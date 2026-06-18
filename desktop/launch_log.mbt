// Launch diagnostics for the packaged app: a double-clicked bundle has no
// terminal, so startup problems would otherwise vanish. Both processes log to
// `openseek-desktop.log` in the per-user runtime dir — the bundle directory
// is read-only on end-user installs (App Translocation mounts it so), which
// is exactly when launch diagnostics matter, so the log lives with the rest
// of the runtime state. xlog's file handler opens in append mode, so the
// host and the framework child can share the file safely.

///|
async fn launch_logger() -> @xlog.Logger {
  guard @extension.prepared_runtime_dir() is Some(dir) else {
    fail("cannot determine the per-user runtime directory")
  }
  @xlog.global().set_handler(
    @xlog.File(dir.join("openseek-desktop.log").to_string()),
  )
  @xlog.global().set_level(Debug)
  @xlog.global()
}

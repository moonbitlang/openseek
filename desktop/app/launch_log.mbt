// Launch diagnostics for the packaged app: a double-clicked bundle has no
// terminal, so startup problems would otherwise vanish. Both processes log to
// `openseek-desktop.log` in the per-user runtime dir — the bundle directory
// is read-only on end-user installs (App Translocation mounts it so), which
// is exactly when launch diagnostics matter, so the log lives with the rest
// of the runtime state. `@log_file` opens it in append mode and writes each
// record as one line, so the host and the framework child can share the file
// safely.

///|
/// Run `body` with every `@logging` record, down to `Debug`, appended to the
/// launch log.
async fn with_launch_log(executable : String, body : async () -> Unit) -> Unit {
  guard @host.prepared_runtime_dir(executable) is Some(dir) else {
    fail("cannot determine the per-user runtime directory")
  }
  let path = dir.join("openseek-desktop.log").to_string()
  // Proton's native shutdown path can run from `atexit`, after MoonBit has
  // already left the app pump. Give it the same append-only JSONL sink so a
  // missing MoonBit "end" record and the native CEF state can be correlated.
  @env.set_env_var("OPENSEEK_DESKTOP_LOG", path)
  @log_file.with_log_file(path, log => {
    @logging.set_sink(record => log.append(record))
    @logging.set_level(Debug)
    body()
  })
}

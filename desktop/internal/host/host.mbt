// The package's public face: the transport-agnostic host ops — everything
// the desktop host offers a client beyond the engine itself (file browsing,
// language services, skills, self-update, app launching) — dispatched by
// method name. The method names and payload shapes are the wire catalog of
// docs/remote-protocol.md, shared verbatim by the proton bridge and the
// remote WebSocket.

///|
/// A host-side failure with a user-facing message. Ops raise it; the
/// transport boundary stringifies it into the error the client displays.
pub(all) suberror HostError {
  HostError(String)
}

///|
impl Show for HostError with fn output(self, logger) {
  match self {
    HostError(message) => logger.write_string(message)
  }
}

///|
/// A request payload that failed to decode — the client sent a shape the
/// method does not accept. Kept apart from `HostError` so transports can
/// report it as a malformed request (JSON-RPC -32602) rather than a failed
/// operation.
pub(all) suberror PayloadError {
  PayloadError(String)
}

///|
impl Show for PayloadError with fn output(self, logger) {
  match self {
    PayloadError(message) => logger.write_string(message)
  }
}

///|
/// The host ops' shared state: the language-server pool, the self-update
/// staging state, and the workspace watcher actor. One per host process,
/// created beside the engine manager.
struct HostState {
  lsp : LspPoolActor
  updates : UpdateState
  fs_watch : FsWatchActor
}

///|
/// `engine` is the engine executable (the LSP pool spawns the bundled
/// `moon-lsp` resolved next to it); `executable` is the host's own binary,
/// which self-update uses to locate the running .app bundle (absent or
/// non-bundle layouts only lose the in-app install, never the announcement).
pub fn new_host_state(
  engine : String,
  runtime_dir? : @path.Path,
  executable? : String,
) -> HostState {
  let lsp = LspPoolActor::new(engine, runtime_dir?)
  // Mirror LSP wire traffic to its own log next to the host's runtime
  // state, so a broken hover/symbol round-trip can be read back without the
  // per-message noise landing in the main app log.
  if runtime_dir is Some(dir) {
    @lsp.enable_traffic_log(dir.join("lsp.log").to_string())
  }
  {
    lsp,
    updates: new_update_state(runtime_dir, executable),
    fs_watch: FsWatchActor::new(),
  }
}

///|
/// The background tasks behind the host ops, spawned into the caller's
/// app-lifetime task group: the LSP pool actor, the diagnostics forwarder, the
/// workspace watcher, and the one-shot update-leftover sweep. `emit` pushes
/// a notification (method, params) to the client channel — `lsp.diagnostics`
/// and `fs.changed`, the catalog's names. Every pump is best-effort: a
/// language-service or watcher hiccup degrades that feature, never the
/// connection.
pub fn[G] spawn_host_pumps(
  group : @async.TaskGroup[G],
  state : HostState,
  emit : async (String, Json) -> Unit,
) -> Unit {
  group.spawn_bg(allow_failure=true, () => state.lsp.run())
  group.spawn_bg(allow_failure=true, () => {
    state.lsp.forward_diagnostics(async fn(push) {
      emit("lsp.diagnostics", ToJson::to_json(push))
    })
  })
  group.spawn_bg(allow_failure=true, () => {
    state.fs_watch.run(async fn(push) {
      emit("fs.changed", ToJson::to_json(push))
    })
  })
  group.spawn_bg(allow_failure=true, () => cleanup_updates(state.updates))
}

///|
fn[T : @json.FromJson] decode_payload(payload : Json) -> T raise {
  @json.from_json(payload) catch {
    _ => raise PayloadError("malformed request payload")
  }
}

///|
/// Dispatch one host method by its catalog name, returning its JSON reply —
/// or None for a name this host does not know, which the transport reports
/// as an unknown method rather than a failed op.
pub async fn host_op(state : HostState, op : String, payload : Json) -> Json? {
  match op {
    "skills.catalog" => Some(ToJson::to_json(skills_catalog_op()))
    "skills.install" =>
      Some(ToJson::to_json(install_skill_op(decode_payload(payload))))
    "skills.installed" => Some(ToJson::to_json(installed_skills_op()))
    "skills.uninstall" =>
      Some(ToJson::to_json(uninstall_skill_op(decode_payload(payload))))
    "host.open_path" =>
      Some(ToJson::to_json(open_path_op(decode_payload(payload))))
    "update.check" =>
      Some(
        ToJson::to_json(check_update_op(state.updates, decode_payload(payload))),
      )
    "update.download" =>
      Some(
        ToJson::to_json(
          download_update_op(state.updates, decode_payload(payload)),
        ),
      )
    "update.apply" => Some(ToJson::to_json(apply_update_op(state.updates)))
    "git.branch" =>
      Some(ToJson::to_json(git_branch_op(decode_payload(payload))))
    "app.list" => Some(ToJson::to_json(list_apps_op()))
    "app.launch" =>
      Some(ToJson::to_json(launch_app_op(decode_payload(payload))))
    "fs.read_directory" =>
      Some(ToJson::to_json(read_directory_op(decode_payload(payload))))
    "fs.list_files" =>
      Some(ToJson::to_json(list_files_op(decode_payload(payload))))
    "fs.read_file" =>
      Some(ToJson::to_json(read_file_op(decode_payload(payload))))
    "fs.stat_files" =>
      Some(ToJson::to_json(stat_files_op(decode_payload(payload))))
    "fs.watch" => {
      state.fs_watch.watch(decode_payload(payload))
      Some(Json::empty_object())
    }
    "fs.unwatch" => {
      state.fs_watch.unwatch()
      Some(Json::empty_object())
    }
    "lsp.hover" =>
      Some(ToJson::to_json(lsp_hover_op(state.lsp, decode_payload(payload))))
    "lsp.open" =>
      Some(ToJson::to_json(lsp_open_op(state.lsp, decode_payload(payload))))
    "lsp.workspace_symbols" =>
      Some(
        ToJson::to_json(
          workspace_symbols_op(state.lsp, decode_payload(payload)),
        ),
      )
    "fs.browse" =>
      Some(ToJson::to_json(browse_directory_op(decode_payload(payload))))
    _ => None
  }
}

///|
/// Every host method name, in catalog order — the transport adapters
/// register or advertise exactly this set.
pub fn host_method_names() -> Array[String] {
  [
    "fs.read_file", "fs.read_directory", "fs.list_files", "fs.stat_files", "fs.watch",
    "fs.unwatch", "fs.browse", "lsp.open", "lsp.hover", "lsp.workspace_symbols",
    "skills.catalog", "skills.installed", "skills.install", "skills.uninstall", "update.check",
    "update.download", "update.apply", "app.list", "app.launch", "git.branch", "host.open_path",
  ]
}

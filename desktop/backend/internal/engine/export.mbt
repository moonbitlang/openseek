///|
/// The exact store selection and display metadata for one session export.
priv struct SessionExport {
  manager : EngineManager
  session : String
  workspace : @pathx.Absolute
  root : @pathx.Absolute
  title : String
}

///|
/// Validate a window request and bind it to one registered live or archived
/// store. The workspace path comes from a host-produced conversation row, but
/// is still checked against the current registry before any file is read.
async fn SessionExport::SessionExport(
  manager : EngineManager,
  payload : @protocol.SessionExportPayload,
) -> SessionExport {
  let session = payload.session.trim().to_owned()
  guard @session_store.safe_session_id(session) else {
    raise EngineError("session id is not safe for export")
  }
  guard @pathx.Absolute::from_uri_path(payload.workspace) is Some(requested) &&
    @workspaces.registered_dir(requested) is Some(workspace) else {
    raise EngineError("\{payload.workspace} is not a registered workspace")
  }
  let live = @workspaces.store_root(workspace)
  let root = if payload.archived {
    @session_store.archived_root(live)
  } else {
    live
  }
  guard @fs.exists(root.join("sessions").join(session).to_string()) else {
    raise EngineError(
      if payload.archived {
        "no archived record for this conversation"
      } else {
        "no durable record for this conversation"
      },
    )
  }
  { manager, session, workspace, root, title: payload.title, }
}

///|
/// Whether a family member is the selected session or one direct subrun.
/// Nested descendants belong to their direct parent's own export, matching
/// `inspect --export-session`.
fn SessionExport::includes(self : SessionExport, candidate : String) -> Bool {
  candidate == self.session ||
  (
    @wire.split_child_session_id(candidate) is Some((parent, _)) &&
    parent == self.session
  )
}

///|
/// Freeze this conversation and its direct subruns into the visualizer's
/// standalone data entries. Record movement is blocked only while the files
/// are read; the native save dialog opens after this method returns.
async fn SessionExport::sessions(
  self : SessionExport,
) -> Array[@viz_export.Session] {
  let record_guard = self.manager.begin_record_read(self.session)
  defer self.manager.end_record_read(self.session, record_guard)
  let family = @session_store.family_in(self.root, self.session) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise EngineError("session export failed: \{error}")
  }
  let sessions : Array[@viz_export.Session] = []
  for entry_id in family {
    if !self.includes(entry_id) {
      continue
    }
    let events = @session_record.read_text(self.root, entry_id) catch {
      error if @async.is_being_cancelled() => raise error
      error => raise EngineError("session export failed: \{error}")
    }
    let key = "session-\{sessions.length()}"
    sessions.push(
      Session(
        key~,
        id=entry_id,
        root=self.root.to_string(),
        root_label=self.workspace.to_path().basename().to_owned(),
        is_marker=true,
        // The standalone export does not sort a catalog of unrelated sessions;
        // omit the live server's cosmetic last-active timestamp and avoid an
        // unrelated filesystem stat in the export path.
        last_active=None,
        first_prompt=if entry_id == self.session { self.title } else { "" },
        events~,
      ),
    )
  }
  sessions
}

///|
/// Export one current or archived OpenSeek conversation as standalone HTML.
/// The supplied shell and bundle are the host build's packaged `viz_app`
/// assets, so the document carries the parser that matches this application.
pub async fn export_session_html(
  manager : EngineManager,
  payload : @protocol.SessionExportPayload,
  shell_html : String,
  bundle_js : String,
) -> String {
  let request = SessionExport::SessionExport(manager, payload)
  @viz_export.StandaloneExport(shell_html, bundle_js).render(request.sessions())
}

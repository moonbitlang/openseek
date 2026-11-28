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
  let requested = @pathx.Absolute::parse_resource_path(payload.workspace)
  guard @workspaces.registered_dir(requested) is Some(workspace) else {
    raise EngineError("\{payload.workspace} is not a registered workspace")
  }
  let live = @workspaces.store_root(workspace)
  let root = if payload.archived {
    @session_store.archived_root(live)
  } else {
    live
  }
  guard @fsx.exists(root.join("sessions").join(session).to_path()) else {
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
/// Whether `candidate` is the selected session or a sub-run below it, at any
/// depth. The session *list* stops at direct children, because each level
/// belongs to its own export; the run's timeline does not.
fn SessionExport::in_run(self : SessionExport, candidate : String) -> Bool {
  if candidate == self.session {
    return true
  }
  match @wire.split_child_session_id(candidate) {
    Some((parent, _)) => self.in_run(parent)
    None => false
  }
}

///|
/// What one conversation export captured: the visualizer entries, and the same
/// files as the run fold needs them.
priv struct SessionExportData {
  sessions : Array[@viz_export.Session]
  sources : Array[@viz_export.RunSource]
}

///|
/// Freeze this conversation and its direct subruns into the visualizer's
/// standalone data entries. Record movement is blocked only while the files
/// are read; the native save dialog opens after this method returns.
///
/// The session list is scoped to this conversation and its direct subruns; the
/// run sources span every descendant, so the timeline an export carries covers
/// the whole run rather than one level of it.
async fn SessionExport::data(self : SessionExport) -> SessionExportData {
  let record_guard = self.manager.begin_record_read(self.session)
  defer self.manager.end_record_read(self.session, record_guard)
  let family = @session_store.family_in(self.root, self.session) catch {
    error => raise EngineError("session export failed: \{error}")
  }
  let sessions : Array[@viz_export.Session] = []
  let sources : Array[@viz_export.RunSource] = []
  let visited : Map[String, Bool] = Map([])
  let queue : Array[String] = []
  for entry_id in family {
    if self.includes(entry_id) || self.in_run(entry_id) {
      if visited.get(entry_id) is None {
        visited[entry_id] = true
        queue.push(entry_id)
      }
    }
  }
  let mut head = 0
  while head < queue.length() {
    let entry_id = queue[head]
    head += 1
    let events = @session_record.read_text(self.root, entry_id) catch {
      error =>
        if entry_id == self.session || self.includes(entry_id) {
          raise EngineError("session export failed: \{error}")
        } else {
          continue
        }
    }
    let listed = self.includes(entry_id)
    let first_prompt = if entry_id == self.session { self.title } else { "" }
    if listed {
      let key = "session-\{sessions.length()}"
      sessions.push(
        Session(
          key~,
          id=entry_id,
          root=self.root.to_string(),
          root_label=self.workspace.to_path().basename().to_owned(),
          is_marker=true,
          // The standalone export does not sort a catalog of unrelated
          // sessions; omit the live server's cosmetic last-active timestamp
          // and avoid an unrelated filesystem stat in the export path.
          last_active=None,
          first_prompt~,
          events~,
          artifacts=self.artifacts(entry_id, events),
          run_root=self.session,
        ),
      )
    }
    let jobs = session_export_jobs(self.root, entry_id)
    sources.push(
      RunSource(
        id=entry_id,
        store=self.root.to_string(),
        first_prompt~,
        text=events,
        jobs~,
      ),
    )
    for child_id in @viz_export.child_session_ids(events) {
      if visited.get(child_id) is None {
        visited[child_id] = true
        queue.push(child_id)
      }
    }
  }
  { sessions, sources, }
}

///|
async fn session_export_jobs(
  root : @pathx.Absolute,
  session_id : String,
) -> Array[@viz_export.JobRecord] {
  let directory = root
    .join("sessions")
    .join(session_id)
    .join("jobs")
    .to_string()
  let generations = @fs.readdir(directory, sort=true) catch { _ => return [] }
  let out : Array[@viz_export.JobRecord] = []
  for generation in generations {
    guard @wire.valid_job_component(generation) else { continue }
    let files = @fs.readdir("\{directory}/\{generation}", sort=true) catch {
      _ => continue
    }
    for name in files {
      guard name.strip_suffix(".json") is Some(stem) else { continue }
      let id = @wire.job_id_from_storage(stem.to_owned())
      let record = read_job_record(directory, generation, id) catch {
        _ => continue
      }
      let (exited, interrupted) = match record.state {
        Exited(code) => (Some(code), false)
        Stopped(_) | Interrupted => (None, true)
        Running | Stopping => (None, false)
      }
      out.push(
        @viz_export.job_record(
          session_id~,
          job_id=record.id,
          started_at_ms=record.started_at_ms,
          finished_at_ms=record.finished_at_ms,
          exited~,
          interrupted~,
        ),
      )
    }
  }
  out
}

///|
async fn SessionExport::artifacts(
  self : SessionExport,
  session : String,
  events : String,
) -> Map[String, String] {
  let files : Map[String, String] = Map([])
  let checkout = Some(@worktree.run_dir(self.workspace, self.session)) catch {
    _ => None
  }
  for event in @session_log.parse_events(events).events {
    if event.item() is Assistant(message) {
      for part in @workspace_file_ref.markdown_parts(message.content()) {
        if part is File(reference) &&
          reference.artifact &&
          reference.extension is Some("html" | "htm" | "svg") &&
          !files.contains(reference.path) {
          let root = if reference.artifact_path() is Some(_) {
            Some(self.root.join("sessions").join(session).resource_path())
          } else {
            checkout.map(path => path.resource_path())
          }
          guard root is Some(root) else { continue }
          let reply = @files.read_file({
            root: Some(root),
            path: reference.path,
            max_bytes: Some(8 * 1024 * 1024),
          }) catch {
            _ => continue
          }
          if reply is Content(content~, ..) {
            files[reference.path] = content
          }
        }
      }
    }
  }
  files
}

///|
/// One current or archived OpenSeek conversation rendered as the standalone
/// HTML visualizer plus its embedded dataset. The supplied shell and bundle
/// are the host build's packaged `viz_app` assets, so the document carries the
/// parser that matches this application.
pub struct ConversationExport {
  html : String
  json : String
}

///|
/// Read the records once so both files describe the same conversation even
/// when another turn is running while the user exports it.
pub async fn ConversationExport::capture(
  manager : EngineManager,
  payload : @protocol.SessionExportPayload,
  shell_html : String,
  bundle_js : String,
) -> ConversationExport {
  let request = SessionExport::SessionExport(manager, payload)
  let data = request.data()
  let exporter = @viz_export.StandaloneExport(shell_html, bundle_js)
  // The export names its own run: the conversation the reader chose, which is
  // itself a subrun when they exported one.
  let runs : Array[@viz_export.TrajectoryDocument] = []
  if @viz_export.bake_run(data.sources, request.session) is Some(document) {
    runs.push(document)
  }
  ConversationExport(exporter, data.sessions, runs~)
}

///|
/// `models=false` leaves out each row's recorded model and `artifacts=false`
/// skips its `artifacts.json` sidecar: title search reads only titles and would
/// otherwise touch every session's sidecars.
async fn session_listing_groups(
  archived~ : Bool,
  models~ : Bool = true,
  artifacts~ : Bool = true,
) -> @protocol.SessionsReply {
  let workspaces = @workspaces.registered()
  let groups : Array[@protocol.SessionGroup] = []
  for workspace in workspaces {
    let root = @workspaces.store_root(workspace)
    groups.push(
      session_group(
        workspace,
        if archived {
          @session_store.archived_root(root)
        } else {
          root
        },
        models~,
        artifacts~,
      ),
    )
  }
  { groups, }
}

///|
async fn session_group(
  workspace : @pathx.Absolute,
  root : @pathx.Absolute,
  models~ : Bool,
  artifacts~ : Bool,
) -> @protocol.SessionGroup {
  let name = workspace.to_path().basename().to_owned()
  let workspace = workspace.resource_path()
  let native_root = root.to_string()
  let sessions_dir = root.join("sessions")
  let root = root.resource_path()
  fn failed(error : String) -> @protocol.SessionGroup {
    { workspace, name, session_root: root, sessions: [], error, }
  }

  let sessions : Array[@protocol.SessionListEntry] = try {
    let store = @store.SessionStore(native_root)
    let entries : Array[(@protocol.SessionListEntry, Int64, Int32)] = []
    let unstamped : Array[@protocol.SessionListEntry] = []
    for id in store.list() {
      let path = store.session_file(id) catch { _ => continue }
      let stamp = Some(file_stamp(@fs.mtime(path))) catch { _ => None }
      let title = if store.title(id) is Some(title) {
        title
      } else if stamp is Some(_) {
        // A damaged transcript must not hide the rest of the sidebar.
        let title = store.backfill_title(id) catch {
          @store.TitleBackfillError(title~, cause~) => {
            if @xlog.warn() is Some(w) {
              w
              ..write_object_begin()
              ..write_object_field(
                "event", "desktop_session_title_backfill_failed",
              )
              ..write_object_field("session", id.value())
              ..write_object_field("error", cause.to_string())
              .write_object_end()
            }
            Some(title)
          }
          _ => None
        }
        title.unwrap_or("")
      } else {
        ""
      }
      let updated_at_ms = stamp.map(stamp => {
        let (seconds, nanoseconds) = stamp
        (seconds * 1000 + (nanoseconds / 1000000).to_int64()).to_double()
      })
      // Like the model record: a damaged artifacts sidecar must not hide the
      // row; it simply renders without PR badges.
      let pull_requests : Array[String] = if artifacts {
        let attached = @session_store.read_artifacts(
          sessions_dir.join(id.value()),
        ) catch {
          _ => @protocol.SessionArtifacts::empty()
        }
        let urls : Array[String] = []
        for artifact in attached.artifacts {
          if artifact.type_ is PullRequest && !urls.contains(artifact.url) {
            urls.push(artifact.url)
          }
        }
        urls
      } else {
        []
      }
      let entry : @protocol.SessionListEntry = {
        id: id.value(),
        title: Some(title),
        updated_at_ms,
        // Like the title fallback: a damaged model record must not hide the
        // row; the conversation then opens on the default model.
        model_settings: if models {
          (store.model(id) catch { _ => None }).map(session_model_settings)
        } else {
          None
        },
        pull_requests,
      }
      if stamp is Some((seconds, nanos)) {
        entries.push((entry, seconds, nanos))
      } else {
        unstamped.push(entry)
      }
    }
    // Match store listings: newest first with full timestamp precision;
    // directories without readable timestamps remain visible at the end.
    entries.sort_by((a, b) => (b.1, b.2).compare((a.1, a.2)))
    [ for entry in entries => entry.0 ]..append(unstamped)
  } catch {
    error => return failed("session list failed: \{error}")
  }
  { workspace, name, session_root: root, sessions, error: "", }
}

///|
/// A file time as `(seconds, nanoseconds)`, which compares and orders.
fn file_stamp(time : @fs.Timestamp) -> (Int64, Int32) {
  (time.sec(), time.subsec_nanos())
}

///|
fn session_model_settings(
  model : @store.SessionModel,
) -> @protocol.SessionModelSettings {
  {
    model: model.model.to_string(),
    thinking: match model.thinking {
      No => ThinkingOff
      High => ThinkingHigh
      Max => ThinkingMax
    },
  }
}

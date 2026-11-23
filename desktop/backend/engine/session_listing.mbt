///|
/// `models=false` leaves out each row's recorded model: title search reads
/// only titles and would otherwise read every session's `model.json`.
async fn session_listing_groups(
  archived~ : Bool,
  models~ : Bool = true,
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
) -> @protocol.SessionGroup {
  let name = workspace.to_path().basename().to_owned()
  let workspace = workspace.resource_path()
  let native_root = root.to_string()
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
        (store.backfill_title(
          id,
          read_first_prompt=@session_preview.read_first_prompt,
        ) catch {
          _ => None
        }).unwrap_or("")
      } else {
        ""
      }
      let updated_at_ms = stamp.map(stamp => {
        let (seconds, nanoseconds) = stamp
        (seconds * 1000 + (nanoseconds / 1000000).to_int64()).to_double()
      })
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
  (time.sec(), time.nsec())
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

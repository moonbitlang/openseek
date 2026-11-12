///|
// Sidebar refreshes warm the same prompt metadata used by title search.
// Desktop owns these caches; detached workspaces are released below.
let listing_prompt_caches : Map[String, Map[String, CachedListingPrompt]] = Map([],
)

///|
/// `models=false` leaves out each row's recorded model: title search reads
/// only titles and would otherwise read every session's `model.json`.
async fn session_listing_groups(
  archived~ : Bool,
  models~ : Bool = true,
) -> @protocol.SessionsReply {
  let workspaces = @workspaces.registered()
  let roots : Set[String] = Set([])
  for workspace in workspaces {
    let root = @workspaces.store_root(workspace)
    roots.add(root.to_string())
    roots.add(@session_store.archived_root(root).to_string())
  }
  listing_prompt_caches.retain((root, _) => roots.contains(root))
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
    let cache = listing_prompt_caches.get_or_init(native_root, () => Map([]))
    let paths : Set[String] = Set([])
    let entries : Array[(@protocol.SessionListEntry, Int64, Int32)] = []
    let unstamped : Array[@protocol.SessionListEntry] = []
    for id in store.list() {
      let path = store.session_file(id) catch { _ => continue }
      paths.add(path)
      let stamp = Some(file_stamp(@fs.mtime(path))) catch { _ => None }
      let title = if store.title(id) is Some(title) {
        title
      } else {
        // A damaged transcript must not hide the rest of the sidebar.
        try cached_listing_prompt(cache, path, stamp) catch {
          _ => ""
        } noraise {
          prompt => listing_prompt_title(prompt.unwrap_or(""))
        }
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
    cache.retain((path, _) => paths.contains(path))
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
// Keep the CLI's display-label convention when no explicit title is stored.
fn listing_prompt_title(first_prompt : String) -> String {
  let first_prompt = match @command_context.parse(first_prompt) {
    Some(shell) => "$ \{shell.command}"
    None => first_prompt
  }
  let content = first_prompt.trim()
  match content.split_once("\n") {
    Some((line, _)) => line.trim().to_owned()
    None => content.to_owned()
  }
}

///|
priv struct CachedListingPrompt {
  mtime : (Int64, Int32)
  ctime : (Int64, Int32)
  text : String
}

///|
/// Reuse successful prompt reads only while both file timestamps match.
/// Title sidecars are read on every call, independently of this
/// cache. ctime also detects rewrites that preserve the original mtime.
async fn cached_listing_prompt(
  cache : Map[String, CachedListingPrompt],
  path : String,
  mtime : (Int64, Int32)?,
) -> String? {
  let ctime = Some(file_stamp(@fs.ctime(path))) catch { _ => None }
  if mtime is Some(mtime) &&
    ctime is Some(ctime) &&
    cache.get(path) is Some(cached) &&
    cached.mtime == mtime &&
    cached.ctime == ctime {
    return Some(cached.text)
  }
  cache.remove(path)
  let text = @session_preview.read_first_prompt(path)
  // Absence and errors are never cached. Empty text is a successful result.
  if text is Some(text) && mtime is Some(mtime) && ctime is Some(ctime) {
    let unchanged = try
      file_stamp(@fs.mtime(path)) == mtime &&
      file_stamp(@fs.ctime(path)) == ctime
    catch {
      _ => false
    }
    if unchanged {
      cache[path] = { mtime, ctime, text, }
    }
  }
  text
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

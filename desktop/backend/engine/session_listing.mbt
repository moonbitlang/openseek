///|
// Sidebar refreshes warm the same prompt metadata used by title search.
// Desktop owns these caches; detached workspaces are released below.
let listing_prompt_caches : Map[String, Map[String, CachedListingPrompt]] = Map([],
)

///|
async fn session_listing_groups(archived~ : Bool) -> SessionsReply {
  let workspaces = @workspaces.registered()
  let roots : Set[String] = Set([])
  for workspace in workspaces {
    let root = @workspaces.store_root(workspace)
    roots.add(root.to_string())
    roots.add(@session_store.archived_root(root).to_string())
  }
  listing_prompt_caches.retain((root, _) => roots.contains(root))
  let groups : Array[SessionGroup] = []
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
      ),
    )
  }
  { groups, }
}

///|
async fn session_group(
  workspace : @pathx.Absolute,
  root : @pathx.Absolute,
) -> SessionGroup {
  let name = workspace.to_path().basename().to_owned()
  let workspace = workspace.resource_path()
  let native_root = root.to_string()
  let root = root.resource_path()
  fn failed(error : String) -> SessionGroup {
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
      let stamp = Some(@fs.mtime(path)) catch { _ => None }
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
    entries.sort_by((a, b) => {
      if a.1 != b.1 {
        b.1.compare(a.1)
      } else {
        b.2.compare(a.2)
      }
    })
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
  let ctime = Some(@fs.ctime(path)) catch { _ => None }
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
      @fs.mtime(path) == mtime && @fs.ctime(path) == ctime
    catch {
      _ => false
    }
    if unchanged {
      cache[path] = { mtime, ctime, text, }
    }
  }
  text
}

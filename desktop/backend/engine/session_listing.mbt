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
  size : Int64
  identity : (UInt64, UInt64)?
  text : String
}

///|
#borrow(path_utf8, out)
extern "C" fn stat_device_inode_ffi(
  path_utf8 : Bytes,
  out : FixedArray[UInt64],
) -> Int32 = "moonbit_openseek_desktop_engine_file_identity"

///|
/// Return `(st_dev, st_ino)` on Linux, or `None` on other platforms (macOS and
/// Windows have sub-microsecond timestamps and skip this lookup) or when `stat`
/// fails.
fn file_identity(path : String) -> (UInt64, UInt64)? {
  guard @async.platform is Linux else { return None }
  guard !path.contains("\u{0}") else { return None }
  let encoded = @utf8.encode(path)
  let c_path = Bytes::makei(encoded.length() + 1, i => {
    if i < encoded.length() {
      encoded[i]
    } else {
      b'\x00'
    }
  })
  let out : FixedArray[UInt64] = [0UL, 0UL]
  if stat_device_inode_ffi(c_path, out) == 0 {
    Some((out[0], out[1]))
  } else {
    None
  }
}

///|
/// Reuse successful prompt reads only while file timestamps, size, and (on
/// Linux) `(dev, ino)` match. Title sidecars are read on every call,
/// independently of this cache. `ctime` detects rewrites that preserve the
/// original `mtime`, `size` detects different-length rewrites within the same
/// clock tick, and `(dev, ino)` detects same-length atomic rewrites within the
/// same coarse Linux clock tick.
async fn cached_listing_prompt(
  cache : Map[String, CachedListingPrompt],
  path : String,
  mtime : (Int64, Int32)?,
) -> String? {
  let ctime = Some(file_stamp(@fs.ctime(path))) catch { _ => None }
  let size = Some(@fs.file_size(path)) catch { _ => None }
  let identity = file_identity(path)
  let identity_ok = if @async.platform is Linux {
    identity is Some(_)
  } else {
    true
  }
  if mtime is Some(mtime) &&
    ctime is Some(ctime) &&
    size is Some(size) &&
    identity_ok &&
    cache.get(path) is Some(cached) &&
    cached.mtime == mtime &&
    cached.ctime == ctime &&
    cached.size == size &&
    cached.identity == identity {
    return Some(cached.text)
  }
  cache.remove(path)
  let text = @session_preview.read_first_prompt(path)
  // Absence and errors are never cached. Empty text is a successful result.
  if text is Some(text) &&
    mtime is Some(mtime) &&
    ctime is Some(ctime) &&
    size is Some(size) &&
    identity_ok {
    let unchanged = try
      file_stamp(@fs.mtime(path)) == mtime &&
      file_stamp(@fs.ctime(path)) == ctime &&
      @fs.file_size(path) == size &&
      file_identity(path) == identity
    catch {
      _ => false
    }
    if unchanged {
      cache[path] = { mtime, ctime, size, identity, text, }
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

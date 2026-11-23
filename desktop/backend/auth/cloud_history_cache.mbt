///|
fn valid_cache_id(id : String) -> Bool {
  !id.is_empty() &&
  id.length() <= 128 &&
  id
  .iter()
  .all(ch => {
    ch.is_ascii_alphabetic() || ch.is_ascii_digit() || ch == '-' || ch == '_'
  })
}

///|
fn cloud_history_directory(runtime : @pathx.Path, user : String) -> @pathx.Path {
  runtime.join("cloud-history-cache").join(user)
}

///|
async fn read_cloud_history(
  path : @pathx.Path,
) -> @protocol.CloudHistoryCachePage? {
  guard @fsx.try_read_text(path) is Some(text) else { return None }
  Some(@json.from_json(@json.parse(text))) catch {
    _ => None
  }
}

///|
/// Window-only Cloud cache operations share the account persistence mutex
/// with credential changes and sign-out cleanup.
pub async fn AuthStore::cloud_history_cache(
  self : AuthStore,
  request : @protocol.CloudHistoryCacheRequest,
) -> @protocol.CloudHistoryCacheReply {
  self.persist_mutex.acquire()
  defer self.persist_mutex.release()
  guard self.cloud_history_runtime is Some(runtime) &&
    self.account() is Some(account) &&
    account.token == request.token &&
    valid_cache_id(account.user.user_id) else {
    return Done
  }
  let user = account.user.user_id
  let dir = cloud_history_directory(runtime, user)
  fn pages(view : @protocol.CloudHistoryView) -> @pathx.Path {
    match view {
      Detail => dir
      Minimal => dir.join("minimal")
    }
  }
  match request.action {
    List => {
      let entries : Map[String, @protocol.CloudHistoryCacheEntry] = Map([])
      for view in [@protocol.CloudHistoryView::Detail, Minimal] {
        let dir = pages(view)
        if @fsx.Directory::try_open(dir) is Some(directory) {
          for entry in directory.collect() {
            let name = entry.name()
            guard name.strip_suffix(".json") is Some(prefix) else { continue }
            let session = prefix.to_owned()
            if valid_cache_id(session) &&
              !self.cloud_history_deleted.contains((user, session)) &&
              (read_cloud_history(dir.join(name)) catch { _ => None })
              is Some(page) {
              entries[session] = { session, label: page.label(session), }
            }
          }
        }
      }
      Entries(entries.values().to_array())
    }
    Read(session~, view~) => {
      guard valid_cache_id(session) &&
        !self.cloud_history_deleted.contains((user, session)) else {
        return Page(None)
      }
      Page(read_cloud_history(pages(view).join(session + ".json")))
    }
    Write(session~, page~, view~) => {
      let dir = pages(view)
      if valid_cache_id(session) &&
        !self.cloud_history_deleted.contains((user, session)) {
        @fs.mkdir(dir.to_string(), recursive=true, permission=0o700) catch {
          @os_error.OsError(AlreadyExists, ..) => ()
          error => raise error
        }
        @openseek/atomic_file.write_text_atomic(
          dir.join(session + ".json").to_string(),
          page.to_json().stringify(),
        )
      }
      Done
    }
    Remove(session~) => {
      if valid_cache_id(session) {
        self.cloud_history_deleted.add((user, session))
        for view in [@protocol.CloudHistoryView::Detail, Minimal] {
          @fsx.remove_if_exists(pages(view).join(session + ".json"))
        }
      }
      Done
    }
  }
}

///|
async fn AuthStore::clear_cloud_history(
  self : AuthStore,
  account : @protocol.AccountSession?,
) -> Unit {
  self.cloud_history_deleted.clear()
  if self.cloud_history_runtime is Some(runtime) &&
    account is Some(account) &&
    valid_cache_id(account.user.user_id) {
    @fsx.remove_if_exists(
      cloud_history_directory(runtime, account.user.user_id),
    )
  }
}

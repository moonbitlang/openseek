///|
priv struct BrowserHistoryCache {
  mutex : @async.Mutex
  mut epoch : Int32
  mut user : String?
  mut unavailable : Bool
  mut running : @indexeddb.Transaction?
  deleted : Map[String, Unit]
}

///|
let indexed_history_store : BrowserHistoryCache = {
  mutex: @async.Mutex(),
  epoch: 0,
  user: None,
  unavailable: false,
  running: None,
  deleted: Map([]),
}

///|
fn abort_history_transaction(tx : @indexeddb.Transaction) -> Unit {
  tx.abort() catch {
    _ => ()
  }
}

///|
/// Keep every transaction ordered with logout cleanup. The epoch and deletion
/// checks run again after opening IndexedDB, before any pages can be written.
async fn BrowserHistoryCache::access(
  self : BrowserHistoryCache,
  write~ : Bool,
  valid~ : () -> Bool,
  cleanup~ : Bool = false,
  operation : (@indexeddb.Transaction) -> @indexeddb.Request raise @indexeddb.IndexedDBError,
) -> Json {
  self.mutex.acquire()
  defer self.mutex.release()
  guard valid() && (!self.unavailable || cleanup) else { return Json::null() }
  @async.with_timeout(1000, () => {
    let db = @indexeddb.open("seekmoon.cloud-history.v1", 1, upgrade=(
      db,
      _,
      previous,
    ) => {
      if previous == 0 {
        let store = db.create_store(
          "pages",
          key_path=Fields(["origin", "user", "session"]),
        )
        ignore(store.create_index("account", Fields(["origin", "user"])))
      }
    })
    defer db.close()
    guard valid() else { return Json::null() }
    let tx = db.transaction(["pages"], if write { ReadWrite } else { ReadOnly })
    self.running = if cleanup { None } else { Some(tx) }
    defer {
      self.running = None
    }
    errdefer abort_history_transaction(tx)
    let query = operation(tx)
    tx.wait()
    query.result().unwrap_or(Json::null())
  }) catch {
    _ => {
      if valid() {
        self.unavailable = true
      }
      Json::null()
    }
  }
}

///|
fn State::cache_account_changed(self : State, previous : String?) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => {
    guard !native_history_cache() else { return }
    let cache = indexed_history_store
    if cache.running is Some(tx) {
      abort_history_transaction(tx)
    }
    cache.epoch = self.epoch
    cache.user = self.user_id
    cache.deleted.clear()
    if self.user_id is None && previous is Some(user) {
      @js.Promise::from_async(() => {
        ignore(
          cache.access(write=true, valid=() => true, cleanup=true, tx => {
            tx
            .store("pages")
            .index("account")
            .delete_all(
              key=Array([String(@cloud_client.CloudOrigin), String(user)]),
            )
          }),
        )
      })
      |> ignore
    }
  })
}

///|
async fn State::indexed_history_cache(
  self : State,
  action : @protocol.CloudHistoryCacheAction,
) -> @protocol.CloudHistoryCacheReply {
  guard self.user_id is Some(user) else { return Done }
  let cache = indexed_history_store
  fn current() {
    cache.epoch == self.epoch && cache.user == Some(user)
  }
  guard current() else { return Done }
  let session = match action {
    List => None
    Read(session~) | Write(session~, ..) | Remove(session~) => Some(session)
  }
  if action is Remove(session~) {
    cache.deleted[session] = ()
  }
  let value = cache.access(
    write=action is (Write(..) | Remove(_)),
    cleanup=action is Remove(_),
    valid=() => {
      current() &&
      (
        action is Remove(_) ||
        !session.map_or(false, id => cache.deleted.contains(id))
      )
    },
    tx => {
      let store = tx.store("pages")
      let key : @indexeddb.Key = Array([
        String(@cloud_client.CloudOrigin),
        String(user),
        String(session.unwrap_or("")),
      ])
      match action {
        List =>
          store
          .index("account")
          .get_all(key=Array([String(@cloud_client.CloudOrigin), String(user)]))
        Read(_) => store.get(key)
        Write(session~, page~) =>
          store.put({
            "origin": @cloud_client.CloudOrigin,
            "user": user,
            "session": session,
            "page": page.to_json(),
          })
        Remove(_) => store.delete(key)
      }
    },
  ) catch {
    _ => return Done
  }
  match action {
    List => {
      let entries : Array[@protocol.CloudHistoryCacheEntry] = []
      if value is Array(rows) {
        for row in rows {
          guard row is { "session": String(session), "page": page, .. } else {
            continue
          }
          let page : @protocol.CloudHistoryCachePage = @json.from_json(page) catch {
            _ => continue
          }
          if cached_history(page) is Some(_) {
            entries.push({ session, label: page.label(session), })
          }
        }
      }
      Entries(entries)
    }
    Read(_) =>
      Page(
        match value {
          { "page": page, .. } =>
            Some(@json.from_json(page)) catch {
              _ => None
            }
          _ => None
        },
      )
    _ => Done
  }
}

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
  stores~ : Array[String],
  operation : (String, @indexeddb.ObjectStore) -> @indexeddb.Request raise @indexeddb.IndexedDBError,
) -> Array[Json] {
  self.mutex.acquire()
  defer self.mutex.release()
  guard valid() && (!self.unavailable || cleanup) else { return [] }
  @async.with_timeout(1000, () => {
    let db = @indexeddb.open("seekmoon.cloud-history.v1", 3, upgrade=(
      db,
      _,
      previous,
    ) => {
      let stores = ["catalog"]
      if previous == 0 {
        stores.push("pages")
      }
      if previous < 2 {
        stores.push("minimalPages")
      }
      for name in stores {
        let store = db.create_store(
          name,
          key_path=Fields(["origin", "user", "session"]),
        )
        ignore(store.create_index("account", Fields(["origin", "user"])))
      }
    })
    defer db.close()
    guard valid() else { return [] }
    let tx = db.transaction(stores, if write { ReadWrite } else { ReadOnly })
    self.running = if cleanup { None } else { Some(tx) }
    defer {
      self.running = None
    }
    errdefer abort_history_transaction(tx)
    let queries = stores.map(name => operation(name, tx.store(name)))
    tx.wait()
    queries.map(query => query.result().unwrap_or(Json::null()))
  }) catch {
    _ => {
      if valid() {
        self.unavailable = true
      }
      []
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
          cache.access(
            write=true,
            valid=() => true,
            cleanup=true,
            stores=["pages", "minimalPages", "catalog"],
            (_, store) => {
              store
              .index("account")
              .delete_all(
                key=Array([String(@cloud_client.CloudOrigin), String(user)]),
              )
            },
          ),
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
    Read(session~, ..) | Write(session~, ..) | Remove(session~) => Some(session)
  }
  if action is Remove(session~) {
    cache.deleted[session] = ()
  }
  let stores = match action {
    Read(view=Minimal, ..) => ["minimalPages"]
    Write(view=Minimal, ..) => ["minimalPages", "catalog"]
    Read(view=Detail, ..) => ["pages"]
    Write(view=Detail, ..) => ["pages", "catalog"]
    List | Remove(_) => ["pages", "minimalPages", "catalog"]
  }
  let values = cache.access(
    stores~,
    write=action is (Write(..) | Remove(_)),
    cleanup=action is Remove(_),
    valid=() => {
      current() &&
      (
        action is Remove(_) ||
        !session.map_or(false, id => cache.deleted.contains(id))
      )
    },
    (name, store) => {
      let key : @indexeddb.Key = Array([
        String(@cloud_client.CloudOrigin),
        String(user),
        String(session.unwrap_or("")),
      ])
      match action {
        List => {
          let account : @indexeddb.Key = Array([
            String(@cloud_client.CloudOrigin),
            String(user),
          ])
          let index = store.index("account")
          if name == "catalog" {
            index.get_all(key=account)
          } else {
            index.get_all_keys(account)
          }
        }
        Read(..) => store.get(key)
        Write(session~, page~, ..) if name == "catalog" =>
          store.put({
            "origin": @cloud_client.CloudOrigin,
            "user": user,
            "session": session,
            "label": page.label(session),
          })
        Write(session~, page~, ..) =>
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
      let entries : Map[String, @protocol.CloudHistoryCacheEntry] = Map([])
      for value in values {
        if value is Array(rows) {
          for row in rows {
            match row {
              // Older caches only have page keys until the next write.
              [_, _, String(session)] =>
                entries[session] = { session, label: session, }
              { "session": String(session), "label": String(label), .. } =>
                entries[session] = { session, label, }
              _ => ()
            }
          }
        }
      }
      Entries(entries.values().to_array())
    }
    Read(..) =>
      Page(
        match values {
          [{ "page": page, .. }] =>
            Some(@json.from_json(page)) catch {
              _ => None
            }
          _ => None
        },
      )
    _ => Done
  }
}

///|
priv struct BrowserHistoryCache {
  mutex : @async.Mutex
  mut epoch : Int32
  mut user : String?
  mut unavailable : Bool
  mut running : HistoryTransaction?
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
fn HistoryTransaction::try_abort(self : HistoryTransaction) -> Unit {
  history_binding(() => self.abort()) catch {
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
  operation : (HistoryTransaction) -> HistoryRequest,
) -> Json {
  self.mutex.acquire()
  defer self.mutex.release()
  guard valid() && (!self.unavailable || cleanup) else { return Json::null() }
  @async.with_timeout(1000, () => {
    let db = @js_async.run_promise(open_history_database)
    defer db.close()
    guard valid() else { return Json::null() }
    let tx = history_binding(() => db.transaction(write))
    self.running = if cleanup { None } else { Some(tx) }
    defer {
      self.running = None
    }
    errdefer tx.try_abort()
    let query = history_binding(() => operation(tx))
    tx.completion().wait(abort_controller=@js_async.AbortController::new())
    query.value().to_json() catch {
      _ => Json::null()
    }
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
      tx.try_abort()
    }
    cache.epoch = self.epoch
    cache.user = self.user_id
    cache.deleted.clear()
    if self.user_id is None && previous is Some(user) {
      @js.Promise::from_async(() => {
        ignore(
          cache.access(write=true, valid=() => true, cleanup=true, store => {
            store.clear_account(@cloud_client.CloudOrigin, user)
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
  let row = match action {
    Write(session~, page~) =>
      Some(
        @js.Value::from_json({
          "origin": @cloud_client.CloudOrigin,
          "user": user,
          "session": session,
          "page": page.to_json(),
        }),
      )
    _ => None
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
    store => {
      let key : FixedArray[String] = [
        @cloud_client.CloudOrigin,
        user,
        session.unwrap_or(""),
      ]
      match action {
        List => store.list(@cloud_client.CloudOrigin, user)
        Read(_) => store.read(key)
        Write(..) => store.write(row.unwrap())
        Remove(_) => store.remove(key)
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

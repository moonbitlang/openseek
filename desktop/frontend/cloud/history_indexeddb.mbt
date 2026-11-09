///|
// Tokens never enter this adapter. Account epochs fence queued work before it
// opens a transaction; deletion tombstones prevent a late write resurrecting it.
let indexed_history_store : @js.Value = new_indexed_history_store()

///|
extern "js" fn new_indexed_history_store() -> @js.Value =
  #| () => {
  #|   let account = null;
  #|   let running = null;
  #|   let unavailable = false;
  #|   let tail = Promise.resolve();
  #|   const deleted = new Set();
  #|   const enqueue = work => (tail = tail.then(work).catch(() => null));
  #|   const transact = (origin, user, action, session, page, scope) => new Promise(resolve => {
  #|     if (unavailable && action !== 'clear' && action !== 'remove') { resolve(null); return; }
  #|     let db, tx, result = null, settled = false;
  #|     const finish = (value, failed = false) => {
  #|       if (settled) return;
  #|       settled = true;
  #|       unavailable ||= failed;
  #|       clearTimeout(timer);
  #|       if (running?.tx === tx) running = null;
  #|       if (db) db.close();
  #|       resolve(value);
  #|     };
  #|     // A blocked or stalled database must not hold up the network history read.
  #|     const timer = setTimeout(() => {
  #|       if (tx) { try { tx.abort(); } catch (_) {} }
  #|       finish(null, true);
  #|     }, 1000);
  #|     try {
  #|       const request = indexedDB.open('seekmoon.cloud-history.v1', 1);
  #|       request.onupgradeneeded = () => {
  #|         request.result.createObjectStore('pages', { keyPath: ['origin', 'user', 'session'] })
  #|           .createIndex('account', ['origin', 'user']);
  #|       };
  #|       request.onerror = request.onblocked = () => finish(null, true);
  #|       request.onsuccess = () => {
  #|         db = request.result;
  #|         if (settled || (scope && account !== scope) ||
  #|             (action !== 'remove' && deleted.has(session))) {
  #|           db.close(); finish(null); return;
  #|         }
  #|         db.onversionchange = () => db.close();
  #|         try {
  #|           tx = db.transaction('pages', action === 'read' || action === 'list' ? 'readonly' : 'readwrite');
  #|           running = { tx, scope };
  #|           tx.oncomplete = () => finish(result);
  #|           tx.onerror = tx.onabort = () => finish(null, !scope || account === scope);
  #|           const store = tx.objectStore('pages');
  #|           const key = [origin, user, session];
  #|           if (action === 'read') {
  #|             store.get(key).onsuccess = event => { result = event.target.result?.page ?? null; };
  #|           } else if (action === 'write') {
  #|             store.put({ origin, user, session, page });
  #|           } else if (action === 'remove') {
  #|             store.delete(key);
  #|           } else {
  #|             result = [];
  #|             store.index('account').openCursor(IDBKeyRange.only([origin, user])).onsuccess = event => {
  #|               const cursor = event.target.result;
  #|               if (!cursor) return;
  #|               if (action === 'clear') cursor.delete();
  #|               else if (!deleted.has(cursor.value.session)) result.push(cursor.value);
  #|               cursor.continue();
  #|             };
  #|           }
  #|         } catch (_) { finish(null, true); }
  #|       };
  #|     } catch (_) { finish(null, true); }
  #|   });
  #|   return {
  #|     activate(request) {
  #|       if (running?.scope) { try { running.tx.abort(); } catch (_) {} }
  #|       account = request;
  #|       deleted.clear();
  #|       if (request.clear !== null) {
  #|         enqueue(() => transact(request.origin, request.clear, 'clear', null, null, null));
  #|       }
  #|     },
  #|     request(request) {
  #|       const scope = account;
  #|       if (!scope || scope.epoch !== request.epoch || scope.origin !== request.origin || scope.user !== request.user) {
  #|         return Promise.resolve(null);
  #|       }
  #|       if (request.action === 'remove') deleted.add(request.session);
  #|       return enqueue(() => account === scope
  #|         ? transact(request.origin, request.user, request.action, request.session, request.page, scope)
  #|         : null);
  #|     }
  #|   };
  #| }

///|
fn State::cache_account_changed(self : State, previous : String?) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => {
    if !native_history_cache() {
      let clear : String? = if self.user_id is None { previous } else { None }
      let request : Json = {
        "origin": @cloud_client.CloudOrigin,
        "epoch": self.epoch,
        "user": self.user_id.map_or(Json::null(), value => Json(value)),
        "clear": clear.map_or(Json::null(), value => Json(value)),
      }
      try {
        let _ : @js.Value = indexed_history_store.apply_with_string(
          "activate",
          [@js.Value::from_json(request)],
        )
      } catch {
        _ => ()
      }
    }
  })
}

///|
async fn State::indexed_history_cache(
  self : State,
  action : @protocol.CloudHistoryCacheAction,
) -> @protocol.CloudHistoryCacheReply {
  guard self.user_id is Some(user) else { return Done }
  let fields : Map[String, Json] = {
    "origin": @cloud_client.CloudOrigin,
    "user": user,
    "epoch": self.epoch,
  }
  match action {
    List => fields["action"] = Json("list")
    Read(session~) => {
      fields["action"] = Json("read")
      fields["session"] = Json(session)
    }
    Write(session~, page~) => {
      fields["action"] = Json("write")
      fields["session"] = Json(session)
      fields["page"] = page.to_json()
    }
    Remove(session~) => {
      fields["action"] = Json("remove")
      fields["session"] = Json(session)
    }
  }
  let value = @interop.js_method_promise(
      indexed_history_store,
      "request",
      @js.Value::from_json(Json(fields)),
    )
    .wait()
    .to_json() catch {
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
    Read(_) => Page(Some(@json.from_json(value)) catch { _ => None })
    _ => Done
  }
}

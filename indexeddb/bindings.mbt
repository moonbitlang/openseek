// Browser primitives only; public contracts and schema policy live in MoonBit.

///|
extern "js" fn catch_ffi(
  body : () -> Value,
  ok : (Value) -> Unit,
  fail : (String, String) -> Unit,
) -> Unit =
  #| (body, ok, fail) => { try { ok(body()); } catch (e) { fail(e.name || 'Error', e.message || String(e)); } }

///|
extern "js" fn open_ffi(
  name : String,
  version : Int32,
  signal : @js_async.AbortSignal,
  upgrade : (Database, RawTransaction, Int32) -> Unit,
  ok : (Database) -> Result[Database, IndexedDBError],
  fail : (String, String) -> Result[Database, IndexedDBError],
) -> @js_async.Promise[Result[Database, IndexedDBError]] =
  #| (name, version, signal, upgrade, ok, fail) => new Promise(resolve => {
  #|   let abandoned = false;
  #|   try {
  #|     const request = indexedDB.open(name, version);
  #|     request.onupgradeneeded = event => {
  #|       if (abandoned || signal.aborted) request.transaction.abort();
  #|       else upgrade(request.result, request.transaction, event.oldVersion);
  #|     };
  #|     request.onerror = () => resolve(fail(request.error.name, request.error.message));
  #|     request.onblocked = () => { abandoned = true; resolve(fail('BlockedError', 'Another connection is blocking the database upgrade.')); };
  #|     request.onsuccess = () => {
  #|       const db = request.result;
  #|       db.onversionchange = () => db.close();
  #|       signal.addEventListener('abort', () => db.close(), { once: true });
  #|       if (abandoned || signal.aborted) db.close(); else resolve(ok(db));
  #|     };
  #|   } catch (e) { resolve(fail(e.name || 'Error', e.message || String(e))); }
  #| })

///|
pub extern "js" fn Database::close(self : Database) -> Unit =
  #| db => db.close()

///|
extern "js" fn Database::create_store_ffi(
  self : Database,
  name : String,
  path : String,
) -> ObjectStore =
  #| (db, name, path) => { const keyPath = JSON.parse(path); return db.createObjectStore(name, keyPath === null ? {} : { keyPath }); }

///|
extern "js" fn ObjectStore::create_index_ffi(
  self : ObjectStore,
  name : String,
  path : String,
) -> Index =
  #| (store, name, path) => store.createIndex(name, JSON.parse(path))

///|
extern "js" fn Database::transaction_ffi(
  self : Database,
  stores : String,
  write : Bool,
) -> RawTransaction =
  #| (db, stores, write) => db.transaction(JSON.parse(stores), write ? 'readwrite' : 'readonly')

///|
extern "js" fn RawTransaction::store_ffi(
  self : RawTransaction,
  name : String,
) -> ObjectStore =
  #| (tx, name) => tx.objectStore(name)

///|
extern "js" fn RawTransaction::abort_ffi(self : RawTransaction) -> Unit =
  #| tx => tx.abort()

///|
extern "js" fn RawTransaction::completion_ffi(
  self : RawTransaction,
  ok : () -> Result[Unit, IndexedDBError],
  fail : (String, String) -> Result[Unit, IndexedDBError],
) -> @js_async.Promise[Result[Unit, IndexedDBError]] =
  #| (tx, ok, fail) => new Promise(resolve => {
  #|   tx.oncomplete = () => resolve(ok());
  #|   tx.onabort = () => resolve(fail(tx.error?.name || 'AbortError', tx.error?.message || 'The transaction was aborted.'));
  #| })

///|
extern "js" fn ObjectStore::get_ffi(
  self : ObjectStore,
  key : String,
) -> RawRequest =
  #| (store, key) => store.get(JSON.parse(key))

///|
extern "js" fn ObjectStore::put_ffi(
  self : ObjectStore,
  value : String,
  key : String,
) -> RawRequest =
  #| (store, value, key) => { key = JSON.parse(key); return key === null ? store.put(JSON.parse(value)) : store.put(JSON.parse(value), key); }

///|
extern "js" fn ObjectStore::delete_ffi(
  self : ObjectStore,
  key : String,
) -> RawRequest =
  #| (store, key) => store.delete(JSON.parse(key))

///|
extern "js" fn ObjectStore::index_ffi(
  self : ObjectStore,
  name : String,
) -> Index =
  #| (store, name) => store.index(name)

///|
extern "js" fn Index::get_all_ffi(self : Index, key : String) -> RawRequest =
  #| (index, key) => { key = JSON.parse(key); return index.getAll(key === null ? undefined : IDBKeyRange.only(key)); }

///|
extern "js" fn Index::read_only_ffi(self : Index) -> Bool =
  #| index => index.objectStore.transaction.mode === 'readonly'

///|
extern "js" fn Index::delete_all_ffi(self : Index, key : String) -> RawRequest =
  #| (index, key) => {
  #|   key = JSON.parse(key);
  #|   const request = index.openCursor(key === null ? undefined : IDBKeyRange.only(key));
  #|   request.onsuccess = event => {
  #|     const cursor = event.target.result;
  #|     if (cursor) { cursor.delete(); cursor.continue(); }
  #|   };
  #|   return request;
  #| }

///|
extern "js" fn RawRequest::result_ffi(
  self : RawRequest,
  found : (String) -> Unit,
) -> Unit =
  #| (request, found) => { if (request.result !== undefined) found(JSON.stringify(request.result)); }

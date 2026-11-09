// IndexedDB bindings only. Cache policy and operation lifetimes live in MoonBit.

///|
#external
priv type HistoryDatabase

///|
#external
priv type HistoryTransaction

///|
#external
priv type HistoryRequest

///|
extern "js" fn open_history_database(
  signal : @js_async.AbortSignal,
) -> @js.Promise[HistoryDatabase] =
  #| signal => new Promise((resolve, reject) => {
  #|   const request = indexedDB.open('seekmoon.cloud-history.v1', 1);
  #|   request.onupgradeneeded = () => {
  #|     request.result.createObjectStore('pages', { keyPath: ['origin', 'user', 'session'] })
  #|       .createIndex('account', ['origin', 'user']);
  #|   };
  #|   request.onerror = request.onblocked = () => reject(request.error);
  #|   request.onsuccess = () => {
  #|     const db = request.result;
  #|     db.onversionchange = () => db.close();
  #|     signal.addEventListener('abort', () => db.close(), { once: true });
  #|     if (signal.aborted) db.close(); else resolve(db);
  #|   };
  #| })

///|
extern "js" fn HistoryDatabase::close(self : HistoryDatabase) -> Unit =
  #| db => db.close()

///|
extern "js" fn HistoryDatabase::transaction(
  self : HistoryDatabase,
  write : Bool,
) -> HistoryTransaction =
  #| (db, write) => db.transaction('pages', write ? 'readwrite' : 'readonly')

///|
extern "js" fn HistoryTransaction::abort(self : HistoryTransaction) -> Unit =
  #| tx => tx.abort()

///|
extern "js" fn HistoryTransaction::completion(
  self : HistoryTransaction,
) -> @js.Promise[Unit] =
  #| tx => new Promise((resolve, reject) => {
  #|   tx.oncomplete = () => resolve();
  #|   tx.onerror = tx.onabort = () => reject(tx.error);
  #| })

///|
extern "js" fn HistoryTransaction::read(
  self : HistoryTransaction,
  key : FixedArray[String],
) -> HistoryRequest =
  #| (tx, key) => tx.objectStore('pages').get(key)

///|
extern "js" fn HistoryTransaction::list(
  self : HistoryTransaction,
  origin : String,
  user : String,
) -> HistoryRequest =
  #| (tx, origin, user) => tx.objectStore('pages').index('account').getAll(IDBKeyRange.only([origin, user]))

///|
extern "js" fn HistoryTransaction::write(
  self : HistoryTransaction,
  row : @js.Value,
) -> HistoryRequest =
  #| (tx, row) => tx.objectStore('pages').put(row)

///|
extern "js" fn HistoryTransaction::remove(
  self : HistoryTransaction,
  key : FixedArray[String],
) -> HistoryRequest =
  #| (tx, key) => tx.objectStore('pages').delete(key)

///|
extern "js" fn HistoryTransaction::clear_account(
  self : HistoryTransaction,
  origin : String,
  user : String,
) -> HistoryRequest =
  #| (tx, origin, user) => {
  #|   const request = tx.objectStore('pages').index('account').openCursor(IDBKeyRange.only([origin, user]));
  #|   request.onsuccess = event => {
  #|     const cursor = event.target.result;
  #|     if (cursor) { cursor.delete(); cursor.continue(); }
  #|   };
  #|   return request;
  #| }

///|
extern "js" fn HistoryRequest::value(self : HistoryRequest) -> @js.Value =
  #| request => request.result ?? null

///|
fn[T] history_binding(call : () -> T) -> T raise @js.Error_ {
  @js.Error_::wrap(() => @js.Value::cast_from(call()), map_ok=@js.Value::cast)
}

///|
/// Open a versioned database and run schema changes during `upgrade`.
/// The callback is synchronous. Connections close on version change; blocked
/// opens fail with `BlockedError`. Cancellation closes a late connection.
pub async fn open(
  name : String,
  version : Int32,
  upgrade~ : (Database, Transaction, Int32) -> Unit raise,
) -> Database {
  let mut upgrade_error : Error? = None
  let result = @js_async.run_promise(signal => {
    open_ffi(
      name,
      version,
      signal,
      (db, raw, previous) => {
        let tx = transaction(raw)
        upgrade(db, tx, previous) catch {
          error => {
            upgrade_error = Some(error)
            tx.abort() catch {
              _ => ()
            }
          }
        }
      },
      db => Ok(db),
      (name, message) => Err(IndexedDBError(name~, message~)),
    )
  })
  if upgrade_error is Some(error) {
    raise error
  }
  match result {
    Ok(db) => db
    Err(error) => raise error
  }
}

///|
/// Create a store during an upgrade. Omitting the key path uses explicit keys.
pub fn Database::create_store(
  self : Database,
  name : String,
  key_path? : KeyPath,
) -> ObjectStore raise IndexedDBError {
  call(() => {
    self.create_store_ffi(
      name,
      key_path.map_or("null", key => key.json().stringify()),
    )
  })
}

///|
pub fn ObjectStore::create_index(
  self : ObjectStore,
  name : String,
  key_path : KeyPath,
) -> Index raise IndexedDBError {
  call(() => self.create_index_ffi(name, key_path.json().stringify()))
}

///|
pub fn Database::transaction(
  self : Database,
  stores : Array[String],
  mode : Mode,
) -> Transaction raise IndexedDBError {
  transaction(
    call(() => self.transaction_ffi(Json(stores).stringify(), mode is ReadWrite)),
  )
}

///|
fn transaction(raw : RawTransaction) -> Transaction {
  {
    raw,
    completion: raw.completion_ffi(() => Ok(()), (name, message) => {
      Err(IndexedDBError(name~, message~))
    }),
  }
}

///|
pub fn Transaction::store(
  self : Transaction,
  name : String,
) -> ObjectStore raise IndexedDBError {
  call(() => self.raw.store_ffi(name))
}

///|
pub fn Transaction::abort(self : Transaction) -> Unit raise IndexedDBError {
  call(() => self.raw.abort_ffi())
}

///|
/// Wait for commit or abort. Request errors are reported through this wait.
pub async fn Transaction::wait(self : Transaction) -> Unit {
  match
    self.completion.wait(abort_controller=@js_async.AbortController::new()) {
    Ok(_) => ()
    Err(error) => raise error
  }
}

///|
pub fn ObjectStore::get(
  self : ObjectStore,
  key : Key,
) -> Request raise IndexedDBError {
  { raw: call(() => self.get_ffi(key.json().stringify())), }
}

///|
pub fn ObjectStore::put(
  self : ObjectStore,
  value : Json,
  key? : Key,
) -> Request raise IndexedDBError {
  {
    raw: call(() => {
      self.put_ffi(
        value.stringify(),
        key.map_or("null", key => key.json().stringify()),
      )
    }),
  }
}

///|
pub fn ObjectStore::delete(
  self : ObjectStore,
  key : Key,
) -> Request raise IndexedDBError {
  { raw: call(() => self.delete_ffi(key.json().stringify())), }
}

///|
pub fn ObjectStore::index(
  self : ObjectStore,
  name : String,
) -> Index raise IndexedDBError {
  call(() => self.index_ffi(name))
}

///|
pub fn Index::get_all(self : Index, key? : Key) -> Request raise IndexedDBError {
  {
    raw: call(() => {
      self.get_all_ffi(key.map_or("null", key => key.json().stringify()))
    }),
  }
}

///|
/// Delete matching records in the index's read/write transaction.
pub fn Index::delete_all(
  self : Index,
  key? : Key,
) -> Request raise IndexedDBError {
  if self.read_only_ffi() {
    raise IndexedDBError(
      name="ReadOnlyError",
      message="Deleting records requires a read/write transaction.",
    )
  }
  {
    raw: call(() => {
      self.delete_all_ffi(key.map_or("null", key => key.json().stringify()))
    }),
  }
}

///|
/// Read a completed request. Missing records return `None`; stored JSON null
/// returns `Some(Json::null())`. An unfinished request raises `InvalidStateError`.
pub fn Request::result(self : Request) -> Json? raise IndexedDBError {
  let mut value : String? = None
  call(() => self.raw.result_ffi(text => value = Some(text)))
  value.map(text => {
    @json.parse(text) catch {
      _ =>
        raise IndexedDBError(
          name="DataError",
          message="The result is not JSON data.",
        )
    }
  })
}

///|
fn[T] call(body : () -> T) -> T raise IndexedDBError {
  let mut value : T? = None
  let mut error : IndexedDBError? = None
  catch_ffi(() => Value::from(body()), v => value = Some(v.cast()), (
    name,
    message,
  ) => error = Some(IndexedDBError(name~, message~)))
  if error is Some(error) {
    raise error
  }
  value.unwrap()
}

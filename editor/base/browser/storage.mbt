///|
/// Storage access failures are distinct from a missing key. Hosts decide
/// whether persistence is optional or must be reported to the user.
pub(all) enum StorageFailure {
  Unavailable
  AccessFailed(String)
} derive(Debug)

///|
fn[T] with_local_storage(
  op : (BrowserStorage) -> T,
) -> Result[T, StorageFailure] {
  @js.Error_::wrap(
    () => {
      match browser_local_storage().to_option() {
        None =>
          @js.Value::cast_from((Err(Unavailable) : Result[T, StorageFailure]))
        Some(storage) =>
          @js.Value::cast_from((Ok(op(storage)) : Result[T, StorageFailure]))
      }
    },
    map_ok=value => (value.cast() : Result[T, StorageFailure]),
  ) catch {
    error => Err(AccessFailed(error.to_string()))
  }
}

///|
/// Read a local preference. `Ok(None)` means the key is absent; an empty
/// stored string remains `Ok(Some(""))`. Storage failures remain errors.
pub fn local_storage_get(key : String) -> Result[String?, StorageFailure] {
  with_local_storage(storage => storage.get_item(key).to_option())
}

///|
/// Persist a value, retaining access and quota failures for the host.
pub fn local_storage_set(
  key : String,
  value : String,
) -> Result[Unit, StorageFailure] {
  with_local_storage(storage => storage.set_item(key, value))
}

///|
/// Remove a key. Removing an absent key succeeds.
pub fn local_storage_remove(key : String) -> Result[Unit, StorageFailure] {
  with_local_storage(storage => storage.remove_item(key))
}

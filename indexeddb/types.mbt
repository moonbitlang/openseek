///|
/// A JSON-compatible IndexedDB key. Array keys preserve their element types.
pub(all) enum Key {
  String(String)
  Number(Double)
  Array(Array[Key])
}

///|
pub(all) enum KeyPath {
  Field(String)
  Fields(Array[String])
}

///|
pub(all) enum Mode {
  ReadOnly
  ReadWrite
}

///|
pub(all) suberror IndexedDBError {
  IndexedDBError(name~ : String, message~ : String)
}

///|
#external
pub type Database

///|
#external
pub type ObjectStore

///|
#external
pub type Index

///|
#external
priv type RawTransaction

///|
#external
priv type RawRequest

///|
/// Requests must be issued synchronously while this transaction is active.
/// Await `wait` before inspecting results. Abort explicitly when abandoning it.
struct Transaction {
  raw : RawTransaction
  completion : @js_async.Promise[Result[Unit, IndexedDBError]]
}

///|
struct Request {
  raw : RawRequest
}

///|
fn Key::json(self : Key) -> Json {
  match self {
    String(value) => Json(value)
    Number(value) => Json(value)
    Array(values) => Json(values.map(key => key.json()))
  }
}

///|
fn KeyPath::json(self : KeyPath) -> Json {
  match self {
    Field(name) => Json(name)
    Fields(names) => Json(names)
  }
}

///|
#external
priv type Value

///|
fn[T] Value::from(value : T) -> Value = "%identity"

///|
fn[T] Value::cast(self : Value) -> T = "%identity"

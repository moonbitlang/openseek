///|
priv enum BootstrapRecord {
  Progress(String)
  Endpoint(port~ : Int32, instance~ : String)
}

///|
/// Recognized records are strict: malformed endpoints must fail rather than
/// making the user wait for startup to time out. Unknown fields are ignored.
impl FromJson for BootstrapRecord with fn from_json(json, path) {
  match json {
    { "stage": String(stage), .. } => Progress(stage)
    {
      "port": Number(port, ..),
      "instance": String(instance),
      "protocol": 1,
      ..
    } if port >= 1 && port <= 65535 && port == port.to_int().to_double() =>
      Endpoint(port=port.to_int(), instance~)
    _ =>
      raise JsonDecodeError(
        (path, "expected SSH progress or protocol 1 endpoint"),
      )
  }
}

///|
/// Login-shell banners (including unrelated JSON) are not bootstrap records.
fn bootstrap_record(line : String) -> BootstrapRecord? raise {
  let value = @json.parse(line) catch { _ => return None }
  guard value is Object(fields) &&
    (fields.contains("stage") || fields.contains("port")) else {
    return None
  }
  Some(@json.from_json(value))
}

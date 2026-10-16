///|
pub const ProtocolVersion : Int32 = 1

///|
pub(all) struct Initialize {
  build_id : String
  protocol_version : Int32
}

///|
pub impl FromJson for Initialize with fn from_json(json, path) {
  let obj = object_fields(json, path, "server.initialize")
  let build_id = required_string(obj, path, "build_id")
  guard !build_id.is_empty() else {
    raise JsonDecodeError((path, "empty build_id"))
  }
  {
    build_id,
    protocol_version: exact_int(
      obj.get("protocol_version").unwrap_or(Json::null()),
      path.add_key("protocol_version"),
    ),
  }
}

///|
pub impl ToJson for Initialize with fn to_json(self) {
  { "build_id": self.build_id, "protocol_version": self.protocol_version }
}

///|
pub(all) struct Identity {
  server_id : String
  instance_id : String
  build_id : String
  protocol_version : Int32
  platform : String
  home : String
  data_dir : String
  status : String
}

///|
pub impl ToJson for Identity with fn to_json(self) {
  {
    "server_id": self.server_id,
    "instance_id": self.instance_id,
    "build_id": self.build_id,
    "protocol_version": self.protocol_version,
    "platform": self.platform,
    "home": self.home,
    "data_dir": self.data_dir,
    "status": self.status,
  }
}

///|
pub impl FromJson for Identity with fn from_json(json, path) {
  let obj = object_fields(json, path, "server identity")
  {
    server_id: required_string(obj, path, "server_id"),
    instance_id: required_string(obj, path, "instance_id"),
    build_id: required_string(obj, path, "build_id"),
    protocol_version: exact_int(
      obj.get("protocol_version").unwrap_or(Json::null()),
      path.add_key("protocol_version"),
    ),
    platform: required_string(obj, path, "platform"),
    home: required_string(obj, path, "home"),
    data_dir: required_string(obj, path, "data_dir"),
    status: required_string(obj, path, "status"),
  }
}

///|
pub fn shutdown_grace_seconds(
  params : Json,
) -> Int32 raise @json.JsonDecodeError {
  let Shutdown(grace) = @json.from_json(params)
  grace
}

///|
priv struct Shutdown(Int32)

///|
impl FromJson for Shutdown with fn from_json(params, path) {
  let obj = object_fields(params, path, "server.shutdown")
  let grace = match obj.get("shutdown_grace_seconds") {
    None | Some(Null) => 60
    Some(value) => exact_int(value, path.add_key("shutdown_grace_seconds"))
  }
  guard grace >= 0 && grace <= 300 else {
    raise JsonDecodeError((path, "shutdown_grace_seconds must be in 0..300"))
  }
  Shutdown(grace)
}

///|
pub extend Initialize with FromJson::{from_json}

///|
pub extend Initialize with ToJson::{to_json}

///|
pub extend Identity with FromJson::{from_json}

///|
pub extend Identity with ToJson::{to_json}

///|
fn exact_int(
  value : Json,
  path : @json.JsonPath,
) -> Int32 raise @json.JsonDecodeError {
  match value {
    Number(n, ..) if n >= 0 && n <= 2147483647.0 && n.to_int().to_double() == n =>
      n.to_int()
    _ => raise JsonDecodeError((path, "expected exact nonnegative integer"))
  }
}

///|
fn object_fields(
  value : Json,
  path : @json.JsonPath,
  expected : String,
) -> Map[String, Json] raise @json.JsonDecodeError {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected " + expected + " object"))
  }
  fields
}

///|
fn required_string(
  fields : Map[String, Json],
  path : @json.JsonPath,
  name : String,
) -> String raise @json.JsonDecodeError {
  guard fields.get(name) is Some(String(value)) else {
    raise JsonDecodeError((path.add_key(name), "expected string"))
  }
  value
}

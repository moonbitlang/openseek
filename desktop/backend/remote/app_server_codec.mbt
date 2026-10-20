///|
priv struct AppServerAnnouncement {
  port : Int32
  instance : String
}

///|
impl ToJson for AppServerAnnouncement with fn to_json(self) {
  { "port": self.port, "instance": self.instance, "protocol": 1 }
}

///|
priv struct AppServerInitializeRequest {
  id : Json
  instance : String
}

///|
// Required fields must match protocol 1; missing, null, and malformed fields
// are rejected. Unknown fields are ignored at both object levels. The request
// ID remains an opaque, required JSON value (including null), echoed unchanged.
impl FromJson for AppServerInitializeRequest with fn from_json(json, path) {
  guard json
    is {
      "jsonrpc": "2.0",
      "id": id,
      "method": "initialize",
      "params": { "protocol": 1, "instance": String(instance), .. },
      ..
    } else {
    raise JsonDecodeError(
      (path, "expected app-server protocol 1 initialize request"),
    )
  }
  { id, instance, }
}

///|
priv struct AppServerInitializeResponse {
  id : Json
  instance : String
}

///|
impl ToJson for AppServerInitializeResponse with fn to_json(self) {
  {
    "jsonrpc": "2.0",
    "id": self.id,
    "result": { "protocol": 1, "instance": self.instance },
  }
}

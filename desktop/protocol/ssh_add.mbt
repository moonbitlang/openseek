///|
/// A friendly SSH entry. Runtime paths are discovered on the selected host;
/// absence of an override is represented explicitly on the wire.
pub(all) struct SshAdd {
  name : String
  destination : String
  port : Int32?
}

///|
pub impl FromJson for SshAdd with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "SshAdd")
  {
    name: object.required_string("name"),
    destination: object.required_string("destination"),
    port: object.optional_int("port"),
  }
}

///|
pub impl ToJson for SshAdd with fn to_json(self) {
  let fields : Map[String, Json] = {
    "name": Json(self.name),
    "destination": Json(self.destination),
  }
  if self.port is Some(port) {
    fields["port"] = Json(port)
  }
  Json(fields)
}

///|
pub extend SshAdd with FromJson::{from_json}

///|
pub extend SshAdd with ToJson::{to_json}

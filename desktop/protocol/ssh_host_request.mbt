///|
/// Desktop-owned operations on one SSH host (including its independent PTYs).
/// These do not use the app-server connection's epoch.
pub(all) struct SshHostRequest {
  host_id : String
  method_ : String
  params : Json
}

///|
pub impl FromJson for SshHostRequest with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "SSH host request")
  {
    host_id: object.required_string("host_id"),
    method_: object.required_string("method"),
    params: object.required_json("params"),
  }
}

///|
pub impl ToJson for SshHostRequest with fn to_json(self) {
  { "host_id": self.host_id, "method": self.method_, "params": self.params }
}

///|
pub extend SshHostRequest with FromJson::{from_json}

///|
pub extend SshHostRequest with ToJson::{to_json}

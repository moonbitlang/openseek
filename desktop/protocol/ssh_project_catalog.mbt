///|
pub(all) struct SshProjectCatalog {
  id : String
  paths : Array[String]
}

///|
pub impl FromJson for SshProjectCatalog with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "SSH project catalog")
  {
    id: object.required_string("id"),
    paths: @json.from_json(
      object.required_json("paths"),
      path=path.add_key("paths"),
    ),
  }
}

///|
pub impl ToJson for SshProjectCatalog with fn to_json(self) {
  { "id": self.id, "paths": self.paths }
}

///|
pub extend SshProjectCatalog with FromJson::{from_json}

///|
pub extend SshProjectCatalog with ToJson::{to_json}

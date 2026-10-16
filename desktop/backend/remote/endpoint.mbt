///|
/// Discovery record for SSH forwarding. TCP addresses are IPv4 loopback.
pub(all) struct Endpoint {
  port : Int32
  instance_id : String
} derive(FromJson, ToJson)

///|
pub fn Endpoint::validate(self : Endpoint) -> Unit raise {
  guard self.port > 0 && self.port <= 65535 && !self.instance_id.is_blank() else {
    fail("invalid working-host endpoint")
  }
}

///|
pub extend Endpoint with @json.FromJson::{from_json}

///|
pub extend Endpoint with ToJson::{to_json}

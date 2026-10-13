///|
/// Current client/server wire-protocol version.
pub fn protocol_version() -> Int32 {
  protocol_version_impl()
}

///|
/// Accepts only the exact current protocol version.
pub fn negotiate_protocol_version(version : Int32) -> ProtocolNegotiation {
  negotiate_protocol_version_impl(version)
}

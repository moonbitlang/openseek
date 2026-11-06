///|
/// A wire resource path parsed into the host's native absolute path type.
/// This validates the protocol's path spelling only; it does not derive or
/// authorize a conversation workspace.
fn wire_path(path : String) -> @pathx.Absolute raise FilesError {
  guard @pathx.Absolute::from_uri_path(path) is Some(absolute) else {
    raise InvalidRequest("path is not absolute")
  }
  absolute.normalize()
}

///|
/// Resolve a protocol-relative `path` against its explicit `root`. Relative
/// components retain their ordinary path meaning; this constructs an address
/// and deliberately does not enforce workspace containment.
fn resolve_wire_path(
  root : @pathx.Absolute,
  path : String,
) -> @pathx.Absolute raise FilesError {
  guard @pathx.Path(path).to_relative() is Some(relative) else {
    raise InvalidRequest("path is not relative to root")
  }
  root.join(relative).normalize()
}

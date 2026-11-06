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

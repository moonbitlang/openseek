///|
#derive(Debug)
pub suberror LanguageError {
  InvalidRequest(String)
  RootNotOwned
  RootMismatch
  PathOutsideRoot
  UnsupportedRoot
  Unavailable(String)
  MoonIdeFailed(String)
}

///|
impl Show for LanguageError with fn output(self, logger) {
  match self {
    InvalidRequest(message) | MoonIdeFailed(message) =>
      logger.write_string(message)
    RootNotOwned =>
      logger.write_string(
        "root has no directory ownership for this conversation",
      )
    RootMismatch =>
      logger.write_string("root does not match the conversation checkout")
    PathOutsideRoot => logger.write_string("path is outside root")
    UnsupportedRoot =>
      logger.write_string("UNC paths are not supported by frontend resources")
    Unavailable(subject) => logger.write_string("\{subject} is unavailable")
  }
}

///|
pub extend LanguageError with Debug::{to_repr}

///|
/// Encode a host-native absolute path for the frontend resource URI. UNC is
/// outside the transport contract because the URI authority is reserved for
/// the device channel rather than a filesystem server.
fn @pathx.Absolute::resource_path(
  self : @pathx.Absolute,
) -> String raise LanguageError {
  guard self.to_uri_path() is Some(path) else { raise UnsupportedRoot }
  path
}

///|
fn root_relative_file(
  root : @pathx.Absolute,
  path : String,
) -> @pathx.Absolute raise LanguageError {
  guard @pathx.Path(path).to_relative() is Some(relative) else {
    raise InvalidRequest("path is not relative to root")
  }
  root.join(relative).normalize()
}

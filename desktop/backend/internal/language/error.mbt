///|
#derive(Debug)
pub suberror LanguageError {
  InvalidRequest(String)
  RootNotOwned
  RootMismatch
  PathOutsideRoot
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
    Unavailable(subject) => logger.write_string("\{subject} is unavailable")
  }
}

///|
pub extend LanguageError with Debug::{to_repr}

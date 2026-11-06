///|
/// A file operation the request cannot be served by, carrying the message
/// shown to the user. Operating-system failures propagate as they are.
priv suberror FilesError {
  InvalidRequest(String)
  NoHomeDirectory
}

///|
impl Show for FilesError with fn output(self, logger) {
  match self {
    InvalidRequest(message) => logger.write_string(message)
    NoHomeDirectory =>
      logger.write_string("cannot determine the home directory")
  }
}

///|
/// A Git operation failure, carrying the message shown to the user.
pub suberror GitError {
  InvalidRequest(String)
  Failed(String)
  Stale(String)
}

///|
pub impl Show for GitError with fn output(self, logger) {
  match self {
    InvalidRequest(message) | Failed(message) | Stale(message) =>
      logger.write_string(message)
  }
}

///|
pub extend GitError with Show::{output, to_string}

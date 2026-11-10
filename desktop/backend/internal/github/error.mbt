///|
/// A GitHub operation failure. Every variant except
/// `DraftsUnavailable` carries the message shown to the user.
pub suberror GithubError {
  InvalidRequest(String)
  InvalidResponse(String)
  Unavailable(String)
  Stale(String)
  GitFailed(String)
  DraftsUnavailable
}

///|
pub impl Show for GithubError with fn output(self, logger) {
  match self {
    InvalidRequest(message)
    | InvalidResponse(message)
    | Unavailable(message)
    | Stale(message)
    | GitFailed(message) => logger.write_string(message)
    DraftsUnavailable =>
      logger.write_string("Local comment draft storage is unavailable.")
  }
}

///|
pub extend GithubError with Show::{output, to_string}

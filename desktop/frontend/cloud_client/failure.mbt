///|
#derive(Eq, Debug)
pub(all) enum Failure {
  Unauthorized
  Busy
  Http(Int32)
  Unreachable
  Malformed
  ExportUnavailable
  ServiceNotConfigured
  SignInFailed(String)
  InvalidImage
}

///|
pub extend Failure with Eq::{equal, not_equal}

///|
pub extend Failure with Debug::{to_repr}

///|
pub fn Failure::label(self : Failure) -> String {
  self.text(English)
}

///|
pub(all) suberror RequestError {
  RequestError(Failure)
}

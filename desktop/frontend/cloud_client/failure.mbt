///|
#derive(Eq)
pub(all) enum Failure {
  Unauthorized
  Busy
  Http(Int32)
  Unreachable
  Malformed
  ExportUnavailable
  ServiceNotConfigured
  SignInFailed(String)
  RemoteMessage(String)
  InvalidImage
}

///|
pub extend Failure with Eq::{equal, not_equal}

///|
pub(all) suberror RequestError {
  RequestError(Failure)
}

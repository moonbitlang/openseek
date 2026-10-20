///|
pub(all) enum Failure {
  Unauthorized
  Busy
  Http(Int32)
  Unreachable
  Malformed
  ServiceNotConfigured
  CredentialServiceUnavailable
  SignInFailed(String)
  InvalidImage
}

///|
pub fn Failure::label(self : Failure) -> String {
  match self {
    Unauthorized => "Your account sign-in expired. Sign in again to continue."
    Busy => "This conversation is already generating. Loading its history…"
    Http(status) => "Cloud answered HTTP \{status}. Try again."
    Unreachable => "Cloud is unreachable. Check your connection and try again."
    Malformed => "Cloud returned an invalid response. Try again."
    ServiceNotConfigured =>
      "Cloud model credentials are not configured. Contact the service administrator."
    SignInFailed(message) => message
    InvalidImage => "Choose a valid PNG, JPEG, GIF or WebP image up to 5 MiB."
    CredentialServiceUnavailable =>
      "The sign-in service is unavailable. Try again."
  }
}

///|
pub(all) suberror RequestError {
  RequestError(Failure)
}

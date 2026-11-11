///|
/// Keep account storage failures semantic until the current locale is rendered.
#derive(Eq)
pub(all) enum Failure {
  StorageUnavailable
  StorageReadFailed(String)
  SignInTimedOut
  SignInCheckHttp(Int32)
  SignInCheckMalformed
  RelayUnreachable(String)
  RelayHttp(Int32)
  DeviceListHttp(Int32)
  DeviceListMalformed
  Cloud(@cloud_client.Failure)
  Bridge(@interop.BridgeProblem)
  Diagnostic(String)
}

///|
pub extend Failure with Eq::{equal, not_equal}

///|
pub fn Failure::text(self : Failure, locale : @i18n.Locale) -> String {
  match self {
    StorageUnavailable => text(locale, StorageUnavailable)
    StorageReadFailed(detail) => text(locale, StorageReadFailed(detail))
    SignInTimedOut => text(locale, SignInTimedOut)
    SignInCheckHttp(status) => text(locale, SignInCheckHttp(status))
    SignInCheckMalformed => text(locale, SignInCheckMalformed)
    RelayUnreachable(detail) => text(locale, RelayUnreachable(detail))
    RelayHttp(status) => text(locale, RelayHttp(status))
    DeviceListHttp(status) => text(locale, DeviceListHttp(status))
    DeviceListMalformed => text(locale, DeviceListMalformed)
    Cloud(failure) => failure.text(locale)
    Bridge(problem) => problem.text(locale)
    Diagnostic(detail) => detail
  }
}

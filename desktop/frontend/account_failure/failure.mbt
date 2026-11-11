///|
/// Keep account storage failures semantic until the current locale is rendered.
#derive(Eq, Debug)
pub(all) enum Failure {
  StorageUnavailable
  StorageReadFailed(String)
  SignInTimedOut
  Diagnostic(String)
}

///|
pub extend Failure with Eq::{equal, not_equal}

///|
pub extend Failure with Debug::{to_repr}

///|
pub fn Failure::text(self : Failure, locale : @i18n.Locale) -> String {
  match self {
    StorageUnavailable => text(locale, StorageUnavailable)
    StorageReadFailed(detail) => text(locale, StorageReadFailed(detail))
    SignInTimedOut => text(locale, SignInTimedOut)
    Diagnostic(detail) => detail
  }
}

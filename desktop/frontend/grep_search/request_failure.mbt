///|
#derive(Eq)
pub(all) enum RequestFailure {
  Cloud(@cloud_client.Failure)
  Bridge(@interop.BridgeProblem)
  Diagnostic(String)
}

///|
pub extend RequestFailure with Eq::{equal, not_equal}

///|
fn RequestFailure::text(self : RequestFailure, locale : @i18n.Locale) -> String {
  match self {
    Cloud(failure) => failure.text(locale)
    Bridge(problem) => problem.text(locale)
    Diagnostic(detail) => detail
  }
}

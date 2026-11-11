///|
#derive(Eq)
pub(all) enum Failure {
  Cloud(@cloud_client.Failure)
  Bridge(@interop.BridgeProblem)
  Diagnostic(String)
  FileTooLarge
}

///|
pub extend Failure with Eq::{equal, not_equal}

///|
fn Failure::text(self : Failure, locale : @i18n.Locale) -> String {
  match (locale, self) {
    (_, Cloud(failure)) => failure.text(locale)
    (_, Bridge(problem)) => problem.text(locale)
    (_, Diagnostic(detail)) => detail
    (English, FileTooLarge) => "JSON must be no larger than 16 MiB."
    (Spanish, FileTooLarge) => "El JSON no puede superar los 16 MiB."
    (SimplifiedChinese, FileTooLarge) => "JSON 不得超过 16 MiB。"
    (TraditionalChinese, FileTooLarge) => "JSON 不得超過 16 MiB。"
    (Japanese, FileTooLarge) => "JSON は 16 MiB 以下にしてください。"
  }
}

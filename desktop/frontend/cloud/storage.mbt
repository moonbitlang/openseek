///|
/// The former independent Cloud credential is never restored or merged.
pub fn discard_legacy_credential() -> Unit {
  @base_browser.local_storage_remove("seekmoon.cloud.token.v1") |> ignore
}

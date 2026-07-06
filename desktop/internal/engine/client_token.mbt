// The client credential the host presents to the official OpenSeek proxy.

///|
/// Stamped by release packaging: `build_native_host` rewrites this constant
/// from the packaging machine's OPENSEEK_CLIENT_TOKEN environment for the
/// duration of the host build and restores it afterwards, so the public
/// repository never carries the real token. Empty means unstamped — the
/// host falls back to the placeholder key, which the proxy accepts only
/// while server-side token enforcement is off.
const StampedOpenseekClientToken : String = ""

///|
/// The client token to present to the official OpenSeek proxy: the runtime
/// environment override first (development builds are unstamped), then the
/// packaged-in stamp; None when neither is set.
fn openseek_client_token() -> String? {
  if @env.get("OPENSEEK_CLIENT_TOKEN") is Some(token) {
    return Some(token)
  }
  if StampedOpenseekClientToken.is_empty() {
    None
  } else {
    Some(StampedOpenseekClientToken)
  }
}

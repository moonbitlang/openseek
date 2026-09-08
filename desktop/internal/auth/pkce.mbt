// The PKCE pieces of the loopback sign-in (docs/remote-protocol.md,
// "Desktop sign-in"): challenge derivation, the start URL the system
// browser opens, and the loopback callback parser. All pure — the flow in
// signin.mbt wires them to the listener and the exchange.

///|
/// The standard S256 challenge (RFC 7636): the unpadded base64url of the
/// verifier's SHA-256, exactly what the relay's `challenge_s256` computes
/// on its side of the comparison. Core's encoder speaks only the standard
/// alphabet, so its two URL-unsafe characters are swapped after the fact.
fn pkce_challenge(verifier : String) -> String {
  let digest = Bytes::from_array(@crypto.sha256(@utf8.encode(verifier)))
  let standard = @base64.encode(digest, padding=false)
  standard.replace_all(old="+", new="-").replace_all(old="/", new="_")
}

///|
/// The consent-page URL the system browser opens. Every interpolated value
/// except `name` is locally generated hex; the device name is
/// percent-encoded.
fn start_url(
  server_url~ : String,
  oauth_state~ : String,
  challenge~ : String,
  port~ : Int,
  name~ : String,
) -> String {
  let origin = without_suffix(server_url, "/")
  "\{origin}/v1/auth/desktop/start" +
  "?state=\{oauth_state}" +
  "&code_challenge=\{challenge}" +
  "&code_challenge_method=S256" +
  "&port=\{port}" +
  "&name=\{@uri.encode_component(name)}"
}

///|
/// What one request to the loopback listener means.
priv enum Callback {
  // The consent redirect, state verified: the one-time code.
  Granted(String)
  // The browser reported a denial (`error` query parameter).
  Denied(String)
  // Anything else — a favicon probe, a forged or stale redirect. The
  // listener answers 404 and keeps waiting; a guess must not be able to
  // cancel or complete the flow.
  Stray
}

///|
/// Parse one request target against the expected redirect: path `/cb`,
/// matching `state`, and either `code` or `error`.
fn parse_callback(target : String, oauth_state~ : String) -> Callback {
  let (path, query) = match target.find("?") {
    Some(index) => (target[:index].to_owned(), target[index + 1:])
    None => (target, "".view())
  }
  guard path == "/cb" else { return Stray }
  let mut code : String? = None
  let mut error_ : String? = None
  let mut state : String? = None
  for pair in query.split("&") {
    let (key, value) = match pair.find("=") {
      Some(index) => (pair[:index].to_owned(), @uri.decode(pair[index + 1:]))
      None => (pair.to_owned(), "")
    }
    match key {
      "code" => code = Some(value)
      "error" => error_ = Some(value)
      "state" => state = Some(value)
      _ => ()
    }
  }
  guard state is Some(state) && state == oauth_state else { return Stray }
  if error_ is Some(reason) {
    return Denied(reason)
  }
  match code {
    Some(code) if !code.is_empty() => Granted(code)
    _ => Stray
  }
}

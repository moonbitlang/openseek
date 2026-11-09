// Shared loopback browser sign-in. Each browser owns its account; this flow
// holds only pending one-time exchanges, never Desktop's AuthStore.

///|
priv struct PendingSignIn {
  verifier : String
  return_to : String
}

///|
struct Flow {
  relay : String
  port : Int32
  pending : Map[String, PendingSignIn]
}

///|
pub fn Flow::Flow(relay~ : String, port~ : Int32) -> Flow {
  { relay, port, pending: Map([]), }
}

///|
/// Start one independent browser login and return its account-service URL.
pub fn Flow::begin(self : Flow, destination : String?) -> String raise {
  guard @entropy.random_hex(16) is Some(oauth_state) &&
    @entropy.random_hex(32) is Some(verifier) else {
    fail("No OS entropy is available to start a sign-in.")
  }
  self.pending.set(oauth_state, {
    verifier,
    return_to: return_path(destination),
  })
  start_url(
    self.relay,
    oauth_state~,
    challenge=pkce_challenge(verifier),
    port=self.port,
  )
}

///|
/// Consume one callback. Success is a storage handoff document; failures
/// carry the HTTP status and plain text for the hosting server to render.
pub async fn Flow::finish(
  self : Flow,
  state : String?,
  code : String?,
  error : String?,
) -> Result[String, (Int32, String)] {
  guard state is Some(state) && self.pending.get(state) is Some(pending) else {
    return Err((400, "This sign-in is unknown or was already used."))
  }
  self.pending.remove(state)
  if error is Some(reason) {
    return Err((200, "Sign-in was not completed: \{reason}"))
  }
  guard code is Some(code) && !code.is_empty() else {
    return Err((400, "This sign-in return is incomplete."))
  }
  let account = exchange(self.relay, code~, verifier=pending.verifier) catch {
    error => return Err((200, "Sign-in failed: \{error}"))
  }
  Ok(sign_in_markup(account, return_to=pending.return_to))
}

///|
const AccountStorageKey : String = "seekmoon.account.v1"

///|
/// The S256 challenge (RFC 7636): the unpadded base64url of the verifier's
/// SHA-256. Core's encoder speaks only the standard alphabet, so its two
/// URL-unsafe characters are swapped after the fact.
pub fn pkce_challenge(verifier : String) -> String {
  let digest = Bytes::from_array(@crypto.sha256(@utf8.encode(verifier)))
  let standard = @base64.encode(digest, padding=false)
  let builder = StringBuilder()
  for c in standard {
    builder.write_char(
      match c {
        '+' => '-'
        '/' => '_'
        c => c
      },
    )
  }
  builder.to_string()
}

///|
/// The relay's account entry for a loopback client on `port`.
fn start_url(
  relay : String,
  oauth_state~ : String,
  challenge~ : String,
  port~ : Int32,
) -> String {
  "\{relay}/v2/auth/account/start?state=\{oauth_state}&code_challenge=\{challenge}&code_challenge_method=S256&port=\{port}"
}

///|
/// The page path to return to after sign-in. Only a path on this origin is
/// kept; anything else returns to the Cloud landing page.
fn return_path(requested : String?) -> String {
  guard requested is Some(path) &&
    path.has_prefix("/") &&
    !path.has_prefix("//") &&
    !path.any(ch => ch == '\\' || ch.is_control()) else {
    return "/cloud"
  }
  path
}

///|
/// Trade the one-time code for the account, returned as the relay's JSON.
async fn exchange(relay : String, code~ : String, verifier~ : String) -> String {
  let request : Json = { "code": code, "code_verifier": verifier }
  let (response, body) = @http.post(
    "\{relay}/v2/auth/account/exchange",
    request,
    headers={ "Content-Type": "application/json" },
  )
  guard response.code == 200 else {
    fail("the relay answered HTTP \{response.code}")
  }
  let text = body.text()
  guard @json.parse(text)
    is { "token": String(token), "user": { "user_id": String(_), .. }, .. } &&
    !token.is_empty() else {
    fail("the relay returned no account")
  }
  text
}

///|
/// A JavaScript string literal that is also safe inside `<script>`.
fn script_string(text : String) -> String {
  Json::string(text).stringify().replace_all(old="<", new="\\u003c")
}

///|
/// The markup that hands `account` to the page and returns to it.
pub fn sign_in_markup(account : String, return_to~ : String) -> String {
  let return_to = return_path(Some(return_to))
  "<!doctype html><meta charset=\"utf-8\"><title>Signing in…</title>" +
  "<script>localStorage.setItem(\{script_string(AccountStorageKey)}, \{script_string(account)});" +
  "location.replace(\{script_string(return_to)});</script>"
}

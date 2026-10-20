// The relay's loopback account sign-in, run on the proxy's own port:
// `/v2/auth/login` starts it at the relay's `/v2/auth/account/start` with a
// PKCE challenge, GitHub and the relay return to `/cb` with a one-time code,
// and the proxy exchanges that code for the account. The page receives the
// account through a small document that stores it where the frontend reads
// its browser account, then returns to the page that asked.

///|
/// The frontend's browser account store (see `load_browser_account`).
const AccountStorageKey : String = "seekmoon.account.v1"

///|
/// The user the demo signs in as.
let demo_user : Json = {
  "user_id": "demo",
  "login": "demo-user",
  "avatar_url": "",
}

///|
/// The demo's account, as the relay's account exchange answers it.
let demo_account : Json = { "token": "demo", "user": demo_user }

///|
/// The S256 challenge (RFC 7636): the unpadded base64url of the verifier's
/// SHA-256. Core's encoder speaks only the standard alphabet, so its two
/// URL-unsafe characters are swapped after the fact.
fn pkce_challenge(verifier : String) -> String {
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
  "\{relay}/v2/auth/account/start" +
  "?state=\{oauth_state}" +
  "&code_challenge=\{challenge}" +
  "&code_challenge_method=S256" +
  "&port=\{port}"
}

///|
/// The page path to return to after sign-in. Only a path on this origin is
/// kept; anything else returns to the Cloud landing page.
fn return_path(requested : String?) -> String {
  guard requested is Some(path) &&
    path.has_prefix("/") &&
    !path.has_prefix("//") &&
    !path.iter().any(ch => ch == '\\' || ch.is_control()) else {
    return "/cloud"
  }
  path
}

///|
async fn Proxy::begin_sign_in(
  self : Proxy,
  req : @moonback.Request,
  res : @moonback.Responder,
) -> Unit {
  let return_to = return_path(req.query().get("return_to"))
  guard self.upstream is Relay(relay) else {
    // The demo has nobody to ask: it signs in as its fixed account at once.
    send_page(res, sign_in_page(demo_account.stringify(), return_to~))
    return
  }
  guard @entropy.random_hex(16) is Some(oauth_state) &&
    @entropy.random_hex(32) is Some(verifier) else {
    send_page(
      res,
      failure_page("No OS entropy is available to start a sign-in."),
      status=500,
    )
    return
  }
  self.pending.set(oauth_state, { verifier, return_to, })
  res.send_void(status=302, headers={
    "Location": start_url(
      relay,
      oauth_state~,
      challenge=pkce_challenge(verifier),
      port=self.port,
    ),
  })
}

///|
async fn Proxy::finish_sign_in(
  self : Proxy,
  req : @moonback.Request,
  res : @moonback.Responder,
) -> Unit {
  let query = req.query()
  // A state is used once; a missing, replayed or unknown one starts nothing.
  guard query.get("state") is Some(state) &&
    self.pending.get(state) is Some(pending) &&
    self.upstream is Relay(relay) else {
    send_page(
      res,
      failure_page("This sign-in is unknown or was already used."),
      status=400,
    )
    return
  }
  self.pending.remove(state)
  if query.get("error") is Some(reason) {
    send_page(res, failure_page("Sign-in was not completed: \{reason}"))
    return
  }
  guard query.get("code") is Some(code) && !code.is_empty() else {
    send_page(
      res,
      failure_page("This sign-in return is incomplete."),
      status=400,
    )
    return
  }
  let account = exchange(relay, code~, verifier=pending.verifier) catch {
    error => {
      @xlog.warn(category="console_proxy") <?
        { "event": "sign_in_exchange_failed", "error": "\{error}" }
      send_page(res, failure_page("Sign-in failed: \{error}"))
      return
    }
  }
  send_page(res, sign_in_page(account, return_to=pending.return_to))
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
fn sign_in_markup(account : String, return_to~ : String) -> String {
  "<!doctype html><meta charset=\"utf-8\"><title>Signing in…</title>" +
  "<script>localStorage.setItem(\{script_string(AccountStorageKey)}, \{script_string(account)});" +
  "location.replace(\{script_string(return_to)});</script>"
}

///|
fn sign_in_page(account : String, return_to~ : String) -> @moonback.Html {
  @moonback.Html::raw(sign_in_markup(account, return_to~))
}

///|
/// A document explaining why sign-in stopped, with a way back.
fn failure_page(message : String) -> @moonback.Html {
  Html(async fn(builder) {
    builder.write_string(
      "<!doctype html><meta charset=\"utf-8\"><title>Sign-in failed</title><p>",
    )
    @moonback.Html::escape(message).write_to(builder)
    builder.write_string(
      "</p><p><a href=\"/cloud\">Back to the console</a></p>",
    )
  })
}

///|
async fn send_page(
  res : @moonback.Responder,
  page : @moonback.Html,
  status~ : Int32 = 200,
) -> Unit {
  res.send_html(page, status~, headers={ "Cache-Control": "no-store" })
}

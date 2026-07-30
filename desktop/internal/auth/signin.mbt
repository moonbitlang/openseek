// The loopback OAuth sign-in (docs/remote-protocol.md, "Desktop sign-in"):
// a one-shot listener on 127.0.0.1:<ephemeral>, the system browser driven
// to the relay's consent page, and the code-for-token exchange that *is*
// device registration.

///|
/// How long the human round-trip through the browser may take.
const SignInTimeoutMs = 300_000

///|
const ExchangeTimeoutMs = 30_000

///|
/// The full sign-in flow against `server_url`. On success the session is
/// committed (auth.json + memory) and the supervisor is poked; the caller
/// owns publishing `auth.changed`. Raises `AuthError` for every failure a
/// user can act on.
pub async fn AuthStore::sign_in(self : AuthStore, server_url~ : String) -> Unit {
  guard !self.sign_in_active else {
    raise AuthError("a sign-in is already in progress")
  }
  self.sign_in_active = true
  defer {
    self.sign_in_active = false
  }
  // A cancel poked after the previous flow ended must not kill this one.
  for ;; {
    guard (self.sign_in_abort.try_get() catch { _ => None }) is Some(_) else {
      break
    }
  }

  // Secrets first: no OS entropy is a hard failure, never weak randomness.
  guard @entropy.random_hex(32) is Some(verifier) else {
    raise AuthError("no OS entropy available for sign-in")
  }
  guard @entropy.random_hex(16) is Some(oauth_state) else {
    raise AuthError("no OS entropy available for sign-in")
  }
  let challenge = pkce_challenge(verifier)

  // The one-shot loopback listener, on an OS-assigned port.
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0")) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise AuthError("could not open the sign-in listener: \{error}")
  }
  defer server.close()
  let port = server.addr.port()

  // Hand the browser the consent URL.
  let name = match @platform.machine_hostname() {
    Some(hostname) => hostname
    None => "desktop"
  }
  let url = start_url(server_url~, oauth_state~, challenge~, port~, name~)
  let code = @platform.open_url(url) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise AuthError("could not open the system browser: \{error}")
  }
  guard code == 0 else {
    raise AuthError("could not open the system browser (exit \{code})")
  }

  // Wait for the redirect, bounded by the human-round-trip timeout and
  // racing the cancel channel (`auth.cancel` — the Settings page's Cancel
  // button); `any` cancels the losing arms, tearing the wait down.
  let outcome : SignInWait = @async.any([
    () => {
      match
        @async.with_timeout_opt(SignInTimeoutMs, () => {
          wait_for_code(
            server,
            oauth_state~,
            console_url=console_url(server_url),
          )
        }) {
        Some(code) => GotCode(code)
        None => TimedOut
      }
    },
    () => {
      self.sign_in_abort.get()
      CancelledByUser
    },
  ])
  let one_time_code = match outcome {
    GotCode(code) => code
    TimedOut => raise AuthError("sign-in timed out waiting for the browser")
    CancelledByUser => raise AuthError("the sign-in was cancelled")
  }

  // Exchange = device registration. The cancel channel stays armed through
  // it: the swap can take up to 30 seconds, and a Cancel clicked then must
  // abort the flow, not queue behind a session commit.
  let exchanged : ExchangeWait = @async.any([
    () => {
      Exchanged(
        exchange_code(server_url~, code=one_time_code, verifier~, name~),
      )
    },
    () => {
      self.sign_in_abort.get()
      ExchangeCancelled
    },
  ])
  guard exchanged is Exchanged(session) else {
    raise AuthError("the sign-in was cancelled")
  }
  // A cancel that landed a hair after the exchange won still counts — but
  // the exchange already minted a device row, so revoke it best-effort
  // before failing the flow.
  if (self.sign_in_abort.try_get() catch { _ => None }) is Some(_) {
    revoke_device(session) catch {
      error if @async.is_being_cancelled() => raise error
      error =>
        @xlog.warn(category="auth") <?
          { "message": "device revoke failed", "error": "\{error}" }
    }
    raise AuthError("the sign-in was cancelled")
  }

  self.commit_session(session)
}

///|
/// Commit one exchanged session without exposing a token that failed to
/// persist. `resume_on_cancel` lets the API finish its server-selection
/// revalidation and `auth.changed` publication after this point; the next
/// unprotected suspension still observes the requester's cancellation.
async fn AuthStore::commit_session(
  self : AuthStore,
  session : AuthSession,
) -> Unit {
  @async.protect_from_cancel(
    () => {
      if self.runtime_dir is Some(dir) {
        save_session_file(dir, session)
      }
      self.session = Some(session)
      self.connected = false
      self.poke()
    },
    resume_on_cancel=true,
  )
}

///|
/// How the wait for the consent redirect ended.
priv enum SignInWait {
  GotCode(String)
  TimedOut
  CancelledByUser
}

///|
/// How the code-for-token exchange ended.
priv enum ExchangeWait {
  Exchanged(AuthSession)
  ExchangeCancelled
}

///|
/// Accept loopback connections until one carries the consent redirect.
/// Stray requests (favicon probes, forged or stale redirects) get a 404
/// and the wait continues — a loopback guesser can neither cancel nor
/// complete the flow. A denial from the consent page raises.
async fn wait_for_code(
  server : @http.Server,
  oauth_state~ : String,
  console_url~ : String,
) -> String {
  for ;; {
    let (conn, _) = server.accept()
    let outcome = serve_callback(conn, oauth_state~, console_url~) catch {
      error if @async.is_being_cancelled() => raise error
      // A broken socket must not kill the flow; keep listening.
      _ => continue
    }
    match outcome {
      Granted(code) => return code
      Denied(reason) =>
        raise AuthError("the browser declined the sign-in: \{reason}")
      Stray => continue
    }
  }
}

///|
/// Serve one loopback request and classify it.
async fn serve_callback(
  conn : @http.ServerConnection,
  oauth_state~ : String,
  console_url~ : String,
) -> Callback {
  defer conn.close()
  let request = conn.read_request()
  let outcome = parse_callback(request.path, oauth_state~)
  match outcome {
    Granted(_) => respond_html(conn, 200, "OK", sign_in_done_page(console_url))
    Denied(_) => respond_html(conn, 200, "OK", SignInDeniedPage)
    Stray => respond_html(conn, 404, "Not Found", "not found")
  }
  outcome
}

///|
async fn respond_html(
  conn : @http.ServerConnection,
  code : Int,
  reason : String,
  body : String,
) -> Unit {
  conn.send_response(code, reason, extra_headers={
    "Content-Type": "text/html; charset=utf-8",
    "Connection": "close",
  })
  conn.write_string(body)
  conn.end_response()
}

///|
/// The console's look (desktop/index.html) reduced to what a static
/// loopback page needs: paper surfaces, hairline border, mono stack. The
/// bundled Geist Mono lives on the relay origin, so these pages fall back
/// to the system mono fonts of the same stack.
const SignInPageStyle : String = "<style>:root{color-scheme:light dark;--paper:#fbfbf9;--surface:#ffffff;--ink:#16171a;--ink-2:#5c5f66;--line:#e9e8e3;--accent:#2a55cc}@media (prefers-color-scheme:dark){:root{--paper:#16181d;--surface:#1c1f26;--ink:#e9ebf0;--ink-2:#a3a8b4;--line:#2c313b;--accent:#9db8ff}}html{background:var(--paper)}body{font-family:\"Geist Mono\",\"SF Mono\",ui-monospace,\"Cascadia Mono\",Menlo,Consolas,monospace;background:var(--surface);color:var(--ink);max-width:26rem;margin:6rem auto;padding:2rem;border:1px solid var(--line);border-radius:10px}h1{font-size:1.05rem;margin:0 0 .75rem}p{margin:.5rem 0;color:var(--ink-2);font-size:.85rem;line-height:1.6}a{color:var(--accent)}</style>"

///|
/// The post-consent landing page: confirm the sign-in, then send the
/// browser on to the console. The one-second pause covers the desktop's
/// code-for-token exchange, so the console already lists the new device
/// when it loads.
fn sign_in_done_page(console_url : String) -> String {
  let href = html_attr_escape(console_url)
  "<!doctype html><meta charset=\"utf-8\"><meta http-equiv=\"refresh\" content=\"1;url=\{href}\"><title>Signed in</title>" +
  SignInPageStyle +
  "<body><h1>You're signed in</h1><p>Taking you to your console…</p><p><a href=\"\{href}\">Continue</a></p>"
}

///|
const SignInDeniedPage : String = "<!doctype html><meta charset=\"utf-8\"><title>Sign-in cancelled</title>" +
  SignInPageStyle +
  "<body><h1>Sign-in cancelled</h1><p>Nothing was connected. You can close this tab.</p>"

///|
/// Escape a value for an HTML attribute. The console URL derives from the
/// user's server selection, so nothing about its charset is guaranteed.
fn html_attr_escape(text : String) -> String {
  let builder = StringBuilder::new()
  for c in text {
    match c {
      '&' => builder.write_string("&amp;")
      '<' => builder.write_string("&lt;")
      '>' => builder.write_string("&gt;")
      '"' => builder.write_string("&quot;")
      c => builder.write_char(c)
    }
  }
  builder.to_string()
}

///|
/// Swap the one-time code (plus the PKCE verifier) for a device token —
/// the exchange creates the device row server-side.
async fn exchange_code(
  server_url~ : String,
  code~ : String,
  verifier~ : String,
  name~ : String,
) -> AuthSession {
  let origin = match server_url.strip_suffix("/") {
    Some(origin) => origin.to_owned()
    None => server_url
  }
  let body : Json = {
    "code": code.to_json(),
    "code_verifier": verifier.to_json(),
    "hostname": name.to_json(),
    "name": name.to_json(),
  }
  guard @async.with_timeout_opt(ExchangeTimeoutMs, () => {
      @http.post("\{origin}/v1/auth/desktop/exchange", body, headers={
        "Content-Type": "application/json",
      }) catch {
        error if @async.is_being_cancelled() => raise error
        error => raise AuthError("the sign-in exchange failed: \{error}")
      }
    })
    is Some((response, data)) else {
    raise AuthError("the sign-in exchange timed out")
  }
  guard response.code == 200 else {
    raise AuthError("the sign-in exchange answered HTTP \{response.code}")
  }
  let json = data.json() catch {
    error if @async.is_being_cancelled() => raise error
    _ => raise AuthError("the sign-in exchange answered malformed JSON")
  }
  guard json
    is {
      "device_token": String(device_token),
      "device": { "id": String(device_id), "name": String(device_name), .. },
      "user": {
        "login": String(user_login),
        "avatar_url": String(user_avatar_url),
        ..
      },
      ..
    } else {
    raise AuthError("the sign-in exchange answered an unexpected shape")
  }
  {
    server_url: origin,
    device_token,
    device_id,
    device_name,
    user_login,
    user_avatar_url,
  }
}

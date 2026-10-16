// The loopback OAuth sign-in (docs/remote-protocol.md, "Desktop sign-in"):
// a one-shot listener on 127.0.0.1:<ephemeral>, the system browser driven
// through GitHub account selection, then a code-for-account-token exchange.
// Device registration is an independent remote-access action.

///|
/// How long the human round-trip through the browser may take.
const SignInTimeoutMs = 300_000

///|
const ExchangeTimeoutMs = 30_000

///|
/// The full sign-in flow against `server_url`. On success the session is
/// committed (auth.json + memory), with remote access disabled; the caller
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
    error => raise AuthError("could not open the sign-in listener: \{error}")
  }
  defer server.close()
  let port = server.addr.port()

  // Start explicit account selection, independently of the browser cookie.
  let url = start_url(server_url~, oauth_state~, challenge~, port~)
  let code = @platform.open_url(url) catch {
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
          wait_for_code(server, oauth_state~)
        }) {
        Some((code, conn)) => GotCode(code, conn)
        None => TimedOut
      }
    },
    () => {
      self.sign_in_abort.get()
      CancelledByUser
    },
  ])
  let (one_time_code, browser) = match outcome {
    GotCode(code, conn) => (code, conn)
    TimedOut => raise AuthError("sign-in timed out waiting for the browser")
    CancelledByUser => raise AuthError("the sign-in was cancelled")
  }
  // Keep the loopback page open until the account credential is committed.
  defer browser.close()

  // The exchange creates an account session. Once it may have committed,
  // cancellation must not discard the credential needed to revoke it. Run
  // the exchange as a structured child so its own timeout
  // remains effective, then protect only the requester's wait for its result.
  //
  // `auth.cancel` itself still replies immediately after queueing its signal;
  // only the pending `auth.connect` waits for exchange cleanup to settle.
  let exchanged : Ref[AuthSession?] = Ref(None)
  @async.protect_from_cancel(() => {
    @async.with_task_group(group => {
      let exchange = group.spawn(() => {
        exchange_code(server_url~, code=one_time_code, verifier~)
      })
      exchanged.val = Some(exchange.wait())
    })
  })
  guard exchanged.val is Some(session) else {
    raise AuthError("the sign-in exchange returned no session")
  }
  // A queued user cancellation, or a transport cancellation that landed
  // immediately after the exchange shield, must revoke instead of commit.
  if (self.sign_in_abort.try_get() catch { _ => None }) is Some(_) ||
    @async.is_being_cancelled() {
    @async.protect_from_cancel(() => session.revoke_after_cancelled_exchange())
    raise AuthError("the sign-in was cancelled")
  }

  self.commit_session(session)
  respond_html(browser, 200, "OK", sign_in_done_page()) catch {
    _ => ()
  }
}

///|
/// Commit one exchanged session without exposing a token that failed to
/// persist. The cancellation shield lets the API finish its
/// `auth.changed` publication after this point; the next
/// unprotected suspension still observes the requester's cancellation.
async fn AuthStore::commit_session(
  self : AuthStore,
  session : AuthSession,
) -> Unit {
  @async.protect_from_cancel(() => {
    self.persist_mutex.acquire()
    defer self.persist_mutex.release()
    if self.runtime_dir is Some(dir) {
      save_session_file(dir, session)
    }
    self.session = Some(session)
    if self.env_override is None {
      self.connected = false
      self.poke()
    }
  })
}

///|
/// How the wait for the account sign-in redirect ended.
priv enum SignInWait {
  GotCode(String, @http.ServerConnection)
  TimedOut
  CancelledByUser
}

///|
/// Accept loopback connections until one carries the account redirect. The
/// granted connection stays open until sign-in commits the account session. Stray requests
/// (favicon probes, forged or stale redirects) get a 404 and the wait
/// continues — a loopback guesser can neither cancel nor complete the flow.
/// A denial from the browser raises.
async fn wait_for_code(
  server : @http.Server,
  oauth_state~ : String,
) -> (String, @http.ServerConnection) {
  for ;; {
    let (conn, _) = server.accept()
    let outcome = try {
      errdefer conn.close()
      serve_callback(conn, oauth_state~)
    } catch {
      // A broken socket must not kill the flow; keep listening.
      _ => continue
    }
    match outcome {
      Granted(code) => return (code, conn)
      Denied(reason) => {
        conn.close()
        raise AuthError("the browser declined the sign-in: \{reason}")
      }
      Stray => {
        conn.close()
        continue
      }
    }
  }
}

///|
/// Serve one loopback request and classify it.
async fn serve_callback(
  conn : @http.ServerConnection,
  oauth_state~ : String,
) -> Callback {
  let request = conn.read_request()
  let outcome = parse_callback(request.path, oauth_state~)
  match outcome {
    // The caller holds this request until exchange and persistence finish.
    Granted(_) => ()
    Denied(_) => respond_html(conn, 200, "OK", SignInDeniedPage)
    Stray => respond_html(conn, 404, "Not Found", "not found")
  }
  outcome
}

///|
async fn respond_html(
  conn : @http.ServerConnection,
  code : Int32,
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
/// loopback page needs: paper surfaces, hairline border, system sans text.
/// This response cannot load the app stylesheet, so it owns a small
/// self-contained copy of the semantic palette and typography tokens while
/// keeping the same names and values.
const SignInPageStyle : String =
  #|<style>
  #|  :root {
  #|    color-scheme: light dark;
  #|    --color-bg-canvas: #fbfbf9;
  #|    --color-bg-surface: #ffffff;
  #|    --color-text-primary: #16171a;
  #|    --color-text-secondary: #5c5f66;
  #|    --color-border: #e9e8e3;
  #|    --color-accent-strong: #2a55cc;
  #|    --font-family-mono: ui-monospace, SFMono-Regular, Menlo, Monaco,
  #|      Consolas, "Liberation Mono", "Courier New", monospace;
  #|    --font-family-sans: ui-sans-serif, system-ui, -apple-system,
  #|      BlinkMacSystemFont, "Segoe UI", sans-serif;
  #|    --font-size-md: 14px;
  #|    --font-size-lg: 17px;
  #|    --font-weight-regular: 450;
  #|    --line-height-relaxed: 1.6;
  #|    --radius-md: 9px;
  #|  }
  #|  @media (prefers-color-scheme: dark) {
  #|    :root {
  #|      --color-bg-canvas: #16181d;
  #|      --color-bg-surface: #1c1f26;
  #|      --color-text-primary: #e9ebf0;
  #|      --color-text-secondary: #a3a8b4;
  #|      --color-border: #2c313b;
  #|      --color-accent-strong: #9db8ff;
  #|    }
  #|  }
  #|  html { background: var(--color-bg-canvas); }
  #|  body {
  #|    max-width: 26rem;
  #|    margin: 6rem auto;
  #|    padding: 2rem;
  #|    border: 1px solid var(--color-border);
  #|    border-radius: var(--radius-md);
  #|    background: var(--color-bg-surface);
  #|    color: var(--color-text-primary);
  #|    font-family: var(--font-family-sans);
  #|    font-weight: var(--font-weight-regular);
  #|  }
  #|  h1 { margin: 0 0 0.75rem; font-size: var(--font-size-lg); }
  #|  p {
  #|    margin: 0.5rem 0;
  #|    color: var(--color-text-secondary);
  #|    font-size: var(--font-size-md);
  #|    line-height: var(--line-height-relaxed);
  #|  }
  #|  a { color: var(--color-accent-strong); }
  #|</style>

///|
/// Finish account sign-in without opening a device or Cloud authorization page.
fn sign_in_done_page() -> String {
  "<!doctype html><meta charset=\"utf-8\"><title>Signed in</title>" +
  SignInPageStyle +
  "<body><h1>You're signed in</h1><p>Return to SeekMoon. You can close this tab.</p>"
}

///|
const SignInDeniedPage : String = "<!doctype html><meta charset=\"utf-8\"><title>Sign-in cancelled</title>" +
  SignInPageStyle +
  "<body><h1>Sign-in cancelled</h1><p>Nothing was connected. You can close this tab.</p>"

///|
/// Exchange the independent ac_ code for the account session; no device is created.
async fn exchange_code(
  server_url~ : String,
  code~ : String,
  verifier~ : String,
) -> AuthSession {
  let origin = match server_url.strip_suffix("/") {
    Some(origin) => origin.to_owned()
    None => server_url
  }
  let body : Json = { "code": Json(code), "code_verifier": Json(verifier) }
  guard @async.with_timeout_opt(ExchangeTimeoutMs, () => {
      @http.post("\{origin}/v2/auth/account/exchange", body, headers={
        "Content-Type": "application/json",
      }) catch {
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
    _ => raise AuthError("the sign-in exchange answered malformed JSON")
  }
  let account : @protocol.AccountSession = @json.from_json(json) catch {
    _ => raise AuthError("the sign-in exchange answered an unexpected shape")
  }
  { server_url: origin, account, device: None, }
}

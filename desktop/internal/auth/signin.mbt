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
  let name = @platform.machine_hostname().unwrap_or("desktop")
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
  // Keep the browser's loopback request open until registration returns its
  // device id. Only then can the completion page point at one exact device.
  defer browser.close()

  // Exchange = device registration. Once the relay may have committed the
  // device, cancelling the HTTP task can lose the only token authorized to
  // revoke it. Run the exchange as a structured child so its own timeout
  // remains effective, then protect only the requester's wait for its result.
  //
  // `auth.cancel` itself still replies immediately after queueing its signal;
  // only the pending `auth.connect` waits for exchange cleanup to settle.
  let exchanged : Ref[AuthSession?] = Ref(None)
  @async.protect_from_cancel(() => {
    @async.with_task_group(group => {
      let exchange = group.spawn(() => {
        exchange_code(server_url~, code=one_time_code, verifier~, name~)
      })
      exchanged.val = Some(exchange.wait())
    })
  }) catch {
    error if @async.is_cancellation_error(error) => {
      // Transport cancellation arrived while the exchange was protected.
      // The result is now available, so remove the minted device before the
      // original cancellation escapes.
      if exchanged.val is Some(session) {
        @async.protect_from_cancel(() => {
          session.revoke_after_cancelled_exchange()
        })
      }
      raise error
    }
    error => raise error
  }
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
  let url = device_url(
    session.server_url,
    session.device_id,
    app_version=self.app_version,
  )
  // Registration and the local commit have already succeeded. A browser tab
  // closed during the exchange must not turn that committed sign-in into an
  // auth failure, while task cancellation must still reach the caller.
  respond_html(browser, 200, "OK", sign_in_done_page(url)) catch {
    error if @async.is_being_cancelled() => raise error
    _ => ()
  }
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
  @async.protect_from_cancel(() => {
    if self.runtime_dir is Some(dir) {
      save_session_file(dir, session)
    }
    self.session = Some(session)
    self.connected = false
    self.poke()
  })
}

///|
/// How the wait for the consent redirect ended.
priv enum SignInWait {
  GotCode(String, @http.ServerConnection)
  TimedOut
  CancelledByUser
}

///|
/// Accept loopback connections until one carries the consent redirect. The
/// granted connection stays open so `sign_in` can finish device registration
/// before returning its device-specific completion page. Stray requests
/// (favicon probes, forged or stale redirects) get a 404 and the wait
/// continues — a loopback guesser can neither cancel nor complete the flow.
/// A denial from the consent page raises.
async fn wait_for_code(
  server : @http.Server,
  oauth_state~ : String,
) -> (String, @http.ServerConnection) {
  for ;; {
    let (conn, _) = server.accept()
    let outcome = serve_callback(conn, oauth_state~) catch {
      error if @async.is_being_cancelled() => {
        conn.close()
        raise error
      }
      // A broken socket must not kill the flow; keep listening.
      _ => {
        conn.close()
        continue
      }
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
    // The caller holds this request until the code exchange supplies the
    // registered device id needed by the completion URL.
    Granted(_) => ()
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
/// The post-consent landing page is sent only after the code exchange and
/// local commit finish, so its URL can identify the newly registered device.
fn sign_in_done_page(device_url : String) -> String {
  let href = html_attr_escape(device_url)
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
  let builder = StringBuilder()
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
  let origin = without_suffix(server_url, "/")
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

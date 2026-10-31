// Browser and relay effects. Only commands leave this file; `update` decides
// which one runs. The browser side goes through the Push API by reflection,
// as frontend/system_notification.mbt reaches the bridge; the relay side is
// the console's own account Bearer, like every other `/v2` call.

///|
priv suberror PushError {
  PushError(String)
}

///|
impl Show for PushError with fn output(self, logger) {
  match self {
    PushError(message) => logger.write_string(message)
  }
}

///|
/// `navigator.serviceWorker`, when this browser has the Push API at all.
fn service_worker() -> @js.Value? {
  guard @interop.js_prop(@js.globalThis, "navigator") is Some(navigator) &&
    @interop.js_prop(navigator, "serviceWorker") is Some(container) &&
    @interop.js_prop(@js.globalThis, "PushManager") is Some(_) &&
    @interop.js_prop(@js.globalThis, "Notification") is Some(_) else {
    return None
  }
  Some(container)
}

///|
async fn call(target : @js.Value, name : String, arg : @js.Value) -> @js.Value {
  @interop.js_method_promise(target, name, arg).wait() catch {
    error => raise PushError("\{name} failed: \{error}")
  }
}

///|
fn undefined() -> @js.Value {
  @js.globalThis.get_with_string("undefined")
}

///|
/// The active registration. `ready` waits for the worker `probe` registered.
async fn registration() -> @js.Value {
  guard service_worker() is Some(container) else {
    raise PushError("this browser has no Push API")
  }
  let ready : @js.Promise[@js.Value] = container.get_with_string("ready")
  ready.wait()
}

///|
async fn current_subscription() -> @js.Value? {
  let manager : @js.Value = registration().get_with_string("pushManager")
  let subscription = call(manager, "getSubscription", undefined())
  if subscription.is_null() || subscription.is_undefined() {
    None
  } else {
    Some(subscription)
  }
}

///|
fn permission() -> Permission {
  let notification : @js.Value = @js.globalThis.get_with_string("Notification")
  let permission : @js.Value = notification.get_with_string("permission")
  match permission.to_string() {
    "granted" => Granted
    "denied" => Denied
    _ => Default
  }
}

///|
async fn relay(
  path : String,
  method_ : @http.RequestMethod,
  token? : String,
  body? : Json,
) -> (Int32, String) {
  let base : String = @js.Value::cast_from(@dom.document()).get_with_string(
    "baseURI",
  )
  let url = match @base_browser.resolve_url(path, base~) {
    Ok((url, _)) => url
    Err(message) => raise PushError(message)
  }
  let headers : Map[@http.CaseInsensitiveString, String] = Map([])
  if token is Some(token) {
    headers["Authorization"] = "Bearer " + token
  }
  let text = match body {
    Some(body) => {
      headers["Content-Type"] = "application/json"
      body.stringify()
    }
    None => ""
  }
  let (response, reply) = @http.request(url, method_, headers, text)
  (response.code, @utf8.decode_lossy(reply.binary(), ignore_bom=true))
}

///|
fn expect_success(what : String, status : Int32) -> Unit raise PushError {
  guard status >= 200 && status < 300 else {
    raise PushError("\{what} answered HTTP \{status}")
  }
}

///|
/// Register this subscription with the relay for the signed-in account.
async fn register_with_relay(subscription : @js.Value, ctx : Ctx) -> Unit {
  let json = call(subscription, "toJSON", undefined()).to_json() catch {
    error => raise PushError("the subscription is unreadable: \{error}")
  }
  guard json is { "endpoint": String(endpoint), "keys": keys, .. } else {
    raise PushError("the subscription has no endpoint")
  }
  let (status, _) = relay("/v2/push/subscription", Put, token=ctx.token, body={
    "endpoint": endpoint,
    "keys": keys,
    "locale": ctx.locale,
  })
  expect_success("registering this device", status)
}

///|
fn endpoint_of(subscription : @js.Value) -> String {
  subscription.get_with_string("endpoint")
}

///|
/// Register the worker and read what this browser and the relay offer. Any
/// failure to reach the relay reads as no key: the control stays hidden until
/// the next page load.
pub fn probe(emit : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.attempt(
    (result : Result[Probe, Error]) => {
      emit(Probed(result.unwrap_or(NoRelayKey)))
    },
    () => {
      guard service_worker() is Some(container) else { return NoPushApi }
      // Served at the root, so its default scope covers every page.
      ignore(call(container, "register", @js.Value::cast_from("/sw.js")))
      let (status, body) = relay("/v2/push/key", Get)
      guard status == 200 &&
        (@json.parse(body) catch { _ => return NoRelayKey })
        is { "public_key": String(key), .. } else {
        return NoRelayKey
      }
      Ready(
        key~,
        permission=permission(),
        subscribed=current_subscription() is Some(_),
      )
    },
  )
}

///|
fn turn_on(key : String, ctx : Ctx, emit : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.attempt(
    (result : Result[Msg, Error]) => {
      emit(
        match result {
          Ok(msg) => msg
          Err(error) => TurnOnFailed(error.to_string())
        },
      )
    },
    () => {
      // First, before anything waits: browsers grant the prompt only while
      // the click that asked is still recent.
      let notification : @js.Value = @js.globalThis.get_with_string(
        "Notification",
      )
      let answer = call(notification, "requestPermission", undefined())
      match answer.to_string() {
        "granted" => ()
        "denied" => return Denied
        _ => return Dismissed
      }
      let manager : @js.Value = registration().get_with_string("pushManager")
      let options = @js.Object::new()
      // Every push shows a notification; iOS and Chrome require the promise.
      options["userVisibleOnly"] = true
      options["applicationServerKey"] = key
      let subscription = call(manager, "subscribe", options.to_value())
      register_with_relay(subscription, ctx)
      TurnedOn
    },
  )
}

///|
fn turn_off(ctx : Ctx, emit : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.attempt(
    (result : Result[Unit, Error]) => {
      emit(
        match result {
          Ok(_) => TurnedOff
          Err(error) => TurnOffFailed(error.to_string())
        },
      )
    },
    () => {
      guard current_subscription() is Some(subscription) else { return }
      let (status, _) = relay(
        "/v2/push/subscription",
        Delete,
        token=ctx.token,
        body={ "endpoint": endpoint_of(subscription) },
      )
      expect_success("removing this device", status)
      ignore(call(subscription, "unsubscribe", undefined()))
    },
  )
}

///|
fn send_test(ctx : Ctx, emit : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.attempt(
    (result : Result[Unit, Error]) => {
      emit(
        match result {
          Ok(_) => TestSent
          Err(error) => TestFailed(error.to_string())
        },
      )
    },
    () => {
      guard current_subscription() is Some(subscription) else {
        raise PushError("this device is not subscribed")
      }
      let (status, _) = relay("/v2/push/test", Post, token=ctx.token, body={
        "endpoint": endpoint_of(subscription),
      })
      expect_success("the test notification", status)
    },
  )
}

///|
/// Register the existing subscription again; nothing waits on the result.
fn resync(ctx : Ctx) -> @cmd.Cmd {
  @cmd.attempt((_ : Result[Unit, Error]) => @cmd.none, () => {
    if current_subscription() is Some(subscription) {
      register_with_relay(subscription, ctx)
    }
  })
}

///|
/// Drop this browser's subscription when the account signs out. The relay's
/// row goes with the signed-out session, so nothing is sent there.
pub fn forget() -> @cmd.Cmd {
  @cmd.attempt((_ : Result[Unit, Error]) => @cmd.none, () => {
    guard service_worker() is Some(_) else { return }
    if current_subscription() is Some(subscription) {
      ignore(call(subscription, "unsubscribe", undefined()))
    }
  })
}

// Whether this browser receives the relay's Web Push, as the console's
// account settings show and toggle it. The window never runs this: its banners
// come from the host. The relay's routes live in moonbitlang/openseek-api.

///|
/// One browser installation's push state. The relay's VAPID key rides the
/// states that may subscribe with it.
#derive(Debug, Eq)
pub enum State {
  // Before the first probe settles.
  Checking
  // No service worker or Push API: an iOS Safari tab outside Home Screen, or
  // an older browser.
  Unsupported
  // The relay has no push configured (or this host is not a relay).
  Unavailable
  Off(key~ : String, error~ : String?)
  // A permission prompt, subscribe, unsubscribe or test is in flight; `on`
  // is whether push is on meanwhile.
  Working(key~ : String, on~ : Bool)
  // `tested` once the relay accepted a test push for this device.
  On(key~ : String, error~ : String?, tested~ : Bool)
  // The user denied notifications for this site; only browser settings can
  // undo that, and the next probe sees it.
  Blocked
}

///|
pub fn State::State() -> State {
  Checking
}

///|
/// The browser's answer to `Notification.permission`.
pub(all) enum Permission {
  Granted
  Denied
  Default
}

///|
/// What one probe of this browser and the relay found.
pub(all) enum Probe {
  NoPushApi
  NoRelayKey
  Ready(key~ : String, permission~ : Permission, subscribed~ : Bool)
}

///|
pub(all) enum Msg {
  Probed(Probe)
  TurnOn
  TurnOff
  SendTest
  // The outcome of TurnOn: subscribed and registered, denied, the prompt
  // dismissed, or failed.
  TurnedOn
  Denied
  Dismissed
  TurnOnFailed(String)
  TurnedOff
  TurnOffFailed(String)
  TestSent
  TestFailed(String)
}

///|
/// The account the relay calls are made as, and the locale the relay stores
/// with the subscription so the worker formats pushes in it.
pub(all) struct Ctx {
  token : String
  locale : String
}

///|
/// Pure: the returned command performs every browser and relay effect.
pub fn State::update(
  self : State,
  msg : Msg,
  ctx : Ctx,
  emit : @cmd.Emit[Msg],
) -> (State, @cmd.Cmd) {
  match (self, msg) {
    (Checking, Probed(NoPushApi)) => (Unsupported, @cmd.none)
    (Checking, Probed(NoRelayKey)) => (Unavailable, @cmd.none)
    (Checking, Probed(Ready(permission=Denied, ..))) => (Blocked, @cmd.none)
    // Re-registering heals a row the relay pruned or bound to an expired
    // sign-in, and refreshes its locale.
    (Checking, Probed(Ready(key~, permission=Granted, subscribed=true))) =>
      (On(key~, error=None, tested=false), resync(ctx))
    (Checking, Probed(Ready(key~, ..))) => (Off(key~, error=None), @cmd.none)
    (Off(key~, ..), TurnOn) =>
      (Working(key~, on=false), turn_on(key, ctx, emit))
    (Working(key~, on=false), TurnedOn) =>
      (On(key~, error=None, tested=false), @cmd.none)
    (Working(on=false, ..), Denied) => (Blocked, @cmd.none)
    (Working(key~, on=false), Dismissed) => (Off(key~, error=None), @cmd.none)
    (Working(key~, on=false), TurnOnFailed(error)) =>
      (Off(key~, error=Some(error)), @cmd.none)
    (On(key~, ..), TurnOff) => (Working(key~, on=true), turn_off(ctx, emit))
    (Working(key~, on=true), TurnedOff) => (Off(key~, error=None), @cmd.none)
    (Working(key~, on=true), TurnOffFailed(error)) =>
      (On(key~, error=Some(error), tested=false), @cmd.none)
    (On(key~, ..), SendTest) => (Working(key~, on=true), send_test(ctx, emit))
    (Working(key~, on=true), TestSent) =>
      (On(key~, error=None, tested=true), @cmd.none)
    (Working(key~, on=true), TestFailed(error)) =>
      (On(key~, error=Some(error), tested=false), @cmd.none)
    // Anything else is a stale reply or a click on a control the state does
    // not show.
    _ => (self, @cmd.none)
  }
}

///|
pub extend State with Debug::{to_repr}

///|
pub extend State with Eq::{equal, not_equal}

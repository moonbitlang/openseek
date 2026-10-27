// The relay actor: the one task that owns "is this host
// registered with a relay". It keeps the running connector matching the
// auth store's desired config — the signed-in session or the environment
// override — restarting on every store poke (sign-in, sign-out, server
// switch) and parking on a terminal relay refusal until a new sign-in
// pokes it awake.

///|
/// Why a connector session ended: the store changed under it, or the
/// relay refused the token.
priv enum SessionEnd {
  Poked
  Refused(String)
}

///|
/// The app-lifetime owner of the relay control connection and every data
/// WebSocket accepted through it. Auth operations communicate desired-state
/// changes through `AuthStore`'s coalescing wakeup mailbox.
struct RelayActor {
  state : @api.ApiState
  announce : (String) -> Unit
}

///|
fn RelayActor::registered(self : RelayActor, device : String) -> Unit {
  (self.announce)(device)
  if self.state.auth_store().mark_registered(device) {
    self.state.publish(AuthChanged(auth_changed_params(self.state)))
  }
}

///|
fn RelayActor::dropped(self : RelayActor) -> Unit {
  if self.state.auth_store().mark_dropped() {
    self.state.publish(AuthChanged(auth_changed_params(self.state)))
  }
}

///|
/// The `auth.changed` params: the store's status shape. Notifications the
/// actor pushes never carry a fallback `server_url` — when nothing is
/// signed in the Settings page derives the selectable server itself.
fn auth_changed_params(state : @api.ApiState) -> @protocol.AuthStatusPayload {
  state.auth_store().status()
}

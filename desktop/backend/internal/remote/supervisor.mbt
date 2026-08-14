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
pub fn RelayActor::RelayActor(
  state : @api.ApiState,
  announce~ : (String) -> Unit,
) -> RelayActor {
  { state, announce, }
}

///|
/// Run for the host's lifetime (spawned once from main). `announce` preserves
/// the startup log line on every successful registration.
pub async fn RelayActor::run(self : RelayActor) -> Unit {
  let store = self.state.auth_store()
  for ;; {
    // `auth.json` may have survived a prior process's failed signed-out
    // marker write. Never connect a persisted token whose issuer no longer
    // matches the currently selected OpenSeek server: clear it in memory
    // before reading `desired_connector`, then retry the durable clear and
    // revoke as best effort. This makes a successful server switch a
    // permanent connection fence even across restarts.
    if !store.managed_by_env() &&
      store.signed_in() &&
      store.session_server() != @engine.remote_server_base(self.state.manager()) {
      store.sign_out() catch {
        error if @async.is_being_cancelled() => raise error
        error =>
          @xlog.warn(category="remote") <?
            {
              "message": "could not persist stale-server sign-out",
              "error": "\{error}",
            }
      }
      self.state.publish(AuthChanged(auth_changed_params(self.state)))
    }
    match store.desired_connector() {
      // Idle: nothing to run until someone pokes the store.
      None => store.wakeups().get()
      Some(config) => {
        let end : SessionEnd = @async.any([
          () => {
            store.wakeups().get()
            Poked
          },
          () => Refused(self.run_connector(config)),
        ])
        match end {
          // The config changed: `any` already cancelled the old connector
          // (tearing its control socket down); re-read and start over.
          Poked => ()
          Refused(message) => {
            @xlog.warn(category="remote") <?
              { "message": "relay refused registration", "error": message }
            store.handle_refusal() catch {
              error if @async.is_being_cancelled() => raise error
              error =>
                // The relay already rejected this token. Keep the actor
                // alive and parked on the cleared in-memory state even if
                // persisting its signed-out marker failed.
                @xlog.warn(category="remote") <?
                  {
                    "message": "could not persist refused sign-out",
                    "error": "\{error}",
                  }
            }
            self.state.publish(AuthChanged(auth_changed_params(self.state)))
          }
        }
      }
    }
  }
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

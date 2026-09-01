// The auth.* op bodies (docs/remote-protocol.md): they run the sign-in
// flows in `internal/auth` and translate its errors into the transports'
// `HostError` vocabulary. They live here — not in `internal/auth` — so
// `auth.changed` can go through the hub, and the relay actor
// (internal/remote, which imports this package) stays cycle-free.

///|
/// The current status. The fallback `server_url` is the relay origin —
/// a SeekMoon-hosted service that no longer depends on the chat provider.
async fn auth_status(state : ApiState) -> @protocol.AuthStatusPayload {
  state.auth.status(server_url?=@engine.remote_server_base(state.manager))
}

///|
/// Run the loopback sign-in against the selected server, then wake the
/// connector. Signed in already means "make sure the connector runs", not
/// a second browser round-trip — every exchange mints a new device row
/// server-side, so re-running the flow would duplicate the device.
async fn auth_connect(state : ApiState) -> @protocol.AuthStatusPayload {
  let store = state.auth
  if store.managed_by_env() {
    raise @host.HostError(
      "remote access is configured through OPENSEEK_RELAY_URL/OPENSEEK_DEVICE_TOKEN",
    )
  }
  if store.signed_in() {
    store.poke()
    return auth_status(state)
  }
  guard @engine.remote_server_base(state.manager) is Some(server_url) else {
    raise @host.HostError("remote access needs the SeekMoon relay origin")
  }
  store.sign_in(server_url~) catch {
    error if @async.is_being_cancelled() => raise error
    @auth.AuthError(message) => raise @host.HostError(message)
    error => raise @host.HostError("sign-in failed: \{error}")
  }
  // The persisted session is not final until its issuer still matches the
  // selected server. This protected completion also runs when cancellation
  // landed during the commit shield in `sign_in`.
  @async.protect_from_cancel(() => {
    if @engine.remote_server_base(state.manager) != Some(server_url) {
      // Publish the final local state even if cleanup itself raises after
      // clearing it.
      defer state.hub.publish(AuthChanged(store.status()))
      store.sign_out() catch {
        @auth.AuthError(message) =>
          raise @host.HostError(
            "could not discard the superseded sign-in: \{message}",
          )
        error =>
          raise @host.HostError(
            "could not discard the superseded sign-in: \{error}",
          )
      }
      raise @host.HostError(
        "the server changed during sign-in; connect again for the selected server",
      )
    }
    state.hub.publish(AuthChanged(store.status()))
  })
  auth_status(state)
}

///|
/// Sign out: the durable local clear wins, the relay-side revoke is
/// best-effort, and the supervisor parks once poked.
async fn auth_disconnect(state : ApiState) -> @protocol.AuthStatusPayload {
  let store = state.auth
  if store.managed_by_env() {
    raise @host.HostError("remote access is configured through the environment")
  }
  store.sign_out() catch {
    error if @async.is_being_cancelled() => {
      // `sign_out` has already cleared local authority and poked the
      // supervisor before cancellation can escape its local transition.
      @async.protect_from_cancel(() => {
        state.hub.publish(AuthChanged(store.status()))
      })
      raise error
    }
    @auth.AuthError(message) => {
      // `clear_local_session` clears memory and parks the connector before
      // it writes the marker. Publish that truthful in-process state even
      // though the persistence failure must still reach the requester.
      @async.protect_from_cancel(() => {
        state.hub.publish(AuthChanged(store.status()))
      })
      raise @host.HostError(message)
    }
    error => raise @host.HostError("sign-out failed: \{error}")
  }
  @async.protect_from_cancel(() => {
    state.hub.publish(AuthChanged(store.status()))
  })
  auth_status(state)
}

///|
/// Abort an in-flight sign-in; the pending `auth.connect` settles with
/// its own error. A no-op (current status) when nothing is in flight.
async fn auth_cancel(state : ApiState) -> @protocol.AuthStatusPayload {
  ignore(state.auth.cancel_sign_in())
  auth_status(state)
}

///|
/// A server switch orphans a sign-in — the device token belongs to the
/// server that issued it. Called after every settings commit; a no-op
/// unless the signed-in issuer no longer matches the selection.
async fn sign_out_after_server_switch(state : ApiState) -> Unit {
  let store = state.auth
  guard !store.managed_by_env() && store.signed_in() else { return }
  if store.session_server() == @engine.remote_server_base(state.manager) {
    return
  }
  store.sign_out() catch {
    error if @async.is_being_cancelled() => raise error
    @auth.AuthError(message) =>
      @xlog.warn(category="auth") <?
        { "message": "sign-out after server switch failed", "error": message }
    error =>
      @xlog.warn(category="auth") <?
        {
          "message": "sign-out after server switch failed",
          "error": "\{error}",
        }
  }
  @async.protect_from_cancel(() => {
    state.hub.publish(AuthChanged(store.status()))
  })
}

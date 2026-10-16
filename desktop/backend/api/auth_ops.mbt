// The auth.* op bodies (docs/remote-protocol.md): they run the sign-in
// flows in `auth` and translate its errors into the transports'
// `HostError` vocabulary. They live here — not in `auth` — so
// `auth.changed` can go through the hub, and the relay actor
// (remote, which imports this package) stays cycle-free.

///|
/// The current status. The fallback `server_url` is the relay origin —
/// a SeekMoon-hosted service that no longer depends on the chat provider.
async fn auth_status(state : ApiState) -> @protocol.AuthStatusPayload {
  state.auth.status(server_url?=@engine.remote_server_base(state.manager))
}

///|
/// Sign in to the fixed account issuer. An existing session is reused;
/// neither path enables remote access or registers a device.
async fn auth_connect(state : ApiState) -> @protocol.AuthStatusPayload {
  let store = state.auth
  if store.signed_in() {
    return auth_status(state)
  }
  let server_url = @auth.AccountOrigin
  store.sign_in(server_url~) catch {
    @auth.AuthError(message) => raise @host.HostError(message)
    error => raise @host.HostError("sign-in failed: \{error}")
  }
  state.hub.publish(AuthChanged(store.status()))
  auth_status(state)
}

///|
/// Sign out: the durable local clear wins, the relay-side revoke is
/// best-effort, and the ordinary remote supervisor parks once poked.
async fn auth_disconnect(state : ApiState) -> @protocol.AuthStatusPayload {
  let store = state.auth
  // Publish the resulting state on success, failure, and cancellation alike;
  // sign_out serializes the local clear with persistence.
  defer state.hub.publish(AuthChanged(store.status()))
  store.sign_out() catch {
    @auth.AuthError(message) => raise @host.HostError(message)
    error => raise @host.HostError("sign-out failed: \{error}")
  }
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
async fn remote_access_set(
  state : ApiState,
  payload : @protocol.RemoteAccessPayload,
) -> @protocol.AuthStatusPayload {
  defer state.publish(AuthChanged(state.auth.status()))
  state.auth.set_remote(payload.enabled) catch {
    @auth.AuthError(message) => raise @host.HostError(message)
    error => raise error
  }
  auth_status(state)
}

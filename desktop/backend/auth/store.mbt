// One account session, with an optional registration for this computer.
// Account sign-in never enables the relay connector. Device rejection and
// transient network loss never retire the account credential.

///|
/// Every user-actionable failure of the sign-in/sign-out flows. The API
/// layer translates it into its transport error shape.
pub(all) suberror AuthError {
  AuthError(String)
}

///|
pub impl Show for AuthError with fn output(self, logger) {
  match self {
    AuthError(message) => logger.write_string(message)
  }
}

///|
/// What the connector needs to run — one shape for both a signed-in
/// session (derived) and the `OPENSEEK_RELAY_URL`/`OPENSEEK_DEVICE_TOKEN`
/// development override (verbatim).
pub(all) struct ConnectorConfig {
  relay_url : String
  device_token : String
  device_name : String
} derive(Eq)

///|
/// One persisted account and its independently enabled device permission.
priv struct AuthSession {
  server_url : String
  account : @protocol.AccountSession
  device : DeviceRegistration?
}

///|
priv struct DeviceRegistration {
  token : String
  id : String
  name : String
}

///|
/// See the package docs above. Constructed once at startup by
/// `AuthStore::load` and shared by the dispatcher (auth.* ops) and the
/// relay actor. Account credentials are exposed only to the local window;
/// broadcasts carry presentation state without secrets.
struct AuthStore {
  runtime_dir : @pathx.Path?
  env_override : ConnectorConfig?
  // Installed package version used to keep the linked Browser bundle on the
  // same release as this Desktop. Development builds have no release bundle.
  app_version : String
  // The relay actor's coalescing poke channel: `DiscardOldest(1)` never
  // blocks a producer and buffers at most one pending wakeup.
  wakeups : @async.Queue[Unit]
  mut session : AuthSession?
  // Whether the control WebSocket is currently registered.
  mut connected : Bool
  // Override mode only: the device id learned at registration (a session
  // carries its own).
  mut override_device : String?
  // Override mode only: the relay rejected the env token as terminal;
  // nothing can mint a new one at runtime, so the supervisor parks.
  mut rejected : Bool
  persist_mutex : @async.Mutex
  mut remote_generation : Int32
  mut sign_in_active : Bool
  // Poked by auth.cancel; the in-flight sign-in races against it.
  sign_in_abort : @async.Queue[Unit]
}

///|
/// Load the persisted sign-in (when there is a runtime dir to read from).
/// The environment override controls only the relay, independently of the
/// persisted account session. The override itself is never persisted.
pub async fn AuthStore::load(
  runtime_dir? : @pathx.Path,
  env_override? : ConnectorConfig,
  app_version~ : String = "development",
) -> AuthStore {
  let session = match runtime_dir {
    Some(dir) => load_session_file(dir)
    None => None
  }
  {
    runtime_dir,
    env_override,
    app_version,
    wakeups: Queue(kind=DiscardOldest(1)),
    session,
    connected: false,
    override_device: None,
    rejected: false,
    persist_mutex: Mutex(),
    remote_generation: 0,
    sign_in_active: false,
    sign_in_abort: Queue(kind=DiscardOldest(1)),
  }
}

///|
/// A store with nothing signed in and nothing persisted — the default for
/// test-constructed API states.
pub fn AuthStore::empty(app_version~ : String = "development") -> AuthStore {
  {
    runtime_dir: None,
    env_override: None,
    app_version,
    wakeups: Queue(kind=DiscardOldest(1)),
    session: None,
    connected: false,
    override_device: None,
    rejected: false,
    persist_mutex: Mutex(),
    remote_generation: 0,
    sign_in_active: false,
    sign_in_abort: Queue(kind=DiscardOldest(1)),
  }
}

///|
/// What the connector should currently run, if anything. The supervisor
/// re-reads this after every wakeup.
pub fn AuthStore::desired_connector(self : AuthStore) -> ConnectorConfig? {
  if self.env_override is Some(config) {
    return if self.rejected { None } else { Some(config) }
  }
  guard self.session is Some(session) && session.device is Some(device) else {
    return None
  }
  Some({
    relay_url: tunnel_url(session.server_url),
    device_token: device.token,
    device_name: device.name,
  })
}

///|
/// Wake the supervisor to re-read `desired_connector`. Never blocks; a
/// poke while one is already pending coalesces. `try_put` can only raise
/// on a closed queue, and this queue is never closed.
pub fn AuthStore::poke(self : AuthStore) -> Unit {
  ignore(self.wakeups.try_put(()) catch { _ => false })
}

///|
/// The relay actor's park/wakeup channel.
pub fn AuthStore::wakeups(self : AuthStore) -> @async.Queue[Unit] {
  self.wakeups
}

///|
/// The control connection registered under `device`. True iff the visible
/// status changed (callers publish `auth.changed` exactly then).
pub fn AuthStore::mark_registered(self : AuthStore, device : String) -> Bool {
  let changed = !self.connected ||
    (self.env_override is Some(_) && self.override_device != Some(device))
  self.connected = true
  if self.env_override is Some(_) {
    self.override_device = Some(device)
  }
  changed
}

///|
/// The control connection ended (retry follows unless the config is
/// gone). True iff this flipped the visible status.
pub fn AuthStore::mark_dropped(self : AuthStore) -> Bool {
  let changed = self.connected
  self.connected = false
  changed
}

///|
/// The relay refused registration as terminal (bad or revoked token). In
/// override mode nothing can repair the config at runtime, so the store
/// only parks the relay actor; a signed-in session is cleared like a
/// sign-out, minus the revoke round-trip the relay already answered for.
pub async fn AuthStore::handle_refusal(
  self : AuthStore,
  expected? : ConnectorConfig,
) -> Unit {
  if expected is Some(expected) && self.desired_connector() != Some(expected) {
    return
  }
  self.connected = false
  if self.env_override is Some(_) {
    self.rejected = true
    return
  }
  self.persist_mutex.acquire()
  defer self.persist_mutex.release()
  if expected is Some(expected) && self.desired_connector() != Some(expected) {
    return
  }
  guard self.session is Some(session) else { return }
  self.remote_generation += 1
  let session = { ..session, device: None, }
  self.session = Some(session)
  if self.runtime_dir is Some(dir) {
    save_session_file(dir, session)
  }
}

///|
/// Abort an in-flight sign-in: the pending `auth.connect` fails with "the
/// sign-in was cancelled". True when one was actually running.
pub fn AuthStore::cancel_sign_in(self : AuthStore) -> Bool {
  guard self.sign_in_active else { return false }
  ignore(self.sign_in_abort.try_put(()) catch { _ => false })
  true
}

///|
/// Whether a sign-in session exists (regardless of connector state).
pub fn AuthStore::signed_in(self : AuthStore) -> Bool {
  self.session is Some(_)
}

///|
/// The fixed issuer of the signed-in account credential.
pub fn AuthStore::session_server(self : AuthStore) -> String? {
  self.session.map(session => session.server_url)
}

///|
/// Whether the environment override drives the connector. Account login and
/// logout remain available and do not alter that debug connection.
pub fn AuthStore::managed_by_env(self : AuthStore) -> Bool {
  self.env_override is Some(_)
}

///|
/// The status shape (docs/remote-protocol.md `auth.*`): also the params of
/// every `auth.changed` notification. `server_url` reflects the signed-in
/// session's issuer when there is one, the override's origin in override
/// mode, and otherwise the caller-provided current selection (absent when
/// the selected server has no relay).
pub fn AuthStore::status(
  self : AuthStore,
  server_url? : String,
) -> @protocol.AuthStatusPayload {
  let user = self.session.map(session => @protocol.AuthUserPayload::{
    login: session.account.user.login,
    avatar_url: session.account.user.avatar_url,
  })
  let device = if self.env_override is Some(config) {
    self.override_device.map(id => @protocol.AuthDevicePayload::{
      id,
      name: config.device_name,
      url: device_url(
        origin_from_relay_url(config.relay_url),
        id,
        app_version=self.app_version,
      ),
    })
  } else {
    self.session.bind(session => {
      session.device.map(device => {
        id: device.id,
        name: device.name,
        url: device_url(
          session.server_url,
          device.id,
          app_version=self.app_version,
        ),
      })
    })
  }
  {
    connected: self.connected,
    server_url: match self.session {
      Some(session) => Some(session.server_url)
      None => server_url
    },
    managed_by_env: if self.env_override is Some(_) {
      Some(true)
    } else {
      None
    },
    user,
    device,
  }
}

///|
/// Sign out: clear the local session first, then best-effort revoke the
/// device at its issuing server. A local persistence failure is reported:
/// memory is already signed out, but returning success while an old token
/// could survive a restart would violate the user's disconnect request.
pub async fn AuthStore::sign_out(self : AuthStore) -> Unit {
  guard !self.sign_in_active else {
    raise AuthError("a sign-in is in progress")
  }
  let retired : Ref[AuthSession?] = Ref(None)
  let mut clear_error : String? = None
  @async.protect_from_cancel(() => {
    self.persist_mutex.acquire()
    defer self.persist_mutex.release()
    retired.val = self.session
    self.clear_session_locked() catch {
      AuthError(message) => clear_error = Some(message)
      error => clear_error = Some("\{error}")
    }
  })
  // Even when the local marker could not be written, revoking online may
  // still make the old on-disk credential harmless on the next launch.
  if retired.val is Some(session) {
    revoke_session(session) catch {
      error =>
        @xlog.warn(category="auth") <?
          { "message": "session revoke failed", "error": "\{error}" }
    }
  }
  if clear_error is Some(message) {
    raise AuthError(message)
  }
}

///|
/// Clear local authority and wake the connector as one cancellation-safe
/// transition. Persisting the signed-out marker may fail and is reported,
/// but neither that failure nor requester cancellation may leave the old
/// connector running in this process.
async fn AuthStore::clear_local_session(
  self : AuthStore,
  token? : String,
) -> Unit {
  @async.protect_from_cancel(() => {
    self.persist_mutex.acquire()
    defer self.persist_mutex.release()
    if token is Some(token) &&
      self.account().map(account => account.token) != Some(token) {
      return
    }
    self.clear_session_locked()
  })
}

///|
/// The caller holds persist_mutex across the state transition and file write.
async fn AuthStore::clear_session_locked(self : AuthStore) -> Unit {
  self.session = None
  self.remote_generation += 1
  if self.env_override is None {
    self.connected = false
    self.poke()
  }
  if self.runtime_dir is Some(dir) {
    delete_session_file(dir)
  }
}

///|
pub extend AuthError with Show::{output, to_string}

///|
pub extend ConnectorConfig with Eq::{equal, not_equal}

///|
/// Read only from the native window's credential endpoint, never auth.changed.
pub fn AuthStore::account(self : AuthStore) -> @protocol.AccountSession? {
  self.session.map(session => session.account)
}

///|
/// Expire only the credential that actually received a 401.
pub async fn AuthStore::expire_account(
  self : AuthStore,
  token : String,
) -> Unit {
  if self.account() is Some(account) && account.token == token {
    self.clear_local_session(token~)
  }
}

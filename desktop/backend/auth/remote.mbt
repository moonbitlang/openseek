///|
/// Account authority is always issued by the canonical authentication origin.
pub const AccountOrigin : String = "https://openseek-api.moonbitlang.cn"

///|
/// Enable or retire only this computer's device permission. Registration is
/// fenced against sign-out or a later toggle while its HTTP request is pending.
pub async fn AuthStore::set_remote(self : AuthStore, enabled : Bool) -> Unit {
  guard !self.managed_by_env() else {
    raise AuthError("remote access is managed by the environment")
  }
  self.remote_generation += 1
  let generation = self.remote_generation
  guard self.session is Some(session) else {
    raise AuthError("sign in before enabling remote access")
  }
  if !enabled {
    let retired : Ref[DeviceRegistration?] = Ref(None)
    @async.protect_from_cancel(() => {
      self.persist_mutex.acquire()
      defer self.persist_mutex.release()
      if self.account().map(account => account.token) !=
        Some(session.account.token) {
        return
      }
      guard self.session is Some(current) else { return }
      retired.val = current.device
      self.session = Some({ ..current, device: None, })
      self.connected = false
      self.poke()
      if self.runtime_dir is Some(dir) {
        save_session_file(dir, { ..current, device: None, })
      }
    })
    if retired.val is Some(device) {
      revoke_device(session.server_url, device)
    }
    return
  }
  if session.device is Some(_) {
    return
  }
  let registered : Ref[DeviceRegistration?] = Ref(None)
  @async.protect_from_cancel(() => {
    @async.with_task_group(group => {
      let exchange = group.spawn(() => register_device(session))
      registered.val = Some(exchange.wait())
    })
  }) catch {
    RegistrationUnauthorized => {
      self.expire_account(session.account.token)
      raise AuthError("your account sign-in expired")
    }
    error => raise error
  }
  guard registered.val is Some(device) else {
    raise AuthError("device registration returned no credential")
  }
  let cancelled = @async.is_being_cancelled()
  let next = { ..session, device: Some(device), }
  @async.protect_from_cancel(() => {
    self.persist_mutex.acquire()
    defer self.persist_mutex.release()
    if cancelled ||
      self.remote_generation != generation ||
      self.account().map(account => account.token) !=
      Some(session.account.token) {
      @async.with_task_group(group => {
        let cleanup = group.spawn(() => {
          revoke_device(session.server_url, device)
        })
        cleanup.wait()
      })
      return
    }
    if self.runtime_dir is Some(dir) {
      errdefer (revoke_device(session.server_url, device) catch { _ => () })
      save_session_file(dir, next)
    }
    self.session = Some(next)
    self.poke()
  })
}

///|
priv suberror RegistrationUnauthorized {
  RegistrationUnauthorized
}

///|
async fn register_device(session : AuthSession) -> DeviceRegistration {
  let name = @platform.machine_hostname().unwrap_or("Desktop")
  guard @async.with_timeout_opt(ExchangeTimeoutMs, () => {
      let body : Json = { "name": name, "hostname": name }
      @http.post(session.server_url + "/v2/devices", body, headers={
        "Authorization": "Bearer " + session.account.token,
      })
    })
    is Some((response, body)) else {
    raise AuthError("device registration timed out")
  }
  if response.code == 401 {
    raise RegistrationUnauthorized
  }
  guard response.code is (200 | 201) else {
    raise AuthError("device registration answered HTTP \{response.code}")
  }
  guard body.json()
    is {
      "device_token": String(token),
      "device": { "id": String(id), "name": String(name), .. },
      ..
    } else {
    raise AuthError("device registration answered malformed JSON")
  }
  { token, id, name, }
}

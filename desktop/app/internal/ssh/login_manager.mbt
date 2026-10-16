///|
priv suberror LoginRequestError {
  LoginUnsent(String)
  LoginRefused(String)
  LoginUnknown(String)
}

///|
impl Show for LoginRequestError with fn output(self, logger) {
  match self {
    LoginUnsent(message) | LoginRefused(message) | LoginUnknown(message) =>
      logger.write_string(message)
  }
}

///|
priv struct LoginAttempt {
  key : String
  epoch : Int32
  reply : @async.Queue[Result[Json, String]]
  stop : @async.Queue[Unit]
  early_completed : Set[String]
  mut login_id : String?
  mut cancelled : Bool
  mut completed : Bool
  mut replied : Bool
  mut cancel_reply : Result[Json, String]?
  mut task : @async.Task[Unit]?
}

///|
fn LoginAttempt::LoginAttempt(epoch : Int32) -> LoginAttempt raise {
  {
    key: @uuid.mint(),
    epoch,
    reply: Queue(kind=Blocking(1)),
    stop: Queue(kind=Blocking(1)),
    early_completed: Set([]),
    login_id: None,
    cancelled: false,
    completed: false,
    replied: false,
    cancel_reply: None,
    task: None,
  }
}

///|
fn LoginAttempt::offer(
  self : LoginAttempt,
  reply : Result[Json, String],
) -> Unit {
  if !self.replied {
    self.replied = true
    ignore(self.reply.try_put(reply) catch { _ => false })
  }
}

///|
fn LoginAttempt::cancel(self : LoginAttempt) -> Unit {
  self.cancelled = true
  ignore(self.stop.try_put(()) catch { _ => false })
}

///|
/// The manager belongs to one immutable window route. Its task group outlives
/// individual command callers so cancellation while login.start is in flight
/// still captures the eventual login ID. The callback-port file lock also
/// arbitrates other windows/processes before starting a remote login.
priv struct LoginManager {
  directory : String
  spawn : (async () -> Unit) -> @async.Task[Unit]
  request : async (Int32, String, Json) -> Json
  abort_connection : (Int32) -> Unit
  tunnel : async (async () -> Unit) -> Unit
  notify_failure : async (Int32, String, String) -> Unit
  mut active : LoginAttempt?
  mut closed : Bool
}

///|
fn LoginManager::LoginManager(
  directory~ : String,
  spawn~ : (async () -> Unit) -> @async.Task[Unit],
  request~ : async (Int32, String, Json) -> Json,
  abort_connection~ : (Int32) -> Unit,
  tunnel~ : async (async () -> Unit) -> Unit,
  notify_failure~ : async (Int32, String, String) -> Unit,
) -> LoginManager {
  {
    directory,
    spawn,
    request,
    abort_connection,
    tunnel,
    notify_failure,
    active: None,
    closed: false,
  }
}

///|
async fn LoginManager::start(
  self : LoginManager,
  epoch : Int32,
  params : Json,
) -> Json {
  guard !self.closed && self.active is None else {
    raise SshError("This SSH host already has a browser login in progress")
  }
  let attempt = LoginAttempt(epoch)
  self.active = Some(attempt)
  attempt.task = Some((self.spawn)(() => self.drive(attempt, params)))
  let delivered = Ref(false)
  defer (if !delivered.val { attempt.cancel() })
  let reply = attempt.reply.get()
  delivered.val = true
  match reply {
    Ok(value) => value
    Err(message) => raise SshError(message)
  }
}

///|
async fn LoginManager::drive(
  self : LoginManager,
  attempt : LoginAttempt,
  params : Json,
) -> Unit {
  defer {
    attempt.offer(
      Err("SSH login scope closed before its callback became ready"),
    )
    if self.active is Some(current) && current.key == attempt.key {
      self.active = None
    }
  }
  try {
    let lease = @fs.open(
      self.directory + "/ssh-oauth-callback.lock",
      mode=ReadWrite,
      create_mode=OpenOrCreate,
      permission=0o600,
    )
    defer lease.close()
    guard lease.try_lock(Exclusive) else {
      raise SshError(
        "Another SSH browser login is using callback port 1455; complete or cancel it first",
      )
    }
    guard !attempt.cancelled else { raise SshError("SSH login was cancelled") }
    let raw = @async.with_timeout(30000, () => {
      (self.request)(
        attempt.epoch,
        @commands.codex_account_login_start.name(),
        params,
      )
    }) catch {
      LoginUnsent(_) | LoginRefused(_) as error => raise error
      error => {
        // The server may have accepted the request without returning an ID.
        // Retire only this epoch; its server-side login scope cleans up even
        // when admission finishes the request after the socket has closed.
        (self.abort_connection)(attempt.epoch)
        raise error
      }
    }
    let decoded : @protocol.CodexCommandReply[@protocol.CodexLoginStartReply] = @json.from_json(
      raw,
    ) catch {
      _ => {
        (self.abort_connection)(attempt.epoch)
        raise SshError("Malformed Codex browser login reply")
      }
    }
    guard decoded is CodexCommandSuccess(login) else {
      attempt.offer(Ok(raw))
      return
    }
    attempt.login_id = Some(login.login_id)
    attempt.completed = attempt.early_completed.contains(login.login_id)
    defer @async.protect_from_cancel(() => self.clean_remote(attempt))
    guard !login.login_id.is_blank() &&
      (
        login.auth_url.has_prefix("https://") ||
        login.auth_url.has_prefix("http://")
      ) else {
      raise SshError("Codex returned an invalid browser login URL or identity")
    }
    if attempt.cancelled || attempt.completed {
      raise SshError(
        "SSH login finished before the browser was opened; refresh account state",
      )
    }
    (self.tunnel)(() => {
      guard !attempt.cancelled && !attempt.completed else { return }
      attempt.offer(Ok(raw))
      attempt.stop.get()
    })
  } catch {
    error =>
      if attempt.replied &&
        !attempt.cancelled &&
        !attempt.completed &&
        attempt.login_id is Some(id) {
        (self.notify_failure)(attempt.epoch, id, "\{error}") catch {
          _ => ()
        }
      } else {
        attempt.offer(Err("\{error}"))
      }
  }
  if !attempt.replied {
    attempt.offer(
      Err("SSH login was cancelled before its callback became ready"),
    )
  }
}

///|
async fn LoginManager::clean_remote(
  self : LoginManager,
  attempt : LoginAttempt,
) -> Unit {
  guard attempt.login_id is Some(id) && !attempt.completed else {
    attempt.cancel_reply = Some(Ok(Json::empty_object()))
    return
  }
  let reply = Ok(
    @async.with_timeout(3000, () => {
      (self.request)(
        attempt.epoch,
        @commands.codex_account_login_cancel.name(),
        { "loginId": id },
      )
    }),
  ) catch {
    error => {
      if error is @async.TimeoutError {
        (self.abort_connection)(attempt.epoch)
      }
      Err("Could not cancel the remote login: \{error}")
    }
  }
  attempt.cancel_reply = Some(reply)
}

///|
async fn LoginManager::cancel(
  self : LoginManager,
  epoch : Int32,
  id : String,
) -> Json {
  guard self.active is Some(attempt) &&
    attempt.epoch == epoch &&
    attempt.login_id == Some(id) else {
    raise SshError("This login is not owned by the current SSH host")
  }
  attempt.cancel()
  if attempt.task is Some(task) {
    task.wait()
  }
  match attempt.cancel_reply {
    Some(Ok(value)) => {
      if value is { "error": String(message), .. } {
        (self.notify_failure)(epoch, id, message)
      }
      value
    }
    Some(Err(message)) => {
      (self.notify_failure)(epoch, id, message)
      raise SshError(message)
    }
    None => raise SshError("SSH login cancellation did not settle")
  }
}

///|
fn LoginManager::observe(
  self : LoginManager,
  epoch : Int32,
  value : Json,
) -> Unit {
  guard self.active is Some(attempt) && attempt.epoch == epoch else { return }
  guard value
    is {
      "method": "codex.notification",
      "params": {
        "method": "account/login/completed",
        "params": { "loginId": String(id), .. },
        ..
      },
      ..
    } else {
    return
  }
  if attempt.login_id == Some(id) {
    attempt.completed = true
    ignore(attempt.stop.try_put(()) catch { _ => false })
  } else if attempt.login_id is None && attempt.early_completed.length() < 16 {
    attempt.early_completed.add(id)
  }
}

///|
fn LoginManager::disconnected(self : LoginManager) -> Unit {
  if self.active is Some(attempt) {
    attempt.cancel()
  }
}

///|
async fn LoginManager::close(self : LoginManager) -> Unit {
  self.closed = true
  self.stop_active() catch {
    _ => ()
  }
}

///|
async fn LoginManager::stop_active(self : LoginManager) -> Unit {
  guard self.active is Some(attempt) else { return }
  attempt.cancel()
  if attempt.task is Some(task) {
    @async.with_timeout(5000, () => task.wait()) catch {
      _ => {
        (self.abort_connection)(attempt.epoch)
        task.cancel()
      }
    }
  }
  match attempt.cancel_reply {
    Some(Err(message)) => raise SshError(message)
    Some(Ok({ "error": String(message), .. })) => raise SshError(message)
    _ => ()
  }
}

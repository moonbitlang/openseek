///|
/// Browser login belongs to the requesting direct connection, unlike an agent
/// run. The admission pump may finish a login-start after that connection has
/// closed; retaining this scope in the admitted operation cancels that late
/// login instead of losing its ID with the reply.
priv struct ClientLoginScope {
  cancel : async (String) -> Unit
  mut closed : Bool
  mut cancelling : Bool
  mut starting : Bool
  mut pending : String?
  completed_while_starting : Set[String]
}

///|
fn ClientLoginScope::ClientLoginScope(
  cancel : async (String) -> Unit,
) -> ClientLoginScope {
  {
    cancel,
    closed: false,
    starting: false,
    cancelling: false,
    pending: None,
    completed_while_starting: Set([]),
  }
}

///|
async fn ClientLoginScope::invoke(
  self : ClientLoginScope,
  method_ : String,
  params : Json,
  body : async () -> Json,
) -> Json {
  if method_ == @commands.codex_account_login_start.name() {
    guard !self.closed && !self.starting else {
      raise @host.HostError("This connection is starting a login or has closed")
    }
    self.starting = true
    self.completed_while_starting.clear()
    defer {
      self.starting = false
      self.completed_while_starting.clear()
    }
    self.cancel_pending()
    guard !self.closed else {
      raise @host.HostError("The login connection closed")
    }
    let reply = body()
    if reply is { "loginId": String(id), .. } {
      if !self.completed_while_starting.contains(id) {
        self.pending = Some(id)
      }
      if self.closed {
        self.close()
        raise @host.HostError(
          "The login connection closed before login was ready",
        )
      }
    }
    return reply
  }
  if method_ == @commands.codex_account_login_cancel.name() {
    guard params is { "loginId": String(id), .. } && self.pending == Some(id) else {
      raise @host.HostError(
        "This login is not owned by the requesting connection",
      )
    }
    let reply = body()
    if !(reply is { "error": _, .. }) && self.pending == Some(id) {
      self.pending = None
    }
    return reply
  }
  body()
}

///|
fn ClientLoginScope::observe(
  self : ClientLoginScope,
  event : @protocol.HostNotification,
) -> Unit {
  guard event
    is CodexNotification(
      {
        "method": "account/login/completed",
        "params": { "loginId": String(id), .. },
        ..
      }
    ) else {
    return
  }
  if self.pending == Some(id) {
    self.pending = None
  } else if self.starting && self.completed_while_starting.length() < 16 {
    self.completed_while_starting.add(id)
  }
}

///|
async fn ClientLoginScope::close(self : ClientLoginScope) -> Unit {
  self.closed = true
  self.cancel_pending()
}

///|
async fn ClientLoginScope::cancel_pending(self : ClientLoginScope) -> Unit {
  guard self.pending is Some(id) else { return }
  self.pending = None
  self.cancelling = true
  defer {
    self.cancelling = false
  }
  // Failed cleanup remains busy, including after disconnect. A later upgrade
  // must not assume that an unconfirmed browser login has gone away.
  errdefer (if self.pending is None { self.pending = Some(id) })
  @async.protect_from_cancel(() => {
    @async.with_timeout(3000, () => (self.cancel)(id))
  })
}

///|
fn ClientLoginScope::has_active_work(self : ClientLoginScope) -> Bool {
  self.starting || self.cancelling || self.pending is Some(_)
}

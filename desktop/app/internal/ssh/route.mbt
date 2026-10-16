///|
/// One immutable window binding. Its only methods are the authoritative
/// working-host catalog supplied by the desktop composition root. Local window
/// and OS commands never fall through this route to a working host.
pub struct Route {
  profile : @protocol.SshProfile
  priv store : Store
  priv connection : @host_client.Connection
  priv methods : Set[String]
  priv mut ready_epoch : Int32?
  priv mut logins : LoginManager?
  priv mut previews : PreviewCache?
  priv terminals : @terminal.TerminalState
  priv mut running : Bool
}

///|
pub fn Route::Route(
  store : Store,
  profile : @protocol.SshProfile,
  methods : Array[String],
  ssh~ : String = "/usr/bin/ssh",
) -> Route raise {
  validate(profile)
  let host = @host_client.Host(id=profile.id, {
    ssh,
    destination: profile.destination,
    launcher: profile.launcher,
    data_dir: profile.data_dir,
    build_id: profile.build_id,
    expected_server_id: profile.server_id,
  })
  {
    profile,
    store,
    terminals: @terminal.new_terminal_state(),
    connection: Connection(host),
    methods: Set::from_array(methods),
    ready_epoch: None,
    previews: None,
    logins: None,
    running: false,
  }
}

///|
/// Identity persistence precedes Connected. A full event queue fails the
/// route, rather than losing events or blocking the WebSocket reader.
pub async fn Route::run(
  self : Route,
  emit~ : async (@host_client.ConnectionEvent) -> Unit,
) -> Unit {
  guard !self.running else {
    raise SshError("SSH host route is already running")
  }
  self.running = true
  defer {
    self.running = false
    self.ready_epoch = None
  }
  let previews = PreviewCache(@fs.tmpdir(prefix="seekmoon-ssh-preview-"))
  self.previews = Some(previews)
  defer {
    self.ready_epoch = None
    self.previews = None
    previews.close()
  }
  let events : @async.Queue[(@host_client.ConnectionEvent, Int32)] = Queue(
    kind=Blocking(64),
  )
  let retained = Ref(0)
  @async.with_task_group(group => {
    let logins = LoginManager(
      directory=self.store.directory,
      spawn=body => group.spawn(body, allow_failure=true),
      request=(epoch, method_, params) => {
        match
          self.request_direct({
            host_id: self.profile.id,
            epoch,
            method_,
            params,
          }) {
          SshSuccess(value) => value
          SshUnsent(message) => raise LoginUnsent(message)
          SshRefused(message) => raise LoginRefused(message)
          SshUnknown(message) => raise LoginUnknown(message)
        }
      },
      abort_connection=epoch => self.connection.invalidate(epoch~),
      tunnel=body => {
        with_callback_tunnel(
          ssh=self.connection.host.config.ssh,
          destination=self.profile.destination,
          body,
        )
      },
      notify_failure=(epoch, id, message) => {
        if self.ready_epoch == Some(epoch) {
          emit(
            Notification(epoch~, value={
              "method": "codex.notification",
              "params": {
                "method": "seekmoon/login_failed",
                "params": { "loginId": id, "message": message },
              },
            }),
          )
        }
      },
    )
    self.logins = Some(logins)
    group.add_defer(() => {
      @async.protect_from_cancel(() => {
        self.logins = None
        logins.close()
      })
    })
    group.spawn_bg(() => {
      self.connection.run(emit=event => {
        let bytes = @utf8.encode(event.to_json().stringify()).length()
        if bytes > 64 * 1024 * 1024 - retained.val {
          return false
        }
        if !(events.try_put((event, bytes)) catch { _ => false }) {
          return false
        }
        retained.val += bytes
        true
      })
    })
    for ;; {
      let (event, bytes) = events.get()
      defer {
        retained.val -= bytes
      }
      match event {
        Connected(epoch~, identity~) => {
          self.store.pin(self.profile, identity.server_id) catch {
            ProfileIdentityChanged(message) => {
              self.ready_epoch = None
              emit(IdentityBlocked(epoch~, message~))
              group.return_immediately(())
              return
            }
            error => raise error
          }
          self.ready_epoch = Some(epoch)
        }
        Connecting(..) | Disconnected(..) | IdentityBlocked(..) => {
          self.ready_epoch = None
          logins.disconnected()
        }
        Notification(epoch~, value~) => logins.observe(epoch, value)
      }
      emit(event)
      if event is IdentityBlocked(..) {
        group.return_immediately(())
        return
      }
    }
  })
}

///|
async fn Route::request_direct(
  self : Route,
  request : @protocol.SshRequest,
) -> @protocol.SshReply {
  guard request.host_id == self.profile.id &&
    self.ready_epoch == Some(request.epoch) else {
    return SshUnsent("SSH host identity or connection changed")
  }
  guard self.methods.contains(request.method_) else {
    return SshUnsent("This operation is not a working-host command")
  }
  let value = self.connection.request(
    epoch=request.epoch,
    request.method_,
    request.params,
  ) catch {
    @host_client.Unsent(message) => return SshUnsent(message)
    @host_client.Refused(message) => return SshRefused(message)
    error => return SshUnknown("\{error}")
  }
  guard self.ready_epoch == Some(request.epoch) else {
    return SshUnknown("SSH response belongs to a retired window connection")
  }
  SshSuccess(value)
}

///|
/// Native window operations capture their route before reading remote content.
/// Request's existing reply fence rejects a replacement connection; no retry or
/// local fallback is performed when the read loses that connection.
pub async fn[Payload : ToJson, Reply : @json.FromJson] Route::request_current(
  self : Route,
  command : @commands.Command[Payload, Reply],
  payload : Payload,
) -> Reply {
  guard self.ready_epoch is Some(epoch) else {
    raise SshError("SSH connection is unavailable")
  }
  match
    self.request({
      host_id: self.profile.id,
      epoch,
      method_: command.name(),
      params: payload.to_json(),
    }) {
    SshSuccess(value) => @json.from_json(value)
    SshUnsent(message) | SshRefused(message) | SshUnknown(message) =>
      raise SshError(message)
  }
}

///|
/// Fetch on the immutable working host, then return a private local copy's
/// URI path. The remote source never becomes a local destination.
pub async fn Route::preview_file(self : Route, source : String) -> String {
  guard self.previews is Some(cache) && self.ready_epoch is Some(epoch) else {
    raise SshError("SSH preview connection is unavailable")
  }
  let local_path = cache.load(source, () => {
    self.request_current(@commands.fs_preview_content, {
      path: source,
      root: None,
    })
  })
  guard self.ready_epoch == Some(epoch) else {
    raise SshError("SSH preview belongs to a retired connection")
  }
  guard @pathx.Path(local_path).to_absolute().bind(path => path.to_uri_path())
    is Some(path) else {
    raise SshError("Invalid local preview path")
  }
  path
}

///|
pub async fn Route::request(
  self : Route,
  request : @protocol.SshRequest,
) -> @protocol.SshReply {
  guard self.methods.contains(request.method_) else {
    return SshUnsent("This operation is not a working-host command")
  }
  guard request.host_id == self.profile.id &&
    self.ready_epoch == Some(request.epoch) else {
    return SshUnsent("SSH host identity or connection changed")
  }
  if request.method_ == @commands.codex_account_login_start.name() ||
    request.method_ == @commands.codex_account_login_cancel.name() {
    guard self.logins is Some(logins) else {
      return SshUnsent("SSH login manager is unavailable")
    }
    let value = try {
      if request.method_ == @commands.codex_account_login_start.name() {
        let payload : @protocol.CodexAccountLoginStartPayload = @json.from_json(
          request.params,
        ) catch {
          _ => return SshRefused("Invalid Codex browser login payload")
        }
        guard payload.kind_ == "chatgpt" else {
          return SshRefused(
            "Only ChatGPT browser login is supported by the SSH callback flow",
          )
        }
        logins.start(request.epoch, payload.to_json())
      } else {
        let payload : @protocol.CodexAccountLoginCancelPayload = @json.from_json(
          request.params,
        )
        logins.cancel(request.epoch, payload.login_id)
      }
    } catch {
      error => return SshUnknown("\{error}")
    }
    guard self.ready_epoch == Some(request.epoch) else {
      return SshUnknown("SSH login response belongs to a retired connection")
    }
    return SshSuccess(value)
  }
  if request.method_ == @commands.codex_account_logout.name() &&
    self.logins is Some(logins) {
    logins.stop_active() catch {
      error => return SshUnknown("\{error}")
    }
  }
  self.request_direct(request)
}

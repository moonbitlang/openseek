///|
/// The direct/SSH catalog routes durable operations through the service-owned
/// admission pump. Connection-owned watchers stay scoped to the socket.
pub fn ApiState::direct_client(
  self : ApiState,
  controls : Array[@transport.RequestHandler],
) -> @transport.Client {
  let connection = self.new_connection()
  let logins = ClientLoginScope(id => {
    ignore(
      self.codex.call(method_="account/login/cancel", params={ "loginId": id }),
    )
  })
  let id = self.next_connection
  self.next_connection += 1
  let busy : () -> Bool = () => logins.has_active_work()
  let handlers : Array[@transport.RequestHandler] = endpoints(self, connection).map(endpoint => {
      name: endpoint.name(),
      invoke: params => {
        // Registration and admission do not suspend. Idle guards may be pruned;
        // the next request registers again before it can create any activity.
        self.upgrade_activity[id] = busy
        self.admission.invoke(endpoint.name(), params, () => {
          logins.invoke(endpoint.name(), params, () => endpoint.invoke(params))
        })
      },
    },
  )
  Client(
    controls + handlers,
    (emit, on_lag) => {
      let subscription = self.subscribe_with(
        offer=event => {
          logins.observe(event)
          emit(@transport.Notification::from_host(event))
        },
        on_lag=sub => {
          sub.close()
          on_lag()
        },
      )
      if self.manager.is_serving() {
        if !(emit(
            @transport.Notification::from_host(
              AgentConnected({ stage: Serving, }),
            ),
          ) catch {
            _ => false
          }) {
          subscription.close()
          on_lag()
        }
      }
      () => subscription.close()
    },
    (emit, progress) => {
      defer (if !busy() { self.upgrade_activity.remove(id) })
      defer @async.protect_from_cancel(() => {
        logins.close() catch {
          error =>
            @xlog.warn(category="codex") <?
              { "event": "connection_login_cancel_failed", "error": "\{error}" }
        }
      })
      connection.run(event => emit(@transport.Notification::from_host(event)), event => {
        progress(@transport.Notification::from_host(event))
      })
    },
  )
}

///|
pub fn ApiState::begin_drain(self : ApiState) -> Unit {
  self.admission.drain()
  self.schedules.stop_admission()
}

///|
pub fn ApiState::status(self : ApiState) -> String {
  self.admission.status().name()
}

///|
pub fn ApiState::has_active_work(self : ApiState) -> Bool {
  self.admission.pending() > 0 ||
  self.manager.has_active_work() ||
  self.schedules.has_active_work() ||
  self.codex.has_active_work() ||
  !self.hub.active_starts.is_empty()
}

///|
pub fn ApiState::require_recovery(self : ApiState) -> Unit {
  self.admission.require_recovery()
  self.schedules.stop_admission()
}

///|
/// The busy check and admission barrier share a single non-suspending turn.
/// Explicit stop/restart retain their separate drain-and-wait behavior.
pub fn ApiState::try_upgrade(self : ApiState) -> Bool {
  let mut connection_busy = false
  for id in self.upgrade_activity.keys().to_array() {
    if self.upgrade_activity.get(id) is Some(busy) && busy() {
      connection_busy = true
    } else {
      self.upgrade_activity.remove(id)
    }
  }
  guard self.status() == "ready" && !self.has_active_work() && !connection_busy else {
    return false
  }
  self.begin_drain()
  true
}

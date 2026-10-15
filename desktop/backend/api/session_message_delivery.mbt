///|
fn message_committed(document : @protocol.SessionDocument, id : String) -> Bool {
  document.events.map_or(false, events => {
    events.any(event => {
      event.item is User(user) && user.submission_id == Some(id)
    })
  })
}

///|
priv enum MessageDeliveryInput {
  Event(@protocol.Notification)
  Receipt(@engine.MessageReceipt)
  Resync
}

///|
/// Acknowledgement is a durable User item, not a successful write to stdin.
/// Subscribe before submission so even an immediate commit cannot be missed.
/// Submit once. Dropped or unwritten input is a delivery failure.
async fn ApiState::deliver_session_input(
  self : ApiState,
  session : String,
  text : String,
  id : String,
) -> Unit {
  @async.with_task_group(group => {
    let events : @async.Queue[MessageDeliveryInput] = Queue(kind=Blocking(64))
    let subscription = self.subscribe(
      events,
      map=notification => {
        match notification {
          SessionEvent(commit) if commit.session == session =>
            Some(Event(notification))
          AgentFinished(_) | AgentConnected(_) => Some(Event(notification))
          _ => None
        }
      },
      on_lag=_ => group.spawn_bg(no_wait=true, () => events.put(Resync)),
    )
    defer subscription.close()
    let loaded = @engine.load_session(self.manager, {
      session,
      workspace: None,
    })
    if message_committed(loaded.session, id) {
      return
    }
    guard loaded.session.events is Some(history) && !history.is_empty() else {
      fail("conversation \{session} no longer has saved history")
    }
    let submitted = @engine.submit_session_message(
      self.manager,
      self.sink(),
      session,
      text,
      id,
      result => group.spawn_bg(no_wait=true, () => events.put(Receipt(result))),
    )
    defer submitted.close()
    for ;; {
      match events.get() {
        Receipt(result) => {
          if result is Dropped {
            fail("message was not delivered: the engine dropped the input")
          }
          let loaded = @engine.load_session(self.manager, {
            session,
            workspace: None,
          })
          if message_committed(loaded.session, id) {
            return
          }
          fail(
            "engine settled input without a durable receipt; do not resend automatically",
          )
        }
        Resync => {
          subscription.resume_delivery()
          let loaded = @engine.load_session(self.manager, {
            session,
            workspace: None,
          })
          if message_committed(loaded.session, id) {
            return
          }
          if submitted.result() is Some(Dropped) {
            fail("message was not delivered: the engine dropped the input")
          }
          // A finished turn can still have a live engine draining the
          // exact steer receipt. Its observer also reports consumer exit.
          if submitted.result() is None &&
            (
              submitted.steering ||
              self.hub.active_starts.contains(submitted.run_id)
            ) {
            continue
          }
          fail(
            "delivery receipt stream lagged; delivery is unconfirmed, do not resend automatically",
          )
        }
        Event(notification) =>
          match notification {
            SessionEvent(commit) if commit.session == session =>
              if commit.event.item is User(user) &&
                user.submission_id == Some(id) {
                return
              }
            AgentFinished(finished) if submitted.run_id == finished.run_id => {
              let loaded = @engine.load_session(self.manager, {
                session,
                workspace: None,
              })
              if message_committed(loaded.session, id) {
                return
              }
              // Retirement can drop an unwritten prompt synchronously,
              // before its queued receipt wakeup reaches this inbox.
              if submitted.result() is Some(Dropped) {
                fail("message was not delivered: the engine dropped the input")
              }
              if !submitted.steering {
                fail(
                  "conversation ended before confirming delivery; do not resend automatically",
                )
              }
              // SteerDropped is allowed to trail Finished. The engine-owned
              // receipt resolves that tail, including unwritten commands/EOF.
            }
            AgentConnected(_) => {
              let loaded = @engine.load_session(self.manager, {
                session,
                workspace: None,
              })
              if message_committed(loaded.session, id) {
                return
              }
              fail("engine restarted before confirming delivery")
            }
            _ => ()
          }
      }
    }
  })
}

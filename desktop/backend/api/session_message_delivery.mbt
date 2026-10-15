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
  Receipt(attempt~ : Int32, @engine.MessageReceipt)
  Resync
}

///|
/// Acknowledgement is a durable User item, not a successful write to stdin.
/// Subscribe before submission so even an immediate commit cannot be missed.
/// Only a dropped steer or a definitely unwritten command permits retry.
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
          AgentEvent(event) if event.session == session =>
            Some(Event(notification))
          AgentFinished(_) | AgentConnected(_) => Some(Event(notification))
          _ => None
        }
      },
      on_lag=_ => group.spawn_bg(no_wait=true, () => events.put(Resync)),
    )
    defer subscription.close()
    // Each attempt owns its engine receipt observer. A late queued wakeup
    // from an earlier attempt must not resubmit the replacement a second time.
    async fn attempt_delivery(attempt : Int32) -> Bool {
      let loaded = @engine.load_session(self.manager, {
        session,
        workspace: None,
      })
      if message_committed(loaded.session, id) {
        return true
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
        result => {
          group.spawn_bg(no_wait=true, () => {
            events.put(Receipt(attempt~, result))
          })
        },
      )
      defer (if submitted is Some(submitted) { submitted.close() })
      for ;; {
        match events.get() {
          Receipt(attempt=owner, result) => {
            if owner != attempt {
              continue
            }
            if result is Dropped {
              return false
            }
            let loaded = @engine.load_session(self.manager, {
              session,
              workspace: None,
            })
            if message_committed(loaded.session, id) {
              return true
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
              return true
            }
            if submitted is Some(submitted) {
              if submitted.result() is Some(Dropped) {
                return false
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
                  return true
                }
              AgentEvent(event) if event.session == session =>
                // A compaction boundary can make the conversation ready again.
                if submitted is None {
                  return false
                }
              AgentFinished(finished) if submitted is Some(submitted) &&
                submitted.run_id == finished.run_id => {
                let loaded = @engine.load_session(self.manager, {
                  session,
                  workspace: None,
                })
                if message_committed(loaded.session, id) {
                  return true
                }
                // Retirement can drop an unwritten prompt synchronously,
                // before its queued receipt wakeup reaches this inbox.
                if submitted.result() is Some(Dropped) {
                  return false
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
                  return true
                }
                fail("engine restarted before confirming delivery")
              }
              _ => ()
            }
        }
      }
    }
    let mut attempt = 0
    while !attempt_delivery(attempt) {
      attempt += 1
    }
  })
}

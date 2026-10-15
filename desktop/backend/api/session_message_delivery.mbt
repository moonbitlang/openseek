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
  Resync
}

///|
/// Acknowledgement is a durable User item, not a successful write to stdin.
/// Subscribe before submission so even an immediate commit cannot be missed.
/// Only an explicit dropped steer permits a retry; an uncertain transport
/// failure must never become an automatic duplicate send.
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
      // The hub pauses this subscription before scheduling one marker.
      // This task must not keep a completed delivery alive if a receipt
      // already in the accepted prefix lets the reader return first.
      on_lag=_ => group.spawn_bg(no_wait=true, () => events.put(Resync)),
    )
    defer subscription.close()
    while true {
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
      )
      let mut dropped = false
      while true {
        let notification = match events.get() {
          Event(notification) => notification
          Resync => {
            // Resume future delivery before the durable snapshot yields.
            // There is no resend on an uncertain gap in the receipt stream.
            subscription.resume_delivery()
            let loaded = @engine.load_session(self.manager, {
              session,
              workspace: None,
            })
            if message_committed(loaded.session, id) {
              return
            }
            if submitted is Some(run_id) &&
              self.hub.active_starts.contains(run_id) {
              // The receiver is still working. Resync the durable history and
              // continue from the new stream; do not abandon a message
              // that it can still consume at its next step boundary.
              continue
            }
            fail(
              "delivery receipt stream lagged; delivery is unconfirmed, do not resend automatically",
            )
          }
        }
        match notification {
          SessionEvent(commit) if commit.session == session =>
            if commit.event.item is User(user) && user.submission_id == Some(id) {
              return
            }
          AgentEvent(event) if event.session == session => {
            if event.event is SteerDropped(submission_id=Some(receipt), ..) &&
              receipt == id {
              dropped = true
            }
            // Between-turn compaction has no active Started record. Any event
            // for this session may be the boundary that makes it ready again.
            if submitted is None {
              break
            }
          }
          AgentFinished(finished) if submitted == Some(finished.run_id) => {
            let loaded = @engine.load_session(self.manager, {
              session,
              workspace: None,
            })
            if message_committed(loaded.session, id) {
              return
            }
            if dropped {
              break
            }
            fail(
              "conversation ended before confirming delivery; do not resend automatically",
            )
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

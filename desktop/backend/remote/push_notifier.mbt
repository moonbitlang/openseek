// What the relay is told to push while this host is registered: the two
// moments the window raises a system banner for (frontend/
// system_notification.mbt), derived from the hub instead of the page, so a
// closed phone app hears about them too. The relay fans each `notify` frame
// out as Web Push (docs/plans/web-push.md).

///|
/// The window's banner length; the frame carries no more than it shows.
const PushTextMaxChars = 180

///|
/// The hub state the push triggers depend on, kept from the moment the
/// subscription was installed.
priv struct PushNotifier {
  // Runs in flight by run id, for the session their settlement names.
  // `agent.finished` carries no session.
  runs : Map[String, String]
  // Every approval in the latest snapshot, by `session` and id. Only an
  // approval missing from it is new; the snapshot is republished whole on
  // every change.
  mut known_approvals : Set[(String, String)]
}

///|
/// Start from what was already true when the subscription began: runs that
/// started before it can still settle, and approvals standing at that moment
/// were raised before this connection and are never announced.
fn PushNotifier::PushNotifier(seed : @protocol.RunsReply) -> PushNotifier {
  let runs = Map([])
  for started in seed.runs {
    if !started.session.is_empty() {
      runs[started.run_id] = started.session
    }
  }
  {
    runs,
    known_approvals: Set::from_iter(
      seed.approvals.iter().map(approval => (approval.session, approval.id)),
    ),
  }
}

///|
/// The notifications this subscription needs.
fn push_relevant(notification : @protocol.Notification) -> Bool {
  notification is (AgentStarted(_) | AgentFinished(_) | AgentApprovals(_))
}

///|
fn PushNotifier::observe(
  self : PushNotifier,
  notification : @protocol.Notification,
) -> Array[@tunnel.PushEvent] {
  match notification {
    // A start without a durable session has no conversation to open.
    AgentStarted(started) if !started.session.is_empty() => {
      self.runs[started.run_id] = started.session
      []
    }
    AgentFinished(finished) => {
      // A repeated settlement finds its run already gone: one push per run.
      guard self.runs.get(finished.run_id) is Some(session) else { return [] }
      self.runs.remove(finished.run_id)
      // Cancelling is the user's own action and stays quiet, as in the window.
      guard finished.status != "cancelled" else { return [] }
      let answer = finished.answer
        .map(push_text)
        .filter(answer => !answer.is_empty())
      [Finished(session~, status=finished.status, answer~)]
    }
    AgentApprovals(snapshot) => {
      let events : Array[@tunnel.PushEvent] = []
      for approval in snapshot.approvals {
        if !approval.answered &&
          !self.known_approvals.contains((approval.session, approval.id)) {
          events.push(
            Approval(
              session=approval.session,
              tool=approval.tool_name,
              detail=push_text(approval.detail),
            ),
          )
        }
      }
      self.known_approvals = Set::from_iter(
        snapshot.approvals
        .iter()
        .map(approval => (approval.session, approval.id)),
      )
      events
    }
    _ => []
  }
}

///|
/// Trim and cut to the banner length on a character boundary.
fn push_text(text : String) -> String {
  let out = StringBuilder()
  for index, ch in text.trim() {
    if index >= PushTextMaxChars {
      out.write_char('…')
      break
    }
    out.write_char(ch)
  }
  out.to_string()
}

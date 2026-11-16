///|
priv enum SuggestedSessionStart {
  Recorded
  Stopped
}

///|
/// The engine acknowledges admission before persistence. Subscribe first and
/// settle only on this prompt's durable User event, or on an ended/restarted
/// run followed by a final read of its saved history.
async fn ApiState::start_suggested_session(
  self : ApiState,
  payload : @protocol.StartPayload,
) -> Unit {
  let recorded : @async.Queue[SuggestedSessionStart] = Queue(kind=Blocking(1))
  let run : Ref[String?] = Ref(None)
  let subscription = self.subscribe(
    recorded,
    map=notification => {
      match notification {
        SessionEvent(commit) if commit.session == payload.session &&
          commit.event.item is User(user) &&
          user.submission_id == payload.submission_id => Some(Recorded)
        AgentStarted(started) if started.session == payload.session &&
          started.submission_id == payload.submission_id => {
          run.val = Some(started.run_id)
          None
        }
        AgentFinished(finished) if run.val == Some(finished.run_id) =>
          Some(Stopped)
        AgentConnected(_) if run.val is Some(_) => Some(Stopped)
        _ => None
      }
    },
    // Only the first terminal outcome matters; a full queue already holds it.
    on_lag=_ => (),
  )
  defer subscription.close()
  // A disconnected create request may have admitted the same first prompt.
  // Adopt its run before the read below, so a finish during that read is
  // queued for this waiter instead of allowing a second submission.
  for started in self.hub.active_starts.values() {
    if started.session == payload.session &&
      started.submission_id == payload.submission_id {
      run.val = Some(started.run_id)
      break
    }
  }
  if suggested_session_prompt_saved(payload) {
    return
  }
  if run.val is None {
    ignore(@engine.start_run(self.sink(), self.manager, payload))
  }
  if recorded.get() is Stopped {
    guard suggested_session_prompt_saved(payload) else {
      fail("the new conversation stopped before its first message was saved")
    }
  }
}

///|
/// An admitted engine can have a follower before its first record exists.
/// That expected absence means keep waiting; I/O and decode errors still
/// propagate instead of being mistaken for an unsent prompt.
async fn suggested_session_prompt_saved(
  payload : @protocol.StartPayload,
) -> Bool {
  guard payload.workspace is Some(workspace) else {
    fail("a suggested session requires its source workspace")
  }
  let root = @workspaces.store_root(
    @pathx.Absolute::parse_resource_path(workspace),
  )
  let document = @session_record.read_document(root, payload.session) catch {
    @session_record.Absent(_) => return false
    error => raise error
  }
  message_committed(document, payload.session)
}

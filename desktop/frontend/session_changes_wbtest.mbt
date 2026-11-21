///|
fn current_key(model : Model) -> @interop.ConversationKey {
  { channel: Local, session: model.active_session, }
}

///|
fn attached_pull_requests(
  numbers : Array[Int32],
) -> Result[@protocol.SessionArtifacts, String] {
  let artifacts : Array[Json] = numbers.map(number => {
    "type": "pull_request",
    "url": "https://github.com/moonbitlang/openseek/pull/\{number}",
  })
  Ok(
    @json.from_json({ "artifacts": Json::array(artifacts) }) catch {
      error => abort(error.to_string())
    },
  )
}

///|
test "showing the overview reads the attached changes of the conversation on screen" {
  let dispatch = test_dispatch()
  let model = test_model()
  let (_, shown) = update(dispatch, ToggleOverview, model)
  assert_true(shown.changes.conversation == Some(current_key(model)))
  assert_true(shown.changes.phase is Checking)
  // The answer is routed back into the changes card.
  let (_, answered) = update(
    dispatch,
    Changes(Listed(serial=shown.changes.serial, attached_pull_requests([7]))),
    shown,
  )
  assert_true(answered.changes.phase is Loaded([_]))
  // Hiding asks nothing and keeps the answer; showing again asks again.
  let (_, hidden) = update(dispatch, ToggleOverview, answered)
  assert_true(hidden.changes == answered.changes)
  let (_, again) = update(dispatch, ToggleOverview, hidden)
  assert_true(again.changes.phase is Reloading([_]))
  // The answer to the superseded question cannot replace the newer one.
  let (_, stale) = update(
    dispatch,
    Changes(Listed(serial=shown.changes.serial, attached_pull_requests([]))),
    again,
  )
  assert_true(stale.changes == again.changes)
}

///|
test "a saved change to the conversation on show reads its list again" {
  let dispatch = test_dispatch()
  let model = test_model()
  let current = current_key(model)
  guard device_msg(
      Local,
      SessionArtifactsChanged({ session: current.session, }),
    )
    is Some(ArtifactsChanged(session)) else {
    fail("the notification should reach the page as a change to read")
  }
  assert_eq(session, current.session)
  // Before the overview has shown there is nothing to keep current.
  let (_, untouched) = update_dev(dispatch, ArtifactsChanged(session), model)
  assert_true(untouched.changes == model.changes)
  let (_, shown) = update(dispatch, ToggleOverview, model)
  let (_, answered) = update(
    dispatch,
    Changes(Listed(serial=shown.changes.serial, attached_pull_requests([7]))),
    shown,
  )
  let (_, changed) = update_dev(dispatch, ArtifactsChanged(session), answered)
  assert_true(changed.changes.phase is Reloading([_]))
  assert_true(changed.changes.serial != answered.changes.serial)
  // Another session's list is not this overview's business.
  let (_, other) = update_dev(
    dispatch,
    ArtifactsChanged("another-session"),
    answered,
  )
  assert_true(other.changes == answered.changes)
}

///|
test "a reconnected device has the overview read its attached changes again" {
  let dispatch = test_dispatch()
  let (_, shown) = update(dispatch, ToggleOverview, test_model())
  let (_, answered) = update(
    dispatch,
    Changes(Listed(serial=shown.changes.serial, attached_pull_requests([7]))),
    shown,
  )
  // A change announced while the connection was down is not replayed.
  let (_, reconnected) = update_dev(dispatch, BridgeReady, answered)
  assert_true(reconnected.changes.phase is Reloading([_]))
  assert_true(reconnected.changes.serial != answered.changes.serial)
}

///|
test "the overview stays shown across conversations and while settings is open" {
  let dispatch = test_dispatch()
  let (_, shown) = update(dispatch, ToggleOverview, test_model())
  let second = empty_conversation(
    @interop.ChannelId::Local,
    "second-session",
    @interop.ChannelId::Local.test_project(),
  )
  let (_, switched) = update(dispatch, OpenSession(Local, "second-session"), {
    ..shown,
    conversations: [..shown.conversations, second],
  })
  assert_eq(switched.active_session, "second-session")
  assert_true(switched.overview_open)
  // The dialog preserves the underlying overview and its conversation.
  let (_, settings) = update(dispatch, OpenSetup, switched)
  assert_true(settings.overview_open)
  assert_true(
    settings.overview_conversation() == switched.overview_conversation(),
  )
}

///|
test "the stored overview choice is read back" {
  let (_, shown) = update(test_dispatch(), OverviewLoaded(true), test_model())
  assert_true(shown.overview_open)
  let (_, hidden) = update(test_dispatch(), OverviewLoaded(false), shown)
  assert_false(hidden.overview_open)
}

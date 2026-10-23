///|
fn deletion_state() -> State {
  let state = {
    ..State::empty(),
    user_id: Some("fixture"),
    epoch: 2,
    sessions: [
      {
        id: "a",
        title: Some("A"),
        updated_at: None,
        generating: false,
        archived: false,
      },
    ],
  }
  let (state, _, _) = update(
    state,
    Open("a"),
    _ => @cmd.none,
    token="fixture",
    navigation=0,
  )
  let request = state.conversations["a"].request
  let (state, _, _) = update(
    state,
    Loaded(2, "a", request, {
      session: native_document([]),
      messages: [],
      generating: false,
    }),
    _ => @cmd.none,
    token="fixture",
    navigation=0,
  )
  state
}

///|
test "deletion retires history and late list or poll responses" {
  let initial = deletion_state()
  let (pending, _, _) = update(
    initial,
    Delete("a"),
    _ => @cmd.none,
    token="fixture",
    navigation=0,
  )
  let request = pending.deletions["a"]
  assert_false(pending.can_delete("a"))
  let (removed, _, _) = update(
    pending,
    Deleted(2, "a", request),
    _ => @cmd.none,
    token="fixture",
    navigation=0,
  )
  assert_true(removed.sessions.is_empty())
  assert_true(removed.conversations.is_empty())
  assert_true(removed.retired == ["a"])
  assert_false(removed.needs_sign_in)
  let (listed, _, _) = update(
    removed,
    Listed(2, removed.list_request, initial.sessions),
    _ => @cmd.none,
    token="fixture",
    navigation=0,
  )
  assert_true(listed.sessions.is_empty())
  let history_request = initial.conversations["a"].request
  for
    message in [
      Loaded(2, "a", history_request, {
        session: native_document([]),
        messages: [],
        generating: true,
      }),
      Poll(2, "a", history_request),
      SendAccepted(2, "a", history_request),
      Open("a"),
    ] {
    let (late, _, _) = update(
      listed,
      message,
      _ => @cmd.none,
      token="fixture",
      navigation=0,
    )
    assert_true(late == listed)
  }
}

///|
test "delete replies belong to the request and account epoch" {
  let (pending, _, _) = update(
    deletion_state(),
    Delete("a"),
    _ => @cmd.none,
    token="fixture",
    navigation=0,
  )
  let request = pending.deletions["a"]
  for message in [Deleted(1, "a", request), Deleted(2, "a", request + 1)] {
    let (late, _, _) = update(
      pending,
      message,
      _ => @cmd.none,
      token="fixture",
      navigation=0,
    )
    assert_true(late == pending)
  }
  let (switched, _, _) = update(
    pending,
    AccountChanged(Some("other")),
    _ => @cmd.none,
    token="other",
    navigation=0,
  )
  let (late, _, _) = update(
    switched,
    Deleted(2, "a", request),
    _ => @cmd.none,
    token="other",
    navigation=0,
  )
  assert_true(late == switched)
}

///|
test "generation and sends block deletion and a pending delete blocks sends" {
  let state = deletion_state()
  for
    conversation in [
      { ..state.conversations["a"], sending: true, },
      { ..state.conversations["a"], generating: true, },
    ] {
    let state = state.replace("a", conversation)
    assert_false(state.can_delete("a"))
    let (unchanged, _, _) = update(
      state,
      Delete("a"),
      _ => @cmd.none,
      token="fixture",
      navigation=0,
    )
    assert_true(unchanged == state)
  }
  let (pending, _, _) = update(
    state,
    Delete("a"),
    _ => @cmd.none,
    token="fixture",
    navigation=0,
  )
  let (unchanged, _, _) = update(
    pending,
    Submit(@interop.Cloud(account="fixture", session="a"), {
      task: "do not send",
      images: [],
      mentions: [],
    }),
    _ => @cmd.none,
    token="fixture",
    navigation=0,
  )
  assert_true(unchanged == pending)
}

///|
test "delete failures preserve the conversation and only 401 expires credentials" {
  let (pending, _, _) = update(
    deletion_state(),
    Delete("a"),
    _ => @cmd.none,
    token="fixture",
    navigation=0,
  )
  let request = pending.deletions["a"]
  let errors : Array[Failure] = [Busy, Http(503), Unreachable]
  for error in errors {
    let (failed, _, _) = update(
      pending,
      DeleteFailed(2, "a", request, error),
      _ => @cmd.none,
      token="fixture",
      navigation=0,
    )
    assert_true(failed.sessions == pending.sessions)
    assert_true(failed.conversations == pending.conversations)
    assert_false(failed.needs_sign_in)
    assert_true(failed.can_delete("a"))
    assert_true(failed.notice is Some(_))
  }
  let (expired, _, _) = update(
    pending,
    DeleteFailed(2, "a", request, Unauthorized),
    _ => @cmd.none,
    token="fixture",
    navigation=0,
  )
  assert_true(expired.needs_sign_in)
}

///|
test "history 404 and authoritative list absence converge on retirement" {
  let state = deletion_state()
  let request = state.conversations["a"].request
  let (missing, _, _) = update(
    state,
    LoadFailed(2, "a", request, Http(404)),
    _ => @cmd.none,
    token="fixture",
    navigation=0,
  )
  assert_true(missing.retired == ["a"])
  assert_true(missing.conversations.is_empty())
  assert_false(missing.needs_sign_in)
  let (refreshed, _, _) = update(
    state,
    Listed(2, state.list_request, []),
    _ => @cmd.none,
    token="fixture",
    navigation=0,
  )
  assert_true(refreshed.retired == ["a"])
  let (failed, _, _) = update(
    state,
    LoadFailed(2, "a", request, Http(503)),
    _ => @cmd.none,
    token="fixture",
    navigation=0,
  )
  assert_true(failed.sessions == state.sessions)
  assert_false(failed.conversations.is_empty())
}

///|
test "completed history supersedes an earlier generating list row for deletion" {
  let initial = deletion_state()
  let state = {
    ..initial.replace("a", { ..initial.conversations["a"], generating: true, }),
    sessions: [{ ..initial.sessions[0], generating: true, }],
  }
  assert_false(state.can_delete("a"))
  let request = state.conversations["a"].request
  let (completed, _, _) = update(
    state,
    Loaded(2, "a", request, {
      session: native_document([]),
      messages: [],
      generating: false,
    }),
    _ => @cmd.none,
    token="fixture",
    navigation=0,
  )
  assert_true(completed.can_delete("a"))
}

///|
test "a newly accepted generating list disables deletion despite earlier idle history" {
  let state = deletion_state()
  assert_true(state.can_delete("a"))
  let (running, _, _) = update(
    state,
    Listed(2, state.list_request, [{ ..state.sessions[0], generating: true, }]),
    _ => @cmd.none,
    token="fixture",
    navigation=0,
  )
  assert_false(running.can_delete("a"))
}

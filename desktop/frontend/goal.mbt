///|
/// A goal command in flight, under a fixed id. The id only ever separates
/// this client's own sends from each other, so tests that never send twice
/// can share one.
fn test_goal_command(request : GoalRequest) -> GoalCommand {
  { id: "goal-1", request, since: 0, }
}

///|
test "the goal slash command opens the editor prefilled from the mirror" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    goal: Some({ text: "ship the feature", blocked: None, }),
    task: "/goal",
  })
  let (_, opened) = run_slash_command(dispatch, model, "goal")
  guard opened.active().goal_edit is Some(edit) else {
    fail("the editor should open")
  }
  inspect(edit.draft, content="ship the feature")
  // Whole-draft semantics, like /compact: accepting clears the typed command.
  inspect(opened.active().task, content="")
}

///|
test "submit holds the text until its marker lands" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    goal_edit: Some({ draft: "   ", }),
  })
  // A blank draft has nothing to set (the button is disabled; this also
  // catches Enter); goal mode stays open for the user to finish.
  let (_, still_open) = update(dispatch, SubmitGoal, model)
  assert_true(still_open.active().goal_edit is Some(_))
  let (_, edited) = update(dispatch, GoalDraftEdited("ship it"), still_open)
  guard edited.active().goal_edit is Some(edit) else { fail("editor lost") }
  inspect(edit.draft, content="ship it")
  let (_, submitted) = update(dispatch, SubmitGoal, edited)
  assert_true(submitted.active().goal_edit is None)
  // `agent.goal` returning is not persistence, so the text waits for the
  // durable marker rather than being dropped on the send.
  assert_true(
    submitted.active().goal_pending is Some({ request: Setting("ship it"), .. }),
  )
  // The mirror is untouched: only the durable `[goal]` commit moves it.
  assert_true(submitted.active().goal is None)
}

///|
test "only the matching set marker settles the pending text" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    goal_pending: Some(test_goal_command(Setting("ship the feature"))),
  })
  fn commit(model, sequence, content) {
    let (_, next) = update_dev(
      dispatch,
      SessionCommitted(
        session="desktop-test",
        sequence~,
        ts=None,
        item=@protocol.RuntimeNotice({ content, }),
        session_root=@interop.ChannelId::Local.test_store_root(),
      ),
      model,
    )
    next
  }

  // A marker proves the engine is committing, not that this command landed.
  // An earlier set from a second submit, and a block on the goal that still
  // stands, both leave the recovery copy alone — the append it belongs to
  // can still fail.
  let other_set = commit(model, 1, "[goal]\nan earlier goal")
  assert_true(
    other_set.active().goal_pending
    is Some({ request: Setting("ship the feature"), .. }),
  )
  let blocked = commit(other_set, 2, "[goal blocked]\nneeds a decision")
  assert_true(
    blocked.active().goal_pending
    is Some({ request: Setting("ship the feature"), .. }),
  )
  let cleared = commit(blocked, 3, "[goal cleared]")
  assert_true(
    cleared.active().goal_pending
    is Some({ request: Setting("ship the feature"), .. }),
  )
  // Its own set does settle it, and moves the mirror.
  let settled = commit(cleared, 4, "[goal]\nship the feature")
  assert_true(settled.active().goal_pending is None)
  assert_true(
    settled.active().goal is Some({ text: "ship the feature", blocked: None, }),
  )
}

///|
test "the row's Cancel leaves the edit and the prompt draft alone" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    task: "half-typed prompt",
    goal_edit: Some({ draft: "a goal being written", }),
  })
  // The row's ✕ and Escape are the same message: leave goal mode, send
  // nothing, and hand the composer back its prompt draft untouched.
  let (_, cancelled) = update(dispatch, CloseGoalEditor, model)
  assert_true(cancelled.active().goal_edit is None)
  inspect(cancelled.active().task, content="half-typed prompt")
  assert_true(cancelled.active().goal is None)
}

///|
test "clear sends from goal mode and from the standing row alike" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    goal_edit: Some({ draft: "", }),
  })
  let (_, cleared) = update(dispatch, ClearGoal, model)
  assert_true(cleared.active().goal_edit is None)
  // The row's ✕ clears with no editor open; the mirror stays untouched until
  // the durable tombstone commits.
  let standing = test_model().replace_conversation({
    ..test_conversation(),
    goal: Some({ text: "ship the feature", blocked: None, }),
  })
  let (_, from_row) = update(dispatch, ClearGoal, standing)
  assert_true(from_row.active().goal_edit is None)
  assert_true(from_row.active().goal is Some(_))
  // The clear is in flight, so the row stops offering Edit and ✕ — the goal
  // is still mirrored underneath it, and a second command sent over this one
  // only earns the host's `GoalPending` refusal.
  assert_true(from_row.active().goal_pending is Some({ request: Clearing, .. }))
}

///|
test "a clear waits for its tombstone, not for any goal marker" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    goal: Some({ text: "ship the feature", blocked: None, }),
    goal_pending: Some(test_goal_command(Clearing)),
  })
  fn commit(model, sequence, content) {
    let (_, next) = update_dev(
      dispatch,
      SessionCommitted(
        session="desktop-test",
        sequence~,
        ts=None,
        item=@protocol.RuntimeNotice({ content, }),
        session_root=@interop.ChannelId::Local.test_store_root(),
      ),
      model,
    )
    next
  }

  // Someone else's set, and a block on the goal this clear is removing,
  // both leave it in flight: neither is the tombstone it asked for.
  let other = commit(model, 1, "[goal]\nsomething else")
  assert_true(other.active().goal_pending is Some({ request: Clearing, .. }))
  let blocked = commit(other, 2, "[goal blocked]\nneeds a decision")
  assert_true(blocked.active().goal_pending is Some({ request: Clearing, .. }))
  // The tombstone settles it, and the mirror empties with it.
  let settled = commit(blocked, 3, "[goal cleared]")
  assert_true(settled.active().goal_pending is None)
  assert_true(settled.active().goal is None)
}

///|
test "each conversation owns its own goal edit" {
  let dispatch = test_dispatch()
  // An edit left open on one conversation while another is active. Both the
  // clear and a new edit act on what is on screen, and neither can reach the
  // draft waiting next door — the reason the draft lives on the conversation
  // rather than in one model-wide slot.
  let neighbour : Conversation = {
    ..empty_conversation(
      @interop.ChannelId::Local,
      "desktop-other",
      @interop.ChannelId::Local.test_project(),
    ),
    goal: Some({ text: "the visible goal", blocked: None, }),
  }
  let model = {
    ..test_model(),
    conversations: [
      {
        ..test_conversation(),
        goal_edit: Some({ draft: "an edit left open next door", }),
      },
      neighbour,
    ],
    active_session: "desktop-other",
  }
  for msg in [ClearGoal, OpenGoalEditor, CloseGoalEditor] {
    let (_, next) = update(dispatch, msg, model)
    guard next.find_conversation(@interop.ChannelId::Local, "desktop-test")
      is Some(hidden) else {
      fail("the neighbour should survive")
    }
    guard hidden.goal_edit is Some(edit) else {
      fail("a neighbour's edit should survive every goal message")
    }
    inspect(edit.draft, content="an edit left open next door")
  }
}

///|
test "goal marker commits write the mirror and render cards" {
  let dispatch = test_dispatch()
  let (_, set) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=1,
      ts=None,
      item=@protocol.RuntimeNotice({ content: "[goal]\nship the feature", }),
      session_root=@interop.ChannelId::Local.test_store_root(),
    ),
    test_model(),
  )
  guard set.active().goal is Some(goal) else {
    fail("the set marker should write the mirror")
  }
  inspect(goal.text, content="ship the feature")
  assert_true(goal.blocked is None)
  inspect(set.active().messages.length(), content="1")
  let (_, blocked) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=2,
      ts=None,
      item=@protocol.RuntimeNotice({
        content: "[goal blocked]\nneeds a decision",
      }),
      session_root=@interop.ChannelId::Local.test_store_root(),
    ),
    set,
  )
  guard blocked.active().goal is Some(goal) else {
    fail("a blocked goal keeps standing")
  }
  assert_true(goal.blocked is Some("needs a decision"))
  let (_, cleared) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=3,
      ts=None,
      item=@protocol.RuntimeNotice({ content: "[goal cleared]", }),
      session_root=@interop.ChannelId::Local.test_store_root(),
    ),
    blocked,
  )
  assert_true(cleared.active().goal is None)
  inspect(cleared.active().messages.length(), content="3")
}

///|
test "a rejected goal request reports it and hands the text back" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    goal_pending: Some(test_goal_command(Setting("ship the feature"))),
  })
  let (_, next) = update_dev(
    dispatch,
    GoalRejected(
      session="desktop-test",
      command="goal-1",
      draft=Some("ship the feature"),
      message="no engine",
    ),
    model,
  )
  inspect(next.notifications.length(), content="1")
  // Nothing durable will ever carry this text, so dropping it loses the
  // user's writing for good — a rejected prompt restores its draft too.
  guard next.active().goal_edit is Some(edit) else {
    fail("the goal text should come back")
  }
  inspect(edit.draft, content="ship the feature")
  // Nothing is still in flight once the rejection has settled.
  assert_true(next.active().goal_pending is None)
}

///|
test "a rejected clear has nothing to restore, and never steals goal mode" {
  let dispatch = test_dispatch()
  // A clear carries no draft.
  let (_, cleared) = update_dev(
    dispatch,
    GoalRejected(
      session="desktop-test",
      command="goal-1",
      draft=None,
      message="no engine",
    ),
    test_model(),
  )
  inspect(cleared.notifications.length(), content="1")
  assert_true(cleared.active().goal_edit is None)
  // A newer edit belongs to the user, not to this dead request.
  let editing = test_model().replace_conversation({
    ..test_conversation(),
    goal_edit: Some({ draft: "something newer", }),
  })
  let (_, kept) = update_dev(
    dispatch,
    GoalRejected(
      session="desktop-test",
      command="goal-1",
      draft=Some("the request that died"),
      message="no engine",
    ),
    editing,
  )
  guard kept.active().goal_edit is Some(edit) else { fail("editor lost") }
  inspect(edit.draft, content="something newer")
}

///|
test "the editor opens on the newest text, not on the retired one" {
  // Mid-flight, the mirror still holds what the set is replacing. Seeding
  // from it would silently revert the user's own sent text.
  let conv : Conversation = {
    ..test_conversation(),
    goal: Some({ text: "the old goal", blocked: None, }),
    goal_pending: Some(test_goal_command(Setting("the goal just sent"))),
  }
  inspect(conv.goal_draft_seed(), content="the goal just sent")
  inspect(
    { ..conv, goal_pending: Some(test_goal_command(Clearing)), }.goal_draft_seed(),
    content="",
  )
  inspect(
    { ..conv, goal_pending: None, }.goal_draft_seed(),
    content="the old goal",
  )
  let dispatch = test_dispatch()
  let (_, opened) = update(
    dispatch,
    OpenGoalEditor,
    test_model().replace_conversation(conv),
  )
  guard opened.active().goal_edit is Some(edit) else { fail("editor lost") }
  inspect(edit.draft, content="the goal just sent")
}

///|
test "a clear over an unconfirmed set waits for a goal to actually go away" {
  let dispatch = test_dispatch()
  // The row keeps its ✕ while a set is out, so this is reachable: the set has
  // no marker yet, and the mirror is still empty. Goallessness is also what a
  // record carries before anything is set, so reading it as the clear's own
  // result would retire the request on the next commit — and if the set then
  // lands durably and the clear's append fails, the goal the user just tried
  // to remove stands with nothing waiting for it.
  let model = test_model().replace_conversation({
    ..test_conversation(),
    goal_pending: Some(test_goal_command(Clearing)),
  })
  fn commit(model, sequence, content) {
    let (_, next) = update_dev(
      dispatch,
      SessionCommitted(
        session="desktop-test",
        sequence~,
        ts=None,
        item=@protocol.RuntimeNotice({ content, }),
        session_root=@interop.ChannelId::Local.test_store_root(),
      ),
      model,
    )
    next
  }

  let unrelated = commit(model, 1, "just some runtime notice")
  assert_true(
    unrelated.active().goal_pending is Some({ request: Clearing, .. }),
  )
  // The set it was sent over lands first; the clear is still outstanding.
  let landed = commit(unrelated, 2, "[goal]\nthe goal being removed")
  assert_true(landed.active().goal_pending is Some({ request: Clearing, .. }))
  assert_true(landed.active().goal is Some(_))
  // Only a goal actually going away is this clear's result.
  let settled = commit(landed, 3, "[goal cleared]")
  assert_true(settled.active().goal_pending is None)
  assert_true(settled.active().goal is None)
}

///|
test "a tombstone over an empty mirror still ends the clear" {
  let dispatch = test_dispatch()
  // The other side of that coin: the set never appended, the user hit ✕ to
  // escape, and the engine records the clear as the no-op it is. Nothing
  // stands before this commit and nothing stands after, so the transition
  // cannot vouch for it — but the record positively says so, and requiring a
  // transition here would leave the escape hatch itself waiting forever.
  let model = test_model().replace_conversation({
    ..test_conversation(),
    goal_pending: Some(test_goal_command(Clearing)),
  })
  let (_, settled) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=1,
      ts=None,
      item=@protocol.RuntimeNotice({ content: "[goal cleared]", }),
      session_root=@interop.ChannelId::Local.test_store_root(),
    ),
    model,
  )
  assert_true(settled.active().goal is None)
  assert_true(settled.active().goal_pending is None)
}

///|
test "re-asserting an unchanged goal waits for its own marker too" {
  let dispatch = test_dispatch()
  // Re-sending the same text is a real command, not a no-op: serve records a
  // fresh baseline beside every set marker and restarts the goal cadence from
  // it. The mirror already reading that text is therefore no evidence at all,
  // and treating it as evidence would let the next commit of any kind retire
  // the request with its recovery copy while its own append could still fail.
  let model = test_model().replace_conversation({
    ..test_conversation(),
    goal: Some({ text: "ship the feature", blocked: None, }),
    goal_pending: Some(test_goal_command(Setting("ship the feature"))),
  })
  fn commit(model, sequence, content) {
    let (_, next) = update_dev(
      dispatch,
      SessionCommitted(
        session="desktop-test",
        sequence~,
        ts=None,
        item=@protocol.RuntimeNotice({ content, }),
        session_root=@interop.ChannelId::Local.test_store_root(),
      ),
      model,
    )
    next
  }

  let unrelated = commit(model, 1, "just some runtime notice")
  assert_true(
    unrelated.active().goal_pending
    is Some({ request: Setting("ship the feature"), .. }),
  )
  // A reload after a missed notification is the case that has to work: the
  // reduced state reads exactly as it did before the request, so the snapshot
  // has to carry the marker itself. Above the request's frontier it answers;
  // at or below it, it is the record agreeing rather than answering.
  fn reload(model : Model, goal_markers) raise {
    let (_, next) = update_dev(
      dispatch,
      SessionRefreshed(
        goal=Some({ text: "ship the feature", blocked: None, }),
        goal_markers~,
        session="desktop-test",
        items=[],
        watermark=9,
        generation=1,
      ),
      {
        ..model,
        conversations: [{ ..model.active(), sync: test_reloading([]), }],
      },
    )
    next
  }

  assert_true(
    reload(unrelated, []).active().goal_pending
    is Some({ request: Setting("ship the feature"), .. }),
  )
  assert_true(
    reload(unrelated, [(0, GoalSet("ship the feature"))]).active().goal_pending
    is Some({ request: Setting("ship the feature"), .. }),
  )
  // Missed live, found by the reload — and no longer stuck forever.
  assert_true(
    reload(unrelated, [(1, GoalSet("ship the feature"))]).active().goal_pending
    is None,
  )
  // Its own marker arriving live says so outright too.
  let settled = commit(unrelated, 2, "[goal]\nship the feature")
  assert_true(settled.active().goal_pending is None)
}

///|
test "a set is recorded even when the record has moved on since" {
  let dispatch = test_dispatch()
  // Set, then blocked — a goal set into a live turn can be blocked by the
  // agent before the reload ever happens. Keeping only the newest goal-family
  // marker would hand the snapshot a `GoalBlocked` and nothing else, and the
  // set could never recognize its own result. What moved the goal on
  // afterwards is a different question from whether this one landed.
  let model = test_model().replace_conversation({
    ..test_conversation(),
    goal_pending: Some({
      id: "goal-1",
      request: Setting("ship the feature"),
      since: 1,
    }),
    sync: test_reloading([]),
  })
  let (_, settled) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=Some({ text: "ship the feature", blocked: Some("needs a decision"), }),
      goal_markers=[
        (2, GoalSet("ship the feature")),
        (3, GoalBlocked("needs a decision")),
      ],
      session="desktop-test",
      items=[],
      watermark=9,
      generation=1,
    ),
    model,
  )
  assert_true(settled.active().goal_pending is None)
  // The row goes on showing the goal as blocked; that is the mirror's job,
  // not the request's.
  assert_true(settled.active().goal is Some({ blocked: Some(_), .. }))
}

///|
test "re-asserting a blocked goal waits for its own marker" {
  let dispatch = test_dispatch()
  // Edit on a blocked goal seeds from the mirror, so resubmitting unchanged
  // is the ordinary way to re-assert one. The record already spells that
  // text, and a set clears the block — so matching on text alone would let
  // the goal being replaced stand in for its replacement, and the next
  // durable item of any kind would retire the request and its recovery copy.
  let model = test_model().replace_conversation({
    ..test_conversation(),
    goal: Some({ text: "ship the feature", blocked: Some("needs a decision"), }),
    goal_pending: Some(test_goal_command(Setting("ship the feature"))),
  })
  fn commit(model, sequence, content) {
    let (_, next) = update_dev(
      dispatch,
      SessionCommitted(
        session="desktop-test",
        sequence~,
        ts=None,
        item=@protocol.RuntimeNotice({ content, }),
        session_root=@interop.ChannelId::Local.test_store_root(),
      ),
      model,
    )
    next
  }

  let unrelated = commit(model, 1, "just some runtime notice")
  assert_true(
    unrelated.active().goal_pending
    is Some({ request: Setting("ship the feature"), .. }),
  )
  // Its own marker is what unblocks it, and that is the state it was waiting
  // for.
  let settled = commit(unrelated, 2, "[goal]\nship the feature")
  assert_true(settled.active().goal_pending is None)
  assert_true(
    settled.active().goal is Some({ text: "ship the feature", blocked: None, }),
  )
}

///|
test "archiving discards the goal draft with its conversation" {
  let dispatch = test_dispatch()
  let model = test_model()
    .replace_conversation({
      ..test_conversation(),
      task: "a prompt typed too",
      goal_edit: Some({ draft: "a goal still being written", }),
    })
    .with_dev(dev => {
      ..dev,
      sessions: [placed_archived_item("desktop-test")],
    })
  let (_, next) = update_dev(
    dispatch,
    SessionsChanged(
      change="archived",
      key={
        session: "desktop-test",
        workspace: @interop.ChannelId::Local.test_project(),
      },
      fresh_session=Some("desktop-restored"),
    ),
    model,
  )
  inspect(next.active_session, content="desktop-restored")
  assert_true(next.active().goal_edit is None)
  inspect(next.active().task, content="")
}

///|
test "archiving discards a goal that was sent but never confirmed" {
  let dispatch = test_dispatch()
  let model = test_model()
    .replace_conversation({
      ..test_conversation(),
      goal_pending: Some(test_goal_command(Setting("a goal still in flight"))),
    })
    .with_dev(dev => {
      ..dev,
      sessions: [placed_archived_item("desktop-test")],
    })
  let (_, next) = update_dev(
    dispatch,
    SessionsChanged(
      change="archived",
      key={
        session: "desktop-test",
        workspace: @interop.ChannelId::Local.test_project(),
      },
      fresh_session=Some("desktop-restored"),
    ),
    model,
  )
  assert_true(next.active().goal_edit is None)
  assert_true(next.active().goal_pending is None)
}

///|
test "archiving carries no goal the record already confirmed" {
  let dispatch = test_dispatch()
  // A standing goal belongs to the record that carries it. The replacement is
  // a different session with no goal, and re-seeding it as a draft would
  // invite setting it again on a conversation that never asked.
  let model = test_model()
    .replace_conversation({
      ..test_conversation(),
      goal: Some({ text: "the goal on record", blocked: None, }),
    })
    .with_dev(dev => {
      ..dev,
      sessions: [placed_archived_item("desktop-test")],
    })
  let (_, next) = update_dev(
    dispatch,
    SessionsChanged(
      change="archived",
      key={
        session: "desktop-test",
        workspace: @interop.ChannelId::Local.test_project(),
      },
      fresh_session=Some("desktop-restored"),
    ),
    model,
  )
  inspect(next.active().goal_edit is None, content="true")
}

///|
#warnings("-alert_unstable")
test "a kept goal draft is a conversation you can get back to" {
  // Retention without a row does not save the draft, it strands it: the
  // conversation lives on with no way to reach it again. Retention and the
  // sidebar therefore ask one predicate, not two.
  let fresh = empty_conversation(
    @interop.ChannelId::Local,
    "desktop-fresh",
    @interop.ChannelId::Local.test_project(),
  )
  assert_false(fresh.worth_keeping())
  // A blank editor is not writing: an untouched `/goal` still lets the husk go.
  assert_false({ ..fresh, goal_edit: Some({ draft: "   ", }), }.worth_keeping())
  for
    holding in [
      { ..fresh, goal_edit: Some({ draft: "a goal still being written", }), },
      { ..fresh, goal_pending: Some(test_goal_command(Setting("awaiting"))), },
    ] {
    assert_true(holding.worth_keeping())
    // On screen, with focus somewhere else — the case that decides whether
    // the draft is reachable at all.
    let model = {
      ..test_model(),
      conversations: [holding, test_conversation()],
      active_session: "desktop-test",
    }
    guard model.focused_device() is Some(dev) else { fail("no device") }
    let rows : Array[(RowStamp, @conversation.Input)] = []
    model.push_group_component_inputs(
      rows,
      dev,
      @interop.ChannelId::Local.test_project(),
      listed=_ => false,
      archived=_ => false,
    )
    assert_true(
      rows.iter().any(row => row.1.id().conversation() == "desktop-fresh"),
    )
  }
}

///|
test "the frontier a goal is sent from counts what is already buffered" {
  let dispatch = test_dispatch()
  // Submitting during a reload: commits above the watermark are already in
  // hand. A goal marker among them sits *below* what the user just asked for,
  // and against the watermark alone it would read as above it — confirming
  // the new request with the older record's answer, and discarding the
  // recovery copy if the new append then failed.
  let reloading : Conversation = {
    ..test_conversation(),
    watermark: 3,
    sync: Reloading(generation=1, attempt=1, reload_after_current=false, buffered=[
      {
        sequence: 7,
        ts: None,
        item: @protocol.RuntimeNotice({ content: "[goal]\nship the feature", }),
      },
    ]),
    goal_edit: Some({ draft: "ship the feature", }),
  }
  inspect(reloading.durable_frontier(), content="7")
  // A read that failed keeps its buffer, and `begin_transcript_reload` carries
  // it forward — so a marker held there is just as much already-in-hand.
  inspect(
    {
      ..reloading,
      sync: ReloadFailed(generation=1, buffered=[
        {
          sequence: 7,
          ts: None,
          item: @protocol.RuntimeNotice({ content: "[goal]\nship the feature", }),
        },
      ]),
    }.durable_frontier(),
    content="7",
  )
  let (_, sent) = update(
    dispatch,
    SubmitGoal,
    test_model().replace_conversation(reloading),
  )
  guard sent.active().goal_pending is Some(pending) else {
    fail("nothing sent")
  }
  inspect(pending.since, content="7")
}

///|
test "a request in flight is reason enough to re-read the record" {
  // An otherwise-empty conversation has nothing else worth reloading for, so
  // without this the reconnect that follows a lost reply would never ask the
  // record the one question the transport could not answer.
  let fresh = empty_conversation(
    @interop.ChannelId::Local,
    "desktop-fresh",
    @interop.ChannelId::Local.test_project(),
  )
  let model = test_model()
  assert_false(model.can_reload_transcript(fresh))
  assert_true(
    model.can_reload_transcript({
      ..fresh,
      goal_pending: Some(test_goal_command(Setting("ship the feature"))),
    }),
  )
  assert_true(
    model.can_reload_transcript({
      ..fresh,
      goal_pending: Some(test_goal_command(Clearing)),
    }),
  )
  // The reconnect's own load can race persistence and come back empty. The
  // session list arriving is later proof the record exists, and that retry
  // gates on the same predicate — so a pending goal earns it too.
  let dispatch = test_dispatch()
  let (_, empty) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[],
      watermark=0,
      generation=1,
    ),
    {
      ..test_model().replace_conversation({
        ..test_conversation(),
        goal_pending: Some(test_goal_command(Setting("ship the feature"))),
        sync: test_reloading([]),
      }),
      transcript_request_generation: 1,
    },
  )
  assert_true(empty.active().sync is Synced)
  assert_true(empty.active().goal_pending is Some(_))
  let (_, proved) = update(
    dispatch,
    sessions_loaded([
      {
        id: "desktop-test",
        title: Some("persisted"),
        workspace: @interop.ChannelId::Local.test_project(),
        workspace_name: "work",
        updated_at_ms: None,
      },
    ]),
    empty,
  )
  guard proved.active().sync is Reloading(generation=2, ..) else {
    fail("durable session-list proof did not retry the pending goal")
  }
}

///|
test "a dead request cannot retire the one that replaced it" {
  let dispatch = test_dispatch()
  // The row keeps its actions while a command is out, so a second send can go
  // over the first — and the obvious second send is a *retry*, the same text
  // again. Two retries are equal `GoalRequest` values, so only the id tells
  // them apart; without it the first one's refusal would drop the second,
  // whose marker would then arrive with nothing waiting for it.
  let model = test_model().replace_conversation({
    ..test_conversation(),
    goal_pending: Some({
      id: "goal-2",
      request: Setting("ship the feature"),
      since: 0,
    }),
  })
  fn reject(model, command) {
    let (_, next) = update_dev(
      dispatch,
      GoalRejected(
        session="desktop-test",
        command~,
        draft=Some("ship the feature"),
        message="a goal command is already in flight",
      ),
      model,
    )
    next
  }

  let stale = reject(model, "goal-1")
  inspect(stale.notifications.length(), content="1")
  assert_true(
    stale.active().goal_pending
    is Some({ id: "goal-2", request: Setting("ship the feature"), since: 0, }),
  )
  // Nor does the superseded send's text come back: the user resent it, so
  // restoring it would read as the send still in flight having failed.
  assert_true(stale.active().goal_edit is None)
  // Its own rejection does retire it, and hands its text back.
  let own = reject(model, "goal-2")
  assert_true(own.active().goal_pending is None)
  guard own.active().goal_edit is Some(edit) else { fail("the text is lost") }
  inspect(edit.draft, content="ship the feature")
}

///|
test "a failed durable append is reported, not inferred from" {
  let dispatch = test_dispatch()
  // The engine says the append did not happen. Nothing else ever will: an
  // idle-time append has no terminal event behind it, and the host drops this
  // one, so without reading it off the stream the goal waits on a commit that
  // is not coming and the user is told nothing.
  let model = test_model().replace_conversation({
    ..test_conversation(),
    goal_pending: Some(test_goal_command(Setting("ship the feature"))),
  })
  let (_, reported) = update_dev(
    dispatch,
    Engine(
      None,
      SessionAppendFailed("failed to append goal update: disk full"),
      session=Some("desktop-test"),
    ),
    model,
  )
  guard reported.notifications.last() is Some(toast) else {
    fail("the failure should be reported")
  }
  assert_true(toast.message.has_suffix("disk full"))
  // It names what failed, not which command asked for it, and the idle
  // appender is shared — so this may have been some other item and the goal's
  // own append may still land. The request keeps waiting; the goal row's own
  // text and actions are what the user recovers with.
  assert_true(
    reported.active().goal_pending
    is Some({ request: Setting("ship the feature"), .. }),
  )
}

///|
test "an undelivered reply goes quiet once its send has been settled" {
  let dispatch = test_dispatch()
  // The socket can die after the commit arrives and before the reply does.
  // "Delivery could not be confirmed" retires nothing, but it is still a
  // claim about the world, and by now the record has answered it.
  let model = test_model().replace_conversation({
    ..test_conversation(),
    goal_pending: Some({
      id: "goal-1",
      request: Setting("ship the feature"),
      since: 0,
    }),
  })
  let (_, settled) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=1,
      ts=None,
      item=@protocol.RuntimeNotice({ content: "[goal]\nship the feature", }),
      session_root=@interop.ChannelId::Local.test_store_root(),
    ),
    model,
  )
  assert_true(settled.active().goal_pending is None)
  fn undelivered(model, command) {
    let (_, next) = update_dev(
      dispatch,
      GoalUndelivered(
        session="desktop-test",
        command~,
        draft=Some("ship the feature"),
        message="bridge unavailable",
      ),
      model,
    )
    next
  }

  inspect(undelivered(settled, "goal-1").notifications.length(), content="0")
  // Nor for a send a newer one has replaced.
  let superseded = model.replace_conversation({
    ..model.active(),
    goal_pending: Some({
      id: "goal-2",
      request: Setting("something newer"),
      since: 0,
    }),
  })
  inspect(undelivered(superseded, "goal-1").notifications.length(), content="0")
  // Still in flight: still true, and still reported.
  inspect(undelivered(model, "goal-1").notifications.length(), content="1")
}

///|
test "a rejection that arrives after the record has spoken only reports" {
  let dispatch = test_dispatch()
  // The successor's marker settles the slot, and then the superseded send's
  // refusal turns up. There is no pending request left to compare against,
  // so a guard that only asks "is the pending one mine" reads this as its
  // own — and reopens an obsolete draft over a goal the record has already
  // confirmed.
  let model = test_model().replace_conversation({
    ..test_conversation(),
    goal_pending: Some({
      id: "goal-2",
      request: Setting("the goal that won"),
      since: 0,
    }),
  })
  let (_, settled) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=1,
      ts=None,
      item=@protocol.RuntimeNotice({ content: "[goal]\nthe goal that won", }),
      session_root=@interop.ChannelId::Local.test_store_root(),
    ),
    model,
  )
  assert_true(settled.active().goal_pending is None)
  let (_, late) = update_dev(
    dispatch,
    GoalRejected(
      session="desktop-test",
      command="goal-1",
      draft=Some("the goal that lost"),
      message="a goal command is already in flight",
    ),
    settled,
  )
  inspect(late.notifications.length(), content="1")
  assert_true(late.active().goal_edit is None)
  assert_true(
    late.active().goal is Some({ text: "the goal that won", blocked: None, }),
  )
}

///|
test "each goal send gets an identity of its own" {
  let dispatch = test_dispatch()
  // Two sends of the same text, back to back. They are equal requests, so an
  // id derived from the request would leave nothing to tell the second reply
  // from the first.
  let model = test_model().replace_conversation({
    ..test_conversation(),
    goal_edit: Some({ draft: "ship the feature", }),
  })
  let (_, first) = update(dispatch, SubmitGoal, model)
  guard first.active().goal_pending is Some(one) else { fail("nothing sent") }
  let (_, again) = update(
    dispatch,
    SubmitGoal,
    first.replace_conversation({
      ..first.active(),
      goal_edit: Some({ draft: "ship the feature", }),
    }),
  )
  guard again.active().goal_pending is Some(two) else { fail("nothing sent") }
  assert_true(one.request == two.request)
  assert_false(one.id == two.id)
  // A clear is more anonymous still — it carries nothing at all — so it needs
  // the id just as much.
  let (_, cleared) = update(dispatch, ClearGoal, again)
  guard cleared.active().goal_pending is Some(clear) else {
    fail("nothing sent")
  }
  assert_true(clear.request is Clearing)
  assert_false(clear.id == two.id)
}

///|
test "an unconfirmed delivery keeps waiting instead of handing the text back" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    goal_pending: Some(test_goal_command(Setting("ship the feature"))),
  })
  // The socket dropped; the host may have taken the command already. Saying
  // "rejected" here would reopen the editor over a goal the record can still
  // be about to carry, and the resend that invites races its own marker.
  let (_, next) = update_dev(
    dispatch,
    GoalUndelivered(
      session="desktop-test",
      command="goal-1",
      draft=Some("ship the feature"),
      message="bridge unavailable",
    ),
    model,
  )
  inspect(next.notifications.length(), content="1")
  assert_true(next.active().goal_edit is None)
  // The writing is not lost: the request still in flight carries it, which is
  // what the goal row shows and what reopening the editor seeds from.
  assert_true(
    next.active().goal_pending
    is Some({ request: Setting("ship the feature"), .. }),
  )
  inspect(next.active().goal_draft_seed(), content="ship the feature")
}

///|
test "a reload settles a request the transport never answered" {
  let dispatch = test_dispatch()
  // Sent, unanswered, and then the connection came back. The snapshot is a
  // complete durable read: it can say what the reply could not — but only by
  // showing the marker that recorded it, above the frontier the request was
  // sent from. The reduced state alone would agree with a record that had
  // said the same thing all along.
  let model = test_model().replace_conversation({
    ..test_conversation(),
    goal_pending: Some({
      id: "goal-1",
      request: Setting("ship the feature"),
      since: 4,
    }),
    sync: test_reloading([]),
  })
  fn refresh(model, goal, goal_markers) {
    let (_, next) = update_dev(
      dispatch,
      SessionRefreshed(
        goal~,
        goal_markers~,
        session="desktop-test",
        items=[],
        watermark=9,
        generation=1,
      ),
      model,
    )
    next
  }

  fn reloading(model : Model) raise {
    {
      ..model,
      conversations: [{ ..model.active(), sync: test_reloading([]), }],
    }
  }

  // A record that does not carry it settles nothing: the append may still be
  // queued behind this read.
  let absent = refresh(model, None, [])
  assert_true(
    absent.active().goal_pending
    is Some({ request: Setting("ship the feature"), .. }),
  )
  // Nor does the goal merely standing, when the marker that put it there is
  // older than the request — that is the record agreeing, not answering.
  let older = refresh(
    reloading(absent),
    Some({ text: "ship the feature", blocked: None, }),
    [(4, GoalSet("ship the feature"))],
  )
  assert_true(
    older.active().goal_pending
    is Some({ request: Setting("ship the feature"), .. }),
  )
  let landed = refresh(
    reloading(older),
    Some({ text: "ship the feature", blocked: None, }),
    [(5, GoalSet("ship the feature"))],
  )
  assert_true(landed.active().goal_pending is None)
  assert_true(landed.active().goal is Some(_))
}

///|
test "a goal on an unbound worktree conversation creates the worktree first" {
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  // Worktree mode chosen, nothing started: the goal has to establish the
  // environment, or the engine spawns in the workspace root and the goal's
  // own durable card retires the mode before the first prompt runs.
  let unbound : Conversation = {
    ..test_conversation(),
    workspace: Project(root=workspace),
    worktree_mode: true,
  }
  assert_true(unbound.goal_creates_worktree() is Some(_))
  // Already bound: placement is settled, so the goal goes straight out.
  assert_true(
    { ..unbound, workspace: Worktree(project=workspace, name="wt-1"), }.goal_creates_worktree()
    is None,
  )
  // Local mode is a deliberate choice to run in the workspace itself.
  assert_true(
    { ..unbound, worktree_mode: false, }.goal_creates_worktree() is None,
  )
  // A conversation that has begun cannot still be waiting for placement.
  assert_true(
    {
      ..unbound,
      messages: [{ kind: User("already talking"), ts: None, sequence: None, }],
    }.goal_creates_worktree()
    is None,
  )
}

///|
test "a fresh conversation survives on its goal draft alone" {
  // `/goal` moves the text out of `task`, so retention must count the goal
  // halves — otherwise activating a neighbour prunes the conversation and
  // takes the only copy of the draft with it.
  let fresh = empty_conversation(
    @interop.ChannelId::Local,
    "desktop-fresh",
    @interop.ChannelId::Local.test_project(),
  )
  assert_true(fresh.draft_empty())
  assert_false(
    { ..fresh, goal_edit: Some({ draft: "still writing", }), }.draft_empty(),
  )
  assert_false(
    {
      ..fresh,
      goal_pending: Some(test_goal_command(Setting("awaiting its marker"))),
    }.draft_empty(),
  )
  // A blank editor is not a draft: an untouched `/goal` still lets the husk go.
  assert_true({ ..fresh, goal_edit: Some({ draft: "   ", }), }.draft_empty())
  let model = {
    ..test_model(),
    conversations: [
      { ..fresh, goal_edit: Some({ draft: "a goal still being written", }), },
      empty_conversation(
        @interop.ChannelId::Local,
        "desktop-other",
        @interop.ChannelId::Local.test_project(),
      ),
    ],
    active_session: "desktop-fresh",
  }
  let switched = model.activate(
    @interop.ChannelId::Local,
    "desktop-other",
    @interop.ChannelId::Local.test_project(),
  )
  assert_true(
    switched.find_conversation(@interop.ChannelId::Local, "desktop-fresh")
    is Some(_),
  )
}

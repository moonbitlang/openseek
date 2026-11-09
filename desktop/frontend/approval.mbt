///|
/// Host message approvals outlive a turn. Restore the next outstanding card
/// after lifecycle transitions clear an engine-owned question. Engine questions
/// have priority, since their tool is blocked until the user answers.
fn Model::restore_message_approvals(self : Model) -> Model {
  if !self.devices.any(device => {
      device.approval_snapshot.map_or(false, snapshot => {
        snapshot.approvals.any(item => item.approval.run_id is None)
      })
    }) &&
    !self.conversations.any(conv => {
      conv.pending_approval is Some({ run_id: None, .. })
    }) {
    return self
  }
  {
    ..self,
    conversations: self.conversations.map(conv => {
      if conv.pending_approval is Some({ run_id: Some(_), .. }) {
        return conv
      }
      guard self.device_state(conv.device) is Some(device) &&
        device.approval_snapshot is Some(snapshot) else {
        return conv
      }
      let pending = snapshot.approvals
        .iter()
        .find_first(item => {
          item.session == conv.session_id && item.approval.run_id is None
        })
        .map(item => {
          let answered_here = conv.pending_approval.map_or(false, previous => {
            previous.id == item.approval.id && previous.answered
          })
          {
            ..item.approval,
            answered: item.approval.answered || answered_here,
          }
        })
      { ..conv, pending_approval: pending, }
    }),
  }
}

///|
test "replayed write approvals decode content and preserve unfamiliar bodies" {
  let model = running_model()
  let cases = [
    (
      "write", "{\"path\":\"a.mbt\",\"content\":\"fn main {\\n  1\\n}\\n\"}", "fn main {\n  1\n}\n",
    ),
    ("write", "{\"content\":\"\"}", ""),
    ("write", "{\"content\":null}", "{\"content\":null}"),
    ("write", "malformed {", "malformed {"),
    ("mbtx", "fn main {\n  1\n}\n", "fn main {\n  1\n}\n"),
  ]
  let mut current = model
  for index, (tool_name, body, expected) in cases {
    let approvals = recover_approvals([
      {
        id: "approval-\{index}",
        session: "desktop-test",
        run_id: Some("r7"),
        tool_name,
        detail: "Inspect operation",
        body: Some(body),
        answered: false,
      },
    ])
    let reply = if index == 0 {
      RunsLoaded(
        approval_generation=1,
        runs=[],
        settled=[],
        approvals~,
        live=["r7"],
        frontier=model.run_snapshot_frontier(Local),
        connection_generation=0,
      )
    } else {
      ApprovalsChanged({ generation: index + 1, approvals, })
    }
    let (_, next) = update_dev(test_dispatch(), reply, current)
    assert_true(
      next.active().pending_approval is Some({ body: Some(text), .. }) &&
      text == expected,
    )
    assert_eq(approvals[0].approval.body, Some(expected))
    current = next
  }
  assert_true(model.active().pending_approval is None)
}

///|
test "running approvals precede message approvals and repeated snapshots do not duplicate them" {
  let model = running_model()
  let message : RecoveredApproval = {
    session: "desktop-test",
    approval: {
      id: "message",
      run_id: None,
      tool_name: "session.send",
      detail: "target-chat",
      body: Some("Exact message"),
      answered: false,
    },
  }
  let engine : RecoveredApproval = {
    session: "desktop-test",
    approval: {
      id: "engine",
      run_id: Some("r7"),
      tool_name: "mbtx",
      detail: "Run command",
      body: Some("command"),
      answered: false,
    },
  }
  let snapshot = ApprovalsChanged({
    generation: 1,
    approvals: [engine, message],
  })
  let (_, asked) = update_dev(test_dispatch(), snapshot, model)
  assert_true(asked.active().pending_approval == Some(engine.approval))
  let (_, repeated) = update_dev(test_dispatch(), snapshot, asked)
  assert_true(repeated.active().pending_approval == Some(engine.approval))
  assert_true(repeated.dev().approval_snapshot == asked.dev().approval_snapshot)
  assert_eq(repeated.notification_seq, asked.notification_seq)
  let (_, advanced) = update_dev(
    test_dispatch(),
    ApprovalsChanged({ generation: 2, approvals: [message], }),
    repeated,
  )
  assert_true(advanced.active().pending_approval == Some(message.approval))
  assert_true(advanced.active().run == model.active().run)
}

///|
test "delivery feedback errors preserve the active and idle sender behind another conversation" {
  for running in [false, true] {
    let initial = if running { running_model() } else { test_model() }
    let model = initial.replace_conversation({
      ..initial.active(),
      messages: [
        {
          kind: User(content=Content([Text("The sender's saved request")])),
          sequence: Some(1),
          ts: None,
        },
      ],
      watermark: 1,
    })
    let source = model.active()
    let selected = model.activate(Local, "desktop-other", source.project())
    let selected = selected.replace_conversation({
      ..selected.active(),
      task: "Unrelated draft",
    })
    let (_, reported) = update_dev(
      test_dispatch(),
      Engine(
        None,
        @wire.SessionError(
          error="Could not deliver message result: the sender is unavailable",
        ),
        session=source.session_id,
      ),
      selected,
    )
    assert_eq(reported.active_session, "desktop-other")
    assert_eq(reported.active().task, "Unrelated draft")
    assert_true(reported.active().run == selected.active().run)
    assert_true(
      reported.find_conversation(Local, source.session_id) is Some(sender) &&
      sender.run == source.run,
    )
    assert_true(
      reported.notifications.last() is Some({ message, .. }) &&
      message ==
      "the engine could not save an item to this session: Could not deliver message result: the sender is unavailable",
    )
    let returned = reported.activate(Local, source.session_id, source.project())
    assert_eq(returned.active().is_running(), running)
    assert_true(returned.active().run == source.run)
  }
}

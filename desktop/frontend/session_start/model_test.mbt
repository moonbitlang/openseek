///|
fn source(
  session~ : String = "source",
  workspace~ : String = "/work/project",
  archived~ : Bool = false,
) -> @session_start.Source {
  { session, workspace: Some(workspace), archived, }
}

///|
fn proposal(status~ : String = "pending") -> @protocol.SessionStartProposal {
  {
    id: "proposal-id",
    request_id: "request",
    title: "Extract focus helper",
    task: "Share the focus helper between views.",
    workspace: "/work/project",
    model: None,
    thinking: None,
    max_steps: None,
    workspace_mode: "local",
    status,
    target_session: if status == "started" {
      Some("target")
    } else {
      None
    },
    error: None,
  }
}

///|
fn snapshot(
  generation~ : Int32 = 1,
  status~ : String = "pending",
  session~ : String = "source",
) -> @session_start.Msg {
  Snapshot({
    session,
    workspace: Some("/work/project"),
    archived: Some(false),
    generation,
    proposals: [proposal(status~)],
  })
}

///|
fn apply(
  model : @session_start.Model,
  message : @session_start.Msg,
) -> @session_start.Model raise {
  let emit : @cmd.Emit[@session_start.Msg] = Emit(_ => @cmd.none)
  let (_, once) = model.update(message, Local, emit)
  let (_, twice) = model.update(message, Local, emit)
  assert_eq(once, twice)
  once
}

///|
test "session suggestion actions are pure and do not mutate earlier snapshots" {
  let empty = @session_start.Model()
  let pending = apply(empty, snapshot())
  assert_eq(empty.cards(source()), [])
  assert_eq(pending.cards(source()).length(), 1)
  let actions : Array[@session_start.Action] = [
    ToggleOptions,
    ToggleModel,
    ToggleWorkspace,
    CloseMenu,
    ModelChanged("deepseek-flash"),
    WorkspaceChanged("worktree"),
    Decide("start"),
    Decide("here"),
    Decide("dismiss"),
    Open,
  ]
  for action in actions {
    let message = @session_start.Interact(
      source=source(),
      request="request",
      action,
    )
    let next = apply(pending, message)
    if action is Decide(_) {
      assert_eq(apply(next, message), next)
      assert_eq(
        apply(
          next,
          Interact(source=source(), request="request", ModelChanged("glm-5.3")),
        ),
        next,
      )
    }
    assert_eq(apply(empty, message), empty)
    assert_eq(pending.cards(source())[0].proposal, proposal())
  }
  assert_eq(
    apply(
      pending,
      Interact(source=source(session="other"), request="request", ToggleOptions),
    ),
    pending,
  )
  assert_eq(
    apply(pending, Interact(source=source(), request="missing", ToggleOptions)),
    pending,
  )
  assert_eq(
    apply(
      pending,
      Interact(source=source(), request="request", WorkspaceChanged("invalid")),
    ),
    pending,
  )
  assert_eq(
    apply(
      pending,
      Interact(source=source(), request="request", Decide("invalid")),
    ),
    pending,
  )
}

///|
test "Here source configuration is pure and keeps proposed launch settings separate" {
  let proposed = {
    ..proposal(),
    model: Some("glm-5.3"),
    workspace_mode: "worktree",
  }
  let pending = apply(
    @session_start.Model(),
    Snapshot({
      session: "source",
      workspace: Some("/work/project"),
      archived: Some(false),
      generation: 1,
      proposals: [proposed],
    }),
  )
  let here_options : @protocol.SessionStartHereOptions = {
    model: Some("deepseek-flash"),
    thinking: Some(ThinkingHigh),
    approval: Some(ApprovalReview),
    max_steps: Some(1000),
    followup_behavior: "queue",
  }
  let emit : @cmd.Emit[@session_start.Msg] = Emit(_ => @cmd.none)
  let message = @session_start.Interact(
    source=source(),
    request="request",
    Decide("here"),
  )
  let (_, once) = pending.update(message, Local, emit, here_options~)
  let (_, twice) = pending.update(message, Local, emit, here_options~)
  assert_eq(once, twice)
  assert_false(once == pending)
  assert_eq(once.cards(source())[0].proposal, proposed)
  assert_eq(pending.cards(source())[0].proposal, proposed)
}

///|
test "started and dismissed suggestions survive old replies and late failures" {
  let empty = @session_start.Model()
  let pending = apply(empty, snapshot())
  let started = apply(pending, snapshot(generation=3, status="started"))
  assert_eq(apply(started, snapshot(generation=2)), started)
  assert_eq(
    apply(
      started,
      Failed(
        source=source(),
        request="request",
        attempt=1,
        error="late failure",
      ),
    ),
    started,
  )
  for status in ["started", "here", "dismissed", "starting"] {
    let settled = apply(pending, snapshot(generation=2, status~))
    assert_eq(
      apply(
        settled,
        Interact(source=source(), request="request", Decide("start")),
      ),
      settled,
    )
    assert_eq(
      settled.cards(source())[0].is_visible(),
      status != "here" && status != "dismissed",
    )
  }
  let separate = apply(started, snapshot(generation=1, session="other"))
  assert_eq(separate.cards(source()), started.cards(source()))
  assert_eq(separate.cards(source(session="other")).length(), 1)
}

///|
test "snapshot generations and late read failures belong to their exact source store" {
  let archived_a = source(workspace="/project-a", archived=true)
  let archived_b = source(workspace="/project-b", archived=true)
  let live_a = source(workspace="/project-a")
  let proposal_a = { ..proposal(status="started"), id: "a", }
  let proposal_b = { ..proposal(status="started"), id: "b", }
  let mut model = @session_start.Model()
  for
    (scope, generation, suggestion) in [
      (archived_a, 5, proposal_a),
      (archived_b, 2, proposal_b),
      (live_a, 20, proposal()),
    ] {
    model = apply(
      model,
      Snapshot({
        session: scope.session,
        workspace: scope.workspace,
        archived: Some(scope.archived),
        generation,
        proposals: [suggestion],
      }),
    )
  }
  assert_eq(model.cards(archived_a)[0].proposal.id, "a")
  assert_eq(model.cards(archived_b)[0].proposal.id, "b")
  assert_eq(model.cards(live_a)[0].proposal.id, "proposal-id")
  let before_b = model.cards(archived_b)
  let late_a = apply(
    model,
    Snapshot({
      session: archived_a.session,
      workspace: archived_a.workspace,
      archived: Some(true),
      generation: 6,
      proposals: [proposal_a],
    }),
  )
  assert_eq(late_a.cards(archived_b), before_b)
  let failed_a = apply(
    late_a,
    LoadFailed(source=archived_a, error="Old store read failed"),
  )
  assert_eq(failed_a.load_error(archived_b), None)
  assert_eq(failed_a.load_error(archived_a), Some("Old store read failed"))
  assert_eq(failed_a.cards(archived_b), before_b)
  assert_eq(
    apply(
      model,
      Interact(source=archived_b, request="request", Decide("start")),
    ),
    model,
  )
}

///|
test "decision failures cannot settle a same-ID request from another workspace" {
  let a = source(workspace="/project-a")
  let b = source(workspace="/project-b")
  let mut model = @session_start.Model()
  for scope in [a, b] {
    model = apply(
      model,
      Snapshot({
        session: scope.session,
        workspace: scope.workspace,
        archived: Some(false),
        generation: 1,
        proposals: [proposal()],
      }),
    )
    model = apply(
      model,
      Interact(source=scope, request="request", Decide("start")),
    )
  }
  let waiting_b = model.cards(b)
  let failed_a = apply(
    model,
    Failed(
      source=a,
      request="request",
      attempt=1,
      error="Project A unavailable",
    ),
  )
  assert_eq(failed_a.cards(b), waiting_b)
  assert_false(failed_a.cards(a) == model.cards(a))
}

///|
test "retry options survive equivalent failed snapshots and list failures are recoverable" {
  let empty = @session_start.Model()
  let failed = apply(empty, snapshot(status="failed"))
  let edited = apply(
    failed,
    Interact(source=source(), request="request", ModelChanged("glm-5.3")),
  )
  assert_eq(apply(edited, snapshot(status="failed")), edited)
  let offline = apply(
    empty,
    LoadFailed(source=source(), error="Host unavailable"),
  )
  assert_eq(offline.load_error(source()), Some("Host unavailable"))
  assert_eq(apply(offline, Retry(source())), offline)
  let recovered = apply(offline, snapshot())
  assert_eq(recovered.load_error(source()), None)
  assert_eq(recovered.cards(source()).length(), 1)
  let sending = apply(
    recovered,
    Interact(source=source(), request="request", Decide("start")),
  )
  let failed = apply(
    sending,
    Failed(source=source(), request="request", attempt=1, error="Offline"),
  )
  assert_false(failed == sending)
  let retrying = apply(
    failed,
    Interact(source=source(), request="request", Decide("start")),
  )
  assert_eq(
    apply(
      retrying,
      Failed(source=source(), request="request", attempt=1, error="Old failure"),
    ),
    retrying,
  )
  assert_false(
    apply(
      retrying,
      Failed(source=source(), request="request", attempt=2, error="New failure"),
    ) ==
    retrying,
  )
}

///|
test "select menus close on shell dismissal without discarding options" {
  let pending = apply(@session_start.Model(), snapshot())
  let opened = apply(
    pending,
    Interact(source=source(), request="request", ToggleModel),
  )
  assert_true(opened.has_open_menu())
  assert_false(pending.has_open_menu())
  let closed = apply(opened, CloseMenus)
  assert_false(closed.has_open_menu())
  assert_true(closed.cards(source())[0].options_open())
  assert_eq(closed.close_menus(), closed)
  let toggled = apply(
    opened,
    Interact(source=source(), request="request", ToggleModel),
  )
  assert_false(toggled.has_open_menu())
}

///|
test "reconnect releases undelivered decisions while retaining selected launch options" {
  let pending = apply(@session_start.Model(), snapshot())
  let edited = apply(
    pending,
    Interact(source=source(), request="request", ModelChanged("glm-5.3")),
  )
  let sending = apply(
    edited,
    Interact(source=source(), request="request", Decide("start")),
  )
  let reconnected = sending.reconnecting()
  assert_eq(reconnected, sending.reconnecting())
  assert_eq(apply(reconnected, snapshot()), reconnected)
  let retried = apply(
    reconnected,
    Interact(source=source(), request="request", Decide("start")),
  )
  assert_false(retried == reconnected)
  assert_false(retried == sending)
  let settled = apply(sending, snapshot(generation=2, status="started"))
  assert_eq(settled.reconnecting(), settled)
  assert_eq(apply(settled.reconnecting(), snapshot()), settled)
}

///|
test "folded cards expose only the open action and pending cards expose the approval actions" {
  for status in ["pending", "started", "here", "dismissed"] {
    let model = apply(@session_start.Model(), snapshot(status~))
    let requested : Array[@session_start.Msg] = []
    let emit : @cmd.Emit[@session_start.Msg] = Emit(message => {
      requested.push(message)
      @cmd.none
    })
    ignore(model.cards(source())[0].render(English, [], true, emit))
    let start = @session_start.Interact(
      source=source(),
      request="request",
      Decide("start"),
    )
    let open = @session_start.Interact(source=source(), request="request", Open)
    assert_eq(requested.contains(start), status == "pending")
    assert_eq(requested.contains(open), status == "started")
    if status == "here" || status == "dismissed" {
      assert_eq(requested, [])
    }
  }
}

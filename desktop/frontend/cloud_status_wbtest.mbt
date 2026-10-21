///|
fn Model::with_status_conversation(
  self : Model,
  change : (@cloud.Conversation) -> @cloud.Conversation,
) -> Model {
  let conversations = self.cloud.conversations.copy()
  conversations["cloud-a"] = change(conversations["cloud-a"])
  { ..self, cloud: { ..self.cloud, conversations, }, }
}

///|
test "Cloud status readiness ignores Local bridge and provider settings" {
  let cloud = integrated_cloud_model().with_dev(dev => {
    ..dev,
    bridge: BridgeLost("offline"),
  })
  assert_true(cloud.cloud_display_status() is Some(Ready))
  assert_true(cloud.display_status() is Unavailable("offline"))
  assert_true({ ..cloud, account: None, }.cloud_display_status() is None)
  assert_true(
    { ..cloud, cloud: { ..cloud.cloud, user_id: Some("another-account"), }, }.cloud_display_status()
    is None,
  )
  let host_model = test_model()
  assert_true(host_model.display_status() is Ready)
  assert_true(
    { ..host_model, deepseek_key_saved: false, }.display_status()
    is ApiKeyRequired,
  )
}

///|
test "Cloud status covers draft creation, loading, failure and archived read-only" {
  let model = integrated_cloud_model()
  let (_, draft) = update(test_dispatch(), CloudAction(@cloud.Create), model)
  assert_true(draft.cloud_display_status() is Some(Ready))
  assert_true(
    submit_blank_cloud(draft).cloud_display_status() is Some(Starting),
  )
  let loading = model.with_status_conversation(conv => {
    ..conv,
    loading: true,
  })
  assert_true(loading.cloud_display_status() is Some(Loading))
  let failed = loading.with_status_conversation(conv => {
    ..conv,
    loading: false,
    history_required: true,
    notice: Some("unreachable"),
  })
  assert_true(failed.cloud_display_status() is Some(Errored))
  let archived = {
    ..model,
    cloud: {
      ..model.cloud,
      sessions: model.cloud.sessions.map(session => {
        ..session,
        archived: true,
      }),
    },
  }
  let status = archived.cloud_display_status().unwrap()
  assert_true(status is ReadOnly)
  assert_eq(status.label(), "Archived conversation · Read only")
  assert_true(status.kind() is Neutral)
  assert_eq(
    Status::Loading.label(locale=SimplifiedChinese),
    "正在加载对话…",
  )
}

///|
test "Cloud status reports admission and the existing engine step" {
  let model = integrated_cloud_model()
  let (_, sending) = update(
    test_dispatch(),
    ComposerAction(
      @composer.DraftSubmitted(identity=model.composer_input().identity, draft={
        task: "hello",
        images: [],
        mentions: [],
      }),
    ),
    model,
  )
  assert_true(sending.cloud_display_status() is Some(Starting))
  let running = sending.with_status_conversation(conv => {
    ..conv,
    generating: true,
    pending: None,
    heartbeat: Some({ stage: @composer.Thinking, started_ms: None, tokens: 0, }),
  })
  assert_true(running.cloud_display_status() is Some(Running))
  let step = running.with_status_conversation(conv => {
    ..conv,
    heartbeat: Some({ stage: @composer.AtStep(3), started_ms: None, tokens: 0, }),
    retrying: Some(
      @composer.Retrying(attempt=1, max_attempts=3, reason="network"),
    ),
  })
  assert_true(step.cloud_display_status() is Some(Step(Some(3))))
  let polled = running.with_status_conversation(conv => {
    ..conv,
    heartbeat: None,
  })
  assert_true(polled.cloud_display_status() is Some(Running))
}

///|
test "Cloud status uses the authoritative result and clears it for the next task" {
  let model = integrated_cloud_model()
  for
    (outer, wire, label, css) in [
      ("completed", "completed", "Finished", "ok"),
      ("incomplete", "context_yield", "Context limit reached", "warn"),
      ("failed", "max_steps_exhausted", "Max steps exhausted", "warn"),
      ("failed", "aborted", "Aborted", "warn"),
      ("failed", "failed", "Failed", "danger"),
    ] {
    let finished = model.with_status_conversation(conv => {
      ..conv,
      records: [
        {
          task_id: "previous-task",
          kind: "task_finished",
          data: { "status": Json(outer), "result": { "status": Json(wire) } },
          created_at: 100,
        },
      ],
    })
    let status = finished.cloud_display_status().unwrap()
    assert_eq(status.label(), label)
    assert_eq(status.kind().css(), css)
    for kind in ["user", "task_started"] {
      let next = finished.with_status_conversation(conv => {
        ..conv,
        events: [
          {
            session_id: "cloud-a",
            task_id: "next-task",
            seq: 1,
            kind,
            data: {},
          },
        ],
      })
      assert_true(next.cloud_display_status() is Some(Ready))
    }
    let streamed = model.with_status_conversation(conv => {
      ..conv,
      events: [
        {
          session_id: "cloud-a",
          task_id: "task",
          seq: 1,
          kind: "task_finished",
          data: { "status": Json(outer), "result": { "status": Json(wire) } },
        },
      ],
    })
    assert_eq(streamed.cloud_display_status().unwrap().label(), label)
  }
  let failed = model.with_status_conversation(conv => {
    ..conv,
    records: [
      {
        task_id: "task",
        kind: "task_finished",
        data: { "status": "failed", "reason": "host failure" },
        created_at: 100,
      },
    ],
  })
  assert_true(failed.cloud_display_status() is Some(Failed))
  assert_true(
    cloud_record_status(Ready, "task_finished", {
      "status": "failed",
      "result": { "status": "completed" },
      "reason": "persistence failure",
    })
    is Failed,
  )
}

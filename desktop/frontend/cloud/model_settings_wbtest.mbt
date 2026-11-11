///|
test "Cloud model codecs use canonical names and restore all supported selections" {
  let base : Map[String, Json] = {
    "id": "a",
    "title": null,
    "updated_at": 1,
    "generating": false,
  }
  let defaults = decode_sessions({ "sessions": [Json(base)] })[0]
  assert_eq(defaults.model, V4Flash)
  assert_eq(defaults.thinking, ThinkingHigh)
  for
    (model_name, model) in [
      ("deepseek-flash", @deepseek.V4Flash),
      ("deepseek-v4-pro", @deepseek.V4Pro),
    ] {
    for
      (thinking_name, thinking) in [
        ("no", @protocol.ThinkingOff),
        ("high", @protocol.ThinkingHigh),
        ("max", @protocol.ThinkingMax),
      ] {
      let fields = base.copy()
      fields["model"] = Json(model_name)
      fields["thinking"] = Json(thinking_name)
      let session = decode_sessions({ "sessions": [Json(fields)] })[0]
      assert_eq(session.model, model)
      assert_eq(session.thinking, thinking)
      assert_eq(ToJson::to_json(SessionEdit::SetInference(model~, thinking~)), {
        "model": Json(model_name),
        "thinking": Json(thinking_name),
      })
    }
  }
  for
    (key, value) in [
      ("model", Json::null()),
      ("thinking", Json::null()),
      ("model", Json("deepseek-pro")),
      ("thinking", Json("off")),
      ("model", Json(1)),
      ("thinking", Json(true)),
    ] {
    let fields = base.copy()
    fields[key] = value
    let rejected = try {
      ignore(decode_sessions({ "sessions": [Json(fields)] }))
      false
    } catch {
      @cloud_client.RequestError(Malformed) => true
      _ => false
    }
    assert_true(rejected)
  }
}

///|
test "Cloud draft settings survive creation failure and seed the created session" {
  let initial = metadata_update(deletion_state(), Create)
  let id = initial.creation.unwrap().id
  assert_eq(initial.inference(id), (V4Flash, ThinkingHigh))
  let selected = metadata_update(
    initial,
    Edit(
      account="fixture",
      session=id,
      edit=SetInference(model=V4Pro, thinking=ThinkingMax),
    ),
  )
  let selected = metadata_update(
    selected,
    Edit(account="fixture", session=id, edit=SetApproval(ApprovalReview)),
  )
  let submit = Submit(selected.draft_identity().unwrap(), {
    task: "First question",
    mentions: [],
    images: [],
  })
  let creating = metadata_update(selected, submit)
  assert_false(creating.can_choose_inference(id))
  assert_true(
    metadata_update(
      creating,
      Edit(
        account="fixture",
        session=id,
        edit=SetInference(model=V4Flash, thinking=ThinkingOff),
      ),
    ) ==
    creating,
  )
  let failed = metadata_update(
    creating,
    CreateFailed(2, creating.creation.unwrap().request, Unreachable),
  )
  assert_eq(failed.inference(id), (V4Pro, ThinkingMax))
  assert_eq(failed.approval(id), ApprovalReview)
  assert_true(failed.can_choose_inference(id))
  let retry = metadata_update(failed, submit)
  let created = metadata_update(
    retry,
    Created(2, retry.creation.unwrap().request, "created"),
  )
  assert_eq(created.inference("created"), (V4Pro, ThinkingMax))
  assert_eq(created.approval("created"), ApprovalReview)
  let fresh = metadata_update(created, Create)
  assert_eq(
    fresh.inference(fresh.creation.unwrap().id),
    (V4Flash, ThinkingHigh),
  )
}

///|
test "Cloud failed settings hold sending and stale replies cannot confirm a retry" {
  let initial = deletion_state()
  let edit = Edit(
    account="fixture",
    session="a",
    edit=SetInference(model=V4Pro, thinking=ThinkingOff),
  )
  let submitting = initial.replace("a", {
    ..initial.conversations["a"],
    sending: true,
  })
  assert_false(submitting.can_choose_inference("a"))
  let pending = metadata_update(initial, edit)
  let request = pending.metadata_saves["a"].request
  assert_eq(pending.inference("a"), (V4Pro, ThinkingOff))
  assert_eq(pending.sessions[0].model, V4Flash)
  assert_false(pending.can_send("a"))
  assert_false(pending.can_choose_inference("a"))
  let failed = metadata_update(
    pending,
    EditFailed(2, "a", request, Unreachable),
  )
  assert_false(failed.saving_metadata("a"))
  assert_false(failed.can_send("a"))
  assert_true(failed.can_choose_inference("a"))
  assert_true(failed.notice is None && failed.conversations["a"].notice is None)
  // A list refresh restores saved values without discarding an unsaved choice.
  let listed = metadata_update(
    failed,
    Listed(2, failed.list_request, initial.sessions),
  )
  assert_eq(listed.inference("a"), (V4Pro, ThinkingOff))
  let retry = metadata_update(listed, edit)
  let next_request = retry.metadata_saves["a"].request
  assert_true(next_request != request)
  for
    message in [
      Edited(2, "a", request),
      EditFailed(2, "a", request, Http(500)),
      Edited(1, "a", next_request),
    ] {
    assert_true(metadata_update(retry, message) == retry)
  }
  let saved = metadata_update(retry, Edited(2, "a", next_request))
  assert_true(saved.can_send("a"))
  assert_eq(saved.sessions[0].thinking, ThinkingOff)
  assert_eq(saved.sessions[0].model, V4Pro)
  let restored = metadata_update(
    failed,
    Edit(
      account="fixture",
      session="a",
      edit=SetInference(model=V4Flash, thinking=ThinkingHigh),
    ),
  )
  // A failed network response may have followed a committed PATCH. Returning
  // to the previous choice must save it too, rather than trusting stale state.
  assert_false(restored.can_send("a"))
  let confirmed = metadata_update(
    restored,
    Edited(2, "a", restored.metadata_saves["a"].request),
  )
  assert_true(confirmed.can_send("a"))
  assert_eq(confirmed.inference("a"), (V4Flash, ThinkingHigh))
  let other = metadata_update(retry, AccountChanged(Some("other")))
  assert_true(metadata_update(other, Edited(2, "a", next_request)) == other)
}

///|
test "Cloud inference saves during generation gate queue sends but preserve Stop and the running turn" {
  let initial = controls_fixture()
  let conversation = initial.conversations["session"]
  let initial = initial.replace("session", {
    ..conversation,
    control: Some({
      ..conversation.control.unwrap(),
      queue: [{ id: "already-queued", content: @wire.Content([Text("Next")]), }],
    }),
  })
  let owner : @interop.ConversationIdentity = Cloud(
    account="account",
    session="session",
  )
  let pending = metadata_update(
    initial,
    Edit(
      account="account",
      session="session",
      edit=SetInference(model=V4Pro, thinking=ThinkingMax),
    ),
  )
  assert_true(
    pending.conversations["session"] == initial.conversations["session"],
  )
  assert_false(pending.can_choose_approval("session"))
  assert_true(controls_submit(pending, @composer.QueueNext) == pending)
  assert_true(controls_submit(pending, @composer.SteerNow) == pending)
  assert_true(
    pending.conversations["session"].control_primary_action(
      @composer.Queue,
      sending_enabled=false,
    )
    is @composer.Running(
      can_stop=true,
      queue_available=false,
      steer_available=false,
      ..
    ),
  )
  assert_true(
    pending.conversations["session"].control_context(sending_enabled=false)
    is [
      @composer.QueuedInputPanel(
        enabled=true,
        items=[
          {
            state: @composer.Queued(steer_available=false, interactive=true, ..),
            ..
          },
        ]
      ),
    ],
  )
  let stopped = pending
    .update_control(
      ControlAction(
        owner,
        @composer.StopRequested(identity={ owner, archive_generation: 0, }),
      ),
      _ => @cmd.none,
      Some("token"),
    )
    .unwrap().0
  assert_true(
    stopped.conversations["session"].control_inputs is [{ operation: Stop, .. }],
  )
  let failed = metadata_update(
    pending,
    EditFailed(
      1,
      "session",
      pending.metadata_saves["session"].request,
      Http(500),
    ),
  )
  assert_true(controls_submit(failed, @composer.QueueNext) == failed)
  let saved = metadata_update(
    pending,
    Edited(1, "session", pending.metadata_saves["session"].request),
  )
  let queued = controls_submit(saved, @composer.QueueNext)
  assert_true(
    queued.conversations["session"].control_inputs
    is [{ operation: QueueAdd(..), .. }],
  )
  assert_eq(queued.inference("session"), (V4Pro, ThinkingMax))
  assert_true(
    metadata_update(
      saved,
      Edit(
        account="wrong",
        session="session",
        edit=SetInference(model=V4Flash, thinking=ThinkingHigh),
      ),
    ) ==
    saved,
  )
}

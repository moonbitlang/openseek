///|
test "session inference codecs cover all choices and reject malformed values" {
  let base : Json = {
    "id": "a",
    "title": null,
    "updated_at": 1,
    "generating": false,
  }
  guard base is Object(fields) else { fail("object fixture") }
  let defaults = decode_sessions({ "sessions": [base] })[0]
  assert_true(defaults.model is V4Flash)
  assert_true(defaults.thinking is ThinkingHigh)
  for
    (name, model) in [
      ("deepseek-flash", @deepseek.V4Flash),
      ("deepseek-v4-pro", @deepseek.V4Pro),
    ] {
    for
      (wire, thinking) in [
        ("no", @protocol.ThinkingOff),
        ("high", @protocol.ThinkingHigh),
        ("max", @protocol.ThinkingMax),
      ] {
      let item = fields.copy()
      item["model"] = Json(name)
      item["thinking"] = Json(wire)
      let session = decode_sessions({ "sessions": [Json(item)] })[0]
      assert_eq(session.model, model)
      assert_eq(session.thinking, thinking)
      assert_eq(ToJson::to_json(SessionEdit::SetModel(model)), { "model": name })
      assert_eq(ToJson::to_json(SessionEdit::SetThinking(thinking)), {
        "thinking": wire,
      })
    }
  }
  for
    (field, invalid) in [
      ("model", Json::null()),
      ("model", Json("pro")),
      ("thinking", Json("off")),
      ("thinking", Json::null()),
      ("thinking", Json(1)),
    ] {
    let item = fields.copy()
    item[field] = invalid
    let rejected = try {
      ignore(decode_sessions({ "sessions": [Json(item)] }))
      false
    } catch {
      @cloud_client.RequestError(Malformed) => true
      _ => false
    }
    assert_true(rejected)
  }
}

///|
test "inference edits share approval saves and preserve saved choices on failure" {
  let initial = deletion_state()
  for edit in [SetModel(V4Pro), SetThinking(ThinkingMax)] {
    let pending = metadata_update(
      initial,
      Edit(account="fixture", session="a", edit~),
    )
    assert_false(pending.can_send("a"))
    assert_false(pending.can_choose_settings("a"))
    assert_true(pending.model("a") is V4Flash)
    assert_true(pending.thinking("a") is ThinkingHigh)
    let request = pending.metadata_saves["a"].request
    let saved = metadata_update(pending, Edited(2, "a", request))
    assert_true(saved.can_send("a"))
    assert_true(saved.can_choose_settings("a"))
    match edit {
      SetModel(_) => assert_true(saved.model("a") is V4Pro)
      SetThinking(_) => assert_true(saved.thinking("a") is ThinkingMax)
      _ => fail("inference edit")
    }
    // An old inventory or a different account cannot overwrite the result.
    assert_true(
      metadata_update(saved, Listed(2, initial.list_request, initial.sessions)) ==
      saved,
    )
    let switched = metadata_update(pending, AccountChanged(Some("other")))
    assert_true(metadata_update(switched, Edited(2, "a", request)) == switched)
    for failure in [@cloud_client.Unreachable, @cloud_client.Http(409)] {
      let failed = metadata_update(
        pending,
        EditFailed(2, "a", request, failure),
      )
      assert_true(failed.model("a") is V4Flash)
      assert_true(failed.thinking("a") is ThinkingHigh)
      assert_true(failed.notice is Some(_))
      assert_true(failed.can_send("a"))
      assert_true(failed.can_edit("a", edit))
    }
  }
}

///|
test "busy or compacting sessions refuse all engine option edits" {
  let initial = deletion_state()
  let conversation = initial.conversations["a"]
  for
    running in [
      initial.replace("a", { ..conversation, generating: true, }),
      initial.replace("a", { ..conversation, sending: true, }),
      initial.replace("a", {
        ..conversation,
        controls: conversation.controls.observe_compaction(
          queued=false,
          compacting=true,
          baseline=true,
        ),
      }),
      initial.replace("a", {
        ..conversation,
        controls: conversation.controls.observe_compaction(
          queued=true,
          compacting=false,
          baseline=true,
        ),
      }),
    ] {
    for
      edit in [
        SetApproval(ApprovalReview),
        SetModel(V4Pro),
        SetThinking(ThinkingOff),
      ] {
      assert_false(running.can_choose_settings("a"))
      assert_true(
        metadata_update(running, Edit(account="fixture", session="a", edit~)) ==
        running,
      )
    }
  }
}

///|
test "draft inference choices survive creation failure and stay with their draft" {
  let blank = command_draft()
  let owner = blank.draft_identity().unwrap()
  let chosen = metadata_update(
    metadata_update(
      blank,
      Edit(account="account", session=owner.session(), edit=SetModel(V4Pro)),
    ),
    Edit(
      account="account",
      session=owner.session(),
      edit=SetThinking(ThinkingOff),
    ),
  )
  let pending = metadata_update(
    chosen,
    Submit(owner, { task: "Keep me", images: [], mentions: [], }),
  )
  assert_false(pending.can_choose_settings(owner.session()))
  let request = pending.creation.unwrap().request
  let failed = metadata_update(pending, CreateFailed(1, request, Unreachable))
  assert_true(failed.model(owner.session()) is V4Pro)
  assert_true(failed.thinking(owner.session()) is ThinkingOff)
  assert_true(failed.can_choose_settings(owner.session()))
  let retry = metadata_update(
    failed,
    Submit(owner, { task: "Keep me", images: [], mentions: [], }),
  )
  let created = metadata_update(
    retry,
    Created(1, retry.creation.unwrap().request, "new"),
  )
  assert_true(created.model("new") is V4Pro)
  assert_true(created.thinking("new") is ThinkingOff)
  let next = metadata_update(created, Create)
  let draft = next.draft_identity().unwrap()
  assert_true(next.model(draft.session()) is V4Flash)
  assert_true(next.thinking(draft.session()) is ThinkingHigh)
}

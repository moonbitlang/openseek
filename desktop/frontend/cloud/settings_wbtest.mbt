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
test "inference saves update only the selected option after confirmation" {
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
      SetModel(_) => {
        assert_true(saved.model("a") is V4Pro)
        assert_true(saved.thinking("a") is ThinkingHigh)
      }
      SetThinking(_) => {
        assert_true(saved.model("a") is V4Flash)
        assert_true(saved.thinking("a") is ThinkingMax)
      }
      _ => fail("inference edit")
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
test "created sessions inherit both draft inference choices" {
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
  let created = metadata_update(
    pending,
    Created(1, pending.creation.unwrap().request, "new"),
  )
  assert_true(created.model("new") is V4Pro)
  assert_true(created.thinking("new") is ThinkingOff)
}

///|
test "uncertain option saves stay fenced until a fresh catalog succeeds" {
  for
    (edit, failure) in [
      (SetModel(V4Pro), @cloud_client.Unreachable),
      (SetThinking(ThinkingMax), @cloud_client.Http(408)),
      (SetApproval(ApprovalReview), @cloud_client.Http(502)),
    ] {
    let initial = deletion_state()
    let pending = metadata_update(
      initial,
      Edit(account="fixture", session="a", edit~),
    )
    let refreshing = metadata_update(pending, Refresh)
    let old_list = refreshing.list_request
    let still_saving = metadata_update(
      refreshing,
      Listed(2, old_list, initial.sessions),
    )
    assert_false(still_saving.can_send("a"))
    let uncertain = metadata_update(
      refreshing,
      EditFailed(2, "a", pending.metadata_saves["a"].request, failure),
    )
    assert_false(uncertain.can_send("a"))
    assert_false(uncertain.can_choose_settings("a"))
    assert_true(uncertain.list_request > old_list)
    assert_true(
      metadata_update(uncertain, Listed(2, old_list, initial.sessions)) ==
      uncertain,
    )
    let failed = metadata_update(
      uncertain,
      ListFailed(2, uncertain.list_request, Unreachable),
    )
    assert_false(failed.can_send("a"))
    let retry = metadata_update(failed, Refresh)
    let sessions = initial.sessions.map(session => {
      match edit {
        SetModel(model) => { ..session, model, }
        SetThinking(thinking) => { ..session, thinking, }
        SetApproval(approval) => { ..session, approval, }
        _ => session
      }
    })
    // The response is authoritative whether the uncertain write committed or not.
    for sessions in [initial.sessions, sessions] {
      let confirmed = metadata_update(
        retry,
        Listed(2, retry.list_request, sessions),
      )
      assert_true(confirmed.sessions == sessions)
      assert_true(confirmed.metadata_saves.is_empty())
      assert_true(confirmed.can_send("a"))
    }
  }
}

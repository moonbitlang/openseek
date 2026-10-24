///|
fn metadata_update(state : State, message : Msg) -> State {
  let (next, _, _) = update(
    state,
    message,
    _ => @cmd.none,
    token="fixture",
    navigation=0,
  )
  next
}

///|
test "Cloud metadata codecs preserve false and reject malformed archive flags" {
  let base : Json = {
    "id": "a",
    "title": "A",
    "updated_at": 1,
    "generating": false,
  }
  assert_false(decode_sessions({ "sessions": [base] })[0].archived)
  for archived in [true, false] {
    let item : Json = {
      "id": "a",
      "title": "A",
      "updated_at": 1,
      "generating": false,
      "archived": Json(archived),
    }
    assert_eq(decode_sessions({ "sessions": [item] })[0].archived, archived)
    assert_eq(ToJson::to_json(SessionEdit::Archive(archived)), {
      "archived": Json(archived),
    })
  }
  assert_eq(ToJson::to_json(SessionEdit::Rename("Title")), { "title": "Title" })
  for invalid in [Json::null(), Json("false"), Json(0)] {
    let item : Json = {
      "id": "a",
      "title": "A",
      "updated_at": 1,
      "generating": false,
      "archived": invalid,
    }
    let failed = try {
      ignore(decode_sessions({ "sessions": [item] }))
      false
    } catch {
      _ => true
    }
    assert_true(failed)
  }
}

///|
test "metadata completion fences inventory reads issued before the PATCH completed" {
  let initial = deletion_state()
  let pending = metadata_update(
    initial,
    Edit(account="fixture", session="a", edit=Rename("  Manual title  ")),
  )
  assert_eq(pending.sessions[0].title, Some("A"))
  assert_false(pending.can_delete("a"))
  assert_false(pending.can_edit("a", Rename("another")))
  let refreshing = metadata_update(pending, Refresh)
  let old_list = refreshing.list_request
  let saved = metadata_update(
    refreshing,
    Edited(2, "a", pending.metadata_saves["a"].request),
  )
  assert_eq(saved.sessions[0].title, Some("Manual title"))
  assert_true(saved.metadata_saves.is_empty())
  assert_true(saved.list_request > old_list)
  let late = metadata_update(saved, Listed(2, old_list, initial.sessions))
  assert_eq(late.sessions[0].title, Some("Manual title"))
  let current = metadata_update(
    saved,
    Listed(2, saved.list_request, saved.sessions),
  )
  assert_eq(current.sessions[0].title, Some("Manual title"))
}

///|
test "metadata responses are scoped to the save and account epoch" {
  let pending = metadata_update(
    deletion_state(),
    Edit(account="fixture", session="a", edit=Rename("Manual")),
  )
  let request = pending.metadata_saves["a"].request
  for
    reply in [
      Edited(1, "a", request),
      Edited(2, "a", request + 1),
      EditFailed(1, "a", request, Unauthorized),
    ] {
    assert_true(metadata_update(pending, reply) == pending)
  }
  let switched = metadata_update(pending, AccountChanged(Some("other")))
  assert_true(metadata_update(switched, Edited(2, "a", request)) == switched)
  assert_true(
    metadata_update(switched, EditFailed(2, "a", request, Unauthorized)) ==
    switched,
  )
  assert_true(switched.metadata_saves.is_empty())
  assert_false(switched.needs_sign_in)
}

///|
test "failed metadata keeps the saved values and permits a normal retry" {
  let errors : Array[Failure] = [Http(503), Busy, Unreachable, Unauthorized]
  for error in errors {
    let pending = metadata_update(
      deletion_state(),
      Edit(account="fixture", session="a", edit=Rename("Manual")),
    )
    let failed = metadata_update(
      pending,
      EditFailed(2, "a", pending.metadata_saves["a"].request, error),
    )
    assert_eq(failed.sessions[0].title, Some("A"))
    assert_false(failed.sessions[0].archived)
    assert_true(failed.metadata_saves.is_empty())
    assert_true(failed.can_edit("a", Rename("Retry")))
    assert_eq(failed.needs_sign_in, error is Unauthorized)
    assert_true(failed.notice is Some(_))
  }
}

///|
test "metadata 404 retires the missing session without late reply resurrection" {
  let pending = metadata_update(
    deletion_state(),
    Edit(account="fixture", session="a", edit=Rename("Manual")),
  )
  let request = pending.metadata_saves["a"].request
  let missing = metadata_update(pending, EditFailed(2, "a", request, Http(404)))
  assert_true(missing.sessions.is_empty())
  assert_true(missing.conversations.is_empty())
  assert_true(missing.metadata_saves.is_empty())
  assert_true(metadata_update(missing, Edited(2, "a", request)) == missing)
}

///|
test "metadata actions reject stale accounts, blank titles and pending deletions" {
  let initial = deletion_state()
  for
    message in [
      Edit(account="other", session="a", edit=Rename("Title")),
      Edit(account="fixture", session="a", edit=Rename("   ")),
      Edit(account="fixture", session="missing", edit=Rename("Title")),
    ] {
    assert_true(metadata_update(initial, message) == initial)
  }
  let deleting = metadata_update(initial, Delete("a"))
  assert_true(
    metadata_update(
      deleting,
      Edit(account="fixture", session="a", edit=Rename("Title")),
    ) ==
    deleting,
  )
}

///|
test "archive and restore block sending until the owning PATCH completes" {
  let initial = deletion_state()
  let owner = @interop.Cloud(account="fixture", session="a")
  let draft : @composer.Draft = {
    task: "must not send",
    images: [],
    mentions: [],
  }
  assert_true(initial.can_send("a"))
  let unknown = { ..initial, sessions: [], }
  assert_false(unknown.can_compose("a"))
  assert_false(unknown.can_send("a"))
  assert_true(metadata_update(unknown, Submit(owner, draft)) == unknown)
  let pending = metadata_update(
    initial,
    Edit(account="fixture", session="a", edit=Archive(true)),
  )
  assert_false(pending.can_send("a"))
  assert_true(metadata_update(pending, Submit(owner, draft)) == pending)
  assert_false(pending.is_archived("a"))
  let archived = metadata_update(
    pending,
    Edited(2, "a", pending.metadata_saves["a"].request),
  )
  assert_true(archived.is_archived("a"))
  assert_false(archived.can_send("a"))
  assert_true(metadata_update(archived, Submit(owner, draft)) == archived)
  assert_false(archived.can_edit("a", Rename("Archived name")))
  let old_list = archived.list_request
  let pending = metadata_update(
    archived,
    Edit(account="fixture", session="a", edit=Archive(false)),
  )
  assert_false(pending.can_send("a"))
  let restored = metadata_update(
    pending,
    Edited(2, "a", pending.metadata_saves["a"].request),
  )
  assert_false(restored.is_archived("a"))
  assert_true(restored.can_send("a"))
  let late = metadata_update(restored, Listed(2, old_list, archived.sessions))
  assert_false(late.is_archived("a"))
  assert_true(late.retired.is_empty())
  assert_true(late.conversations.contains("a"))
}

///|
test "running conversations allow rename but reject archive and archive failure keeps the record live" {
  let initial = deletion_state()
  let running = {
    ..initial,
    sessions: initial.sessions.map(item => { ..item, generating: true, }),
  }
  assert_true(running.can_edit("a", Rename("Running name")))
  assert_false(running.can_edit("a", Archive(true)))
  assert_true(
    metadata_update(
      running,
      Edit(account="fixture", session="a", edit=Archive(true)),
    ) ==
    running,
  )
  let renaming = metadata_update(
    initial,
    Edit(account="fixture", session="a", edit=Rename("Title")),
  )
  assert_true(renaming.can_send("a"))
  let pending = metadata_update(
    initial,
    Edit(account="fixture", session="a", edit=Archive(true)),
  )
  let failed = metadata_update(
    pending,
    EditFailed(2, "a", pending.metadata_saves["a"].request, Http(409)),
  )
  assert_false(failed.is_archived("a"))
  assert_true(failed.can_send("a"))
  assert_false(failed.needs_sign_in)
}

///|
test "a completed archive wins over an earlier history response's running flag" {
  let pending = metadata_update(
    metadata_update(deletion_state(), Open("a")),
    Edit(account="fixture", session="a", edit=Archive(true)),
  )
  let old_history = Loaded(2, "a", pending.conversations["a"].request, {
    prediction: None,
    session: native_document([]),
    messages: [],
    generating: true,
  })
  let sending = metadata_update(
    deletion_state(),
    Submit(@interop.Cloud(account="fixture", session="a"), {
      task: "question",
      mentions: [],
      images: [],
    }),
  )
  let recovering = metadata_update(
    sending,
    SendFailed(2, "a", sending.conversations["a"].request, Unreachable),
  )
  let pending_recovery = metadata_update(
    recovering,
    Edit(account="fixture", session="a", edit=Archive(true)),
  )
  for
    state in [pending, metadata_update(pending, old_history), pending_recovery] {
    let old_history = Loaded(2, "a", state.conversations["a"].request, {
      prediction: None,
      session: native_document([]),
      messages: [],
      generating: true,
    })
    let archived = metadata_update(
      state,
      Edited(2, "a", state.metadata_saves["a"].request),
    )
    assert_true(archived.conversations["a"].loading)
    assert_false(archived.sessions[0].generating)
    assert_false(archived.conversations["a"].generating)
    assert_true(archived.can_edit("a", Archive(false)))
    let late = metadata_update(archived, old_history)
    assert_false(late.sessions[0].generating)
    assert_false(late.conversations["a"].generating)
    assert_true(late.can_edit("a", Archive(false)))
    let restoring = metadata_update(
      archived,
      Edit(account="fixture", session="a", edit=Archive(false)),
    )
    let restored = metadata_update(
      restoring,
      Edited(2, "a", restoring.metadata_saves["a"].request),
    )
    let late = metadata_update(restored, old_history)
    assert_true(late == restored)
    assert_false(late.sessions[0].generating)
    assert_false(late.conversations["a"].generating)
    assert_true(
      late.conversations["a"].request != state.conversations["a"].request,
    )
    let ready = metadata_update(
      late,
      Loaded(2, "a", late.conversations["a"].request, {
        prediction: None,
        session: native_document([]),
        messages: [
          {
            task_id: "finished",
            kind: "assistant_message",
            data: { "content": "Final answer" },
            engine_sequence: None,
            created_at: 5,
          },
        ],
        generating: false,
      }),
    )
    assert_true(ready.can_send("a"))
    assert_eq(ready.conversations["a"].records[0].data, {
      "content": "Final answer",
    })
  }
}

///|
test "externally archived inventory fences pending history through restoration" {
  let opened = metadata_update(deletion_state(), Open("a"))
  let old_request = opened.conversations["a"].request
  let creating = metadata_update(opened, Create)
  let creating = metadata_update(
    creating,
    Submit(creating.draft_identity().unwrap(), {
      task: "First message",
      images: [],
      mentions: [],
    }),
  )
  let created = metadata_update(
    creating,
    Created(2, creating.creation.unwrap().request, "b"),
  )
  let sessions = created.sessions.map(session => {
    if session.id == "a" {
      { ..session, archived: true, generating: false, }
    } else {
      session
    }
  })
  let archived = metadata_update(
    created,
    Listed(2, created.list_request, sessions),
  )
  let old_history = Loaded(2, "a", old_request, {
    prediction: None,
    session: native_document([]),
    messages: [],
    generating: true,
  })
  assert_true(archived.is_archived("a"))
  assert_true(metadata_update(archived, old_history) == archived)
  assert_true(archived.can_edit("a", Archive(false)))
  let restoring = metadata_update(
    archived,
    Edit(account="fixture", session="a", edit=Archive(false)),
  )
  let restored = metadata_update(
    restoring,
    Edited(2, "a", restoring.metadata_saves["a"].request),
  )
  assert_false(restored.is_archived("a"))
  assert_true(metadata_update(restored, old_history) == restored)
  assert_true(restored.conversations["a"].request != old_request)
  let ready = metadata_update(
    restored,
    Loaded(2, "a", restored.conversations["a"].request, {
      prediction: None,
      session: native_document([]),
      messages: [],
      generating: false,
    }),
  )
  assert_true(ready.can_send("a"))
  assert_false(
    ready.sessions.iter().find_first(item => item.id == "a").unwrap().generating,
  )
  let sending = metadata_update(
    deletion_state(),
    Submit(@interop.Cloud(account="fixture", session="a"), {
      task: "question",
      mentions: [],
      images: [],
    }),
  )
  let listing = metadata_update(sending, Refresh)
  let listed = metadata_update(
    listing,
    Listed(
      2,
      listing.list_request,
      listing.sessions.map(item => {
        ..item,
        archived: true,
        generating: false,
      }),
    ),
  )
  assert_eq(
    listed.conversations["a"].request,
    sending.conversations["a"].request,
  )
  let ended = metadata_update(
    listed,
    SendFailed(2, "a", sending.conversations["a"].request, Unreachable),
  )
  assert_false(ended.conversations["a"].sending)
  assert_true(ended.can_edit("a", Archive(false)))
}

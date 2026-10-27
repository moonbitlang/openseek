///|
test "Cloud prepares file mentions in the same command before and after creation" {
  let model = integrated_cloud_model()
  let draft : @composer.Draft = {
    task: "",
    mentions: [{ ref_: File(path="index.html"), range: None, }],
    images: [],
  }
  let (_, sending) = update(
    test_dispatch(),
    ComposerAction(
      @composer.DraftSubmitted(identity=model.composer_input().identity, draft~),
    ),
    model,
  )
  assert_eq(
    sending.cloud.conversations["cloud-a"].pending.unwrap().content.text(),
    draft.prompt(),
  )
  let (_, blank) = update(test_dispatch(), CloudAction(@cloud.Create), model)
  let (_, creating) = update(
    test_dispatch(),
    ComposerAction(
      @composer.DraftSubmitted(identity=blank.composer_input().identity, draft~),
    ),
    blank,
  )
  let (_, created) = update(
    test_dispatch(),
    CloudAction(
      @cloud.Created(creating.cloud.epoch, creating.cloud.sequence, "new-cloud"),
    ),
    creating,
  )
  let submission = created.cloud.conversations["new-cloud"].outgoing.unwrap()
  assert_true(
    submission.input is @cloud.Prompt(content~, draft=source, ..) &&
    source == draft &&
    content.text() == draft.prompt(),
  )
}

///|
test "Cloud file chips and transcript links open session source previews" {
  let model = integrated_cloud_model()
  let identity = model.composer_input().identity
  let mention : @composer.Mention = {
    ref_: File(path="index.html"),
    range: None,
  }
  let actions = [
    ComposerAction(@composer.MentionOpened(identity~, mention~)),
    TranscriptLinkOpened(
      slot=model.transcript_slot().unwrap().key(),
      path="index.html",
    ),
    TranscriptLocationOpened(
      slot=model.transcript_slot().unwrap().key(),
      @mention_context.target(Symbol(name="heading", file="index.html", line=3)).unwrap(),
    ),
  ]
  let expected = @resource.join_relative(
    file_ctx(model).root().unwrap(),
    Relative("index.html"),
  )
  for action in actions {
    let (_, opened) = update(test_dispatch(), action, model)
    assert_eq(@dock.active_file(opened.dock_state()), Some(expected))
    assert_true(opened.right_panel_open)
    assert_eq(opened.file_panel.owner, Some(identity.owner))
    assert_true(opened.file_panel.docs.contains(expected))
  }
  for
    owner in [
      @interop.Cloud(account="other-account", session="cloud-a"),
      @interop.Cloud(account="fixture-user", session="other-session"),
    ] {
    let (_, ignored) = update(
      test_dispatch(),
      ComposerAction(
        @composer.MentionOpened(identity={ ..identity, owner, }, mention~),
      ),
      model,
    )
    assert_true(ignored.docks == model.docks)
  }
  for
    path in [
      "/tmp/index.html",
      "../index.html",
      "file:///tmp/index.html",
      expected.to_string(),
    ] {
    let (_, ignored) = update(test_dispatch(), OpenFile(path), model)
    assert_true(ignored.docks == model.docks)
  }
}

///|
test "Cloud editor feedback uses the current resource identity and Annotation contract" {
  let model = integrated_cloud_model()
  let path = @resource.join_relative(
    file_ctx(model).root().unwrap(),
    Relative("src/main.mbt"),
  )
  let range = @common.Range(2, 1, 3, 4)
  let event = (resource : @common.Uri) => {
    FileEditor(
      @fileeditor.EditorCommentAdded(
        resource=@fileeditor.ModelUri::of(resource),
        file=Relative("src/main.mbt"),
        range~,
        quote="exact selection",
        comment="Explain this",
        feedback_id="feedback",
      ),
    )
  }
  let reply = model.routed_editor_feedback(event(path)).unwrap()
  assert_eq(reply.identity, model.composer_input().identity)
  assert_false(reply.send)
  guard reply.content is @composer.Annotation(mention) else {
    fail("missing annotation")
  }
  let draft : @composer.Draft = {
    task: "Existing draft",
    mentions: [mention],
    images: [],
  }
  let (_, sending) = update(
    test_dispatch(),
    ComposerAction(@composer.DraftSubmitted(identity=reply.identity, draft~)),
    model,
  )
  assert_eq(
    sending.cloud.conversations["cloud-a"].pending.unwrap().content.text(),
    draft.prompt(),
  )
  assert_true(draft.prompt().contains("<annotation"))
  assert_true(draft.prompt().contains("exact selection"))
  let (_, opened) = update(
    test_dispatch(),
    ComposerAction(@composer.MentionOpened(identity=reply.identity, mention~)),
    model,
  )
  assert_eq(@dock.active_file(opened.dock_state()), Some(path))
  assert_true(opened.file_panel.docs.contains(path))
  assert_true(
    model
    .routed_editor_feedback(
      FileEditor(
        @fileeditor.ApplyEditorFeedback(@fileeditor.ModelUri::of(path)),
      ),
    )
    .unwrap().send,
  )
  for (account, session) in [("other", "cloud-a"), ("fixture-user", "other")] {
    let foreign = @resource.join_relative(
      @resource.cloud_root(@cloud.CloudOrigin, account, session).unwrap(),
      Relative("src/main.mbt"),
    )
    assert_true(model.routed_editor_feedback(event(foreign)) is None)
    let (_, ignored) = update(test_dispatch(), event(foreign), model)
    assert_true(ignored.active_conversation() == model.active_conversation())
  }
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
  assert_false(file_ctx(archived).feedback_enabled)
  assert_true(archived.routed_editor_feedback(event(path)) is None)
  let conversation = model.cloud.conversations["cloud-a"]
  let conversations = model.cloud.conversations.copy()
  conversations["cloud-a"] = { ..conversation, generating: true, }
  let running = { ..model, cloud: { ..model.cloud, conversations, }, }
  assert_true(running.routed_editor_feedback(event(path)) is Some(_))
  let (_, unchanged) = update(
    test_dispatch(),
    ComposerAction(@composer.DraftSubmitted(identity=reply.identity, draft~)),
    running,
  )
  assert_true(unchanged.cloud.conversations["cloud-a"].pending is None)
}

///|
fn Model::routed_editor_feedback(
  self : Model,
  message : Msg,
) -> @composer.QuoteReply? {
  let replies : Array[@composer.QuoteReply] = []
  ignore(
    update(
      @cmd.Emit(message => {
        if message is ComposerReply(reply) {
          replies.push(reply)
        }
        @cmd.none
      }),
      message,
      self,
    ),
  )
  replies.get(0)
}

///|
test "Cloud file menu downloads an unopened target without changing the active preview" {
  let model = integrated_cloud_model()
  let root = file_ctx(model).root().unwrap()
  let target = @resource.join_relative(root, Relative("src/data.bin"))
  let (_, pending) = update(
    test_dispatch(),
    DownloadFile("src/data.bin"),
    model,
  )
  assert_eq(pending.file_panel.download, Some(target))
  assert_true(pending.dock_state() == model.dock_state())
  assert_false(pending.file_panel.docs.contains(target))
  let (_, duplicate) = update(
    test_dispatch(),
    DownloadFile("other.bin"),
    pending,
  )
  assert_eq(duplicate.file_panel.download, Some(target))
  assert_eq(
    duplicate.file_panel.download_generation,
    pending.file_panel.download_generation,
  )
  let foreign = @resource.cloud_root(
    @cloud.CloudOrigin,
    "other-account",
    "cloud-a",
  ).unwrap()
  for
    path in [
      "../outside.bin",
      "/outside.bin",
      @resource.join_relative(foreign, Relative("data.bin")).to_string(),
    ] {
    let (_, ignored) = update(test_dispatch(), DownloadFile(path), model)
    assert_true(ignored.file_panel.download is None)
    let (_, ignored) = update(test_dispatch(), ShareFile(path), model)
    assert_false(ignored.file_share_dialog.is_open())
  }
}

///|
test "file sharing resolves relative and absolute paths only inside the owning checkout" {
  let model = test_model()
  let expected = model.test_file("src/data.bin")
  for path in ["src/data.bin", expected.path, expected.to_string()] {
    assert_eq(model.workspace_file(path), Some(expected))
  }
  for
    path in ["../data.bin", "/other/data.bin", "https://example.test/data.bin"] {
    assert_true(model.workspace_file(path) is None)
  }
}

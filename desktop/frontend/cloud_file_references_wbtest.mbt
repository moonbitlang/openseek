///|
test "Cloud sends file mentions and restores the first submission as chips" {
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
    sending.cloud.conversations["cloud-a"].pending.unwrap().content,
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
  assert_true(created.composer_input().draft == draft)
  assert_eq(
    created.cloud.conversations["new-cloud"].pending.unwrap().content,
    draft.prompt(),
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
    assert_eq(@dock.active_file(opened.dock), Some(expected))
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
    assert_true(ignored.dock == model.dock)
  }
  for
    path in [
      "/tmp/index.html",
      "../index.html",
      "file:///tmp/index.html",
      expected.to_string(),
    ] {
    let (_, ignored) = update(test_dispatch(), OpenFile(path), model)
    assert_true(ignored.dock == model.dock)
  }
}

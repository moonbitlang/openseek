///|
test "Cloud model content keeps the original image bytes and leaves plain text as a string" {
  let image : @composer.Image = {
    name: "picture.png",
    url: "data:image/png;base64,iVBORw0KGgo=",
  }
  let draft : @composer.Draft = {
    task: "Inspect",
    mentions: [],
    images: [image],
  }
  let content = prompt_content(draft)
  assert_true(
    content.to_json()
    is [
      { "type": "text", "text": "Inspect", .. },
      { "type": "image", "media_type": "image/png", "data": "iVBORw0KGgo=", .. },
    ],
  )
  let changed = { ..draft, images: [], }
  assert_eq(prompt_content(changed).to_json(), Json("Inspect"))
  assert_true(content.to_json() is [_, { "data": "iVBORw0KGgo=", .. }])
  let invalid = {
    ..draft,
    images: [{ name: "bad.png", url: "data:image/png;base64,dGV4dA==", }],
  }
  assert_true(
    try {
      ignore(prompt_content(invalid))
      false
    } catch {
      @cloud_client.RequestError(InvalidImage) => true
      _ => false
    },
  )
}

///|
test "first Cloud file-only submission creates once and admits the prepared file reference" {
  let emit : @cmd.Emit[Msg] = _ => @cmd.none
  let state = { ..State::empty(), user_id: Some("user"), epoch: 1, }
  let (blank, _, _) = update(state, Create, emit, token="fixture", navigation=0)
  let owner = blank.draft_identity().unwrap()
  let attachments = [
    @protocol.AttachmentBytes(name="report.pdf", data_base64="JVBERg=="),
  ]
  let draft : @composer.Draft = { task: "", images: [], mentions: [], }
  let (creating, _, _) = update(
    blank,
    SubmitAttachments(owner, draft, attachments),
    emit,
    token="fixture",
    navigation=0,
  )
  assert_true(
    creating.creation is Some({ submission: Some(_), attachments: [_], .. }),
  )
  let (created, _, selected) = update(
    creating,
    Created(1, creating.sequence, "new-session"),
    emit,
    token="fixture",
    navigation=0,
  )
  assert_eq(selected, Some("new-session"))
  let conversation = created.conversations["new-session"]
  assert_true(conversation.sending)
  assert_eq(conversation.initial_attachments, attachments)
  let path = ".openseek/attachments/uuid/report.pdf"
  let (stored, _, _) = update(
    created,
    AttachmentStored(
      1,
      "new-session",
      conversation.request,
      attachments[0],
      path,
    ),
    emit,
    token="fixture",
    navigation=0,
  )
  let prepared = draft.with_mention({ ref_: File(path~), range: None, })
  let (ready, _, _) = update(
    stored,
    MessagePrepared(
      1,
      "new-session",
      conversation.request,
      prepared,
      prompt_content(prepared),
    ),
    emit,
    token="fixture",
    navigation=0,
  )
  assert_true(ready.conversations["new-session"].initial_attachments.is_empty())
  assert_eq(
    ready.conversations["new-session"].initial_submission,
    Some(prepared),
  )
  let (admitted, _, _) = update(
    ready,
    StreamEvent(1, "new-session", conversation.request, {
      session_id: "new-session",
      task_id: "task",
      seq: 1,
      kind: "task_started",
      data: {},
    }),
    emit,
    token="fixture",
    navigation=0,
  )
  assert_true(admitted.conversations["new-session"].pending is None)
  assert_true(admitted.conversations["new-session"].uploads.is_empty())
  assert_true(admitted.conversations["new-session"].initial_submission is None)
}

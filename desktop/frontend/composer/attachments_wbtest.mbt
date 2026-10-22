///|
fn attachment_step(model : Model, input : Input, message : Msg) -> Model {
  model.update(input, message, Msg::test_emit(), Action::test_emit()).0
}

///|
fn attachment_reading(input : Input) -> Model {
  attachment_step(
    Model(input),
    input,
    ImageRead(
      input.identity,
      input.root,
      @image_input.NativePicked(Ok(Some("/Downloads/report.pdf"))),
    ),
  )
}

///|
test "native picker results preserve concurrent browser reads and remain pure" {
  let input = Input::fixture("keep this text")
  for reads in [0, 1] {
    let model = Model(input).with_entry({ ..Entry(input), image_reads: reads, })
    for
      result in [
        Ok(None),
        Ok(Some("/Downloads/report.pdf")),
        Err("picker failed"),
      ] {
      let msg = ImageRead(
        input.identity,
        input.root,
        @image_input.NativePicked(result),
      )
      let next = attachment_step(model, input, msg)
      assert_true(next == attachment_step(model, input, msg))
      assert_eq(next.active(input).image_reads, reads)
      assert_eq(next.active(input).draft, input.draft)
      match result {
        Ok(None) => assert_true(next == model)
        Ok(Some(_)) => {
          assert_eq(next.active(input).attachment_requests.length(), 1)
          assert_true(
            next.active(input).attachment_requests[0].phase
            is AttachmentPreparing,
          )
          assert_false(next.active(input).can_send(input))
        }
        Err(_) => {
          assert_eq(next.active(input).image_error, Some("picker failed"))
          assert_true(next.active(input).attachment_requests.is_empty())
        }
      }
      assert_eq(model.active(input).image_reads, reads)
      assert_true(model.active(input).attachment_requests.is_empty())
    }
  }
}

///|
test "native selection belongs to its original draft and ignores retired drafts" {
  let input = Input::fixture("keep this text")
  let other = {
    ..input,
    identity: {
      ..input.identity,
      owner: @interop.Host({ channel: Local, session: "other", }),
    },
  }
  let msg = ImageRead(
    input.identity,
    input.root,
    @image_input.NativePicked(Ok(Some("/Downloads/report.pdf"))),
  )
  let model = Model(input)
  let next = attachment_step(model, other, msg)
  assert_eq(next.active(input).attachment_requests.length(), 1)
  assert_true(next.active(other).attachment_requests.is_empty())
  let retired = { ..other, retirements: [input.identity.owner], }
  let dropped = attachment_step(model, retired, msg)
  assert_true(dropped.entries.all(entry => entry.owner != input.identity.owner))
  let changed = { ..input, root: Some(@common.Uri::file("/other")), }
  assert_true(
    attachment_step(model, changed, msg).active(changed).attachment_requests.is_empty(),
  )
}

///|
test "document attachment confirmation blocks send and cancel preserves the draft" {
  let input = Input::fixture("keep this text")
  let model = attachment_reading(input)
  let request = model.active(input).attachment_requests[0]
  assert_eq(model.active(input).draft.task, "keep this text")
  assert_true(model.active(input).draft.mentions.is_empty())
  assert_false(model.active(input).can_send(input))
  assert_true(
    model
    .active(input)
    .action_buttons(Msg::test_emit(), Action::test_emit(), input)[0].disabled,
  )
  let waiting = attachment_step(
    model,
    input,
    AttachmentPrepared(
      input.identity,
      request.root,
      request.id,
      Ok(@protocol.AttachmentUploadRequired(name="report.pdf")),
    ),
  )
  let blocked = attachment_step(waiting, input, SubmitRequested)
  assert_true(blocked.active(input).pending_submission is None)
  assert_true(
    waiting
    .active(input)
    .action_buttons(Msg::test_emit(), Action::test_emit(), input)[0].disabled,
  )
  let cancelled = attachment_step(
    waiting,
    input,
    AttachmentCancelled(input.identity, request.root, request.id),
  )
  assert_eq(cancelled.active(input).draft, input.draft)
  assert_true(cancelled.active(input).can_send(input))
  assert_true(cancelled.active(input).attachment_requests.is_empty())
  assert_false(
    cancelled
    .active(input)
    .action_buttons(Msg::test_emit(), Action::test_emit(), input)[0].disabled,
  )
}

///|
test "pending document attachments disable steering while Stop remains available" {
  let base = Input::fixture("steer after attaching the document")
  let input = {
    ..base,
    presentation: {
      ..base.presentation,
      primary_action: Running(
        steer_available=true,
        can_stop=true,
        submit=Steer,
        queue_available=true,
      ),
    },
  }
  let model = attachment_reading(input)
  let request = model.active(input).attachment_requests[0]
  let actions = model
    .active(input)
    .action_buttons(Msg::test_emit(), Action::test_emit(), input)
  assert_eq(actions.map(action => action.id), ["stop", "send"])
  assert_false(actions[0].disabled)
  assert_true(actions[1].disabled)
  let waiting = attachment_step(
    model,
    input,
    AttachmentPrepared(
      input.identity,
      request.root,
      request.id,
      Ok(@protocol.AttachmentUploadRequired(name="report.pdf")),
    ),
  )
  let cancelled = attachment_step(
    waiting,
    input,
    AttachmentCancelled(input.identity, request.root, request.id),
  )
  assert_false(
    cancelled
    .active(input)
    .action_buttons(Msg::test_emit(), Action::test_emit(), input)[1].disabled,
  )
}

///|
test "workspace documents reuse clickable file mentions and retain existing images" {
  let input = {
    ..Input::fixture("inspect"),
    draft: {
      ..Input::fixture("inspect").draft,
      images: [{ name: "old.png", url: "data:image/png;base64,YQ==", }],
    },
  }
  let model = attachment_reading(input)
  let request = model.active(input).attachment_requests[0]
  let ready = attachment_step(
    model,
    input,
    AttachmentPrepared(
      input.identity,
      request.root,
      request.id,
      Ok(@protocol.WorkspaceAttachment(path="docs/report.pdf")),
    ),
  )
  let draft = ready.active(input).draft
  assert_eq(draft.images, input.draft.images)
  assert_true(draft.prompt().contains("<file path=\"docs/report.pdf\"/>"))
  assert_eq(
    @mention_context.target(draft.mentions[0].ref_).map(target => target.file),
    Some("docs/report.pdf"),
  )
  assert_true(ready.active(input).can_send(input))
}

///|
test "document upload starts only once after confirmation and rejects late cancelled replies" {
  let input = Input::fixture("keep")
  let model = attachment_reading(input)
  let request = model.active(input).attachment_requests[0]
  let waiting = attachment_step(
    model,
    input,
    AttachmentPrepared(
      input.identity,
      request.root,
      request.id,
      Ok(@protocol.AttachmentUploadRequired(name="report.pdf")),
    ),
  )
  let confirm = AttachmentConfirmed(input.identity, request.root, request.id)
  let uploading = attachment_step(waiting, input, confirm)
  assert_true(attachment_step(uploading, input, confirm) == uploading)
  assert_false(uploading.active(input).can_send(input))
  let done = AttachmentImported(
    input.identity,
    request.root,
    request.id,
    Ok(".openseek/attachments/id/report.pdf"),
  )
  let ready = attachment_step(uploading, input, done)
  assert_eq(ready.active(input).draft.mentions.length(), 1)
  let cancelled = attachment_step(
    waiting,
    input,
    AttachmentCancelled(input.identity, request.root, request.id),
  )
  assert_true(attachment_step(cancelled, input, done) == cancelled)
  let failure = attachment_step(
    uploading,
    input,
    AttachmentImported(
      input.identity,
      request.root,
      request.id,
      Err("disk full"),
    ),
  )
  assert_eq(failure.active(input).draft, input.draft)
  assert_eq(failure.active(input).image_error, Some("disk full"))
  assert_true(failure.active(input).can_send(input))
}

///|
test "document imports stay scoped to their original conversation and workspace" {
  let input = Input::fixture("original")
  let model = attachment_reading(input)
  let request = model.active(input).attachment_requests[0]
  let waiting = attachment_step(
    model,
    input,
    AttachmentPrepared(
      input.identity,
      request.root,
      request.id,
      Ok(@protocol.AttachmentUploadRequired(name="report.pdf")),
    ),
  )
  let other = {
    ..input,
    identity: {
      ..input.identity,
      owner: @interop.Host({
        ..input.identity.owner.host().unwrap(),
        session: "other",
      }),
    },
  }
  assert_true(
    attachment_step(
      waiting,
      other,
      AttachmentConfirmed(input.identity, request.root, request.id),
    ).active(input).attachment_requests[0].phase
    is AttachmentConfirming(_),
  )
  assert_true(waiting.active(other).draft.mentions.is_empty())
  let changed = { ..input, root: Some(@common.Uri::file("/other-workspace")), }
  let stale = attachment_step(
    waiting,
    changed,
    AttachmentConfirmed(input.identity, request.root, request.id),
  )
  assert_true(stale.active(changed).attachment_requests.is_empty())
  assert_true(stale.active(changed).draft.mentions.is_empty())
  assert_true(stale.active(changed).can_send(changed))
}

///|
test "remote document selections retain bytes for confirmation instead of sending client paths" {
  let input = {
    ..Input::fixture("inspect"),
    identity: {
      owner: @interop.Host({
        channel: @interop.Remote("device"),
        session: "remote",
      }),
      archive_generation: 0,
    },
  }
  let reading = attachment_step(
    Model(input),
    input,
    ImageRead(input.identity, input.root, @image_input.Reading),
  )
  let prepared = attachment_step(
    reading,
    input,
    ImageRead(
      input.identity,
      input.root,
      @image_input.DocumentsReady(images=[], documents=[
        {
          name: "report.pdf",
          data_base64: "JVBERg==",
          native_path: Some("/workspace/report.pdf"),
        },
      ]),
    ),
  )
  assert_true(
    prepared.active(input).attachment_requests[0].source
    is @protocol.AttachmentBytes(name="report.pdf", data_base64="JVBERg=="),
  )
  assert_true(
    prepared.active(input).attachment_requests[0].phase
    is AttachmentConfirming(name="report.pdf"),
  )
}

///|
test "blank Cloud confirms bytes locally and submits them without a workspace or file path" {
  let input = {
    ..Input::fixture(""),
    identity: {
      owner: @interop.Cloud(account="user", session="draft:1"),
      archive_generation: 0,
    },
    root: None,
    cloud_access: Some({ token: "fixture", epoch: 1, }),
  }
  let reading = attachment_step(
    Model(input),
    input,
    ImageRead(input.identity, None, @image_input.Reading),
  )
  let chosen = attachment_step(
    reading,
    input,
    ImageRead(
      input.identity,
      None,
      @image_input.DocumentsReady(images=[], documents=[
        {
          name: "report.pdf",
          data_base64: "JVBERg==",
          native_path: Some("/private/browser/report.pdf"),
        },
      ]),
    ),
  )
  let request = chosen.active(input).attachment_requests[0]
  assert_true(
    request.source is AttachmentBytes(name="report.pdf", data_base64="JVBERg=="),
  )
  assert_false(chosen.active(input).can_send(input))
  let confirmed = attachment_step(
    chosen,
    input,
    AttachmentConfirmed(input.identity, None, request.id),
  )
  assert_true(confirmed.active(input).can_send(input))
  assert_true(
    confirmed.active(input).attachment_requests[0].phase
    is AttachmentStaged(name="report.pdf"),
  )
  let actions : Array[Action] = []
  ignore(
    confirmed.update(input, SubmitRequested, Msg::test_emit(), action => {
      actions.push(action)
      @cmd.none
    }),
  )
  assert_true(
    actions
    is [
      DraftAttachmentsSubmitted(
        draft={ task: "", .. },
        attachments=[AttachmentBytes(name="report.pdf", data_base64="JVBERg==")],
        ..
      ),
    ],
  )
  let removed = attachment_step(
    confirmed,
    input,
    AttachmentCancelled(input.identity, None, request.id),
  )
  assert_true(removed.active(input).attachment_requests.is_empty())
}

///|
test "Cloud import failures keep the selected bytes for an explicit retry" {
  let input = {
    ..Input::fixture("inspect"),
    identity: {
      owner: @interop.Cloud(account="user", session="session"),
      archive_generation: 0,
    },
    cloud_access: Some({ token: "fixture", epoch: 1, }),
  }
  let source = @protocol.AttachmentBytes(
    name="report.pdf",
    data_base64="JVBERg==",
  )
  let (entry, _) = Entry(input).prepare_attachments([source], Msg::test_emit())
  let model = Model(input).with_entry(entry)
  let confirmed = attachment_step(
    model,
    input,
    AttachmentConfirmed(
      input.identity,
      input.root,
      entry.attachment_requests[0].id,
    ),
  )
  let failed = attachment_step(
    confirmed,
    input,
    AttachmentImported(
      input.identity,
      input.root,
      entry.attachment_requests[0].id,
      Err("offline"),
    ),
  )
  assert_eq(failed.active(input).attachment_requests[0].source, source)
  assert_true(
    failed.active(input).attachment_requests[0].phase
    is AttachmentConfirming(name="report.pdf"),
  )
  assert_eq(failed.active(input).image_error, Some("offline"))
  let refreshed = {
    ..input,
    cloud_access: Some({ token: "new-fixture", epoch: 2, }),
  }
  let stale = attachment_step(
    confirmed,
    refreshed,
    AttachmentImported(
      input.identity,
      input.root,
      entry.attachment_requests[0].id,
      Ok("stale.pdf"),
    ),
  )
  assert_true(stale.active(refreshed).draft.mentions.is_empty())
  assert_eq(stale.active(refreshed).attachment_requests[0].source, source)
  assert_true(
    stale.active(refreshed).attachment_requests[0].phase
    is AttachmentConfirming(_),
  )
}

///|
test "running follow-ups submit staged attachments with mixed or attachment-only drafts" {
  let base = Input::fixture("")
  let source = @protocol.AttachmentBytes(
    name="report.pdf",
    data_base64="JVBERg==",
  )
  let mixed : Draft = {
    task: "inspect this report",
    images: [{ name: "chart.png", url: "data:image/png;base64,YQ==", }],
    mentions: [{ ref_: File(path="notes.txt"), range: None, }],
  }
  for submit in [Steer, Queue] {
    for draft in [base.draft, mixed] {
      let input = {
        ..base,
        identity: {
          owner: @interop.Cloud(account="user", session="session"),
          archive_generation: 0,
        },
        draft,
        staged_attachments: [source],
        presentation: {
          ..base.presentation,
          primary_action: Running(
            steer_available=true,
            can_stop=true,
            submit~,
            queue_available=true,
          ),
        },
      }
      let model = Model(input)
      let buttons = model
        .active(input)
        .action_buttons(Msg::test_emit(), Action::test_emit(), input)
      assert_eq(buttons.length(), 2)
      assert_false(buttons[1].disabled)
      let entry = model.active(input)
      for
        blocked_entry in [
          entry.with_attachment_phase(1, AttachmentPreparing),
          entry.with_attachment_phase(
            1,
            AttachmentConfirming(name="report.pdf"),
          ),
          entry.with_attachment_phase(1, AttachmentImporting),
          entry.attachment_failed(1, "offline"),
        ] {
        let unready = model.with_entry(blocked_entry)
        assert_true(
          unready
          .active(input)
          .action_buttons(Msg::test_emit(), Action::test_emit(), input)[1].disabled,
        )
        let blocked : Array[Action] = []
        ignore(
          unready.update(input, SubmitRequested, Msg::test_emit(), action => {
            blocked.push(action)
            @cmd.none
          }),
        )
        assert_true(blocked.is_empty())
      }
      let actions : Array[Action] = []
      let (submitted, _) = model.update(
        input,
        SubmitRequested,
        Msg::test_emit(),
        action => {
          actions.push(action)
          @cmd.none
        },
      )
      guard actions
        is [FollowupSubmitted(identity~, draft=sent, choice~, attachments~)] else {
        fail("expected the existing follow-up action with staged sources")
      }
      assert_eq(identity, input.identity)
      assert_eq(sent, draft)
      assert_eq(choice, if submit is Steer { SteerNow } else { QueueNext })
      assert_eq(attachments, [source])
      assert_eq(submitted.active(input).draft, draft)
      assert_eq(submitted.active(input).attachment_requests.length(), 1)
      let acknowledged = {
        ..input,
        draft: base.draft,
        staged_attachments: [],
        submission_sequence: 1,
      }
      assert_true(submitted.active(acknowledged).draft.is_blank())
      assert_true(submitted.active(acknowledged).attachment_requests.is_empty())
    }
  }
}

///|
test "running follow-up acknowledgement preserves newer draft text images and references" {
  for submit in [Steer, Queue] {
    let base = Input::fixture("submitted text")
    let image : Image = { name: "sent.png", url: "data:image/png;base64,YQ==", }
    let input = {
      ..base,
      identity: {
        owner: @interop.Cloud(account="user", session="session"),
        archive_generation: 0,
      },
      draft: {
        ..base.draft,
        images: [image],
        mentions: [{ ref_: File(path="sent.txt"), range: None, }],
      },
      staged_attachments: [
        @protocol.AttachmentBytes(name="report.pdf", data_base64="JVBERg=="),
      ],
      presentation: {
        ..base.presentation,
        primary_action: Running(
          steer_available=true,
          can_stop=true,
          submit~,
          queue_available=true,
        ),
      },
    }
    let submitted = attachment_step(Model(input), input, SubmitRequested)
    let edited = attachment_step(submitted, input, TextChanged("next draft"))
    let next_image : Image = {
      name: "next.png",
      url: "data:image/png;base64,Yg==",
    }
    let edited = attachment_step(
      edited,
      input,
      ImageRead(input.identity, input.root, @image_input.Reading),
    )
    let edited = attachment_step(
      edited,
      input,
      ImageRead(
        input.identity,
        input.root,
        @image_input.Ready([(next_image.name, next_image.url)]),
      ),
    )
    let next_reference : Mention = { ref_: File(path="next.txt"), range: None, }
    let acknowledged = {
      ..input,
      draft: { task: "", images: [], mentions: [next_reference], },
      staged_attachments: [],
      submission_sequence: 1,
    }
    let entry = edited.active(acknowledged)
    assert_eq(entry.draft.task, "next draft")
    assert_eq(entry.draft.images, [next_image])
    assert_eq(entry.draft.mentions, [next_reference])
    assert_true(entry.attachment_requests.is_empty())
    assert_true(entry.pending_submission is None)
  }
}

///|
test "running follow-ups without staged attachments retain their existing input" {
  let base = Input::fixture("follow-up")
  for submit in [Steer, Queue] {
    for
      draft in [
        base.draft,
        {
          ..base.draft,
          task: "",
          images: [{ name: "chart.png", url: "data:image/png;base64,YQ==", }],
        },
        {
          ..base.draft,
          task: "",
          mentions: [{ ref_: File(path="notes.txt"), range: None, }],
        },
      ] {
      let input = {
        ..base,
        draft,
        presentation: {
          ..base.presentation,
          primary_action: Running(
            steer_available=true,
            can_stop=true,
            submit~,
            queue_available=true,
          ),
        },
      }
      let actions : Array[Action] = []
      ignore(
        Model(input).update(input, SubmitRequested, Msg::test_emit(), action => {
          actions.push(action)
          @cmd.none
        }),
      )
      assert_true(
        actions is [FollowupSubmitted(draft=sent, attachments=[], ..)] &&
        sent == draft,
      )
    }
  }
}

///|
test "Local running attachment readiness remains unchanged" {
  let base = Input::fixture("keep this draft")
  let input = {
    ..base,
    staged_attachments: [
      @protocol.AttachmentBytes(name="report.pdf", data_base64="JVBERg=="),
    ],
    presentation: {
      ..base.presentation,
      primary_action: Running(
        steer_available=true,
        can_stop=true,
        submit=Steer,
        queue_available=true,
      ),
    },
  }
  let model = Model(input)
  assert_false(model.active(input).can_send(input))
  assert_true(
    model
    .active(input)
    .action_buttons(Msg::test_emit(), Action::test_emit(), input)[1].disabled,
  )
  let actions : Array[Action] = []
  ignore(
    model.update(input, SubmitRequested, Msg::test_emit(), action => {
      actions.push(action)
      @cmd.none
    }),
  )
  assert_true(actions.is_empty())
  assert_eq(model.active(input).draft, base.draft)
}

///|
test "idle queue editing reuses draft submission without Stop or follow-up controls" {
  let base = Input::fixture("Edited queue")
  let input = {
    ..base,
    presentation: {
      ..base.presentation,
      primary_action: SaveQueuedInput(available=true),
    },
  }
  let model = Model(input)
  let buttons = model
    .active(input)
    .action_buttons(Msg::test_emit(), Action::test_emit(), input)
  assert_eq(buttons.length(), 1)
  assert_eq(buttons[0].id, "send")
  assert_eq(buttons[0].title, "Save queued message")
  assert_false(buttons[0].disabled)
  let actions : Array[Action] = []
  let (submitted, _) = model.update(input, SubmitRequested, Msg::test_emit(), action => {
    actions.push(action)
    @cmd.none
  })
  assert_true(
    actions is [DraftSubmitted(draft={ task: "Edited queue", .. }, ..)],
  )
  let edited = attachment_step(submitted, input, TextChanged("Next draft"))
  let acknowledged = {
    ..input,
    draft: { task: "", images: [], mentions: [], },
    submission_sequence: 1,
  }
  assert_eq(edited.active(acknowledged).draft.task, "Next draft")
}

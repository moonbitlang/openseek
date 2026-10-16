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
      owner: { ..input.identity.owner, session: "other", },
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
      owner: { ..input.identity.owner, session: "other", },
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
      owner: { channel: @interop.Remote("device"), session: "remote", },
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

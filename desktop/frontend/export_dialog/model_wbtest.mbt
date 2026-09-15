///|
test "dialog updates are pure and late replies cannot cross openings" {
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let source : @protocol.SessionExportPayload = {
    session: "a",
    workspace: "/workspace",
    title: "Conversation A",
    archived: false,
  }
  let model = Model()
  let (_, first) = model.open(source)
  let (_, again) = model.open(source)
  assert_true(first == again)
  assert_true(model.content is None)
  let messages : Array[Msg] = [
    Download,
    Share,
    SignIn,
    Close,
    Published(generation=first.generation, SignInRequired),
    Downloaded(generation=first.generation, Err("failed")),
    SignedIn(generation=first.generation, Ok(())),
    ClipboardFinished(generation=first.generation, Ok(())),
  ]
  for msg in messages {
    let (_, a) = first.update(emit, msg)
    let (_, b) = first.update(emit, msg)
    assert_true(a == b)
  }
  let (_, pending) = first.update(emit, Share)
  assert_true(pending.content is Some({ operation: Sharing, .. }))
  for msg in [Share, Download, SignIn] {
    let (_, ignored) = pending.update(emit, msg)
    assert_true(ignored == pending)
  }
  let (_, closed) = pending.update(emit, Close)
  let reply = Published(
    generation=first.generation,
    Shared(url="https://shares.test/v1/shares/a"),
  )
  let (_, late) = closed.update(emit, reply)
  assert_true(late == closed)
  let (_, other) = closed.open({
    ..source,
    session: "b",
    title: "Conversation B",
  })
  let (_, other_pending) = other.update(emit, Share)
  let (_, stale) = other_pending.update(emit, reply)
  assert_true(stale == other_pending)
  assert_true(stale.content is Some({ source: { session: "b", .. }, .. }))
}

///|
test "share login failure success and clipboard feedback transitions" {
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let (_, open) = Model().open({
    session: "a",
    workspace: "/workspace",
    title: "A",
    archived: true,
  })
  let (_, pending) = open.update(emit, Share)
  for
    reply in [
      @protocol.SignInRequired,
      @protocol.Failed(message="Storage unavailable"),
      @protocol.Shared(url="http://shares.test/a"),
    ] {
    let msg = Published(generation=pending.generation, reply)
    let (_, first) = pending.update(emit, msg)
    let (_, again) = pending.update(emit, msg)
    assert_true(first == again)
    match first.content {
      Some({ operation: SignInRequired, .. }) => {
        let (_, signing_in) = first.update(emit, SignIn)
        let (_, signing_in_again) = first.update(emit, SignIn)
        assert_true(signing_in == signing_in_again)
        assert_true(signing_in.content is Some({ operation: SigningIn, .. }))
        for result in [Ok(()), Err("Cancelled")] {
          let signed_in = SignedIn(generation=first.generation, result)
          let (_, done) = signing_in.update(emit, signed_in)
          let (_, again) = signing_in.update(emit, signed_in)
          assert_true(done == again)
          assert_true(
            done.content is Some({ operation: Ready | SignInFailed(_), .. }),
          )
          if result is Err(message) {
            guard done.content is Some({ operation: SignInFailed(detail), .. }) else {
              fail("expected sign-in failure with its diagnostic")
            }
            assert_eq(detail, message)
            let (_, retry) = done.update(emit, SignIn)
            assert_true(retry.content is Some({ operation: SigningIn, .. }))
          }
        }
      }
      Some({ publication: Some(_), .. }) => {
        let (_, downloading) = first.update(emit, Download)
        let (_, downloaded) = downloading.update(
          emit,
          Downloaded(
            generation=first.generation,
            Ok({ path: None, opened: false, }),
          ),
        )
        assert_true(
          downloaded.content
          is Some(
            {
              publication: Some({ url: "http://shares.test/a", .. }),
              operation: Ready,
              ..
            }
          ),
        )
        let (_, duplicate) = first.update(emit, Share)
        assert_true(duplicate == first)
        for result in [Ok(()), Err("Clipboard denied")] {
          let copied = ClipboardFinished(generation=first.generation, result)
          let (_, done) = first.update(emit, copied)
          let (_, again) = first.update(emit, copied)
          assert_true(done == again)
          assert_true(
            done.content
            is Some({ publication: Some({ copy: Copied | Failed(_), .. }), .. }),
          )
        }
      }
      Some({ operation: Failed("Storage unavailable"), .. }) => {
        let (_, retry) = first.update(emit, Share)
        assert_true(retry.content is Some({ operation: Sharing, .. }))
      }
      _ => fail("unexpected publication state")
    }
  }
}

///|
test "download cancellation and saved but not opened remain distinct" {
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let (_, open) = Model().open({
    session: "a",
    workspace: "/workspace",
    title: "A",
    archived: false,
  })
  let (_, pending) = open.update(emit, Download)
  for
    result in [
      Ok(@protocol.SessionExportReply::{ path: None, opened: false, }),
      Ok({ path: Some("/exports/a.html"), opened: false, }),
      Ok({ path: Some("/exports/a.html"), opened: true, }),
      Err("No access"),
    ] {
    let msg = Downloaded(generation=pending.generation, result)
    let (_, done) = pending.update(emit, msg)
    let (_, again) = pending.update(emit, msg)
    assert_true(done == again)
    match result {
      Ok({ path: None, .. }) =>
        assert_true(done.content is Some({ operation: Ready, .. }))
      Ok({ opened: false, .. }) =>
        assert_true(
          done.content is Some({ operation: Saved(opened=false, ..), .. }),
        )
      Ok(_) =>
        assert_true(
          done.content is Some({ operation: Saved(opened=true, ..), .. }),
        )
      Err(_) =>
        assert_true(
          done.content is Some({ operation: Failed("No access"), .. }),
        )
    }
  }
}

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
    let (_, a) = first.advance(emit, msg)
    let (_, b) = first.advance(emit, msg)
    assert_true(a == b)
  }
  let (_, pending) = first.advance(emit, Share)
  assert_true(pending.content is Some({ operation: Sharing(_), .. }))
  for msg in [Share, Download, SignIn] {
    let (_, ignored) = pending.advance(emit, msg)
    assert_true(ignored == pending)
  }
  let (_, closed) = pending.advance(emit, Close)
  let reply = Published(
    generation=pending.generation,
    Shared(url="https://shares.test/v1/shares/a"),
  )
  let (_, late) = closed.advance(emit, reply)
  assert_true(late == closed)
  let (_, other) = closed.open({
    ..source,
    session: "b",
    title: "Conversation B",
  })
  let (_, other_pending) = other.advance(emit, Share)
  let (_, stale) = other_pending.advance(emit, reply)
  assert_true(stale == other_pending)
  assert_true(
    stale.content is Some({ source: Host(_, { session: "b", .. }), .. }),
  )
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
  let (_, pending) = open.advance(emit, Share)
  for
    reply in [
      @protocol.SignInRequired,
      @protocol.Failed(message="Storage unavailable"),
      @protocol.Shared(url="http://shares.test/a"),
    ] {
    let msg = Published(generation=pending.generation, reply)
    let (_, first) = pending.advance(emit, msg)
    let (_, again) = pending.advance(emit, msg)
    assert_true(first == again)
    match first.content {
      Some({ operation: SignInRequired, .. }) => {
        let (_, signing_in) = first.advance(emit, SignIn)
        let (_, signing_in_again) = first.advance(emit, SignIn)
        assert_true(signing_in == signing_in_again)
        assert_true(signing_in.content is Some({ operation: SigningIn, .. }))
        for result in [Ok(()), Err("Cancelled")] {
          let signed_in = SignedIn(generation=first.generation, result)
          let (_, done) = signing_in.advance(emit, signed_in)
          let (_, again) = signing_in.advance(emit, signed_in)
          assert_true(done == again)
          assert_true(
            done.content is Some({ operation: Ready | SignInFailed(_), .. }),
          )
          if result is Err(message) {
            guard done.content is Some({ operation: SignInFailed(detail), .. }) else {
              fail("expected sign-in failure with its diagnostic")
            }
            assert_eq(detail, message)
            let (_, retry) = done.advance(emit, SignIn)
            assert_true(retry.content is Some({ operation: SigningIn, .. }))
          }
        }
      }
      Some({ publication: Some(_), .. }) => {
        let (_, downloading) = first.advance(emit, Download)
        let (_, downloaded) = downloading.advance(
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
        let (_, duplicate) = first.advance(emit, Share)
        assert_true(duplicate == first)
        for result in [Ok(()), Err("Clipboard denied")] {
          let copied = ClipboardFinished(generation=first.generation, result)
          let (_, done) = first.advance(emit, copied)
          let (_, again) = first.advance(emit, copied)
          assert_true(done == again)
          assert_true(
            done.content
            is Some({ publication: Some({ copy: Copied | Failed(_), .. }), .. }),
          )
        }
      }
      Some({ operation: Failed("Storage unavailable"), .. }) => {
        let (_, retry) = first.advance(emit, Share)
        assert_true(retry.content is Some({ operation: Sharing(_), .. }))
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
  let (_, pending) = open.advance(emit, Download)
  for
    result in [
      Ok(@protocol.SessionExportReply::{ path: None, opened: false, }),
      Ok({ path: Some("/exports/a.html"), opened: false, }),
      Ok({ path: Some("/exports/a.html"), opened: true, }),
      Err("No access"),
    ] {
    let msg = Downloaded(generation=pending.generation, result)
    let (_, done) = pending.advance(emit, msg)
    let (_, again) = pending.advance(emit, msg)
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

///|
fn Model::advance(
  self : Model,
  emit : @cmd.Emit[Msg],
  msg : Msg,
) -> (@cmd.Cmd, Model) {
  self.update(emit, msg, account={
    token: "ts_fixture",
    user: { user_id: "123", login: "octocat", avatar_url: "", },
  })
}

///|
test "sharing without an account requests login and never uploads automatically" {
  let emit : @cmd.Emit[Msg] = _ => @cmd.none
  let (_, opened) = Model().open({
    session: "a",
    workspace: "/workspace",
    title: "A",
    archived: false,
  })
  let (_, refused) = opened.update(emit, Share)
  assert_true(refused.content is Some({ operation: SignInRequired, .. }))
  let (_, signing_in) = refused.update(emit, SignIn)
  let (_, ready) = signing_in.account_changed(Ok(()))
  assert_true(
    ready.content is Some({ operation: Ready, publication: None, .. }),
  )
  let (_, retired) = ready.account_changed(Ok(()))
  assert_false(
    retired.account_expired(
      Published(generation=opened.generation, @protocol.SignInRequired),
    ),
  )
  assert_false(retired.is_open())
}

///|
test "progress is pure and belongs only to the current upload" {
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let (_, opened) = Model().open({
    session: "a",
    workspace: "/workspace",
    title: "A",
    archived: false,
  })
  let (_, pending) = opened.advance(emit, Share)
  for
    progress in [
      @protocol.Preparing,
      Connecting(attempt=1),
      Uploading(attempt=1),
      Waiting(attempt=1),
      Connecting(attempt=2),
      Uploading(attempt=2),
    ] {
    let msg = Progress({ generation: pending.generation, progress, })
    let (_, first) = pending.advance(emit, msg)
    let (_, again) = pending.advance(emit, msg)
    assert_true(first == again)
    assert_true(
      first.content is Some({ operation: Sharing(actual), .. }) &&
      actual == progress,
    )
    let (_, ignored) = opened.advance(emit, msg)
    assert_true(ignored == opened)
  }
  let late = Progress({
    generation: pending.generation,
    progress: Waiting(attempt=1),
  })
  let (_, failed) = pending.update(
    emit,
    Published(generation=pending.generation, Failed(message="offline")),
  )
  let (_, retry) = failed.advance(emit, Share)
  let (_, ignored) = retry.advance(emit, late)
  assert_true(ignored == retry)
  let (_, closed) = pending.advance(emit, Close)
  let (_, ignored) = closed.advance(emit, late)
  assert_true(ignored == closed)
  let (_, done) = pending.update(
    emit,
    Published(generation=pending.generation, Shared(url="https://share.test/a")),
  )
  let (_, ignored) = done.advance(emit, late)
  assert_true(ignored == done)
}

///|
test "host progress belongs to both the selected source channel and current opening" {
  let emit : @cmd.Emit[Msg] = _ => @cmd.none
  let channel = @interop.ChannelId::Remote("selected-host")
  let (_, opened) = Model().open(
    {
      session: "session",
      workspace: "/workspace",
      title: "Title",
      archived: false,
    },
    channel~,
  )
  let (_, pending) = opened.advance(emit, Share)
  for
    (owner, generation) in [
      (@interop.Local, pending.generation),
      (channel, pending.generation - 1),
    ] {
    let (_, ignored) = pending.update(
      emit,
      HostProgress(owner, { generation, progress: Uploading(attempt=2), }),
    )
    assert_true(ignored == pending)
  }
  let (_, updated) = pending.update(
    emit,
    HostProgress(channel, {
      generation: pending.generation,
      progress: Uploading(attempt=2),
    }),
  )
  assert_true(
    updated.content is Some({ operation: Sharing(Uploading(attempt=2)), .. }),
  )
}

///|
test "the local debug console explains sharing is unsupported without requesting login" {
  let emit : @cmd.Emit[Msg] = _ => @cmd.none
  let (_, opened) = Model().open(
    {
      session: "session",
      workspace: "/workspace",
      title: "Title",
      archived: false,
    },
    channel=Remote("host"),
  )
  let (_, refused) = opened.update(emit, Share, desktop=false)
  assert_true(
    refused.content is Some({ operation: Failed(message), .. }) &&
    message.contains("SeekMoonDev.app"),
  )
  let (_, downloading) = refused.update(emit, Download, desktop=false)
  assert_true(downloading.content is Some({ operation: Downloading, .. }))
}

///|
test "file sharing survives dismissal and reopening without starting another operation" {
  let emit : @cmd.Emit[Msg] = _ => @cmd.none
  let source = HostFile(@interop.Local, {
    root: Some("/workspace"),
    path: "report.bin",
  })
  let (_, opened) = Model().open_file(source)
  let (_, pending) = opened.advance(emit, Share)
  let (_, hidden) = pending.advance(emit, Close)
  assert_false(hidden.is_open())
  assert_true(hidden.file_pending())
  let (_, reopened) = hidden.open_file(source)
  assert_eq(reopened.generation, pending.generation)
  let (_, duplicate) = reopened.advance(emit, Share)
  assert_true(duplicate == reopened)
  let (_, hidden) = reopened.advance(emit, Close)
  let (_, finished) = hidden.advance(
    emit,
    Published(
      generation=hidden.generation,
      Shared(url="https://shares.test/file"),
    ),
  )
  assert_false(finished.is_open())
  let (_, reopened) = finished.open_file(source)
  let (_, duplicate) = reopened.advance(emit, Share)
  assert_true(duplicate == reopened)
  assert_true(
    reopened.content
    is Some({ publication: Some({ url: "https://shares.test/file", .. }), .. }),
  )
  let (_, closed) = reopened.advance(emit, Close)
  let (_, next) = closed.open_file(source)
  assert_true(next.generation > reopened.generation)
  assert_true(next.content is Some({ publication: None, .. }))
}

///|
test "file share failures allow explicit retry and account changes fence hidden responses" {
  let emit : @cmd.Emit[Msg] = _ => @cmd.none
  let (_, opened) = Model().open_file(
    CloudFile(account="123", session="cloud", path="data.bin"),
  )
  let (_, pending) = opened.advance(emit, Share)
  let (_, failed) = pending.advance(
    emit,
    Published(generation=pending.generation, Failed(message="offline")),
  )
  assert_false(failed.file_pending())
  let (_, retry) = failed.advance(emit, Share)
  assert_true(retry.generation > failed.generation)
  let (_, hidden) = retry.advance(emit, Close)
  let (_, changed) = hidden.account_changed(Ok(()))
  let (_, late) = changed.advance(
    emit,
    Published(
      generation=retry.generation,
      Shared(url="https://shares.test/old"),
    ),
  )
  assert_true(late == changed)
  assert_false(late.is_open())
  assert_true(late.content is None)
}

///|
test "file sharing uses the existing explicit sign-in and confirmation flow" {
  let emit : @cmd.Emit[Msg] = _ => @cmd.none
  let (_, opened) = Model().open_file(
    HostFile(@interop.Local, { root: Some("/workspace"), path: "file.bin", }),
  )
  let (_, needs_login) = opened.update(emit, Share)
  assert_true(needs_login.content is Some({ operation: SignInRequired, .. }))
  let (_, signing_in) = needs_login.update(emit, SignIn)
  let (_, signed_in) = signing_in.account_changed(Ok(()))
  assert_true(signed_in.content is Some({ operation: Ready, .. }))
  assert_false(signed_in.file_pending())
}

///|
test "history updates are pure and stale completions cannot reopen a dialog" {
  let emit : @cmd.Emit[@session_import.Msg] = @cmd.Emit(_ => @cmd.none)
  let initial = @session_import.Model()
  let (_, opened) = initial.open(target())
  let ready = opened
  assert_true(ready.is_open())
  assert_false(initial.is_open())
  let (_, typed, _) = ready.update(
    emit,
    LinkChanged("https://example/v1/shares/sh_a"),
  )
  let (_, pending, _) = typed.update(emit, ImportLink)
  let (_, repeated, _) = typed.update(emit, ImportLink)
  assert_true(pending == repeated)
  let (_, duplicate, _) = pending.update(emit, ImportLink)
  assert_true(duplicate == pending)
  let (_, closed, _) = pending.update(emit, Close)
  let (_, stale, _) = closed.update(emit, Imported(2, Ok("import-1")))
  assert_true(stale == closed)
  let (_, next) = closed.open(
    Host({ ..host_target(), channel: Remote("other-device"), }),
  )
  let (_, stale, _) = next.update(emit, Imported(2, Ok("import-1")))
  assert_true(stale == next)
}

///|
test "cancelled file selection returns to ready and errors permit retry" {
  let emit : @cmd.Emit[@session_import.Msg] = @cmd.Emit(_ => @cmd.none)
  let (_, opened) = @session_import.Model().open(target())
  let ready = opened
  let (_, choosing, _) = ready.update(emit, PickFile)
  let (_, canceled, _) = choosing.update(emit, Picked(2, Ok(None)))
  let (_, choosing_again, _) = canceled.update(emit, PickFile)
  assert_true(choosing_again != canceled)
  let (_, failed, _) = choosing_again.update(
    emit,
    Picked(3, Err(@session_import.Diagnostic("Cannot read file"))),
  )
  let (_, retry, _) = failed.update(emit, PickFile)
  assert_true(retry != failed)
  let (_, duplicate, _) = failed.update(emit, PickFile)
  assert_true(retry == duplicate)
}

///|
test "a Cloud import reports its account and new session, and failures stay retryable" {
  let emit : @cmd.Emit[@session_import.Msg] = @cmd.Emit(_ => @cmd.none)
  let target : @session_import.Target = Cloud(account="user-1")
  let (_, opened) = @session_import.Model().open(target)
  let (_, typed, _) = opened.update(
    emit,
    LinkChanged("https://example/v1/shares/sh_a"),
  )
  let (_, pending, _) = typed.update(emit, ImportLink)
  let (_, failed, imported) = pending.update(
    emit,
    Imported(
      2,
      Err(
        @session_import.Cloud(
          @cloud_client.RemoteMessage(
            "Only Cloud exports can be imported here.",
          ),
        ),
      ),
    ),
  )
  assert_eq(imported, None)
  assert_true(failed.is_open())
  let (_, retrying, _) = failed.update(emit, ImportLink)
  assert_true(retrying != failed)
  let (_, done, imported) = retrying.update(emit, Imported(3, Ok("cloud-1")))
  assert_false(done.is_open())
  assert_eq(imported, Some((target, "cloud-1")))
}

///|
fn host_target() -> @session_import.HostTarget {
  {
    channel: Local,
    connection_generation: 1,
    workspace: "/workspace",
    worktree_of: None,
  }
}

///|
fn target() -> @session_import.Target {
  Host(host_target())
}

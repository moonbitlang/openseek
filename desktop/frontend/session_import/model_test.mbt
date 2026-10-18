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
  assert_eq(pending, repeated)
  let (_, duplicate, _) = pending.update(emit, ImportLink)
  assert_eq(duplicate, pending)
  let (_, closed, _) = pending.update(emit, Close)
  let (_, stale, _) = closed.update(emit, Imported(2, Success("import-1")))
  assert_eq(stale, closed)
  let (_, next) = closed.open({ ..target(), channel: Remote("other-device"), })
  let (_, stale, _) = next.update(emit, Imported(2, Success("import-1")))
  assert_eq(stale, next)
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
    Picked(3, Err("Cannot read file")),
  )
  let (_, retry, _) = failed.update(emit, PickFile)
  assert_true(retry != failed)
  let (_, duplicate, _) = failed.update(emit, PickFile)
  assert_eq(retry, duplicate)
}

///|
fn target() -> @session_import.Target {
  {
    channel: Local,
    connection_generation: 1,
    workspace: Registered("/workspace"),
    worktree_of: None,
  }
}

///|
test "workspace progress is pure, survives failure and ignores stale completion" {
  let emit : @cmd.Emit[@session_import.Msg] = @cmd.Emit(_ => @cmd.none)
  for workspace in [@session_import.Allocated("/chat"), Registered("/chat")] {
    let (_, opened) = @session_import.Model().open({
      ..target(),
      workspace: Unplaced,
    })
    let (_, typed, _) = opened.update(
      emit,
      LinkChanged("https://example/v1/shares/sh_a"),
    )
    let (_, pending, _) = typed.update(emit, ImportLink)
    let progress = @session_import.WorkspaceChanged(2, workspace)
    let (_, ready, _) = pending.update(emit, progress)
    let (_, repeated, _) = pending.update(emit, progress)
    assert_eq(ready, repeated)
    let (_, failed, _) = ready.update(emit, Imported(2, Failed("retry")))
    let (_, retry, _) = failed.update(emit, ImportLink)
    let (_, _, outcome) = retry.update(emit, Imported(3, Success("imported")))
    guard outcome is Some((target, _)) else {
      fail("expected completed import")
    }
    assert_eq(target.workspace, workspace)
    let (_, closed, _) = pending.update(emit, Close)
    let (_, stale, _) = closed.update(emit, progress)
    assert_eq(stale, closed)
    let (_, reopened) = closed.open({ ..target, workspace: Unplaced, })
    let (_, stale, _) = reopened.update(emit, progress)
    assert_eq(stale, reopened)
  }
}

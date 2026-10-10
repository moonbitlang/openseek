///|
test "restoring a draft with pending context is pure and retains other drafts" {
  let emit : @cmd.Emit[@codex.Msg] = @cmd.Emit(_ => @cmd.none)
  let channel = @interop.ChannelId::Local
  let (_, first) = @codex.update(
    emit,
    @codex.Msg::start_draft("draft-a", "/project-a"),
    @codex.State(),
    channel,
    _ => @cmd.none,
  )
  let (_, second) = @codex.update(
    emit,
    @codex.Msg::start_draft("draft-b", "/project-b"),
    first,
    channel,
    _ => @cmd.none,
  )
  guard second.restore_navigation_draft(emit, channel, "draft-a")
    is Some((_, restored)) else {
    fail("expected retained draft A")
  }
  guard second.restore_navigation_draft(emit, channel, "draft-a")
    is Some((_, repeated)) else {
    fail("expected repeatable restoration")
  }
  assert_true(restored == repeated)
  assert_eq(restored.active_id(), Some("draft-a"))
  assert_eq(second.active_id(), Some("draft-b"))
  assert_true(restored.is_busy())
  assert_true(
    restored.restore_navigation_draft(emit, channel, "draft-b") is Some(_),
  )
  assert_true(second.restore_navigation_draft(emit, channel, "missing") is None)
}

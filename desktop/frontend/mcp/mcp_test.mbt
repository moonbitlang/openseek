///|
fn quiet() -> @cmd.Emit[@mcp.Msg] {
  Emit(_ => @cmd.none)
}

///|
fn conversation(session : String) -> @interop.ConversationKey {
  { channel: Local, session, }
}

///|
fn answer() -> @protocol.McpStatusReply {
  Running({
    configs: [{ path: "/home/.openseek/mcp.json", state: Loaded, }],
    servers: [
      { name: "playwright", transport: Stdio, target: "npx", state: NoTools, },
    ],
  })
}

///|
test "opening the panel asks the conversation's engine, every time" {
  let one = conversation("s-1")
  let (_, checking) = @mcp.update(quiet(), Opened(one), @mcp.State::initial())
  assert_true(checking.phase is Checking)
  assert_true(checking.conversation == Some(one))
  let (_, loaded) = @mcp.update(
    quiet(),
    Checked(serial=checking.serial, Ok(answer())),
    checking,
  )
  assert_true(loaded.phase is Loaded(reply) && reply == answer())
  // The answer is the engine's latest report, and asking starts nothing, so
  // reopening the panel asks again — with the last answer on show meanwhile.
  let (_, reopened) = @mcp.update(quiet(), Opened(one), loaded)
  assert_true(reopened.phase is Reloading(reply) && reply == answer())
  assert_true(reopened.serial != loaded.serial)
  // A question already out is not asked twice.
  let (_, again) = @mcp.update(quiet(), Opened(one), reopened)
  assert_true(again == reopened)
}

///|
test "the answer to a superseded question is dropped" {
  let (_, first) = @mcp.update(
    quiet(),
    Opened(conversation("s-1")),
    @mcp.State::initial(),
  )
  let (_, second) = @mcp.update(quiet(), Opened(conversation("s-2")), first)
  let (_, stale) = @mcp.update(
    quiet(),
    Checked(serial=first.serial, Ok(answer())),
    second,
  )
  assert_true(stale == second)
  let (_, settled) = @mcp.update(
    quiet(),
    Checked(serial=second.serial, Err("device offline")),
    second,
  )
  assert_true(settled.phase is CheckFailed("device offline"))
  // An answer cannot arrive twice.
  let (_, again) = @mcp.update(
    quiet(),
    Checked(serial=second.serial, Ok(answer())),
    settled,
  )
  assert_true(again == settled)
}

///|
test "refresh asks again, but never while a question is out" {
  let one = conversation("s-1")
  let (_, checking) = @mcp.update(quiet(), Opened(one), @mcp.State::initial())
  let (_, still) = @mcp.update(quiet(), Refresh(one), checking)
  assert_true(still == checking)
  let (_, failed) = @mcp.update(
    quiet(),
    Checked(serial=checking.serial, Err("engine did not answer")),
    checking,
  )
  let (_, retried) = @mcp.update(quiet(), Refresh(one), failed)
  assert_true(retried.phase is Checking)
  assert_true(retried.serial != failed.serial)
  assert_true(retried.conversation == Some(one))
}

///|
test "an answer is shown only for the conversation whose engine gave it" {
  let one = conversation("s-1")
  let two = conversation("s-2")
  let (_, checking) = @mcp.update(quiet(), Opened(one), @mcp.State::initial())
  let (_, loaded) = @mcp.update(
    quiet(),
    Checked(serial=checking.serial, Ok(answer())),
    checking,
  )
  assert_true(loaded.phase_for(one) is Loaded(_))
  // Another conversation has its own engine.
  assert_true(loaded.phase_for(two) is Unchecked)
  // The same session id on another host is another conversation.
  assert_true(
    loaded.phase_for({ channel: Remote("device-a"), session: "s-1", })
    is Unchecked,
  )
  let (_, asked) = @mcp.update(quiet(), Refresh(two), loaded)
  assert_true(asked.phase_for(two) is Checking)
  assert_true(asked.phase_for(one) is Unchecked)
}

///|
test "an engine's report makes the panel read again without blanking it" {
  let one = conversation("s-1")
  let (_, checking) = @mcp.update(quiet(), Opened(one), @mcp.State::initial())
  let (_, loaded) = @mcp.update(
    quiet(),
    Checked(serial=checking.serial, Ok(answer())),
    checking,
  )
  // The last answer stays on show while its replacement is fetched.
  let (_, reloading) = @mcp.update(quiet(), Changed(one), loaded)
  assert_true(reloading.phase is Reloading(reply) && reply == answer())
  assert_true(reloading.serial != loaded.serial)
  // A question is out, so a refresh has nothing to add.
  let (_, still) = @mcp.update(quiet(), Refresh(one), reloading)
  assert_true(still == reloading)
  let newer : @protocol.McpStatusReply = Running({ configs: [], servers: [], })
  let (_, settled) = @mcp.update(
    quiet(),
    Checked(serial=reloading.serial, Ok(newer)),
    reloading,
  )
  assert_true(settled.phase is Loaded(reply) && reply == newer)
}

///|
test "a report supersedes a question that may have been answered before it" {
  let one = conversation("s-1")
  let (_, checking) = @mcp.update(quiet(), Opened(one), @mcp.State::initial())
  let (_, asked_again) = @mcp.update(quiet(), Changed(one), checking)
  assert_true(asked_again.phase is Checking)
  assert_true(asked_again.serial != checking.serial)
  // The first question's answer — an engine still connecting — is stale.
  let (_, stale) = @mcp.update(
    quiet(),
    Checked(serial=checking.serial, Ok(Connecting)),
    asked_again,
  )
  assert_true(stale == asked_again)
  let (_, settled) = @mcp.update(
    quiet(),
    Checked(serial=asked_again.serial, Ok(answer())),
    asked_again,
  )
  assert_true(settled.phase is Loaded(reply) && reply == answer())
}

///|
test "a report from an engine the panel is not showing changes nothing" {
  let one = conversation("s-1")
  let initial = @mcp.State::initial()
  // The panel has never opened: there is nothing to keep current.
  let (_, untouched) = @mcp.update(quiet(), Changed(one), initial)
  assert_true(untouched == initial)
  let (_, checking) = @mcp.update(quiet(), Opened(one), initial)
  let (_, loaded) = @mcp.update(
    quiet(),
    Checked(serial=checking.serial, Ok(answer())),
    checking,
  )
  let (_, other) = @mcp.update(quiet(), Changed(conversation("s-2")), loaded)
  assert_true(other == loaded)
  // The same session id on another host is another conversation.
  let (_, remote) = @mcp.update(
    quiet(),
    Changed({ channel: Remote("device-a"), session: "s-1", }),
    loaded,
  )
  assert_true(remote == loaded)
}

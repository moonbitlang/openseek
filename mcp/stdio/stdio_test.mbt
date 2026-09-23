///|
async test "connect raises when the command cannot start" {
  @async.with_task_group(group => {
    try
      @stdio.connect(
        group,
        command="openseek-no-such-mcp-server-xyz",
        args=[],
        client_name="openseek",
        client_version="0.1",
      )
    catch {
      _ => ()
    } noraise {
      _ => fail("expected connect to raise when the command cannot start")
    }
  })
}

///|
/// A child that starts but never answers `initialize` must not hang connect: it
/// raises at the deadline (and tears the process down).
async test "connect times out a server that never handshakes" {
  @async.with_task_group(group => {
    try
      @stdio.connect(
        group,
        command="sh",
        args=["-c", "sleep 30"],
        client_name="openseek",
        client_version="0.1",
        handshake_timeout_ms=500,
      )
    catch {
      _ => ()
    } noraise {
      _ => fail("connect should timeout a server that never handshakes")
    }
  })
}

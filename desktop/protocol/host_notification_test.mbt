///|
test "desktop adapts service notifications without changing wire payloads" {
  let source = @protocol.HostNotification::TerminalOutput({
    id: "pty-1",
    sequence: 7,
    data: "5Lit",
  })
  let event = @protocol.Notification::from_host(source)
  assert_eq(event.wire_name(), source.wire_name())
  assert_eq(event.params(), source.params())
  assert_eq(
    @protocol.Notification::from_wire(source.wire_name(), source.params()),
    Some(event),
  )
  assert_true(
    @protocol.Notification::from_wire("auth.changed", { "connected": false })
    is Some(AuthChanged(_)),
  )
}

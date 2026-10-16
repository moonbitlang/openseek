///|
test "connections without a terminal runtime allocate no terminal state" {
  let connection = HostConnection()
  assert_true(connection.terminal is None)
  connection.close_terminals()
}

///|
async test "connection terminal pump forwards output and joins its PTY on close" {
  @async.with_timeout(2000, () => {
    @async.with_task_group(group => {
      let output : @async.Queue[Unit] = Queue(kind=Blocking(1))
      let events : @async.Queue[@protocol.HostNotification] = Queue(
        kind=Blocking(2),
      )
      let joined = Ref(false)
      let connection = HostConnection(runtime={
        spawn_pty: (owner, _, _, _, _, _) => {
          owner.add_defer(() => joined.val = true)
          {
            pid: 42,
            read: buffer => {
              output.get()
              buffer[0] = b'X'
              1
            },
            write: _ => (),
            resize: (_, _) => (),
            wait: () => {
              assert_true(joined.val)
              137
            },
          }
        },
      })
      guard connection.terminal is Some(terminal) else {
        fail("embedded connection must own terminal state")
      }
      let pump = group.spawn(() => {
        connection.run(event => events.put(event), _ => ())
      })
      let id = @terminal.open_terminal(
        terminal,
        cwd="/unused",
        cols=80,
        rows=24,
        command=["unused"],
      )
      output.put(())
      guard events.get() is TerminalOutput(event) else {
        fail("missing connection-owned terminal output")
      }
      assert_eq(event.id, id)
      assert_eq(event.sequence, 1)
      assert_eq(event.data, "WA==")
      connection.close_terminals()
      guard events.get() is TerminalExit(event) else {
        fail("missing terminal exit after close")
      }
      assert_eq(event.id, id)
      assert_eq(event.code, 137)
      assert_true(joined.val)
      pump.cancel()
      pump.wait() catch {
        @async.WaitedTaskAlreadyCancelled => ()
        error => raise error
      }
    })
  })
}

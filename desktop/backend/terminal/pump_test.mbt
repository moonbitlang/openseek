///|
priv suberror BrokenPty

///|
async test "PTY transport failures never become a fabricated exit notification" {
  for stage in ["read", "wait"] {
    @async.with_timeout(1000, () => {
      @async.with_task_group(group => {
        let release : @async.Queue[Unit] = Queue(kind=Blocking(1))
        let runtime : @runtime.HostRuntime = {
          spawn_pty: (_, _, _, _, _, _) => {
            pid: 42,
            read: _ => {
              release.get()
              if stage == "read" {
                raise BrokenPty
              }
              0
            },
            write: _ => (),
            resize: (_, _) => (),
            wait: () => raise BrokenPty,
          },
        }
        let state = @terminal.new_terminal_state(runtime~)
        defer state.shutdown()
        let pushes : Array[@terminal.TerminalPush] = []
        let pump = group.spawn(allow_failure=true, () => {
          @terminal.run_terminal_pump(state, push => pushes.push(push))
        })
        ignore(
          @terminal.open_terminal(state, cwd="/unused", cols=80, rows=24, command=[
            "unused",
          ]),
        )
        release.put(())
        let failed = try {
          pump.wait()
          false
        } catch {
          BrokenPty => true
          error => raise error
        }
        assert_true(failed)
        assert_true(pushes.is_empty())
      })
    })
  }
}

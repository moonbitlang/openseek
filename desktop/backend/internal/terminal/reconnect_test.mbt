///|
#cfg(not(platform="windows"))
async fn output_line(
  pushes : @async.Queue[@terminal.TerminalPush],
) -> (String, Int32) {
  let mut text = ""
  for ;; {
    match pushes.get() {
      Output(data~, sequence~, ..) => {
        text += @utf8.decode_lossy(data)
        if text.contains("\n") {
          return (text.trim().to_owned(), sequence)
        }
      }
      Exited(..) => fail("shell exited before producing its response")
    }
  }
}

///|
#cfg(not(platform="windows"))
async test "reattachment preserves the shell PID variables cwd and missing output" {
  @async.with_timeout(10000, () => {
    @async.with_task_group(group => {
      let state = @terminal.new_terminal_state()
      defer state.shutdown()
      let first = @terminal.TerminalClient()
      let next = @terminal.TerminalClient()
      defer first.detach()
      defer next.detach()
      let before : @async.Queue[@terminal.TerminalPush] = Queue(
        kind=Blocking(32),
      )
      let after : @async.Queue[@terminal.TerminalPush] = Queue(
        kind=Blocking(32),
      )
      group.spawn_bg(() => @terminal.run_terminal_pump(state))
      let transport = group.spawn(no_wait=true, () => {
        first.run(push => before.put(push))
      })
      group.spawn_bg(no_wait=true, () => next.run(push => after.put(push)))
      let id = @terminal.open_terminal(
        state,
        first,
        cwd="/tmp",
        cols=80,
        rows=24,
        command=[
          "/bin/sh", "-c", "stty -echo; kept=retained; cd /; printf '%s:%s:%s\\n' \"$$\" \"$kept\" \"$PWD\"; read gate; printf '%s:%s:%s\\n' \"$$\" \"$kept\" \"$PWD\"; read gate; printf '%s:%s:%s\\n' \"$$\" \"$kept\" \"$PWD\"; exit 7",
        ],
      )
      let (original, sequence) = output_line(before)
      assert_true(original.has_suffix(":retained:/"))
      // A malformed attach must not change ownership, and an unattached
      // channel cannot operate this PTY.
      try
        @terminal.attach_terminal(state, next, id~, sequence=sequence + 100)
      catch {
        TerminalError(_) => ()
      } noraise {
        _ => fail("accepted a future output cursor")
      }
      try @terminal.write_terminal(next, id~, b"wrong\n") catch {
        @terminal.TerminalError(_) => ()
        error => raise error
      } noraise {
        _ => fail("unattached input reached shell")
      }
      // Input is delivered once; its resulting output may race disconnection.
      @terminal.write_terminal(first, id~, b"once\n")
      transport.cancel()
      transport.wait() catch {
        @async.WaitedTaskAlreadyCancelled => ()
        error => raise error
      }
      @async.sleep(30)
      assert_true(@terminal.attach_terminal(state, next, id~, sequence~))
      // A stale acknowledgement from the retired connection cannot discard the
      // output owed to the new one, even if it guesses the future sequence.
      @terminal.ack_terminal(first, id~, sequence=sequence + 1)
      let (replayed, replay_sequence) = output_line(after)
      assert_eq(replayed, original)
      assert_true(replay_sequence > sequence)
      @terminal.ack_terminal(next, id~, sequence=replay_sequence)
      @terminal.write_terminal(next, id~, b"fresh\n")
      let (fresh, _) = output_line(after)
      assert_eq(fresh, original)
      for ;; {
        if after.get() is Exited(code~, ..) {
          assert_eq(code, 7)
          break
        }
      }
      @terminal.close_terminal(next, id~)
    })
  })
}

///|
#cfg(not(platform="windows"))
async test "a newer connection takes over bounded output losslessly from a half-open client" {
  @async.with_timeout(10000, () => {
    @async.with_task_group(group => {
      let state = @terminal.new_terminal_state()
      defer state.shutdown()
      let first = @terminal.TerminalClient()
      let next = @terminal.TerminalClient()
      defer first.detach()
      defer next.detach()
      group.spawn_bg(() => @terminal.run_terminal_pump(state))
      let id = @terminal.open_terminal(
        state,
        first,
        cwd="/tmp",
        cols=80,
        rows=24,
        command=["/bin/sh", "-c", "head -c 524288 /dev/zero; exit 9"],
      )
      @async.sleep(50)
      // The old transport can still appear alive when its replacement arrives.
      assert_true(@terminal.attach_terminal(state, next, id~, sequence=0))
      try @terminal.attach_terminal(state, first, id~, sequence=0) catch {
        TerminalError(_) => ()
      } noraise {
        _ => fail("stale connection reclaimed the terminal")
      }
      try @terminal.write_terminal(first, id~, b"stale") catch {
        @terminal.TerminalError(_) => ()
        error => raise error
      } noraise {
        _ => fail("old connection wrote after takeover")
      }
      first.detach()
      let pushes : @async.Queue[@terminal.TerminalPush] = Queue(
        kind=Blocking(32),
      )
      group.spawn_bg(no_wait=true, () => next.run(push => pushes.put(push)))
      let mut total = 0
      let mut last = 0
      for ;; {
        match pushes.get() {
          Output(sequence~, data~, ..) => {
            assert_eq(sequence, last + 1)
            last = sequence
            total += data.length()
            assert_true(data.iter().all(byte => byte == b'\x00'))
            @terminal.ack_terminal(next, id~, sequence~)
          }
          Exited(code~, ..) => {
            assert_eq(code, 9)
            break
          }
        }
      }
      assert_eq(total, 524288)
      @terminal.close_terminal(next, id~)
    })
  })
}

///|
#cfg(not(platform="windows"))
async test "expired sessions cannot attach and offline exit follows retained output" {
  @async.with_timeout(10000, () => {
    @async.with_task_group(group => {
      let state = @terminal.new_terminal_state(grace_ms=80)
      defer state.shutdown()
      let first = @terminal.TerminalClient()
      let next = @terminal.TerminalClient()
      defer first.detach()
      defer next.detach()
      group.spawn_bg(() => @terminal.run_terminal_pump(state))
      let id = @terminal.open_terminal(
        state,
        first,
        cwd="/tmp",
        cols=80,
        rows=24,
        command=["/bin/cat"],
      )
      first.detach()
      @async.sleep(250)
      assert_false(@terminal.attach_terminal(state, next, id~, sequence=0))
      let state = @terminal.new_terminal_state()
      defer state.shutdown()
      group.spawn_bg(() => @terminal.run_terminal_pump(state))
      let id = @terminal.open_terminal(
        state,
        next,
        cwd="/tmp",
        cols=80,
        rows=24,
        command=["/bin/sh", "-c", "printf done; exit 3"],
      )
      next.detach()
      let third = @terminal.TerminalClient()
      defer third.detach()
      assert_true(@terminal.attach_terminal(state, third, id~, sequence=0))
      let pushes : @async.Queue[@terminal.TerminalPush] = Queue(
        kind=Blocking(32),
      )
      group.spawn_bg(no_wait=true, () => third.run(push => pushes.put(push)))
      let mut text = ""
      for ;; {
        match pushes.get() {
          Output(data~, ..) => text += @utf8.decode_lossy(data)
          Exited(code~, ..) => {
            assert_eq(code, 3)
            break
          }
        }
      }
      assert_eq(text, "done")
      @terminal.close_terminal(third, id~)
    })
  })
}

///|
#cfg(not(platform="windows"))
async test "replay yields to a bounded transport writer between records" {
  @async.with_timeout(10000, () => {
    @async.with_task_group(group => {
      let state = @terminal.new_terminal_state()
      defer state.shutdown()
      let first = @terminal.TerminalClient()
      let next = @terminal.TerminalClient()
      defer first.detach()
      defer next.detach()
      let before : @async.Queue[@terminal.TerminalPush] = Queue(
        kind=Blocking(1),
      )
      let wire : @async.Queue[@terminal.TerminalPush] = Queue(kind=Blocking(1))
      group.spawn_bg(() => @terminal.run_terminal_pump(state))
      group.spawn_bg(no_wait=true, () => first.run(push => before.put(push)))
      let id = @terminal.open_terminal(
        state,
        first,
        cwd="/tmp",
        cols=80,
        rows=24,
        command=[
          "/bin/sh", "-c", "stty -echo; echo READY; while read line; do echo \"$line\"; done",
        ],
      )
      let _ = output_line(before)
      // Keep acknowledgements outstanding and force distinct PTY reads by
      // waiting for each reply before supplying the next input line.
      for _ in 0..<20 {
        @terminal.write_terminal(first, id~, b"item\n")
        let _ = output_line(before)
      }
      first.detach()
      assert_true(@terminal.attach_terminal(state, next, id~, sequence=0))
      group.spawn_bg(no_wait=true, () => {
        next.run(push => {
          guard wire.try_put(push) else {
            fail("replay flooded the transport writer")
          }
        })
      })
      let expected = "READY\r\n" + Array::make(20, "item\r\n").join("")
      let mut received = ""
      while received.length() < expected.length() {
        guard wire.get() is Output(data~, sequence~, ..) else {
          fail("shell exited during replay")
        }
        received += @utf8.decode_lossy(data)
        @terminal.ack_terminal(next, id~, sequence~)
      }
      assert_eq(received, expected)
      @terminal.close_terminal(next, id~)
    })
  })
}

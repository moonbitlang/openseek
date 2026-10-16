///|
async fn terminal_request(
  route : Route,
  method_ : String,
  params : Json,
) -> Json {
  for endpoint in route.terminal_endpoints() {
    if endpoint.name() == method_ {
      return endpoint.invoke(params)
    }
  }
  fail("missing terminal endpoint: " + method_)
}

///|
#cfg(not(platform="windows"))
async test "SSH terminals run independently of app-server with remote cwd input resize and exit" {
  let directory = @fs.tmpdir(prefix="seekmoon-ssh-terminal-")
  defer @fs.rmdir(directory, recursive=true)
  let cwd = directory + "/worktree ' $literal %20 中文"
  @fs.mkdir(cwd)
  let ssh = directory + "/ssh"
  @fs.write_file(
    ssh,
    (
      #|#!/bin/sh
      #|export SHELL=/bin/sh
      #|printf '%s\n' "$@" > "$(dirname "$0")/args"
      #|for arg do last=$arg; done
      #|exec /bin/sh -c "$last"
    ),
    create_mode=CreateOrTruncate,
  )
  @fs.chmod(ssh, 0o700)
  let route = Route(
    Store(directory),
    {
      id: "ssh_test",
      name: "test",
      destination: "remote-alias",
      launcher: "/missing-app-server",
      data_dir: "/unused",
      build_id: "test",
      server_id: None,
    },
    [],
    ssh~,
  )
  let events : @async.Queue[@protocol.Notification] = Queue(kind=Unbounded)
  @async.with_timeout(10000, () => {
    @async.with_task_group(group => {
      group.spawn_bg(no_wait=true, () => {
        route.run_terminals(event => events.put(event))
      })
      let reply = terminal_request(route, "terminal.open", {
        "session": "remote-session",
        "workspace": @pathx.Path(cwd)
        .to_absolute()
        .bind(path => path.to_uri_path())
        .unwrap(),
        "cols": 80,
        "rows": 24,
        "command": "printf 'CWD=%s\\n' \"$PWD\"; printf 'READY\\n'; read answer; stty size; printf 'ANSWER=%s\\n' \"$answer\"; exit 23",
      })
      guard reply is { "id": String(id), .. } else {
        fail("missing terminal id")
      }
      let mut output = ""
      while !output.contains("READY\r\n") {
        guard events.get() is TerminalOutput(event) else {
          fail("terminal exited before ready")
        }
        assert_eq(event.id, id)
        output += @utf8.decode_lossy(@base64.decode(event.data))
        ignore(
          terminal_request(route, "terminal.ack", {
            "id": id,
            "sequence": event.sequence,
          }),
        )
      }
      assert_true(output.contains("CWD=" + cwd))
      ignore(
        terminal_request(route, "terminal.resize", {
          "id": id,
          "cols": 101,
          "rows": 37,
        }),
      )
      ignore(
        terminal_request(route, "terminal.input", {
          "id": id,
          "data_base64": @base64.encode(b"hello\n"),
        }),
      )
      for ;; {
        match events.get() {
          TerminalOutput(event) => {
            output += @utf8.decode_lossy(@base64.decode(event.data))
            ignore(
              terminal_request(route, "terminal.ack", {
                "id": id,
                "sequence": event.sequence,
              }),
            )
          }
          TerminalExit(event) => {
            assert_eq(event.id, id)
            assert_eq(event.code, 23)
            break
          }
          _ => fail("unexpected terminal event")
        }
      }
      assert_true(output.contains("37 101"))
      assert_true(output.contains("ANSWER=hello"))
      let args = @fs.read_file(directory + "/args").text()
      for
        option in [
          "-tt\n", "ControlPath=none\n", "EscapeChar=none\n", "ClearAllForwardings=yes\n",
          "--\nremote-alias\n",
        ] {
        assert_true(args.contains(option))
      }
      assert_true(route.ready_epoch is None)
    })
  })
}

///|
#cfg(not(platform="windows"))
async test "SSH terminal page close retires children and unresolved cwd never starts locally" {
  let directory = @fs.tmpdir(prefix="seekmoon-ssh-terminal-close-")
  defer @fs.rmdir(directory, recursive=true)
  let ssh = directory + "/ssh"
  @fs.write_file(
    ssh,
    (
      #|#!/bin/sh
      #|trap 'exit 0' HUP
      #|printf 'ALIVE\n'
      #|while :; do read line || exit 0; done
    ),
    create_mode=CreateOrTruncate,
  )
  @fs.chmod(ssh, 0o700)
  let route = Route(
    Store(directory),
    {
      id: "ssh_test",
      name: "test",
      destination: "remote-alias",
      launcher: "/missing-app-server",
      data_dir: "/unused",
      build_id: "test",
      server_id: None,
    },
    [],
    ssh~,
  )
  @async.with_timeout(10000, () => {
    @async.with_task_group(group => {
      let events : @async.Queue[@protocol.Notification] = Queue(kind=Unbounded)
      group.spawn_bg(no_wait=true, () => {
        route.run_terminals(event => events.put(event))
      })
      try
        terminal_request(route, "terminal.open", {
          "session": "unknown",
          "cols": 80,
          "rows": 24,
        })
      catch {
        SshError(_) => ()
        error => raise error
      } noraise {
        _ => fail("missing remote cwd must be refused")
      }
      let reply = terminal_request(route, "terminal.open", {
        "session": "s",
        "workspace": "/remote",
        "cols": 80,
        "rows": 24,
      })
      guard reply is { "id": String(id), .. } else { fail("missing id") }
      guard events.get() is TerminalOutput(_) else { fail("missing output") }
      route.close_terminals()
      for ;; {
        if events.get() is TerminalExit(event) {
          assert_eq(event.id, id)
          break
        }
      }
      try
        terminal_request(route, "terminal.input", {
          "id": id,
          "data": "must not run",
        })
      catch {
        @terminal.TerminalError::TerminalError(_) => ()
        error => raise error
      } noraise {
        _ => fail("closed SSH session accepted input")
      }
    })
  })
}

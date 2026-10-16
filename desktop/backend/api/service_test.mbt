///|
fn service_config(dir : String) -> @api.HostConfig {
  {
    data_dir: Path(dir),
    engine_executable: "unused-engine",
    codex: @codex.CodexSettings::default(),
    resources: @host.HostResources::from_path(),
    build_id: "test",
    mode: Headless,
  }
}

///|
test "headless hosts omit terminal endpoints while embedded hosts retain them" {
  for mode in [@api.Headless, Embedded] {
    let service = @api.ApiState(
      { ..service_config("/unused-host-data"), mode, },
      @runtime.HostRuntime::without_terminal(),
    )
    let names = @api.endpoints(service, service.new_connection()).map(e => {
      e.name()
    })
    for
      name in [
        "terminal.open", "terminal.input", "terminal.resize", "terminal.ack", "terminal.close",
      ] {
      assert_eq(names.contains(name), mode is Embedded)
    }
    assert_true(names.contains("fs.read_file"))
    assert_true(names.contains("agent.start"))
  }
}

///|
async test "host preparation reports an unusable data directory" {
  let dir = @fs.tmpdir(prefix="openseek-host-data-dir-")
  defer @fs.rmdir(dir, recursive=true)
  let file = dir + "/not-a-directory"
  @fs.write_file(file, "retain")
  let service = @api.ApiState(
    service_config(file),
    @runtime.HostRuntime::without_terminal(),
  )
  let failed = try {
    service.prepare()
    false
  } catch {
    _ => true
  }
  assert_true(failed)
  assert_eq(@fs.read_file(file).text(), "retain")
}

///|
#cfg(not(platform="windows"))
async test "host lifetime owns actors and settles pending calls on shutdown" {
  let dir = @fs.tmpdir(prefix="openseek-host-lifetime-")
  defer @fs.rmdir(dir, recursive=true)
  let script = dir + "/app-server.sh"
  let source =
    #|#!/bin/sh
    #|while IFS= read -r line; do
    #|  case "$line" in
    #|    *'"method":"initialize"'*)
    #|      id=$(printf '%s' "$line" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p')
    #|      printf '{"jsonrpc":"2.0","id":%s,"result":{}}\n' "$id"
    #|      ;;
    #|    *'"method":"block"'*)
    #|      printf '{"jsonrpc":"2.0","method":"test/blocked","params":{}}\n'
    #|      ;;
    #|  esac
    #|done
  @fs.write_file(script, source, create_mode=CreateOrTruncate)
  @fs.chmod(script, 0o700)
  let config = service_config(dir)
  let service = @api.ApiState(
    {
      ..config,
      codex: CodexSettings(command=script, home=Some(Path(dir + "/codex"))),
    },
    @runtime.HostRuntime::without_terminal(),
  )
  let events : @async.Queue[@protocol.HostNotification] = Queue(
    kind=Blocking(64),
  )
  let events_sub = service.subscribe(events, map=value => Some(value), on_lag=sub => {
    sub.close()
  })
  defer events_sub.close()
  @async.with_timeout(10000, () => {
    @async.with_task_group(group => {
      let running = group.spawn(() => service.run())
      // This is the engine actor's startup notification, not a synthetic
      // WebSocket readiness reply. Codex notifications share the same hub.
      for ;; {
        if events.get() is AgentConnected(_) {
          break
        }
      }
      let caller = group.spawn(() => {
        try
          service
          .codex_actor()
          .call(method_="block", params=Json::empty_object())
        catch {
          @codex.TransportClosed(method_="block") => true
          error => raise error
        } noraise {
          _ => false
        }
      })
      for ;; {
        if events.get() is CodexNotification({ "method": "test/blocked", .. }) {
          break
        }
      }
      running.cancel()
      try running.wait() catch {
        @async.WaitedTaskAlreadyCancelled => ()
        error => raise error
      } noraise {
        _ => fail("host should propagate cancellation")
      }
      assert_true(caller.wait())
    })
  })
}

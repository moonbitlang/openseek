///|
async fn input_line() -> String? {
  let buffer = Buffer()
  for ;; {
    match @stdio.stdin.read_some(max_len=1) {
      None =>
        return if buffer.length() == 0 {
          None
        } else {
          Some(@utf8.decode(buffer.to_bytes()))
        }
      Some(bytes) if bytes == b"\n" =>
        return Some(@utf8.decode(buffer.to_bytes()))
      Some(bytes) => {
        guard buffer.length() < 32 * 1024 * 1024 else {
          fail("local request exceeds 32 MiB")
        }
        buffer.write_bytes(bytes)
      }
    }
  }
}

///|
async fn remote(matches : @argparse.Matches) -> Unit {
  let host : @host_client.SshHost = {
    ssh: required(matches, "ssh"),
    destination: required(matches, "host"),
    launcher: required(matches, "launcher"),
    data_dir: required(matches, "data-dir"),
    build_id: required(matches, "build-id"),
    expected_server_id: value(matches, "expected-server-id"),
  }
  if matches.flags.get("reconnect") is Some(true) {
    remote_reconnecting(host, required(matches, "host-id"))
    return
  }
  @host_client.with_client(host, client => {
    let lock = @async.Mutex()
    async fn output(value : Json) -> Unit {
      lock.acquire()
      defer lock.release()
      @stdio.stdout.write(value.stringify() + "\n")
    }
    output({
      "jsonrpc": "2.0",
      "method": "host.connected",
      "params": client.identity.to_json(),
    })
    @async.with_task_group(group => {
      group.spawn_bg(() => {
        for ;; {
          output(client.next_notification())
        }
      })
      while input_line() is Some(line) {
        guard @json.parse(line)
          is { "id": id, "method": String(method_), "params": params, .. } else {
          fail("input must be a JSONL request with id, method and params")
        }
        let result = client.request(method_, params) catch {
          error => {
            let outcome = match error {
              @host_client.Unsent(_) => "unsent"
              @host_client.Refused(_) => "refused"
              _ => "unknown"
            }
            output({
              "jsonrpc": "2.0",
              "id": id,
              "error": {
                "code": -32020,
                "message": "\{error}",
                "data": { "outcome": outcome },
              },
            })
            continue
          }
        }
        output({ "jsonrpc": "2.0", "id": id, "result": result })
      }
      group.return_immediately(())
    })
  })
}

///|
/// Diagnostic entrypoint for the same per-window supervisor used by desktop.
/// Requests must name the observed epoch, including while disconnected.
async fn remote_reconnecting(
  config : @host_client.SshHost,
  host_id : String,
) -> Unit {
  let connection = @host_client.Connection(Host(id=host_id, config))
  let output : @async.Queue[(String, Int32)?] = Queue(kind=Blocking(64))
  let retained = Ref(0)
  fn enqueue(value : Json) -> Bool {
    let text = value.stringify() + "\n"
    let bytes = @utf8.encode(text).length()
    if bytes > 64 * 1024 * 1024 - retained.val {
      return false
    }
    if !(output.try_put(Some((text, bytes))) catch { _ => false }) {
      return false
    }
    retained.val += bytes
    true
  }
  @async.with_task_group(group => {
    let writer = group.spawn(() => {
      while output.get() is Some((text, bytes)) {
        defer {
          retained.val -= bytes
        }
        @stdio.stdout.write(text)
      }
    })
    let supervisor = group.spawn(() => {
      connection.run(emit=event => {
        enqueue({
          "jsonrpc": "2.0",
          "method": "host.connection",
          "params": event.to_json(),
        })
      })
    })
    while input_line() is Some(line) {
      guard @json.parse(line)
        is {
          "id": id,
          "epoch": epoch,
          "method": String(method_),
          "params": params,
          ..
        } else {
        fail("reconnecting requests require id, epoch, method and params")
      }
      let epoch : Int32 = @json.from_json(epoch)
      let result = connection.request(epoch~, method_, params) catch {
        error => {
          let outcome = match error {
            @host_client.Unsent(_) => "unsent"
            @host_client.Refused(_) => "refused"
            _ => "unknown"
          }
          guard enqueue({
            "jsonrpc": "2.0",
            "id": id,
            "error": { "message": "\{error}", "data": { "outcome": outcome } },
          }) else {
            fail("client output overflow")
          }
          continue
        }
      }
      guard enqueue({ "jsonrpc": "2.0", "id": id, "result": result }) else {
        fail("client output overflow")
      }
    }
    supervisor.cancel()
    supervisor.wait() catch {
      _ => ()
    }
    @async.with_timeout(5000, () => {
      output.put(None)
      writer.wait()
    })
    group.return_immediately(())
  })
}

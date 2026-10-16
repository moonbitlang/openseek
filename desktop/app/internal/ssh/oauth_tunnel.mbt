///|
/// Keep the callback forward in an owned SSH process. LocalCommand runs only
/// after SSH connects and installs local forwards; ExitOnForwardFailure makes
/// a port conflict fatal before the readiness marker can be emitted. A TCP
/// connect probe alone could mistake another process's listener for ours.
pub async fn[T] with_callback_tunnel(
  ssh~ : String,
  destination~ : String,
  body : async () -> T,
) -> T {
  callback_tunnel(ssh~, destination~, body)
}

///|
async fn[T] callback_tunnel(
  ssh~ : String,
  destination~ : String,
  body : async () -> T,
  ready_timeout_ms~ : Int32 = 5000,
  lifetime_ms~ : Int32 = 600000,
) -> T {
  guard !destination.is_blank() &&
    !destination.has_prefix("-") &&
    !destination.contains("\u0000") &&
    !destination.contains("\n") &&
    !destination.contains("\r") else {
    raise SshError("Invalid SSH callback destination")
  }
  let marker = "__seekmoon_oauth_" + @uuid.mint() + "__"
  @async.with_task_group(group => {
    let (stdin, input) = @process.write_to_process()
    input.close()
    let (output, stdout) = @process.read_from_process()
    group.add_defer(() => output.close())
    let (errors, stderr) = @process.read_from_process()
    group.add_defer(() => errors.close())
    let process = @process.spawn(
      group,
      ssh,
      [
        "-N",
        "-T",
        "-o",
        "BatchMode=yes",
        "-o",
        "ControlMaster=no",
        "-o",
        "ControlPath=none",
        "-o",
        "ExitOnForwardFailure=yes",
        "-o",
        "ConnectTimeout=10",
        "-o",
        "ServerAliveInterval=15",
        "-o",
        "ServerAliveCountMax=4",
        "-o",
        "ForwardAgent=no",
        "-o",
        "PermitLocalCommand=yes",
        "-o",
        "LocalCommand=echo " + marker,
        "-L",
        "127.0.0.1:1455:127.0.0.1:1455",
        "--",
        destination,
      ],
      stdin~,
      stdout~,
      stderr~,
      no_console_window=true,
      cancel_handler=@process.graceful_cancel(timeout=1000),
      no_wait=true,
    )
    defer process.cancel()
    let diagnostics = Buffer()
    let drained = group.spawn(allow_failure=true, () => {
      for ;; {
        guard errors.read_some(max_len=4096) is Some(chunk) else { break }
        let room = 8192 - diagnostics.length()
        if room > 0 {
          diagnostics.write_bytes(chunk[:Int32::min(room, chunk.length())])
        }
      }
    })
    let result = @async.any([
      () => {
        let code = process.wait()
        @async.with_timeout(250, () => drained.wait()) catch {
          _ => ()
        }
        raise SshError(
          "SSH callback tunnel exited (\{code}): " +
          @utf8.decode_lossy(diagnostics.to_bytes()),
        )
      },
      () => {
        @async.sleep(lifetime_ms)
        raise SshError("SSH callback login expired after its time limit")
      },
      () => {
        @async.with_timeout(ready_timeout_ms, () => {
          let expected = @utf8.encode(marker + "\n")
          let actual = output.read_exactly(expected.length())
          guard actual == expected && process.try_wait() is None else {
            raise SshError("SSH callback tunnel did not become ready")
          }
        }) catch {
          @async.TimeoutError =>
            raise SshError(
              "SSH callback tunnel did not become ready within 5 seconds",
            )
          error => {
            // Pipe EOF can win the race with process exit. Give the bounded
            // stderr reader time to retain OpenSSH's actionable diagnosis.
            @async.with_timeout(250, () => drained.wait()) catch {
              _ => ()
            }
            raise SshError(
              "Could not establish SSH callback tunnel on 127.0.0.1:1455: \{error}. " +
              @utf8.decode_lossy(diagnostics.to_bytes()),
            )
          }
        }
        body()
      },
    ])
    group.return_immediately(result)
    result
  })
}

///|
#cfg(not(platform="windows"))
async fn callback_fixture(directory : String, mode : String) -> String {
  let script = directory + "/ssh"
  let source =
    #|#!/bin/sh
    #|dir=$(dirname "$0")
    #|trap 'printf stopped > "$dir/stopped"; exit 0' TERM
    #|printf '%s\n' "$@" > "$dir/args"
    #|mode=$(cat "$dir/mode")
    #|if [ "$mode" = failed ]; then echo "bind 127.0.0.1:1455: Address already in use" >&2; exit 42; fi
    #|if [ "$mode" != silent ]; then
    #|  for arg in "$@"; do
    #|    case "$arg" in LocalCommand=*) eval "${arg#LocalCommand=}";; esac
    #|  done
    #|fi
    #|while :; do sleep 0.02; done
  @fs.write_file(script, source, create_mode=CreateOrTruncate)
  @fs.write_file(directory + "/mode", mode, create_mode=CreateOrTruncate)
  @fs.chmod(script, 0o700)
  script
}

///|
#cfg(not(platform="windows"))
async test "callback tunnel opens only after readiness and owns its child" {
  let directory = @fs.tmpdir(prefix="ssh-callback-ready-")
  defer @fs.rmdir(directory, recursive=true)
  let ssh = callback_fixture(directory, "ready")
  assert_eq(with_callback_tunnel(ssh~, destination="demo", () => 42), 42)
  let args = @fs.read_file(directory + "/args").text()
  for
    required in [
      "-N\n", "ControlMaster=no\n", "ControlPath=none\n", "ExitOnForwardFailure=yes\n",
      "ForwardAgent=no\n", "127.0.0.1:1455:127.0.0.1:1455\n",
    ] {
    assert_true(args.contains(required))
  }
  assert_eq(@fs.read_file(directory + "/stopped").text(), "stopped")
}

///|
#cfg(not(platform="windows"))
async test "callback tunnel failure or missing readiness never opens the login page" {
  for mode in ["failed", "silent"] {
    let directory = @fs.tmpdir(prefix="ssh-callback-refused-")
    defer @fs.rmdir(directory, recursive=true)
    let ssh = callback_fixture(directory, mode)
    let opened = Ref(false)
    let refused = try {
      callback_tunnel(ssh~, destination="demo", ready_timeout_ms=100, () => {
        opened.val = true
      })
      false
    } catch {
      SshError(message) => {
        if mode == "failed" {
          assert_true(message.contains("Address already in use"))
        }
        true
      }
      error => raise error
    }
    assert_true(refused)
    assert_false(opened.val)
    if mode == "silent" {
      assert_eq(@fs.read_file(directory + "/stopped").text(), "stopped")
    }
  }
}

///|
#cfg(not(platform="windows"))
async test "callback tunnel expiration and caller cancellation clean up the owned child" {
  for cancel in [false, true] {
    let directory = @fs.tmpdir(prefix="ssh-callback-close-")
    defer @fs.rmdir(directory, recursive=true)
    let ssh = callback_fixture(directory, "ready")
    let entered : @async.Queue[Unit] = Queue(kind=Blocking(1))
    let never : @async.Queue[Unit] = Queue(kind=Blocking(1))
    @async.with_timeout(5000, () => {
      @async.with_task_group(group => {
        let job = group.spawn(allow_failure=true, () => {
          callback_tunnel(
            ssh~,
            destination="demo",
            lifetime_ms=if cancel { 4000 } else { 200 },
            () => {
              entered.put(())
              never.get()
            },
          )
        })
        entered.get()
        if cancel {
          job.cancel()
        }
        try job.wait() catch {
          @async.WaitedTaskAlreadyCancelled if cancel => ()
          SshError(message) if !cancel =>
            assert_true(message.contains("expired"))
          error => raise error
        } noraise {
          _ => fail("tunnel should not complete normally")
        }
      })
    })
    assert_eq(@fs.read_file(directory + "/stopped").text(), "stopped")
  }
}

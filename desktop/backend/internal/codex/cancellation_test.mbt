///|
#cfg(not(platform="windows"))
async test "cancelling the Codex actor settles an in-flight API call" {
  let dir = @fs.tmpdir(prefix="openseek-codex-cancel-")
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
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let started : @async.Queue[Unit] = Queue(kind=Blocking(1))
      let actor = @codex.Actor(CodexSettings(command=script, home=None))
      let running = group.spawn(() => {
        actor.run((event, payload) => {
          if event == "codex.notification" &&
            payload is { "method": "test/blocked", .. } {
            ignore(started.try_put(()) catch { _ => false })
          }
        })
      })
      let caller = group.spawn(() => {
        try actor.call(method_="block", params=Json::empty_object()) catch {
          @codex.TransportClosed(method_="block") => true
          error => raise error
        } noraise {
          _ => false
        }
      })
      started.get()
      running.cancel()
      try running.wait() catch {
        @async.TaskCancelled => ()
        error => raise error
      } noraise {
        _ => fail("actor should propagate cancellation")
      }
      assert_true(caller.wait())
    })
  })
}

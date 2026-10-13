///|
test "codex home is a codex subdirectory of the runtime dir" {
  let home = @codex.home_dir(Path("/tmp/openseek-state"))
  assert_eq(
    home.to_string(),
    if @async.platform is Windows {
      "\\tmp\\openseek-state\\codex"
    } else {
      "/tmp/openseek-state/codex"
    },
  )
}

///|
async test "prepared codex home creates the directory" {
  let root : @pathx.Path = @fs.tmpdir(prefix="openseek-codex-home-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  let home = @codex.prepared_home(root)
  assert_eq(home, @codex.home_dir(root))
  assert_true(@fs.kind(home.to_string()) is Directory)
  // Preparing an existing home must succeed too: that is the steady state
  // of every launch after the first.
  assert_eq(@codex.prepared_home(root), home)
}

///|
#cfg(not(platform="windows"))
async test "Codex home failure prevents spawning and can recover on a later request" {
  let root = @fs.tmpdir(prefix="openseek-codex-isolation-")
  defer @fs.rmdir(root, recursive=true)
  let home = root + "/codex"
  let marker = root + "/spawned"
  let script = root + "/app-server.sh"
  let source =
    #|#!/bin/sh
    #|printf '%s' "$CODEX_HOME" > "$(dirname "$0")/spawned"
    #|while IFS= read -r line; do
    #|  case "$line" in
    #|    *'"id":'*)
    #|      id=$(printf '%s' "$line" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p')
    #|      printf '{"jsonrpc":"2.0","id":%s,"result":{}}\n' "$id"
    #|      ;;
    #|  esac
    #|done
  @fs.write_file(script, source, create_mode=CreateOrTruncate)
  @fs.chmod(script, 0o700)
  @fs.write_file(home, "preserve this file", create_mode=CreateOrTruncate)
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let failed : @async.Queue[Unit] = Queue(kind=Blocking(1))
      let actor = @codex.Actor(
        CodexSettings(command=script, home=Some(Path(home))),
      )
      group.spawn_bg(() => {
        actor.run((event, payload) => {
          if event == "codex.status_changed" &&
            payload is { "status": "unavailable", .. } {
            ignore(failed.try_put(()) catch { _ => false })
          }
        })
      })
      failed.get()
      try actor.call(method_="account/read", params={}) catch {
        @codex.Unavailable(message) =>
          assert_true(message.contains("Could not prepare isolated Codex home"))
        error => raise error
      } noraise {
        _ => fail("blocked home should reject Codex calls")
      }
      assert_eq(@fs.read_file(home).text(), "preserve this file")
      assert_false(@fs.readdir(root).contains("spawned"))
      @fs.remove(home)
      assert_eq(
        actor.call(method_="account/read", params={}),
        Json::empty_object(),
      )
      assert_eq(@fs.read_file(marker).text(), home)
      assert_true(@fs.kind(home) is Directory)
      group.return_immediately(())
    })
  })
}

///|
async test "Desktop requires an isolated home instead of inheriting one" {
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let actor = @codex.Actor(
        CodexSettings(
          command="must-not-be-spawned",
          home=None,
          require_home=true,
        ),
      )
      group.spawn_bg(() => actor.run((_, _) => ()))
      try actor.call(method_="account/read", params={}) catch {
        @codex.Unavailable(message) =>
          assert_true(
            message.contains("Could not determine isolated Codex home"),
          )
        error => raise error
      } noraise {
        _ => fail("missing isolated home must refuse Codex calls")
      }
      group.return_immediately(())
    })
  })
}

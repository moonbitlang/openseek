///|
#cfg(not(platform="windows"))
async test "a committed fork succeeds even when its title cannot be saved" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  defer restore_home_env(previous)
  let dir = @fs.realpath(@fs.tmpdir(prefix="openseek-fork-title-failure-"))
  defer @fs.rmdir(dir, recursive=true)
  let workspace = dir + "/workspace"
  @sys.set_env_var("HOME", dir + "/home")
  @fs.mkdir(dir + "/home/.openseek", recursive=true)
  @fs.mkdir(workspace + "/.openseek", recursive=true)
  @fs.write_file(
    dir + "/home/.openseek/workspaces.json",
    ({ "workspaces": [workspace] } : Json).stringify(),
  )
  let newline = "\\n"
  // Commit a loadable session, then make the title destination a directory.
  // Atomic title replacement must fail even when tests run with write access.
  let engine = dir + "/engine.sh"
  let script =
    $|#!/bin/sh
    $|set -eu
    $|while [ "$#" -gt 0 ]; do
    $|  case "$1" in
    $|    --as) fork="$2"; shift 2 ;;
    $|    --session-root) root="$2"; shift 2 ;;
    $|    *) shift ;;
    $|  esac
    $|done
    $|target="$root/sessions/$fork"
    $|mkdir -p "$target/session-title"
    $|printf '{"version":1,"id":"%s","system_prompt":"test"}\{newline}' "$fork" > "$target/openseek_session-$fork.jsonl"
    $|printf '%s\{newline}' "$fork"
  @fs.write_file(engine, script)
  assert_eq(@process.run("chmod", ["+x", engine]), 0)
  let manager = new_engine_manager(engine)
  let reply = fork_session(manager, {
    session: "source",
    workspace: @pathx.Path(workspace).resolve().resource_path(),
    through: 3,
    model: "deepseek-flash",
    source_title: "Original title",
  })
  assert_eq(reply.title, "Original title")
  let store = @store.SessionStore(workspace + "/.openseek")
  let id : @agent_session.SessionId = SessionId(reply.session)
  assert_eq(store.load(id).id().value(), reply.session)
  assert_true(manager.record_guards.get("source") is None)
  let title_failed = try {
    store.set_title(id, "Retry title")
    false
  } catch {
    _ => true
  }
  assert_true(title_failed)
}

///|
#cfg(not(platform="windows"))
async test "artifact reads bind the exact workspace and continue after archive and deletion reclaims only that session" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  defer restore_home_env(previous)
  let dir = @fs.realpath(@fs.tmpdir(prefix="openseek-artifact-host-"))
  defer @fs.rmdir(dir, recursive=true)
  let home = dir + "/home"
  @sys.set_env_var("HOME", home)
  @fs.mkdir(home + "/Documents", recursive=true)
  @fs.mkdir(home + "/.openseek", recursive=true)
  let first = dir + "/first"
  let second = dir + "/second"
  @fs.mkdir(first)
  @fs.mkdir(second)
  @fs.write_file(
    home + "/.openseek/workspaces.json",
    ({ "workspaces": [first, second] } : Json).stringify(),
  )
  let one = @store.SessionStore(first + "/.openseek")
  let two = @store.SessionStore(second + "/.openseek")
  let id : @agent_session.SessionId = SessionId("same-id")
  for store in [one, two] {
    store.create(Session(id, system_prompt="system"))
  }
  let one_files = one.artifact_dir(id)
  let two_files = two.artifact_dir(id)
  @fs.mkdir(one_files, recursive=true)
  @fs.mkdir(two_files, recursive=true)
  @fs.write_file(one_files + "/chart.html", "first")
  @fs.write_file(two_files + "/chart.html", "second")
  let manager = new_engine_manager("openseek")
  let payload : @protocol.ArtifactFilePayload = {
    session: id.value(),
    workspace: @pathx.Path(first).resolve().resource_path(),
    archived: false,
    reference: "artifact://chart.html",
  }
  assert_eq(session_artifact_file(manager, payload).content, Some("first"))
  assert_eq(
    session_artifact_file(manager, {
      ..payload,
      workspace: @pathx.Path(second).resolve().resource_path(),
    }).content,
    Some("second"),
  )
  @fs.mkdir(first + "/.openseek/archived/sessions", recursive=true)
  @fs.rename(
    first + "/.openseek/sessions/same-id",
    first + "/.openseek/archived/sessions/same-id",
  )
  assert_eq(
    session_artifact_file(manager, { ..payload, archived: true, }).content,
    Some("first"),
  )
  let archived_store = @store.SessionStore(first + "/.openseek/archived")
  let archived_files = archived_store.artifact_dir(id)
  assert_false(@fs.exists(one_files))
  assert_true(@fs.exists(archived_files + "/chart.html"))
  @fs.rename(
    first + "/.openseek/archived/sessions/same-id",
    first + "/.openseek/sessions/same-id",
  )
  assert_eq(session_artifact_file(manager, payload).content, Some("first"))
  @fs.rename(
    first + "/.openseek/sessions/same-id",
    first + "/.openseek/archived/sessions/same-id",
  )
  @fs.mkdir(first + "/.openseek/archived/deleting", recursive=true)
  @fs.rename(
    first + "/.openseek/archived/sessions/same-id",
    first + "/.openseek/archived/deleting/same-id",
  )
  manager.sweep_archived_deletions_in(
    @pathx.Path(first + "/.openseek").resolve(),
  )
  assert_false(@fs.exists(one_files))
  assert_false(@fs.exists(archived_files))
  assert_true(@fs.exists(two_files + "/chart.html"))
}

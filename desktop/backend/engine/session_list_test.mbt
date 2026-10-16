///|
#cfg(not(platform="windows"))
async test "live and archived listings read stores without an engine executable" {
  let dir = @fs.tmpdir(prefix="openseek-direct-list-")
  defer @fs.rmdir(dir, recursive=true)
  let previous = @sys.get_env_var("HOME")
  @sys.set_env_var("HOME", dir)
  defer (match previous {
    Some(value) => @sys.set_env_var("HOME", value)
    None => @sys.unset_env_var("HOME")
  })
  let workspace = dir + "/project"
  let broken = dir + "/broken"
  let empty = dir + "/empty"
  @fs.mkdir(dir + "/.openseek", recursive=true)
  @fs.write_file(
    dir + "/.openseek/workspaces.json",
    ({ "workspaces": [workspace, broken, empty] } : Json).stringify(),
    create_mode=CreateOrTruncate,
  )
  let store = @store.SessionStore(workspace + "/.openseek")
  let original = @agent_session.Session(SessionId("renamed"), system_prompt="")
  store.create(original.append(User(UserMessage(Content([Text("original")])))))
  store.set_title(SessionId("renamed"), "Explicit title")
  store.create(
    @agent_session.Session(SessionId("prompt"), system_prompt="").append(
      User(UserMessage(Content([Text("  first line\nsecond line  ")]))),
    ),
  )
  store.create(
    @agent_session.Session(SessionId("shell"), system_prompt="").append(
      User(
        UserMessage(
          Content([
            Text(
              @command_context.encode(
                "git status\ngit log",
                Ok({
                  exit_code: Some(0),
                  text: "",
                  output_limit_reached: false,
                }),
              ),
            ),
          ]),
        ),
      ),
    ),
  )
  @fs.mkdir(workspace + "/.openseek/sessions/husk", recursive=true)
  // Keep the store listing policy: skip invalid ids without losing good rows.
  @fs.mkdir(workspace + "/.openseek/sessions/bad\\name", recursive=true)
  let archive = @store.SessionStore(workspace + "/.openseek/archived")
  archive.create(Session(SessionId("archived"), system_prompt=""))
  archive.set_title(SessionId("archived"), "Archived title")
  let corrupt = @store.SessionStore(broken + "/.openseek")
  corrupt.create(Session(SessionId("bad"), system_prompt=""))
  @fs.write_file(
    broken + "/.openseek/sessions/bad/session-title",
    " ",
    create_mode=CreateOrTruncate,
  )
  let reply = @engine.list_sessions()
  assert_eq(reply.groups.length(), 3)
  let group = reply.groups[0]
  assert_eq(group.error, "")
  assert_eq(group.sessions.length(), 4)
  let titles = Map::from_array(group.sessions.map(row => (row.id, row.title)))
  assert_eq(titles.get("renamed"), Some(Some("Explicit title")))
  assert_eq(titles.get("prompt"), Some(Some("first line")))
  assert_eq(titles.get("shell"), Some(Some("$ git status")))
  assert_eq(titles.get("husk"), Some(Some("")))
  assert_eq(group.sessions[3].id, "husk")
  assert_eq(group.sessions[3].updated_at_ms, None)
  for row in group.sessions[:3] {
    let (seconds, nanos) = @fs.mtime(store.session_file(SessionId(row.id)))
    assert_eq(
      row.updated_at_ms,
      Some((seconds * 1000 + (nanos / 1000000).to_int64()).to_double()),
    )
  }
  assert_true(reply.groups[1].error.contains("session title must not be blank"))
  assert_eq(reply.groups[1].sessions.length(), 0)
  assert_eq(reply.groups[2].error, "")
  assert_eq(reply.groups[2].sessions.length(), 0)
  let archived = @engine.archived_sessions()
  assert_eq(archived.groups[0].error, "")
  assert_eq(archived.groups[0].sessions.length(), 1)
  assert_eq(archived.groups[0].sessions[0].title, Some("Archived title"))
  let title_hits = @engine.search_sessions({
    query: "  EXPLICIT  ",
    include_archived: false,
  })
  assert_eq(title_hits.hits.length(), 1)
  assert_eq(title_hits.hits[0].session, "renamed")
  assert_eq(title_hits.errors.length(), 1)
  assert_false(title_hits.has_more)
  // The first prompt contains this word, but an explicit title replaced it.
  let body_only = @engine.search_sessions({
    query: "original",
    include_archived: false,
  })
  assert_eq(body_only.hits.length(), 0)
  let id_only = @engine.search_sessions({
    query: "renamed",
    include_archived: false,
  })
  assert_eq(id_only.hits.length(), 0)
  let live_only = @engine.search_sessions({
    query: "Archived title",
    include_archived: false,
  })
  assert_eq(live_only.hits.length(), 0)
  let with_archived = @engine.search_sessions({
    query: "Archived title",
    include_archived: true,
  })
  assert_eq(with_archived.hits.length(), 1)
  assert_true(with_archived.hits[0].archived)
  let blank = @engine.search_sessions({ query: "  ", include_archived: true, })
  assert_eq(blank.hits.length(), 0)
  assert_eq(blank.errors.length(), 0)
  // The sidebar and search share a Desktop-owned cache. Other writers, including
  // CLI sessions and archive moves, must remain visible after a warm search.
  store.set_title(SessionId("renamed"), "Updated title")
  assert_eq(
    @engine.search_sessions({ query: "explicit", include_archived: false, }).hits.length(),
    0,
  )
  assert_eq(
    @engine.search_sessions({ query: "updated title", include_archived: false, }).hits.length(),
    1,
  )
  store.create(
    @agent_session.Session(SessionId("prompt"), system_prompt="").append(
      User(UserMessage(Content([Text("Rewritten prompt")]))),
    ),
  )
  assert_eq(
    @engine.search_sessions({ query: "rewritten", include_archived: false, }).hits.length(),
    1,
  )
  @fs.rename(
    workspace + "/.openseek/sessions/prompt",
    workspace + "/.openseek/archived/sessions/prompt",
  )
  assert_eq(
    @engine.search_sessions({ query: "rewritten", include_archived: false, }).hits.length(),
    0,
  )
  let moved = @engine.search_sessions({
    query: "rewritten",
    include_archived: true,
  })
  assert_eq(moved.hits.length(), 1)
  assert_true(moved.hits[0].archived)
  // Reusing a live path after an archive move must not reuse the old prompt.
  let recreated = @agent_session.Session(SessionId("prompt"), system_prompt="")
  store.create(recreated.append(User(UserMessage(Content([Text("Before")])))))
  assert_eq(
    @engine.search_sessions({ query: "before", include_archived: false, }).hits.length(),
    1,
  )
  // Same-length external rewrites must invalidate cached text.
  store.create(recreated.append(User(UserMessage(Content([Text("After!")])))))
  assert_eq(
    @engine.search_sessions({ query: "before", include_archived: false, }).hits.length(),
    0,
  )
  assert_eq(
    @engine.search_sessions({ query: "after!", include_archived: false, }).hits.length(),
    1,
  )
  @fs.remove(store.session_file(SessionId("prompt")))
  assert_eq(
    @engine.search_sessions({ query: "after!", include_archived: false, }).hits.length(),
    0,
  )
  store.create(recreated.append(User(UserMessage(Content([Text("")])))))
  let titles = Map::from_array(
    @engine.list_sessions().groups[0].sessions.map(row => (row.id, row.title)),
  )
  assert_eq(titles.get("prompt"), Some(Some("")))
  store.create(
    recreated.append(User(UserMessage(Content([Text("Recovered")])))),
  )
  assert_eq(
    @engine.search_sessions({ query: "recovered", include_archived: false, }).hits.length(),
    1,
  )
  @fs.rmdir(workspace + "/.openseek/sessions/prompt", recursive=true)
  assert_eq(
    @engine.search_sessions({ query: "recovered", include_archived: false, }).hits.length(),
    0,
  )
  store.create(
    recreated.append(User(UserMessage(Content([Text("New session")])))),
  )
  assert_eq(
    @engine.search_sessions({ query: "new session", include_archived: false, }).hits.length(),
    1,
  )
}

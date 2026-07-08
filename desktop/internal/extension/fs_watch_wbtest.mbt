// The watcher's pruning rules and the stat op's wire shapes.

///|
test "ignored_watch_path prunes cache and build subtrees at any depth" {
  assert_true(ignored_watch_path(".git"))
  assert_true(ignored_watch_path("sub/project/.git"))
  assert_true(ignored_watch_path("target"))
  assert_true(ignored_watch_path("deps/node_modules"))
  assert_true(ignored_watch_path("editor/_build"))
  assert_true(ignored_watch_path(".mooncakes"))
  assert_true(ignored_watch_path(".repos"))
  // Only whole segments match — a file merely named like a cache dir stays.
  assert_false(ignored_watch_path("targets"))
  assert_false(ignored_watch_path("src/main.mbt"))
  assert_false(ignored_watch_path("git/notes.md"))
  assert_false(ignored_watch_path(""))
}

///|
test "stat_files payload decodes with and without a workspace hint" {
  let payload : StatFilesPayload = @json.from_json({
    "session": "s-1",
    "paths": ["a.mbt", "src/b.mbt"],
    "workspace": "/work/project",
  })
  assert_eq(payload.session, "s-1")
  assert_true(payload.paths == ["a.mbt", "src/b.mbt"])
  assert_true(payload.workspace is Some("/work/project"))
  let bare : WatchWorkspacePayload = @json.from_json({ "session": "" })
  assert_eq(bare.session, "")
  assert_true(bare.workspace is None)
}

///|
async test "file_signature reads a missing file as blank" {
  assert_eq(file_signature("/nonexistent/openseek-fs-watch-test"), "")
}

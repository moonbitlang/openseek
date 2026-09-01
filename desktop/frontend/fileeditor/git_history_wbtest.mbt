///|
fn graph_fixture_state() -> State {
  let commit = "1111111111111111111111111111111111111111"
  let base = "2222222222222222222222222222222222222222"
  {
    ..owned_state(),
    explorer_mode: ExplorerChanges,
    changes: ChangeListReady(
      repository=true,
      files=[],
      refreshing=None,
      refresh_again=false,
    ),
    git_graph: GitGraphReady(
      repository=true,
      snapshot={
        head: Some(commit),
        branch: Some("feature/graph"),
        refs: [
          { name: "feature/graph", revision: commit, kind: "current", },
          { name: "origin/feature/graph", revision: commit, kind: "upstream", },
          { name: "origin/main", revision: base, kind: "base", },
        ],
        tips: [commit, base],
      },
      commits=[
        {
          id: commit,
          parent_ids: [base],
          subject: "Add Git Graph",
          author: "OpenSeek",
          authored_at: "2026-08-19T10:00:00+08:00",
        },
        {
          id: base,
          parent_ids: [
            "3333333333333333333333333333333333333333", "4444444444444444444444444444444444444444",
          ],
          subject: "Base commit",
          author: "MoonBit",
          authored_at: "2026-08-18T10:00:00+08:00",
        },
      ],
      has_more=true,
      loading_more=None,
      load_error=None,
    ),
    git_graph_selected: Some(commit),
    git_commit_files: GitCommitFilesReady(commit~, parent=Some(base), files=[
      {
        path: "src/main.mbt",
        original_path: None,
        status: "modified",
        kind: "file",
      },
    ]),
  }
}

///|
test "historical model URIs encode revision side and path immutably" {
  let revision = "1111111111111111111111111111111111111111"
  let uri = history_revision_model_uri(
    test_ctx().owner,
    revision,
    "original",
    @pathx.Relative("src/a #.mbt"),
  ).unwrap()
  assert_eq(uri.scheme, HistoryRevisionScheme)
  assert_eq(uri.path, "/\{revision}/original/src/a #.mbt")
  assert_true(uri.to_string().contains("src/a%20%23.mbt"))
}

///|
test "Git history replies are fenced by request UUID" {
  let request_id = "git-history-current"
  let state = {
    ..graph_fixture_state(),
    git_graph: GitGraphLoading(request_id~),
  }
  let reply : @protocol.GitHistoryReply = {
    repository: true,
    snapshot: { head: None, branch: None, refs: [], tips: [], },
    commits: [],
    has_more: false,
  }
  let (_, stale) = update(
    test_emit(),
    GitHistoryLoaded(
      owner=test_ctx().owner,
      request_id=@uuid.mint(),
      append=false,
      reply~,
    ),
    state,
    test_ctx(),
  )
  assert_true(stale.git_graph is GitGraphLoading(..))
  let (_, settled) = update(
    test_emit(),
    GitHistoryLoaded(owner=test_ctx().owner, request_id~, append=false, reply~),
    state,
    test_ctx(),
  )
  assert_true(
    settled.git_graph
    is GitGraphReady(repository=true, commits=[], has_more=false, ..),
  )
}

///|
fn sidebar_pr_fixture(
  number : Int32,
  state : String,
  draft~ : Bool = false,
) -> @protocol.GitPullRequest {
  {
    number,
    title: "PR #\{number}",
    state,
    draft,
    url: "https://github.com/moonbitlang/openseek/pull/\{number}",
    base: "main",
    additions: 1,
    deletions: 0,
    changed_files: 1,
    checks: None,
  }
}

///|
fn sidebar_pr_item(
  id : String,
  pull_requests : Array[String],
) -> @transcript.SessionListItem {
  {
    id,
    title: Some("Session \{id}"),
    workspace: @interop.ChannelId::Local.test_project(),
    workspace_name: "work",
    updated_at_ms: Some(1.0),
    model_settings: None,
    pull_requests,
  }
}

///|
test "sidebar PR badges aggregate multi-PR state by priority and show unknown until summarized" {
  let dispatch = test_dispatch()
  let pr_open = "https://github.com/moonbitlang/openseek/pull/101"
  let pr_draft = "https://github.com/moonbitlang/openseek/pull/102"
  let pr_merged = "https://github.com/moonbitlang/openseek/pull/103"
  let pr_closed = "https://github.com/moonbitlang/openseek/pull/104"
  let items = [
    sidebar_pr_item("s-none", []),
    sidebar_pr_item("s-merged-3", [pr_merged, pr_closed]),
    sidebar_pr_item("s-open-wins", [pr_merged, pr_open, pr_draft]),
    sidebar_pr_item("s-draft-wins", [pr_merged, pr_draft]),
    sidebar_pr_item("s-closed", [pr_closed]),
  ]
  let (_, loaded) = update_dev(
    dispatch,
    SessionsLoaded(items, connection_generation=0, request_generation=0),
    test_model(),
  )
  assert_true(loaded.sidebar_pull_request_badge(Local, "s-none") is None)
  // Before GitHub responds, sessions with PRs show an Unknown badge with the attached count.
  assert_eq(
    loaded
    .sidebar_pull_request_badge(Local, "s-open-wins")
    .map(b => (b.tone, b.count)),
    Some((@conversation.Unknown, 3)),
  )
  let summaries : Map[String, @protocol.GitPullRequest] = Map([
    (pr_open, sidebar_pr_fixture(101, "open")),
    (pr_draft, sidebar_pr_fixture(102, "open", draft=true)),
    (pr_merged, sidebar_pr_fixture(103, "merged")),
    (pr_closed, sidebar_pr_fixture(104, "closed")),
  ])
  let (_, summarized) = update(
    dispatch,
    Changes(BatchSummarized(None, Ok({ pull_requests: summaries, }))),
    loaded,
  )
  assert_eq(
    summarized
    .sidebar_pull_request_badge(Local, "s-open-wins")
    .map(b => (b.tone, b.count)),
    Some((@conversation.Open, 3)),
  )
  assert_eq(
    summarized
    .sidebar_pull_request_badge(Local, "s-draft-wins")
    .map(b => (b.tone, b.count)),
    Some((@conversation.Draft, 2)),
  )
  assert_eq(
    summarized
    .sidebar_pull_request_badge(Local, "s-merged-3")
    .map(b => (b.tone, b.count)),
    Some((@conversation.Merged, 2)),
  )
  assert_eq(
    summarized
    .sidebar_pull_request_badge(Local, "s-closed")
    .map(b => (b.tone, b.count)),
    Some((@conversation.Closed, 1)),
  )
}

///|
test "synced artifact changes update a sidebar row live and ignore branch-only attachments" {
  let dispatch = test_dispatch()
  let pr_url = "https://github.com/moonbitlang/openseek/pull/205"
  let items = [sidebar_pr_item("s-live", [])]
  let (_, loaded) = update_dev(
    dispatch,
    SessionsLoaded(items, connection_generation=0, request_generation=0),
    test_model(),
  )
  assert_true(loaded.sidebar_pull_request_badge(Local, "s-live") is None)
  let mixed : @protocol.SessionArtifacts = @json.from_json({
    "artifacts": [
      {
        "type": "branch",
        "url": "https://github.com/moonbitlang/openseek/tree/topic",
      },
      { "type": "pull_request", "url": pr_url },
    ],
  }) catch {
    error => abort(error.to_string())
  }
  let (_, synced) = update_dev(
    dispatch,
    SessionArtifactsSynced(session="s-live", Ok(mixed)),
    loaded,
  )
  assert_eq(
    synced
    .sidebar_pull_request_badge(Local, "s-live")
    .map(b => (b.tone, b.count)),
    Some((@conversation.Unknown, 1)),
  )
  let (_, resolved) = update(
    dispatch,
    Changes(
      BatchSummarized(
        None,
        Ok({
          pull_requests: Map([(pr_url, sidebar_pr_fixture(205, "merged"))]),
        }),
      ),
    ),
    synced,
  )
  assert_eq(
    resolved
    .sidebar_pull_request_badge(Local, "s-live")
    .map(b => (b.tone, b.count)),
    Some((@conversation.Merged, 1)),
  )
  // Removing all PRs clears the badge immediately.
  let (_, cleared) = update_dev(
    dispatch,
    SessionArtifactsSynced(
      session="s-live",
      Ok(@protocol.SessionArtifacts::empty()),
    ),
    resolved,
  )
  assert_true(cleared.sidebar_pull_request_badge(Local, "s-live") is None)
}

///|
test "session_component_input wires PR badge for conversations" {
  let dispatch = test_dispatch()
  let pr_url = "https://github.com/moonbitlang/openseek/pull/301"
  let items = [sidebar_pr_item("s-main", [pr_url])]
  let (_, loaded) = update_dev(
    dispatch,
    SessionsLoaded(items, connection_generation=0, request_generation=0),
    test_model(),
  )
  let (_, summarized) = update(
    dispatch,
    Changes(
      BatchSummarized(
        None,
        Ok({ pull_requests: Map([(pr_url, sidebar_pr_fixture(301, "open"))]), }),
      ),
    ),
    loaded,
  )
  let row = session_component_input(summarized, Local, "s-main", "Main chat")
  assert_eq(
    row.pull_request.map(b => (b.tone, b.count)),
    Some((@conversation.Open, 1)),
  )
}

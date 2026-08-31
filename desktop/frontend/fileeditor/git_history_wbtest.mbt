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
      refreshing=false,
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
      loading_more=false,
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
test "Review tree renders VS Code-style Git Graph and inline commit files" {
  let html = render_review_html(
    tree_pane(test_emit(), graph_fixture_state(), test_ctx()),
  )
  assert_true(html.contains("id=\"review-changes-section\""))
  assert_true(html.contains("id=\"git-graph-resize-handle\""))
  assert_true(html.contains("role=\"separator\""))
  assert_true(html.contains(">Graph</span>"))
  assert_true(html.contains("git-graph-repository"))
  assert_true(html.contains(">work</span>"))
  assert_true(html.contains("git-graph-branch"))
  assert_true(html.contains("feature/graph"))
  assert_true(html.contains("Add Git Graph"))
  assert_true(html.contains("OpenSeek"))
  assert_true(html.contains("2026-08-19T10:00:00+08:00"))
  assert_true(html.contains("1111111111111111111111111111111111111111"))
  assert_true(html.contains("git-commit-row current selected"))
  assert_true(html.contains("git-graph-node-head-outer"))
  assert_true(html.contains("git-graph-node-head-inner"))
  assert_true(html.contains("git-graph-node-merge-outer"))
  assert_true(html.contains("git-graph-node-merge-inner"))
  assert_true(html.contains("git-ref-current"))
  assert_true(html.contains("git-ref-upstream"))
  assert_true(html.contains("git-ref-base"))
  assert_true(html.contains("current: feature/graph"))
  assert_true(html.contains("upstream: origin/feature/graph"))
  assert_true(html.contains("base: origin/main"))
  assert_true(html.contains("git-commit-actions"))
  assert_false(html.contains("git-commit-meta"))
  assert_false(html.contains("git-commit-sha"))
  assert_true(html.contains("src/main.mbt"))
  assert_true(html.contains("Open historical diff for src/main.mbt"))
  assert_true(html.contains("git-history-graph-placeholder"))
  assert_true(html.contains("role=\"tree\""))
  assert_true(html.contains("role=\"treeitem\""))
  assert_true(html.contains("git-graph-load-more-label"))
  assert_true(html.contains(">Load more</span>"))
  let collapsed = render_review_html(
    tree_pane(
      test_emit(),
      { ..graph_fixture_state(), changes_collapsed: true, },
      test_ctx(),
    ),
  )
  assert_true(collapsed.contains("review-git-layout changes-collapsed"))
  assert_true(collapsed.contains("review-split-handle hidden"))
}

///|
test "Git graph SVG ports VS Code merge and duplicate-lane curves" {
  let merge = render_review_html(
    git_graph_cell(
      {
        input_swimlanes: [{ id: "b", color: 0, }],
        output_swimlanes: [{ id: "c", color: 0, }, { id: "d", color: 1, }],
      },
      graph_test_commit("b", ["c", "d"]),
      false,
    ),
  )
  assert_true(merge.contains("width=\"33\""))
  assert_true(merge.contains("M 11 11 A 11 11 0 0 1 22 22 M 11 11 H 11"))
  assert_true(merge.contains("git-graph-node-merge-outer"))
  assert_true(merge.contains("git-graph-node-merge-inner"))

  let converging = render_review_html(
    git_graph_cell(
      {
        input_swimlanes: [{ id: "c", color: 0, }, { id: "c", color: 1, }],
        output_swimlanes: [{ id: "e", color: 0, }],
      },
      graph_test_commit("c", ["e"]),
      false,
    ),
  )
  assert_true(converging.contains("width=\"33\""))
  assert_true(converging.contains("M 22 0 A 11 11 0 0 1 11 11 H 11"))

  let placeholder = render_review_html(
    git_graph_placeholder(
      [{ id: "e", color: 0, }, { id: "d", color: 1, }],
      Some(1),
    ),
  )
  assert_true(placeholder.contains("width=\"33\""))
  assert_true(placeholder.contains("git-graph-edge-highlight"))
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
test "historical tabs use only the inert diff surface and history controls" {
  let diff : @dock.GitHistoryDiff = {
    commit: "1111111111111111111111111111111111111111",
    parent: Some("0000000000000000000000000000000000000000"),
    path: @pathx.Relative("src/main.mbt"),
    original_path: None,
    status: "modified",
    kind: "file",
  }
  let key = history_diff_key(diff)
  let history_docs : Map[String, HistoryDiffDoc] = Map([])
  history_docs[key] = {
    diff,
    generation: 1,
    original: HistoryBlobContent("old"),
    modified: HistoryBlobContent("new"),
  }
  let state = { ..graph_fixture_state(), history_docs, }
  let ctx = {
    ..test_ctx(),
    open_history_diffs: [diff],
    active_history_diff: Some(diff),
  }
  let body = render_review_html(body_view(test_emit(), state, ctx))
  assert_true(
    body.contains(
      "id=\"viewer-host\" class=\"viewer-host editor-shell moonbit-viewer-surface-hidden\"",
    ),
  )
  assert_true(
    body.contains("id=\"diff-editor-host\" class=\"viewer-host editor-shell\""),
  )
  inspect(
    render_review_control(review_diff_mode_toolbar(test_emit(), state, ctx)),
    content=(
      #|<div role="toolbar" aria-label="Comparison algorithm" class="review-mode-toolbar review-history-mode-toolbar">
      #|<button data-diff-mode="core" aria-label="Line diff" aria-pressed="true" title="Use Line diff" type="button" class="review-mode-button active">Line</button>
      #|<button data-diff-mode="token" aria-label="Token diff" aria-pressed="false" title="Use Token diff" type="button" class="review-mode-button">Token</button>
      #|<button data-diff-mode="tree" aria-label="Tree diff" aria-pressed="false" title="Use Tree diff" type="button" class="review-mode-button">Tree</button>
      #|</div>
    ),
  )
  inspect(
    render_review_control(review_diff_layout_toggle(test_emit(), state, ctx)),
    content=(
      #|<div role="group" aria-label="Diff layout" class="review-layout-control">
      #|<button data-layout="side-by-side" aria-label="Split diff layout" aria-pressed="true" title="Use side-by-side diff layout" type="button" class="review-layout-button active">Split</button>
      #|<button data-layout="inline" aria-label="Unified diff layout" aria-pressed="false" title="Use unified diff layout" type="button" class="review-layout-button">Unified</button>
      #|</div>
    ),
  )
  inspect(
    render_review_control(review_comments_control(test_emit(), state, ctx)),
    content=(
      #|<button aria-label="Ignore comments" aria-pressed="false" title="Available in Token and Tree diff" type="button" class="review-comments-control" disabled>Comments: ignored</button>
    ),
  )
  inspect(
    render_review_control(review_diff_navigation(test_emit(), state, ctx)),
    content=(
      #|<div role="group" aria-label="Diff change navigation" class="review-diff-navigation">
      #|<button data-action="previous-diff-change" aria-label="Previous change" aria-keyshortcuts="Shift+F7" title="Previous change (Shift+F7)" type="button" class="review-nav-button" disabled>
      #|<span aria-hidden="true" class="icon">
      #|<svg>…</svg>
      #|</span>
      #|</button>
      #|<button data-action="next-diff-change" aria-label="Next change" aria-keyshortcuts="F7" title="Next change (F7)" type="button" class="review-nav-button" disabled>
      #|<span aria-hidden="true" class="icon">
      #|<svg>…</svg>
      #|</span>
      #|</button>
      #|</div>
    ),
  )
  inspect(
    render_review_control(
      review_diff_navigation(
        test_emit(),
        { ..state, review_diff_navigation_available: true, },
        ctx,
      ),
    ),
    content=(
      #|<div role="group" aria-label="Diff change navigation" class="review-diff-navigation">
      #|<button data-action="previous-diff-change" aria-label="Previous change" aria-keyshortcuts="Shift+F7" title="Previous change (Shift+F7)" type="button" class="review-nav-button">
      #|<span aria-hidden="true" class="icon">
      #|<svg>…</svg>
      #|</span>
      #|</button>
      #|<button data-action="next-diff-change" aria-label="Next change" aria-keyshortcuts="F7" title="Next change (F7)" type="button" class="review-nav-button">
      #|<span aria-hidden="true" class="icon">
      #|<svg>…</svg>
      #|</span>
      #|</button>
      #|</div>
    ),
  )

  let text_diff = { ..diff, path: @pathx.Relative("README.md"), }
  let text_history_docs : Map[String, HistoryDiffDoc] = Map([])
  text_history_docs[history_diff_key(text_diff)] = {
    diff: text_diff,
    generation: 1,
    original: HistoryBlobContent("old"),
    modified: HistoryBlobContent("new"),
  }
  let text_state = {
    ..state,
    history_docs: text_history_docs,
    review_diff_mode: ReviewDiffTree,
    review_diff_status: Some({
      requested: ReviewDiffTree,
      effective: ReviewDiffToken,
      fell_back: true,
    }),
  }
  let text_ctx = {
    ..ctx,
    open_history_diffs: [text_diff],
    active_history_diff: Some(text_diff),
  }
  inspect(
    render_review_control(review_diff_status(text_state, text_ctx)),
    content=(
      #|<span role="status" aria-live="polite" class="review-diff-mode-status hidden">
      #|</span>
    ),
  )
}

///|
test "Git history replies are fenced by generation" {
  let state = {
    ..graph_fixture_state(),
    git_graph: GitGraphLoading,
    git_graph_generation: 3,
  }
  let reply : @protocol.GitHistoryReply = {
    repository: true,
    snapshot: { head: None, branch: None, refs: [], tips: [], },
    commits: [],
    has_more: false,
  }
  let (_, stale) = update(
    test_emit(),
    GitHistoryLoaded(owner=test_ctx().owner, generation=2, append=false, reply~),
    state,
    test_ctx(),
  )
  assert_true(stale.git_graph is GitGraphLoading)
  let (_, settled) = update(
    test_emit(),
    GitHistoryLoaded(owner=test_ctx().owner, generation=3, append=false, reply~),
    state,
    test_ctx(),
  )
  assert_true(
    settled.git_graph
    is GitGraphReady(repository=true, commits=[], has_more=false, ..),
  )
}

///|
test "Git history and commit failures keep explicit retry actions" {
  let graph_failed = render_review_html(
    tree_pane(
      test_emit(),
      {
        ..graph_fixture_state(),
        git_graph: GitGraphFailed("unknown command"),
        git_graph_selected: None,
        git_commit_files: GitCommitFilesIdle,
      },
      test_ctx(),
    ),
  )
  assert_true(
    graph_failed.contains("Could not load Git history: unknown command"),
  )
  assert_true(graph_failed.contains(">Retry</button>"))
  let commit_failed = render_review_html(
    tree_pane(
      test_emit(),
      {
        ..graph_fixture_state(),
        git_commit_files: GitCommitFilesFailed(
          commit="1111111111111111111111111111111111111111",
          message="object unavailable",
        ),
      },
      test_ctx(),
    ),
  )
  assert_true(
    commit_failed.contains("Could not load this commit: object unavailable"),
  )
  assert_true(commit_failed.contains("git-history-retry"))
}

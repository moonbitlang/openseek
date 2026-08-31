///|
#warnings("-alert_unstable")
fn render_review_html(node : @html.Html) -> String {
  @rabbita.render_to_string(() => @rabbita.Val::constant(node))
}

///|
/// Snapshot one toolbar control at a time. Icon presence stays visible while
/// SVG geometry remains outside these interaction tests.
fn render_review_control(node : @html.Html) -> String {
  let rendered = render_review_html(node).replace_all(old="><", new=">\n<")
  let lines : Array[String] = []
  let mut inside_svg = false
  for view in rendered.split("\n") {
    let line = "\{view}"
    if line.has_prefix("<svg ") {
      lines.push("<svg>…</svg>")
      inside_svg = true
    } else if line == "</svg>" {
      inside_svg = false
    } else if !inside_svg {
      lines.push(line)
    }
  }
  lines.join("\n")
}

///|
test "desktop review keeps sibling hosts stable across source and diff modes" {
  let path = @pathx.Relative("src/main.mbt")
  let ctx = { ..test_ctx(), open_files: [path], active_file: Some(path), }
  let selected = test_modified_change(path)
  let source_doc = {
    ..loaded_doc("src/main.mbt"),
    review: Some({
      generation: 1,
      working_generation: 1,
      baseline: ReviewContent("old source"),
      view_mode: ReviewSource,
      selected,
    }),
  }
  let source_docs = owned_state().docs.copy()
  source_docs[path] = source_doc
  let source_state = {
    ..owned_state(),
    docs: source_docs,
    explorer_mode: ExplorerChanges,
    changes: ChangeListReady(
      repository=true,
      files=[selected],
      refreshing=false,
      refresh_again=false,
    ),
  }
  let source = render_review_html(body_view(test_emit(), source_state, ctx))
  assert_true(
    source.contains("id=\"viewer-host\" class=\"viewer-host editor-shell\""),
  )
  assert_true(
    source.contains(
      "id=\"markdown-viewer-host\" class=\"viewer-host editor-shell moonbit-viewer-surface-hidden\"",
    ),
  )
  assert_true(
    source.contains(
      "id=\"diff-editor-host\" class=\"viewer-host editor-shell moonbit-viewer-surface-hidden\"",
    ),
  )
  inspect(
    render_review_control(review_mode_toolbar(test_emit(), source_state, ctx)),
    content=(
      #|<div role="toolbar" aria-label="Review mode" class="review-mode-toolbar">
      #|<button data-review-mode="file" aria-label="File view" aria-pressed="true" title="Show file" type="button" class="review-mode-button active">File</button>
      #|<span aria-hidden="true" class="review-mode-divider">
      #|</span>
      #|<button data-diff-mode="core" aria-label="Line diff" aria-pressed="false" title="Use Line diff" type="button" class="review-mode-button">Line</button>
      #|<button data-diff-mode="token" aria-label="Token diff" aria-pressed="false" title="Use Token diff" type="button" class="review-mode-button">Token</button>
      #|<button data-diff-mode="tree" aria-label="Tree diff" aria-pressed="false" title="Use Tree diff" type="button" class="review-mode-button">Tree</button>
      #|</div>
    ),
  )
  inspect(
    render_review_control(
      review_diff_layout_toggle(test_emit(), source_state, ctx),
    ),
    content=(
      #|<div role="group" aria-label="Diff layout" class="review-layout-control disabled">
      #|<button data-layout="side-by-side" aria-label="Split diff layout" aria-pressed="false" title="Use side-by-side diff layout" type="button" class="review-layout-button" disabled>Split</button>
      #|<button data-layout="inline" aria-label="Unified diff layout" aria-pressed="false" title="Use unified diff layout" type="button" class="review-layout-button" disabled>Unified</button>
      #|</div>
    ),
  )
  inspect(
    render_review_control(
      review_comments_control(test_emit(), source_state, ctx),
    ),
    content=(
      #|<button aria-label="Ignore comments" aria-pressed="false" title="Available in diff view" type="button" class="review-comments-control" disabled>Comments: ignored</button>
    ),
  )
  inspect(
    render_review_control(
      review_diff_navigation(test_emit(), source_state, ctx),
    ),
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

  let diff_doc = {
    ..source_doc,
    review: source_doc.review.map(review => { ..review, view_mode: ReviewDiff, }),
  }
  let diff_docs = source_docs.copy()
  diff_docs[path] = diff_doc
  let diff_state = { ..source_state, docs: diff_docs, }
  let diff = render_review_html(body_view(test_emit(), diff_state, ctx))
  assert_true(
    diff.contains(
      "id=\"viewer-host\" class=\"viewer-host editor-shell moonbit-viewer-surface-hidden\"",
    ),
  )
  assert_true(
    diff.contains(
      "id=\"markdown-viewer-host\" class=\"viewer-host editor-shell moonbit-viewer-surface-hidden\"",
    ),
  )
  assert_true(
    diff.contains("id=\"diff-editor-host\" class=\"viewer-host editor-shell\""),
  )
  inspect(
    render_review_control(review_mode_toolbar(test_emit(), diff_state, ctx)),
    content=(
      #|<div role="toolbar" aria-label="Review mode" class="review-mode-toolbar">
      #|<button data-review-mode="file" aria-label="File view" aria-pressed="false" title="Show file" type="button" class="review-mode-button">File</button>
      #|<span aria-hidden="true" class="review-mode-divider">
      #|</span>
      #|<button data-diff-mode="core" aria-label="Line diff" aria-pressed="true" title="Use Line diff" type="button" class="review-mode-button active">Line</button>
      #|<button data-diff-mode="token" aria-label="Token diff" aria-pressed="false" title="Use Token diff" type="button" class="review-mode-button">Token</button>
      #|<button data-diff-mode="tree" aria-label="Tree diff" aria-pressed="false" title="Use Tree diff" type="button" class="review-mode-button">Tree</button>
      #|</div>
    ),
  )
  inspect(
    render_review_control(
      review_diff_layout_toggle(test_emit(), diff_state, ctx),
    ),
    content=(
      #|<div role="group" aria-label="Diff layout" class="review-layout-control">
      #|<button data-layout="side-by-side" aria-label="Split diff layout" aria-pressed="true" title="Use side-by-side diff layout" type="button" class="review-layout-button active">Split</button>
      #|<button data-layout="inline" aria-label="Unified diff layout" aria-pressed="false" title="Use unified diff layout" type="button" class="review-layout-button">Unified</button>
      #|</div>
    ),
  )
  inspect(
    render_review_control(review_comments_control(test_emit(), diff_state, ctx)),
    content=(
      #|<button aria-label="Ignore comments" aria-pressed="false" title="Available in Token and Tree diff" type="button" class="review-comments-control" disabled>Comments: ignored</button>
    ),
  )
  inspect(
    render_review_control(
      review_diff_navigation(
        test_emit(),
        { ..diff_state, review_diff_navigation_available: true, },
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

  let fallback_state = {
    ..diff_state,
    review_diff_mode: ReviewDiffTree,
    review_diff_status: Some({
      requested: ReviewDiffTree,
      effective: ReviewDiffToken,
      fell_back: true,
    }),
  }
  inspect(
    render_review_control(review_diff_status(fallback_state, ctx)),
    content=(
      #|<span role="status" aria-live="polite" class="review-diff-mode-status">Tree unavailable — showing Token diff</span>
    ),
  )

  let core_fallback_state = {
    ..diff_state,
    review_diff_mode: ReviewDiffToken,
    review_diff_status: Some({
      requested: ReviewDiffToken,
      effective: ReviewDiffCore,
      fell_back: true,
    }),
  }
  inspect(
    render_review_control(review_diff_status(core_fallback_state, ctx)),
    content=(
      #|<span role="status" aria-live="polite" class="review-diff-mode-status">Token unavailable — showing Line diff</span>
    ),
  )

  inspect(
    render_review_control(
      review_diff_layout_toggle(
        test_emit(),
        { ..diff_state, review_diff_layout: ReviewInline, },
        ctx,
      ),
    ),
    content=(
      #|<div role="group" aria-label="Diff layout" class="review-layout-control">
      #|<button data-layout="side-by-side" aria-label="Split diff layout" aria-pressed="false" title="Use side-by-side diff layout" type="button" class="review-layout-button">Split</button>
      #|<button data-layout="inline" aria-label="Unified diff layout" aria-pressed="true" title="Use unified diff layout" type="button" class="review-layout-button active">Unified</button>
      #|</div>
    ),
  )

  let reviewed_state = { ..diff_state, reviewed_changes: [selected], }
  inspect(
    render_review_control(review_progress(test_emit(), reviewed_state, ctx)),
    content=(
      #|<button aria-label="Mark file reviewed" aria-pressed="true" title="Return this changed file to the review queue" type="button" class="review-badge review-progress reviewed">✓ Reviewed</button>
    ),
  )
  let reviewed_tree = render_review_html(
    tree_pane(test_emit(), reviewed_state, ctx),
  )
  assert_true(reviewed_tree.contains("1 of 1 reviewable files reviewed"))
  assert_true(reviewed_tree.contains("change-row selected reviewed"))
  assert_true(reviewed_tree.contains("id=\"changed-file-row-0\""))
}

///|
test "desktop explicitly routes Markdown source while DiffEditor stays code-only" {
  let path = @pathx.Relative("docs/Guide.MD")
  let ctx = { ..test_ctx(), open_files: [path], active_file: Some(path), }
  let docs = owned_state().docs.copy()
  docs[path] = loaded_doc(path.0)
  let source_state = { ..owned_state(), docs, }
  let source = render_review_html(body_view(test_emit(), source_state, ctx))
  assert_true(
    source.contains(
      "id=\"viewer-host\" class=\"viewer-host editor-shell moonbit-viewer-surface-hidden\"",
    ),
  )
  assert_true(
    source.contains(
      "id=\"markdown-viewer-host\" class=\"viewer-host editor-shell\"",
    ),
  )
  assert_true(
    source.contains(
      "id=\"diff-editor-host\" class=\"viewer-host editor-shell moonbit-viewer-surface-hidden\"",
    ),
  )

  let selected = test_modified_change(path)
  let diff_docs = docs.copy()
  diff_docs[path] = {
    ..loaded_doc(path.0),
    review: Some({
      generation: 1,
      working_generation: 1,
      baseline: ReviewContent("# Before"),
      view_mode: ReviewDiff,
      selected,
    }),
  }
  let diff = render_review_html(
    body_view(test_emit(), { ..source_state, docs: diff_docs, }, ctx),
  )
  assert_true(
    diff.contains(
      "id=\"viewer-host\" class=\"viewer-host editor-shell moonbit-viewer-surface-hidden\"",
    ),
  )
  assert_true(
    diff.contains(
      "id=\"markdown-viewer-host\" class=\"viewer-host editor-shell moonbit-viewer-surface-hidden\"",
    ),
  )
  assert_true(
    diff.contains("id=\"diff-editor-host\" class=\"viewer-host editor-shell\""),
  )
}

///|
test "non-MoonBit review keeps File and Line without specialized controls" {
  let path = @pathx.Relative("README.md")
  let ctx = { ..test_ctx(), open_files: [path], active_file: Some(path), }
  let selected = test_modified_change(path)
  let docs = owned_state().docs.copy()
  docs[path] = {
    ..loaded_doc(path.0),
    review: Some({
      generation: 1,
      working_generation: 1,
      baseline: ReviewContent("old text"),
      view_mode: ReviewDiff,
      selected,
    }),
  }
  let state = {
    ..owned_state(),
    docs,
    review_diff_mode: ReviewDiffTree,
    // Reproduce switching away after a Moon provider reported a fallback.
    review_diff_status: Some({
      requested: ReviewDiffTree,
      effective: ReviewDiffToken,
      fell_back: true,
    }),
  }
  inspect(
    render_review_control(review_mode_toolbar(test_emit(), state, ctx)),
    content=(
      #|<div role="toolbar" aria-label="Review mode" class="review-mode-toolbar">
      #|<button data-review-mode="file" aria-label="File view" aria-pressed="false" title="Show file" type="button" class="review-mode-button">File</button>
      #|<span aria-hidden="true" class="review-mode-divider">
      #|</span>
      #|<button data-diff-mode="core" aria-label="Line diff" aria-pressed="true" title="Use Line diff" type="button" class="review-mode-button active">Line</button>
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
      #|<span class="review-comments-control hidden">
      #|</span>
    ),
  )
  inspect(
    render_review_control(review_diff_status(state, ctx)),
    content=(
      #|<span role="status" aria-live="polite" class="review-diff-mode-status hidden">
      #|</span>
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
}

///|
test "pending full diff never reveals the source surface" {
  let path = @pathx.Relative("src/main.mbt")
  let ctx = { ..test_ctx(), open_files: [path], active_file: Some(path), }
  let selected = test_modified_change(path)
  let pending_doc = {
    ..loaded_doc(path.0),
    review: Some({
      generation: 1,
      working_generation: 1,
      baseline: ReviewLoading,
      view_mode: ReviewDiff,
      selected,
    }),
  }
  let pending_docs = owned_state().docs.copy()
  pending_docs[path] = pending_doc
  let pending_state = { ..owned_state(), docs: pending_docs, }
  let pending = render_review_html(body_view(test_emit(), pending_state, ctx))
  assert_true(
    pending.contains(
      "id=\"viewer-host\" class=\"viewer-host editor-shell moonbit-viewer-surface-hidden\"",
    ),
  )
  assert_true(
    pending.contains(
      "id=\"diff-editor-host\" class=\"viewer-host editor-shell\"",
    ),
  )
  assert_false(pending.contains("Loading diff for main.mbt…"))
  assert_true(pending.contains("viewer-notice diff-transition-shield"))
  let pending_breadcrumb = render_review_html(
    breadcrumb_view(test_emit(), pending_state, ctx),
  )
  assert_false(
    pending_breadcrumb.contains("aria-label=\"Diff change navigation\""),
  )

  let (_, delayed_state) = update(
    test_emit(),
    DiffLoadingDue(owner=test_ctx().owner, path~, generation=1),
    pending_state,
    ctx,
  )
  let delayed = render_review_html(body_view(test_emit(), delayed_state, ctx))
  assert_true(delayed.contains("Loading diff for main.mbt…"))
  assert_false(delayed.contains("viewer-notice diff-transition-shield"))

  // Once the baseline is known to be unavailable there is no comparison to
  // wait for, so the ordinary file surface becomes usable again.
  let unavailable_docs = pending_docs.copy()
  unavailable_docs[path] = {
    ..pending_doc,
    review: pending_doc.review.map(review => {
      ..review,
      baseline: ReviewFailed("missing baseline"),
    }),
  }
  let unavailable = render_review_html(
    body_view(test_emit(), { ..delayed_state, docs: unavailable_docs, }, ctx),
  )
  assert_true(
    unavailable.contains(
      "id=\"viewer-host\" class=\"viewer-host editor-shell\"",
    ),
  )
  assert_true(
    unavailable.contains(
      "id=\"diff-editor-host\" class=\"viewer-host editor-shell moonbit-viewer-surface-hidden\"",
    ),
  )
}

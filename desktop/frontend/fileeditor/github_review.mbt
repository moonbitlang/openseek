///|
let github_review_auto_layout : Ref[Bool] = Ref(false)

///|
priv enum GithubInlineContent {
  GithubThread(@protocol.GithubReviewThread)
  GithubDraft(@protocol.GithubDraftTarget)
}

///|
priv struct GithubInlineBlock {
  key : String
  original : Bool
  line : Int32
  content : GithubInlineContent
}

///|
fn github_review_side_matches(expected : String?, displayed : String) -> Bool {
  match expected {
    Some(contents) => contents == displayed
    // The editor displays an empty buffer for the absent side. Its absence
    // remains explicit in the snapshot and cannot acquire comment actions.
    None => displayed.is_empty()
  }
}

///|
fn github_review_matches(state : State, ctx : Ctx) -> Bool {
  guard ctx.active_history_diff is None &&
    ctx.active_file is Some(path) &&
    ctx.relative(path) is Some(relative) &&
    state.docs.get(path) is Some(doc) &&
    doc.visible_diff() is Some((original, modified)) &&
    state.github_review.file is Some(Ok(Some(file))) else {
    return false
  }
  file.path == relative.0 &&
  github_review_side_matches(file.original, original) &&
  github_review_side_matches(file.modified, modified)
}

///|
fn github_review_semantic_matches(state : State) -> Bool {
  guard state.semantic_review_input is Some(input) &&
    input.feedback_file is Some(path) &&
    state.github_review.file is Some(Ok(Some(file))) else {
    return false
  }
  file.path == path.0 &&
  github_review_side_matches(file.original, input.old_source) &&
  github_review_side_matches(file.modified, input.new_source)
}

///|
fn github_review_blocks(
  state : @github_review.State,
) -> Array[GithubInlineBlock] {
  guard state.enabled &&
    state.path is Some(path) &&
    state.review is Some(review) &&
    state.file is Some(Ok(Some(blob))) else {
    return []
  }
  let blocks : Array[GithubInlineBlock] = []
  for thread in review.threads {
    if thread.path == path &&
      !thread.outdated &&
      thread.line is Some(line) &&
      (if thread.side == "LEFT" { blob.original } else { blob.modified })
      is Some(_) &&
      line > 0 {
      blocks.push({
        key: "thread:" + thread.id,
        original: thread.side == "LEFT",
        line,
        content: GithubThread(thread),
      })
    }
  }
  let targets = state.drafts.map(draft => draft.target)
  if state.active is Some(target) && !targets.contains(target) {
    targets.push(target)
  }
  for target in targets {
    if target
      is @protocol.GithubDraftTarget::Line(path=file, side~, line~, head~) &&
      path == file &&
      head == review.head &&
      (if side == "LEFT" { blob.original } else { blob.modified }) is Some(_) {
      blocks.push({
        key: "draft:" + target.key(),
        original: side == "LEFT",
        line,
        content: GithubDraft(target),
      })
    }
  }
  blocks
}

///|
fn github_review_local_line(
  block : GithubInlineBlock,
  section : @moon_diff_provider.SemanticReviewSection?,
) -> Int32? {
  guard section is Some(section) else { return Some(block.line) }
  let side = if block.original {
    SemanticReviewOriginal
  } else {
    SemanticReviewModified
  }
  guard semantic_feedback_line_offset(section, side) is Some(offset) else {
    return None
  }
  let range = if block.original { section.old_range } else { section.new_range }
  if section.kind is @moon_diff_provider.SemanticReviewSectionKind::Whole {
    return Some(block.line)
  }
  guard range is Some(range) &&
    block.line >= range.start_line_number &&
    block.line < range.start_line_number + range.line_count else {
    return None
  }
  Some(block.line - offset)
}

///|
fn github_review_block_id(surface : String, key : String) -> String {
  "github-review-block:\{surface}:\{key}"
}

///|
fn github_review_target_line(
  section : @moon_diff_provider.SemanticReviewSection?,
  original : Bool,
  line : Int32,
) -> Int32? {
  guard line > 0 else { return None }
  guard section is Some(section) else { return Some(line) }
  let side = if original {
    SemanticReviewOriginal
  } else {
    SemanticReviewModified
  }
  if !(section.kind is @moon_diff_provider.SemanticReviewSectionKind::Whole) {
    let range = if original { section.old_range } else { section.new_range }
    guard range is Some(range) && line <= range.line_count else { return None }
  }
  semantic_feedback_line_offset(section, side).map(offset => line + offset)
}

///|
fn github_review_comment_target(
  state : @github_review.State,
  section : @moon_diff_provider.SemanticReviewSection?,
  original : Bool,
  line : Int32,
) -> @protocol.GithubDraftTarget? {
  guard state.file is Some(Ok(Some(file))) &&
    state.path is Some(path) &&
    state.review is Some(review) &&
    (if original { file.original } else { file.modified }) is Some(_) &&
    github_review_target_line(section, original, line) is Some(line) &&
    review.can_comment(path, original, line) else {
    return None
  }
  Some(
    @protocol.GithubDraftTarget::Line(
      path~,
      side=if original { "LEFT" } else { "RIGHT" },
      line~,
      head=review.head,
    ),
  )
}

///|
fn github_review_layer(
  locale~ : @i18n.Locale,
  dispatch : @cmd.Emit[Msg],
  state : @github_review.State,
  surface : String,
  section : @moon_diff_provider.SemanticReviewSection?,
  matching : Bool,
) -> @html.Html {
  let children : Map[String, @html.Html] = Map([])
  if matching {
    for block in github_review_blocks(state) {
      guard github_review_local_line(block, section) is Some(_) else {
        continue
      }
      let emit = dispatch.map(msg => GithubReview(msg))
      let content = match block.content {
        GithubThread(thread) =>
          @github_review.thread_view(locale~, state, emit, thread)
        GithubDraft(target) =>
          @html.section(
            class="github-review-thread",
            @github_review.composer(locale~, state, emit, target, true),
          )
      }
      children[block.key] = @html.div(
        class="github-review-inline-block",
        attrs=@html.Attrs::build().id(
          github_review_block_id(surface, block.key),
        ),
        content,
      )
    }
  }
  @html.div(class="github-review-inline-layer", children)
}

///|
fn github_review_line_layer(
  locale~ : @i18n.Locale,
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @html.Html {
  github_review_layer(
    locale~,
    dispatch,
    state.github_review,
    "line",
    None,
    github_review_matches(state, ctx) && state.semantic_review_input is None,
  )
}

///|
fn sync_github_review(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> (@cmd.Cmd, State) {
  let path = if ctx.active_history_diff is None {
    ctx.active_file.bind(path => ctx.relative(path)).map(path => path.0)
  } else {
    None
  }
  let (command, github_review) = @github_review.reconcile(
    dispatch.map(msg => GithubReview(msg)),
    state.github_review,
    ctx.github,
    path,
  )
  (command, { ..state, github_review, })
}

///|
/// Rabbita retains comment DOM ownership in a sibling overlay. The editor
/// reserves measured ViewZones and reports geometry; no node is reparented out
/// of the virtual DOM, so text selection, focus, and event lifetime stay intact.
fn github_review_place_node(
  node : @dom.Element,
  layout : (Double, Double, Double)?,
) -> Unit {
  guard node.as_node().get_parent_node().to_option() is Some(parent) &&
    parent.to_element() is Some(parent) else {
    return
  }
  let origin = parent.get_bounding_client_rect()
  guard layout is Some((left, top, width)) else {
    @base_browser.set_style_property(node, "visibility", "hidden")
    return
  }
  @base_browser.set_style_property(node, "visibility", "visible")
  @base_browser.set_style_property(
    node,
    "left",
    "\{left - origin.get_left()}px",
  )
  @base_browser.set_style_property(node, "top", "\{top - origin.get_top()}px")
  @base_browser.set_style_property(node, "width", "\{width}px")
  if node.query_selector("[data-github-review-focus]") is Some(input) {
    input.remove_attribute("data-github-review-focus")
    @base_browser.focus_prevent_scroll(input)
  }
}

///|
fn install_github_review_widgets(
  dispatch : @cmd.Emit[Msg],
  scheduler : &@cmd.Scheduler,
  state : @github_review.State,
  editor : @viewer.DiffEditor,
  surface : String,
  section : @moon_diff_provider.SemanticReviewSection?,
  matching : Bool,
) -> Unit {
  let widgets : Array[@viewer.DiffLineWidget] = []
  if matching && state.enabled {
    for block in github_review_blocks(state) {
      guard github_review_local_line(block, section) is Some(line) &&
        editor.get_model() is Some(pair) else {
        continue
      }
      let model = if block.original { pair.original } else { pair.modified }
      guard line <= model.get_line_count() &&
        @dom.document()
        .get_element_by_id(github_review_block_id(surface, block.key))
        .to_option()
        is Some(node) else {
        continue
      }
      widgets.push({
        original: block.original,
        line,
        node,
        on_layout: layout => github_review_place_node(node, layout),
      })
    }
  }
  editor.set_line_widgets(widgets)
  let allowed = (original : Bool, line : Int32) => {
    github_review_comment_target(state, section, original, line) is Some(_)
  }
  let action = if matching &&
    state.enabled &&
    !state.busy &&
    state.path is Some(_) &&
    state.review is Some(_) {
    Some((original : Bool, line : Int32) => {
      guard github_review_comment_target(state, section, original, line)
        is Some(target) else {
        return
      }
      scheduler.add(dispatch(GithubReview(@github_review.Compose(target))))
    })
  } else {
    None
  }
  editor.set_line_action(action, allowed~)
  if viewer_state.services is Some(services) && editor.get_model() is Some(pair) {
    for (original, model) in [(true, pair.original), (false, pair.modified)] {
      let enabled = !state.enabled &&
        (match section {
          Some(section) =>
            semantic_feedback_side_enabled(
              state.path.map(path => @pathx.Relative(path)),
              section,
              if original {
                SemanticReviewOriginal
              } else {
                SemanticReviewModified
              },
            )
          None => state.path is Some(_)
        })
      services.feedback.set_feedback_enabled(model.uri, enabled)
    }
  }
}

///|
fn sync_github_review_widgets(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @cmd.Cmd {
  @cmd.custom_cmd(
    scheduler => {
      if github_review_auto_layout.val != state.github_review.enabled {
        github_review_auto_layout.val = state.github_review.enabled
        viewer_state.diff_options = viewer_state.diff_options.with_automatic_inline(
          state.github_review.enabled,
          width=640.0,
        )
        if viewer_state.diff_editor is Some(editor) {
          editor.update_options(viewer_state.diff_options)
        }
        for _, entry in semantic_review_editors {
          entry.editor.update_options(
            semantic_diff_options(state.review_diff_layout),
          )
        }
      }
      let matching = ctx.panel_open && github_review_matches(state, ctx)
      if viewer_state.diff_editor is Some(editor) {
        install_github_review_widgets(
          dispatch,
          scheduler,
          state.github_review,
          editor,
          "line",
          None,
          matching && state.semantic_review_input is None,
        )
      }
      for key, entry in semantic_review_editors {
        install_github_review_widgets(
          dispatch,
          scheduler,
          state.github_review,
          entry.editor,
          key,
          Some(entry.section),
          matching && !state.semantic_review_collapsed.contains(key),
        )
      }
    },
    kind=@cmd.after_render,
  )
}

///|
fn github_review_status(
  locale~ : @i18n.Locale,
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @html.Html {
  let review = state.github_review
  let matching = github_review_matches(state, ctx)
  let inline_blocks = if matching {
    github_review_blocks(review).filter(block => {
      if state.semantic_review_input is None {
        return true
      }
      semantic_sections(state.semantic_review_plan).any(section => {
        !state.semantic_review_collapsed.contains(section.key) &&
        github_review_local_line(block, Some(section)) is Some(_)
      })
    })
  } else {
    []
  }
  let threads = review.review
    .map(pr => {
      pr.threads.filter(thread => {
        Some(thread.path) == review.path &&
        !inline_blocks.any(block => block.key == "thread:" + thread.id)
      })
    })
    .unwrap_or([])
  let drafts = review.drafts
    .map(draft => draft.target)
    .filter(target => {
      target is @protocol.GithubDraftTarget::Line(path~, ..) &&
      Some(path) == review.path &&
      !inline_blocks.any(block => block.key == "draft:" + target.key())
    })
  @github_review.status_view(
    locale~,
    review,
    dispatch.map(msg => GithubReview(msg)),
    matching,
    threads,
    drafts,
    update_pr=dispatch(UpdatePullRequest),
    updating=ctx.github.checkout_busy(),
    current=ctx.github,
  )
}

///|
fn github_comment_fixture() -> (State, Ctx) raise {
  let (initial, ctx, change) = review_progress_state()
  let original = "///|\npub fn retry_delay(attempt : Int) -> Int {\n  500 * attempt\n}\n\n///|\npub fn max_retries() -> Int {\n  3\n}\n"
  let modified = "///|\npub fn retry_delay(attempt : Int) -> Int {\n  250 * attempt\n}\n\n///|\npub fn max_retries() -> Int {\n  5\n}\n"
  let current = {
    ..@github.State::empty(),
    scope: Some({
      channel: @interop.Local,
      cwd: "/work",
      branch: Some("feature"),
      head: Some("head"),
    }),
    current: Some(
      Ok({
        branch: Some("feature"),
        pull_request_url: Some("https://github.com/owner/project/pull/42"),
        has_open_pull_request: true,
      }),
    ),
  }
  let review : @protocol.GithubReview = {
    url: "https://github.com/owner/project/pull/42",
    head: "head",
    base: "base",
    threads: [],
    commentable: [
      {
        path: change.path.0,
        left_lines: [3, 8],
        right_lines: [1, 2, 3, 4, 5, 6, 7, 8, 9],
      },
    ],
  }
  let file : @protocol.GithubReviewFile = {
    path: change.path.0,
    original: Some(original),
    modified: Some(modified),
  }
  let docs = initial.docs.copy()
  docs[test_file(change.path.0)] = {
    ..reviewed_doc(change.path, change, baseline=original),
    state: TabLoaded(content=modified, sig="working"),
  }
  (
    {
      ..initial,
      docs,
      github_review: {
        ..@github_review.State::empty(),
        checkout: current.scope,
        path: Some(change.path.0),
        enabled: true,
        review: Some(review),
        file: Some(Ok(Some(file))),
        files: [(change.path.0, Some(file))],
      },
    },
    { ..ctx, github: current, },
  )
}

///|
test "GitHub comment actions admit only patch lines on present source sides" {
  let (state, _) = github_comment_fixture()
  let review = state.github_review
  for
    (original, line, expected) in [
      (true, 2, None),
      (true, 3, Some("LEFT")),
      (false, 2, Some("RIGHT")),
      (false, 33, None),
      (true, 0, None),
    ] {
    let actual = github_review_comment_target(review, None, original, line)
    assert_true(
      actual ==
      expected.map(side => {
        @protocol.GithubDraftTarget::Line(
          path="src/main.mbt",
          side~,
          line~,
          head="head",
        )
      }),
    )
  }
  let file = review.file.unwrap().unwrap().unwrap()
  for original in [true, false] {
    let missing = {
      ..review,
      file: Some(
        Ok(
          Some({
            ..file,
            original: if original {
              None
            } else {
              file.original
            },
            modified: if original {
              file.modified
            } else {
              None
            },
          }),
        ),
      ),
    }
    assert_true(
      github_review_comment_target(missing, None, original, 3) is None,
    )
    assert_true(
      github_review_comment_target(missing, None, !original, 3) is Some(_),
    )
  }
}

///|
test "Token and Tree comment drafts retain the full-file patch coordinate" {
  let (initial, ctx) = github_comment_fixture()
  let emit = test_emit()
  for mode in [ReviewDiffToken, ReviewDiffTree] {
    let (_, selected) = update(emit, ReviewDiffModeSelected(mode), initial, ctx)
    let (state, _) = sync(emit, selected, ctx)
    let sections = semantic_sections(state.semantic_review_plan)
    guard sections.filter(section => {
        section.original_source.contains("max_retries")
      })
      is [section] else {
      fail("expected the second function's semantic section")
    }
    let lines = section.original_source
      .split("\n")
      .map(line => line.to_owned())
      .collect()
    guard lines.search("  3") is Some(index) else {
      fail("the semantic section lost its changed source line")
    }
    guard github_review_comment_target(
        state.github_review,
        Some(section),
        true,
        index + 1,
      )
      is Some(target) else {
      fail("the changed source line must allow a GitHub comment")
    }
    let expected = @protocol.GithubDraftTarget::Line(
      path="src/main.mbt",
      side="LEFT",
      line=8,
      head="head",
    )
    assert_true(target == expected)
    let (_, composing) = update(emit, GithubReview(Compose(target)), state, ctx)
    let (_, edited) = update(
      emit,
      GithubReview(Edit(target, "Coordinate QA")),
      composing,
      ctx,
    )
    assert_true(
      edited.github_review.drafts ==
      [{ target: expected, body: "Coordinate QA", }],
    )
    assert_true(edited.github_review.active == Some(expected))
    assert_false(edited.github_review.busy)
    let (_, cancelled) = update(
      emit,
      GithubReview(Cancel(expected)),
      edited,
      ctx,
    )
    assert_true(cancelled.github_review.drafts.is_empty())
    assert_true(cancelled.github_review.active is None)
  }
}

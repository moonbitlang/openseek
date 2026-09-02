///|
priv enum ReviewHunkBridgeSurface {
  ReviewLineSurface
  ReviewSemanticSurface
} derive(Eq)

///|
/// The active review identity is shared by the permanent Line editor and the
/// currently visible semantic editors. Keeping only the visible surface here
/// prevents the parked Line editor from replacing a Token/Tree selection.
priv struct ReviewHunkBridgeTarget {
  change : ChangedFile
  review_generation : Int
  surface : ReviewHunkBridgeSurface
  semantic_input : SemanticReviewInput?
  active_hunk : ReviewHunk?
  dispatch : (Msg) -> Unit
}

///|
let review_hunk_bridge_target : Ref[ReviewHunkBridgeTarget?] = Ref(None)

///|
fn current_review_hunk_bridge_target(
  state : State,
  active_file : @pathx.Relative?,
  dispatch : (Msg) -> Unit,
) -> ReviewHunkBridgeTarget? {
  guard active_file is Some(path) &&
    state.docs.get(path) is Some({ review: Some(review), .. }) &&
    state.current_review_generation(review.selected, active_file)
    is Some(review_generation) else {
    return None
  }
  let active_hunk = state
    .active_review_hunk(active_file)
    .map(active => active.hunk)
  Some({
    change: review.selected,
    review_generation,
    surface: if state.semantic_review_input is Some(_) {
      ReviewSemanticSurface
    } else {
      ReviewLineSurface
    },
    semantic_input: state.semantic_review_input,
    active_hunk,
    dispatch,
  })
}

///|
fn sync_review_hunk_bridge_target(
  state : State,
  active_file : @pathx.Relative?,
  dispatch : (Msg) -> Unit,
) -> Unit {
  review_hunk_bridge_target.val = current_review_hunk_bridge_target(
    state, active_file, dispatch,
  )
  if review_hunk_bridge_target.val is Some({ surface: ReviewLineSurface, .. }) &&
    mounted_diff_editor() is Some(editor) {
    publish_line_review_active_hunk(editor, editor.get_active_hunk_index())
  }
}

///|
fn projected_review_hunk(
  editor : @viewer.DiffEditor,
  active_index : Int?,
  old_offset : Int?,
  new_offset : Int?,
) -> ReviewHunk? {
  guard active_index is Some(index) else { return None }
  let hunks = editor.get_hunks()
  guard index >= 0 && index < hunks.length() else { return None }
  let hunk = ReviewHunk::from_diff_hunk(hunks[index], old_offset, new_offset)
  if hunk.is_empty() {
    None
  } else {
    Some(hunk)
  }
}

///|
fn publish_review_active_hunk(
  surface : ReviewHunkBridgeSurface,
  hunk : ReviewHunk?,
) -> Unit {
  guard review_hunk_bridge_target.val is Some(target) &&
    target.surface == surface &&
    target.active_hunk != hunk else {
    return
  }
  review_hunk_bridge_target.val = Some({ ..target, active_hunk: hunk, })
  (target.dispatch)(
    ReviewActiveHunkChanged(
      change=target.change,
      review_generation=target.review_generation,
      hunk~,
    ),
  )
}

///|
fn publish_line_review_active_hunk(
  editor : @viewer.DiffEditor,
  active_index : Int?,
) -> Unit {
  guard review_hunk_bridge_target.val
    is Some({ surface: ReviewLineSurface, .. }) else {
    return
  }
  publish_review_active_hunk(
    ReviewLineSurface,
    projected_review_hunk(editor, active_index, Some(0), Some(0)),
  )
}

///|
fn publish_semantic_review_active_hunk(
  input : SemanticReviewInput,
  key : String,
  editor : @viewer.DiffEditor,
  section : @moon_diff_provider.SemanticReviewSection,
  active_index : Int?,
) -> Unit {
  guard review_hunk_bridge_target.val is Some(target) &&
    target.surface == ReviewSemanticSurface &&
    target.semantic_input == Some(input) &&
    semantic_review_active_key.val == Some(key) else {
    return
  }
  publish_review_active_hunk(
    ReviewSemanticSurface,
    projected_review_hunk(
      editor,
      active_index,
      semantic_feedback_line_offset(section, SemanticReviewOriginal),
      semantic_feedback_line_offset(section, SemanticReviewModified),
    ),
  )
}

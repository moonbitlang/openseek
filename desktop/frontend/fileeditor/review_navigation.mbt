///|
/// Exact Changes-row ordering also handles two reviews sharing one path.
fn review_navigation_neighbor(
  state : State,
  ctx : Ctx,
  previous : Bool,
) -> ChangedFile? {
  guard active_review_position(state, ctx) is Some((selected, _, total)) &&
    total > 1 else {
    return None
  }
  match review_neighbor(state, selected, if previous { -1 } else { 1 }) {
    Some(change) => Some(change)
    None => review_edge(state, selected, first=!previous)
  }
}

///|
/// The current hunk remains visible after marking; subsequent navigation only
/// visits hunks with outstanding changed lines, including partial coverage.
fn review_hunk_navigation_index(
  state : State,
  change : ChangedFile?,
  hunks : Array[ReviewHunk],
  current : Int?,
  previous : Bool,
) -> Int? {
  let mut index = match current {
    Some(index) => index + (if previous { -1 } else { 1 })
    None => if previous { hunks.length() - 1 } else { 0 }
  }
  while index >= 0 && index < hunks.length() {
    let hunk = hunks[index]
    if !hunk.is_empty() &&
      !(change is Some(change) &&
      state.review_hunk_state(change, hunk) == ReviewHunkViewed) {
      return Some(index)
    }
    index += if previous { -1 } else { 1 }
  }
  None
}

///|
fn review_editor_navigation_index(
  state : State,
  change : ChangedFile?,
  editor : @viewer.DiffEditor,
  old_offset : Int?,
  new_offset : Int?,
  previous : Bool,
  edge~ : Bool,
) -> Int? {
  guard editor.is_diff_up_to_date() else { return None }
  review_hunk_navigation_index(
    state,
    change,
    editor
    .get_hunks()
    .map(hunk => ReviewHunk::from_diff_hunk(hunk, old_offset, new_offset)),
    if edge {
      None
    } else {
      editor.get_active_hunk_index()
    },
    previous,
  )
}

///|
/// Select the predecessor without scrolling, then use the public reveal API
/// to reach the chosen hunk with a single scroll and reveal event.
fn reveal_review_editor_hunk(editor : @viewer.DiffEditor, index : Int) -> Unit {
  if index == 0 {
    editor.reveal_first_diff()
  } else {
    editor.select_hunk(index - 1)
    ignore(editor.reveal_next_change_without_wrap())
  }
  editor.focus()
}

///|
/// Arm only after opening the destination, so cached and newly loaded reviews
/// use the actual generation that owns the incoming content.
pub fn State::with_review_navigation_destination(
  self : State,
  ctx : Ctx,
  change : ChangedFile,
  last : Bool,
) -> State {
  guard ctx.resource(change.path).bind(file => self.docs.get(file))
    is Some({ review: Some(review), .. }) &&
    review.selected == change else {
    return self
  }
  {
    ..self,
    review_navigation_destination: Some((change, review.generation, last)),
  }
}

///|
fn reveal_semantic_review_edge(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
  last : Bool,
) -> (@cmd.Cmd, State) {
  let sections = semantic_sections(state.semantic_review_plan)
  let change = active_review_change(state, ctx)
  guard semantic_review_section_navigation_index(
      state,
      change,
      sections,
      None,
      last,
    )
    is Some(index) else {
    return (@cmd.none, state)
  }
  let key = sections[index].key
  (dispatch(RevealSemanticReviewSectionChange(key, last)), state)
}

///|
/// Reconciliation runs after accepted content replies and before the render.
/// Cancel a stale destination instead of moving a later tab when a read settles.
fn sync_review_navigation_destination(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> (@cmd.Cmd, State) {
  guard state.review_navigation_destination is Some((change, generation, last)) else {
    return (@cmd.none, state)
  }
  let cleared = { ..state, review_navigation_destination: None, }
  let cancelled = { ..cleared, review_navigation_remaining: None, }
  guard ctx.active_history_diff is None &&
    ctx.active_file.bind(file => ctx.relative(file)) == Some(change.path) &&
    ctx.resource(change.path).bind(file => state.docs.get(file)) is Some(doc) &&
    doc.review is Some(review) &&
    review.selected == change &&
    review.generation == generation &&
    review.view_mode is ReviewDiff else {
    return (@cmd.none, cancelled)
  }
  if doc.state is TabLoading || review.baseline is ReviewLoading {
    return (@cmd.none, state)
  }
  guard full_diff_ready(state, ctx) else { return (@cmd.none, cancelled) }
  if !state.review_navigation_ready(ctx) {
    return (@cmd.none, state)
  }
  if line_diff_ready(state, ctx) {
    guard mounted_diff_editor() is Some(editor) &&
      editor.is_diff_up_to_date() &&
      editor.get_diff() is Some(_) else {
      return (@cmd.none, state)
    }
    // Logical changes are ready before the next render commits hunk geometry.
    // Leave hunk selection to the after-render reveal command.
    if projected_review_file_changes(editor) is Some(file_changes) &&
      state.review_hunk_state(change, file_changes) != ReviewHunkViewed {
      (reveal_line_review_edge(state, ctx, last), cancelled)
    } else {
      (dispatch(ReviewDiffFileBoundary(last)), cleared)
    }
  } else {
    let sections = semantic_sections(state.semantic_review_plan)
    if semantic_review_section_navigation_index(
        state,
        Some(change),
        sections,
        None,
        last,
      )
      is Some(_) {
      reveal_semantic_review_edge(dispatch, cancelled, ctx, last)
    } else {
      (dispatch(ReviewDiffFileBoundary(last)), cleared)
    }
  }
}

///|
priv suberror ReviewDiffNavigationSubscription {
  ReviewDiffNavigationSubscription(@cmd.Emit[Msg])
}

///|
fn review_diff_navigation_sub_loader(
  payload : Error,
  scheduler : &Scheduler,
) -> @sub.RunningSub? {
  match payload {
    ReviewDiffNavigationSubscription(dispatch) => {
      let mut dispatch = dispatch
      let target = @dom.document().as_event_target()
      let listener : @dom.Listener = event => {
        guard event.to_keyboard_event() is Some(keyboard) &&
          review_diff_shortcut_message(keyboard) is Some(message) &&
          [
            SemanticReviewHostId,
            DiffEditorHostId,
            "review-navigation-controls",
            "review-change-navigation",
          ].any(id => {
            guard @dom.document().get_element_by_id(id).to_option()
              is Some(host) else {
              return false
            }
            @base_browser.event_target_has_matching_ancestor(
              event,
              host,
              if id == SemanticReviewHostId {
                ".semantic-diff-entry"
              } else if id == DiffEditorHostId {
                ".moonbit-diff-editor"
              } else if id == "review-navigation-controls" {
                ".review-navigation-controls"
              } else {
                ".review-diff-navigation"
              },
            ) &&
            !@base_browser.event_target_has_matching_ancestor(
              event, host, "input, textarea, select, [contenteditable]:not([contenteditable=\"false\"]), [role=\"textbox\"]",
            )
          }) else {
          return
        }
        // Include collapsed section headers and capture before the child
        // DiffEditor, so keys and buttons share the host's review policy.
        event.prevent_default()
        event.stop_propagation()
        scheduler.add(dispatch(message))
      }
      target.add_event_listener_with_options("keydown", listener, capture=true)
      Some({
        unload: _ => {
          target.remove_event_listener_with_options(
            "keydown",
            listener,
            capture=true,
          )
        },
        update_tagger: payload => {
          guard payload is ReviewDiffNavigationSubscription(next) else {
            return
          }
          dispatch = next
        },
      })
    }
    _ => None
  }
}

///|
fn review_diff_shortcut_message(keyboard : @dom.KeyboardEvent) -> Msg? {
  guard !keyboard.ctrl_key() &&
    !keyboard.meta_key() &&
    !keyboard.alt_key() &&
    !keyboard.is_composing() &&
    !keyboard.repeat() else {
    return None
  }
  if keyboard.key() == "F7" {
    return Some(
      if keyboard.shift_key() {
        RevealPreviousReviewDiffChange
      } else {
        RevealNextReviewDiffChange
      },
    )
  }
  guard !keyboard.shift_key() else { return None }
  match keyboard.key() {
    "n" => Some(RevealNextReviewDiffChange)
    "p" => Some(RevealPreviousReviewDiffChange)
    "m" => Some(ToggleActiveReviewHunk)
    _ => None
  }
}

///|
fn review_diff_navigation_subscription(
  state : State,
  ctx : Ctx,
  dispatch : @cmd.Emit[Msg],
) -> @sub.Sub {
  // Keep marking available after the final outstanding change is reviewed.
  guard review_diff_navigation_enabled(state, ctx) ||
    (
      ctx.active_history_diff is None &&
      ctx.active_file.bind(path => state.docs.get(path))
      is Some({ review: Some({ view_mode: ReviewDiff, .. }), .. }) &&
      active_review_change(state, ctx) is Some(_)
    ) else {
    return @sub.none
  }
  @sub.custom_sub(
    "fileeditor-review-diff-navigation",
    @sub.Local,
    ReviewDiffNavigationSubscription(dispatch),
    review_diff_navigation_sub_loader,
  )
}

///|
/// Only small presentation values are retained, never an old State or callbacks.
pub struct ReviewNavigationDisplay {
  priv file_position : (Int, Int)?
  priv position : ReviewHunkPosition?
  priv hunk_toggle : (ReviewHunkState, Bool)?
  priv enabled : Bool
} derive(Eq)

///|
fn review_navigation_complete(state : State, ctx : Ctx) -> Bool {
  ctx.active_file is Some(path) &&
  state.docs.get(path) is Some(doc) &&
  doc.review is Some(review) &&
  (
    review.view_mode is ReviewSource ||
    (
      !doc.diff_is_pending() &&
      (doc.diff_content() is None || state.review_navigation_ready(ctx))
    )
  )
}

///|
fn current_review_navigation_display(
  state : State,
  ctx : Ctx,
) -> ReviewNavigationDisplay {
  let active = state.active_review_hunk(ctx)
  {
    file_position: active_review_position(state, ctx).map(position => {
      (position.1, position.2)
    }),
    position: active.bind(active => active.position),
    hunk_toggle: active.map(active => {
      (
        state.review_hunk_state(active.change, active.hunk),
        state.is_change_reviewed(active.change) && active.file_changes is None,
      )
    }),
    enabled: review_diff_navigation_enabled(state, ctx),
  }
}

///|
fn State::sync_review_navigation_display(self : State, ctx : Ctx) -> State {
  let display = if ctx.active_history_diff is Some(_) ||
    !ctx.checkout_ready() ||
    !(ctx.active_file is Some(path) &&
    self.docs.get(path) is Some({ review: Some(_), .. })) {
    None
  } else if review_navigation_complete(self, ctx) {
    Some(current_review_navigation_display(self, ctx))
  } else {
    self.review_navigation_display
  }
  { ..self, review_navigation_display: display, }
}

///|
pub extend ReviewNavigationDisplay with Eq::{equal, not_equal}

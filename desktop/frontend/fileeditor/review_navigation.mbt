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
  last : Bool,
) -> (@cmd.Cmd, State) {
  let sections = semantic_sections(state.semantic_review_plan)
  guard !sections.is_empty() else { return (@cmd.none, state) }
  let key = sections[if last { sections.length() - 1 } else { 0 }].key
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
  guard ctx.active_history_diff is None &&
    ctx.active_file.bind(file => ctx.relative(file)) == Some(change.path) &&
    ctx.resource(change.path).bind(file => state.docs.get(file)) is Some(doc) &&
    doc.review is Some(review) &&
    review.selected == change &&
    review.generation == generation &&
    review.view_mode is ReviewDiff else {
    return (@cmd.none, cleared)
  }
  if doc.state is TabLoading || review.baseline is ReviewLoading {
    return (@cmd.none, state)
  }
  guard full_diff_ready(state, ctx) else { return (@cmd.none, cleared) }
  if line_diff_ready(state, ctx) {
    (reveal_line_review_edge(last), cleared)
  } else {
    reveal_semantic_review_edge(dispatch, cleared, last)
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
          keyboard.key() == "F7" &&
          [SemanticReviewHostId, DiffEditorHostId, "review-change-navigation"].any(id => {
              @dom.document().get_element_by_id(id).to_option() is Some(host) &&
              @base_browser.event_target_has_matching_ancestor(
                event,
                host,
                if id == SemanticReviewHostId {
                  ".semantic-diff-entry"
                } else if id == DiffEditorHostId {
                  ".moonbit-diff-editor"
                } else {
                  ".review-diff-navigation"
                },
              )
            },
          ) else {
          return
        }
        // Include collapsed section headers and capture before the child
        // DiffEditor, so buttons and F7 share the host's file boundaries.
        event.prevent_default()
        event.stop_propagation()
        scheduler.add(
          dispatch(
            if keyboard.shift_key() {
              RevealPreviousReviewDiffChange
            } else {
              RevealNextReviewDiffChange
            },
          ),
        )
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
fn review_diff_navigation_subscription(
  state : State,
  ctx : Ctx,
  dispatch : @cmd.Emit[Msg],
) -> @sub.Sub {
  guard review_diff_navigation_enabled(state, ctx) else { return @sub.none }
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

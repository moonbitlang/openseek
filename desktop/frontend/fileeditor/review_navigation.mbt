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
  destination : ReviewDestination,
) -> State {
  guard ctx.resource(change.path).bind(file => self.docs.get(file))
    is Some({ review: Some(review), .. }) &&
    review.selected == change else {
    return self
  }
  {
    ..self,
    review_diff_mode: if destination is ReviewLine(_) {
      ReviewDiffLine
    } else {
      self.review_diff_mode
    },
    review_navigation_destination: Some(
      (change, review.generation, destination),
    ),
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
/// A recorded line survives status-only inventory updates for the same file
/// and generation; edge navigation still follows an exact Changes row.
fn sync_review_navigation_destination(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> (@cmd.Cmd, State) {
  guard state.review_navigation_destination
    is Some((change, generation, destination)) else {
    return (@cmd.none, state)
  }
  let cleared = { ..state, review_navigation_destination: None, }
  guard ctx.active_history_diff is None &&
    ctx.active_file.bind(file => ctx.relative(file)) == Some(change.path) &&
    ctx.resource(change.path).bind(file => state.docs.get(file)) is Some(doc) &&
    doc.review is Some(review) &&
    (
      review.selected == change ||
      (destination is ReviewLine(_) && review.selected.path == change.path)
    ) &&
    review.generation == generation &&
    review.view_mode is ReviewDiff else {
    return (@cmd.none, cleared)
  }
  if doc.state is TabLoading || review.baseline is ReviewLoading {
    return (@cmd.none, state)
  }
  guard full_diff_ready(state, ctx) else { return (@cmd.none, cleared) }
  match destination {
    ReviewLine(line) => (ReviewDestination::reveal_line(line), cleared)
    ReviewEdge(last) =>
      if line_diff_ready(state, ctx) {
        (reveal_line_review_edge(last), cleared)
      } else {
        reveal_semantic_review_edge(dispatch, cleared, last)
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

///|
/// A transcript position is a source line, while cross-file F7 navigation
/// selects an edge of the current changes. Neither is inferred from text.
pub(all) enum ReviewDestination {
  ReviewEdge(Bool)
  ReviewLine(Int)
} derive(Eq)

///|
fn ReviewDestination::reveal_line(line : Int) -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      if mounted_diff_editor() is Some(editor) {
        editor.reveal_modified_line(line)
        editor.focus()
      }
    },
    kind=@cmd.after_render,
  )
}

///|
/// Prefer the current inventory's rename/deletion metadata. A transcript can
/// also refer to a now-clean file or arrive before the inventory is loaded;
/// those paths still have a valid HEAD-versus-working-tree review.
fn State::change_for_review(
  self : State,
  path : @pathx.Relative,
) -> ChangedFile {
  if self.changes is ChangeListReady(files~, ..) {
    for change in files {
      if change.path == path {
        return change
      }
    }
  }
  {
    path,
    original_path: None,
    kind: ChangeModified,
    index_status: " ",
    worktree_status: " ",
  }
}

///|
pub extend ReviewDestination with Eq::{equal, not_equal}

///|
/// Open a file comparison independently of membership in the Changes list.
/// A clean file still has a HEAD/current pair and can reveal a recorded line.
pub fn State::open_review_at(
  self : State,
  dispatch : @cmd.Emit[Msg],
  ctx : Ctx,
  path : @pathx.Relative,
  line : Int?,
  had_active~ : Bool,
) -> (@cmd.Cmd, State) {
  guard ctx.resource(path) is Some(file) else { return (@cmd.none, self) }
  let change = self.change_for_review(path)
  guard ctx.placement_ready() && change.selectable() else {
    return (@cmd.none, self)
  }
  let (cmd, state) = open_changed_document(
    dispatch,
    self,
    ctx,
    change,
    had_active~,
  )
  let state = state.with_review_navigation_destination(
    ctx,
    change,
    line.map(line => ReviewLine(line)).unwrap_or(ReviewEdge(false)),
  )
  (
    @cmd.batch([mount_cmds(dispatch), cmd]),
    {
      ..state,
      file_review_paths: [
        ..state.file_review_paths.filter(path => path != file),
        file,
      ],
    },
  )
}

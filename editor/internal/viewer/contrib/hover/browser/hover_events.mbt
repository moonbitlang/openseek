// The mouse-facing half of the hover input bridge, relocated from
// `internal/viewer/contrib/hover` (2026-07-09): everything whose signature
// carries the hit-test target lives browser-side, mirroring Monaco — the
// source's `ContentHoverWidgetWrapper.showsOrWillShow` /
// `_findHoverAnchorCandidates` (`contentHoverWidgetWrapper.ts`) are
// `editor/contrib/hover/browser` code. The multi-target
// `internal/viewer/contrib/hover` package keeps the DOM-free hover model
// (`HoverController`, anchors, participants). Targets arrive **model-space**
// (the public-event boundary converts), exactly like the source's
// `IEditorMouseEvent`.

///|
/// Typed editor events produced by the input bridge. Feature controllers
/// consume these the way VS Code contributions consume editor events; no
/// controller sees raw DOM events. `pub(all)` because the viewer's dispatch
/// glue in the root package constructs these values across the package
/// boundary. That glue remains root-owned because it reads private Viewer
/// state and owns editor-event dispatch.
pub(all) enum EditorEvent {
  MouseMoved(@editor_browser.MouseTarget)
  EscapePressed
}

///|
/// Read-only viewer state controllers may consult while handling an event.
/// `participants` are the wrapper's `_participants` (their
/// `suggestHoverAnchor` pass runs inside `hover_on_event`),
/// `typical_halfwidth_character_width` feeds the `CONTENT_EMPTY` epsilon arm,
/// and `mouse_posx`/`mouse_posy` are the recorded pointer position the
/// anchors carry. `pub(all)` for the same cross-package reason as
/// `EditorEvent`.
pub(all) struct EditorContext {
  view_model : @view_model.ViewModel?
  participants : Array[@hover.HoverParticipantHandle]
  typical_halfwidth_character_width : Double
  mouse_posx : Double?
  mouse_posy : Double?
  /// Actual rendered widget primary position used by range-anchor adoption.
  show_at_position : @base_common.Position?
  /// Participant-selected logical visibility, including loading-only views.
  content_hover_visible : Bool
}

///|
/// The browser reducer for the `HoverController` owned by the multi-target
/// package. It is a public free function because the root Viewer calls it
/// across the package boundary; a private local method on the foreign
/// controller type would not provide that cross-package entrypoint. The
/// `MouseMoved` arm is Monaco's `showsOrWillShow`
/// (`contentHoverWidgetWrapper.ts:249-261`).
pub fn hover_on_event(
  controller : @hover.HoverController,
  event : EditorEvent,
  ctx : EditorContext,
  sticky_mouse_getting_closer~ : Bool = false,
) -> (@hover.HoverEffect, @hover.HoverController) {
  match event {
    MouseMoved(target) =>
      match ctx.view_model {
        Some(_) => {
          // Find the anchor candidates and start at the best one; no
          // candidate is the `_startShowingOrUpdateHover(null)` arm. (The
          // `isResizing` and code-action-widget early-keeps are sashes/N-A
          // concerns.) Positionless targets (widgets, unknown) contribute no
          // candidate — the source needs no explicit line-bounds gate and
          // neither does this.
          let candidates = find_anchor_candidates(
            ctx.participants,
            target,
            ctx.typical_halfwidth_character_width,
            initial_mouse_pos_x?=ctx.mouse_posx,
            initial_mouse_pos_y?=ctx.mouse_posy,
          )
          match candidates {
            [anchor, ..] =>
              controller.start_showing_or_update_hover(
                anchor,
                sticky_mouse_getting_closer,
                show_at_position?=ctx.show_at_position,
                live_widget_visible=ctx.content_hover_visible,
              )
            [] =>
              // No anchor under the pointer (Monaco
              // `_startShowingOrUpdateHover(null)`): a visible hover the
              // pointer is approaching is kept; otherwise hide.
              if sticky_mouse_getting_closer && ctx.content_hover_visible {
                (HoverNoEffect, controller)
              } else {
                (HoverNoEffect, controller.cleared())
              }
          }
        }
        None => (HoverNoEffect, controller)
      }
    EscapePressed => (HoverNoEffect, controller.cleared())
  }
}

///|
/// `ContentHoverWidgetWrapper._findHoverAnchorCandidates`
/// (`contentHoverWidgetWrapper.ts:263-296`): each participant may suggest a
/// (foreign-element) anchor for the target; a `CONTENT_TEXT` hit contributes
/// the priority-0 range anchor at the hit position, and a `CONTENT_EMPTY` hit
/// within half a typical halfwidth character past the end of the line
/// contributes the same (the epsilon arm — `!detail.isAfterLines &&
/// typeof detail.horizontalDistanceToText === 'number' && … < epsilon`,
/// with no lower bound: the distance is `>= 0` by construction). Candidates
/// sort by descending priority. `target.range` is already model-space.
fn find_anchor_candidates(
  participants : Array[@hover.HoverParticipantHandle],
  target : @editor_browser.MouseTarget,
  typical_halfwidth_character_width : Double,
  initial_mouse_pos_x? : Double,
  initial_mouse_pos_y? : Double,
) -> Array[@hover.HoverAnchor] {
  let anchor_candidates : Array[@hover.HoverAnchor] = []
  let injected_text = hover_target_injected_text(target)
  let target_range = target.range()
  append_suggested_anchors_from(
    anchor_candidates,
    participants,
    participant => participant.suggest_hover_anchor,
    injected_text,
    target_range,
    initial_mouse_pos_x,
    initial_mouse_pos_y,
  )
  finish_anchor_candidates(
    anchor_candidates, target, typical_halfwidth_character_width, initial_mouse_pos_x,
    initial_mouse_pos_y,
  )
}

///|
fn hover_target_injected_text(
  target : @editor_browser.MouseTarget,
) -> @view_model.InjectedText? {
  match target {
    MouseTargetContentText(detail~, ..) => detail.injected_text
    _ => None
  }
}

///|
/// The single iteration path used by both live participant handles and the
/// callback-level white-box seam. It adds no intermediate array on pointer
/// movement.
fn[T] append_suggested_anchors_from(
  anchor_candidates : Array[@hover.HoverAnchor],
  items : Array[T],
  suggestion_of : (T) -> ((
    @view_model.InjectedText?,
    @base_common.Range,
    Double?,
    Double?,
  ) -> @hover.HoverAnchor?)?,
  injected_text : @view_model.InjectedText?,
  target_range : @base_common.Range?,
  initial_mouse_pos_x : Double?,
  initial_mouse_pos_y : Double?,
) -> Unit {
  for item in items {
    append_suggested_anchor(
      anchor_candidates,
      suggestion_of(item),
      injected_text,
      target_range,
      initial_mouse_pos_x,
      initial_mouse_pos_y,
    )
  }
}

///|
fn append_suggested_anchor(
  anchor_candidates : Array[@hover.HoverAnchor],
  suggestion : ((
    @view_model.InjectedText?,
    @base_common.Range,
    Double?,
    Double?,
  ) -> @hover.HoverAnchor?)?,
  injected_text : @view_model.InjectedText?,
  target_range : @base_common.Range?,
  initial_mouse_pos_x : Double?,
  initial_mouse_pos_y : Double?,
) -> Unit {
  match (target_range, suggestion) {
    (Some(range), Some(suggest_hover_anchor)) =>
      match
        suggest_hover_anchor(
          injected_text, range, initial_mouse_pos_x, initial_mouse_pos_y,
        ) {
        Some(anchor) => anchor_candidates.push(anchor)
        None => ()
      }
    _ => ()
  }
}

///|
fn finish_anchor_candidates(
  anchor_candidates : Array[@hover.HoverAnchor],
  target : @editor_browser.MouseTarget,
  typical_halfwidth_character_width : Double,
  initial_mouse_pos_x : Double?,
  initial_mouse_pos_y : Double?,
) -> Array[@hover.HoverAnchor] {
  match target {
    MouseTargetContentText(range~, ..) =>
      anchor_candidates.push(
        HoverRangeAnchor(
          priority=0,
          range~,
          initial_mouse_pos_x~,
          initial_mouse_pos_y~,
        ),
      )
    MouseTargetContentEmpty(range~, detail~, ..) => {
      let epsilon = typical_halfwidth_character_width / 2.0
      // Let hover kick in even when the mouse is technically in the empty
      // area after a line, given the distance is small enough
      let mouse_is_within_lines_and_close_to_hover = !detail.is_after_lines &&
        detail.horizontal_distance_to_text is Some(distance) &&
        distance < epsilon
      if mouse_is_within_lines_and_close_to_hover {
        anchor_candidates.push(
          HoverRangeAnchor(
            priority=0,
            range~,
            initial_mouse_pos_x~,
            initial_mouse_pos_y~,
          ),
        )
      }
    }
    _ => ()
  }
  sort_hover_anchor_candidates_stably(anchor_candidates)
}

///|
/// Source JavaScript sorting is stable. MoonBit sorting is not, so retain the
/// insertion index as an explicit tie-breaker after descending priority.
fn sort_hover_anchor_candidates_stably(
  candidates : Array[@hover.HoverAnchor],
) -> Array[@hover.HoverAnchor] {
  let indexed : Array[(Int32, @hover.HoverAnchor)] = []
  for index, anchor in candidates {
    indexed.push((index, anchor))
  }
  indexed.sort_by((left, right) => {
    let priority = right.1.priority() - left.1.priority()
    if priority != 0 {
      priority
    } else {
      left.0 - right.0
    }
  })
  indexed.map(item => item.1)
}

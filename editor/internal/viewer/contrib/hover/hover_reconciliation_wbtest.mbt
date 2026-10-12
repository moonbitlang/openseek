// Phase 4 of `monaco-hover-logic-chain-port.md`, increment 3: the shown-hover
// reconciliation (`_startShowingOrUpdateHover` / `_withResult` /
// `_setCurrentResult`). One case per behavior-switching branch.

///|
fn anchor_at(start : Int32, end : Int32, line : Int32) -> HoverAnchor {
  HoverRangeAnchor(
    priority=0,
    range=Range(line, start + 1, line, end + 1),
    initial_mouse_pos_x=None,
    initial_mouse_pos_y=None,
  )
}

///|
/// A complete shown hover for the `[3, 7)` anchor on line 1, with one markdown
/// part covering that span.
fn shown_complete_hover() -> HoverController {
  let (_, armed) = HoverController::empty().start_delayed(3, 7)
  let (_, second) = armed.op_trigger_async(1)
  // Async finishes before the sync compute, so the sync trigger completes
  // straight to Idle: the shown result is complete.
  let done = second.op_async_done(1)
  done.op_trigger_sync(1, [markdown_part(3, 7, "hello")])
}

///|
test "reconciliation: the same anchor keeps the shown hover untouched" {
  let shown = shown_complete_hover()
  assert_true(shown.view is Some(_))
  let (effect, after) = shown.start_showing_or_update_hover(
    anchor_at(3, 7, 1),
    false,
  )
  assert_true(effect is HoverNoEffect)
  // No operation restart, no result change.
  assert_true(after == shown)
}

///|
test "reconciliation: a compatible anchor keeps the still-valid parts and restarts the operation" {
  let shown = shown_complete_hover()
  let token_before = shown.operation.token
  // (4, 6) is on the same line and inside the shown part's [3, 7) range.
  let (effect, after) = shown.start_showing_or_update_hover(
    anchor_at(4, 6, 1),
    false,
  )
  assert_true(effect is HoverScheduleDelayed(_))
  // The old part survives the filter, so the hover stays visible meanwhile.
  match after.view {
    Some(view) => {
      assert_eq(view.parts.length(), 1)
      assert_true(view.parts[0] == markdown_part(3, 7, "hello"))
    }
    None => fail("expected the compatible hover to stay visible")
  }
  // A fresh operation is armed for the new anchor.
  assert_eq(after.operation.token, token_before + 1)
  assert_true(after.operation.state is HoverOpFirstWait)
}

///|
test "reconciliation: a compatible anchor outside the parts hides the hover then restarts" {
  let shown = shown_complete_hover()
  // Same line, but (10, 12) is outside the shown part's [3, 7) range.
  let (effect, after) = shown.start_showing_or_update_hover(
    anchor_at(10, 12, 1),
    false,
  )
  assert_true(effect is HoverScheduleDelayed(_))
  // The filter empties, so the hover hides while the new operation computes.
  assert_true(after.view is None)
  assert_true(after.operation.state is HoverOpFirstWait)
}

///|
test "reconciliation: an incompatible anchor (different line) hides the hover and restarts" {
  let shown = shown_complete_hover()
  let (effect, after) = shown.start_showing_or_update_hover(
    anchor_at(20, 24, 5),
    false,
  )
  assert_true(effect is HoverScheduleDelayed(_))
  assert_true(after.view is None)
  assert_true(after.operation.state is HoverOpFirstWait)
}

///|
test "withResult: a complete hover is kept until the new result completes" {
  let shown = shown_complete_hover()
  // Move to a compatible anchor: the old part stays visible, a new op is armed.
  let (_, updating) = shown.start_showing_or_update_hover(
    anchor_at(4, 6, 1),
    false,
  )
  let token = updating.operation.token
  assert_eq(updating.current_complete, true)
  // The new operation produces a different, still-incomplete result.
  let (_, second) = updating.op_trigger_async(token)
  let partial = second.op_trigger_sync(token, [markdown_part(4, 6, "new")])
  assert_true(partial.operation.state is HoverOpWaitingForAsync)
  // The previous complete hover is still shown — no flicker to the partial.
  match partial.view {
    Some(view) => assert_true(view.parts[0] == markdown_part(3, 7, "hello"))
    None => fail("expected the previous complete hover to remain")
  }
  // When the new operation completes, the shown result swaps to the new parts.
  let completed = partial.op_async_done(token)
  assert_true(completed.is_complete())
  match completed.view {
    Some(view) => assert_true(view.parts[0] == markdown_part(4, 6, "new"))
    None => fail("expected the completed result to be shown")
  }
}

///|
test "setCurrentResult: an empty complete result hides the shown hover" {
  let shown = shown_complete_hover()
  let (_, updating) = shown.start_showing_or_update_hover(
    anchor_at(4, 6, 1),
    false,
  )
  let token = updating.operation.token
  let (_, second) = updating.op_trigger_async(token)
  // The new operation completes empty (sync produced nothing, async done).
  let done = second.op_async_done(token)
  let emptied = done.op_trigger_sync(token, [])
  assert_true(emptied.is_complete())
  // A complete empty result is not held back (no insist), so the hover hides.
  assert_true(emptied.view is None)
}

///|
test "getting closer: keeps the shown hover and kicks an insist-update at the new anchor" {
  let shown = shown_complete_hover()
  let token_before = shown.operation.token
  // Sticky + mouse getting closer toward an incompatible anchor (different line):
  // without the keep this would hide; instead the current hover is kept.
  let (effect, after) = shown.start_showing_or_update_hover(
    anchor_at(20, 24, 5),
    true,
  )
  assert_true(effect is HoverScheduleDelayed(_))
  // The shown hover is untouched (no filter, no hide) while the update computes.
  match after.view {
    Some(view) => assert_true(view.parts[0] == markdown_part(3, 7, "hello"))
    None => fail("expected the approached hover to stay visible")
  }
  // A fresh operation is armed, insisting on keeping the hover visible.
  assert_eq(after.operation.token, token_before + 1)
  assert_eq(after.insist_on_keeping, true)
}

///|
test "getting closer: an empty insist-update keeps the previous hover instead of hiding" {
  let shown = shown_complete_hover()
  let (_, updating) = shown.start_showing_or_update_hover(
    anchor_at(20, 24, 5),
    true,
  )
  let token = updating.operation.token
  let (_, second) = updating.op_trigger_async(token)
  // The insist-update resolves empty (the new anchor has no hover).
  let done = second.op_async_done(token)
  let resolved = done.op_trigger_sync(token, [])
  assert_true(resolved.is_complete())
  // insist + empty -> the previous complete hover is kept (Monaco
  // `shouldKeepPreviousHoverVisible`), not hidden.
  match resolved.view {
    Some(view) => assert_true(view.parts[0] == markdown_part(3, 7, "hello"))
    None =>
      fail("expected the previous hover to be kept on an empty insist-update")
  }
}

///|
test "withResult: empty insist still clears a previous incomplete hover" {
  let (_, first) = HoverController::empty().start_showing_or_update_hover(
    anchor_at(3, 7, 1),
    false,
  )
  let first_token = first.operation.token
  let (_, first_async) = first.op_trigger_async(first_token)
  let incomplete = first_async.op_trigger_sync(first_token, [
    markdown_part(3, 7, "incomplete"),
  ])
  assert_true(incomplete.view is Some(_))
  assert_false(incomplete.current_complete)

  // A sticky getting-closer update preserves the incomplete result while it
  // starts, but its empty complete result still enters `_setCurrentResult`
  // before `_withResult` reaches the insist early return: the special keep is
  // only for a previous visible *complete* result.
  let (_, insisting) = incomplete.start_showing_or_update_hover(
    anchor_at(20, 24, 5),
    true,
  )
  assert_true(insisting.insist_on_keeping)
  let insisting_token = insisting.operation.token
  let (_, insisting_async) = insisting.op_trigger_async(insisting_token)
  let async_done = insisting_async.op_async_done(insisting_token)
  let empty_complete = async_done.op_trigger_sync(insisting_token, [])
  assert_true(empty_complete.is_complete())
  assert_true(empty_complete.view is None)
  assert_true(empty_complete.current_anchor is None)
}

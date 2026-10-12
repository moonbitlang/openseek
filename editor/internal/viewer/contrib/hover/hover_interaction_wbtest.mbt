// Phase 3 of `monaco-hover-logic-chain-port.md`: the pure helpers of
// `hoverUtils.ts` and the behavior-switching predicates of
// `contentHoverController.ts`, exercised across the hover-setting matrix
// (`enabled ∈ {on, off, onKeyboardModifier}` × `sticky` × `hidingDelay` × the
// multi-cursor modifier) so each source branch has a case that takes it.

///|
fn mods(
  ctrl~ : Bool = false,
  meta~ : Bool = false,
  alt~ : Bool = false,
) -> EventModifiers {
  { ctrl, meta, alt, }
}

///|
test "empty event modifiers clear every carried input flag" {
  let empty = EventModifiers::none()
  assert_false(empty.ctrl)
  assert_false(empty.meta)
  assert_false(empty.alt)
}

///|
test "isMousePositionWithinElement insets the box by the 3px padding ring" {
  // Box at (100,50) sized 200×100; the 3px ring on every side reads as outside.
  let inside = mouse_within_element(100.0, 50.0, 200.0, 100.0, 150.0, 80.0)
  assert_true(inside)
  // Just inside the left/top padding boundary (left+3, top+3) still counts.
  assert_true(mouse_within_element(100.0, 50.0, 200.0, 100.0, 103.0, 53.0))
  // Within the left ring (x < left+3) is outside.
  assert_false(mouse_within_element(100.0, 50.0, 200.0, 100.0, 101.0, 80.0))
  // Within the right ring (x > left+width-3).
  assert_false(mouse_within_element(100.0, 50.0, 200.0, 100.0, 298.0, 80.0))
  // Within the top ring and the bottom ring.
  assert_false(mouse_within_element(100.0, 50.0, 200.0, 100.0, 150.0, 52.0))
  assert_false(mouse_within_element(100.0, 50.0, 200.0, 100.0, 150.0, 148.0))
}

///|
test "isTriggerModifierPressed inverts the multi-cursor modifier" {
  // Multi-cursor = Alt -> trigger is Ctrl OR Meta.
  assert_true(is_trigger_modifier_pressed(MultiCursorAlt, mods(ctrl=true)))
  assert_true(is_trigger_modifier_pressed(MultiCursorAlt, mods(meta=true)))
  assert_false(is_trigger_modifier_pressed(MultiCursorAlt, mods(alt=true)))
  assert_false(
    is_trigger_modifier_pressed(MultiCursorAlt, EventModifiers::none()),
  )
  // Multi-cursor = Ctrl or Meta -> trigger is Alt.
  assert_true(is_trigger_modifier_pressed(MultiCursorCtrl, mods(alt=true)))
  assert_false(is_trigger_modifier_pressed(MultiCursorCtrl, mods(ctrl=true)))
  assert_true(is_trigger_modifier_pressed(MultiCursorMeta, mods(alt=true)))
  assert_false(is_trigger_modifier_pressed(MultiCursorMeta, mods(meta=true)))
}

///|
test "shouldShowHover gates on the enabled setting and trigger modifier" {
  // 'on' always shows; 'off' never shows; both regardless of modifiers.
  assert_true(
    should_show_hover(HoverEnabledOn, MultiCursorAlt, EventModifiers::none()),
  )
  assert_false(
    should_show_hover(HoverEnabledOff, MultiCursorAlt, mods(ctrl=true)),
  )
  // 'onKeyboardModifier' defers to the trigger modifier.
  assert_true(
    should_show_hover(
      HoverEnabledOnKeyboardModifier,
      MultiCursorAlt,
      mods(meta=true),
    ),
  )
  assert_false(
    should_show_hover(
      HoverEnabledOnKeyboardModifier,
      MultiCursorAlt,
      EventModifiers::none(),
    ),
  )
}

///|
test "shouldRescheduleHoverComputation needs visible AND sticky AND delay>0" {
  assert_true(should_reschedule_hover(true, true, 300))
  // Each conjunct is necessary.
  assert_false(should_reschedule_hover(false, true, 300))
  assert_false(should_reschedule_hover(true, false, 300))
  assert_false(should_reschedule_hover(true, true, 0))
}

///|
test "shouldKeepCurrentHover keeps on keep-open or sticky pointer-on-widget" {
  // External keep-open flag wins regardless of sticky / pointer.
  assert_true(should_keep_current_hover(true, false, false))
  // Sticky AND pointer on the widget keeps it.
  assert_true(should_keep_current_hover(false, true, true))
  // Sticky off, or pointer off the widget, does not keep it.
  assert_false(should_keep_current_hover(false, false, true))
  assert_false(should_keep_current_hover(false, true, false))
}

///|
test "shouldKeepHoverWidgetVisible tracks the pointer-on-widget flag" {
  assert_true(should_keep_hover_widget_visible(true))
  assert_false(should_keep_hover_widget_visible(false))
}

///|
test "hover settings default to enabled-on, sticky, 300ms hiding delay" {
  let settings = HoverSettings::defaults()
  assert_true(settings.enabled is HoverEnabledOn)
  assert_true(
    should_show_hover(
      settings.enabled,
      hover_multi_cursor_modifier,
      EventModifiers::none(),
    ),
  )
  assert_true(settings.sticky)
  assert_eq(settings.hiding_delay, 300)
  // The dev sticky kill-switch ships disabled.
  assert_false(hover_sticky_debug)
}

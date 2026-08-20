// Phase 3 of `monaco-hover-logic-chain-port.md`: the pure helpers of Monaco's
// `hoverUtils.ts` plus the behavior-switching predicates of
// `contentHoverController.ts`. These carry no DOM or timer state — the viewer
// (`editor_events.mbt`) drives the side effects around them — so each branch is
// whitebox-testable across the hover-setting matrix.

///|
/// Monaco `hoverUtils.ts` `PADDING.VALUE`: the hover hit-test inset, in CSS px.
/// `isMousePositionWithinElement` treats the outer 3px ring of the widget box as
/// "outside" so a pointer skimming the very edge does not count as on the widget.
let hover_hit_padding : Double = 3.0

///|
/// Monaco `ContentHoverController._sticky`: a dev-only kill-switch (always
/// `false` in shipped code) that, when flipped, keeps the hover from ever hiding
/// on focus-out / mouse-leave / keydown. Kept as a named constant so the guard
/// sites read 1:1 against the source.
pub let hover_sticky_debug : Bool = false

///|
/// Monaco `editor.hover.enabled` (`IHoverSettings.enabled`).
enum HoverEnabled {
  HoverEnabledOn
  HoverEnabledOff
  HoverEnabledOnKeyboardModifier
}

///|
/// Maps the `editor.hover.enabled` config value (Monaco's
/// `'on' | 'off' | 'onKeyboardModifier'`) to the setting; unknown values fall
/// back to the option default `'on'`. The config seam is not surfaced yet (see
/// the plan's Deviations), so today only `'on'` is fed in.
fn HoverEnabled::from_config(value : String) -> HoverEnabled {
  match value {
    "off" => HoverEnabledOff
    "onKeyboardModifier" => HoverEnabledOnKeyboardModifier
    _ => HoverEnabledOn
  }
}

///|
/// Monaco `editor.multiCursorModifier` reduced to the modifier key it resolves to
/// (`'altKey' | 'ctrlKey' | 'metaKey'`).
enum MultiCursorModifier {
  MultiCursorAlt
  MultiCursorCtrl
  MultiCursorMeta
}

///|
/// Resolves the `editor.multiCursorModifier` config value to its modifier key:
/// `'ctrlCmd'` is Meta on macOS and Ctrl elsewhere; anything else (the default
/// `'alt'`) is Alt — the platform split Monaco applies before
/// `isTriggerModifierPressed` reads `'altKey' | 'ctrlKey' | 'metaKey'`.
fn MultiCursorModifier::from_config(
  value : String,
  mac~ : Bool,
) -> MultiCursorModifier {
  match value {
    "ctrlCmd" => if mac { MultiCursorMeta } else { MultiCursorCtrl }
    _ => MultiCursorAlt
  }
}

///|
/// VS Code's `editor.multiCursorModifier` default (`'alt'`). Threaded into
/// `should_show_hover` for the `'onKeyboardModifier'` branch.
pub let hover_multi_cursor_modifier : MultiCursorModifier = MultiCursorModifier::from_config(
  "alt",
  mac=false,
)

///|
/// The modifier-key flags carried by a pointer (or keyboard) event — the subset
/// `hoverUtils` reads (`event.ctrlKey` / `event.metaKey` / `event.altKey`).
struct EventModifiers {
  ctrl : Bool
  meta : Bool
  alt : Bool
} derive(Debug)

///|
/// Creates the modifier snapshot carried across the browser input boundary.
pub fn EventModifiers::EventModifiers(
  ctrl : Bool,
  meta : Bool,
  alt : Bool,
) -> EventModifiers {
  { ctrl, meta, alt }
}

///|
pub fn EventModifiers::none() -> EventModifiers {
  EventModifiers(false, false, false)
}

///|
/// Monaco `ContentHoverController` `IHoverSettings`: the snapshot of the
/// `editor.hover` options taken in `_hookListeners`.
pub struct HoverSettings {
  enabled : HoverEnabled
  sticky : Bool
  hiding_delay : Int
}

///|
/// VS Code's `editor.hover` defaults: enabled `'on'`, sticky `true`, hidingDelay
/// `300`ms. The viewer does not surface hover options yet, so the controller
/// snapshots these constants (see the plan's Deviations: config plumbing
/// deferred until hover options are modeled).
pub fn HoverSettings::defaults() -> HoverSettings {
  {
    enabled: HoverEnabled::from_config("on"),
    sticky: true,
    hiding_delay: hover_hiding_delay_ms,
  }
}

///|
/// Monaco `hoverUtils.isMousePositionWithinElement`: whether a pointer at
/// `(posx, posy)` lies inside the element box (its four edges) inset by
/// `hover_hit_padding` on all sides. The viewer measures the widget with
/// `getBoundingClientRect`, so `posx` / `posy` are client coordinates (Monaco
/// uses page coordinates against `getDomNodePagePosition`; both are consistent
/// pairs — see the Deviations note on client- vs page-space).
pub fn mouse_within_element(
  left : Double,
  top : Double,
  width : Double,
  height : Double,
  posx : Double,
  posy : Double,
) -> Bool {
  if posx < left + hover_hit_padding ||
    posx > left + width - hover_hit_padding ||
    posy < top + hover_hit_padding ||
    posy > top + height - hover_hit_padding {
    return false
  }
  true
}

///|
/// Monaco `hoverUtils.isTriggerModifierPressed`: the trigger modifier is the
/// inverse of the multi-cursor modifier — when multi-cursor is Alt, the trigger
/// is Ctrl/Meta; otherwise (multi-cursor is Ctrl/Meta) the trigger is Alt.
fn is_trigger_modifier_pressed(
  multi_cursor_modifier : MultiCursorModifier,
  e : EventModifiers,
) -> Bool {
  match multi_cursor_modifier {
    MultiCursorAlt => e.ctrl || e.meta
    MultiCursorCtrl | MultiCursorMeta => e.alt
  }
}

///|
/// Monaco `hoverUtils.shouldShowHover`: `'on'` always shows, `'off'` never, and
/// `'onKeyboardModifier'` shows only while the trigger modifier is held.
pub fn should_show_hover(
  hover_enabled : HoverEnabled,
  multi_cursor_modifier : MultiCursorModifier,
  e : EventModifiers,
) -> Bool {
  match hover_enabled {
    HoverEnabledOn => true
    HoverEnabledOff => false
    HoverEnabledOnKeyboardModifier =>
      is_trigger_modifier_pressed(multi_cursor_modifier, e)
  }
}

///|
/// Monaco `ContentHoverController._shouldRescheduleHoverComputation`: once the
/// widget is visible, a sticky hover with a positive hiding delay debounces the
/// mouse-move reaction by that delay (the grace period for the pointer to travel
/// onto the widget) instead of reacting immediately.
pub fn should_reschedule_hover(
  widget_visible : Bool,
  sticky : Bool,
  hiding_delay : Int,
) -> Bool {
  widget_visible && sticky && hiding_delay > 0
}

///|
/// Monaco `ContentHoverController._shouldKeepHoverWidgetVisible`: a mouse-down or
/// mouse-leave keeps the widget when the pointer is on it. The two other
/// disjuncts — `_isContentWidgetResizing()` (sashes, DEFERRED) and
/// `isOnColorDecorator` (color-picker, N-A) — are out of scope this phase.
pub fn should_keep_hover_widget_visible(mouse_on_widget : Bool) -> Bool {
  mouse_on_widget
}

///|
/// Monaco `ContentHoverController._shouldKeepCurrentHover`: the in-scope
/// disjuncts that keep the current hover through a mouse move — the external
/// keep-open flag (`shouldKeepOpenOnEditorMouseMoveOrLeave`) and, when sticky,
/// the pointer resting on the widget (`isMouseOnStickyContentHoverWidget`). The
/// `isFocused` / `isResizing` / sticky-from-keyboard arms need Phase 4 widget
/// state, and the color-picker / text-selection arms are N-A; all omitted here.
pub fn should_keep_current_hover(
  keep_open : Bool,
  sticky : Bool,
  mouse_on_widget : Bool,
) -> Bool {
  keep_open || (sticky && mouse_on_widget)
}

///|
pub extend EventModifiers with Debug::{to_repr}

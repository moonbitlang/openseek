// Explicit staged hover contracts. These closed enums mix cases used by the
// current Viewer with source-compatible cases reserved for injected-text and
// programmatic-hover integrations; keeping them here makes that exception
// visible to `moon ide analyze`.

///|
/// Monaco `HoverRangeAnchor` / `HoverForeignElementAnchor`
/// (`hoverTypes.ts:47-82`). `range` is model-space. The foreign variant's
/// `owner` is the explicitly minted identity of the suggesting participant;
/// `injected_text_index` is the local payload for injected text and takes no
/// part in `equals` (the source inherits the owner-only comparison).
/// `initial_mouse_pos_*` are carried per the source shape; the
/// mouse-getting-closer seam reads the live recorded pointer instead
/// (`MouseCloserState`, Phase 4 increment 2).
pub(all) enum HoverAnchor {
  HoverRangeAnchor(
    priority~ : Int,
    range~ : @base_common.Range,
    initial_mouse_pos_x~ : Double?,
    initial_mouse_pos_y~ : Double?
  )
  HoverForeignElementAnchor(
    priority~ : Int,
    owner~ : HoverParticipantOwner,
    injected_text_index~ : Int,
    range~ : @base_common.Range,
    initial_mouse_pos_x~ : Double?,
    initial_mouse_pos_y~ : Double?,
    supports_marker_hover~ : Bool
  )
} derive(Eq, Debug)

///|
/// Mints the identity required by the staged foreign-element anchor contract.
/// A factory that rebuilds handles for separate input/compute passes must
/// retain and reuse this value across them.
pub fn HoverParticipantOwner::HoverParticipantOwner() -> HoverParticipantOwner {
  next_hover_participant_owner_id.val += 1
  { id: next_hover_participant_owner_id.val }
}

///|
/// Typed start mode from Monaco's `HoverStartMode`. Numeric enum encodings are
/// intentionally not observable in the MoonBit API.
pub(all) enum HoverStartMode {
  HoverStartDelayed
  HoverStartImmediate
} derive(Eq, Debug)

///|
/// Typed origin of a hover start from Monaco's `HoverStartSource`.
pub(all) enum HoverStartSource {
  HoverStartMouse
  HoverStartClick
  HoverStartKeyboard
} derive(Eq, Debug)

///|
pub extend HoverAnchor with Debug::{to_repr}

///|
pub extend HoverAnchor with Eq::{equal, not_equal}

///|
pub extend HoverStartMode with Debug::{to_repr}

///|
pub extend HoverStartMode with Eq::{equal, not_equal}

///|
pub extend HoverStartSource with Debug::{to_repr}

///|
pub extend HoverStartSource with Eq::{equal, not_equal}

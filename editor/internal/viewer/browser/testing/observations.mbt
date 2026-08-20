///|
/// Test/workbench telemetry emitted after a viewer prepares model content for
/// rendering. `model` is the stable model handle; the remaining fields are
/// passive counts and timings rather than mutable implementation state.
pub(all) struct ViewModelBuiltObservation {
  model : @model.TextModel
  line_count : Int
  token_count : Int
  tokenize_ms : Double
  build_ms : Double
} derive(Debug)

///|
/// Test/workbench telemetry emitted after a viewer patches model content into
/// the DOM. Diagnostics remain owned by the marker service and deliberately do
/// not cross this testing boundary.
pub(all) struct ModelRenderedObservation {
  model : @model.TextModel
  line_count : Int
  rendered_lines : Int
  patch_ms : Double
  fresh : Bool
} derive(Debug)

///|
/// Test/workbench telemetry emitted when one hover resolution completes.
pub(all) struct HoverResolvedObservation {
  ok : Bool
  revision : String
} derive(Debug, Eq)

///|
/// Internal phases used to correlate an accepted scroll position with its
/// Viewer render and the page-observed `.lines-content` style commit.
pub(all) enum ScrollFramePhase {
  StateCommitted
  RenderStarted
  RenderFinished
} derive(Debug, Eq)

///|
/// Viewer-scoped scroll/render telemetry. The registry constructs this record
/// only while a listener is installed, so ordinary product execution does not
/// allocate trace observations.
priv struct ScrollFrameObservation {
  viewer_id : String
  phase : ScrollFramePhase
  scroll_top : Double
  scroll_left : Double
}

///|
#deprecated
pub extend HoverResolvedObservation with Debug::{to_repr}

///|
pub extend HoverResolvedObservation with Eq::{equal, not_equal}

///|
#deprecated
pub extend ModelRenderedObservation with Debug::{to_repr}

///|
#deprecated
pub extend ScrollFramePhase with Debug::{to_repr}

///|
pub extend ScrollFramePhase with Eq::{equal, not_equal}

///|
#deprecated
pub extend ViewModelBuiltObservation with Debug::{to_repr}

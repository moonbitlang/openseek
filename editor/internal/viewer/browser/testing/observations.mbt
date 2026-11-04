///|
/// Test/workbench telemetry emitted after a viewer prepares model content for
/// rendering. `model` is the stable model handle; the remaining fields are
/// passive counts and timings rather than mutable implementation state.
#derive(Debug)
pub(all) struct ViewModelBuiltObservation {
  model : @model.TextModel
  line_count : Int32
  token_count : Int32
  tokenize_ms : Double
  build_ms : Double
}

///|
/// Test/workbench telemetry emitted after a viewer patches model content into
/// the DOM. Diagnostics remain owned by the marker service and deliberately do
/// not cross this testing boundary.
#derive(Debug)
pub(all) struct ModelRenderedObservation {
  model : @model.TextModel
  line_count : Int32
  rendered_lines : Int32
  patch_ms : Double
  fresh : Bool
}

///|
/// Test/workbench telemetry emitted when one hover resolution completes.
#derive(Debug, Eq)
pub(all) struct HoverResolvedObservation {
  ok : Bool
  revision : String
}

///|
pub extend HoverResolvedObservation with Debug::{to_repr}

///|
pub extend HoverResolvedObservation with Eq::{equal, not_equal}

///|
pub extend ModelRenderedObservation with Debug::{to_repr}

///|
pub extend ViewModelBuiltObservation with Debug::{to_repr}

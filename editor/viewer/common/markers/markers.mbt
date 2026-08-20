// Data model ported 1:1 from
// vscode/src/vs/platform/markers/common/markers.ts

///|
/// Sentinel `endColumn` meaning "to end of line", Monaco's `Number.MAX_VALUE`
/// (`markerDecorationsService.ts:216`). A producer sets a marker's `end_column`
/// to this to request the full-line first-non-whitespace snap. Int max stands in
/// for the JS float sentinel.
let max_value_column : Int = 2147483647

///|
/// Severity of a marker, with Monaco's load-bearing bit values
/// (`markers.ts:56`). `read({severities})` is a bitmask test over these bits
/// and `Hint` drives a distinct decoration-range branch, so the values matter;
/// `value` exposes them. Kept local rather than reusing
/// `@language.DiagnosticSeverity` (which has no `Hint` and no bit values).
pub(all) enum MarkerSeverity {
  Hint
  Info
  Warning
  Error
} derive(Eq, Debug)

///|
/// The marker severity's bit value (`Hint=1, Info=2, Warning=4, Error=8`),
/// `markers.ts:56-61`.
fn MarkerSeverity::value(self : MarkerSeverity) -> Int {
  match self {
    Hint => 1
    Info => 2
    Warning => 4
    Error => 8
  }
}

///|
/// Bridge `@language.DiagnosticSeverity` → `MarkerSeverity`. Replaces Monaco's
/// `fromSeverity`, whose `base/common/severity` source enum has no viewer
/// analog (deferred).
fn MarkerSeverity::from_diagnostic_severity(
  severity : @language.DiagnosticSeverity,
) -> MarkerSeverity {
  match severity {
    Error => Error
    Warning => Warning
    Info => Info
    Hint => Hint
  }
}

///|
/// Inverse bridge for the `to_diagnostic` shim.
fn MarkerSeverity::to_diagnostic_severity(
  self : MarkerSeverity,
) -> @language.DiagnosticSeverity {
  match self {
    Error => Error
    Warning => Warning
    Info => Info
    Hint => Hint
  }
}

///|
/// Marker tag, `MarkerTag` (`markers.ts:51`). Bit values drive nothing here but
/// are kept faithful via `value`.
pub(all) enum MarkerTag {
  Unnecessary
  Deprecated
} derive(Eq, Debug)

///|
/// Inverse bridge for the `to_diagnostic` shim.
fn MarkerTag::to_diagnostic_tag(self : MarkerTag) -> @language.DiagnosticTag {
  match self {
    Unnecessary => Unnecessary
    Deprecated => Deprecated
  }
}

///|
/// Pre-sanitize marker input, `IMarkerData` (`markers.ts:109`). Monaco's
/// `code?: string | { value; target }` object form (code links) is reduced to
/// `String?` — the link target is out of scope (deviation).
struct MarkerData {
  code : String?
  severity : MarkerSeverity
  message : String
  source : String?
  start_line_number : Int
  start_column : Int
  end_line_number : Int
  end_column : Int
  model_version_id : Int?
  related_information : Array[RelatedInformation]?
  tags : Array[MarkerTag]?
  origin : String?
} derive(Eq, Debug)

///|
/// Builds marker input from the required fields, leaving the optional metadata
/// (`code`, `source`, `tags`, …) defaulted to absent.
fn new_marker_data(
  severity~ : MarkerSeverity,
  message~ : String,
  start_line_number~ : Int,
  start_column~ : Int,
  end_line_number~ : Int,
  end_column~ : Int,
  code? : String,
  source? : String,
  model_version_id? : Int,
  related_information? : Array[RelatedInformation],
  tags? : Array[MarkerTag],
  origin? : String,
) -> MarkerData {
  {
    code,
    severity,
    message,
    source,
    start_line_number,
    start_column,
    end_line_number,
    end_column,
    model_version_id,
    related_information,
    tags,
    origin,
  }
}

///|
/// `IMarkerData` sanitize, `MarkerService._toMarker` (`markerService.ts:228`):
/// drops markers with an empty message and clamps the line/column fields. The
/// owner/resource are bound here as the static does.
fn MarkerData::to_marker(
  self : MarkerData,
  owner : String,
  resource : @base_common.Uri,
) -> Marker? {
  if self.message == "" {
    return None
  }
  // santize data (markerService.ts:243-246)
  let start_line_number = if self.start_line_number > 0 {
    self.start_line_number
  } else {
    1
  }
  let start_column = if self.start_column > 0 { self.start_column } else { 1 }
  let end_line_number = if self.end_line_number >= start_line_number {
    self.end_line_number
  } else {
    start_line_number
  }
  let end_column = if self.end_column > 0 {
    self.end_column
  } else {
    start_column
  }
  Some({
    owner,
    resource,
    code: self.code,
    severity: self.severity,
    message: self.message,
    source: self.source,
    start_line_number,
    start_column,
    end_line_number,
    end_column,
    model_version_id: self.model_version_id,
    related_information: self.related_information,
    tags: self.tags,
    origin: self.origin,
  })
}

///|
/// A sanitized marker, `IMarker` (`markers.ts:129`). `range` is derived from the
/// separate line/column fields (Monaco stores them flat). `start_column` is
/// mutable because `_createDecorationRange` snaps it for full-line markers
/// (`markerDecorationsService.ts:220`).
pub struct Marker {
  owner : String
  resource : @base_common.Uri
  severity : MarkerSeverity
  code : String?
  message : String
  source : String?
  mut start_column : Int
  start_line_number : Int
  end_line_number : Int
  end_column : Int
  model_version_id : Int?
  related_information : Array[RelatedInformation]?
  tags : Array[MarkerTag]?
  origin : String?
} derive(Eq, Debug)

///|
/// The marker's line/column span as a `Range` (Monaco's `Range.lift(marker)`).
fn Marker::range(self : Marker) -> @base_common.Range {
  Range(
    self.start_line_number,
    self.start_column,
    self.end_line_number,
    self.end_column,
  )
}

///|
/// Whether the marker carries `tag`, `MarkerDecorations._hasMarkerTag`
/// (`markerDecorationsService.ts:299`).
fn Marker::has_tag(self : Marker, tag : MarkerTag) -> Bool {
  match self.tags {
    Some(tags) => tags.contains(tag)
    None => false
  }
}

///|
/// Read filter, `IMarkerReadOptions` (`markers.ts:13`).
priv struct MarkerReadOptions {
  owner : String?
  resource : @base_common.Uri?
  severities : Int?
  take : Int?
  ignore_resource_filters : Bool
}

///|
/// Builds a read filter; every field is optional, `ignore_resource_filters`
/// defaults to false.
fn MarkerReadOptions::MarkerReadOptions(
  owner? : String,
  resource? : @base_common.Uri,
  severities? : Int,
  take? : Int,
  ignore_resource_filters? : Bool = false,
) -> MarkerReadOptions {
  { owner, resource, severities, take, ignore_resource_filters }
}

///|
/// Converts marker data back to the shared diagnostic shape.
fn Marker::to_diagnostic(self : Marker) -> @language.Diagnostic {
  {
    range: self.range(),
    severity: self.severity.to_diagnostic_severity(),
    message: self.message,
    tags: self.tags.map(tags => tags.map(MarkerTag::to_diagnostic_tag)),
  }
}

///|
#deprecated
pub extend Marker with Debug::{to_repr}

///|
pub extend Marker with Eq::{equal, not_equal}

///|
#deprecated
pub extend MarkerData with Debug::{to_repr}

///|
pub extend MarkerData with Eq::{equal, not_equal}

///|
#deprecated
pub extend MarkerSeverity with Debug::{to_repr}

///|
pub extend MarkerSeverity with Eq::{equal, not_equal}

///|
#deprecated
pub extend MarkerTag with Debug::{to_repr}

///|
pub extend MarkerTag with Eq::{equal, not_equal}

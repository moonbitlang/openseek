///|
/// Closed, serializable work kinds. Arbitrary registered closures never cross
/// the worker boundary. A worker receives one request and is then terminated.
pub(all) enum CodeWorkerRequest {
  Diff(original~ : String, modified~ : String, ignore_trim_whitespace~ : Bool)
  Folding(
    text~ : String,
    language_id~ : String,
    off_side~ : Bool,
    tab_size~ : Int,
    limit~ : Int,
    outline~ : Bool
  )
} derive(FromJson, ToJson)

///|
pub(all) struct WorkerDiffChange {
  original_start : Int
  original_end : Int
  modified_start : Int
  modified_end : Int
  ignored : Bool
  inner_changes : Array[(Int, Int, Int, Int, Int, Int, Int, Int)]?
} derive(FromJson, ToJson)

///|
pub(all) struct PreparedFoldRange {
  start : Int
  end : Int
  kind : String?
} derive(FromJson, ToJson)

///|
pub(all) enum CodeWorkerResponse {
  Diff(Array[WorkerDiffChange])
  // None means the immutable outline structure is identical to provider.
  Folding(Array[PreparedFoldRange], Array[PreparedFoldRange]?)
  Failed
} derive(FromJson, ToJson)

///|
pub fn encode_diff(document : @diff.DocumentDiff) -> CodeWorkerResponse {
  Diff(
    document.changes.map(change => {
      let mapping = change.mapping
      {
        original_start: mapping.original.start_line_number,
        original_end: mapping.original.end_line_number_exclusive,
        modified_start: mapping.modified.start_line_number,
        modified_end: mapping.modified.end_line_number_exclusive,
        ignored: change.kind == Ignored,
        inner_changes: mapping.inner_changes.map(inner => {
          inner.map(item => {
            let a = item.original
            let b = item.modified
            (
              a.start_line_number,
              a.start_column,
              a.end_line_number,
              a.end_column,
              b.start_line_number,
              b.start_column,
              b.end_line_number,
              b.end_column,
            )
          })
        }),
      }
    }),
  )
}

///|
pub fn decode_diff(changes : Array[WorkerDiffChange]) -> @diff.DocumentDiff {
  {
    changes: changes.map(change => {
      DocumentDiffChange(
        DetailedLineRangeMapping(
          LineRange(change.original_start, change.original_end),
          LineRange(change.modified_start, change.modified_end),
          change.inner_changes.map(inner => {
            inner.map(item => {
              let (a, b, c, d, e, f, g, h) = item
              RangeMapping(Range(a, b, c, d), Range(e, f, g, h))
            })
          }),
        ),
        kind=if change.ignored { Ignored } else { Visible },
      )
    }),
  }
}

///|
pub fn encode_folds(
  regions : @folding_browser.FoldingRegions,
) -> Array[PreparedFoldRange] {
  Array::makei(regions.length(), index => {
    let range = regions.to_fold_range(index)
    {
      start: range.start_line_number(),
      end: range.end_line_number(),
      kind: regions.get_type(index),
    }
  })
}

///|
pub fn decode_folds(
  ranges : Array[PreparedFoldRange],
) -> @folding_browser.FoldingRegions {
  @folding_browser.FoldingRegions::from_fold_ranges(
    ranges.map(range => FoldRange(range.start, range.end, type_?=range.kind)),
  )
}

///|
pub extend CodeWorkerRequest with ToJson::{to_json}

///|
pub extend CodeWorkerRequest with @json.FromJson::{from_json}

///|
pub extend CodeWorkerResponse with ToJson::{to_json}

///|
pub extend CodeWorkerResponse with @json.FromJson::{from_json}

///|
pub extend WorkerDiffChange with ToJson::{to_json}

///|
pub extend WorkerDiffChange with @json.FromJson::{from_json}

///|
pub extend PreparedFoldRange with ToJson::{to_json}

///|
pub extend PreparedFoldRange with @json.FromJson::{from_json}

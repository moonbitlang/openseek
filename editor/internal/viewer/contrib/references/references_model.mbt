// Algorithm-fidelity port of:
// - vscode/src/vs/editor/contrib/gotoSymbol/browser/referencesModel.ts:147-297
// - vscode/src/vs/editor/contrib/gotoSymbol/browser/referencesModel.ts:66-145
// Pinned vscode revision: b18492a288de038fbc7643aae6de8247029d11bd.
//
// URI identity deliberately uses the canonical `Uri::to_string()` everywhere.
// Unlike upstream `extUri.isEqual(..., true)` grouping, fragments are not
// ignored. Snippets retain source substrings instead of exposing highlight
// offsets, and embedded line breaks become display spaces.

///|
/// One immutable reference in deterministic display order.
pub(all) struct ReferenceItem {
  flat_index : Int
  group_index : Int
  index_in_group : Int
  uri : @base_common.Uri
  uri_string : String
  range : @base_common.Range
} derive(Eq, Debug)

///|
/// Reconstructs the host-neutral location used by open callbacks.
pub fn ReferenceItem::location(self : ReferenceItem) -> @language.Location {
  { uri: self.uri, range: self.range }
}

///|
/// Stable one-based fallback used when no valid model snippet is available.
pub fn ReferenceItem::fallback_label(self : ReferenceItem) -> String {
  "\{@base_common.basename_or_authority(self.uri)}:\{self.range.start_line_number}:\{self.range.start_column}"
}

///|
/// One canonical-URI group in deterministic resource order.
pub(all) struct ReferenceGroup {
  group_index : Int
  uri : @base_common.Uri
  uri_string : String
  references : Array[ReferenceItem]
} derive(Eq, Debug)

///|
/// Normalized reference results. `references` is the flat navigation order;
/// `groups` partitions that exact sequence without changing item identity.
pub(all) struct ReferencesModel {
  groups : Array[ReferenceGroup]
  references : Array[ReferenceItem]
} derive(Eq, Debug)

///|
priv struct IndexedReferenceLocation {
  location : @language.Location
  uri_string : String
  original_index : Int
}

///|
fn compare_indexed_reference_locations(
  left : IndexedReferenceLocation,
  right : IndexedReferenceLocation,
) -> Int {
  let uri_order = @base_common.compare(left.uri_string, right.uri_string)
  if uri_order != 0 {
    return uri_order
  }
  let range_order = @base_common.Range::compare_ranges_using_starts(
    left.location.range,
    right.location.range,
  )
  if range_order != 0 {
    return range_order
  }
  // MoonBit's `sort_by` is unstable. Retaining the caller index as the final
  // key preserves upstream's stable first-occurrence rule for exact ties.
  left.original_index - right.original_index
}

///|
fn sorted_indexed_reference_locations(
  locations : Array[@language.Location],
) -> Array[IndexedReferenceLocation] {
  let indexed : Array[IndexedReferenceLocation] = []
  for original_index, location in locations {
    indexed.push({
      location,
      uri_string: location.uri.to_string(),
      original_index,
    })
  }
  indexed.sort_by(compare_indexed_reference_locations)
  indexed
}

///|
/// Copies, canonical-URI/range sorts, and removes exact URI-string plus range
/// duplicates. Equal entries retain their first caller occurrence.
fn normalize_reference_locations(
  locations : Array[@language.Location],
) -> Array[@language.Location] {
  let result : Array[@language.Location] = []
  let mut previous_uri : String? = None
  let mut previous_range : @base_common.Range? = None
  for entry in sorted_indexed_reference_locations(locations) {
    let duplicate = previous_uri == Some(entry.uri_string) &&
      previous_range == Some(entry.location.range)
    if !duplicate {
      result.push(entry.location)
      previous_uri = Some(entry.uri_string)
      previous_range = Some(entry.location.range)
    }
  }
  result
}

///|
/// Constructs the immutable grouped and flat result model from a caller-owned
/// location array. The input array is never sorted or retained.
pub fn ReferencesModel::ReferencesModel(
  locations : Array[@language.Location],
) -> ReferencesModel {
  let groups : Array[ReferenceGroup] = []
  let references : Array[ReferenceItem] = []
  let normalized = normalize_reference_locations(locations)
  for location in normalized {
    let uri_string = location.uri.to_string()
    let needs_group = match groups.last() {
      None => true
      Some(group) => group.uri_string != uri_string
    }
    if needs_group {
      groups.push({
        group_index: groups.length(),
        uri: location.uri,
        uri_string,
        references: [],
      })
    }
    let group_index = groups.length() - 1
    let group = groups[group_index]
    let item = {
      flat_index: references.length(),
      group_index,
      index_in_group: group.references.length(),
      uri: location.uri,
      uri_string,
      range: location.range,
    }
    group.references.push(item)
    references.push(item)
  }
  { groups, references }
}

///|
pub fn ReferencesModel::is_empty(self : ReferencesModel) -> Bool {
  self.references.is_empty()
}

///|
fn common_uri_prefix_length(left : String, right : String) -> Int {
  let left_chars = left.to_array()
  let right_chars = right.to_array()
  let limit = left_chars.length().min(right_chars.length())
  let mut length = 0
  while length < limit && left_chars[length] == right_chars[length] {
    length += 1
  }
  length
}

///|
/// Selects the reference nearest to the source resource and anchor. Longer
/// URI-string prefix wins, then the pinned line/column distance, then the
/// existing stable sorted order.
pub fn ReferencesModel::nearest_reference(
  self : ReferencesModel,
  source_resource : @base_common.Uri,
  anchor : @base_common.Position,
) -> ReferenceItem? {
  let source = source_resource.to_string()
  let mut best : ReferenceItem? = None
  let mut best_prefix = -1
  let mut best_distance = 0
  for reference in self.references {
    let prefix = common_uri_prefix_length(reference.uri_string, source)
    let distance = (reference.range.start_line_number - anchor.line_number).abs() *
      100 +
      (reference.range.start_column - anchor.column).abs()
    if best is None ||
      prefix > best_prefix ||
      (prefix == best_prefix && distance < best_distance) {
      best = Some(reference)
      best_prefix = prefix
      best_distance = distance
    }
  }
  best
}

///|
/// Returns the adjacent flat reference and wraps at either end. A reference
/// not belonging to this model produces `None`.
fn ReferencesModel::next_or_previous_reference(
  self : ReferencesModel,
  reference : ReferenceItem,
  next : Bool,
) -> ReferenceItem? {
  let count = self.references.length()
  if count == 0 ||
    reference.flat_index < 0 ||
    reference.flat_index >= count ||
    self.references[reference.flat_index] != reference {
    return None
  }
  let target_index = if next {
    (reference.flat_index + 1) % count
  } else {
    (reference.flat_index + count - 1) % count
  }
  Some(self.references[target_index])
}

///|
pub fn ReferencesModel::next_reference(
  self : ReferencesModel,
  reference : ReferenceItem,
) -> ReferenceItem? {
  self.next_or_previous_reference(reference, true)
}

///|
pub fn ReferencesModel::previous_reference(
  self : ReferencesModel,
  reference : ReferenceItem,
) -> ReferenceItem? {
  self.next_or_previous_reference(reference, false)
}

///|
/// One single-row source preview with the exact match kept as a distinct part.
pub(all) struct ReferenceSnippet {
  before : String
  matched : String
  after : String
} derive(Eq, Debug)

///|
pub fn ReferenceSnippet::display_text(self : ReferenceSnippet) -> String {
  self.before + self.matched + self.after
}

///|
/// A row is always renderable: failed or unavailable snippets retain their
/// stable location fallback and remain selectable.
pub(all) enum ReferenceRowPreview {
  Snippet(ReferenceSnippet)
  LocationFallback(String)
} derive(Eq, Debug)

///|
fn normalize_snippet_line_breaks(value : String) -> String {
  value
  .replace_all(old="\r\n", new=" ")
  .replace_all(old="\n", new=" ")
  .replace_all(old="\r", new=" ")
}

///|
fn valid_snippet_range(
  model : @model.TextModel,
  range : @base_common.Range,
) -> Bool {
  if model.is_disposed() || model.validate_range(range) != range {
    return false
  }
  let start = range.get_start_position()
  let end = @base_common.Position(range.end_line_number, range.end_column)
  start.is_before_or_equal(end)
}

///|
/// Builds the pinned eight-column/word-context snippet. Invalid, stale, empty,
/// or surrogate-splitting ranges return `None` rather than being clamped.
fn reference_snippet(
  model : @model.TextModel,
  range : @base_common.Range,
) -> ReferenceSnippet? {
  if !valid_snippet_range(model, range) {
    return None
  }
  let context_position = @base_common.Position(
    range.start_line_number,
    (range.start_column - 8).max(1),
  )
  let context_start_column = match
    model.get_word_at_position(context_position) {
    Some(word) => word.start_column
    None => context_position.column
  }
  let before = normalize_snippet_line_breaks(
      model.get_value_in_range(
        Range(
          range.start_line_number,
          context_start_column,
          range.start_line_number,
          range.start_column,
        ),
      ),
    )
    .trim_start()
    .to_owned()
  let matched = normalize_snippet_line_breaks(model.get_value_in_range(range))
  let after = normalize_snippet_line_breaks(
      model.get_value_in_range(
        Range(
          range.end_line_number,
          range.end_column,
          range.end_line_number,
          model.get_line_max_column(range.end_line_number),
        ),
      ),
    )
    .trim_end()
    .to_owned()
  if before.is_empty() && matched.is_empty() && after.is_empty() {
    None
  } else {
    Some({ before, matched, after })
  }
}

///|
/// Resolves this row against an optional exact-resource model. Missing,
/// disposed, wrong-resource, and invalid-range models all preserve fallback.
pub fn ReferenceItem::row_preview(
  self : ReferenceItem,
  model : @model.TextModel?,
) -> ReferenceRowPreview {
  match model {
    Some(model) if model.uri.to_string() == self.uri_string =>
      match reference_snippet(model, self.range) {
        Some(snippet) => Snippet(snippet)
        None => LocationFallback(self.fallback_label())
      }
    _ => LocationFallback(self.fallback_label())
  }
}

///|
pub extend ReferenceGroup with Debug::{to_repr}

///|
pub extend ReferenceGroup with Eq::{equal, not_equal}

///|
pub extend ReferenceItem with Debug::{to_repr}

///|
pub extend ReferenceItem with Eq::{equal, not_equal}

///|
pub extend ReferenceRowPreview with Debug::{to_repr}

///|
pub extend ReferenceRowPreview with Eq::{equal, not_equal}

///|
pub extend ReferenceSnippet with Debug::{to_repr}

///|
pub extend ReferenceSnippet with Eq::{equal, not_equal}

///|
pub extend ReferencesModel with Debug::{to_repr}

///|
pub extend ReferencesModel with Eq::{equal, not_equal}

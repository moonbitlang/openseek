// The renderer-facing state mirrors VS Code's DiffState/DiffMapping boundary.
// A real change has exactly one canonical DetailedLineRangeMapping. The only
// local extension is `additional_alignments`; those mappings are injected into
// alignment computation and are deliberately absent from every visual feature.

///|
pub struct DiffMapping {
  line_range_mapping : @diff.DetailedLineRangeMapping
}

///|
pub struct DiffState {
  mappings : Array[DiffMapping]
  additional_alignments : Array[@diff.LineRangeMapping]
}

///|
fn DiffState::from_diff_result(result : @diff.DocumentDiff) -> DiffState {
  {
    mappings: result.changes.map(change => { line_range_mapping: change, }),
    additional_alignments: result.additional_alignments.copy(),
  }
}

///|
priv struct IndexedDiffAlignment {
  source_index : Int
  line_range_mapping : @diff.LineRangeMapping
  diff : @diff.DetailedLineRangeMapping?
}

///|
fn compare_line_range(
  left : @base_common.LineRange,
  right : @base_common.LineRange,
) -> Int {
  if left.start_line_number != right.start_line_number {
    left.start_line_number - right.start_line_number
  } else {
    left.end_line_number_exclusive - right.end_line_number_exclusive
  }
}

///|
fn compare_indexed_diff_alignment(
  left : IndexedDiffAlignment,
  right : IndexedDiffAlignment,
) -> Int {
  let original = compare_line_range(
    left.line_range_mapping.original,
    right.line_range_mapping.original,
  )
  if original != 0 {
    return original
  }
  let modified = compare_line_range(
    left.line_range_mapping.modified,
    right.line_range_mapping.modified,
  )
  if modified != 0 {
    return modified
  }
  left.source_index - right.source_index
}

///|
priv struct DiffAlignment {
  line_range_mapping : @diff.LineRangeMapping
  /// `None` is the sole extension point: a geometry-only alignment must never
  /// be mistaken for a visible diff mapping.
  diff : @diff.DetailedLineRangeMapping?
}

///|
fn DiffState::alignments(self : DiffState) -> Array[DiffAlignment] {
  let indexed : Array[IndexedDiffAlignment] = []
  for mapping in self.mappings {
    indexed.push({
      source_index: indexed.length(),
      line_range_mapping: mapping.line_range_mapping.line_mapping(),
      diff: Some(mapping.line_range_mapping),
    })
  }
  for alignment in self.additional_alignments {
    indexed.push({
      source_index: indexed.length(),
      line_range_mapping: alignment,
      diff: None,
    })
  }
  indexed.sort_by(compare_indexed_diff_alignment)
  indexed.map(item => {
    line_range_mapping: item.line_range_mapping,
    diff: item.diff,
  })
}

///|
priv struct DiffNavigationTarget {
  change_index : Int
  change_count : Int
  change : @diff.DetailedLineRangeMapping
}

///|
/// One product-visible hunk. `members` retains only the provider's real changed
/// mappings; `reveal_mapping` is the joined range used by F7/Shift+F7.
pub(all) struct DiffHunk {
  members : Array[@diff.DetailedLineRangeMapping]
  priv reveal_mapping : @diff.DetailedLineRangeMapping
}

///|
// Pinned behavior oracle: vscode@07c20d96cf3f2cbc8142ac7079ba9048cf7f6134,
// `accessibleDiffViewer.ts::computeViewElementGroups`. Its three context lines
// on each side merge adjacent mappings while the gap is strictly less than
// six lines. `commands.ts` binds F7/Shift+F7 to these groups.
const DiffNavigationGroupLineMargin = 3

///|
fn DiffState::hunks(self : DiffState) -> Array[DiffHunk] {
  let result : Array[DiffHunk] = []
  for mapping in self.mappings {
    let change = mapping.line_range_mapping
    if result.is_empty() {
      result.push({ members: [change], reveal_mapping: change, })
      continue
    }
    let last_index = result.length() - 1
    let previous = result[last_index]
    if change.modified.start_line_number -
      previous.reveal_mapping.modified.end_line_number_exclusive <
      2 * DiffNavigationGroupLineMargin {
      let members = previous.members.copy()
      members.push(change)
      result[last_index] = {
        members,
        reveal_mapping: DetailedLineRangeMapping(
          previous.reveal_mapping.original.join(change.original),
          previous.reveal_mapping.modified.join(change.modified),
          None,
        ),
      }
    } else {
      result.push({ members: [change], reveal_mapping: change, })
    }
  }
  result
}

///|
fn DiffState::navigation_changes(
  self : DiffState,
) -> Array[@diff.DetailedLineRangeMapping] {
  self.hunks().map(hunk => hunk.reveal_mapping)
}

///|
// Keep navigation relative to the modified editor cursor rather than an
// independent last-navigation index. Only the projected group list affects
// navigation; renderer mappings remain canonical and ungrouped.
fn DiffState::next_change_from_modified_line(
  self : DiffState,
  current_line_number : Int,
  modified_line_count : Int,
) -> DiffNavigationTarget? {
  let changes = self.navigation_changes()
  let count = changes.length()
  if count == 0 {
    return None
  }
  let mut index = 0
  if current_line_number != modified_line_count {
    while index < count &&
          changes[index].modified.start_line_number <= current_line_number {
      index += 1
    }
  }
  if index == count {
    index = 0
  }
  Some({ change_index: index, change_count: count, change: changes[index], })
}

///|
/// Resolve the next navigation group without wrapping to the first group.
/// Multi-diff hosts use this to decide whether F7 stays in the active item or
/// advances to the next comparison.
fn DiffState::next_change_from_modified_line_without_wrap(
  self : DiffState,
  current_line_number : Int,
) -> DiffNavigationTarget? {
  let changes = self.navigation_changes()
  let count = changes.length()
  let mut index = 0
  while index < count &&
        changes[index].modified.start_line_number <= current_line_number {
    index += 1
  }
  guard index < count else { return None }
  Some({ change_index: index, change_count: count, change: changes[index], })
}

///|
fn DiffState::previous_change_from_modified_line(
  self : DiffState,
  current_line_number : Int,
) -> DiffNavigationTarget? {
  let changes = self.navigation_changes()
  let count = changes.length()
  if count == 0 {
    return None
  }
  let mut index = count - 1
  while index >= 0 &&
        changes[index].modified.start_line_number >= current_line_number {
    index -= 1
  }
  if index < 0 {
    index = count - 1
  }
  Some({ change_index: index, change_count: count, change: changes[index], })
}

///|
/// Resolve the previous navigation group without wrapping to the final group.
fn DiffState::previous_change_from_modified_line_without_wrap(
  self : DiffState,
  current_line_number : Int,
) -> DiffNavigationTarget? {
  let changes = self.navigation_changes()
  let count = changes.length()
  let mut index = count - 1
  while index >= 0 &&
        changes[index].modified.start_line_number >= current_line_number {
    index -= 1
  }
  guard index >= 0 else { return None }
  Some({ change_index: index, change_count: count, change: changes[index], })
}

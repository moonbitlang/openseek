// All source changes share one ordered stream. Visible changes drive diff
// features; ignored changes retain geometry without decorations or navigation.

///|
pub struct DiffMapping {
  kind : @diff.DocumentDiffChangeKind
  line_range_mapping : @diff.DetailedLineRangeMapping
}

///|
pub struct DiffState {
  mappings : Array[DiffMapping]
}

///|
fn DiffState::from_diff_result(result : @diff.DocumentDiff) -> DiffState {
  {
    mappings: result.changes.map(change => {
      kind: change.kind,
      line_range_mapping: change.mapping,
    }),
  }
}

///|
fn DiffState::visible_mappings(self : DiffState) -> Array[DiffMapping] {
  self.mappings.filter(mapping => mapping.kind is Visible)
}

///|
priv struct DiffAlignment {
  line_range_mapping : @diff.LineRangeMapping
  /// Ignored changes participate in geometry without visible diff features.
  diff : @diff.DetailedLineRangeMapping?
}

///|
fn DiffState::alignments(self : DiffState) -> Array[DiffAlignment] {
  self.mappings.map(mapping => {
    line_range_mapping: mapping.line_range_mapping.line_mapping(),
    diff: match mapping.kind {
      Visible => Some(mapping.line_range_mapping)
      Ignored => None
    },
  })
}

///|
priv struct DiffNavigationTarget {
  change_index : Int32
  change_count : Int32
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
  for mapping in self.visible_mappings() {
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
  current_line_number : Int32,
  modified_line_count : Int32,
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
  current_line_number : Int32,
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
  current_line_number : Int32,
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
  current_line_number : Int32,
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

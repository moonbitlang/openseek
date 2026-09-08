// Readability-focused parts of VS Code's Advanced diff pipeline.
//
// Algorithm-fidelity reference (pinned editor/vscode revision
// 07c20d96cf3f2cbc8142ac7079ba9048cf7f6134):
// - defaultLinesDiffComputer/algorithms/dynamicProgrammingDiffing.ts
// - defaultLinesDiffComputer/heuristicSequenceOptimizations.ts
// - defaultLinesDiffComputer/lineSequence.ts
// - defaultLinesDiffComputer/linesSliceCharSequence.ts
//
// The local representation deliberately stays renderer-neutral and does not
// import the reference tree. Offsets index either lines or Unicode scalars;
// UTF-16 conversion remains owned by InnerDiffSequence.

///|
priv struct DiffOffsetRange {
  start : Int
  end_exclusive : Int
}

///|
fn DiffOffsetRange::length(self : DiffOffsetRange) -> Int {
  self.end_exclusive - self.start
}

///|
fn DiffOffsetRange::is_empty(self : DiffOffsetRange) -> Bool {
  self.start == self.end_exclusive
}

///|
fn DiffOffsetRange::delta(
  self : DiffOffsetRange,
  offset : Int,
) -> DiffOffsetRange {
  { start: self.start + offset, end_exclusive: self.end_exclusive + offset, }
}

///|
fn DiffOffsetRange::join(
  self : DiffOffsetRange,
  other : DiffOffsetRange,
) -> DiffOffsetRange {
  {
    start: self.start.min(other.start),
    end_exclusive: self.end_exclusive.max(other.end_exclusive),
  }
}

///|
fn DiffOffsetRange::intersect(
  self : DiffOffsetRange,
  other : DiffOffsetRange,
) -> DiffOffsetRange? {
  let start = self.start.max(other.start)
  let end_exclusive = self.end_exclusive.min(other.end_exclusive)
  if start <= end_exclusive {
    Some({ start, end_exclusive, })
  } else {
    None
  }
}

///|
fn DiffOffsetRange::intersects(
  self : DiffOffsetRange,
  other : DiffOffsetRange,
) -> Bool {
  self.start.max(other.start) < self.end_exclusive.min(other.end_exclusive)
}

///|
priv struct SequenceDiff {
  original : DiffOffsetRange
  modified : DiffOffsetRange
}

///|
fn SequenceDiff::delta(self : SequenceDiff, offset : Int) -> SequenceDiff {
  {
    original: self.original.delta(offset),
    modified: self.modified.delta(offset),
  }
}

///|
fn SequenceDiff::swap(self : SequenceDiff) -> SequenceDiff {
  { original: self.modified, modified: self.original, }
}

///|
fn SequenceDiff::join(
  self : SequenceDiff,
  other : SequenceDiff,
) -> SequenceDiff {
  {
    original: self.original.join(other.original),
    modified: self.modified.join(other.modified),
  }
}

///|
fn SequenceDiff::intersect(
  self : SequenceDiff,
  other : SequenceDiff,
) -> SequenceDiff? {
  guard self.original.intersect(other.original) is Some(original) else {
    return None
  }
  guard self.modified.intersect(other.modified) is Some(modified) else {
    return None
  }
  Some({ original, modified, })
}

///|
priv struct ReadabilitySequence {
  values : Array[Int]
  strongly_equal : (Int, Int) -> Bool
  boundary_score : (Int) -> Int
}

///|
// Port of DynamicProgrammingDiffing.compute. In particular, the direction
// order, diagonal tie preference, and consecutive-diagonal bonus match the
// pinned source.
fn weighted_sequence_diffs(
  sequence1 : Array[Int],
  sequence2 : Array[Int],
  equality_score : (Int, Int) -> Double,
) -> Array[SequenceDiff] {
  if sequence1.is_empty() && sequence2.is_empty() {
    return []
  }
  if sequence1.is_empty() || sequence2.is_empty() {
    return [
      {
        original: { start: 0, end_exclusive: sequence1.length(), },
        modified: { start: 0, end_exclusive: sequence2.length(), },
      },
    ]
  }
  let width = sequence1.length()
  let height = sequence2.length()
  let scores = Array::make(width * height, 0.0)
  let directions = Array::make(width * height, 0)
  let lengths = Array::make(width * height, 0)
  let index_of = fn(s1 : Int, s2 : Int) { s1 + s2 * width }
  for s1 in 0..<width {
    for s2 in 0..<height {
      let horizontal = if s1 == 0 { 0.0 } else { scores[index_of(s1 - 1, s2)] }
      let vertical = if s2 == 0 { 0.0 } else { scores[index_of(s1, s2 - 1)] }
      let extended = if sequence1[s1] == sequence2[s2] {
        let mut score = if s1 == 0 || s2 == 0 {
          0.0
        } else {
          scores[index_of(s1 - 1, s2 - 1)]
        }
        if s1 > 0 && s2 > 0 && directions[index_of(s1 - 1, s2 - 1)] == 3 {
          score += lengths[index_of(s1 - 1, s2 - 1)].to_double()
        }
        score + equality_score(s1, s2)
      } else {
        -1.0
      }
      let new_value = horizontal.max(vertical).max(extended)
      let index = index_of(s1, s2)
      if new_value == extended {
        let previous_length = if s1 > 0 && s2 > 0 {
          lengths[index_of(s1 - 1, s2 - 1)]
        } else {
          0
        }
        lengths[index] = previous_length + 1
        directions[index] = 3
      } else if new_value == horizontal {
        lengths[index] = 0
        directions[index] = 1
      } else {
        lengths[index] = 0
        directions[index] = 2
      }
      scores[index] = new_value
    }
  }

  let reversed : Array[SequenceDiff] = []
  let mut last_s1 = width
  let mut last_s2 = height
  let report_alignment = fn(s1 : Int, s2 : Int) {
    if s1 + 1 != last_s1 || s2 + 1 != last_s2 {
      reversed.push({
        original: { start: s1 + 1, end_exclusive: last_s1, },
        modified: { start: s2 + 1, end_exclusive: last_s2, },
      })
    }
    last_s1 = s1
    last_s2 = s2
  }
  let mut s1 = width - 1
  let mut s2 = height - 1
  while s1 >= 0 && s2 >= 0 {
    match directions[index_of(s1, s2)] {
      3 => {
        report_alignment(s1, s2)
        s1 -= 1
        s2 -= 1
      }
      1 => s1 -= 1
      _ => s2 -= 1
    }
  }
  report_alignment(-1, -1)
  reversed.rev()
}

///|
fn myers_sequence_diffs(
  sequence1 : Array[Int],
  sequence2 : Array[Int],
) -> Array[SequenceDiff] {
  let edits = @core_diff.Diff(
    old=sequence1[:],
    new=sequence2[:],
    algorithm=Myers,
  ).edits()
  let changes : Array[SequenceDiff] = []
  let mut index = 0
  while index < edits.length() {
    match edits[index] {
      Equal(..) => index += 1
      _ => {
        let mut original_start = 0x7FFFFFFF
        let mut original_end = -1
        let mut modified_start = 0x7FFFFFFF
        let mut modified_end = -1
        let mut original_anchor = 0
        let mut modified_anchor = 0
        while index < edits.length() {
          match edits[index] {
            Equal(..) => break
            Delete(old_index~, old_len~, new_index~) => {
              original_start = original_start.min(old_index)
              original_end = original_end.max(old_index + old_len)
              modified_anchor = new_index
            }
            Insert(old_index~, new_index~, new_len~) => {
              modified_start = modified_start.min(new_index)
              modified_end = modified_end.max(new_index + new_len)
              original_anchor = old_index
            }
          }
          index += 1
        }
        changes.push({
          original: if original_end >= 0 {
            { start: original_start, end_exclusive: original_end, }
          } else {
            { start: original_anchor, end_exclusive: original_anchor, }
          },
          modified: if modified_end >= 0 {
            { start: modified_start, end_exclusive: modified_end, }
          } else {
            { start: modified_anchor, end_exclusive: modified_anchor, }
          },
        })
      }
    }
  }
  changes
}

///|
fn join_sequence_diffs_by_shifting(
  sequence1 : ReadabilitySequence,
  sequence2 : ReadabilitySequence,
  sequence_diffs : Array[SequenceDiff],
) -> Array[SequenceDiff] {
  if sequence_diffs.is_empty() {
    return sequence_diffs
  }
  let result : Array[SequenceDiff] = [sequence_diffs[0]]
  for index in 1..<sequence_diffs.length() {
    let previous = result[result.length() - 1]
    let mut current = sequence_diffs[index]
    if current.original.is_empty() || current.modified.is_empty() {
      let length = current.original.start - previous.original.end_exclusive
      let mut distance = 1
      while distance <= length {
        if sequence1.values[current.original.start - distance] !=
          sequence1.values[current.original.end_exclusive - distance] ||
          sequence2.values[current.modified.start - distance] !=
          sequence2.values[current.modified.end_exclusive - distance] {
          break
        }
        distance += 1
      }
      distance -= 1
      if distance == length {
        result[result.length() - 1] = {
          original: {
            start: previous.original.start,
            end_exclusive: current.original.end_exclusive - length,
          },
          modified: {
            start: previous.modified.start,
            end_exclusive: current.modified.end_exclusive - length,
          },
        }
        continue
      }
      current = current.delta(-distance)
    }
    result.push(current)
  }

  let shifted : Array[SequenceDiff] = []
  for index in 0..<(result.length() - 1) {
    let next = result[index + 1]
    let mut current = result[index]
    if current.original.is_empty() || current.modified.is_empty() {
      let length = next.original.start - current.original.end_exclusive
      let mut distance = 0
      while distance < length {
        if !(sequence1.strongly_equal)(
            current.original.start + distance,
            current.original.end_exclusive + distance,
          ) ||
          !(sequence2.strongly_equal)(
            current.modified.start + distance,
            current.modified.end_exclusive + distance,
          ) {
          break
        }
        distance += 1
      }
      if distance == length {
        result[index + 1] = {
          original: {
            start: current.original.start + length,
            end_exclusive: next.original.end_exclusive,
          },
          modified: {
            start: current.modified.start + length,
            end_exclusive: next.modified.end_exclusive,
          },
        }
        continue
      }
      if distance > 0 {
        current = current.delta(distance)
      }
    }
    shifted.push(current)
  }
  shifted.push(result[result.length() - 1])
  shifted
}

///|
fn shift_diff_to_better_position(
  diff : SequenceDiff,
  sequence1 : ReadabilitySequence,
  sequence2 : ReadabilitySequence,
  sequence1_valid : DiffOffsetRange,
  sequence2_valid : DiffOffsetRange,
) -> SequenceDiff {
  let max_shift_limit = 100
  let mut before = 1
  while diff.original.start - before >= sequence1_valid.start &&
        diff.modified.start - before >= sequence2_valid.start &&
        (sequence2.strongly_equal)(
          diff.modified.start - before,
          diff.modified.end_exclusive - before,
        ) &&
        before < max_shift_limit {
    before += 1
  }
  before -= 1
  let mut after = 0
  while diff.original.start + after < sequence1_valid.end_exclusive &&
        diff.modified.end_exclusive + after < sequence2_valid.end_exclusive &&
        (sequence2.strongly_equal)(
          diff.modified.start + after,
          diff.modified.end_exclusive + after,
        ) &&
        after < max_shift_limit {
    after += 1
  }
  if before == 0 && after == 0 {
    return diff
  }
  let mut best_delta = 0
  let mut best_score = -1
  for delta in -before..<=after {
    let modified_start = diff.modified.start + delta
    let modified_end = diff.modified.end_exclusive + delta
    let original_offset = diff.original.start + delta
    let score = (sequence1.boundary_score)(original_offset) +
      (sequence2.boundary_score)(modified_start) +
      (sequence2.boundary_score)(modified_end)
    if score > best_score {
      best_score = score
      best_delta = delta
    }
  }
  diff.delta(best_delta)
}

///|
fn shift_sequence_diffs(
  sequence1 : ReadabilitySequence,
  sequence2 : ReadabilitySequence,
  sequence_diffs : Array[SequenceDiff],
) -> Array[SequenceDiff] {
  let result = sequence_diffs.copy()
  for index in 0..<result.length() {
    let previous = if index > 0 { Some(result[index - 1]) } else { None }
    let next = if index + 1 < result.length() {
      Some(result[index + 1])
    } else {
      None
    }
    let sequence1_valid : DiffOffsetRange = {
      start: previous.map_or(0, value => value.original.end_exclusive + 1),
      end_exclusive: next.map_or(sequence1.values.length(), value => {
        value.original.start - 1
      }),
    }
    let sequence2_valid : DiffOffsetRange = {
      start: previous.map_or(0, value => value.modified.end_exclusive + 1),
      end_exclusive: next.map_or(sequence2.values.length(), value => {
        value.modified.start - 1
      }),
    }
    let current = result[index]
    if current.original.is_empty() {
      result[index] = shift_diff_to_better_position(
        current, sequence1, sequence2, sequence1_valid, sequence2_valid,
      )
    } else if current.modified.is_empty() {
      result[index] = shift_diff_to_better_position(
        current.swap(),
        sequence2,
        sequence1,
        sequence2_valid,
        sequence1_valid,
      ).swap()
    }
  }
  result
}

///|
fn optimize_sequence_diffs(
  sequence1 : ReadabilitySequence,
  sequence2 : ReadabilitySequence,
  sequence_diffs : Array[SequenceDiff],
) -> Array[SequenceDiff] {
  let first = join_sequence_diffs_by_shifting(
    sequence1, sequence2, sequence_diffs,
  )
  let second = join_sequence_diffs_by_shifting(sequence1, sequence2, first)
  shift_sequence_diffs(sequence1, sequence2, second)
}

///|
// One left-to-right pass that folds each diff into the one accumulated before
// it whenever `should_join` accepts the pair.
fn join_adjacent_sequence_diffs(
  sequence_diffs : Array[SequenceDiff],
  should_join : (SequenceDiff, SequenceDiff) -> Bool,
) -> Array[SequenceDiff] {
  let result : Array[SequenceDiff] = []
  for diff in sequence_diffs {
    let last_index = result.length() - 1
    if last_index >= 0 && should_join(result[last_index], diff) {
      result[last_index] = result[last_index].join(diff)
    } else {
      result.push(diff)
    }
  }
  result
}

///|
// Repeat that pass until it stops merging, at most eleven times. Every join
// drops one diff, so a pass that returns as many diffs as it received made no
// join and the sequence is stable.
fn join_adjacent_sequence_diffs_until_stable(
  sequence_diffs : Array[SequenceDiff],
  should_join : (SequenceDiff, SequenceDiff) -> Bool,
) -> Array[SequenceDiff] {
  let mut diffs = sequence_diffs
  for _ in 0..<11 {
    let joined = join_adjacent_sequence_diffs(diffs, should_join)
    let stable = joined.length() == diffs.length()
    diffs = joined
    if stable {
      break
    }
  }
  diffs
}

///|
fn remove_short_matches(
  original_values : Array[Int],
  modified_values : Array[Int],
  sequence_diffs : Array[SequenceDiff],
) -> Array[SequenceDiff] {
  join_adjacent_sequence_diffs(sequence_diffs, (last, diff) => {
    let original_gap : DiffOffsetRange = {
      start: last.original.end_exclusive,
      end_exclusive: diff.original.start,
    }
    let modified_gap : DiffOffsetRange = {
      start: last.modified.end_exclusive,
      end_exclusive: diff.modified.start,
    }
    scalar_range_utf16_length(original_values, original_gap) <= 2 ||
    scalar_range_utf16_length(modified_values, modified_gap) <= 2
  })
}

///|
fn scalar_utf16_length(value : Int) -> Int {
  value.unsafe_to_char().utf16_len()
}

///|
fn scalar_range_utf16_length(
  values : Array[Int],
  range : DiffOffsetRange,
) -> Int {
  let mut length = 0
  for index in range.start..<range.end_exclusive {
    length += scalar_utf16_length(values[index])
  }
  length
}

///|
fn scalar_range_line_count(values : Array[Int], range : DiffOffsetRange) -> Int {
  let mut count = 0
  for index in range.start..<range.end_exclusive {
    if values[index] == '\n'.to_int() {
      count += 1
    }
  }
  count
}

///|
fn scalar_trimmed_range(
  values : Array[Int],
  range : DiffOffsetRange,
) -> DiffOffsetRange {
  let mut start = range.start
  let mut end_exclusive = range.end_exclusive
  while start < end_exclusive && values[start].unsafe_to_char().is_whitespace() {
    start += 1
  }
  while end_exclusive > start &&
        values[end_exclusive - 1].unsafe_to_char().is_whitespace() {
    end_exclusive -= 1
  }
  { start, end_exclusive, }
}

///|
fn scalar_extend_to_full_lines(
  values : Array[Int],
  range : DiffOffsetRange,
) -> DiffOffsetRange {
  let mut start = range.start
  while start > 0 && values[start - 1] != '\n'.to_int() {
    start -= 1
  }
  let mut end_exclusive = range.end_exclusive
  while end_exclusive < values.length() &&
        (end_exclusive == 0 || values[end_exclusive - 1] != '\n'.to_int()) {
    end_exclusive += 1
  }
  { start, end_exclusive, }
}

///|
fn long_diff_side_score(line_count : Int, utf16_length : Int) -> Double {
  (line_count * 40 + utf16_length).min(130).to_double()
}

///|
fn long_diff_pair_score(
  first_line_count : Int,
  first_utf16_length : Int,
  second_line_count : Int,
  second_utf16_length : Int,
) -> Double {
  @math.pow(
    @math.pow(long_diff_side_score(first_line_count, first_utf16_length), 1.5) +
    @math.pow(long_diff_side_score(second_line_count, second_utf16_length), 1.5),
    1.5,
  )
}

///|
fn should_join_long_scalar_diffs(
  original_values : Array[Int],
  modified_values : Array[Int],
  before : SequenceDiff,
  after : SequenceDiff,
) -> Bool {
  let unchanged : DiffOffsetRange = {
    start: before.original.end_exclusive,
    end_exclusive: after.original.start,
  }
  if scalar_range_line_count(original_values, unchanged) > 5 ||
    scalar_range_utf16_length(original_values, unchanged) > 500 {
    return false
  }
  let trimmed = scalar_trimmed_range(original_values, unchanged)
  if scalar_range_utf16_length(original_values, trimmed) > 20 ||
    scalar_range_line_count(original_values, trimmed) > 0 {
    return false
  }
  let before_score = long_diff_pair_score(
    scalar_range_line_count(original_values, before.original),
    scalar_range_utf16_length(original_values, before.original),
    scalar_range_line_count(modified_values, before.modified),
    scalar_range_utf16_length(modified_values, before.modified),
  )
  let after_score = long_diff_pair_score(
    scalar_range_line_count(original_values, after.original),
    scalar_range_utf16_length(original_values, after.original),
    scalar_range_line_count(modified_values, after.modified),
    scalar_range_utf16_length(modified_values, after.modified),
  )
  let threshold = @math.pow(@math.pow(130.0, 1.5), 1.5) * 1.3
  before_score + after_score > threshold
}

///|
fn mark_short_trim_as_changed(
  original_values : Array[Int],
  modified_values : Array[Int],
  diffs : Array[SequenceDiff],
) -> Array[SequenceDiff] {
  let result : Array[SequenceDiff] = []
  for index in 0..<diffs.length() {
    let previous = if index > 0 { Some(diffs[index - 1]) } else { None }
    let current = diffs[index]
    let next = if index + 1 < diffs.length() {
      Some(diffs[index + 1])
    } else {
      None
    }
    let mut expanded = current
    let changed_utf16_length = scalar_range_utf16_length(
        original_values,
        current.original,
      ) +
      scalar_range_utf16_length(modified_values, current.modified)
    if changed_utf16_length > 100 {
      let full_original = scalar_extend_to_full_lines(
        original_values,
        current.original,
      )
      let prefix : DiffOffsetRange = {
        start: full_original.start,
        end_exclusive: current.original.start,
      }
      let prefix_trimmed = scalar_trimmed_range(original_values, prefix)
      let prefix_utf16_length = scalar_range_utf16_length(
        original_values, prefix,
      )
      if prefix_utf16_length > 0 &&
        scalar_range_utf16_length(original_values, prefix_trimmed) <= 3 {
        let scalar_length = prefix.length()
        expanded = {
          original: {
            start: expanded.original.start - scalar_length,
            end_exclusive: expanded.original.end_exclusive,
          },
          modified: {
            start: expanded.modified.start - scalar_length,
            end_exclusive: expanded.modified.end_exclusive,
          },
        }
      }
      let suffix : DiffOffsetRange = {
        start: current.original.end_exclusive,
        end_exclusive: full_original.end_exclusive,
      }
      let suffix_trimmed = scalar_trimmed_range(original_values, suffix)
      let suffix_utf16_length = scalar_range_utf16_length(
        original_values, suffix,
      )
      if suffix_utf16_length > 0 &&
        scalar_range_utf16_length(original_values, suffix_trimmed) <= 3 {
        let scalar_length = suffix.length()
        expanded = {
          original: {
            start: expanded.original.start,
            end_exclusive: expanded.original.end_exclusive + scalar_length,
          },
          modified: {
            start: expanded.modified.start,
            end_exclusive: expanded.modified.end_exclusive + scalar_length,
          },
        }
      }
    }
    let available : SequenceDiff = {
      original: {
        start: previous.map_or(0, value => value.original.end_exclusive),
        end_exclusive: next.map_or(original_values.length(), value => {
          value.original.start
        }),
      },
      modified: {
        start: previous.map_or(0, value => value.modified.end_exclusive),
        end_exclusive: next.map_or(modified_values.length(), value => {
          value.modified.start
        }),
      },
    }
    guard expanded.intersect(available) is Some(clamped) else { continue }
    if !result.is_empty() {
      let last_index = result.length() - 1
      let last = result[last_index]
      if clamped.original.start == last.original.end_exclusive &&
        clamped.modified.start == last.modified.end_exclusive {
        result[last_index] = last.join(clamped)
        continue
      }
    }
    result.push(clamped)
  }
  result
}

///|
// Mandatory final stage of the pinned ordinary DiffEditor character pipeline.
// It merges tiny one-line matches between substantial edits, then extends
// large edits over visually meaningless <=3-code-unit line trim.
fn remove_very_short_matching_text_between_long_diffs(
  original_values : Array[Int],
  modified_values : Array[Int],
  sequence_diffs : Array[SequenceDiff],
) -> Array[SequenceDiff] {
  let diffs = join_adjacent_sequence_diffs_until_stable(sequence_diffs, (
    previous,
    current,
  ) => {
    should_join_long_scalar_diffs(
      original_values, modified_values, previous, current,
    )
  })
  mark_short_trim_as_changed(original_values, modified_values, diffs)
}

///|
fn merge_touching_sequence_diffs(
  sequence_diffs : Array[SequenceDiff],
) -> Array[SequenceDiff] {
  join_adjacent_sequence_diffs(sequence_diffs, (last, diff) => {
    last.original.end_exclusive >= diff.original.start ||
    last.modified.end_exclusive >= diff.modified.start
  })
}

///|
fn line_indentation(line : String) -> Int {
  let mut index = 0
  while index < line.length() && line[index] is (' ' | '\t') {
    index += 1
  }
  index
}

///|
fn line_readability_sequence(
  values : Array[Int],
  lines : Array[String],
) -> ReadabilitySequence {
  {
    values,
    strongly_equal: fn(first, second) { lines[first] == lines[second] },
    boundary_score: fn(length) {
      let before = if length == 0 {
        0
      } else {
        line_indentation(lines[length - 1])
      }
      let after = if length == lines.length() {
        0
      } else {
        line_indentation(lines[length])
      }
      1000 - (before + after)
    },
  }
}

///|
fn intern_line_values(
  original_lines : Array[String],
  modified_lines : Array[String],
) -> (Array[Int], Array[Int]) {
  let keys : Map[String, Int] = Map([])
  let get_key = fn(line : String) {
    let text = line.trim().to_owned()
    match keys.get(text) {
      Some(key) => key
      None => {
        let key = keys.length()
        keys[text] = key
        key
      }
    }
  }
  (
    original_lines.map(line => get_key(line)),
    modified_lines.map(line => get_key(line)),
  )
}

///|
fn compute_advanced_line_diffs(
  original_lines : Array[String],
  modified_lines : Array[String],
) -> Array[SequenceDiff] {
  let (original_values, modified_values) = intern_line_values(
    original_lines, modified_lines,
  )
  let original_sequence = line_readability_sequence(
    original_values, original_lines,
  )
  let modified_sequence = line_readability_sequence(
    modified_values, modified_lines,
  )
  let initial = if original_values.length() + modified_values.length() < 1700 {
    weighted_sequence_diffs(original_values, modified_values, fn(
      original_offset,
      modified_offset,
    ) {
      if original_lines[original_offset] == modified_lines[modified_offset] {
        let length = modified_lines[modified_offset].length()
        if length == 0 {
          0.1
        } else {
          1.0 + @math.ln(1.0 + length.to_double())
        }
      } else {
        0.99
      }
    })
  } else {
    myers_sequence_diffs(original_values, modified_values)
  }
  let optimized = optimize_sequence_diffs(
    original_sequence, modified_sequence, initial,
  )
  remove_very_short_matching_lines_between_diffs(original_lines, optimized)
}

///|
fn include_strict_whitespace_line_diffs(
  original_lines : Array[String],
  modified_lines : Array[String],
  sequence_diffs : Array[SequenceDiff],
  ignore_trim_whitespace : Bool,
) -> Array[SequenceDiff] {
  if ignore_trim_whitespace {
    return sequence_diffs
  }
  let result : Array[SequenceDiff] = []
  // Emit a one-line diff for every line of an equal run whose two sides still
  // differ once whitespace is no longer ignored.
  fn push_strict_whitespace_diffs(
    original_start : Int,
    modified_start : Int,
    equal_count : Int,
  ) -> Unit {
    for offset in 0..<equal_count {
      let original_offset = original_start + offset
      let modified_offset = modified_start + offset
      if original_lines[original_offset] != modified_lines[modified_offset] {
        result.push({
          original: {
            start: original_offset,
            end_exclusive: original_offset + 1,
          },
          modified: {
            start: modified_offset,
            end_exclusive: modified_offset + 1,
          },
        })
      }
    }
  }

  let mut original_start = 0
  let mut modified_start = 0
  for diff in sequence_diffs {
    push_strict_whitespace_diffs(
      original_start,
      modified_start,
      diff.original.start - original_start,
    )
    result.push(diff)
    original_start = diff.original.end_exclusive
    modified_start = diff.modified.end_exclusive
  }
  push_strict_whitespace_diffs(
    original_start,
    modified_start,
    original_lines.length() - original_start,
  )
  merge_touching_sequence_diffs(result)
}

///|
fn line_non_whitespace_length(
  lines : Array[String],
  start : Int,
  end_exclusive : Int,
) -> Int {
  let mut length = 0
  for line_index in start..<end_exclusive {
    for character in lines[line_index] {
      if !character.is_whitespace() {
        length += character.utf16_len()
      }
    }
  }
  length
}

///|
// Port of removeVeryShortMatchingLinesBetweenDiffs. Its <=4, >5, and
// at-most-eleven-pass constants are behavior-bearing.
fn remove_very_short_matching_lines_between_diffs(
  original_lines : Array[String],
  sequence_diffs : Array[SequenceDiff],
) -> Array[SequenceDiff] {
  join_adjacent_sequence_diffs_until_stable(sequence_diffs, (previous, current) => {
    let short_unchanged = line_non_whitespace_length(
        original_lines,
        previous.original.end_exclusive,
        current.original.start,
      ) <=
      4
    let substantial_side = previous.original.length() +
      previous.modified.length() >
      5 ||
      current.original.length() + current.modified.length() > 5
    short_unchanged && substantial_side
  })
}

///|
priv enum ScalarBoundaryCategory {
  WordLower
  WordUpper
  WordNumber
  End
  Other
  Separator
  Space
  LineBreak
} derive(Eq)

///|
fn scalar_boundary_category(value : Int) -> ScalarBoundaryCategory {
  if value == '\n'.to_int() {
    LineBreak
  } else if value == ' '.to_int() || value == '\t'.to_int() {
    Space
  } else if value >= 'a'.to_int() && value <= 'z'.to_int() {
    WordLower
  } else if value >= 'A'.to_int() && value <= 'Z'.to_int() {
    WordUpper
  } else if value >= '0'.to_int() && value <= '9'.to_int() {
    WordNumber
  } else if value == -1 {
    End
  } else if value == ','.to_int() || value == ';'.to_int() {
    Separator
  } else {
    Other
  }
}

///|
fn scalar_category_score(category : ScalarBoundaryCategory) -> Int {
  match category {
    WordLower | WordUpper | WordNumber => 0
    End | LineBreak => 10
    Other => 2
    Separator => 30
    Space => 3
  }
}

///|
fn scalar_boundary_score(values : Array[Int], length : Int) -> Int {
  let previous = scalar_boundary_category(
    if length > 0 {
      values[length - 1]
    } else {
      -1
    },
  )
  let next = scalar_boundary_category(
    if length < values.length() {
      values[length]
    } else {
      -1
    },
  )
  if previous == LineBreak {
    return 150
  }
  let mut score = scalar_category_score(previous) + scalar_category_score(next)
  if previous != next {
    score += 10
    if previous == WordLower && next == WordUpper {
      score += 1
    }
  }
  score
}

///|
fn scalar_readability_sequence(values : Array[Int]) -> ReadabilitySequence {
  {
    values,
    strongly_equal: fn(first, second) { values[first] == values[second] },
    boundary_score: fn(length) { scalar_boundary_score(values, length) },
  }
}

///|
fn is_ascii_word_scalar(value : Int) -> Bool {
  (value >= 'a'.to_int() && value <= 'z'.to_int()) ||
  (value >= 'A'.to_int() && value <= 'Z'.to_int()) ||
  (value >= '0'.to_int() && value <= '9'.to_int())
}

///|
fn find_word_containing(values : Array[Int], offset : Int) -> DiffOffsetRange? {
  if offset < 0 ||
    offset >= values.length() ||
    !is_ascii_word_scalar(values[offset]) {
    return None
  }
  let mut start = offset
  while start > 0 && is_ascii_word_scalar(values[start - 1]) {
    start -= 1
  }
  let mut end_exclusive = offset
  while end_exclusive < values.length() &&
        is_ascii_word_scalar(values[end_exclusive]) {
    end_exclusive += 1
  }
  Some({ start, end_exclusive, })
}

///|
fn invert_sequence_diffs(
  sequence_diffs : Array[SequenceDiff],
  original_length : Int,
  modified_length : Int,
) -> Array[SequenceDiff] {
  let result : Array[SequenceDiff] = []
  let mut original_start = 0
  let mut modified_start = 0
  for diff in sequence_diffs {
    result.push({
      original: { start: original_start, end_exclusive: diff.original.start, },
      modified: { start: modified_start, end_exclusive: diff.modified.start, },
    })
    original_start = diff.original.end_exclusive
    modified_start = diff.modified.end_exclusive
  }
  result.push({
    original: { start: original_start, end_exclusive: original_length, },
    modified: { start: modified_start, end_exclusive: modified_length, },
  })
  result
}

///|
fn merge_sequence_diff_sets(
  first : Array[SequenceDiff],
  second : Array[SequenceDiff],
) -> Array[SequenceDiff] {
  let merged : Array[SequenceDiff] = []
  let mut first_index = 0
  let mut second_index = 0
  while first_index < first.length() || second_index < second.length() {
    let next = if first_index < first.length() &&
      (
        second_index >= second.length() ||
        first[first_index].original.start < second[second_index].original.start
      ) {
      let value = first[first_index]
      first_index += 1
      value
    } else {
      let value = second[second_index]
      second_index += 1
      value
    }
    merged.push(next)
  }
  join_adjacent_sequence_diffs(merged, (last, next) => {
    last.original.end_exclusive >= next.original.start
  })
}

///|
fn scan_parent_for_word_extension(
  sequence1 : Array[Int],
  sequence2 : Array[Int],
  equal_mappings : Array[SequenceDiff],
  future_index : Int,
  pair_original : Int,
  pair_modified : Int,
  equal_mapping : SequenceDiff,
  last_original : Int,
  last_modified : Int,
  find_parent : (Array[Int], Int) -> DiffOffsetRange?,
  force : Bool,
  additional : Array[SequenceDiff],
) -> (Int, Int, Int) {
  if pair_original < last_original || pair_modified < last_modified {
    return (future_index, last_original, last_modified)
  }
  guard find_parent(sequence1, pair_original) is Some(word1) else {
    return (future_index, last_original, last_modified)
  }
  guard find_parent(sequence2, pair_modified) is Some(word2) else {
    return (future_index, last_original, last_modified)
  }
  let mut word : SequenceDiff = { original: word1, modified: word2, }
  guard word.intersect(equal_mapping) is Some(equal_part) else {
    return (future_index, last_original, last_modified)
  }
  let mut equal_chars1 = equal_part.original.length()
  let mut equal_chars2 = equal_part.modified.length()
  let mut index = future_index
  while index < equal_mappings.length() {
    let next = equal_mappings[index]
    if !next.original.intersects(word.original) &&
      !next.modified.intersects(word.modified) {
      break
    }
    guard find_parent(sequence1, next.original.start) is Some(next_word1) else {
      break
    }
    guard find_parent(sequence2, next.modified.start) is Some(next_word2) else {
      break
    }
    let next_word : SequenceDiff = {
      original: next_word1,
      modified: next_word2,
    }
    guard next_word.intersect(next) is Some(next_equal_part) else { break }
    equal_chars1 += next_equal_part.original.length()
    equal_chars2 += next_equal_part.modified.length()
    word = word.join(next_word)
    if word.original.end_exclusive >= next.original.end_exclusive {
      index += 1
    } else {
      break
    }
  }
  let equal_chars = equal_chars1 + equal_chars2
  let word_chars = word.original.length() + word.modified.length()
  if (force && equal_chars < word_chars) || equal_chars * 3 < word_chars * 2 {
    additional.push(word)
  }
  (index, word.original.end_exclusive, word.modified.end_exclusive)
}

///|
fn extend_diffs_to_parent_if_appropriate(
  sequence1 : Array[Int],
  sequence2 : Array[Int],
  sequence_diffs : Array[SequenceDiff],
  find_parent : (Array[Int], Int) -> DiffOffsetRange?,
  force? : Bool = false,
) -> Array[SequenceDiff] {
  let equal_mappings = invert_sequence_diffs(
    sequence_diffs,
    sequence1.length(),
    sequence2.length(),
  )
  let additional : Array[SequenceDiff] = []
  let mut index = 0
  let mut last_original = 0
  let mut last_modified = 0
  while index < equal_mappings.length() {
    let equal_mapping = equal_mappings[index]
    index += 1
    if equal_mapping.original.is_empty() {
      continue
    }
    let anchors = [
      (equal_mapping.original.start, equal_mapping.modified.start),
      (
        equal_mapping.original.end_exclusive - 1,
        equal_mapping.modified.end_exclusive - 1,
      ),
    ]
    for anchor in anchors {
      let (pair_original, pair_modified) = anchor
      let (next_index, next_original, next_modified) = scan_parent_for_word_extension(
        sequence1, sequence2, equal_mappings, index, pair_original, pair_modified,
        equal_mapping, last_original, last_modified, find_parent, force, additional,
      )
      index = next_index
      last_original = next_original
      last_modified = next_modified
    }
  }
  merge_sequence_diff_sets(sequence_diffs, additional)
}

///|
fn compute_advanced_scalar_diffs(
  original_values : Array[Int],
  modified_values : Array[Int],
) -> Array[SequenceDiff] {
  let original_sequence = scalar_readability_sequence(original_values)
  let modified_sequence = scalar_readability_sequence(modified_values)
  let original_utf16_length = scalar_range_utf16_length(original_values, {
    start: 0,
    end_exclusive: original_values.length(),
  })
  let modified_utf16_length = scalar_range_utf16_length(modified_values, {
    start: 0,
    end_exclusive: modified_values.length(),
  })
  let initial = if original_utf16_length + modified_utf16_length < 500 {
    weighted_sequence_diffs(original_values, modified_values, fn(
      _original_offset,
      _modified_offset,
    ) {
      1.0
    })
  } else {
    myers_sequence_diffs(original_values, modified_values)
  }
  let optimized = optimize_sequence_diffs(
    original_sequence, modified_sequence, initial,
  )
  let word_aligned = extend_diffs_to_parent_if_appropriate(
    original_values, modified_values, optimized, find_word_containing,
  )
  remove_very_short_matching_text_between_long_diffs(
    original_values,
    modified_values,
    remove_short_matches(original_values, modified_values, word_aligned),
  )
}

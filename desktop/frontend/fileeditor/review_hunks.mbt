///|
/// One hunk's true changed lines in full-file coordinates. The same normalized
/// value also stores accumulated Line/Token/Tree review coverage.
pub(all) struct ReviewHunk {
  priv old_ranges : Array[@common.LineRange]
  priv new_ranges : Array[@common.LineRange]
} derive(Eq)

///|
fn ReviewHunk::ReviewHunk(
  old_ranges~ : Array[@common.LineRange],
  new_ranges~ : Array[@common.LineRange],
) -> ReviewHunk {
  {
    old_ranges: normalize_review_line_ranges(old_ranges),
    new_ranges: normalize_review_line_ranges(new_ranges),
  }
}

///|
fn ReviewHunk::is_empty(self : ReviewHunk) -> Bool {
  self.old_ranges.is_empty() && self.new_ranges.is_empty()
}

///|
fn ReviewHunk::union(self : ReviewHunk, other : ReviewHunk) -> ReviewHunk {
  let old_ranges = self.old_ranges.copy()
  old_ranges.append(other.old_ranges)
  let new_ranges = self.new_ranges.copy()
  new_ranges.append(other.new_ranges)
  ReviewHunk(old_ranges~, new_ranges~)
}

///|
fn ReviewHunk::subtract(self : ReviewHunk, other : ReviewHunk) -> ReviewHunk {
  ReviewHunk(
    old_ranges=review_line_ranges_subtract(self.old_ranges, other.old_ranges),
    new_ranges=review_line_ranges_subtract(self.new_ranges, other.new_ranges),
  )
}

///|
fn ReviewHunk::contains(self : ReviewHunk, other : ReviewHunk) -> Bool {
  review_line_ranges_subset(other.old_ranges, self.old_ranges) &&
  review_line_ranges_subset(other.new_ranges, self.new_ranges)
}

///|
fn ReviewHunk::intersects(self : ReviewHunk, other : ReviewHunk) -> Bool {
  review_line_ranges_intersect(self.old_ranges, other.old_ranges) ||
  review_line_ranges_intersect(self.new_ranges, other.new_ranges)
}

///|
/// Only DiffEditor's real mapping members participate. Joined reveal context
/// is navigation geometry, not review coverage. `None` drops an empty side's
/// artificial TextModel anchor.
fn ReviewHunk::from_diff_hunk(
  hunk : @viewer.DiffHunk,
  old_offset : Int?,
  new_offset : Int?,
) -> ReviewHunk {
  let old_ranges : Array[@common.LineRange] = []
  let new_ranges : Array[@common.LineRange] = []
  for mapping in hunk.members {
    if old_offset is Some(offset) && !mapping.original.is_empty() {
      old_ranges.push(
        @common.LineRange(
          mapping.original.start_line_number + offset,
          mapping.original.end_line_number_exclusive + offset,
        ),
      )
    }
    if new_offset is Some(offset) && !mapping.modified.is_empty() {
      new_ranges.push(
        @common.LineRange(
          mapping.modified.start_line_number + offset,
          mapping.modified.end_line_number_exclusive + offset,
        ),
      )
    }
  }
  ReviewHunk(old_ranges~, new_ranges~)
}

///|
priv enum ReviewHunkState {
  ReviewHunkUnviewed
  ReviewHunkPartial
  ReviewHunkViewed
}

///|
pub(all) enum ReviewFileProgress {
  ReviewFileInProgress(ReviewHunk)
  ReviewFileComplete
} derive(Eq)

///|
pub(all) struct ChangedFileReview {
  priv change : ChangedFile
  priv progress : ReviewFileProgress
} derive(Eq)

///|
priv enum ReviewCompletionState {
  ReviewUnviewed
  ReviewInProgress
  ReviewComplete
}

///|
pub(all) struct ReviewActiveHunk {
  priv change : ChangedFile
  priv review_generation : Int
  priv hunk : ReviewHunk
  // The complete Line diff is the file-level review universe. Semantic hunks
  // project into it, but never redefine it when filters or grouping change.
  priv file_changes : ReviewHunk?
  priv position : ReviewHunkPosition?
} derive(Eq)

///|
pub(all) struct ReviewHunkPosition {
  priv current : Int
  priv total : Int
} derive(Eq)

///|
fn ReviewHunkPosition::from_zero_based(
  index : Int?,
  total : Int,
) -> ReviewHunkPosition? {
  guard index is Some(index) && index >= 0 && index < total else { return None }
  Some({ current: index + 1, total, })
}

///|
fn normalize_review_line_ranges(
  ranges : Array[@common.LineRange],
) -> Array[@common.LineRange] {
  let sorted = ranges.filter(range => {
    range.start_line_number >= 1 &&
    range.end_line_number_exclusive > range.start_line_number
  })
  sorted.sort_by((left, right) => {
    let starts = left.start_line_number - right.start_line_number
    if starts != 0 {
      starts
    } else {
      left.end_line_number_exclusive - right.end_line_number_exclusive
    }
  })
  let result : Array[@common.LineRange] = []
  for range in sorted {
    if result.is_empty() {
      result.push(range)
      continue
    }
    let last_index = result.length() - 1
    let last = result[last_index]
    if range.start_line_number <= last.end_line_number_exclusive {
      result[last_index] = @common.LineRange(
        last.start_line_number,
        last.end_line_number_exclusive.max(range.end_line_number_exclusive),
      )
    } else {
      result.push(range)
    }
  }
  result
}

///|
fn review_line_ranges_subtract(
  source : Array[@common.LineRange],
  removed : Array[@common.LineRange],
) -> Array[@common.LineRange] {
  let source = normalize_review_line_ranges(source)
  let removed = normalize_review_line_ranges(removed)
  let result : Array[@common.LineRange] = []
  for range in source {
    let mut cursor = range.start_line_number
    for cut in removed {
      if cut.end_line_number_exclusive <= cursor {
        continue
      }
      if cut.start_line_number >= range.end_line_number_exclusive {
        break
      }
      if cut.start_line_number > cursor {
        result.push(
          @common.LineRange(
            cursor,
            cut.start_line_number.min(range.end_line_number_exclusive),
          ),
        )
      }
      cursor = cursor.max(cut.end_line_number_exclusive)
      if cursor >= range.end_line_number_exclusive {
        break
      }
    }
    if cursor < range.end_line_number_exclusive {
      result.push(@common.LineRange(cursor, range.end_line_number_exclusive))
    }
  }
  result
}

///|
fn review_line_ranges_subset(
  requested : Array[@common.LineRange],
  available : Array[@common.LineRange],
) -> Bool {
  let requested = normalize_review_line_ranges(requested)
  let available = normalize_review_line_ranges(available)
  let mut available_index = 0
  for range in requested {
    while available_index < available.length() &&
          available[available_index].end_line_number_exclusive <=
          range.start_line_number {
      available_index += 1
    }
    if available_index >= available.length() {
      return false
    }
    let cover = available[available_index]
    if cover.start_line_number > range.start_line_number ||
      cover.end_line_number_exclusive < range.end_line_number_exclusive {
      return false
    }
  }
  true
}

///|
fn review_line_ranges_intersect(
  left : Array[@common.LineRange],
  right : Array[@common.LineRange],
) -> Bool {
  let left = normalize_review_line_ranges(left)
  let right = normalize_review_line_ranges(right)
  let mut left_index = 0
  let mut right_index = 0
  while left_index < left.length() && right_index < right.length() {
    let left_range = left[left_index]
    let right_range = right[right_index]
    if left_range.start_line_number < right_range.end_line_number_exclusive &&
      right_range.start_line_number < left_range.end_line_number_exclusive {
      return true
    }
    if left_range.end_line_number_exclusive <
      right_range.end_line_number_exclusive {
      left_index += 1
    } else {
      right_index += 1
    }
  }
  false
}

///|
fn State::review_file_progress(
  self : State,
  change : ChangedFile,
) -> ReviewFileProgress? {
  for entry in self.review_progress {
    if entry.change == change {
      return Some(entry.progress)
    }
  }
  None
}

///|
fn State::changed_file_review_state(
  self : State,
  change : ChangedFile,
) -> ReviewCompletionState {
  match self.review_file_progress(change) {
    None => ReviewUnviewed
    Some(ReviewFileInProgress(_)) => ReviewInProgress
    Some(ReviewFileComplete) => ReviewComplete
  }
}

///|
fn State::is_change_reviewed(self : State, change : ChangedFile) -> Bool {
  self.changed_file_review_state(change) is ReviewComplete
}

///|
fn State::review_hunk_state(
  self : State,
  change : ChangedFile,
  hunk : ReviewHunk,
) -> ReviewHunkState {
  if hunk.is_empty() {
    return ReviewHunkUnviewed
  }
  match self.review_file_progress(change) {
    Some(ReviewFileComplete) => ReviewHunkViewed
    Some(ReviewFileInProgress(coverage)) =>
      if coverage.contains(hunk) {
        ReviewHunkViewed
      } else if coverage.intersects(hunk) {
        ReviewHunkPartial
      } else {
        ReviewHunkUnviewed
      }
    None => ReviewHunkUnviewed
  }
}

///|
fn State::set_review_file_progress(
  self : State,
  change : ChangedFile,
  progress : ReviewFileProgress?,
) -> State {
  let entries = self.review_progress.filter(entry => entry.change != change)
  if progress is Some(progress) {
    entries.push({ change, progress, })
  }
  { ..self, review_progress: entries, }
}

///|
fn State::current_review_generation(
  self : State,
  change : ChangedFile,
  active_file : @pathx.Relative?,
) -> Int? {
  guard active_file == Some(change.path) &&
    self.changes is ChangeListReady(files~, ..) &&
    files.contains(change) &&
    self.docs.get(change.path) is Some({ review: Some(review), .. }) &&
    review.selected == change &&
    review.view_mode is ReviewDiff &&
    self.review_view_mode is ReviewDiff else {
    return None
  }
  Some(review.diff_loading_generation())
}

///|
fn State::accept_active_review_hunk(
  self : State,
  change : ChangedFile,
  review_generation : Int,
  hunk : ReviewHunk?,
  file_changes : ReviewHunk?,
  position : ReviewHunkPosition?,
  active_file : @pathx.Relative?,
) -> State {
  guard self.current_review_generation(change, active_file) ==
    Some(review_generation) else {
    return self
  }
  {
    ..self,
    review_active_hunk: hunk.map(hunk => {
      change,
      review_generation,
      hunk,
      file_changes,
      position,
    }),
  }
}

///|
fn State::active_review_hunk(
  self : State,
  active_file : @pathx.Relative?,
) -> ReviewActiveHunk? {
  guard self.review_active_hunk is Some(active) &&
    self.current_review_generation(active.change, active_file) ==
    Some(active.review_generation) else {
    return None
  }
  Some(active)
}

///|
fn State::toggle_active_review_hunk(
  self : State,
  active_file : @pathx.Relative?,
) -> State {
  guard self.active_review_hunk(active_file) is Some(active) &&
    !active.hunk.is_empty() else {
    return self
  }
  match self.review_file_progress(active.change) {
    Some(ReviewFileComplete) => {
      // File completion projects to every hunk. Once the full Line universe is
      // known, unmarking one hunk keeps every other hunk viewed and naturally
      // returns the file to partial progress.
      guard active.file_changes is Some(file_changes) else { return self }
      let next = file_changes.subtract(active.hunk)
      self.set_review_file_progress(
        active.change,
        if next.is_empty() {
          None
        } else {
          Some(ReviewFileInProgress(next))
        },
      )
    }
    Some(ReviewFileInProgress(coverage)) => {
      let next = if coverage.contains(active.hunk) {
        coverage.subtract(active.hunk)
      } else {
        coverage.union(active.hunk)
      }
      self.set_review_file_progress(
        active.change,
        if next.is_empty() {
          None
        } else if active.file_changes is Some(file_changes) &&
          next.contains(file_changes) {
          Some(ReviewFileComplete)
        } else {
          Some(ReviewFileInProgress(next))
        },
      )
    }
    None =>
      self.set_review_file_progress(
        active.change,
        if active.file_changes is Some(file_changes) &&
          active.hunk.contains(file_changes) {
          Some(ReviewFileComplete)
        } else {
          Some(ReviewFileInProgress(active.hunk))
        },
      )
  }
}

///|
fn State::clear_review_active_hunk(self : State) -> State {
  if self.review_active_hunk is None {
    self
  } else {
    { ..self, review_active_hunk: None, }
  }
}

///|
pub extend ReviewHunk with Eq::{equal, not_equal}

///|
pub extend ReviewFileProgress with Eq::{equal, not_equal}

///|
pub extend ChangedFileReview with Eq::{equal, not_equal}

///|
pub extend ReviewActiveHunk with Eq::{equal, not_equal}

///|
pub extend ReviewHunkPosition with Eq::{equal, not_equal}

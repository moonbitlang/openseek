///|
/// Source coordinates stay separate from the (possibly clipped) preview.
/// Columns use the editor's one-based UTF-16 coordinates, with exclusive ends.
priv struct SearchPreviewLine {
  line : Int32
  text : String
  start_column : Int32
}

///|
/// One visible result can contain several occurrences, or one multiline match.
/// Presentation and navigation consume this model without knowing the engine.
priv struct SearchResultItem {
  path : String
  target : @common.Range
  ranges : Array[@common.Range]
  preview : Array[SearchPreviewLine]
}

///|
fn SearchResultItem::from_text(
  result : @protocol.TextSearchMatch,
) -> SearchResultItem? {
  let ranges = result.ranges.map(range => {
    @common.Range(
      result.line_number,
      range.start_column,
      result.line_number,
      range.end_column,
    )
  })
  guard ranges is [target, ..] else { return None }
  Some({
    path: result.path,
    target,
    ranges,
    preview: [
      {
        line: result.line_number,
        text: result.preview,
        start_column: result.preview_start_column,
      },
    ],
  })
}

///|
fn SearchResultItem::from_semantic(
  hit : @protocol.SemanticSearchHit,
) -> SearchResultItem {
  let target = @common.Range(
    hit.start_line,
    hit.start_column,
    hit.end_line,
    hit.end_column,
  )
  let preview = hit.source_context.map(line => SearchPreviewLine::{
    line: line.line,
    text: line.text,
    start_column: 1,
  })
  // Context rows may be absent or rejected by the Host. The matched source
  // still provides a useful preview, whose first line starts at the match.
  if preview.is_empty() {
    for index, text in hit.matched_source.split("\n").to_array() {
      preview.push({
        line: hit.start_line + index,
        text: text.to_owned(),
        start_column: if index == 0 {
          hit.start_column
        } else {
          1
        },
      })
    }
  }
  preview.sort_by((a, b) => a.line.compare(b.line))
  { path: hit.path, target, ranges: [target], preview, }
}

///|
fn Page::result_items(self : Page) -> Array[SearchResultItem] {
  match self.mode {
    Text => self.text.matches.filter_map(SearchResultItem::from_text)
    Semantic => self.semantic.hits.map(SearchResultItem::from_semantic)
  }
}

///|
/// Project a source range onto one preview line; never use preview offsets for
/// navigation. Empty intersections include an exclusive end at column one.
fn SearchPreviewLine::highlight_slices(
  self : SearchPreviewLine,
  ranges : Array[@common.Range],
) -> Array[(Int32, Int32)] {
  let slices : Array[(Int32, Int32)] = []
  for range in ranges {
    if self.line < range.start_line_number || self.line > range.end_line_number {
      continue
    }
    let start = if self.line == range.start_line_number {
      range.start_column - self.start_column
    } else {
      0
    }
    let end = if self.line == range.end_line_number {
      range.end_column - self.start_column
    } else {
      self.text.length()
    }
    let start = start.max(0).min(self.text.length())
    let end = end.max(0).min(self.text.length())
    if start < end {
      slices.push((start, end))
    }
  }
  slices.sort_by((a, b) => a.0.compare(b.0))
  slices
}

///|
/// Combine touching source previews within a file, regardless of provider.
/// Collect each cluster before merging so large runs do not repeatedly copy
/// growing arrays. Keep occurrences separate from the deduplicated preview.
fn coalesce_results(items : Array[SearchResultItem]) -> Array[SearchResultItem] {
  let sorted = items.copy()
  sorted.sort_by((a, b) => {
    let a_line = a.preview[0].line
    let b_line = b.preview[0].line
    a_line.compare(b_line)
  })
  let results : Array[SearchResultItem] = []
  let cluster : Array[SearchResultItem] = []
  let mut last_line : Int32? = None
  for item in sorted {
    let first = item.preview[0].line
    if last_line is Some(last) && first > last + 1 {
      results.push(merge_result_cluster(cluster))
      cluster.clear()
      last_line = None
    }
    cluster.push(item)
    let end = item.preview[item.preview.length() - 1].line
    last_line = Some(
      match last_line {
        Some(last) => last.max(end)
        None => end
      },
    )
  }
  if !cluster.is_empty() {
    results.push(merge_result_cluster(cluster))
  }
  results
}

///|
fn merge_result_cluster(items : Array[SearchResultItem]) -> SearchResultItem {
  let ranges : Array[@common.Range] = []
  let lines : Array[SearchPreviewLine] = []
  for item in items {
    ranges.append(item.ranges)
    lines.append(item.preview)
  }
  ranges.sort_by((a, b) => {
    let line = a.start_line_number.compare(b.start_line_number)
    if line != 0 {
      line
    } else {
      a.start_column.compare(b.start_column)
    }
  })
  lines.sort_by((a, b) => {
    let line = a.line.compare(b.line)
    if line != 0 {
      line
    } else {
      a.start_column.compare(b.start_column)
    }
  })
  let preview : Array[SearchPreviewLine] = []
  for line in lines {
    if preview.last() is Some(previous) && previous.line == line.line {
      let offset = line.start_column - previous.start_column
      // A fallback may contain only part of a line. Join overlapping fragments
      // without losing either end; disjoint clipped fragments remain separate.
      if offset <= previous.text.length() {
        let covered = previous.text.length() - offset
        if covered < line.text.length() {
          preview[preview.length() - 1] = {
            ..previous,
            text: previous.text + line.text[covered:].to_owned(),
          }
        }
        continue
      }
    }
    preview.push(line)
  }
  { path: items[0].path, target: ranges[0], ranges, preview, }
}

///|
/// Each line remains an independent keyboard/pointer destination after merging.
/// Context opens its nearest match; within a match, prefer the latest start
/// (so a nested or subsequent hit does not always open the first occurrence).
fn SearchResultItem::target_for_line(
  self : SearchResultItem,
  line : Int32,
) -> @common.Range {
  let mut target = self.target
  let mut distance : Int32? = None
  for range in self.ranges {
    let end_line = if range.end_column == 1 &&
      range.end_line_number > range.start_line_number {
      range.end_line_number - 1
    } else {
      range.end_line_number
    }
    let candidate = (range.start_line_number - line).max(line - end_line).max(0)
    if distance is None ||
      (
        distance is Some(d) &&
        (
          candidate < d ||
          (
            candidate == 0 &&
            d == 0 &&
            range.start_line_number > target.start_line_number
          )
        )
      ) {
      target = range
      distance = Some(candidate)
    }
  }
  target
}

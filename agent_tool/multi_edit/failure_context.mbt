///|
/// Surrounding context lines shown above and below a failed edit's anchor.
const FailureContextLinesBefore : Int32 = 2

///|
const FailureContextLinesAfter : Int32 = 2

///|
/// Maximum lines rendered in a single failure's file context block, so a wide
/// `start_line`..`end_line` range or long `old_string` cannot flood the report.
const FailureContextMaxLines : Int32 = 20

///|
/// Longest rendered context line; longer lines are cut with an ellipsis on a
/// character boundary.
const FailureLineDisplayCap : Int32 = 200

///|
/// Maximum number of failed edits in one batch that include a file context
/// block (matching `RejectedFileDisplayLimit`), and total character budget
/// across all context blocks in a batch.
const FailureContextSiteLimit : Int32 = 3

///|
const FailureContextBudgetChars : Int32 = 12_000

///|
/// Maximum total match locations listed in one `old_string not found` hint.
/// Each side retains up to this many nearby matches before merging so closer
/// matches on one side are never evicted by farther matches on the other.
const MatchHintDisplayLimit : Int32 = 5

///|
const MatchHintWindowEachSide : Int32 = MatchHintDisplayLimit

///|
priv struct NormalizedContent {
  text : String
  offset_map : Array[Int32]
}

///|
/// Per-file lazily normalized content and line-start index shared across all
/// edits targeting the same file in a `multi_edit` batch. Pure insertion
/// batches never normalize or index the file.
priv struct FileContextIndex {
  content : String
  mut normalized : NormalizedContent?
  mut line_starts : Array[Int32]?
}

///|
fn FileContextIndex::new(content : String) -> FileContextIndex {
  { content, normalized: None, line_starts: None, }
}

///|
fn FileContextIndex::normalized(self : FileContextIndex) -> NormalizedContent {
  match self.normalized {
    Some(value) => value
    None => {
      let (text, offset_map) = @matching.normalize_content_for_matching(
        self.content,
      )
      let value : NormalizedContent = { text, offset_map, }
      self.normalized = Some(value)
      value
    }
  }
}

///|
fn FileContextIndex::line_starts(self : FileContextIndex) -> Array[Int32] {
  match self.line_starts {
    Some(starts) => starts
    None => {
      let starts = line_start_index(self.normalized().text)
      self.line_starts = Some(starts)
      starts
    }
  }
}

///|
/// Total logical line count derived in O(1) from the cached `line_starts`
/// index: a trailing `\n` produces one extra sentinel start at EOF.
fn line_count_from_starts(
  content : String,
  line_starts : Array[Int32],
) -> Int32 {
  if content == "" {
    0
  } else if content.has_suffix("\n") {
    line_starts.length() - 1
  } else {
    line_starts.length()
  }
}

///|
fn total_line_count(content : String) -> Int32 {
  if content == "" {
    return 0
  }
  let count = content.iter().count_if(ch => ch == '\n')
  if content.has_suffix("\n") {
    count
  } else {
    count + 1
  }
}

///|
fn line_start_index(content : String) -> Array[Int32] {
  let starts = [0]
  for index in 0..<content.length() {
    if content[index] == '\n' {
      starts.push(index + 1)
    }
  }
  starts
}

///|
fn line_text_at(
  content : String,
  line_starts : Array[Int32],
  line : Int32,
) -> String {
  guard line >= 1 && line <= line_starts.length() else { return "" }
  let start = line_starts[line - 1]
  let end = if line < line_starts.length() {
    line_starts[line]
  } else {
    content.length()
  }
  let text = content.unsafe_substring(start~, end~)
  if text.has_suffix("\n") {
    text.unsafe_substring(start=0, end=text.length() - 1)
  } else {
    text
  }
}

///|
fn display_context_line(text : String) -> String {
  if text.length() <= FailureLineDisplayCap {
    return text
  }
  "\{text[:FailureLineDisplayCap]}…"
}

///|
/// Context attachment state for an `EditFailure`:
/// - `NoContext`: failure kind does not attach file context (e.g. overlap, IO).
/// - `Context(String)`: rendered `─── file context ───` block.
/// - `Omitted`: context was skipped because the batch budget was already full.
priv enum FailureContext {
  NoContext
  Context(String)
  Omitted
}

///|
/// Batch-wide budget tracker used during validation so failures beyond the
/// display cap skip file indexing and context rendering altogether.
priv struct ContextBudget {
  mut shown : Int32
  mut chars : Int32
  mut exhausted : Bool
}

///|
fn ContextBudget::new() -> ContextBudget {
  { shown: 0, chars: 0, exhausted: false, }
}

///|
fn ContextBudget::can_accept(self : ContextBudget) -> Bool {
  !self.exhausted && self.shown < FailureContextSiteLimit
}

///|
fn ContextBudget::record(
  self : ContextBudget,
  rendered : String,
) -> FailureContext {
  if self.shown < FailureContextSiteLimit &&
    self.chars + rendered.length() <= FailureContextBudgetChars {
    self.shown += 1
    self.chars += rendered.length()
    Context(rendered)
  } else {
    self.exhausted = true
    Omitted
  }
}

///|
/// Build a bounded `─── file context ───` code block around a failed edit's
/// anchor (`start_line`..`end_line`). Uses LF-normalized content so CRLF files
/// render cleanly without trailing `\r`.
fn build_file_context(
  file_index : FileContextIndex,
  start_line : Int32,
  end_line : Int32?,
  old_string_lines : Int32,
) -> String {
  let content = file_index.normalized().text
  if content == "" {
    return "─── file context (file is empty) ───────────────"
  }
  let line_starts = file_index.line_starts()
  let total_lines = line_count_from_starts(content, line_starts)
  if start_line > total_lines {
    let tail_span = FailureContextLinesBefore + FailureContextLinesAfter + 1
    let first_line = (total_lines - tail_span + 1).max(1)
    let width = "\{total_lines}".length()
    let out = StringBuilder()
    out.write_string(
      "─── file context (file has \{total_lines} line(s); start_line \{start_line} is past EOF) ───\n```\n",
    )
    for line_no in first_line..<=total_lines {
      let number = "\{line_no}".pad_start(width, ' ')
      let text = display_context_line(
        line_text_at(content, line_starts, line_no),
      )
      out.write_string("   \{number} |\{text}\n")
    }
    out.write_string("```")
    return out.to_string()
  }
  let span_lines = old_string_lines.max(1)
  let focus_end = match end_line {
    Some(end) => end.min(total_lines)
    None => (start_line + span_lines - 1).min(total_lines)
  }
  let first_line = (start_line - FailureContextLinesBefore).max(1)
  let unclamped_last = (focus_end + FailureContextLinesAfter).min(total_lines)
  let display_last = unclamped_last.min(first_line + FailureContextMaxLines - 1)
  let omitted = unclamped_last - display_last
  let width = "\{display_last}".length()
  let out = StringBuilder()
  out.write_string(
    "─── file context ───────────────────────────────\n```\n",
  )
  for line_no in first_line..<=display_last {
    let gutter = if line_no >= start_line &&
      (end_line is None || line_no <= focus_end) {
      " >"
    } else {
      "  "
    }
    let number = "\{line_no}".pad_start(width, ' ')
    let text = display_context_line(line_text_at(content, line_starts, line_no))
    out.write_string("\{gutter} \{number} |\{text}\n")
  }
  if omitted > 0 {
    out.write_string("   ... (\{omitted} more line(s) omitted)\n")
  }
  out.write_string("```")
  out.to_string()
}

///|
priv struct MatchSpans {
  spans : Array[(Int32, Int32)]
  has_more : Bool
}

///|
/// Number of additional lines covered by `needle` beyond its starting line:
/// newlines strictly before the final code unit. A trailing `\n` stays on the
/// last matched line rather than spilling onto the next line.
fn needle_extra_lines(needle : String) -> Int32 {
  let limit = needle.length() - 1
  let mut extra = 0
  for i in 0..<limit {
    if needle[i] == '\n' {
      extra += 1
    }
  }
  extra
}

///|
/// Scan `haystack` in one linear pass for occurrences of `needle`, retaining
/// up to `MatchHintWindowEachSide` closest matches above and at/after
/// `start_line` so an out-of-range `old_string` can hint its actual line
/// number(s) in O(file) time and O(1) memory.
///
/// After matching on `first_line`, the scan advances to the start of the next
/// line (`first_line + 1`): every match starting on `first_line` has the same
/// `(first_line, first_line + extra_lines)` span, while advancing by one line
/// still discovers overlapping multiline matches starting on subsequent lines.
fn find_match_spans(
  haystack : String,
  needle : String,
  start_line : Int32,
) -> MatchSpans {
  guard needle.length() > 0 else { return { spans: [], has_more: false, } }
  let before : Array[(Int32, Int32)] = []
  let at_or_after : Array[(Int32, Int32)] = []
  let mut dropped_before = false
  let mut has_more_after = false
  let mut scan_offset = 0
  let mut scan_line = 1
  fn line_at(offset : Int32) -> Int32 {
    while scan_offset < offset {
      if haystack[scan_offset] == '\n' {
        scan_line += 1
      }
      scan_offset += 1
    }
    scan_line
  }

  let extra_lines = needle_extra_lines(needle)
  let needle_view = needle[:]
  let mut from = 0
  while from < haystack.length() &&
        haystack[from:].find(needle_view) is Some(found) {
    let offset = from + found
    let first_line = line_at(offset)
    let span = (first_line, first_line + extra_lines)
    if first_line < start_line {
      if before.length() == MatchHintWindowEachSide {
        // Keep the closest matches immediately above start_line.
        ignore(before.remove(0))
        dropped_before = true
      }
      before.push(span)
    } else if at_or_after.length() < MatchHintWindowEachSide {
      at_or_after.push(span)
    } else {
      has_more_after = true
      break
    }
    // Advance to the start of the line after `first_line`.
    let mut next_from = offset
    while next_from < haystack.length() && haystack[next_from] != '\n' {
      next_from += 1
    }
    from = if next_from < haystack.length() {
      next_from + 1
    } else {
      haystack.length()
    }
  }
  let combined : Array[(Int32, Int32)] = [..before, ..at_or_after]
  let truncated = combined.length() > MatchHintDisplayLimit
  let chosen = if truncated {
    let by_distance = combined.copy()
    by_distance.sort_by((a, b) => {
      let da = (a.0 - start_line).abs()
      let db = (b.0 - start_line).abs()
      (da, a.0, a.1).compare((db, b.0, b.1))
    })
    let top = [ for span in by_distance[:MatchHintDisplayLimit] => span ]
    top.sort_by((a, b) => a.compare(b))
    top
  } else {
    combined
  }
  { spans: chosen, has_more: dropped_before || has_more_after || truncated, }
}

///|
fn format_line_span(span : (Int32, Int32)) -> String {
  let (first, last) = span
  if first == last {
    "\{first}"
  } else {
    "\{first}-\{last}"
  }
}

///|
fn format_match_hint(kind : String, matches : MatchSpans) -> String? {
  guard !matches.spans.is_empty() else { return None }
  let labels = [ for span in matches.spans => format_line_span(span) ]
  let plural = matches.spans.length() > 1 ||
    matches.spans[0].0 != matches.spans[0].1
  let noun = if plural { "lines" } else { "line" }
  let more = if matches.has_more { " (and more)" } else { "" }
  Some("\{kind} found at \{noun} \{labels.join(", ")}\{more}")
}

///|
/// When `old_string` was not found in the requested range, search the full file
/// (exact first, then quote-normalized) to report where it actually appears.
fn find_other_match_hint(
  norm_content : String,
  norm_old : String,
  start_line : Int32,
) -> String? {
  let exact = find_match_spans(norm_content, norm_old, start_line)
  if format_match_hint("exact match", exact) is Some(hint) {
    return Some(hint)
  }
  let quote_content = @matching.normalize_quotes(norm_content)
  let quote_old = @matching.normalize_quotes(norm_old)
  if quote_content == norm_content && quote_old == norm_old {
    return None
  }
  let quoted = find_match_spans(quote_content, quote_old, start_line)
  format_match_hint("quote-normalized match", quoted)
}

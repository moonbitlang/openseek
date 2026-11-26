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
/// block, and total character budget across all context blocks in a batch.
const FailureContextSiteLimit : Int32 = 8

///|
const FailureContextBudgetChars : Int32 = 12_000

///|
/// How many nearby matches before and at/after `start_line` to retain when
/// hinting where an out-of-range `old_string` exists elsewhere in the file.
const MatchHintWindowEachSide : Int32 = 3

///|
/// Maximum total match locations listed in one `old_string not found` hint.
const MatchHintDisplayLimit : Int32 = 5

///|
/// Per-file normalized content and lazily computed line-start index shared
/// across all edits targeting the same file in a `multi_edit` batch.
priv struct FileContextIndex {
  norm_content : String
  offset_map : Array[Int32]
  mut line_starts : Array[Int32]?
}

///|
fn FileContextIndex::new(content : String) -> FileContextIndex {
  let (norm_content, offset_map) = @matching.normalize_content_for_matching(
    content,
  )
  { norm_content, offset_map, line_starts: None, }
}

///|
fn FileContextIndex::line_starts(self : FileContextIndex) -> Array[Int32] {
  match self.line_starts {
    Some(starts) => starts
    None => {
      let starts = line_start_index(self.norm_content)
      self.line_starts = Some(starts)
      starts
    }
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
/// Build a bounded `─── file context ───` code block around a failed edit's
/// anchor (`start_line`..`end_line`). Uses LF-normalized content so CRLF files
/// render cleanly without trailing `\r`.
fn build_file_context(
  file_index : FileContextIndex,
  start_line : Int32,
  end_line : Int32?,
  old_string_lines : Int32,
) -> String {
  let content = file_index.norm_content
  let total_lines = total_line_count(content)
  if total_lines == 0 {
    return "─── file context (file is empty) ───────────────"
  }
  let line_starts = file_index.line_starts()
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
/// Scan `haystack` in one linear pass for occurrences of `needle`, retaining
/// the closest matches above and at/after `start_line` so an out-of-range
/// `old_string` can hint its actual line number(s) in O(file) time and O(1)
/// memory.
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

  let needle_view = needle[:]
  let mut from = 0
  let mut last_recorded : (Int32, Int32)? = None
  while haystack[from:].find(needle_view) is Some(found) {
    let offset = from + found
    from = offset + needle.length()
    let first_line = line_at(offset)
    let last_line = line_at(offset + needle.length() - 1)
    let span = (first_line, last_line)
    if last_recorded is Some(prev) && prev == span {
      continue
    }
    last_recorded = Some(span)
    if first_line < start_line {
      if before.length() == MatchHintWindowEachSide {
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

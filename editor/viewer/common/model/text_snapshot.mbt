///|
/// Immutable LF-normalized text plus cached line starts, the readonly analog
/// of Monaco's text buffer: the field pair is the piece tree's leaf
/// (`StringBuffer { buffer, lineStarts }`, `pieceTreeBase.ts:147`) and the
/// 1-based methods are the `IReadonlyTextBuffer` read surface
/// (`model.ts:1524`). Offsets and columns are UTF-16 code units so browser,
/// Monaco, and LSP-facing code share one convention. Document identity
/// (language id, version) lives on `TextModel`, not the buffer — same split as
/// Monaco.
struct TextSnapshot {
  text : String
  line_starts : Array[Int]
} derive(Debug)

///|
/// Builds a snapshot by replacing every CRLF pair, lone CR, or LF with one LF
/// before deriving line starts. U+FEFF, U+2028/U+2029, surrogate code units,
/// and all other UTF-16 content are preserved verbatim.
pub fn TextSnapshot::TextSnapshot(text : String) -> TextSnapshot {
  let text = normalize_eol(text)
  let line_starts = build_line_starts(text)
  { text, line_starts }
}

///|
/// Snapshot length in the repo's JavaScript-compatible UTF-16 indexing model.
/// Mirrors `IReadonlyTextBuffer.getLength`.
fn TextSnapshot::get_length(self : TextSnapshot) -> Int {
  self.text.length()
}

///|
/// Number of logical lines, including the final empty line after a trailing
/// newline.
pub fn TextSnapshot::line_count(self : TextSnapshot) -> Int {
  self.line_starts.length()
}

///|
/// Start offset for `line`, clamped into the snapshot's line range.
fn TextSnapshot::line_start_offset(self : TextSnapshot, line : Int) -> Int {
  let line = line.clamp(min=0, max=self.line_count() - 1)
  self.line_starts[line]
}

///|
/// End offset for `line`, clamped into the snapshot's line range and excluding
/// the stored LF line break.
fn TextSnapshot::line_end_offset(self : TextSnapshot, line : Int) -> Int {
  let line = line.clamp(min=0, max=self.line_count() - 1)
  if line + 1 < self.line_count() {
    self.line_starts[line + 1] - 1
  } else {
    self.get_length()
  }
}

///|
/// Text of one logical line without its line break. Zero-based, part of the
/// offset-centric internal layer (see the README parity ledger); the
/// `IReadonlyTextBuffer` surface is `get_line_content`.
pub fn TextSnapshot::line_text(self : TextSnapshot, line : Int) -> String {
  let start = self.line_start_offset(line)
  let end = self.line_end_offset(line)
  code_unit_slice(self.text, start, end)
}

///|
/// Text of the one-based `line_number` without its line break, clamped into
/// the snapshot. Mirrors `IReadonlyTextBuffer.getLineContent` (the viewer
/// clamps where Monaco throws `Illegal value for lineNumber`).
pub fn TextSnapshot::get_line_content(
  self : TextSnapshot,
  line_number : Int,
) -> String {
  self.line_text(line_number - 1)
}

///|
/// Full stored document text. Construction has already normalized every line
/// ending to LF, so this is the direct fixed-LF `getValue()` result.
pub fn TextSnapshot::get_value(self : TextSnapshot) -> String {
  self.text
}

///|
/// Stored model end-of-line sequence. Viewer snapshots have one fixed LF EOL
/// and expose no TextDefined/CRLF preference.
fn TextSnapshot::get_eol(_self : TextSnapshot) -> String {
  "\n"
}

///|
/// Text inside a 1-based line/column `Range`, interior line breaks emitted as
/// `\n`. Mirrors Monaco's `getValueInRange` at its default LF EOL. Columns are
/// clamped into each line.
fn TextSnapshot::get_value_in_range(
  self : TextSnapshot,
  range : @base_common.Range,
) -> String {
  let start_line = (range.start_line_number - 1).clamp(
    min=0,
    max=self.line_count() - 1,
  )
  let end_line = (range.end_line_number - 1).clamp(
    min=0,
    max=self.line_count() - 1,
  )
  if start_line == end_line {
    let line = self.line_text(start_line)
    let a = (range.start_column - 1).clamp(min=0, max=line.length())
    let b = (range.end_column - 1).clamp(min=a, max=line.length())
    return code_unit_slice(line, a, b)
  }
  let sb = StringBuilder::new()
  let first = self.line_text(start_line)
  let a = (range.start_column - 1).clamp(min=0, max=first.length())
  sb.write_string(code_unit_slice(first, a, first.length()))
  for line in (start_line + 1)..<end_line {
    sb <+ "\n\{self.line_text(line)}"
  }
  let last = self.line_text(end_line)
  let b = (range.end_column - 1).clamp(min=0, max=last.length())
  sb <+ "\n\{code_unit_slice(last, 0, b)}"
  sb.to_string()
}

///|
/// Length, in UTF-16 code units, of `get_value_in_range`. Mirrors Monaco's
/// `getValueLengthInRange` at its default LF EOL.
fn TextSnapshot::get_value_length_in_range(
  self : TextSnapshot,
  range : @base_common.Range,
) -> Int {
  self.get_value_in_range(range).length()
}

///|
/// Whole-buffer equality — `PieceTreeTextBuffer.equals` behind
/// `TextModel.equalsTextBuffer` (`textModel.ts:457-459`). The source compares
/// its selected-EOL representation; the Viewer compares its coherent
/// LF-normalized representation, including U+FEFF as ordinary content. Hosts
/// use it for the refresh no-op early return (`modelService.ts:370-373`).
pub fn TextSnapshot::equals(self : TextSnapshot, other : TextSnapshot) -> Bool {
  self.text == other.text
}

///|
/// Returns a clamped half-open slice of the snapshot text.
pub fn TextSnapshot::slice(
  self : TextSnapshot,
  range : @base_common.OffsetRange,
) -> String {
  let start = range.start.clamp(min=0, max=self.get_length())
  let end = range.end_exclusive.clamp(min=start, max=self.get_length())
  code_unit_slice(self.text, start, end)
}

///|
/// Zero-based line containing `offset`, with out-of-range offsets clamped to
/// the snapshot.
fn TextSnapshot::line_at_offset(self : TextSnapshot, offset : Int) -> Int {
  let offset = offset.clamp(min=0, max=self.get_length())
  let mut found = 0
  for i in 0..<self.line_starts.length() {
    if self.line_starts[i] <= offset {
      found = i
    }
  }
  found
}

///|
/// Converts an offset to a one-based line/column `Position` (Monaco's
/// convention; this is the offset↔position boundary, so it adds the +1 on both
/// axes that keeps the rest of the viewer in 1-based coordinates). Mirrors
/// `IReadonlyTextBuffer.getPositionAt`.
fn TextSnapshot::get_position_at(
  self : TextSnapshot,
  offset : Int,
) -> @base_common.Position {
  let offset = offset.clamp(min=0, max=self.get_length())
  let line = self.line_at_offset(offset)
  { line_number: line + 1, column: offset - self.line_starts[line] + 1 }
}

///|
/// Converts an offset span to a line/column `Range` (the boundary helper for
/// code that carries `Range` but holds offsets, e.g. the hover widget).
pub fn TextSnapshot::range_of(
  self : TextSnapshot,
  offset_range : @base_common.OffsetRange,
) -> @base_common.Range {
  @base_common.Range::from_positions(
    self.get_position_at(offset_range.start),
    self.get_position_at(offset_range.end_exclusive),
  )
}

///|
/// Converts a line/column `Range` to an offset span (inverse of `range_of`).
pub fn TextSnapshot::offset_range_of(
  self : TextSnapshot,
  range : @base_common.Range,
) -> @base_common.OffsetRange {
  OffsetRange(
    self.get_offset_at(range.start_line_number, range.start_column),
    self.get_offset_at(range.end_line_number, range.end_column),
  )
}

///|
/// Converts a one-based line/column pair to a clamped document offset,
/// undoing the +1 this boundary added in `get_position_at`. Mirrors
/// `IReadonlyTextBuffer.getOffsetAt` (same arity; the `Position`-taking
/// form is `TextModel::get_offset_at`).
pub fn TextSnapshot::get_offset_at(
  self : TextSnapshot,
  line_number : Int,
  column : Int,
) -> Int {
  let line = (line_number - 1).clamp(min=0, max=self.line_count() - 1)
  let start = self.line_start_offset(line)
  let end = self.line_end_offset(line)
  (start + column - 1).clamp(min=start, max=end)
}

///|
/// Length, in UTF-16 code units, of `line`'s content (1-based, EOL excluded).
/// Mirrors `IReadonlyTextBuffer.getLineLength`.
fn TextSnapshot::get_line_length(self : TextSnapshot, line : Int) -> Int {
  self.line_text(line - 1).length()
}

///|
/// Max (1-based) column for `line`: content length + 1. Mirrors
/// `getLineMaxColumn`.
pub fn TextSnapshot::get_line_max_column(
  self : TextSnapshot,
  line : Int,
) -> Int {
  self.get_line_length(line) + 1
}

///|
/// Code unit at 0-based `index` of `line`. The content endpoint of a non-final
/// line is its LF. A true-empty or non-empty final-line endpoint keeps the
/// pinned source's terminal failure.
fn TextSnapshot::get_line_char_code(
  self : TextSnapshot,
  line : Int,
  index : Int,
) -> Int {
  let content = self.line_text(line - 1)
  if line >= 1 && line < self.line_count() && index == content.length() {
    return 10
  }
  content[index].to_int()
}

///|
/// 1-based column of the first non-whitespace character on `line`, or `0` if the
/// line is empty/whitespace-only. Mirrors `getLineFirstNonWhitespaceColumn`.
pub fn TextSnapshot::get_line_first_non_whitespace_column(
  self : TextSnapshot,
  line : Int,
) -> Int {
  let result = @base_common.first_non_whitespace_index(self.line_text(line - 1))
  if result == -1 {
    0
  } else {
    result + 1
  }
}

///|
/// 1-based column just past the last non-whitespace character on `line`, or `0`
/// if the line is empty/whitespace-only. Mirrors
/// `getLineLastNonWhitespaceColumn`.
fn TextSnapshot::get_line_last_non_whitespace_column(
  self : TextSnapshot,
  line : Int,
) -> Int {
  let result = @base_common.last_non_whitespace_index(self.line_text(line - 1))
  if result == -1 {
    0
  } else {
    result + 2
  }
}

///|
/// Replaces every CRLF pair or lone CR with one LF. Existing LF and all other
/// UTF-16 units are preserved. Raw code-unit substrings deliberately avoid the
/// Unicode-scalar boundary checks of `StringView`, so lone low/high surrogates
/// beside an EOL are retained exactly once on both JS and native targets.
fn normalize_eol(text : String) -> String {
  let len = text.length()
  let sb = StringBuilder::new()
  let mut segment_start = 0
  let mut i = 0
  let mut changed = false
  while i < len {
    if text[i].to_int() == 13 {
      changed = true
      if segment_start < i {
        sb.write_string(code_unit_slice(text, segment_start, i))
      }
      sb.write_string("\n")
      if i + 1 < len && text[i + 1].to_int() == 10 {
        i += 2
      } else {
        i += 1
      }
      segment_start = i
    } else {
      i += 1
    }
  }
  if !changed {
    return text
  }
  if segment_start < len {
    sb.write_string(code_unit_slice(text, segment_start, len))
  }
  sb.to_string()
}

///|
/// Copies the half-open UTF-16 code-unit interval without requiring Unicode
/// scalar boundaries. Bounds are validated/clamped by each caller. Monaco's
/// JavaScript `substring` likewise permits ranges that begin/end at either
/// half of a surrogate pair and returns the corresponding lone code unit.
fn code_unit_slice(text : String, start : Int, end : Int) -> String {
  text.unsafe_substring(start~, end~)
}

///|
/// Offsets where each line begins in the normalized stored text (0-based).
/// Construction has already reduced every source EOL to LF, so only LF can
/// create a start. The raw workspace `DocumentSnapshot` scanner intentionally
/// remains separate on the provider side of this boundary.
fn build_line_starts(text : String) -> Array[Int] {
  let starts = [0]
  for i in 0..<text.length() {
    if text[i].to_int() == 10 {
      starts.push(i + 1)
    }
  }
  starts
}

///|
#deprecated
pub extend TextSnapshot with Debug::{to_repr}

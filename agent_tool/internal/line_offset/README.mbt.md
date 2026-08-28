# agent_tool/internal/line_offset

Two functions that turn a 1-based line number into a code-unit offset in a
string. `edit` and `multi_edit` both anchor their searches to a line range, and
both need the same answer to "where does line N start, and where does it end?",
so the scan lives here rather than once per tool.

Nothing here reads a file. The input is content already in memory, and the
result is an offset into that same string — safe to hand straight to
`unsafe_substring`, because both functions clamp to the content's length.

## The contract

- **Lines are 1-based.** Line 1 starts at offset 0.
- **An end offset is *past* the newline.** `line_end_offset(c, n)` and
  `line_start_offset(c, n + 1)` name the same position, so an inclusive line
  range `[start, end]` is the half-open offset range
  `[line_start_offset(c, start), line_end_offset(c, end))`.
- **Out of range clamps, never fails.** A line past the end of the content —
  and a line number below 1 — yields an in-bounds offset.

```mbt check
///|
test "offsets bracket each line, end offsets landing past the newline" {
  let content = "alpha\nbeta\ngamma\n"
  inspect(@line_offset.line_start_offset(content, 1), content="0")
  inspect(@line_offset.line_end_offset(content, 1), content="6")
  // Line 2's start is line 1's end: an inclusive line range is a half-open
  // offset range.
  inspect(@line_offset.line_start_offset(content, 2), content="6")
  inspect(@line_offset.line_end_offset(content, 2), content="11")
  inspect(content.unsafe_substring(start=6, end=11), content="beta\n")
}

///|
test "a line with no trailing newline ends at the content's end" {
  let content = "alpha\nbeta"
  inspect(@line_offset.line_end_offset(content, 2), content="10")
  inspect(content.length(), content="10")
}
```

## Edges worth knowing

Every out-of-range question answers with an in-bounds offset, which is what
lets a caller clamp a decoded line range instead of rejecting it.

```mbt check
///|
test "out-of-range lines clamp to the ends of the content" {
  let content = "alpha\nbeta\n"
  // Past EOF: both ends land on the content's length, so the selected slice is
  // empty rather than invalid.
  inspect(@line_offset.line_start_offset(content, 99), content="11")
  inspect(@line_offset.line_end_offset(content, 99), content="11")
  // Below 1: line 0 and line -5 both start where line 1 does.
  inspect(@line_offset.line_start_offset(content, 0), content="0")
  inspect(@line_offset.line_start_offset(content, -5), content="0")
}

///|
test "empty content has one empty line" {
  inspect(@line_offset.line_start_offset("", 1), content="0")
  inspect(@line_offset.line_end_offset("", 1), content="0")
}
```

A `\r\n` line ending is *not* special-cased: the scan splits on `\n`, so the
`\r` belongs to the line it terminates and shows up inside the selected slice.

```mbt check
///|
test "CRLF keeps its carriage return inside the line" {
  let content = "alpha\r\nbeta\r\n"
  inspect(@line_offset.line_end_offset(content, 1), content="7")
  inspect(content.unsafe_substring(start=0, end=7), content="alpha\r\n")
}
```

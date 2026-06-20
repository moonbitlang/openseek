///|
priv struct SourceRange {
  first : Int
  last_exclusive : Int
}

///|
pub fn without_comments(markdown : String) -> String {
  let ranges = comment_ranges(markdown)
  guard !ranges.is_empty() else { markdown }
  ranges.sort_by(fn(left, right) { left.first.compare(right.first) })
  remove_source_ranges(markdown, ranges)
}

///|
fn comment_ranges(markdown : String) -> Array[SourceRange] {
  let ranges = []
  let doc = @cmark.Doc::from_string(locs=true, markdown)
  collect_block_comment_ranges(markdown, doc.block, ranges)
  ranges
}

///|
fn collect_block_comment_ranges(
  markdown : String,
  block : @cmark.Block,
  ranges : Array[SourceRange],
) -> Unit {
  match block {
    HtmlBlock(node) => push_html_block_ranges(markdown, ranges, node.v)
    Heading(node) => collect_inline_comment_ranges(node.v.inline, ranges)
    Paragraph(node) => collect_inline_comment_ranges(node.v.inline, ranges)
    BlockQuote(node) =>
      collect_block_comment_ranges(markdown, node.v.block, ranges)
    Blocks(node) =>
      for child in node.v.iter() {
        collect_block_comment_ranges(markdown, child, ranges)
      }
    List(node) =>
      for item in node.v.items.iter() {
        collect_block_comment_ranges(markdown, item.v.block, ranges)
      }
    ExtFootnoteDefinition(node) =>
      collect_block_comment_ranges(markdown, node.v.block, ranges)
    ExtTable(node) =>
      for row_entry in node.v.rows.iter() {
        let (row, _) = row_entry
        collect_table_row_comment_ranges(row.v, ranges)
      }
    BlankLine(_)
    | CodeBlock(_)
    | LinkRefDefinition(_)
    | ThematicBreak(_)
    | ExtMathBlock(_) => ()
  }
}

///|
fn collect_table_row_comment_ranges(
  row : @cmark.TableRow,
  ranges : Array[SourceRange],
) -> Unit {
  match row {
    Header(cells) | Data(cells) =>
      for cell in cells.iter() {
        let (inline, _) = cell
        collect_inline_comment_ranges(inline, ranges)
      }
    Sep(_) => ()
  }
}

///|
fn collect_inline_comment_ranges(
  inline : @cmark.Inline,
  ranges : Array[SourceRange],
) -> Unit {
  match inline {
    RawHtml(node) =>
      if inline_raw_html_is_comment(node.v) {
        push_loc_range(ranges, node.meta)
      }
    Inlines(node) =>
      for child in node.v.iter() {
        collect_inline_comment_ranges(child, ranges)
      }
    Image(node) | Link(node) =>
      collect_inline_comment_ranges(node.v.text, ranges)
    Emphasis(node) | StrongEmphasis(node) =>
      collect_inline_comment_ranges(node.v.inline, ranges)
    ExtStrikethrough(node) => collect_inline_comment_ranges(node.v.0, ranges)
    Autolink(_) | Break(_) | CodeSpan(_) | ExtMathSpan(_) | Text(_) => ()
  }
}

///|
fn push_html_block_ranges(
  markdown : String,
  ranges : Array[SourceRange],
  block : @cmark.HtmlBlock,
) -> Unit {
  guard block.0.get(0) is Some(first_line) else { return }
  guard block.0.get(block.0.length() - 1) is Some(last_line) else { return }
  let first_loc = first_line.meta.loc
  let last_loc = last_line.meta.loc
  if first_loc.is_none() ||
    first_loc.is_empty() ||
    last_loc.is_none() ||
    last_loc.is_empty() {
    return
  }
  let len = markdown.length()
  let start = line_start(markdown, clamp(first_loc.first_ccode, min=0, max=len))
  let stop = clamp(last_loc.last_ccode + 1, min=start, max=len)
  push_html_comment_ranges(markdown, ranges, start~, stop~)
}

///|
fn inline_raw_html_is_comment(raw : @cmark.InlineRawHtml) -> Bool {
  let text = StringBuilder()
  for tight in raw.0.iter() {
    text.write_string(tight.to_string())
  }
  is_html_comment(text.to_string())
}

///|
fn is_html_comment(text : StringView) -> Bool {
  text.trim_start().has_prefix("<!--")
}

///|
fn push_loc_range(ranges : Array[SourceRange], meta : @cmark_base.Meta) -> Unit {
  let loc = meta.loc
  if loc.is_none() || loc.is_empty() {
    return
  }
  ranges.push({ first: loc.first_ccode, last_exclusive: loc.last_ccode + 1 })
}

///|
fn push_html_comment_ranges(
  markdown : String,
  ranges : Array[SourceRange],
  start~ : Int,
  stop~ : Int,
) -> Unit {
  let len = markdown.length()
  let stop = clamp(stop, min=0, max=len)
  let mut cursor = clamp(start, min=0, max=stop)
  while cursor < stop {
    match find_html_comment_open(markdown, start=cursor, stop~) {
      Some(first) =>
        match find_html_comment_close(markdown, start=first + 4, stop~) {
          Some(last_exclusive) => {
            ranges.push({ first, last_exclusive })
            cursor = last_exclusive
          }
          None => break
        }
      None => break
    }
  }
}

///|
fn find_html_comment_open(markdown : String, start~ : Int, stop~ : Int) -> Int? {
  let stop = clamp(stop, min=0, max=markdown.length())
  let start = clamp(start, min=0, max=stop)
  for cursor = start; cursor + 3 < stop; cursor = cursor + 1 {
    if markdown[cursor] == '<' &&
      markdown[cursor + 1] == '!' &&
      markdown[cursor + 2] == '-' &&
      markdown[cursor + 3] == '-' {
      break Some(cursor)
    }
  } nobreak {
    None
  }
}

///|
fn find_html_comment_close(
  markdown : String,
  start~ : Int,
  stop~ : Int,
) -> Int? {
  let stop = clamp(stop, min=0, max=markdown.length())
  let start = clamp(start, min=0, max=stop)
  for cursor = start; cursor + 2 < stop; cursor = cursor + 1 {
    if markdown[cursor] == '-' &&
      markdown[cursor + 1] == '-' &&
      markdown[cursor + 2] == '>' {
      break Some(cursor + 3)
    }
  } nobreak {
    None
  }
}

///|
fn line_start(markdown : String, offset : Int) -> Int {
  for cursor = offset; cursor > 0; {
    if markdown[cursor - 1] == '\n' || markdown[cursor - 1] == '\r' {
      break cursor
    }
    continue cursor - 1
  } nobreak {
    cursor
  }
}

///|
fn remove_source_ranges(
  markdown : String,
  ranges : Array[SourceRange],
) -> String {
  let len = markdown.length()
  let out = StringBuilder(size_hint=len)
  let mut cursor = 0
  for range in ranges {
    let first = clamp(range.first, min=0, max=len)
    let last_exclusive = clamp(range.last_exclusive, min=0, max=len)
    if last_exclusive <= cursor {
      continue
    }
    if first > cursor {
      out.write_string(markdown.unsafe_substring(start=cursor, end=first))
    }
    cursor = last_exclusive
  }
  if cursor < len {
    out.write_string(markdown.unsafe_substring(start=cursor, end=len))
  }
  out.to_string()
}

///|
fn clamp(value : Int, min~ : Int, max~ : Int) -> Int {
  if value < min {
    min
  } else if value > max {
    max
  } else {
    value
  }
}

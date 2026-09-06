///|
/// Detects configuration-backed whole-line Markdown comments in `snapshot`.
/// The scan is deterministic, line-first, and linear in the snapshot text.
fn detect_markdown_comments_in_snapshot(
  snapshot : @model.TextSnapshot,
  rule : @languages.CommentRule,
) -> Array[@language.MarkdownCommentBlock] {
  let result : Array[@language.MarkdownCommentBlock] = []
  let line_count = snapshot.line_count()
  let mut line_index = 0
  while line_index < line_count {
    // Line comments deliberately take precedence when configured delimiters
    // overlap. A whole consecutive run is consumed by this branch.
    if rule.line_comment is Some(line_rule) &&
      line_comment_content(
        snapshot.get_line_content(line_index + 1),
        line_rule.comment,
      )
      is Some(first_content) {
      let contents = [first_content]
      let start_line_number = line_index + 1
      line_index += 1
      while line_index < line_count {
        guard line_comment_content(
            snapshot.get_line_content(line_index + 1),
            line_rule.comment,
          )
          is Some(content) else {
          break
        }
        contents.push(content)
        line_index += 1
      }
      result.push({
        line_range: LineRange(start_line_number, line_index + 1),
        markdown: contents.join("\n"),
      })
      continue
    }
    if rule.block_comment is Some(pair) {
      let first_line = snapshot.get_line_content(line_index + 1)
      let opening_offset = leading_indent_end(first_line)
      if matches_at(first_line, opening_offset, pair.open) {
        let start_line_index = line_index
        let after_open = opening_offset + pair.open.length()
        let mut closing_line_index = line_index
        let mut closing_offset = -1
        while closing_line_index < line_count {
          let line = snapshot.get_line_content(closing_line_index + 1)
          let search_start = if closing_line_index == start_line_index {
            after_open
          } else {
            0
          }
          closing_offset = find_from(line, pair.close, search_start)
          if closing_offset >= 0 {
            break
          }
          closing_line_index += 1
        }
        if closing_line_index == line_count {
          // The unmatched opening delimiter owns the remaining source as a
          // block comment, but cannot produce a renderable whole-line block.
          line_index = line_count
          continue
        }
        let closing_line = snapshot.get_line_content(closing_line_index + 1)
        let closes_at_boundary = closing_offset + pair.close.length() ==
          trailing_content_end(closing_line)
        if closes_at_boundary {
          let body_lines : Array[String] = []
          if start_line_index == closing_line_index {
            body_lines.push(slice(first_line, after_open, closing_offset))
          } else {
            body_lines.push(slice(first_line, after_open, first_line.length()))
            let mut interior_line = start_line_index + 1
            while interior_line < closing_line_index {
              body_lines.push(snapshot.get_line_content(interior_line + 1))
              interior_line += 1
            }
            body_lines.push(slice(closing_line, 0, closing_offset))
          }
          result.push({
            line_range: LineRange(start_line_index + 1, closing_line_index + 2),
            markdown: normalize_block_body(body_lines),
          })
        }
        // The first closing delimiter ends the language block even when
        // trailing source makes the whole-line candidate invalid.
        line_index = closing_line_index + 1
        continue
      }
    }
    line_index += 1
  }
  result
}

///|
/// The normalized blocks plus the explicit presentation capability captured
/// from the same winning provider registration. Configuration-backed detection
/// is never foldable.
pub struct ResolvedMarkdownCommentBlocks {
  blocks : Array[@language.MarkdownCommentBlock]
  foldable : Bool
}

///|
pub fn resolve_markdown_comment_blocks_with_presentation(
  model : @model.TextModel,
  languages : @languages.LanguageHandle,
  log_service : @log.LogHandle,
) -> ResolvedMarkdownCommentBlocks {
  let snapshot = model.snapshot()
  let (raw_blocks, foldable) = match
    languages.markdown_comment_provider_render_result(model) {
    Some(provider_result) => (provider_result.blocks, provider_result.foldable)
    None => {
      let configuration = languages.get_language_configuration(
        model.get_language_id(),
      )
      match configuration.comments {
        Some(rule) =>
          (detect_markdown_comments_in_snapshot(snapshot, rule), false)
        None => ([], false)
      }
    }
  }
  {
    blocks: normalize_markdown_comment_blocks(
      raw_blocks,
      snapshot.line_count(),
      log_service,
    ),
    foldable,
  }
}

///|
/// Normalizes raw detector or provider blocks against `model_line_count`.
/// Ranges are 1-based and half-open. Invalid ranges and later overlaps are
/// dropped with warning-level diagnostics; touching ranges remain distinct.
fn normalize_markdown_comment_blocks(
  blocks : Array[@language.MarkdownCommentBlock],
  model_line_count : Int,
  log_service : @log.LogHandle,
) -> Array[@language.MarkdownCommentBlock] {
  let indexed : Array[IndexedBlock] = []
  for index, block in blocks {
    let range = block.line_range
    if range.start_line_number < 1 ||
      range.end_line_number_exclusive <= range.start_line_number ||
      range.end_line_number_exclusive > model_line_count + 1 {
      warn_invalid_range(log_service, range)
    } else {
      indexed.push({ block, original_index: index, })
    }
  }
  indexed.sort_by((left, right) => {
    let left_range = left.block.line_range
    let right_range = right.block.line_range
    if left_range.start_line_number != right_range.start_line_number {
      left_range.start_line_number - right_range.start_line_number
    } else if left_range.end_line_number_exclusive !=
      right_range.end_line_number_exclusive {
      left_range.end_line_number_exclusive -
      right_range.end_line_number_exclusive
    } else {
      left.original_index - right.original_index
    }
  })
  let non_overlapping : Array[@language.MarkdownCommentBlock] = []
  for entry in indexed {
    let block = entry.block
    if non_overlapping is [.., previous] &&
      block.line_range.start_line_number <
      previous.line_range.end_line_number_exclusive {
      warn_overlap(log_service, previous.line_range, block.line_range)
    } else {
      non_overlapping.push(block)
    }
  }
  let normalized = non_overlapping.filter(block => block.markdown != "")
  let covered_line_count = for block in normalized; covered_line_count = 0 {
    continue covered_line_count + block.line_range.length()
  } nobreak {
    covered_line_count
  }
  if model_line_count > 0 && covered_line_count == model_line_count {
    []
  } else {
    normalized
  }
}

///|
priv struct IndexedBlock {
  block : @language.MarkdownCommentBlock
  original_index : Int
}

///|
fn line_comment_content(line : String, delimiter : String) -> String? {
  let offset = leading_indent_end(line)
  if !matches_at(line, offset, delimiter) {
    return None
  }
  let mut content_start = offset + delimiter.length()
  if content_start < line.length() && line[content_start].to_int() == 32 {
    content_start += 1
  }
  Some(slice(line, content_start, line.length()))
}

///|
fn normalize_block_body(lines : Array[String]) -> String {
  let common_indent = for line in lines; common_indent = -1 {
    // Boundary/doc-comment lines such as the extra `*` in `/**` and
    // conventional ` *` blank lines carry no Markdown content. They must not
    // force the shared source indentation down to zero before mixed starred
    // and unstarred content is dedented.
    if trailing_content_end(strip_interior_star(line)) > 0 {
      let indent = leading_indent_end(line)
      continue if common_indent < 0 || indent < common_indent {
          indent
        } else {
          common_indent
        }
    }
    continue common_indent
  } nobreak {
    common_indent.max(0)
  }
  let normalized : Array[String] = []
  for line in lines {
    let indent = leading_indent_end(line)
    if indent == line.length() {
      normalized.push("")
      continue
    }
    let dedented = slice(line, common_indent.min(indent), line.length())
    normalized.push(strip_interior_star(dedented))
  }
  normalized.join("\n")
}

///|
fn strip_interior_star(line : String) -> String {
  let star_offset = leading_indent_end(line)
  if star_offset >= line.length() || line[star_offset].to_int() != 42 {
    return line
  }
  let after_star = star_offset + 1
  if after_star < line.length() && line[after_star].to_int() != 32 {
    return line
  }
  let content_start = if after_star < line.length() {
    after_star + 1
  } else {
    after_star
  }
  slice(line, content_start, line.length())
}

///|
fn leading_indent_end(text : String) -> Int {
  let mut offset = 0
  while offset < text.length() {
    let code = text[offset].to_int()
    if code != 32 && code != 9 {
      break
    }
    offset += 1
  }
  offset
}

///|
fn trailing_content_end(text : String) -> Int {
  let mut offset = text.length()
  while offset > 0 {
    let code = text[offset - 1].to_int()
    if code != 32 && code != 9 {
      break
    }
    offset -= 1
  }
  offset
}

///|
fn matches_at(text : String, offset : Int, candidate : String) -> Bool {
  if candidate == "" ||
    offset < 0 ||
    offset + candidate.length() > text.length() {
    return false
  }
  for index in 0..<candidate.length() {
    if text[offset + index] != candidate[index] {
      return false
    }
  }
  true
}

///|
fn find_from(text : String, candidate : String, start : Int) -> Int {
  if candidate == "" {
    return -1
  }
  let last_start = text.length() - candidate.length()
  let mut offset = start.max(0)
  while offset <= last_start {
    if matches_at(text, offset, candidate) {
      return offset
    }
    offset += 1
  }
  -1
}

///|
fn slice(text : String, start : Int, end : Int) -> String {
  text.unsafe_substring(start~, end~)
}

///|
fn warn_invalid_range(
  log_service : @log.LogHandle,
  range : @base_common.LineRange,
) -> Unit {
  log_service.warn(
    "viewer.markdownComments",
    "discarded Markdown comment block with invalid line range",
    details=[
      ("startLineNumber", range.start_line_number.to_string()),
      ("endLineNumberExclusive", range.end_line_number_exclusive.to_string()),
    ],
  )
}

///|
fn warn_overlap(
  log_service : @log.LogHandle,
  kept : @base_common.LineRange,
  discarded : @base_common.LineRange,
) -> Unit {
  log_service.warn(
    "viewer.markdownComments",
    "discarded overlapping Markdown comment block",
    details=[
      ("keptRange", kept.to_string()),
      ("discardedRange", discarded.to_string()),
    ],
  )
}

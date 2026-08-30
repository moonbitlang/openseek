///|
fn projection_block(source : String, index : Int) -> MarkdownCodeBlock {
  render_markdown(source).projection.code_blocks[index]
}

///|
fn projection_source_offset(source : String, needle : String) -> Int {
  source.find(needle).unwrap()
}

///|
fn assert_projection_range(
  actual : @common.OffsetRange,
  start : Int,
  end_exclusive : Int,
) -> Unit raise {
  assert_eq(actual.start, start)
  assert_eq(actual.end_exclusive, end_exclusive)
}

///|
fn semantic_boundaries(line : MarkdownCodeLine) -> Array[Int?] {
  line.displayed_boundary_to_source_offset
}

///|
test "projection keeps zero and identical code blocks distinct with full fence info" {
  assert_eq(render_markdown("plain").projection.code_blocks.length(), 0)
  let source =
    #|# Title
    #|
    #|```mbt  check extra
    #|same()
    #|```
    #|
    #|```mbt check
    #|same()
    #|```
  let projection = render_markdown(source).projection
  assert_eq(projection.code_blocks.length(), 2)
  let first = projection.code_blocks[0]
  let second = projection.code_blocks[1]
  assert_eq(first.block_index, 0)
  assert_eq(second.block_index, 1)
  assert_eq(first.code, "same()\n")
  assert_eq(first.code, second.code)
  assert_false(first.block_source_range.equals(second.block_source_range))
  assert_eq(first.language_id, Some("mbt"))
  assert_eq(first.full_info_string, Some("mbt  check extra"))
  assert_eq(first.info_remainder, Some("check extra"))
  assert_eq(first.code_lines.length(), 1)
  assert_eq(first.code_lines[0].displayed_text, "same()")
  assert_eq(first.code_lines[0].source_line_number, 4)
  let snapshot = @model.TextSnapshot(source)
  assert_eq(snapshot.slice(first.code_lines[0].source_range), "same()")
}

///|
test "root-element ordinals ignore omitted blocks and nested anchors" {
  let source =
    #|first
    #|
    #|<script>unsafe</script>
    #|
    #|[ref]: /target
    #|
    #|---
    #|
    #|> quoted
    #|
    #|```mbt
    #|x
    #|```
  let rendered = render_markdown(source)
  assert_true(rendered.html.contains("CommonMark HTML block omitted"))
  let ordinals : Array[Int] = []
  let mut nested_anchor_count = 0
  for anchor in rendered.projection.block_anchors {
    match anchor.rendered_element_index {
      Some(index) => ordinals.push(index)
      None => nested_anchor_count += 1
    }
  }
  assert_eq(ordinals, [0, 1, 2, 3])
  assert_true(nested_anchor_count >= 2)
  let code_block = rendered.projection.code_blocks[0]
  let code_element_index = for
    anchor in rendered.projection.block_anchors
    code_element_index = (None : Int?) {
    if anchor.source_range.equals(code_block.block_source_range) {
      continue anchor.rendered_element_index
    }
    continue code_element_index
  } nobreak {
    code_element_index
  }
  assert_eq(code_element_index, Some(3))
}

///|
test "UTF-16 boundaries round trip through astral code units before and inside a block" {
  let source =
    #|before 😊
    #|```mbt check
    #|let 😊x = 1
    #|```
  let block = projection_block(source, 0)
  assert_eq(
    block.block_source_range.start,
    projection_source_offset(source, "```"),
  )
  let line = block.code_lines[0]
  let source_start = projection_source_offset(source, "let ")
  assert_projection_range(
    line.source_range,
    source_start,
    source_start + "let 😊x = 1".length(),
  )
  for boundary in 0..<=line.displayed_text.length() {
    assert_eq(
      line.source_offset_at_displayed_boundary(boundary),
      Some(source_start + boundary),
    )
    assert_eq(
      line.displayed_boundary_at_source_offset(source_start + boundary),
      Some(boundary),
    )
  }
  // Boundary 5 is between the two UTF-16 code units of the astral scalar.
  assert_eq(line.source_offset_at_displayed_boundary(5), Some(source_start + 5))
}

///|
test "isolated high and low surrogate units keep exact source boundary offsets" {
  for code_unit in [0xD800, 0xDFFF] {
    let lone = Int::unsafe_to_char(code_unit).to_string()
    let source =
      $|\{lone}
      $|```mbt check
      $|\{lone}x
      $|```
    let parser_input = markdown_cmark_input(source)
    assert_eq(parser_input.length(), source.length())
    assert_eq(parser_input[0].to_int(), 0xFFFD)
    let block = projection_block(source, 0)
    assert_eq(block.block_source_range.start, lone.length() + 1)
    let line = block.code_lines[0]
    let source_start = (
      $|\{lone}
      $|```mbt check
      $|
    ).length()
    assert_eq(line.displayed_text.length(), 2)
    assert_eq(
      line.displayed_text,
      "\{Int::unsafe_to_char(0xFFFD).to_string()}x",
    )
    assert_eq(semantic_boundaries(line), [
      Some(source_start),
      Some(source_start + 1),
      Some(source_start + 2),
    ])
  }
}

///|
test "blank code lines empty blocks and unclosed fences retain source facts" {
  let blank_source =
    #|```mbt check
    #|
    #|x
    #|
    #|
    #|```
  let blank_block = projection_block(blank_source, 0)
  assert_eq(
    blank_block.code,
    (
      #|
      #|x
      #|
      #|
    ),
  )
  assert_eq(blank_block.code_lines.length(), 3)
  assert_eq(blank_block.code_lines[0].displayed_text, "")
  assert_eq(blank_block.code_lines[1].displayed_text, "x")
  assert_eq(blank_block.code_lines[2].displayed_text, "")
  assert_eq(
    blank_block.code_lines[0].source_offset_at_displayed_boundary(0),
    Some(
      projection_source_offset(
        blank_source,
        (
          #|
          #|
          #|
        ),
      ) +
      1,
    ),
  )

  let empty = projection_block("```mbt check\n```", 0)
  assert_eq(empty.code, "")
  assert_eq(empty.code_lines.length(), 0)

  let unclosed_source =
    #|```mbt check
    #|
    #|x
    #|
    #|
    #|
  let unclosed = projection_block(unclosed_source, 0)
  assert_eq(
    unclosed.code,
    (
      #|
      #|x
      #|
      #|
      #|
    ),
  )
  assert_eq(unclosed.code_lines.length(), 4)
  assert_eq(unclosed.code_lines[3].displayed_text, "")
  assert_eq(
    unclosed.block_source_range.end_exclusive,
    unclosed.code_lines[3].source_range.end_exclusive,
  )
}

///|
test "blockquote and list fences map only original code text" {
  let source =
    #|> ```mbt check
    #|> quote
    #|> ```
    #|
    #|- item
    #|  ```moonbit check
    #|  list
    #|  ```
  let projection = render_markdown(source).projection
  assert_eq(projection.code_blocks.length(), 2)
  let quote = projection.code_blocks[0].code_lines[0]
  let list = projection.code_blocks[1].code_lines[0]
  assert_eq(quote.displayed_text, "quote")
  assert_eq(list.displayed_text, "list")
  assert_eq(quote.source_range.start, projection_source_offset(source, "quote"))
  assert_eq(list.source_range.start, projection_source_offset(source, "list"))
  assert_eq(
    quote.source_offset_at_displayed_boundary(0),
    Some(quote.source_range.start),
  )
  assert_eq(
    list.source_offset_at_displayed_boundary(0),
    Some(list.source_range.start),
  )
}

///|
test "partially consumed tab padding is displayed but non-semantic" {
  let source = "- foo\n\n\t\tbar"
  let block = projection_block(source, 0)
  assert_eq(block.code, "  bar\n")
  let line = block.code_lines[0]
  let bar = projection_source_offset(source, "bar")
  assert_eq(line.displayed_text, "  bar")
  assert_projection_range(line.source_range, bar, bar + 3)
  assert_eq(semantic_boundaries(line), [
    None,
    None,
    Some(bar),
    Some(bar + 1),
    Some(bar + 2),
    Some(bar + 3),
  ])
  assert_eq(line.source_offset_at_displayed_boundary(0), None)
  assert_eq(line.source_offset_at_displayed_boundary(1), None)
}

///|
test "literal tab content and uneven space-indented fences map exact source units" {
  let tab_source = "```mbt check\n\tvalue\n```"
  let tab_line = projection_block(tab_source, 0).code_lines[0]
  let tab_start = projection_source_offset(tab_source, "\tvalue")
  assert_eq(tab_line.displayed_text, "\tvalue")
  assert_projection_range(tab_line.source_range, tab_start, tab_start + 6)
  for boundary in 0..<=tab_line.displayed_text.length() {
    assert_eq(
      tab_line.source_offset_at_displayed_boundary(boundary),
      Some(tab_start + boundary),
    )
  }

  let uneven_source =
    #|  ```mbt check
    #| value
    #|  ```
  let uneven_line = projection_block(uneven_source, 0).code_lines[0]
  let value_start = projection_source_offset(uneven_source, "value")
  assert_eq(uneven_line.displayed_text, "value")
  assert_projection_range(
    uneven_line.source_range,
    value_start,
    value_start + 5,
  )
  assert_eq(semantic_boundaries(uneven_line), [
    Some(value_start),
    Some(value_start + 1),
    Some(value_start + 2),
    Some(value_start + 3),
    Some(value_start + 4),
    Some(value_start + 5),
  ])
}

///|
test "source ranges project inside across lines and outside the code block" {
  let source =
    #|before
    #|```mbt check
    #|abc
    #|def
    #|```
    #|after
  let block = projection_block(source, 0)
  let abc = projection_source_offset(source, "abc")
  let def = projection_source_offset(source, "def")

  let inside = block.project_source_range(
    @common.OffsetRange::from_to(abc + 1, abc + 3),
  )
  assert_eq(inside.length(), 1)
  assert_eq(inside[0].line_index, 0)
  assert_projection_range(inside[0].displayed_range, 1, 3)

  let crossing = block.project_source_range(
    @common.OffsetRange::from_to(abc + 2, def + 2),
  )
  assert_eq(crossing.length(), 2)
  assert_eq(crossing[0].line_index, 0)
  assert_projection_range(crossing[0].displayed_range, 2, 3)
  assert_eq(crossing[1].line_index, 1)
  assert_projection_range(crossing[1].displayed_range, 0, 2)

  let outside = block.project_source_range(
    @common.OffsetRange::from_to(0, source.length()),
  )
  assert_eq(outside.length(), 2)
  assert_projection_range(outside[0].displayed_range, 0, 3)
  assert_projection_range(outside[1].displayed_range, 0, 3)

  let newline_only = block.project_source_range(
    @common.OffsetRange::from_to(abc + 3, def),
  )
  assert_eq(newline_only.length(), 0)
}

///|
test "first EOL and block-end boundaries obey half-open mapping" {
  let source =
    #|```mbt check
    #|abc
    #|```
  let block = projection_block(source, 0)
  let line = block.code_lines[0]
  let abc = projection_source_offset(source, "abc")
  let first = block.project_source_range(@common.OffsetRange::empty_at(abc))
  assert_eq(first.length(), 1)
  assert_projection_range(first[0].displayed_range, 0, 0)
  let eol = block.project_source_range(@common.OffsetRange::empty_at(abc + 3))
  assert_eq(eol.length(), 1)
  assert_projection_range(eol[0].displayed_range, 3, 3)
  assert_eq(
    block
    .project_source_range(
      @common.OffsetRange::empty_at(block.block_source_range.end_exclusive),
    )
    .length(),
    0,
  )
  assert_eq(line.source_offset_at_displayed_boundary(-1), None)
  assert_eq(line.source_offset_at_displayed_boundary(4), None)
}

///|
test "unrepresentable displayed-source relationships keep static text and disable mapping" {
  let source_range = @common.OffsetRange::from_to(10, 13)
  let non_space_padding = markdown_code_line_from_source_facts(
    "xabc", 2, source_range,
  )
  assert_eq(non_space_padding.displayed_text, "xabc")
  assert_eq(semantic_boundaries(non_space_padding), [
    None,
    None,
    None,
    None,
    None,
  ])
  assert_eq(non_space_padding.project_source_range(source_range), None)

  let shorter = markdown_code_line_from_source_facts("ab", 2, source_range)
  assert_eq(shorter.displayed_text, "ab")
  assert_eq(semantic_boundaries(shorter), [None, None, None])
}

///|
test "TextSnapshot normalization gives CRLF lone-CR and LF one projection space" {
  let lf =
    #|before
    #|```mbt check
    #|one
    #|two
    #|```
  let mixed = "before\r\n```mbt check\rone\r\ntwo\r```"
  let normalized = @model.TextSnapshot(mixed).get_value()
  assert_eq(normalized, lf)
  assert_eq(
    render_markdown(normalized).projection,
    render_markdown(lf).projection,
  )
  assert_false(normalized.contains("\r"))
}

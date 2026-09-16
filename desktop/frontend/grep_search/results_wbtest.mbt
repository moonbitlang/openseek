///|
test "clipped previews preserve UTF-16 navigation and occurrence counts" {
  let raw : @protocol.TextSearchMatch = {
    path: "src/main.mbt",
    line_number: 7,
    preview: "😀 moon moon",
    preview_start_column: 9,
    ranges: [
      { start_column: 12, end_column: 16, },
      { start_column: 17, end_column: 21, },
      { start_column: 40, end_column: 44, },
    ],
  }
  guard SearchResultItem::from_text(raw) is Some(item) else {
    fail("expected a navigable search result")
  }
  assert_eq(item.target, Range(7, 12, 7, 16))
  assert_eq(item.ranges.length(), 3)
  assert_eq(item.preview[0].highlight_slices(item.ranges), [(3, 7), (8, 12)])
  let groups = visible_file_groups([item, item], 1)
  assert_eq(groups.length(), 1)
  assert_eq(groups[0].matches.length(), 1)
  assert_eq(groups[0].count, 6)
}

///|
test "structural previews highlight only the matched multiline extent" {
  let raw : @protocol.SemanticSearchHit = {
    path: "src/main.mbt",
    rule_id: "example",
    description: Some("Match the whole call"),
    start_line: 3,
    start_column: 3,
    end_line: 5,
    end_column: 1,
    matched_source: "inspect(\n  😀\n",
    source_context: [
      { line: 2, text: "before", is_match: false, },
      { line: 3, text: "  inspect(", is_match: true, },
      { line: 4, text: "  😀", is_match: true, },
      { line: 5, text: "after", is_match: true, },
    ],
  }
  let item = SearchResultItem::from_semantic(raw)
  assert_eq(item.target, Range(3, 3, 5, 1))
  assert_eq(item.preview.map(line => line.highlight_slices(item.ranges)), [
    [],
    [(2, 10)],
    [(0, 4)],
    [],
  ])
  let without_context = SearchResultItem::from_semantic({
    ..raw,
    source_context: [],
  })
  assert_eq(without_context.preview[0].start_column, 3)
  assert_eq(
    without_context.preview.map(line => line.highlight_slices(item.ranges)),
    [[(0, 8)], [(0, 4)], []],
  )
}

///|
test "shared results merge neighboring contexts without losing counts or destinations" {
  let hit : @protocol.SemanticSearchHit = {
    path: "src/main.mbt",
    rule_id: "inspect($_)",
    description: None,
    start_line: 3,
    start_column: 3,
    end_line: 3,
    end_column: 13,
    matched_source: "inspect(1)",
    source_context: [
      { line: 2, text: "fn main {", is_match: false, },
      { line: 3, text: "  inspect(1)", is_match: true, },
      { line: 4, text: "  inspect(2)", is_match: false, },
    ],
  }
  let first = SearchResultItem::from_semantic(hit)
  let second = SearchResultItem::from_semantic({
    ..hit,
    start_line: 4,
    end_line: 4,
    matched_source: "inspect(2)",
    source_context: [
      { line: 3, text: "  inspect(1)", is_match: false, },
      { line: 4, text: "  inspect(2)", is_match: true, },
      { line: 5, text: "}", is_match: false, },
    ],
  })
  // Text and AST adapters both enter the same aggregation API.
  let text : @protocol.TextSearchMatch = {
    path: hit.path,
    line_number: 6,
    preview: "inspect(3)",
    preview_start_column: 1,
    ranges: [{ start_column: 1, end_column: 11, }],
  }
  guard SearchResultItem::from_text(text) is Some(adjacent) else {
    fail("expected text result")
  }
  let distant = {
    ..adjacent,
    preview: [{ line: 20, text: "inspect(3)", start_column: 1, }],
    target: Range(20, 1, 20, 11),
    ranges: [Range(20, 1, 20, 11)],
  }
  let other_file = { ..first, path: "src/other.mbt", }
  let groups = visible_file_groups(
    [second, other_file, distant, first, adjacent],
    5,
  )
  assert_eq(groups.map(group => group.count), [4, 1])
  assert_eq(groups.map(group => group.matches.length()), [2, 1])
  let merged = groups[0].matches[0]
  assert_eq(merged.preview.map(line => line.line), [2, 3, 4, 5, 6])
  assert_eq(merged.ranges.length(), 3)
  assert_eq(merged.preview[1].highlight_slices(merged.ranges), [(2, 12)])
  assert_eq(merged.preview[2].highlight_slices(merged.ranges), [(2, 12)])
  assert_eq(merged.target_for_line(3), first.target)
  assert_eq(merged.target_for_line(4), second.target)
  assert_eq(merged.target_for_line(5), second.target)
  assert_eq(merged.target_for_line(6), adjacent.target)
  let limited = visible_file_groups([first, second, distant], 2)
  assert_eq(limited[0].count, 3)
  assert_eq(limited[0].matches.length(), 1)
  assert_eq(limited[0].matches[0].preview.map(line => line.line), [2, 3, 4, 5])
}

///|
test "merged fallback fragments retain UTF-16 source offsets and overlapping highlights" {
  let hit : @protocol.SemanticSearchHit = {
    path: "src/main.mbt",
    rule_id: "$_",
    description: None,
    start_line: 1,
    start_column: 3,
    end_line: 1,
    end_column: 9,
    matched_source: "😀moon",
    source_context: [],
  }
  let first = SearchResultItem::from_semantic(hit)
  let second = SearchResultItem::from_semantic({
    ..hit,
    start_column: 5,
    end_column: 11,
    matched_source: "moon()",
  })
  let merged = coalesce_results([second, first])[0]
  assert_eq(merged.preview.length(), 1)
  assert_eq(merged.preview[0].text, "😀moon()")
  assert_eq(merged.preview[0].start_column, 3)
  assert_eq(merged.preview[0].highlight_slices(merged.ranges), [(0, 6), (2, 8)])
  assert_eq(merged.target_for_line(1), first.target)
}

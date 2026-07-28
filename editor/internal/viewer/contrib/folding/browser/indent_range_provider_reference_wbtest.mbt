// Conformance port of Monaco/VS Code's indentation-folding suites.
//
// Ports:
//   vscode/src/vs/editor/contrib/folding/test/browser/indentRangeProvider.test.ts
//   vscode/src/vs/editor/contrib/folding/test/browser/indentFold.test.ts
//   plus the `computeRanges`-backed cases of foldingRanges.test.ts
//   (`test max folding regions`, `findRange`, `setCollapsed`).
// From the checked-in vscode submodule.
//
// The suites' `/^\s*#region\b/`-style `RegExp` markers become predicate
// helpers (leading whitespace skip + keyword + word-boundary check); the
// case-insensitive variants stand in for the `i` flag.

///|
fn folding_test_model(lines : Array[String]) -> @model.TextModel {
  TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="model",
      path="/folding-test.txt",
    ),
    "folding-test.txt",
    "plaintext",
    1,
    "rev-1",
    lines.join("\n"),
  )
}

///|
/// ASCII lowercase fold for the case-insensitive marker variants.
fn ascii_lower(c : Int) -> Int {
  if c >= 'A' && c <= 'Z' {
    c + 32
  } else {
    c
  }
}

///|
fn is_word_char(c : Int) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_'
}

///|
/// `/^\s*<keyword>\b/` as a predicate.
fn region_marker(
  keyword : String,
  ignore_case? : Bool = false,
) -> (String) -> Bool {
  line => {
    let mut i = 0
    while i < line.length() && (line[i] == ' ' || line[i] == '\t') {
      i += 1
    }
    if i + keyword.length() > line.length() {
      return false
    }
    for j in 0..<keyword.length() {
      let mut c = line[i + j].to_int()
      if ignore_case {
        c = ascii_lower(c)
      }
      if c != keyword[j].to_int() {
        return false
      }
    }
    // `\b`: end of line or a non-word character.
    let after = i + keyword.length()
    after >= line.length() || !is_word_char(line[after].to_int())
  }
}

///|
/// The exact `/^#region$/` matchers of foldingRanges.test.ts.
fn exact_markers() -> @languages.FoldingMarkers {
  { start: line => line == "#region", end: line => line == "#endregion" }
}

///|
/// The `/^\s*#region\b/` markers of indentRangeProvider.test.ts.
fn word_markers() -> @languages.FoldingMarkers {
  { start: region_marker("#region"), end: region_marker("#endregion") }
}

///|
priv struct ExpectedIndentRange {
  start_line_number : Int
  end_line_number : Int
  parent_index : Int
} derive(Eq, Debug)

///|
/// The suite's `r(start, end, parentIndex)` literal.
fn er(
  start_line_number : Int,
  end_line_number : Int,
  parent_index : Int,
) -> ExpectedIndentRange {
  { start_line_number, end_line_number, parent_index }
}

///|
/// The suite's `assertRanges`.
fn assert_indent_ranges(
  lines : Array[String],
  expected : Array[ExpectedIndentRange],
  offside : Bool,
  markers? : @languages.FoldingMarkers,
) -> Unit raise {
  let model = folding_test_model(lines)
  let actual = compute_ranges(model, offside, markers?)
  let actual_ranges : Array[ExpectedIndentRange] = []
  for i in 0..<actual.length() {
    actual_ranges.push(
      er(
        actual.get_start_line_number(i),
        actual.get_end_line_number(i),
        actual.get_parent_index(i),
      ),
    )
  }
  if actual_ranges != expected {
    fail("\{Repr(actual_ranges)} != \{Repr(expected)}")
  }
}

///|
test "Fold one level" {
  let range = ["A", "  A", "  A", "  A"]
  assert_indent_ranges(range, [er(1, 4, -1)], true)
  assert_indent_ranges(range, [er(1, 4, -1)], false)
}

///|
test "Fold two levels" {
  let range = ["A", "  A", "  A", "    A", "    A"]
  assert_indent_ranges(range, [er(1, 5, -1), er(3, 5, 0)], true)
  assert_indent_ranges(range, [er(1, 5, -1), er(3, 5, 0)], false)
}

///|
test "Fold three levels" {
  let range = ["A", "  A", "    A", "      A", "A"]
  assert_indent_ranges(range, [er(1, 4, -1), er(2, 4, 0), er(3, 4, 1)], true)
  assert_indent_ranges(range, [er(1, 4, -1), er(2, 4, 0), er(3, 4, 1)], false)
}

///|
test "Fold decreasing indent" {
  let range = ["    A", "  A", "A"]
  assert_indent_ranges(range, [], true)
  assert_indent_ranges(range, [], false)
}

///|
test "Fold Java" {
  assert_indent_ranges(
    [
      "class A {", "  void foo() {", "    console.log();", "    console.log();",
      "  }", "", "  void bar() {", "    console.log();", "  }", "}", "interface B {",
      "  void bar();", "}",
    ],
    [er(1, 9, -1), er(2, 4, 0), er(7, 8, 0), er(11, 12, -1)],
    false,
  )
}

///|
test "Fold Javadoc" {
  assert_indent_ranges(
    ["/**", " * Comment", " */", "class A {", "  void foo() {", "  }", "}"],
    [er(1, 3, -1), er(4, 6, -1)],
    false,
  )
}

///|
test "Fold Whitespace Java" {
  assert_indent_ranges(
    [
      "class A {", "", "  void foo() {", "     ", "     return 0;", "  }", "      ",
      "}",
    ],
    [er(1, 7, -1), er(3, 5, 0)],
    false,
  )
}

///|
test "Fold Whitespace Python" {
  assert_indent_ranges(
    [
      "def a:", "  pass", "   ", "  def b:", "    pass", "  ", "      ", "def c: # since there was a deintent here",
    ],
    [er(1, 5, -1), er(4, 5, 0)],
    true,
  )
}

///|
test "Fold Tabs" {
  assert_indent_ranges(
    [
      "class A {", "\t\t", "\tvoid foo() {", "\t \t//hello", "\t    return 0;", "  \t}",
      "      ", "}",
    ],
    [er(1, 7, -1), er(3, 5, 0)],
    false,
  )
}

///|
test "Inside region, indented" {
  assert_indent_ranges(
    [
      "class A {", "  #region", "  void foo() {", "     ", "     return 0;", "  }",
      "  #endregion", "}",
    ],
    [er(1, 7, -1), er(2, 7, 0), er(3, 5, 1)],
    false,
    markers=word_markers(),
  )
}

///|
test "Inside region, not indented" {
  assert_indent_ranges(
    [
      "var x;", "#region", "void foo() {", "     ", "     return 0;", "  }", "#endregion",
      "",
    ],
    [er(2, 7, -1), er(3, 6, 0)],
    false,
    markers=word_markers(),
  )
}

///|
test "Empty Regions" {
  assert_indent_ranges(
    ["var x;", "#region", "#endregion", "#region", "", "#endregion", "var y;"],
    [er(2, 3, -1), er(4, 6, -1)],
    false,
    markers=word_markers(),
  )
}

///|
test "Nested Regions" {
  assert_indent_ranges(
    ["var x;", "#region", "#region", "", "#endregion", "#endregion", "var y;"],
    [er(2, 6, -1), er(3, 5, 0)],
    false,
    markers=word_markers(),
  )
}

///|
test "Nested Regions 2" {
  assert_indent_ranges(
    [
      "class A {", "  #region", "", "  #region", "", "  #endregion", "  // comment",
      "  #endregion", "}",
    ],
    [er(1, 8, -1), er(2, 8, 0), er(4, 6, 1)],
    false,
    markers=word_markers(),
  )
}

///|
test "Incomplete Regions" {
  assert_indent_ranges(
    ["class A {", "#region", "  // comment", "}"],
    [er(2, 3, -1)],
    false,
    markers=word_markers(),
  )
}

///|
test "Incomplete Regions 2" {
  assert_indent_ranges(
    [
      "", "#region", "#region", "#region", "  // comment", "#endregion", "#endregion",
      " // hello",
    ],
    [er(3, 7, -1), er(4, 6, 0)],
    false,
    markers=word_markers(),
  )
}

///|
test "Indented region before" {
  assert_indent_ranges(
    ["if (x)", "  return;", "", "#region", "  // comment", "#endregion"],
    [er(1, 3, -1), er(4, 6, -1)],
    false,
    markers=word_markers(),
  )
}

///|
test "Indented region before 2" {
  assert_indent_ranges(
    [
      "if (x)", "  log();", "", "    #region", "      // comment", "    #endregion",
    ],
    [er(1, 6, -1), er(2, 6, 0), er(4, 6, 1)],
    false,
    markers=word_markers(),
  )
}

///|
test "Indented region in-between" {
  assert_indent_ranges(
    ["#region", "  // comment", "  if (x)", "    return;", "", "#endregion"],
    [er(1, 6, -1), er(3, 5, 0)],
    false,
    markers=word_markers(),
  )
}

///|
test "Indented region after" {
  assert_indent_ranges(
    ["#region", "  // comment", "", "#endregion", "  if (x)", "    return;"],
    [er(1, 4, -1), er(5, 6, -1)],
    false,
    markers=word_markers(),
  )
}

///|
test "With off-side" {
  assert_indent_ranges(
    ["#region", "  ", "", "#endregion", ""],
    [er(1, 4, -1)],
    true,
    markers=word_markers(),
  )
}

///|
test "Nested with off-side" {
  assert_indent_ranges(
    ["#region", "  ", "#region", "", "#endregion", "", "#endregion", ""],
    [er(1, 7, -1), er(3, 5, 0)],
    true,
    markers=word_markers(),
  )
}

///|
test "Issue 35981" {
  assert_indent_ranges(
    [
      "function thisFoldsToEndOfPage() {", "  const variable = []", "    // #region",
      "    .reduce((a, b) => a,[]);", "}", "", "function thisFoldsProperly() {",
      "  const foo = \"bar\"", "}",
    ],
    [er(1, 4, -1), er(2, 4, 0), er(7, 8, -1)],
    false,
    markers=word_markers(),
  )
}

///|
test "Misspelled Markers" {
  assert_indent_ranges(
    [
      "#Region", "#endregion", "#regionsandmore", "#endregion", "#region", "#end region",
      "#region", "#endregionff",
    ],
    [],
    true,
    markers=word_markers(),
  )
}

///|
test "Issue 79359" {
  assert_indent_ranges(
    [
      "#region", "", "class A", "  foo", "", "class A", "  foo", "", "#endregion",
    ],
    [er(1, 9, -1), er(3, 4, 0), er(6, 7, 0)],
    true,
    markers=word_markers(),
  )
}

///|
test "Markers with stateful flags" {
  // `/^\s*#region\b/g` + `/^\s*#endregion\b/g`
  assert_indent_ranges(
    ["#region", "content", "#endregion"],
    [er(1, 3, -1)],
    false,
    markers=word_markers(),
  )
  // `/^\s*#region\b/gi` + `/^\s*#endregion\b/g`
  assert_indent_ranges(
    ["#REGION", "content", "#endregion"],
    [er(1, 3, -1)],
    false,
    markers={
      start: region_marker("#region", ignore_case=true),
      end: region_marker("#endregion"),
    },
  )
  assert_indent_ranges(["#REGION", "content", "#ENDREGION"], [], false, markers={
    start: region_marker("#region", ignore_case=true),
    end: region_marker("#endregion"),
  })
  assert_indent_ranges(["#REGION", "content", "#ENDREGION"], [], false, markers={
    start: region_marker("#region"),
    end: region_marker("#endregion", ignore_case=true),
  })
}

///|
/// foldingRanges.test.ts `test max folding regions`.
test "test max folding regions" {
  let lines : Array[String] = []
  let n_regions = MAX_FOLDING_REGIONS
  let collector = RangesCollector({
    limit: () => MAX_FOLDING_REGIONS,
    update: (_computed, _limited) => (),
  })
  for _ in 0..<n_regions {
    let start_line_number = lines.length()
    lines.push("#region")
    let end_line_number = lines.length()
    lines.push("#endregion")
    collector.insert_first(start_line_number, end_line_number, 0)
  }
  let model = folding_test_model(lines)
  let actual = collector.to_indent_ranges(model)
  assert_eq(actual.length(), n_regions)
}

///|
/// foldingRanges.test.ts `findRange`.
test "findRange" {
  let lines = [
    "#region", "#endregion", "class A {", "  void foo() {", "    if (true) {", "        return;",
    "    }", "", "    if (true) {", "      return;", "    }", "  }", "}",
  ]
  let text_model = folding_test_model(lines)
  let actual = compute_ranges(text_model, false, markers=exact_markers())
  // r0 = (1, 2), r1 = (3, 12), r2 = (4, 11), r3 = (5, 6), r4 = (9, 10)
  assert_eq(actual.find_range(1), 0)
  assert_eq(actual.find_range(2), 0)
  assert_eq(actual.find_range(3), 1)
  assert_eq(actual.find_range(4), 2)
  assert_eq(actual.find_range(5), 3)
  assert_eq(actual.find_range(6), 3)
  assert_eq(actual.find_range(7), 2)
  assert_eq(actual.find_range(8), 2)
  assert_eq(actual.find_range(9), 4)
  assert_eq(actual.find_range(10), 4)
  assert_eq(actual.find_range(11), 2)
  assert_eq(actual.find_range(12), 1)
  assert_eq(actual.find_range(13), -1)
}

///|
/// foldingRanges.test.ts `setCollapsed`.
test "setCollapsed" {
  let lines : Array[String] = []
  let n_regions = 500
  for _ in 0..<n_regions {
    lines.push("#region")
  }
  for _ in 0..<n_regions {
    lines.push("#endregion")
  }
  let model = folding_test_model(lines)
  let actual = compute_ranges(model, false, markers=exact_markers())
  assert_eq(actual.length(), n_regions)
  for i in 0..<n_regions {
    actual.set_collapsed(i, i % 3 == 0)
  }
  for i in 0..<n_regions {
    assert_eq(actual.is_collapsed(i), i % 3 == 0)
  }
}

///|
/// indentFold.test.ts `Limit by indent`.
test "Limit by indent" {
  let lines = [
    "A", "  A", "  A", "    A", "      A", "    A", "      A", "      A", "         A",
    "      A", "         A", "  A", "              A", "                 A", "A",
    "  A",
  ]
  let r1 = (1, 14) // 0
  let r2 = (3, 11) // 1
  let r3 = (4, 5) // 2
  let r4 = (6, 11) // 2
  let r5 = (8, 9) // 3
  let r6 = (10, 11) // 3
  let r7 = (12, 14) // 1
  let r8 = (13, 14) // 4
  let r9 = (15, 16) // 0
  let model = folding_test_model(lines)
  let assert_limit = (
    max_entries : Int,
    expected_ranges : Array[(Int, Int)],
    message : String,
  ) => {
    let reported : Ref[Int?] = { val: None }
    let indent_ranges = compute_ranges(model, true, folding_ranges_limit={
      limit: () => max_entries,
      update: (_computed, limited) => reported.val = limited,
    })
    guard indent_ranges.length() <= max_entries else { fail("max " + message) }
    let actual : Array[(Int, Int)] = []
    for i in 0..<indent_ranges.length() {
      actual.push(
        (
          indent_ranges.get_start_line_number(i),
          indent_ranges.get_end_line_number(i),
        ),
      )
    }
    if actual != expected_ranges {
      fail("\{message}: \{Repr(actual)} != \{Repr(expected_ranges)}")
    }
    let expected_reported : Int? = if 9 <= max_entries {
      None
    } else {
      Some(max_entries)
    }
    if reported.val != expected_reported {
      fail("limited " + message)
    }
  }
  assert_limit(1000, [r1, r2, r3, r4, r5, r6, r7, r8, r9], "1000")
  assert_limit(9, [r1, r2, r3, r4, r5, r6, r7, r8, r9], "9")
  assert_limit(8, [r1, r2, r3, r4, r5, r6, r7, r9], "8")
  assert_limit(7, [r1, r2, r3, r4, r5, r7, r9], "7")
  assert_limit(6, [r1, r2, r3, r4, r7, r9], "6")
  assert_limit(5, [r1, r2, r3, r7, r9], "5")
  assert_limit(4, [r1, r2, r7, r9], "4")
  assert_limit(3, [r1, r2, r9], "3")
  assert_limit(2, [r1, r9], "2")
  assert_limit(1, [r1], "1")
  assert_limit(0, [], "0")
}

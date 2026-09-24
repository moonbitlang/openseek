// White-box section derivation over a real parse. Every case renders actual Markdown
// rather than hand-building anchors, so these assertions also pin the
// heading-level retention added to `MarkdownBlockAnchor`.

///|
/// Renders `source` and describes each derived section as
/// `level:heading_anchor:[body anchors]:foldable`.
fn describe_sections(source : String) -> Array[String] {
  let projection = render_markdown(source).projection
  markdown_sections(projection).map(section => {
    "level \{section.level} heading@\{section.heading_anchor_index} body\{Repr(section.body_anchor_indexes)} foldable=\{section.is_foldable(projection)}"
  })
}

///|
test "a heading owns every following block until a same-or-shallower heading" {
  debug_inspect(
    describe_sections(
      (
        #|# One
        #|
        #|body of one
        #|
        #|# Two
        #|
        #|body of two
        #|
      ),
    ),
    content=(
      #|[
      #|  "level 1 heading@0 body[1] foldable=true",
      #|  "level 1 heading@2 body[3] foldable=true",
      #|]
    ),
  )
}

///|
test "a deeper heading nests inside the section above it" {
  debug_inspect(
    describe_sections(
      (
        #|# Outer
        #|
        #|outer body
        #|
        #|## Inner
        #|
        #|inner body
        #|
        #|# Next
        #|
      ),
    ),
    content=(
      #|[
      #|  "level 1 heading@0 body[1, 2, 3] foldable=true",
      #|  "level 2 heading@2 body[3] foldable=true",
      #|  "level 1 heading@4 body[] foldable=false",
      #|]
    ),
  )
}

///|
test "a heading with no body is not foldable" {
  debug_inspect(
    describe_sections(
      (
        #|# Empty
        #|# Also empty
        #|## Deeper, and this one has a body
        #|
        #|body text
        #|
      ),
    ),
    content=(
      #|[
      #|  "level 1 heading@0 body[] foldable=false",
      #|  "level 1 heading@1 body[2, 3] foldable=true",
      #|  "level 2 heading@2 body[3] foldable=true",
      #|]
    ),
  )
}

///|
test "a level jump does not create an intermediate section" {
  debug_inspect(
    describe_sections(
      (
        #|# One
        #|
        #|### Three
        #|
        #|body
        #|
        #|## Two
        #|
        #|body two
        #|
      ),
    ),
    content=(
      #|[
      #|  "level 1 heading@0 body[1, 2, 3, 4] foldable=true",
      #|  "level 3 heading@1 body[2] foldable=true",
      #|  "level 2 heading@3 body[4] foldable=true",
      #|]
    ),
  )
}

///|
test "setext headings behave exactly like their ATX levels" {
  debug_inspect(
    (
      describe_sections(
        (
          #|Title
          #|=====
          #|
          #|body
          #|
          #|Subtitle
          #|--------
          #|
          #|sub body
          #|
        ),
      ),
      describe_sections(
        (
          #|# Title
          #|
          #|body
          #|
          #|## Subtitle
          #|
          #|sub body
          #|
        ),
      ),
    ),
    content=(
      #|(
      #|  [
      #|    "level 1 heading@0 body[1, 2, 3] foldable=true",
      #|    "level 2 heading@2 body[3] foldable=true",
      #|  ],
      #|  [
      #|    "level 1 heading@0 body[1, 2, 3] foldable=true",
      #|    "level 2 heading@2 body[3] foldable=true",
      #|  ],
      #|)
    ),
  )
}

///|
test "a document with no heading has no sections" {
  debug_inspect(
    describe_sections(
      (
        #|just prose
        #|
        #|and more prose
        #|
      ),
    ),
    content=(
      #|[]
    ),
  )
}

///|
test "a preamble before the first heading belongs to no section" {
  debug_inspect(
    describe_sections(
      (
        #|preamble prose
        #|
        #|# First
        #|
        #|body
        #|
      ),
    ),
    content=(
      #|["level 1 heading@1 body[2] foldable=true"]
    ),
  )
}

///|
test "the body source range covers the body and excludes the heading" {
  let source =
    #|# Title
    #|
    #|body line
    #|
  let projection = render_markdown(source).projection
  let sections = markdown_sections(projection)
  guard sections is [section, ..] else { fail("expected one section") }
  let heading = projection.block_anchors[section.heading_anchor_index]
  debug_inspect(
    (
      section.source_range,
      section.body_source_range,
      // the body starts after the heading ends
      section.body_source_range.map(body => {
        body.start >= heading.source_range.end_exclusive
      }),
    ),
    content=(
      #|(
      #|  { start: 0, end_exclusive: 18 },
      #|  Some({ start: 9, end_exclusive: 18 }),
      #|  Some(true),
      #|)
    ),
  )
}

///|
test "the hidden run contains body node identities and excludes its heading" {
  let source =
    #|# Title
    #|
    #|first paragraph
    #|
    #|second paragraph
    #|
    #|# Next
    #|
  let projection = render_markdown(source).projection
  let sections = markdown_sections(projection)
  guard sections is [first, ..] else { fail("expected a first section") }
  let heading_id = projection.block_anchors[first.heading_anchor_index].node_id
  let body_ids = first.body_node_ids(projection)
  assert_eq(body_ids.length(), 2)
  assert_false(body_ids.contains(heading_id))
  assert_eq(
    body_ids.map(id => {
      projection
      .source_range_for_node(id)
      .map(range => source[range.start:range.end_exclusive].to_owned())
    }),
    [Some("first paragraph"), Some("second paragraph")],
  )
}

///|
test "a code fence inside a section is part of that section's body" {
  let source =
    #|# Example
    #|
    #|```mbt check
    #|test { }
    #|```
    #|
    #|# Other
    #|
  let projection = render_markdown(source).projection
  let sections = markdown_sections(projection)
  guard sections is [example, ..] else { fail("expected the example section") }
  guard projection.code_blocks is [block, ..] else {
    fail("expected one code block")
  }
  debug_inspect(
    (
      example.is_foldable(projection),
      // the fence's own anchor is inside the section's source span
      example.source_range.contains(block.block_source_range.start),
      block.is_moonbit_check_fence(MoonBitMarkdown),
    ),
    content=(
      #|(true, true, true)
    ),
  )
}

///|
test "section lookup by source offset returns the innermost match" {
  let source =
    #|# Outer
    #|
    #|outer body
    #|
    #|## Inner
    #|
    #|inner body
    #|
  let projection = render_markdown(source).projection
  let sections = markdown_sections(projection)
  guard source.find("inner body") is Some(inner_body_offset) else {
    fail("fixture must contain the inner body")
  }
  guard source.find("outer body") is Some(outer_body_offset) else {
    fail("fixture must contain the outer body")
  }
  let level_at = offset => {
    markdown_section_at_source_offset(sections, offset).map(section => {
      section.level
    })
  }
  debug_inspect(
    (level_at(outer_body_offset), level_at(inner_body_offset), level_at(0)),
    content=(
      #|(Some(1), Some(2), Some(1))
    ),
  )
}

///|
/// Renders `source` and pairs each section with its reconciliation key.
fn describe_keys(source : String) -> Array[String] {
  let projection = render_markdown(source).projection
  let sections = markdown_sections(projection)
  markdown_section_keys(sections, projection, source).map(key => {
    key.replace_all(old="\u{1f}", new="|")
  })
}

///|
test "the key is level, normalized heading text, and occurrence" {
  debug_inspect(
    describe_keys(
      (
        #|# Title
        #|
        #|body
        #|
        #|##   Spaced   Heading   ##
        #|
        #|body
        #|
      ),
    ),
    content=(
      #|["1|Title|0", "2|Spaced Heading|0"]
    ),
  )
}

///|
test "repeated headings differ only by occurrence" {
  debug_inspect(
    describe_keys(
      (
        #|## Example
        #|
        #|first
        #|
        #|## Example
        #|
        #|second
        #|
        #|## Example
        #|
        #|third
        #|
      ),
    ),
    content=(
      #|["2|Example|0", "2|Example|1", "2|Example|2"]
    ),
  )
}

///|
test "a setext heading keys identically to its ATX equivalent" {
  debug_inspect(
    (
      describe_keys(
        (
          #|Title
          #|=====
          #|
          #|body
          #|
        ),
      ),
      describe_keys(
        (
          #|# Title
          #|
          #|body
          #|
        ),
      ),
    ),
    content=(
      #|(["1|Title|0"], ["1|Title|0"])
    ),
  )
}

///|
test "editing a later section does not change an earlier section's key" {
  let before = describe_keys(
    (
      #|# Stable
      #|
      #|body
      #|
      #|# Other
      #|
      #|original text
      #|
    ),
  )
  let after = describe_keys(
    (
      #|# Stable
      #|
      #|body
      #|
      #|# Other
      #|
      #|rewritten, longer body text that shifts every later offset
      #|
      #|and gains a whole extra paragraph
      #|
    ),
  )
  debug_inspect(
    (before, after, before[0] == after[0]),
    content=(
      #|(["1|Stable|0", "1|Other|0"], ["1|Stable|0", "1|Other|0"], true)
    ),
  )
}

///|
test "a heading inside a blockquote does not end the enclosing section" {
  debug_inspect(
    describe_sections(
      (
        #|# A
        #|
        #|> # quoted
        #|> quoted text
        #|
        #|after
        #|
        #|# B
        #|
      ),
    ),
    content=(
      #|[
      #|  "level 1 heading@0 body[1, 2, 3, 4] foldable=true",
      #|  "level 1 heading@5 body[] foldable=false",
      #|]
    ),
  )
}

///|
test "a closing hash sequence is stripped only when whitespace-delimited" {
  debug_inspect(
    (
      describe_keys(
        (
          #|# C
          #|
          #|body
          #|
        ),
      ),
      describe_keys(
        (
          #|# C#
          #|
          #|body
          #|
        ),
      ),
      describe_keys(
        (
          #|# C ###
          #|
          #|body
          #|
        ),
      ),
    ),
    content=(
      #|(["1|C|0"], ["1|C#|0"], ["1|C|0"])
    ),
  )
}

///|
test "a body of only non-rendering anchors is not foldable" {
  let source =
    #|# Only a link definition
    #|
    #|[ref]: https://example.com
    #|
    #|# Next
    #|
  let projection = render_markdown(source).projection
  debug_inspect(
    markdown_sections(projection).map(section => {
      (
        section.body_anchor_indexes.length(),
        section.body_node_ids(projection).length(),
        section.is_foldable(projection),
      )
    }),
    content=(
      #|[(0, 0, false), (0, 0, false)]
    ),
  )
}

///|
test "inline markup and setext line breaks do not change a heading's identity" {
  debug_inspect(
    (
      // emphasis, code spans, and links reduce to the words a reader sees
      describe_keys(
        (
          #|# *Title*
          #|
          #|body
          #|
        ),
      ),
      describe_keys(
        (
          #|# Title
          #|
          #|body
          #|
        ),
      ),
      describe_keys(
        (
          #|# `Title`
          #|
          #|body
          #|
        ),
      ),
      // a multi-line setext heading keeps all of its words
      describe_keys(
        (
          #|Foo
          #|bar
          #|---
          #|
          #|body
          #|
        ),
      ),
      describe_keys(
        (
          #|## Foo bar
          #|
          #|body
          #|
        ),
      ),
      // a literal trailing hash is content, not decoration
      describe_keys(
        (
          #|# C#
          #|
          #|body
          #|
        ),
      ),
    ),
    content=(
      #|(
      #|  ["1|Title|0"],
      #|  ["1|Title|0"],
      #|  ["1|Title|0"],
      #|  ["2|Foo bar|0"],
      #|  ["2|Foo bar|0"],
      #|  ["1|C#|0"],
      #|)
    ),
  )
}

///|
/// Renders `source` and describes its TOC as `depth/level indent text`.
fn describe_toc(source : String) -> Array[String] {
  markdown_table_of_contents(render_markdown(source).projection).map(entry => {
    "d\{entry.depth}/h\{entry.level} \{"  ".repeat(entry.depth - 1)}\{entry.text}"
  })
}

///|
test "the toc indents by structural depth, not literal heading level" {
  debug_inspect(
    describe_toc(
      (
        #|# Top
        #|
        #|body
        #|
        #|### Jumped straight to three
        #|
        #|body
        #|
        #|## Back to two
        #|
        #|body
        #|
        #|# Second top
        #|
        #|body
        #|
      ),
    ),
    content=(
      #|[
      #|  "d1/h1 Top",
      #|  "d2/h3   Jumped straight to three",
      #|  "d2/h2   Back to two",
      #|  "d1/h1 Second top",
      #|]
    ),
  )
}

///|
test "a document starting at h3 still indents from depth one" {
  debug_inspect(
    describe_toc(
      (
        #|### Deep but first
        #|
        #|body
        #|
        #|#### Child
        #|
        #|body
        #|
      ),
    ),
    content=(
      #|["d1/h3 Deep but first", "d2/h4   Child"]
    ),
  )
}

///|
test "toc text is markup-independent and skips headings inside containers" {
  debug_inspect(
    describe_toc(
      (
        #|# A `code` and *emphasis* heading
        #|
        #|> # quoted, not outline structure
        #|> text
        #|
        #|## Real child
        #|
        #|body
        #|
      ),
    ),
    content=(
      #|["d1/h1 A code and emphasis heading", "d2/h2   Real child"]
    ),
  )
}

///|
test "toc rows carry the reveal offset and agree with foldability" {
  let source =
    #|# Has a body
    #|
    #|body
    #|
    #|# Empty
    #|
  let projection = render_markdown(source).projection
  debug_inspect(
    markdown_table_of_contents(projection).map(entry => {
      (entry.text, entry.source_offset, entry.is_foldable, entry.section_index)
    }),
    content=(
      #|[("Has a body", 0, true, 0), ("Empty", 20, false, 1)]
    ),
  )
}

///|
test "auto-fold collapses only bulky sections at depth three or deeper" {
  let source =
    #|# Doc
    #|
    #|intro
    #|
    #|## Shallow
    #|
    #|paragraph 0
    #|
    #|paragraph 1
    #|
    #|paragraph 2
    #|
    #|paragraph 3
    #|
    #|paragraph 4
    #|
    #|paragraph 5
    #|
    #|paragraph 6
    #|
    #|paragraph 7
    #|
    #|### Bulky by elements
    #|
    #|element 0
    #|
    #|element 1
    #|
    #|element 2
    #|
    #|element 3
    #|
    #|element 4
    #|
    #|element 5
    #|
    #|element 6
    #|
    #|### Bulky by lines
    #|
    #|```
    #|line 0
    #|line 1
    #|line 2
    #|line 3
    #|line 4
    #|line 5
    #|line 6
    #|line 7
    #|line 8
    #|line 9
    #|line 10
    #|line 11
    #|line 12
    #|line 13
    #|```
    #|
    #|### Small
    #|
    #|only one paragraph
    #|
  let projection = render_markdown(source).projection
  let entries = markdown_table_of_contents(projection)
  let collapsed = markdown_default_collapsed_sections(projection, source)
  debug_inspect(
    (
      entries.map(entry => (entry.depth, entry.text)),
      collapsed.map(index => entries[index].text),
    ),
    content=(
      #|(
      #|  [
      #|    (1, "Doc"),
      #|    (2, "Shallow"),
      #|    (3, "Bulky by elements"),
      #|    (3, "Bulky by lines"),
      #|    (3, "Small"),
      #|  ],
      #|  ["Bulky by elements", "Bulky by lines"],
      #|)
    ),
  )
}

///|
test "the thresholds are tunable and depth gating wins over bulk" {
  let source =
    #|# Doc
    #|
    #|### Deep
    #|
    #|body
    #|
  let projection = render_markdown(source).projection
  debug_inspect(
    (
      markdown_default_collapsed_sections(projection, source).length(),
      markdown_default_collapsed_sections(
        projection,
        source,
        min_rendered_elements=1,
        min_body_lines=1,
      ).length(),
      markdown_default_collapsed_sections(
        projection,
        source,
        min_depth=99,
        min_rendered_elements=1,
        min_body_lines=1,
      ).length(),
    ),
    content=(
      #|(0, 0, 0)
    ),
  )
}

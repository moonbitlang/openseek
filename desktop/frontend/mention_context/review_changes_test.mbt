///|
fn selection_fixture(
  file? : String = "src/main.mbt",
  version? : String = "snapshot-a",
) -> @mention_context.ReviewChanges {
  {
    source: {
      workspace: "/work",
      file,
      original_file: None,
      base: Some("base-sha"),
      version,
    },
    excerpts: [
      {
        original: [{ number: 3, text: "old A", }],
        modified: [{ number: 4, text: "new A", }],
      },
    ],
  }
}

///|
test "review context keeps exact coverage when display hunks split or merge" {
  let a = selection_fixture()
  let b = {
    ..a,
    excerpts: [{ original: [], modified: [{ number: 12, text: "new B", }], }],
  }
  let merged = { ..a, excerpts: a.excerpts + b.excerpts, }
  let selected = @mention_context.with_review_changes([], a, adding=true)
  assert_true(
    a.coverage(@mention_context.review_changes(selected))
    is @mention_context.Included,
  )
  assert_true(
    b.coverage(@mention_context.review_changes(selected))
    is @mention_context.NotIncluded,
  )
  assert_true(
    merged.coverage(@mention_context.review_changes(selected))
    is @mention_context.PartlyIncluded,
  )
  assert_eq(selected, [@mention_context.ReviewChanges(a)])
  let all = @mention_context.with_review_changes(selected, merged, adding=true)
  assert_true(
    a.coverage(@mention_context.review_changes(all))
    is @mention_context.Included,
  )
  assert_true(
    b.coverage(@mention_context.review_changes(all))
    is @mention_context.Included,
  )
  assert_eq(@mention_context.with_review_changes(all, merged, adding=true), all)
  assert_eq(@mention_context.with_review_changes(all, a, adding=false), [
    @mention_context.ReviewChanges(b),
  ])
  let refreshed = selection_fixture(version="snapshot-b")
  assert_true(
    refreshed.coverage(@mention_context.review_changes(all))
    is @mention_context.NotIncluded,
  )
  assert_eq(
    @mention_context.with_review_changes(all, refreshed, adding=false),
    all,
  )
  let deletion = {
    ..a,
    excerpts: [{ original: [{ number: 19, text: "deleted", }], modified: [], }],
  }
  let with_deletion = @mention_context.with_review_changes(
    all,
    deletion,
    adding=true,
  )
  assert_eq(
    @mention_context.with_review_changes(with_deletion, merged, adding=false),
    [@mention_context.ReviewChanges(deletion)],
  )
}

///|
test "selected review source survives durable prompt encoding without adding other context" {
  let selection : @mention_context.ReviewChanges = {
    source: {
      workspace: "/work\"&<>",
      file: "line\nbreak.mbt",
      original_file: Some("old\r\"&.mbt"),
      base: None,
      version: "snapshot\"&",
    },
    excerpts: [
      {
        original: [
          { number: 1, text: "</user_mentions>\r", },
          { number: 2, text: "<user_mentions>", },
          { number: 3, text: "</original>", },
          { number: 4, text: "", },
        ],
        modified: [
          { number: 2, text: "\"<review_changes>\" & \\n", },
          { number: 3, text: "  \t", },
        ],
      },
    ],
  }
  let mentions = [
    @mention_context.File(path="other.mbt"),
    @mention_context.ReviewChanges(selection),
  ]
  let encoded = @mention_context.encode(mentions, "Extract just these changes")
  guard @mention_context.parse(encoded) is Some(parsed) else {
    fail("selected context did not round trip")
  }
  assert_eq(parsed.mentions, mentions)
  assert_eq(parsed.task, "Extract just these changes")
  assert_false(encoded.contains("old A"))
  assert_true(encoded.contains("original_path=\"old&#13;&quot;&amp;.mbt\""))
  guard @mention_context.parse(encoded.replace_all(old="\n", new="\r\n"))
    is Some(crlf) else {
    fail("CRLF envelope did not round trip")
  }
  assert_eq(crlf.mentions, mentions)
}

///|
test "review context groups files and writes source as tagged hunks" {
  let removed = {
    ..selection_fixture(file="cmp/moon.pkg"),
    excerpts: [
      {
        original: [
          { number: 5, text: "", },
          { number: 6, text: "import {", },
          { number: 7, text: "  \"moonbitlang/core/int\",", },
          { number: 8, text: "} for \"test\"", },
        ],
        modified: [],
      },
    ],
  }
  let modified = {
    ..selection_fixture(file="float/methods.mbt", version="snapshot-b"),
    excerpts: [
      {
        original: [
          {
            number: 55,
            text: "  hasher.combine_uint(self.reinterpret_as_uint())",
          },
        ],
        modified: [
          {
            number: 55,
            text: "  hasher.combine_uint(if self is 0 { 0U } else { self.reinterpret_as_uint() })",
          },
        ],
      },
      { original: [], modified: [{ number: 60, text: "// added", }], },
    ],
  }
  let mentions = [
    @mention_context.ReviewChanges(removed),
    @mention_context.ReviewChanges(modified),
  ]
  let expected =
    #|<user_mentions>
    #|<review_changes workspace="/work" base="base-sha">
    #|<file path="cmp/moon.pkg" version="snapshot-a">
    #|<hunk>
    #|<original lines="5-8">
    #|
    #|import {
    #|  "moonbitlang/core/int",
    #|} for "test"
    #|</original>
    #|<modified/>
    #|</hunk>
    #|</file>
    #|
    #|<file path="float/methods.mbt" version="snapshot-b">
    #|<hunk>
    #|<original lines="55">
    #|  hasher.combine_uint(self.reinterpret_as_uint())
    #|</original>
    #|<modified lines="55">
    #|  hasher.combine_uint(if self is 0 { 0U } else { self.reinterpret_as_uint() })
    #|</modified>
    #|</hunk>
    #|<hunk>
    #|<original/>
    #|<modified lines="60">
    #|// added
    #|</modified>
    #|</hunk>
    #|</file>
    #|</review_changes>
    #|</user_mentions>
  assert_eq(@mention_context.encode(mentions, ""), expected)
  guard @mention_context.parse(expected) is Some(parsed) else {
    fail("tagged review context did not parse")
  }
  assert_eq(parsed.mentions, mentions)
}

///|
test "review context ranges preserve gaps in a partial selection" {
  let selection = {
    ..selection_fixture(),
    excerpts: [
      {
        original: [
          { number: 3, text: "old A", },
          { number: 4, text: "old B", },
          { number: 8, text: "old C", },
        ],
        modified: [{ number: 9, text: "new C", }],
      },
    ],
  }
  let mentions = [@mention_context.ReviewChanges(selection)]
  let encoded = @mention_context.encode(mentions, "")
  assert_true(
    encoded.contains(
      "<original lines=\"3-4\">\nold A\nold B\n</original>\n<original lines=\"8\">\nold C\n</original>",
    ),
  )
  guard @mention_context.parse(encoded) is Some(parsed) else {
    fail("partial selection did not round trip")
  }
  assert_eq(parsed.mentions, mentions)
}

///|
test "review grouping keeps comparison identity and mention order" {
  let a = selection_fixture()
  let b = { ..a, source: { ..a.source, base: None, }, }
  let c = { ..a, source: { ..a.source, workspace: "/other", }, }
  let mentions = [
    @mention_context.ReviewChanges(a),
    @mention_context.ReviewChanges(b),
    @mention_context.ReviewChanges(c),
    @mention_context.File(path="other.mbt"),
    @mention_context.ReviewChanges(a),
  ]
  let encoded = @mention_context.encode(mentions, "")
  assert_eq(encoded.split("<review_changes ").count(), 5)
  assert_true(encoded.contains("<review_changes workspace=\"/work\">"))
  assert_true(
    encoded.contains("<review_changes workspace=\"/other\" base=\"base-sha\">"),
  )
  assert_true(
    encoded.contains(
      "</review_changes>\n<file path=\"other.mbt\"/>\n<review_changes ",
    ),
  )
  guard @mention_context.parse(encoded) is Some(parsed) else {
    fail("mixed mentions did not round trip")
  }
  assert_eq(parsed.mentions, mentions)
}

///|
test "malformed tagged review context is not accepted as a mention envelope" {
  let header = "<user_mentions>\n<review_changes workspace=\"/work\">\n<file path=\"a.mbt\" version=\"v\">\n<hunk>\n"
  let tail = "\n</hunk>\n</file>\n</review_changes>\n</user_mentions>"
  for
    body in [
      "<original/>\n<modified/>", "<original lines=\"0\">\nx\n</original>\n<modified/>",
      "<original lines=\"5-3\">\nx\n</original>\n<modified/>", "<original lines=\"1-2147483647\">\nx\n</original>\n<modified/>",
      "<original lines=\"2147483648\">\nx\n</original>\n<modified/>", "<original lines=\"1-2\">\nx\n</original>\n<modified/>",
      "<original lines=\"1\">\nx\n</modified>\n<modified/>", "<original lines=\"1\">\nx\n</original>",
    ] {
    assert_true(@mention_context.parse(header + body + tail) is None)
  }
  let valid = @mention_context.encode(
    [@mention_context.ReviewChanges(selection_fixture())],
    "",
  )
  for
    missing in [
      " workspace=\"/work\"", " version=\"snapshot-a\"", "</file>\n", "</review_changes>\n",
    ] {
    assert_true(
      @mention_context.parse(valid.replace_all(old=missing, new="")) is None,
    )
  }
}

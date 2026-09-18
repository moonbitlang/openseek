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
  let selection = {
    ..selection_fixture(),
    excerpts: [
      {
        original: [{ number: 1, text: "</user_mentions>\r", }],
        modified: [{ number: 2, text: "\"<review_changes>\" & \\n", }],
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
}

///|
test "malformed review context is not accepted as a mention envelope" {
  for
    body in [
      "{}", "null", "{\"source\":null,\"excerpts\":[]}", "{\"source\":{\"workspace\":\"/work\",\"file\":\"a\",\"version\":\"v\"},\"excerpts\":[{\"original\":[{\"line\":0,\"text\":\"x\"}],\"modified\":[]}]}",
    ] {
    assert_true(
      @mention_context.parse(
        "<user_mentions>\n<review_changes>\n\{body}\n</review_changes>\n</user_mentions>",
      )
      is None,
    )
  }
}

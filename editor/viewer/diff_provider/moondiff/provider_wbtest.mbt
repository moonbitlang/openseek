///|
fn changed_line(
  index : Int,
  prefix : String,
  changed : String,
  suffix : String,
) -> @mbtdiff.DiffLine {
  {
    index,
    segments: [
      { kind: Unchanged, text: prefix, },
      { kind: Changed, text: changed, },
      { kind: Unchanged, text: suffix, },
    ],
  }
}

///|
test "fragment adapter keeps MoonDiff coordinates local to one section" {
  let document : @mbtdiff.HunkDocument = {
    hunks: [
      {
        old_start: 0,
        old_len: 1,
        new_start: 0,
        new_len: 1,
        blocks: [
          ChangeBlock([
            Paired(
              changed_line(0, "fn value() { ", "1", " }"),
              changed_line(0, "fn value() { ", "2", " }"),
            ),
          ]),
        ],
      },
    ],
  }
  guard fragment_document_diff(document, "fn value() { 1 }", "fn value() { 2 }")
    is Some({ changes: [{ mapping: change, .. }], }) else {
    fail("expected one valid fragment-local change")
  }
  assert_eq(change.original, LineRange(1, 2))
  assert_eq(change.modified, LineRange(1, 2))
  guard change.inner_changes is Some([inner]) else {
    fail("expected one intraline mapping")
  }
  assert_eq(inner.original, Range(1, 14, 1, 15))
  assert_eq(inner.modified, Range(1, 14, 1, 15))
}

///|
test "fragment adapter preserves one-sided intraline mappings" {
  let document : @mbtdiff.HunkDocument = {
    hunks: [
      {
        old_start: 0,
        old_len: 0,
        new_start: 0,
        new_len: 1,
        blocks: [ChangeBlock([NewOnly(changed_line(0, "", "new()", ""))])],
      },
    ],
  }
  guard fragment_document_diff(document, "anchor", "new()\nanchor")
    is Some({ changes: [{ mapping: change, .. }], }) else {
    fail("expected one insertion")
  }
  assert_eq(change.original, LineRange(1, 1))
  assert_eq(change.modified, LineRange(1, 2))
  guard change.inner_changes is Some([inner]) else {
    fail("expected the inserted token mapping")
  }
  assert_eq(inner.original, Range(1, 1, 1, 1))
  assert_eq(inner.modified, Range(1, 1, 1, 6))
}

///|
test "ignored fragment rows do not become visible changes" {
  let old : @mbtdiff.DiffLine = {
    index: 0,
    segments: [{ kind: Changed, text: "// old", }],
  }
  let new : @mbtdiff.DiffLine = {
    index: 0,
    segments: [{ kind: Changed, text: "// new", }],
  }
  let document : @mbtdiff.HunkDocument = {
    hunks: [
      {
        old_start: 0,
        old_len: 1,
        new_start: 0,
        new_len: 1,
        blocks: [IgnoredBlock([Paired(old, new)])],
      },
    ],
  }
  guard fragment_document_diff(document, "// old", "// new") is Some(result) else {
    fail("expected a valid ignored fragment")
  }
  guard result.changes is [{ kind: Ignored, mapping, }] else {
    fail("expected an ignored paired change")
  }
  assert_eq(mapping.original, LineRange(1, 2))
  assert_eq(mapping.modified, LineRange(1, 2))
}

///|
test "fragment provider returns its prevalidated document unchanged" {
  let document : @diff.DocumentDiff = { changes: [], }
  let provider = MoonFragmentDiffProvider(document)
  let object = provider.as_document_diff_provider()
  assert_eq(
    object.compute_diff(TextSnapshot("old"), TextSnapshot("new"), {
      ignore_trim_whitespace: true,
    }),
    document,
  )
}

///|
test "fragment adapter groups same-kind rows while retaining visibility boundaries" {
  let line = fn(index, text) {
    @mbtdiff.DiffLine::{ index, segments: [{ kind: Ignored, text, }], }
  }
  let document : @mbtdiff.HunkDocument = {
    hunks: [
      {
        old_start: 0,
        old_len: 2,
        new_start: 0,
        new_len: 5,
        blocks: [
          IgnoredBlock([Paired(line(0, "// same"), line(0, "// same"))]),
          IgnoredBlock([NewOnly(line(1, "// first"))]),
          IgnoredBlock([NewOnly(line(2, "// second"))]),
          ChangeBlock([
            Paired(
              changed_line(1, "", "old", ""),
              changed_line(3, "", "new", ""),
            ),
          ]),
          IgnoredBlock([NewOnly(line(4, "// last"))]),
        ],
      },
    ],
  }
  guard fragment_document_diff(
      document, "// same\nold", "// same\n// first\n// second\nnew\n// last",
    )
    is Some(result) else {
    fail("expected valid interleaved changes")
  }
  assert_eq(result.changes.map(change => change.kind), [
    Ignored,
    Visible,
    Ignored,
  ])
  assert_eq(result.changes[0].mapping.original, LineRange(2, 2))
  assert_eq(result.changes[0].mapping.modified, LineRange(2, 4))
  assert_eq(result.changes[1].mapping.modified, LineRange(4, 5))
  assert_eq(result.changes[2].mapping.modified, LineRange(5, 6))
}

///|
test "fragment adapter does not merge away overlapping ignored hunks" {
  let old : @mbtdiff.DiffLine = {
    index: 0,
    segments: [{ kind: Ignored, text: "// old", }],
  }
  let new : @mbtdiff.DiffLine = {
    index: 0,
    segments: [{ kind: Ignored, text: "// new", }],
  }
  let hunk : @mbtdiff.DiffHunk = {
    old_start: 0,
    old_len: 1,
    new_start: 0,
    new_len: 1,
    blocks: [IgnoredBlock([Paired(old, new)])],
  }
  assert_true(
    fragment_document_diff({ hunks: [hunk, hunk], }, "// old", "// new") is None,
  )
}

///|
test "sparse fragments align ignored prefix middle and suffix at unchanged anchors" {
  let hunks : Array[@mbtdiff.DiffHunk] = [
    for
      (old_index, new_index, old_text, new_text) in [
        (1, 2, "old-a", "new-a"),
        (5, 5, "old-b", "new-b"),
      ] => {
      {
        old_start: old_index,
        old_len: 1,
        new_start: new_index,
        new_len: 1,
        blocks: [
          ChangeBlock([
            Paired(
              changed_line(old_index, "", old_text, ""),
              changed_line(new_index, "", new_text, ""),
            ),
          ]),
        ],
      }
    }
  ]
  guard fragment_document_diff(
      { hunks, },
      "head\nold-a\nkeep-1\n// removed\nkeep-2\nold-b\ntail",
      "// added\nhead\nnew-a\nkeep-1\nkeep-2\nnew-b\ntail\n// end",
    )
    is Some(result) else {
    fail("expected a complete mapping for the sparse fragment")
  }
  assert_eq(
    result.changes.map(change => {
      (change.kind, change.mapping.original, change.mapping.modified)
    }),
    [
      (Ignored, LineRange(1, 1), LineRange(1, 2)),
      (Visible, LineRange(2, 3), LineRange(3, 4)),
      (Ignored, LineRange(4, 5), LineRange(5, 5)),
      (Visible, LineRange(6, 7), LineRange(6, 7)),
      (Ignored, LineRange(8, 8), LineRange(8, 9)),
    ],
  )
}

///|
test "sparse fragment hunks can share unchanged context" {
  let shared : @mbtdiff.DiffBlock = ContextBlock([
    { old_index: 2, new_index: 3, text: "shared", },
  ])
  let document : @mbtdiff.HunkDocument = {
    hunks: [
      {
        old_start: 1,
        old_len: 2,
        new_start: 2,
        new_len: 2,
        blocks: [
          ChangeBlock([
            Paired(
              changed_line(1, "", "old-a", ""),
              changed_line(2, "", "new-a", ""),
            ),
          ]),
          shared,
        ],
      },
      {
        old_start: 2,
        old_len: 2,
        new_start: 3,
        new_len: 2,
        blocks: [
          shared,
          ChangeBlock([
            Paired(
              changed_line(3, "", "old-b", ""),
              changed_line(4, "", "new-b", ""),
            ),
          ]),
        ],
      },
    ],
  }
  guard fragment_document_diff(
      document, "// pre\nold-a\nshared\nold-b\ntail", "// pre\n// added\nnew-a\nshared\nnew-b\ntail",
    )
    is Some(result) else {
    fail("expected overlapping context to remain valid")
  }
  assert_eq(
    result.changes.map(change => {
      (change.kind, change.mapping.original, change.mapping.modified)
    }),
    [
      (Ignored, LineRange(2, 2), LineRange(2, 3)),
      (Visible, LineRange(2, 3), LineRange(3, 4)),
      (Visible, LineRange(4, 5), LineRange(5, 6)),
    ],
  )
}

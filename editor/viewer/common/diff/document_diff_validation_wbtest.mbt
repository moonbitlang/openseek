///|
test "document diff validation canonicalizes newline anchors idempotently" {
  let original = @model.TextSnapshot("deleted\n\nkeep")
  let modified = @model.TextSnapshot("\nkeep")
  let raw : DocumentDiff = {
    changes: [
      DocumentDiffChange(
        DetailedLineRangeMapping(
          LineRange(1, 2),
          LineRange(1, 1),
          Some([RangeMapping(Range(1, 1, 1, 8), Range(1, 1, 1, 1))]),
        ),
      ),
    ],
  }
  guard normalize_and_validate_document_diff(raw, original, modified)
    is Some(canonical) else {
    fail("expected canonical pure-deletion mapping")
  }
  guard canonical.changes[0].mapping.inner_changes is Some([inner]) else {
    fail("expected one canonical inner mapping")
  }
  assert_eq(inner.original, Range(1, 1, 2, 1))
  assert_eq(inner.modified, Range(1, 1, 2, 1))
  assert_eq(
    normalize_and_validate_document_diff(canonical, original, modified),
    Some(canonical),
  )
}

///|
test "document diff validation rejects overlapping visible and ignored changes" {
  let original = @model.TextSnapshot("fn stable() {}")
  let modified = @model.TextSnapshot(
    "/// ignored before\nfn inserted() {}\n/// ignored after\nfn stable() {}",
  )
  let invalid : DocumentDiff = {
    changes: [
      DocumentDiffChange(
        DetailedLineRangeMapping(LineRange(1, 1), LineRange(1, 4), None),
        kind=Ignored,
      ),
      DocumentDiffChange(
        DetailedLineRangeMapping(LineRange(1, 1), LineRange(2, 3), None),
      ),
    ],
  }
  assert_true(
    normalize_and_validate_document_diff(invalid, original, modified) is None,
  )
}

///|
test "document diff validation accepts interleaved visible and ignored changes" {
  let original = @model.TextSnapshot("fn stable() {}")
  let modified = @model.TextSnapshot(
    "/// ignored before\nfn inserted() {}\n/// ignored after\nfn stable() {}",
  )
  let valid : DocumentDiff = {
    changes: [
      DocumentDiffChange(
        DetailedLineRangeMapping(LineRange(1, 1), LineRange(1, 2), None),
        kind=Ignored,
      ),
      DocumentDiffChange(
        DetailedLineRangeMapping(LineRange(1, 1), LineRange(2, 3), None),
      ),
      DocumentDiffChange(
        DetailedLineRangeMapping(LineRange(1, 1), LineRange(3, 4), None),
        kind=Ignored,
      ),
    ],
  }
  assert_eq(
    normalize_and_validate_document_diff(valid, original, modified),
    Some(valid),
  )
}

///|
test "document diff validation rejects invalid provider coordinates" {
  let original = @model.TextSnapshot("old\nkeep")
  let modified = @model.TextSnapshot("new\nkeep")
  let invalid : DocumentDiff = {
    changes: [
      DocumentDiffChange(
        DetailedLineRangeMapping(
          LineRange(1, 2),
          LineRange(1, 2),
          Some([RangeMapping(Range(1, 1, 99, 1), Range(1, 1, 99, 1))]),
        ),
      ),
    ],
  }
  assert_true(
    normalize_and_validate_document_diff(invalid, original, modified) is None,
  )
}

///|
test "visibility never bypasses document mapping validation" {
  let source = @model.TextSnapshot("a\nb\nc")
  for kind in [Visible, Ignored] {
    let adjacent : DocumentDiff = {
      changes: [
        DocumentDiffChange(
          DetailedLineRangeMapping(LineRange(1, 2), LineRange(1, 2), None),
          kind~,
        ),
        DocumentDiffChange(
          DetailedLineRangeMapping(LineRange(2, 3), LineRange(2, 3), None),
          kind~,
        ),
      ],
    }
    assert_true(
      normalize_and_validate_document_diff(adjacent, source, source) is None,
    )
    let invalid : DocumentDiff = {
      changes: [
        DocumentDiffChange(
          DetailedLineRangeMapping(
            LineRange(1, 2),
            LineRange(1, 2),
            Some([RangeMapping(Range(1, 1, 1, 99), Range(1, 1, 1, 2))]),
          ),
          kind~,
        ),
      ],
    }
    assert_true(
      normalize_and_validate_document_diff(invalid, source, source) is None,
    )
  }
  let unordered : DocumentDiff = {
    changes: [
      DocumentDiffChange(
        DetailedLineRangeMapping(LineRange(2, 3), LineRange(2, 3), None),
        kind=Ignored,
      ),
      DocumentDiffChange(
        DetailedLineRangeMapping(LineRange(1, 2), LineRange(1, 2), None),
      ),
    ],
  }
  assert_true(
    normalize_and_validate_document_diff(unordered, source, source) is None,
  )
  let unequal_gap : DocumentDiff = {
    changes: [
      DocumentDiffChange(
        DetailedLineRangeMapping(LineRange(1, 2), LineRange(1, 2), None),
        kind=Ignored,
      ),
      DocumentDiffChange(
        DetailedLineRangeMapping(LineRange(3, 4), LineRange(2, 3), None),
      ),
    ],
  }
  assert_true(
    normalize_and_validate_document_diff(unequal_gap, source, source) is None,
  )
}

///|
test "document diff accepts the EOF newline anchor but rejects consuming unchanged preceding text" {
  let original = @model.TextSnapshot("keep\ntail")
  let modified = @model.TextSnapshot("keep")
  let removed : DocumentDiff = {
    changes: [
      DocumentDiffChange(
        DetailedLineRangeMapping(
          LineRange(2, 3),
          LineRange(2, 2),
          Some([RangeMapping(Range(1, 5, 2, 5), Range(1, 5, 1, 5))]),
        ),
      ),
    ],
  }
  assert_eq(
    normalize_and_validate_document_diff(removed, original, modified),
    Some(removed),
  )
  let added : DocumentDiff = {
    changes: [
      DocumentDiffChange(
        DetailedLineRangeMapping(
          LineRange(2, 2),
          LineRange(2, 3),
          Some([RangeMapping(Range(1, 5, 1, 5), Range(1, 5, 2, 5))]),
        ),
      ),
    ],
  }
  assert_eq(
    normalize_and_validate_document_diff(added, modified, original),
    Some(added),
  )
  let invalid : DocumentDiff = {
    changes: [
      DocumentDiffChange(
        DetailedLineRangeMapping(
          LineRange(2, 3),
          LineRange(2, 2),
          Some([RangeMapping(Range(1, 4, 2, 5), Range(1, 5, 1, 5))]),
        ),
      ),
    ],
  }
  assert_true(
    normalize_and_validate_document_diff(invalid, original, modified) is None,
  )
}

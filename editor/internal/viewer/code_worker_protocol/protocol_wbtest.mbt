///|
test "worker diff transport preserves normalized UTF16 mappings and ignored changes" {
  for
    (a, b, ignore_trim_whitespace) in [
      ("a\r\n😀x\r\ntail\n", "a\n😀y\nnew\ntail\n", false),
      ("  alpha\nbeta\n", "alpha\nbeta\n", true),
      ("", "inserted\n", false),
    ] {
    let original = @model.TextSnapshot(a)
    let modified = @model.TextSnapshot(b)
    let expected = @diff.LineDocumentDiffProvider().compute_diff(
      original,
      modified,
      { ignore_trim_whitespace, },
    )
    let response : CodeWorkerResponse = @json.from_json(
      @json.parse(encode_diff(expected).to_json().stringify()),
    )
    guard response is Diff(changes) else { fail("expected diff result") }
    let decoded = decode_diff(changes)
    assert_eq(decoded, expected)
    assert_eq(
      @diff.normalize_and_validate_document_diff(decoded, original, modified),
      Some(expected),
    )
  }
}

///|
test "worker folding transport preserves range types without sharing collapse state" {
  let expected = @folding_browser.FoldingRegions::from_fold_ranges([
    FoldRange(1, 8, type_="moonbit-outline"),
    FoldRange(3, 5),
  ])
  let response : CodeWorkerResponse = @json.from_json(
    @json.parse(
      CodeWorkerResponse::Folding(encode_folds(expected), None)
      .to_json()
      .stringify(),
    ),
  )
  guard response is Folding(ranges, None) else {
    fail("expected folding result")
  }
  let decoded = decode_folds(ranges)
  assert_eq(decoded.length(), 2)
  assert_eq(decoded.to_fold_range(0), expected.to_fold_range(0))
  assert_eq(decoded.to_fold_range(1), expected.to_fold_range(1))
  assert_eq(decoded.get_type(0), Some("moonbit-outline"))
  assert_eq(decoded.get_type(1), None)
  assert_false(physical_equal(expected, decoded))
}

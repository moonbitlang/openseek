///|
test "model uris round-trip the absolute path" {
  for path in ["/ws/my proj/src/a b.mbt", "/tmp/中文/x.mbt", "C:/ws/a.mbt"] {
    let minted = model_uri_of(Absolute(path))
    assert_true(model_uri_path(minted) == Some(Absolute(path)))
    // The ModelUri string form re-parses to the same document key — the
    // `remove_editor_feedback` path. Monaco's string form normalizes the
    // Windows drive letter's case, so the key, not the path bytes, is what
    // must survive this leg.
    let reparsed = @common.Uri::parse(ModelUri::of(Absolute(path)).0)
    assert_eq(reparsed.to_string(), minted.to_string())
    assert_true(model_uri_path(reparsed) is Some(_))
  }
}

///|
test "foreign uris do not parse as model paths" {
  assert_true(model_uri_path(@common.Uri::parse("untitled:one")) is None)
  assert_true(model_uri_path(@common.Uri::file("/a.bin")) is None)
  assert_true(model_uri_path(app_uri("openseek-notice", "/a.bin")) is None)
}

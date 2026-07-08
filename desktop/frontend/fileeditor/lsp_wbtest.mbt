///|
test "model uris round-trip the absolute path" {
  for path in ["/ws/my proj/src/a b.mbt", "/tmp/中文/x.mbt", "C:/ws/a.mbt"] {
    assert_true(
      parse_model_uri(ModelUri::of(Absolute(path)).0) == Some(Absolute(path)),
    )
  }
}

///|
test "foreign uris do not parse as model paths" {
  assert_true(parse_model_uri("untitled:one") is None)
  assert_true(parse_model_uri("openseek://") is None)
  assert_true(parse_model_uri("openseek-notice://a.bin") is None)
}

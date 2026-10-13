///|
fn remote_language_test_uri(path : String) -> @base_common.Uri {
  try! @base_common.Uri::parse("readonly-remote://workspace/\{path}")
}

///|
fn remote_language_test_model(
  uri : @base_common.Uri,
  version : Int32,
  revision : String,
  text : String,
) -> @model.TextModel {
  TextModel(uri, "main.mbt", "moonbit", version, revision, text)
}

///|
fn remote_language_test_diagnostic(message : String) -> @language.Diagnostic {
  { range: Range(1, 1, 1, 2), severity: Warning, message, tags: None, }
}

///|
fn remote_language_test_hover(message : String) -> @language.Hover {
  { range: Range(1, 1, 1, 2), contents: [PlainText(message)], }
}

///|
test "remote diagnostics require the exact live model generation" {
  let markers = @markers.MarkerService()
  let freshness = RemoteLanguageFreshness(markers)
  let uri = remote_language_test_uri("src/main.mbt")
  let model = remote_language_test_model(uri, 1, "rev-1", "a")
  defer {
    freshness.invalidate()
    model.dispose()
    markers.dispose()
  }
  freshness.note_document(model)
  let payload : @remote_protocol.DiagnosticsPayload = {
    uri,
    revision: "rev-1",
    diagnostics: [remote_language_test_diagnostic("fresh")],
  }
  guard freshness.prepare_diagnostics(payload) is Some(stamp) else {
    fail("expected an exact diagnostic stamp")
  }
  assert_true(freshness.apply_diagnostics(stamp, payload))
  assert_eq(markers.diagnostics_for_resource(uri).length(), 1)
  model.set_value("b")
  assert_false(freshness.apply_diagnostics(stamp, payload))
  assert_eq(markers.diagnostics_for_resource(uri).length(), 0)
}

///|
test "remote model invalidation clears only moon markers" {
  let markers = @markers.MarkerService()
  let freshness = RemoteLanguageFreshness(markers)
  let uri = remote_language_test_uri("src/owners.mbt")
  let model = remote_language_test_model(uri, 1, "rev", "a")
  defer {
    freshness.invalidate()
    model.dispose()
    markers.dispose()
  }
  markers.set_diagnostics("moon", uri, [remote_language_test_diagnostic("moon")])
  markers.set_diagnostics("other", uri, [
    remote_language_test_diagnostic("other"),
  ])
  freshness.note_document(model)
  let live = markers.markers_for_resource(uri)
  assert_eq(live.length(), 1)
  assert_eq(live[0].owner, "other")
  model.set_value("changed")
  let after_change = markers.markers_for_resource(uri)
  assert_eq(after_change.length(), 1)
  assert_eq(after_change[0].owner, "other")
}

///|
test "same URI and revision replacement rejects deferred remote work" {
  let markers = @markers.MarkerService()
  let freshness = RemoteLanguageFreshness(markers)
  let uri = remote_language_test_uri("src/replaced.mbt")
  let first = remote_language_test_model(uri, 1, "same-revision", "old")
  let replacement = remote_language_test_model(uri, 2, "same-revision", "new")
  defer {
    freshness.invalidate()
    first.dispose()
    replacement.dispose()
    markers.dispose()
  }
  freshness.note_document(first)
  let diagnostics : @remote_protocol.DiagnosticsPayload = {
    uri,
    revision: "same-revision",
    diagnostics: [remote_language_test_diagnostic("old")],
  }
  guard freshness.prepare_diagnostics(diagnostics) is Some(old_stamp) else {
    fail("expected the first generation")
  }
  freshness.note_document(replacement)
  assert_false(freshness.apply_diagnostics(old_stamp, diagnostics))
  let hover : @remote_protocol.HoverResultPayload = {
    id: "hover-1",
    uri,
    revision: "same-revision",
    hover: Some(remote_language_test_hover("old")),
  }
  assert_true(freshness.accept_hover(old_stamp, hover) is None)
  guard freshness.capture_model(replacement) is Some(new_stamp) else {
    fail("expected the replacement generation")
  }
  assert_true(freshness.accept_hover(new_stamp, hover) is Some(_))
}

///|
test "remote payload URI and revision mismatches are rejected" {
  let markers = @markers.MarkerService()
  let freshness = RemoteLanguageFreshness(markers)
  let uri = remote_language_test_uri("src/main.mbt")
  let other_uri = remote_language_test_uri("src/other.mbt")
  let model = remote_language_test_model(uri, 1, "rev-1", "a")
  defer {
    freshness.invalidate()
    model.dispose()
    markers.dispose()
  }
  freshness.note_document(model)
  guard freshness.capture_model(model) is Some(stamp) else {
    fail("expected current model")
  }
  let wrong_revision : @remote_protocol.HoverResultPayload = {
    id: "hover-1",
    uri,
    revision: "rev-2",
    hover: Some(remote_language_test_hover("wrong revision")),
  }
  let wrong_uri : @remote_protocol.HoverResultPayload = {
    id: "hover-2",
    uri: other_uri,
    revision: "rev-1",
    hover: Some(remote_language_test_hover("wrong uri")),
  }
  assert_true(freshness.accept_hover(stamp, wrong_revision) is None)
  assert_true(freshness.accept_hover(stamp, wrong_uri) is None)
}

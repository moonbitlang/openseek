///|
fn source_preparation_test_fixture(
  document : @common.Uri,
) -> (SourcePreparation, @markers.MarkerService, @common.Disposable) {
  let previous_services = viewer_state.services
  let previous_document = viewer_state.document
  let previous_live = viewer_state.live
  cancel_source_preparation()
  let markers = @markers.MarkerService(schedule=action => action())
  let services : DesktopViewerServices = {
    viewer_services: @viewer.ViewerServices(),
    markers,
    feedback: @feedback.DesktopFeedbackService(),
    quick_diff: DesktopQuickDiffService(),
    _navigation_registrations: [],
    _code_lens_registration: @common.Disposable::from(() => ()),
  }
  viewer_state.services = Some(services)
  viewer_state.document = None
  viewer_state.live = false
  let cache = SourceModelCache()
  let lease = cache.acquire(
    { owner: { channel: Local, session: "preparation-test", }, root: None, },
    document,
    model_uri_of(document),
    "fn main {}",
    () => {
      @model.TextModel(
        model_uri_of(document),
        "main.mbt",
        "moonbit",
        1,
        "1",
        "fn main {}",
      )
    },
  )
  let preparation : SourcePreparation = {
    lease,
    channel: Local,
    document,
    live: true,
    generation: viewer_state.show_generation,
    diagnostics: None,
    job: None,
  }
  viewer_state.source_preparation = Some(preparation)
  let cleanup = @common.Disposable::from(() => {
    cancel_source_preparation()
    lease.dispose()
    cache.clear()
    markers.dispose()
    services.viewer_services.dispose()
    viewer_state.services = previous_services
    viewer_state.document = previous_document
    viewer_state.live = previous_live
  })
  (preparation, markers, cleanup)
}

///|
fn source_preparation_test_diagnostic(
  message : String,
) -> @protocol.LspDiagnostic {
  {
    range: {
      start: { line: 0, character: 3, },
      end: { line: 0, character: 7, },
    },
    message,
    severity: Some(1),
    tags: None,
  }
}

///|
test "source preparation applies the latest early diagnostics only after commit" {
  let document = try! @common.Uri::parse("openseek://local/work/main.mbt")
  let uri = model_uri_of(document)
  // An explicitly empty publish is also the newest complete batch: it must
  // clear earlier markers rather than being mistaken for no pending reply.
  for latest in [[source_preparation_test_diagnostic("latest")], []] {
    let (preparation, markers, cleanup) = source_preparation_test_fixture(
      document,
    )
    defer cleanup.dispose()
    let previous = [source_preparation_test_diagnostic("previous")]
    markers.set_diagnostics(
      DiagnosticsOwner,
      uri,
      DiagnosticsProjection(previous).to_viewer(),
    )
    apply_diagnostics_now(Local, document, [
      source_preparation_test_diagnostic("loaded"),
    ])
    apply_diagnostics_now(Local, document, latest)
    assert_eq(
      markers.diagnostics_for_resource(uri),
      DiagnosticsProjection(previous).to_viewer(),
    )
    let mut committed = false
    preparation.finish(
      Ok(()),
      () => {
        committed = true
        viewer_state.document = Some(document)
        viewer_state.live = true
      },
      _ => (),
    )
    assert_true(committed)
    assert_eq(
      markers.diagnostics_for_resource(uri),
      DiagnosticsProjection(latest).to_viewer(),
    )
    // Once attached, later publishes keep their ordinary immediate path.
    apply_diagnostics_now(Local, document, previous)
    assert_eq(
      markers.diagnostics_for_resource(uri),
      DiagnosticsProjection(previous).to_viewer(),
    )
  }
}

///|
test "source preparation diagnostics do not cross resources or a canceled show" {
  let first = try! @common.Uri::parse("openseek://local/work/first.mbt")
  let second = try! @common.Uri::parse("openseek://local/work/second.mbt")
  let (old, _, old_cleanup) = source_preparation_test_fixture(first)
  defer old_cleanup.dispose()
  apply_diagnostics_now(Local, first, [
    source_preparation_test_diagnostic("old"),
  ])
  let (current, markers, cleanup) = source_preparation_test_fixture(second)
  defer cleanup.dispose()
  apply_diagnostics_now(Local, first, [
    source_preparation_test_diagnostic("wrong file"),
  ])
  apply_diagnostics_now(Remote("other"), second, [
    source_preparation_test_diagnostic("wrong channel"),
  ])
  assert_true(current.diagnostics is None)
  let mut old_committed = false
  old.finish(Ok(()), () => old_committed = true, _ => ())
  assert_false(old_committed)
  assert_true(
    viewer_state.source_preparation is Some(pending) &&
    physical_equal(pending, current),
  )
  let latest = [source_preparation_test_diagnostic("current")]
  apply_diagnostics_now(Local, second, latest)
  current.finish(
    Ok(()),
    () => {
      viewer_state.document = Some(second)
      viewer_state.live = true
    },
    _ => (),
  )
  assert_eq(markers.diagnostics_for_resource(model_uri_of(first)), [])
  assert_eq(
    markers.diagnostics_for_resource(model_uri_of(second)),
    DiagnosticsProjection(latest).to_viewer(),
  )
}

///|
test "failed source preparation discards early diagnostics without committing" {
  let document = try! @common.Uri::parse("openseek://local/work/main.mbt")
  let (preparation, markers, cleanup) = source_preparation_test_fixture(
    document,
  )
  defer cleanup.dispose()
  apply_diagnostics_now(Local, document, [
    source_preparation_test_diagnostic("early"),
  ])
  let mut committed = false
  let mut failed = false
  preparation.finish(Err(Computation), () => committed = true, _ => {
    failed = true
  })
  assert_false(committed)
  assert_true(failed)
  assert_true(viewer_state.source_preparation is None)
  assert_true(viewer_state.document is None)
  assert_false(viewer_state.live)
  assert_eq(markers.diagnostics_for_resource(model_uri_of(document)), [])
}

///|
/// White-box marker-handle coverage.
test "MarkerServiceHandle forwards only borrowed store operations" {
  let markers = MarkerService()
  let handle = markers.marker_service_handle()
  let uri = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/handle-store.mbt",
  )
  let changed : Array[Array[@base_common.Uri]] = []
  let subscription = handle.on_did_change_markers(resources => {
    changed.push(resources)
  })
  markers.change_one("owner", uri, [
    MarkerData(
      severity=Error,
      message="diagnostic",
      start_line_number=1,
      start_column=1,
      end_line_number=1,
      end_column=2,
    ),
  ])
  assert_eq(changed.length(), 1)
  let live = handle.read(MarkerReadOptions(resource=uri))
  assert_eq(live.length(), 1)
  assert_eq(live[0].message, "diagnostic")
  handle.remove("owner", [uri])
  assert_eq(changed.length(), 2)
  assert_eq(handle.read(MarkerReadOptions(resource=uri)).length(), 0)
  subscription.dispose()
  markers.dispose()
}

///|
test "MarkerDecorationsHandle preserves model leases and change events" {
  let markers = MarkerService()
  let marker_service_handle = markers.marker_service_handle()
  let source : MarkerDecorationsSource = MarkerStore(marker_service_handle)
  guard source is MarkerStore(_) else { fail("expected marker store source") }
  let service = MarkerDecorationsService(marker_service_handle)
  let handle = service.marker_decorations_handle()
  let adapted : MarkerDecorationsSource = Decorations(handle)
  guard adapted is Decorations(_) else { fail("expected decorations source") }
  let uri = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/handle-decorations.mbt",
  )
  let model = @model.TextModel(
    uri, "handle-decorations.mbt", "moonbit", 1, "rev", "diagnostic text",
  )
  let changed : Array[Int32] = []
  let subscription = handle.on_did_change_marker_decorations(changed_model => {
    changed.push(changed_model.identity())
  })
  let lease = handle.acquire_model(model)
  markers.change_one("owner", uri, [
    MarkerData(
      severity=Error,
      message="error",
      start_line_number=1,
      start_column=2,
      end_line_number=1,
      end_column=4,
    ),
    MarkerData(
      severity=Warning,
      message="projected",
      start_line_number=1,
      start_column=1,
      end_line_number=1,
      end_column=11,
    ),
    MarkerData(
      severity=Hint,
      message="unnecessary",
      start_line_number=1,
      start_column=3,
      end_line_number=1,
      end_column=5,
      tags=[Unnecessary],
    ),
    MarkerData(
      severity=Hint,
      message="deprecated",
      start_line_number=1,
      start_column=4,
      end_line_number=1,
      end_column=6,
      tags=[Deprecated],
    ),
  ])
  assert_eq(changed, [model.identity()])
  let live = handle.get_live_markers_for_model(model)
  assert_eq(live.length(), 4)
  let resolved = handle.get_live_resolved_marker_decorations_for_model(model)
  assert_eq(resolved.length(), 4)
  // z=0 first; the empty Deprecated class precedes Unnecessary in JS
  // lexicographic order. Warning/Error then follow their z=20/30 policy.
  assert_eq(resolved.map(item => item.marker.message), [
    "deprecated", "unnecessary", "projected", "error",
  ])
  assert_eq(resolved.map(item => item.options.z_index), [0, 0, 20, 30])
  assert_eq(resolved[0].options.class_name, "")
  assert_eq(
    resolved[0].options.inline_class_name,
    Some("squiggly-inline-deprecated"),
  )
  assert_eq(resolved[1].options.class_name, "squiggly-unnecessary")
  assert_eq(
    resolved[1].options.inline_class_name,
    Some("squiggly-inline-unnecessary"),
  )
  assert_eq(resolved[2].options.class_name, "squiggly-warning")
  lease.dispose()
  assert_eq(handle.get_live_markers_for_model(model).length(), 0)
  subscription.dispose()
  service.dispose()
  markers.dispose()
  model.dispose()
}

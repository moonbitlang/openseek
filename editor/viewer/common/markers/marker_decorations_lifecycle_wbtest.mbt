///|
fn lifecycle_uri(scheme : String, path : String) -> @base_common.Uri {
  try! @base_common.Uri::from(scheme~, authority="model", path~)
}

///|
fn lifecycle_model(
  uri : @base_common.Uri,
  name : String,
  text : String,
) -> @model.TextModel {
  TextModel(uri, name, "moonbit", 1, "rev", text)
}

///|
fn marker_model_decorations(
  model : @model.TextModel,
) -> Array[@model.ModelDecoration] {
  model.get_decorations_in_range(model.get_full_model_range())
}

///|
fn lifecycle_marker(
  message : String,
  start_column? : Int = 1,
  end_column? : Int = 2,
) -> MarkerData {
  MarkerData(
    severity=Error,
    message~,
    start_line_number=1,
    start_column~,
    end_line_number=1,
    end_column~,
  )
}

///|
test "preloaded markers seed once and same-identity leases refcount" {
  let markers = MarkerService()
  let uri = lifecycle_uri("inmemory", "/preload.mbt")
  markers.change_one("host", uri, [lifecycle_marker("preloaded")])
  let service = MarkerDecorationsService(markers.marker_service_handle())
  let model = lifecycle_model(uri, "preload.mbt", "alpha")
  let changed : Array[Int] = []
  let changed_subscription = service.on_did_change_marker_decorations(m => {
    changed.push(m.identity())
  })

  let first = service.acquire_model(model)
  assert_eq(marker_model_decorations(model).length(), 1)
  assert_true(changed == [model.identity()])
  let second = service.acquire_model(model)
  assert_eq(service.model_registrations.length(), 1)
  assert_eq(
    service.model_registrations.get(model.identity()).unwrap().ref_count,
    2,
  )
  assert_true(
    service.model_ids_by_uri.get(uri.to_string()).unwrap() == [model.identity()],
  )
  assert_eq(changed.length(), 1)

  // Release the later lease first (the root Viewer integration covers the
  // opposite order); either handle independently decrements once.
  second.dispose()
  second.dispose()
  assert_eq(
    service.model_registrations.get(model.identity()).unwrap().ref_count,
    1,
  )
  assert_eq(marker_model_decorations(model).length(), 1)
  first.dispose()
  assert_eq(service.model_registrations.length(), 0)
  assert_eq(service.model_ids_by_uri.length(), 0)
  assert_eq(marker_model_decorations(model).length(), 0)
  // Ordinary release never owns the host's diagnostics, even for a transient
  // URI. A later lease for the still-live identity re-seeds the same host data
  // in a fresh owner, without any historical watch or ordering entry.
  assert_eq(markers.read(MarkerReadOptions(resource=uri)).length(), 1)
  let reattached = service.acquire_model(model)
  assert_eq(marker_model_decorations(model).length(), 1)
  assert_eq(service.model_registrations.length(), 1)
  reattached.dispose()
  assert_eq(marker_model_decorations(model).length(), 0)
  // The final release removed the new model-dispose watch too, so later host
  // disposal is unseen and cannot run transient cleanup.
  model.dispose()
  assert_eq(markers.read(MarkerReadOptions(resource=uri)).length(), 1)
  changed_subscription.dispose()
  service.dispose()
}

///|
test "set_value refreshes one owner once without acquiring another lease" {
  let markers = MarkerService()
  let uri = lifecycle_uri("file", "/set-value.mbt")
  markers.change_one("host", uri, [lifecycle_marker("stable")])
  let service = MarkerDecorationsService(markers.marker_service_handle())
  let model = lifecycle_model(uri, "set-value.mbt", "before")
  let first = service.acquire_model(model)
  let second = service.acquire_model(model)
  let old_id = marker_model_decorations(model)[0].id
  let events : Array[Int] = []
  let event_subscription = service.on_did_change_marker_decorations(changed => {
    events.push(changed.identity())
  })

  model.set_value("after")
  assert_true(events == [model.identity()])
  assert_eq(marker_model_decorations(model).length(), 1)
  assert_false(marker_model_decorations(model)[0].id == old_id)
  assert_eq(
    service.model_registrations.get(model.identity()).unwrap().ref_count,
    2,
  )
  first.dispose()
  assert_eq(
    service.model_registrations.get(model.identity()).unwrap().ref_count,
    1,
  )
  second.dispose()
  assert_eq(service.model_registrations.length(), 0)
  event_subscription.dispose()
  service.dispose()
}

///|
test "lease release disposes owner before deleting registration indexes" {
  let markers = MarkerService()
  let uri = lifecycle_uri("file", "/release-order.mbt")
  markers.change_one("host", uri, [lifecycle_marker("ordered")])
  let service = MarkerDecorationsService(markers.marker_service_handle())
  let model = lifecycle_model(uri, "release-order.mbt", "alpha")
  let lease = service.acquire_model(model)
  let saw_source_order = Ref(false)
  let model_subscription = model.on_did_change_decorations(_ => {
    match service.model_registrations.get(model.identity()) {
      Some(registration) =>
        saw_source_order.val = !registration.active &&
          registration.content_subscription is None &&
          registration.dispose_subscription is None &&
          service.model_ids_by_uri.contains(uri.to_string())
      None => ()
    }
  })

  lease.dispose()
  assert_true(saw_source_order.val)
  assert_false(service.model_registrations.contains(model.identity()))
  assert_false(service.model_ids_by_uri.contains(uri.to_string()))
  model_subscription.dispose()
  model.dispose()
  service.dispose()
}

///|
test "reentrant marker updates drain after the active decoration delta" {
  let markers = MarkerService()
  let uri = lifecycle_uri("file", "/nested-update.mbt")
  markers.change_one("host", uri, [lifecycle_marker("before")])
  let service = MarkerDecorationsService(markers.marker_service_handle())
  let model = lifecycle_model(uri, "nested-update.mbt", "alpha")
  let lease = service.acquire_model(model)
  let mut reentered = false
  let model_subscription = model.on_did_change_decorations(_ => {
    if !reentered {
      reentered = true
      markers.change_one("host", uri, [lifecycle_marker("nested")])
      // MicrotaskEmitter deliberately drops an event re-fired during its own
      // flush. Invoke the same service ingress directly to exercise the
      // synchronous model-decoration reentrancy seam deterministically.
      service.handle_marker_change([uri])
    }
  })
  let mut outward_events = 0
  let outward_subscription = service.on_did_change_marker_decorations(_ => {
    outward_events += 1
  })

  markers.change_one("host", uri, [lifecycle_marker("outer")])
  assert_true(reentered)
  assert_eq(outward_events, 2)
  assert_eq(marker_model_decorations(model).length(), 1)
  let live = service.get_live_markers_for_model(model)
  assert_eq(live.length(), 1)
  assert_eq(live[0].1.message, "nested")
  let registration = service.model_registrations.get(model.identity()).unwrap()
  assert_eq(registration.marker_decorations.entries.length(), 1)
  assert_false(registration.update_in_progress)
  assert_false(registration.update_requested)

  outward_subscription.dispose()
  model_subscription.dispose()
  lease.dispose()
  service.dispose()
}

///|
fn assert_active_model_dispose_cleanup(
  scheme : String,
  cleans : Bool,
) -> Unit raise {
  let markers = MarkerService()
  let uri = lifecycle_uri(scheme, "/active-dispose.mbt")
  markers.change_one("host", uri, [lifecycle_marker("owned by host")])
  let service = MarkerDecorationsService(markers.marker_service_handle())
  let model = lifecycle_model(uri, "active-dispose.mbt", "value")
  let lease = service.acquire_model(model)
  let saw_source_order = Ref(false)
  let model_subscription = model.on_did_change_decorations(_ => {
    match service.model_registrations.get(model.identity()) {
      Some(registration) =>
        saw_source_order.val = !registration.active &&
          service.model_ids_by_uri.contains(uri.to_string())
      None => ()
    }
  })
  model.dispose()
  assert_true(saw_source_order.val)
  assert_eq(service.model_registrations.length(), 0)
  assert_eq(service.model_ids_by_uri.length(), 0)
  assert_eq(
    markers.read(MarkerReadOptions(resource=uri)).length(),
    if cleans {
      0
    } else {
      1
    },
  )
  lease.dispose()
  model_subscription.dispose()
  service.dispose()
}

///|
test "only active transient ModelDisposed removes diagnostics" {
  assert_active_model_dispose_cleanup("inmemory", true)
  assert_active_model_dispose_cleanup("internal", true)
  assert_active_model_dispose_cleanup("vscode", true)
  assert_active_model_dispose_cleanup("file", false)
}

///|
test "transient cleanup waits for the last same-URI identity" {
  let markers = MarkerService()
  let uri = lifecycle_uri("inmemory", "/shared-transient.mbt")
  markers.change_one("host", uri, [lifecycle_marker("shared")])
  let service = MarkerDecorationsService(markers.marker_service_handle())
  let model_a = lifecycle_model(uri, "a.mbt", "alpha")
  let model_b = lifecycle_model(uri, "b.mbt", "beta")
  let lease_a = service.acquire_model(model_a)
  let lease_b = service.acquire_model(model_b)

  model_a.dispose()
  assert_eq(markers.read(MarkerReadOptions(resource=uri)).length(), 1)
  assert_eq(service.get_live_markers_for_model(model_b).length(), 1)
  model_b.dispose()
  assert_eq(markers.read(MarkerReadOptions(resource=uri)).length(), 0)
  lease_a.dispose()
  lease_b.dispose()
  service.dispose()
}

///|
fn definition_navigation_test_uri(name : String) -> @base_common.Uri {
  try! @base_common.Uri::parse("readonly-remote://workspace/src/\{name}.mbt")
}

///|
extend RemoteLanguageClient with @language.DefinitionProvider::{
  provide_definition,
}

///|
extend RemoteLanguageClient with @language.ReferencesProvider::{
  provide_references,
}

///|
test "preview references share one host model and retire it after the final lease" {
  let uri = definition_navigation_test_uri("lease-target")
  let model = @model.TextModel(
    uri, "lease-target.mbt", "moonbit", 1, "rev-lease", "let target = 1",
  )
  let state : PreviewResourceState = {
    uri,
    model: Some(model),
    in_flight: 0,
    leases: 0,
    lifecycle: PreviewResourceOpen,
  }
  preview_resources[uri.to_string()] = state

  let first = acquire_preview_reference(state, model)
  let second = acquire_preview_reference(state, model)
  assert_eq(state.leases, 2)
  assert_true(preview_resource_retains_remote_document(uri))
  assert_true(first.model().same(second.model()))

  first.dispose()
  first.dispose()
  assert_eq(state.leases, 1)
  assert_false(model.is_disposed())
  assert_true(preview_resources.contains(uri.to_string()))

  second.dispose()
  assert_eq(state.leases, 0)
  assert_true(model.is_disposed())
  assert_false(preview_resources.contains(uri.to_string()))
  assert_false(preview_resource_retains_remote_document(uri))
}

///|
test "preview shutdown waits for real leases and in-flight reads" {
  let leased_uri = definition_navigation_test_uri("shutdown-leased")
  let leased_model = @model.TextModel(
    leased_uri, "shutdown-leased.mbt", "moonbit", 1, "rev-shutdown", "let target = 1",
  )
  let leased_state : PreviewResourceState = {
    uri: leased_uri,
    model: Some(leased_model),
    in_flight: 0,
    leases: 0,
    lifecycle: PreviewResourceOpen,
  }
  preview_resources[leased_uri.to_string()] = leased_state
  let lease = acquire_preview_reference(leased_state, leased_model)

  begin_preview_resource_shutdown(leased_state)
  assert_true(leased_state.lifecycle == PreviewResourceClosing)
  assert_eq(leased_state.leases, 1)
  assert_false(leased_model.is_disposed())
  assert_true(preview_resources.contains(leased_uri.to_string()))

  lease.dispose()
  assert_eq(leased_state.leases, 0)
  assert_true(leased_state.lifecycle == PreviewResourceDisposed)
  assert_true(leased_model.is_disposed())
  assert_false(preview_resources.contains(leased_uri.to_string()))

  let pending_uri = definition_navigation_test_uri("shutdown-pending")
  let pending_state : PreviewResourceState = {
    uri: pending_uri,
    model: None,
    in_flight: 1,
    leases: 0,
    lifecycle: PreviewResourceOpen,
  }
  preview_resources[pending_uri.to_string()] = pending_state
  begin_preview_resource_shutdown(pending_state)
  assert_true(pending_state.lifecycle == PreviewResourceClosing)
  assert_eq(pending_state.in_flight, 1)
  assert_true(preview_resources.contains(pending_uri.to_string()))

  // Simulates the late resolver continuation decrementing its own request.
  pending_state.in_flight -= 1
  retire_preview_resource_if_unused(pending_state)
  assert_true(pending_state.lifecycle == PreviewResourceDisposed)
  assert_false(preview_resources.contains(pending_uri.to_string()))
}

///|
async test "remote definition provider preserves ordered locations and cancellation" {
  let previous_send = protocol_send.val
  let previous_dispatch = workbench_dispatch.val
  let previous_preview_shutdown = preview_resources_shutdown.val
  preview_resources_shutdown.val = false
  let source_uri = definition_navigation_test_uri("definition-source")
  let first_uri = definition_navigation_test_uri("definition-first")
  let second_uri = definition_navigation_test_uri("definition-second")
  let source_model = @model.TextModel(
    source_uri, "definition-source.mbt", "moonbit", 2, "rev-source", "let answer = target",
  )
  let markers = @markers.MarkerService()
  let freshness = RemoteLanguageFreshness(markers)
  freshness.note_document(source_model)
  let client = RemoteLanguageClient::{
    log_service: LogService(logger=@log.NullLogger()),
    freshness,
  }
  let observed_uri = Ref("")
  let observed_revision = Ref("")
  let observed_offset = Ref(-1)
  let unexpected_packet = Ref(false)
  protocol_send.val = Some(packet => {
    match packet {
      Definition(request) => {
        observed_uri.val = request.uri.to_string()
        observed_revision.val = request.document_revision
        observed_offset.val = request.offset
        resolve_pending_response(
          DefinitionResult({
            id: request.id,
            uri: request.uri,
            revision: request.document_revision,
            locations: [
              { uri: first_uri, range: Range(3, 2, 3, 8), },
              { uri: second_uri, range: Range(9, 1, 9, 5), },
            ],
          }),
        )
        |> ignore
      }
      _ => unexpected_packet.val = true
    }
  })
  let locations = client.provide_definition(
    source_model,
    Position(1, 14),
    @language.CancellationToken::none(),
  )
  assert_false(unexpected_packet.val)
  assert_eq(observed_uri.val, source_uri.to_string())
  assert_eq(observed_revision.val, "rev-source")
  assert_eq(observed_offset.val, source_model.get_offset_at(Position(1, 14)))
  assert_eq(locations.length(), 2)
  assert_eq(locations[0].uri.to_string(), first_uri.to_string())
  assert_eq(locations[0].range, Range(3, 2, 3, 8))
  assert_eq(locations[1].uri.to_string(), second_uri.to_string())
  assert_eq(locations[1].range, Range(9, 1, 9, 5))

  let cancelled = @language.CancellationTokenSource()
  let late_response_consumed = Ref(false)
  let cancelled_request_id = Ref("")
  protocol_send.val = Some(packet => {
    match packet {
      Definition(request) => {
        cancelled_request_id.val = request.id
        cancelled.cancel()
      }
      _ => unexpected_packet.val = true
    }
  })
  let cancelled_locations = client.provide_definition(
    source_model,
    Position(1, 14),
    cancelled.token(),
  )
  assert_true(cancelled_locations.is_empty())
  // The local cancellation has resumed the provider. A later server response
  // is consumed through the retained request-id tombstone.
  late_response_consumed.val = resolve_pending_response(
    DefinitionResult({
      id: cancelled_request_id.val,
      uri: source_uri,
      revision: "rev-source",
      locations: [{ uri: first_uri, range: Range(1, 1, 1, 2), }],
    }),
  )
  assert_true(late_response_consumed.val)
  assert_false(unexpected_packet.val)
  freshness.invalidate()
  markers.dispose()

  let preview_uri = definition_navigation_test_uri("definition-preview")
  let preview_open_count = Ref(0)
  let preview_close_count = Ref(0)
  protocol_send.val = Some(packet => {
    match packet {
      OpenDocument(request) => {
        preview_open_count.val += 1
        resolve_pending_response(
          DocumentLoaded({
            id: request.id,
            document: DocumentSnapshot(
              request.uri,
              "definition-preview.mbt",
              "moonbit",
              "rev-preview",
              "let preview = 1",
            ),
          }),
        )
        |> ignore
      }
      CloseDocument(_) => preview_close_count.val += 1
      _ => unexpected_packet.val = true
    }
  })
  guard resolve_preview_model(preview_uri, @language.CancellationToken::none())
    is Some(first_preview) else {
    fail("first preview resolution returned no model")
  }
  guard resolve_preview_model(preview_uri, @language.CancellationToken::none())
    is Some(second_preview) else {
    fail("cached preview resolution returned no model")
  }
  assert_eq(preview_open_count.val, 1)
  assert_true(first_preview.model().same(second_preview.model()))
  let preview_model = first_preview.model()
  first_preview.dispose()
  assert_false(preview_model.is_disposed())
  assert_eq(preview_close_count.val, 0)
  second_preview.dispose()
  assert_true(preview_model.is_disposed())
  assert_eq(preview_close_count.val, 1)
  assert_false(preview_resources.contains(preview_uri.to_string()))

  let opened_uri = Ref("")
  workbench_dispatch.val = Some(msg => {
    match msg {
      OpenDefinitionLocation(location) =>
        opened_uri.val = location.uri.to_string()
      _ => unexpected_packet.val = true
    }
  })
  let opener = workbench_location_opener()
  let open_request : @navigation_api.OpenLocationRequest = {
    source_viewer_id: "definition-test-viewer",
    location: { uri: first_uri, range: Range(3, 2, 3, 8), },
    mode: Current,
  }
  assert_true(opener.open(open_request))
  assert_eq(opened_uri.val, first_uri.to_string())
  assert_false(opener.open({ ..open_request, mode: Side, }))
  assert_false(unexpected_packet.val)

  let shutdown_uri = definition_navigation_test_uri("definition-shutdown")
  let shutdown_open_count = Ref(0)
  let shutdown_close_count = Ref(0)
  let shutdown_saw_real_in_flight = Ref(false)
  protocol_send.val = Some(packet => {
    match packet {
      OpenDocument(request) => {
        shutdown_open_count.val += 1
        match preview_resources.get(request.uri.to_string()) {
          Some(state) =>
            shutdown_saw_real_in_flight.val = state.in_flight == 1 &&
              state.lifecycle == PreviewResourceOpen
          None => ()
        }
        // This is the real synchronous `Viewer::on_did_dispose` boundary:
        // the wire request has started, but its continuation has not resumed.
        shutdown_preview_resources()
        resolve_pending_response(
          DocumentLoaded({
            id: request.id,
            document: DocumentSnapshot(
              request.uri,
              "definition-shutdown.mbt",
              "moonbit",
              "rev-shutdown",
              "let shutdown = 1",
            ),
          }),
        )
        |> ignore
      }
      CloseDocument(_) => shutdown_close_count.val += 1
      _ => unexpected_packet.val = true
    }
  })
  let shutdown_result = resolve_preview_model(
    shutdown_uri,
    @language.CancellationToken::none(),
  )
  assert_true(shutdown_saw_real_in_flight.val)
  assert_true(shutdown_result is None)
  assert_eq(shutdown_open_count.val, 1)
  assert_eq(shutdown_close_count.val, 1)
  assert_false(preview_resources.contains(shutdown_uri.to_string()))

  let rejected_after_shutdown = resolve_preview_model(
    definition_navigation_test_uri("definition-after-shutdown"),
    @language.CancellationToken::none(),
  )
  assert_true(rejected_after_shutdown is None)
  assert_eq(shutdown_open_count.val, 1)
  preview_resources_shutdown.val = previous_preview_shutdown

  protocol_send.val = previous_send
  workbench_dispatch.val = previous_dispatch
  cancelled.dispose()
  source_model.dispose()
}

///|
async test "remote references provider preserves locations and cancellation" {
  let previous_send = protocol_send.val
  defer {
    protocol_send.val = previous_send
  }
  let source_uri = definition_navigation_test_uri("references-source")
  let first_uri = definition_navigation_test_uri("references-first")
  let second_uri = definition_navigation_test_uri("references-second")
  let source_model = @model.TextModel(
    source_uri, "references-source.mbt", "moonbit", 2, "rev-references", "let answer = target",
  )
  defer source_model.dispose()
  let markers = @markers.MarkerService()
  defer markers.dispose()
  let freshness = RemoteLanguageFreshness(markers)
  freshness.note_document(source_model)
  defer freshness.invalidate()
  let client = RemoteLanguageClient::{
    log_service: LogService(logger=@log.NullLogger()),
    freshness,
  }
  let observed_uri = Ref("")
  let observed_revision = Ref("")
  let observed_offset = Ref(-1)
  let unexpected_packet = Ref(false)
  protocol_send.val = Some(packet => {
    match packet {
      References(request) => {
        observed_uri.val = request.uri.to_string()
        observed_revision.val = request.document_revision
        observed_offset.val = request.offset
        resolve_pending_response(
          ReferencesResult({
            id: request.id,
            uri: request.uri,
            revision: request.document_revision,
            references: [
              {
                uri: first_uri,
                range: Range(3, 2, 3, 8),
                line: 3,
                column: 2,
                line_text: "let first = target",
              },
              {
                uri: second_uri,
                range: Range(9, 1, 9, 5),
                line: 9,
                column: 1,
                line_text: "target()",
              },
            ],
          }),
        )
        |> ignore
      }
      _ => unexpected_packet.val = true
    }
  })
  let locations = client.provide_references(
    source_model,
    Position(1, 14),
    @language.CancellationToken::none(),
  )
  assert_false(unexpected_packet.val)
  assert_eq(observed_uri.val, source_uri.to_string())
  assert_eq(observed_revision.val, "rev-references")
  assert_eq(observed_offset.val, source_model.get_offset_at(Position(1, 14)))
  assert_eq(locations.length(), 2)
  assert_eq(locations[0].uri.to_string(), first_uri.to_string())
  assert_eq(locations[0].range, Range(3, 2, 3, 8))
  assert_eq(locations[1].uri.to_string(), second_uri.to_string())
  assert_eq(locations[1].range, Range(9, 1, 9, 5))

  let cancelled = @language.CancellationTokenSource()
  defer cancelled.dispose()
  let cancelled_request_id = Ref("")
  protocol_send.val = Some(packet => {
    match packet {
      References(request) => {
        cancelled_request_id.val = request.id
        cancelled.cancel()
      }
      _ => unexpected_packet.val = true
    }
  })
  let cancelled_locations = client.provide_references(
    source_model,
    Position(1, 14),
    cancelled.token(),
  )
  assert_true(cancelled_locations.is_empty())
  assert_true(
    resolve_pending_response(
      ReferencesResult({
        id: cancelled_request_id.val,
        uri: source_uri,
        revision: "rev-references",
        references: [],
      }),
    ),
  )
  assert_false(unexpected_packet.val)
}

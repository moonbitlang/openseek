///|
/// Pushes one stable diagnostic before attachment so lifecycle tests can
/// distinguish MarkerService data from the derived per-model decorations.
fn seed_lifecycle_marker(
  markers : @markers.MarkerService,
  model : @model.TextModel,
) -> Unit {
  markers.change_one("lifecycle-owner", model.uri, [
    MarkerData(
      severity=Error,
      message="preloaded",
      start_line_number=1,
      start_column=1,
      end_line_number=1,
      end_column=2,
    ),
  ])
}

///|
fn live_lifecycle_marker_count(
  marker_decorations : @markers.MarkerDecorationsHandle,
  model : @model.TextModel,
) -> Int {
  marker_decorations.get_live_markers_for_model(model).length()
}

///|
/// Caller-retained concrete backings for root white-box tests. Production
/// receives only the narrowed handles captured by `services`.
struct RootTestServiceBackings {
  services : CodeEditorServices
  languages : @languages.Languages
  markers : @markers.MarkerService
  marker_decorations : @markers.MarkerDecorationsService
  agent_feedback : @agent_feedback.AgentFeedbackService
  quick_diff : @quick_diff.QuickDiffService
  log_service : @log.LogService
  log_output : @log.MemoryLogger
}

///|
fn RootTestServiceBackings::RootTestServiceBackings() -> RootTestServiceBackings {
  let log_output = @log.MemoryLogger()
  let log_service = @log.LogService(level=Trace, logger=log_output)
  let languages = @languages.Languages()
  let markers = @markers.MarkerService()
  let marker_decorations = @markers.MarkerDecorationsService(
    markers.marker_service_handle(),
  )
  let agent_feedback = @agent_feedback.AgentFeedbackService()
  let quick_diff = @quick_diff.QuickDiffService()
  let services = CodeEditorServices(
    languages=languages.language_handle(log_service.log_handle()),
    markers=Decorations(marker_decorations.marker_decorations_handle()),
    agent_feedback=agent_feedback.agent_feedback_handle(),
    quick_diff=quick_diff.quick_diff_handle(),
    log_service=log_service.log_handle(),
  )
  {
    services,
    languages,
    markers,
    marker_decorations,
    agent_feedback,
    quick_diff,
    log_service,
    log_output,
  }
}

///|
fn RootTestServiceBackings::dispose(self : RootTestServiceBackings) -> Unit {
  // The explicit bundle owns none of these injected backings.
  self.services.dispose()
  self.marker_decorations.dispose()
  self.markers.dispose()
  self.agent_feedback.dispose()
}

///|
test "model slot generation and browser shape follow headless lifecycle" {
  let viewer = CodeEditorWidget::CodeEditorWidget()
  let model = test_model("alpha")
  assert_eq(viewer.model_slot.generation, 0)
  assert_true(viewer.model_slot.current is None)

  viewer.set_model(Some(model))
  assert_eq(viewer.model_slot.generation, 1)
  guard viewer.model_slot.current is Some(first) else {
    fail("headless model slot was not installed")
  }
  assert_true(first.browser is None)

  viewer.set_value("beta")
  viewer.set_model(Some(model))
  assert_eq(viewer.model_slot.generation, 1)

  viewer.set_model(None)
  assert_eq(viewer.model_slot.generation, 2)
  assert_true(viewer.model_slot.current is None)

  viewer.set_model(Some(model))
  assert_eq(viewer.model_slot.generation, 3)
  guard viewer.model_slot.current is Some(second) else {
    fail("headless model slot was not reinstalled")
  }
  assert_true(second.browser is None)

  viewer.dispose()
  assert_eq(viewer.model_slot.generation, 4)
  assert_true(viewer.model_slot.current is None)
  model.dispose()
}

///|
test "preloaded markers survive detach and seed again on reattach" {
  let backings = RootTestServiceBackings::RootTestServiceBackings()
  let viewer = CodeEditorWidget::CodeEditorWidget(services=backings.services)
  let model = test_model("alpha")
  seed_lifecycle_marker(backings.markers, model)
  viewer.set_model(Some(model))
  let marker_handle = backings.marker_decorations.marker_decorations_handle()
  assert_eq(live_lifecycle_marker_count(marker_handle, model), 1)
  viewer.set_model(None)
  assert_eq(live_lifecycle_marker_count(marker_handle, model), 0)
  assert_eq(backings.markers.diagnostics_for_resource(model.uri).length(), 1)
  viewer.set_model(Some(model))
  assert_eq(live_lifecycle_marker_count(marker_handle, model), 1)
  viewer.dispose()
  assert_false(model.is_disposed())
  model.dispose()
  backings.dispose()
}

///|
test "set_value refresh does not acquire another shared-model lease" {
  let backings = RootTestServiceBackings::RootTestServiceBackings()
  let first = CodeEditorWidget::CodeEditorWidget(services=backings.services)
  let second = CodeEditorWidget::CodeEditorWidget(services=backings.services)
  let model = test_model("alpha")
  seed_lifecycle_marker(backings.markers, model)
  first.set_model(Some(model))
  second.set_model(Some(model))
  let marker_handle = backings.marker_decorations.marker_decorations_handle()
  assert_eq(live_lifecycle_marker_count(marker_handle, model), 1)
  first.set_value("beta")
  assert_eq(live_lifecycle_marker_count(marker_handle, model), 1)
  first.dispose()
  assert_eq(live_lifecycle_marker_count(marker_handle, model), 1)
  second.dispose()
  assert_eq(live_lifecycle_marker_count(marker_handle, model), 0)
  assert_false(backings.services.disposed)
  assert_eq(backings.markers.diagnostics_for_resource(model.uri).length(), 1)
  model.dispose()
  backings.dispose()
  assert_true(backings.services.disposed)
}

///|
test "distinct same-URI models retain independent decoration owners" {
  let backings = RootTestServiceBackings::RootTestServiceBackings()
  let first_viewer = CodeEditorWidget::CodeEditorWidget(
    services=backings.services,
  )
  let second_viewer = CodeEditorWidget::CodeEditorWidget(
    services=backings.services,
  )
  let first_model = test_model("first")
  let second_model = test_model("second")
  assert_true(first_model.uri.to_string() == second_model.uri.to_string())
  assert_false(first_model.same(second_model))
  seed_lifecycle_marker(backings.markers, first_model)
  first_viewer.set_model(Some(first_model))
  second_viewer.set_model(Some(second_model))
  let marker_handle = backings.marker_decorations.marker_decorations_handle()
  assert_eq(live_lifecycle_marker_count(marker_handle, first_model), 1)
  assert_eq(live_lifecycle_marker_count(marker_handle, second_model), 1)
  first_viewer.dispose()
  assert_eq(live_lifecycle_marker_count(marker_handle, first_model), 0)
  assert_eq(live_lifecycle_marker_count(marker_handle, second_model), 1)
  second_viewer.dispose()
  assert_eq(live_lifecycle_marker_count(marker_handle, second_model), 0)
  first_model.dispose()
  second_model.dispose()
  backings.dispose()
}

///|
test "model disposal detaches two Viewers sharing one registration" {
  let backings = RootTestServiceBackings::RootTestServiceBackings()
  let first = CodeEditorWidget::CodeEditorWidget(services=backings.services)
  let second = CodeEditorWidget::CodeEditorWidget(services=backings.services)
  let model = test_model("alpha")
  seed_lifecycle_marker(backings.markers, model)
  first.set_model(Some(model))
  second.set_model(Some(model))
  let marker_handle = backings.marker_decorations.marker_decorations_handle()
  model.dispose()
  assert_true(first.get_model() is None)
  assert_true(second.get_model() is None)
  assert_eq(live_lifecycle_marker_count(marker_handle, model), 0)
  first.dispose()
  second.dispose()
  backings.dispose()
}

///|
test "explicit services stay borrowed after CodeEditorWidget disposal" {
  let backings = RootTestServiceBackings::RootTestServiceBackings()
  let viewer = CodeEditorWidget::CodeEditorWidget(services=backings.services)
  assert_false(viewer.owns_services)
  viewer.dispose()
  assert_false(backings.services.disposed)
  let model = test_model("alpha")
  seed_lifecycle_marker(backings.markers, model)
  let marker_handle = backings.marker_decorations.marker_decorations_handle()
  let lease = marker_handle.acquire_model(model)
  assert_eq(live_lifecycle_marker_count(marker_handle, model), 1)
  lease.dispose()
  model.dispose()
  backings.dispose()
}

///|
test "MarkerStore makes only its generated decorations bundle-owned" {
  let backings = RootTestServiceBackings::RootTestServiceBackings()
  let services = CodeEditorServices(
    languages=backings.languages.language_handle(
      backings.log_service.log_handle(),
    ),
    markers=MarkerStore(backings.markers.marker_service_handle()),
    agent_feedback=backings.agent_feedback.agent_feedback_handle(),
    quick_diff=backings.quick_diff.quick_diff_handle(),
    log_service=backings.log_service.log_handle(),
  )
  let generated_decorations = services.owned_marker_decorations.unwrap()
  assert_true(services.owned_markers is None)
  assert_true(services.owned_agent_feedback is None)
  let model = test_model("alpha")
  seed_lifecycle_marker(backings.markers, model)
  let generated_handle = generated_decorations.marker_decorations_handle()
  let lease = generated_handle.acquire_model(model)
  assert_eq(live_lifecycle_marker_count(generated_handle, model), 1)
  let marker_deliveries = Ref(0)
  let subscription = backings.markers.on_did_change_markers(_ => {
    marker_deliveries.val += 1
  })

  services.dispose()
  services.dispose()

  assert_true(services.disposed)
  assert_eq(live_lifecycle_marker_count(generated_handle, model), 0)
  seed_lifecycle_marker(backings.markers, model)
  assert_eq(marker_deliveries.val, 1)
  subscription.dispose()
  lease.dispose()
  model.dispose()
  backings.dispose()
}

///|
test "Decorations leaves every caller handle live after bundle disposal" {
  let backings = RootTestServiceBackings::RootTestServiceBackings()
  let log_handle = backings.log_service.log_handle()
  let language_handle = backings.languages.language_handle(log_handle)
  let marker_handle = backings.marker_decorations.marker_decorations_handle()
  let feedback_handle = backings.agent_feedback.agent_feedback_handle()
  let quick_diff_handle = backings.quick_diff.quick_diff_handle()
  let services = CodeEditorServices(
    languages=language_handle,
    markers=Decorations(marker_handle),
    agent_feedback=feedback_handle,
    quick_diff=quick_diff_handle,
    log_service=log_handle,
  )
  assert_true(services.owned_marker_decorations is None)
  assert_true(services.owned_markers is None)
  assert_true(services.owned_agent_feedback is None)

  services.dispose()
  services.dispose()

  let model = test_model("alpha")
  seed_lifecycle_marker(backings.markers, model)
  let lease = marker_handle.acquire_model(model)
  assert_eq(live_lifecycle_marker_count(marker_handle, model), 1)
  backings.agent_feedback.set_feedback_enabled(model.uri, true)
  assert_true(feedback_handle.is_feedback_enabled(model.uri))
  backings.quick_diff.set_original_content(model.uri, Some("baseline"))
  assert_true(
    quick_diff_handle.get_original_content(model.uri) == Some("baseline"),
  )
  backings.languages.set_language_configuration("root-test", {
    comments: None,
    folding_rules: Some({ off_side: true, markers: None, }),
  })
  guard language_handle.get_language_configuration("root-test").folding_rules
    is Some(folding_rules) else {
    fail("caller language handle lost its registered configuration")
  }
  assert_true(folding_rules.off_side)
  log_handle.warn("viewer.lifecycle", "still live")
  assert_eq(backings.log_output.entries().length(), 1)

  lease.dispose()
  model.dispose()
  backings.dispose()
}

///|
async test "navigation handles stay optional and borrowed after bundle disposal" {
  let target = try! @base_common.Uri::parse("memory://workspace/definition.mbt")
  let model = @model.TextModel(
    target, "definition.mbt", "moonbit", 1, "definition-rev", "let definition = 1",
  )
  let mut open_calls = 0
  let mut resolve_calls = 0
  let mut release_calls = 0
  let opener = @navigation_api.LocationOpenerHandle(open=request => {
    open_calls += 1
    request.location.uri.to_string() == target.to_string()
  })
  let resolver = @navigation_api.TextModelResolverHandle(resolve=(
    resource,
    _token,
  ) => {
    resolve_calls += 1
    if resource.to_string() == target.to_string() {
      Some(TextModelReference(model, release=() => release_calls += 1))
    } else {
      None
    }
  })
  let services = CodeEditorServices(
    location_opener=opener,
    text_model_resolver=resolver,
  )
  assert_true(services.location_opener is Some(_))
  assert_true(services.text_model_resolver is Some(_))
  services.dispose()
  services.dispose()
  let request : @navigation_api.OpenLocationRequest = {
    source_viewer_id: "viewer-navigation-owner",
    location: { uri: target, range: Range(1, 5, 1, 15), },
    mode: Current,
  }
  assert_true(opener.open(request))
  guard resolver.resolve(target, @language.CancellationToken::none())
    is Some(reference) else {
    fail("borrowed resolver stopped after CodeEditorServices disposal")
  }
  assert_true(reference.model().same(model))
  reference.dispose()
  assert_eq(open_calls, 1)
  assert_eq(resolve_calls, 1)
  assert_eq(release_calls, 1)
  assert_false(model.is_disposed())
  model.dispose()

  let defaults = CodeEditorServices()
  assert_true(defaults.location_opener is None)
  assert_true(defaults.text_model_resolver is None)
  defaults.dispose()
}

///|
test "omitted services are owned and CodeEditorWidget disposal is idempotent" {
  let viewer = CodeEditorWidget::CodeEditorWidget()
  let services = viewer.services
  let owned_markers = services.owned_markers.unwrap()
  let owned_marker_decorations = services.owned_marker_decorations.unwrap()
  let owned_agent_feedback = services.owned_agent_feedback.unwrap()
  let owned_feedback_handle = owned_agent_feedback.agent_feedback_handle()
  assert_false(services.disposed)
  let model = test_model("alpha")
  seed_lifecycle_marker(owned_markers, model)
  viewer.set_model(Some(model))
  let marker_deliveries = Ref(0)
  let mut feedback_deliveries = 0
  let marker_subscription = owned_markers.on_did_change_markers(_ => {
    marker_deliveries.val += 1
  })
  let feedback_subscription = owned_feedback_handle.on_did_change_feedback(_ => {
    feedback_deliveries += 1
  })
  let mut dispose_events = 0
  let mut contribution_alive_in_event = false
  let mut lifetime_store_alive_in_event = false
  let mut model_detached_in_event = false
  viewer.on_did_dispose(() => {
    dispose_events += 1
    contribution_alive_in_event = viewer.contributions.lookup(
        "editor.contrib.contentHover",
      )
      is Some(_)
    lifetime_store_alive_in_event = !viewer.lifetime_disposables.is_empty()
    model_detached_in_event = viewer.get_model() is None
  })
  |> ignore
  viewer.dispose()
  viewer.dispose()
  assert_true(viewer.owns_services)
  assert_true(viewer.disposed)
  assert_true(services.disposed)
  assert_eq(dispose_events, 1)
  assert_true(contribution_alive_in_event)
  assert_true(lifetime_store_alive_in_event)
  assert_true(model_detached_in_event)
  assert_eq(viewer.lifetime_disposables.length(), 0)
  // A never-attached CodeEditorWidget remains semantically headless through disposal:
  // it has no browser frame, focus, host, or placeholder capability to tear
  // down.
  assert_true(viewer.mount is Headless)
  assert_false(viewer.mount.has_pending_render())
  assert_false(viewer.has_text_focus())
  assert_false(model.is_disposed())
  // The owning CodeEditorWidget released all three bundle-owned default backings. Their
  // captured concrete references remain safe but have no live ingress.
  seed_lifecycle_marker(owned_markers, model)
  owned_agent_feedback.set_feedback_enabled(model.uri, true)
  owned_feedback_handle.add_feedback(
    model.uri,
    Range(1, 1, 1, 2),
    "after default disposal",
  )
  |> ignore
  assert_eq(marker_deliveries.val, 0)
  assert_eq(feedback_deliveries, 0)
  let later_model = test_model("later")
  let owned_marker_handle = owned_marker_decorations.marker_decorations_handle()
  let late_lease = owned_marker_handle.acquire_model(later_model)
  assert_eq(live_lifecycle_marker_count(owned_marker_handle, later_model), 0)
  late_lease.dispose()
  marker_subscription.dispose()
  feedback_subscription.dispose()
  model.dispose()
  later_model.dispose()
}

///|
test "disposed headless CodeEditorWidget ignores later model and callback work" {
  let backings = RootTestServiceBackings::RootTestServiceBackings()
  let viewer = CodeEditorWidget::CodeEditorWidget(services=backings.services)
  let model = test_model("alpha")
  viewer.set_model(Some(model))
  let mut content_events = 0
  viewer.on_did_change_model_content(_ => content_events += 1) |> ignore
  viewer.dispose()
  model.set_value("beta")
  // Later model and render requests are both ignored after disposal.
  viewer.set_model(Some(model))
  viewer.schedule_render()
  assert_eq(content_events, 0)
  assert_false(viewer.configuration.consume_measure_request())
  assert_true(viewer.get_model() is None)
  assert_true(viewer.mount is Headless)
  assert_false(viewer.mount.has_pending_render())
  model.dispose()
  backings.dispose()
}

///|
test "headless CodeEditorWidget detaches its model on disposal" {
  let viewer = CodeEditorWidget::CodeEditorWidget()
  assert_true(viewer.get_model() is None)
  let model = test_model("testing-registration")
  viewer.set_model(Some(model))
  assert_true(viewer.get_model() is Some(_))

  viewer.dispose()

  assert_true(viewer.get_model() is None)
  model.dispose()
}

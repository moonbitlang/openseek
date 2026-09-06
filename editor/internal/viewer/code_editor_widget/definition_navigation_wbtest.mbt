///|
priv struct DefinitionNavigationTestProvider {
  locations : Array[@language.Location]
}

///|
impl @language.DefinitionProvider for DefinitionNavigationTestProvider with fn provide_definition(
  self,
  _model,
  _position,
  _token,
) {
  self.locations.copy()
}

///|
priv struct SequencedDefinitionProvider {
  responses : Array[Array[@language.Location]]
  calls : Ref[Int]
}

///|
impl @language.DefinitionProvider for SequencedDefinitionProvider with fn provide_definition(
  self,
  _model,
  _position,
  _token,
) {
  let index = self.calls.val
  self.calls.val += 1
  if index < self.responses.length() {
    self.responses[index].copy()
  } else {
    []
  }
}

///|
priv struct ManualDefinitionTasks {
  tasks : Array[async () -> Unit noraise]
}

///|
fn ManualDefinitionTasks::ManualDefinitionTasks() -> ManualDefinitionTasks {
  { tasks: [], }
}

///|
fn ManualDefinitionTasks::schedule(
  self : ManualDefinitionTasks,
  task : async () -> Unit noraise,
) -> Unit {
  self.tasks.push(task)
}

///|
async fn ManualDefinitionTasks::run_next(
  self : ManualDefinitionTasks,
) -> Unit noraise {
  guard !self.tasks.is_empty() else { return }
  let task = self.tasks.remove(0)
  task()
}

///|
fn definition_navigation_test_model(
  resource : String,
  text? : String = "let source = target\n",
) -> @model.TextModel {
  TextModel(
    try! @base_common.Uri::parse(resource),
    "source.mbt",
    "moonbit",
    1,
    "revision-1",
    text,
  )
}

///|
fn definition_navigation_services(
  locations : Array[@language.Location],
  opener? : @navigation_api.LocationOpenerHandle,
  resolver? : @navigation_api.TextModelResolverHandle,
) -> CodeEditorServices {
  let languages = @languages.Languages()
  let provider = DefinitionNavigationTestProvider::{ locations, }
  languages.register_definition_provider(LanguageId("moonbit"), provider)
  |> ignore
  let log_service = @log.LogService()
  CodeEditorServices(
    languages=languages.language_handle(log_service.log_handle()),
    location_opener?=opener,
    text_model_resolver?=resolver,
    log_service=log_service.log_handle(),
  )
}

///|
/// Installs a viewer over `model` whose definition async tasks land in a
/// manually drained queue.
fn definition_navigation_viewer(
  services : CodeEditorServices,
  model : @model.TextModel,
) -> (CodeEditorWidget, ManualDefinitionTasks) {
  let viewer = CodeEditorWidget(services~)
  let tasks = ManualDefinitionTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  viewer.set_model(Some(model))
  (viewer, tasks)
}

///|
test "definition-link cancellation callbacks cannot clobber replacement owners" {
  let services = definition_navigation_services([])
  let viewer = CodeEditorWidget(services~)
  guard viewer.definition_contribution() is Some(state) else {
    fail("definition contribution was not installed")
  }
  let old_link = @language.CancellationTokenSource()
  let new_link = @language.CancellationTokenSource()
  old_link
  .token()
  .on_cancellation_requested(() => state.link_source = Some(new_link))
  |> ignore
  state.link_source = Some(old_link)
  state.cancel_link()
  guard state.link_source is Some(current_link) else {
    fail("link cancellation clobbered its replacement owner")
  }
  assert_true(physical_equal(current_link, new_link))

  new_link.dispose(cancel=true)
  state.link_source = None
  viewer.dispose()
  services.dispose()
}

///|
async test "F12 reveals a same-resource definition without calling the opener" {
  let model = definition_navigation_test_model("file:///source.mbt")
  let location : @language.Location = {
    uri: model.uri,
    range: Range(1, 14, 1, 20),
  }
  let opener_calls = Ref(0)
  let opener = @navigation_api.LocationOpenerHandle(open=_request => {
    opener_calls.val += 1
    true
  })
  let services = definition_navigation_services([location], opener~)
  let (viewer, tasks) = definition_navigation_viewer(services, model)
  viewer.set_position(Position(1, 5))

  assert_true(
    viewer.handle_editor_key_down("F12", alt=false, ctrl_cmd=false, shift=false),
  )
  assert_eq(tasks.tasks.length(), 1)
  tasks.run_next()
  assert_eq(viewer.get_position(), Some(Position(1, 14)))
  assert_eq(opener_calls.val, 0)
  assert_true(viewer.definition_message_for_test() is None)
  let highlights = viewer
    .get_line_decorations(1)
    .filter(decoration => decoration.options.class_name == "symbolHighlight")
  assert_eq(highlights.length(), 1)
  assert_eq(highlights[0].range, location.range)
  assert_eq(
    highlights[0].options.description,
    "symbol-navigate-action-highlight",
  )

  viewer.dispose()
  services.dispose()
  model.dispose()
}

///|
async test "headless multiple definitions retain provider-first fallback" {
  let model = definition_navigation_test_model("file:///source.mbt")
  let provider_first = try! @base_common.Uri::parse(
    "file:///provider-first.mbt",
  )
  let requests : Array[@navigation_api.OpenLocationRequest] = []
  let opener = @navigation_api.LocationOpenerHandle(open=request => {
    requests.push(request)
    true
  })
  let services = definition_navigation_services(
    [
      { uri: provider_first, range: Range(8, 2, 8, 6), },
      { uri: model.uri, range: Range(1, 14, 1, 20), },
    ],
    opener~,
  )
  let (viewer, tasks) = definition_navigation_viewer(services, model)
  viewer.set_position(Position(1, 5))
  viewer.start_goto_definition()
  tasks.run_next()
  assert_eq(requests.length(), 1)
  assert_eq(requests[0].location.uri.to_string(), provider_first.to_string())

  viewer.dispose()
  services.dispose()
  model.dispose()
}

///|
async test "F12 sends a cross-resource request and preserves rejection feedback" {
  let model = definition_navigation_test_model("file:///source.mbt")
  let target = try! @base_common.Uri::parse("file:///target.mbt")
  let location : @language.Location = { uri: target, range: Range(4, 2, 4, 8), }
  let requests : Array[@navigation_api.OpenLocationRequest] = []
  let opener = @navigation_api.LocationOpenerHandle(open=request => {
    requests.push(request)
    false
  })
  let services = definition_navigation_services([location], opener~)
  let (viewer, tasks) = definition_navigation_viewer(services, model)
  viewer.set_position(Position(1, 5))

  assert_true(
    viewer.handle_editor_key_down("F12", alt=false, ctrl_cmd=true, shift=false),
  )
  tasks.run_next()
  assert_eq(requests.length(), 1)
  assert_eq(requests[0].source_viewer_id, viewer.get_id())
  assert_eq(requests[0].location.uri.to_string(), target.to_string())
  assert_eq(requests[0].mode, Current)
  assert_eq(
    viewer.definition_message_for_test(),
    Some("Unable to open definition"),
  )

  viewer.dispose()
  services.dispose()
  model.dispose()
}

///|
async test "a superseded definition opener failure cannot overwrite a newer navigation" {
  let model = definition_navigation_test_model("file:///source.mbt")
  let target = try! @base_common.Uri::parse("file:///target.mbt")
  let location : @language.Location = { uri: target, range: Range(4, 2, 4, 8), }
  let calls = Ref(0)
  let first_started = @async.Semaphore(1, initial_value=0)
  let release_first = @async.Semaphore(1, initial_value=0)
  let opener = @navigation_api.LocationOpenerHandle(open=_request => {
    let call = calls.val
    calls.val += 1
    if call == 0 {
      first_started.release()
      release_first.acquire() catch {
        _ => return false
      }
      false
    } else {
      true
    }
  })
  let services = definition_navigation_services([location], opener~)
  let (viewer, tasks) = definition_navigation_viewer(services, model)
  viewer.set_position(Position(1, 5))

  @async.with_task_group() <| group => {
    viewer.start_goto_definition()
    let first = group.spawn(() => tasks.run_next())
    first_started.acquire()

    viewer.start_goto_definition()
    // Merely starting B is enough to stale A's feedback; B's provider/opener
    // has not run yet.
    release_first.release()
    first.wait()
    assert_true(viewer.definition_message_for_test() is None)

    let second = group.spawn(() => tasks.run_next())
    second.wait()
    assert_eq(calls.val, 2)
  }
  assert_true(viewer.definition_message_for_test() is None)

  viewer.dispose()
  services.dispose()
  model.dispose()
}

///|
async test "cursor movement suppresses late definition opener failure" {
  let model = definition_navigation_test_model("file:///source.mbt")
  let target = try! @base_common.Uri::parse("file:///target.mbt")
  let location : @language.Location = { uri: target, range: Range(4, 2, 4, 8), }
  let started = @async.Semaphore(1, initial_value=0)
  let release = @async.Semaphore(1, initial_value=0)
  let opener = @navigation_api.LocationOpenerHandle(open=_request => {
    started.release()
    release.acquire() catch {
      _ => return false
    }
    false
  })
  let services = definition_navigation_services([location], opener~)
  let (viewer, tasks) = definition_navigation_viewer(services, model)
  viewer.set_position(Position(1, 5))

  @async.with_task_group() <| group => {
    viewer.start_goto_definition()
    let request = group.spawn(() => tasks.run_next())
    started.acquire()
    viewer.set_position(Position(1, 6))
    release.release()
    request.wait()
  }
  assert_true(viewer.definition_message_for_test() is None)

  viewer.dispose()
  services.dispose()
  model.dispose()
}

///|
async test "empty and stale definition actions cannot navigate" {
  let model = definition_navigation_test_model("file:///source.mbt")
  let target = try! @base_common.Uri::parse("file:///target.mbt")
  let location : @language.Location = { uri: target, range: Range(1, 1, 1, 2), }
  let opener_calls = Ref(0)
  let opener = @navigation_api.LocationOpenerHandle(open=_request => {
    opener_calls.val += 1
    true
  })
  let services = definition_navigation_services([location], opener~)
  let (viewer, tasks) = definition_navigation_viewer(services, model)
  viewer.start_goto_definition()
  viewer.set_value("let source = changed\n")
  tasks.run_next()
  assert_eq(opener_calls.val, 0)
  assert_true(viewer.definition_message_for_test() is None)

  viewer.set_position(Position(1, 5))
  viewer.start_goto_definition()
  viewer.set_position(Position(1, 6))
  tasks.run_next()
  assert_eq(opener_calls.val, 0)

  let empty_services = definition_navigation_services([], opener~)
  let empty_model = definition_navigation_test_model("file:///empty.mbt")
  let (empty_viewer, empty_tasks) = definition_navigation_viewer(
    empty_services, empty_model,
  )
  empty_viewer.start_goto_definition()
  empty_tasks.run_next()
  assert_eq(
    empty_viewer.definition_message_for_test(),
    Some("No definition found for 'let'"),
  )

  viewer.dispose()
  empty_viewer.dispose()
  services.dispose()
  empty_services.dispose()
  model.dispose()
  empty_model.dispose()
}

///|
async test "empty definition-link result is cached silently for one gesture" {
  let model = definition_navigation_test_model("file:///source.mbt")
  let services = definition_navigation_services([])
  let (viewer, tasks) = definition_navigation_viewer(services, model)
  let position = @base_common.Position(1, 14)
  let word = model.get_word_at_position(position).unwrap()
  let target = @definition.DefinitionTargetFingerprint::from_model(
    model,
    viewer.model_slot.generation,
    position,
    word,
  )
  guard viewer.definition_contribution() is Some(state) else {
    fail("definition contribution was not installed")
  }
  state.link_modifier_down = true
  state.last_pointer_target = Some(target)
  viewer.start_definition_link_request(target)
  assert_eq(tasks.tasks.length(), 1)
  tasks.run_next()
  match state.link_state {
    LinkResolvedEmpty(stamp) => assert_eq(stamp.target, target)
    _ => fail("empty link result was not cached")
  }
  assert_true(viewer.definition_message_for_test() is None)
  viewer.start_definition_link_request(target)
  viewer.start_definition_link_request(target)
  assert_eq(tasks.tasks.length(), 0)
  assert_eq(state.link_decorations.length(), 0)

  viewer.reset_definition_link()
  state.link_modifier_down = true
  state.last_pointer_target = Some(target)
  viewer.start_definition_link_request(target)
  assert_eq(tasks.tasks.length(), 1)

  viewer.dispose()
  services.dispose()
  model.dispose()
}

///|
test "definition-link trigger is the exact platform CtrlCmd modifier" {
  assert_false(definition_link_modifier_is_active(false, false, false, false))
  assert_false(definition_link_modifier_is_active(true, true, false, false))
  assert_false(
    definition_link_modifier_is_active(
      !@base_common.is_macintosh,
      @base_common.is_macintosh,
      true,
      false,
    ),
  )
  assert_false(
    definition_link_modifier_is_active(
      !@base_common.is_macintosh,
      @base_common.is_macintosh,
      false,
      true,
    ),
  )
  assert_true(
    definition_link_modifier_is_active(
      !@base_common.is_macintosh,
      @base_common.is_macintosh,
      false,
      false,
    ),
  )
}

///|
async test "definition-link arms only a fresh token and stale content clears it" {
  let model = definition_navigation_test_model("file:///source.mbt")
  let location : @language.Location = {
    uri: try! @base_common.Uri::parse("file:///target.mbt"),
    range: Range(3, 2, 3, 8),
  }
  let services = definition_navigation_services([location])
  let (viewer, tasks) = definition_navigation_viewer(services, model)
  let position = @base_common.Position(1, 14)
  let word = model.get_word_at_position(position).unwrap()
  let target = @definition.DefinitionTargetFingerprint::from_model(
    model,
    viewer.model_slot.generation,
    position,
    word,
  )
  guard viewer.definition_contribution() is Some(state) else {
    fail("definition contribution was not installed")
  }
  state.link_modifier_down = true
  state.last_pointer_target = Some(target)
  viewer.start_definition_link_request(target)
  assert_eq(tasks.tasks.length(), 1)
  match state.link_state {
    LinkResolving(stamp) => assert_eq(stamp.target, target)
    _ => fail("link did not enter resolving state")
  }
  tasks.run_next()
  match state.link_state {
    LinkArmed(stamp, locations) => {
      assert_eq(stamp.target, target)
      assert_eq(locations.length(), 1)
      assert_eq(locations[0].uri.to_string(), "file:///target.mbt")
    }
    _ => fail("fresh resolved link was not armed")
  }
  assert_eq(state.link_decorations.length(), 1)
  assert_eq(state.link_decorations.get_range(0), Some(target.word_range()))

  state.link_modifier_down = true
  state.last_pointer_target = Some(target)
  viewer.start_definition_link_request(target)
  // The already-armed exact target is cached and does not issue a duplicate.
  assert_eq(tasks.tasks.length(), 0)
  state.cancel_link()
  state.link_modifier_down = true
  state.last_pointer_target = Some(target)
  viewer.start_definition_link_request(target)
  assert_eq(tasks.tasks.length(), 1)
  viewer.set_value("let source = changed\n")
  assert_eq(state.link_decorations.length(), 0)
  match state.link_state {
    LinkIdle => ()
    _ => fail("content change did not reset the link gesture")
  }
  tasks.run_next()
  match state.link_state {
    LinkIdle => ()
    _ => fail("late link result re-armed stale content")
  }

  viewer.dispose()
  services.dispose()
  model.dispose()
}

///|
async test "definition-link caches by word and executes a fresh Definition action" {
  let model = definition_navigation_test_model("file:///source.mbt")
  let preview_uri = try! @base_common.Uri::parse("file:///preview-result.mbt")
  let action_uri = try! @base_common.Uri::parse("file:///action-result.mbt")
  let calls = Ref(0)
  let languages = @languages.Languages()
  languages.register_definition_provider(LanguageId("moonbit"), SequencedDefinitionProvider::{
    responses: [
      [{ uri: preview_uri, range: Range(2, 1, 2, 4), }],
      [{ uri: action_uri, range: Range(7, 3, 7, 9), }],
    ],
    calls,
  })
  |> ignore
  let requests : Array[@navigation_api.OpenLocationRequest] = []
  let opener = @navigation_api.LocationOpenerHandle(open=request => {
    requests.push(request)
    true
  })
  let log_service = @log.LogService()
  let services = CodeEditorServices(
    languages=languages.language_handle(log_service.log_handle()),
    location_opener=opener,
    log_service=log_service.log_handle(),
  )
  let (viewer, tasks) = definition_navigation_viewer(services, model)
  let first_position = @base_common.Position(1, 14)
  let second_position = @base_common.Position(1, 18)
  let first_target = @definition.DefinitionTargetFingerprint::from_model(
    model,
    viewer.model_slot.generation,
    first_position,
    model.get_word_at_position(first_position).unwrap(),
  )
  let second_target = @definition.DefinitionTargetFingerprint::from_model(
    model,
    viewer.model_slot.generation,
    second_position,
    model.get_word_at_position(second_position).unwrap(),
  )
  assert_true(first_target.same_word(second_target))
  guard viewer.definition_contribution() is Some(state) else {
    fail("definition contribution was not installed")
  }
  state.link_modifier_down = true
  state.last_pointer_target = Some(first_target)
  viewer.start_definition_link_request(first_target)
  assert_eq(tasks.tasks.length(), 1)
  viewer.handle_definition_pointer_move(
    Some(second_target),
    !@base_common.is_macintosh,
    @base_common.is_macintosh,
    false,
    false,
    0,
  )
  // Moving within the same word reuses the in-flight preview request.
  assert_eq(tasks.tasks.length(), 1)
  tasks.run_next()
  assert_eq(calls.val, 1)
  match state.link_state {
    LinkArmed(stamp, locations) => {
      assert_true(stamp.target.same_word(second_target))
      assert_eq(locations[0].uri.to_string(), preview_uri.to_string())
    }
    _ => fail("definition link was not armed")
  }

  assert_true(viewer.before_definition_target_mouse_down(Some(second_target)))
  assert_true(
    viewer.handle_definition_pointer_up(
      Some(second_target),
      !@base_common.is_macintosh,
      @base_common.is_macintosh,
      false,
      false,
    ),
  )
  assert_false(state.link_modifier_down)
  assert_true(state.last_pointer_target is None)
  assert_eq(state.definition_mouse_down_line, 0)
  match state.link_state {
    LinkIdle => ()
    _ => fail("successful mouseup retained link-preview state")
  }
  assert_eq(tasks.tasks.length(), 1)
  tasks.run_next()
  assert_eq(calls.val, 2)
  assert_eq(requests.length(), 1)
  assert_eq(requests[0].location.uri.to_string(), action_uri.to_string())

  viewer.dispose()
  services.dispose()
  model.dispose()
}

///|
async test "definition-link click does not wait for preview resolution" {
  let model = definition_navigation_test_model("file:///source.mbt")
  let target_uri = try! @base_common.Uri::parse("file:///target.mbt")
  let location : @language.Location = {
    uri: target_uri,
    range: Range(3, 2, 3, 6),
  }
  let opener_calls = Ref(0)
  let opener = @navigation_api.LocationOpenerHandle(open=_request => {
    opener_calls.val += 1
    true
  })
  let services = definition_navigation_services([location], opener~)
  let (viewer, tasks) = definition_navigation_viewer(services, model)
  let position = @base_common.Position(1, 14)
  let target = @definition.DefinitionTargetFingerprint::from_model(
    model,
    viewer.model_slot.generation,
    position,
    model.get_word_at_position(position).unwrap(),
  )
  guard viewer.definition_contribution() is Some(state) else {
    fail("definition contribution was not installed")
  }
  state.link_modifier_down = true
  state.last_pointer_target = None
  viewer.start_definition_link_request(target)
  assert_eq(tasks.tasks.length(), 1)
  // Preview is still LinkResolving, so selection is not suppressed; the
  // independent click gesture nevertheless records a valid mouse-down line.
  state.link_modifier_down = false
  assert_false(viewer.before_definition_target_mouse_down(Some(target)))
  viewer.on_definition_cursor_selection_changed(true)
  assert_true(state.link_modifier_down)
  assert_eq(state.definition_mouse_down_line, target.position().line_number)
  match state.link_state {
    LinkIdle => ()
    _ => fail("selection change did not cancel the pending link preview")
  }
  assert_true(
    viewer.handle_definition_pointer_up(
      Some(target),
      !@base_common.is_macintosh,
      @base_common.is_macintosh,
      false,
      false,
    ),
  )
  assert_eq(tasks.tasks.length(), 2)
  tasks.run_next()
  assert_eq(opener_calls.val, 0)
  tasks.run_next()
  assert_eq(opener_calls.val, 1)

  viewer.dispose()
  services.dispose()
  model.dispose()
}

///|
async test "drag selection cancels an unresolved definition-link click" {
  let model = definition_navigation_test_model("file:///source.mbt")
  let target_uri = try! @base_common.Uri::parse("file:///target.mbt")
  let location : @language.Location = {
    uri: target_uri,
    range: Range(3, 2, 3, 6),
  }
  let opener_calls = Ref(0)
  let opener = @navigation_api.LocationOpenerHandle(open=_request => {
    opener_calls.val += 1
    true
  })
  let services = definition_navigation_services([location], opener~)
  let (viewer, tasks) = definition_navigation_viewer(services, model)
  let position = @base_common.Position(1, 14)
  let target = @definition.DefinitionTargetFingerprint::from_model(
    model,
    viewer.model_slot.generation,
    position,
    model.get_word_at_position(position).unwrap(),
  )
  guard viewer.definition_contribution() is Some(state) else {
    fail("definition contribution was not installed")
  }
  state.link_modifier_down = true
  viewer.start_definition_link_request(target)
  assert_false(viewer.before_definition_target_mouse_down(Some(target)))
  viewer.on_definition_cursor_selection_changed(false)
  assert_false(state.link_modifier_down)
  assert_eq(state.definition_mouse_down_line, 0)
  assert_false(
    viewer.handle_definition_pointer_up(
      Some(target),
      !@base_common.is_macintosh,
      @base_common.is_macintosh,
      false,
      false,
    ),
  )
  // Only the cancelled preview task remains; mouseup did not enqueue a fresh
  // Definition action.
  assert_eq(tasks.tasks.length(), 1)
  tasks.run_next()
  assert_eq(opener_calls.val, 0)

  viewer.dispose()
  services.dispose()
  model.dispose()
}

///|
test "plain definition pointer-up preserves the keyboard command anchor" {
  let model = definition_navigation_test_model("file:///source.mbt")
  let services = definition_navigation_services([])
  let viewer = CodeEditorWidget(services~)
  viewer.set_model(Some(model))
  let position = @base_common.Position(1, 14)
  let target = @definition.DefinitionTargetFingerprint::from_model(
    model,
    viewer.model_slot.generation,
    position,
    model.get_word_at_position(position).unwrap(),
  )
  guard viewer.definition_contribution() is Some(state) else {
    fail("definition contribution was not installed")
  }
  state.last_pointer_target = None
  state.definition_mouse_down_line = target.position().line_number
  assert_false(
    viewer.handle_definition_pointer_up(
      Some(target),
      false,
      false,
      false,
      false,
    ),
  )
  assert_eq(state.last_pointer_target, Some(target))
  assert_false(state.link_modifier_down)
  assert_eq(state.definition_mouse_down_line, 0)
  match state.link_state {
    LinkIdle => ()
    _ => fail("plain pointer-up retained transient link state")
  }

  viewer.dispose()
  services.dispose()
  model.dispose()
}

///|
async test "plain definition click cancels the previous pointer-anchored action" {
  let model = definition_navigation_test_model("file:///source.mbt")
  let target_uri = try! @base_common.Uri::parse("file:///target.mbt")
  let opener_calls = Ref(0)
  let opener = @navigation_api.LocationOpenerHandle(open=_request => {
    opener_calls.val += 1
    true
  })
  let services = definition_navigation_services(
    [{ uri: target_uri, range: Range(3, 2, 3, 6), }],
    opener~,
  )
  let (viewer, tasks) = definition_navigation_viewer(services, model)
  let first_position = @base_common.Position(1, 5)
  let second_position = @base_common.Position(1, 14)
  let second_target = @definition.DefinitionTargetFingerprint::from_model(
    model,
    viewer.model_slot.generation,
    second_position,
    model.get_word_at_position(second_position).unwrap(),
  )

  viewer.start_goto_definition_at(first_position, mute_message=false)
  let state = viewer.definition_contribution().unwrap()
  viewer.commit_plain_definition_pointer_target(Some(second_target))
  assert_eq(state.last_pointer_target, Some(second_target))
  tasks.run_next()
  assert_eq(opener_calls.val, 0)
  assert_true(viewer.definition_message_for_test() is None)

  viewer.dispose()
  services.dispose()
  model.dispose()
}

///|
test "non-left definition mouseup does not replace the command anchor" {
  let model = definition_navigation_test_model("file:///source.mbt")
  let services = definition_navigation_services([])
  let (viewer, _tasks) = definition_navigation_viewer(services, model)
  let first_position = @base_common.Position(1, 5)
  let second_position = @base_common.Position(1, 14)
  let first_target = @definition.DefinitionTargetFingerprint::from_model(
    model,
    viewer.model_slot.generation,
    first_position,
    model.get_word_at_position(first_position).unwrap(),
  )
  let second_target = @definition.DefinitionTargetFingerprint::from_model(
    model,
    viewer.model_slot.generation,
    second_position,
    model.get_word_at_position(second_position).unwrap(),
  )
  viewer.start_goto_definition_at(first_position, mute_message=false)
  let state = viewer.definition_contribution().unwrap()
  state.last_pointer_target = Some(first_target)

  assert_false(
    viewer.handle_definition_pointer_up(
      Some(second_target),
      false,
      false,
      false,
      false,
      left_button=false,
      detail=1,
    ),
  )
  assert_eq(state.last_pointer_target, Some(first_target))

  viewer.dispose()
  services.dispose()
  model.dispose()
}

///|
test "definition-link modifier edges cancel unrelated CtrlCmd chords" {
  let model = definition_navigation_test_model("file:///source.mbt")
  let services = definition_navigation_services([])
  let viewer = CodeEditorWidget(services~)
  viewer.set_model(Some(model))
  let position = @base_common.Position(1, 14)
  let target = @definition.DefinitionTargetFingerprint::from_model(
    model,
    viewer.model_slot.generation,
    position,
    model.get_word_at_position(position).unwrap(),
  )
  guard viewer.definition_contribution() is Some(state) else {
    fail("definition contribution was not installed")
  }
  state.link_modifier_down = true
  state.last_pointer_target = Some(target)
  state.definition_mouse_down_line = 1
  viewer.handle_definition_modifier_key(
    "K",
    true,
    !@base_common.is_macintosh,
    @base_common.is_macintosh,
    false,
    false,
  )
  assert_false(state.link_modifier_down)
  assert_eq(state.last_pointer_target, Some(target))
  assert_eq(state.definition_mouse_down_line, 0)

  state.link_modifier_down = true
  state.last_pointer_target = Some(target)
  viewer.handle_definition_modifier_key(
    if @base_common.is_macintosh {
      "Meta"
    } else {
      "Control"
    },
    false,
    false,
    false,
    false,
    false,
  )
  assert_false(state.link_modifier_down)
  assert_eq(state.last_pointer_target, Some(target))

  viewer.dispose()
  services.dispose()
  model.dispose()
}

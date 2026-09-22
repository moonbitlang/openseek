///|
priv struct SymbolNavigationTestDefinitionProvider {
  locations : Array[@language.Location]
  calls : Ref[Int]
  tokens : Array[@language.CancellationToken]
  started : @async.Semaphore?
  release : @async.Semaphore?
}

///|
impl @language.DefinitionProvider for SymbolNavigationTestDefinitionProvider with fn provide_definition(
  self,
  _model,
  _position,
  token,
) {
  self.calls.val += 1
  self.tokens.push(token)
  match self.started {
    Some(started) => started.release()
    None => ()
  }
  match self.release {
    Some(release) => release.acquire()
    None => ()
  }
  self.locations.copy()
}

///|
priv struct SymbolNavigationTestReferencesProvider {
  locations : Array[@language.Location]
  calls : Ref[Int]
}

///|
impl @language.ReferencesProvider for SymbolNavigationTestReferencesProvider with fn provide_references(
  self,
  _model,
  _position,
  _token,
) {
  self.calls.val += 1
  self.locations.copy()
}

///|
priv struct SymbolNavigationTestHost {
  model : @model.TextModel
  surface_generation : Ref[Int]
  prepare_calls : Ref[Int]
  opened : Array[@language.Location]
  open_modes : Array[@navigation_api.OpenLocationMode]
  peek_modes : Array[@references.ReferencesPeekMode]
  peek_results : Array[Array[@language.Location]]
  messages : Array[String]
  accept_peek : Ref[Bool]
}

///|
fn SymbolNavigationTestHost::host(
  self : SymbolNavigationTestHost,
) -> SymbolNavigationActionHost {
  {
    prepare_navigation: () => self.prepare_calls.val += 1,
    is_anchor_current: anchor => {
      anchor.model().same(self.model) &&
      anchor.surface_generation() == self.surface_generation.val
    },
    open_location: (_anchor, location, mode, _source) => {
      self.opened.push(location)
      self.open_modes.push(mode)
      true
    },
    open_in_peek: (_anchor, mode, locations) => {
      self.peek_modes.push(mode)
      self.peek_results.push(locations.copy())
      self.accept_peek.val
    },
    show_message: (_anchor, message) => self.messages.push(message),
  }
}

///|
fn symbol_navigation_test_model() -> @model.TextModel {
  TextModel(
    try! @base_common.Uri::parse("file:///symbol-navigation.mbt"),
    "symbol-navigation.mbt",
    "moonbit",
    1,
    "revision-1",
    "let source = target\n",
  )
}

///|
fn symbol_navigation_test_anchor(
  model : @model.TextModel,
  surface_generation : Int,
) -> SymbolNavigationAnchor {
  SymbolNavigationAnchor::from_model(
    model,
    Position(1, 14),
    Range(1, 14, 1, 20),
    surface_generation,
  )
}

///|
fn symbol_navigation_test_host(
  model : @model.TextModel,
  surface_generation : Ref[Int],
) -> SymbolNavigationTestHost {
  {
    model,
    surface_generation,
    prepare_calls: Ref(0),
    opened: [],
    open_modes: [],
    peek_modes: [],
    peek_results: [],
    messages: [],
    accept_peek: Ref(true),
  }
}

///|
async fn symbol_navigation_run_test_tasks(
  tasks : Array[async () -> Unit],
) -> Unit {
  for task in tasks {
    task()
  }
}

///|
test "action cancellation callbacks cannot clobber a replacement source" {
  let model = symbol_navigation_test_model()
  defer model.dispose()
  let surface_generation = Ref(1)
  let host = symbol_navigation_test_host(model, surface_generation)
  let languages = @languages.Languages()
  let action = SymbolNavigationAction(
    languages.language_handle(@log.LogService().log_handle()),
    host.host(),
    symbol_navigation_run_test_tasks,
  )
  let old_source = @language.CancellationTokenSource()
  let replacement_source = @language.CancellationTokenSource()
  old_source
  .token()
  .on_cancellation_requested(() => action.source = Some(replacement_source))
  |> ignore
  action.source = Some(old_source)
  action.cancel()
  guard action.source is Some(current_source) else {
    fail("cancellation clobbered the replacement source")
  }
  assert_true(physical_equal(current_source, replacement_source))
  action.source = None
  replacement_source.dispose(cancel=true)
  action.dispose()
}

///|
async test "shared DefinitionAction applies zero one and multi-result policy once" {
  let model = symbol_navigation_test_model()
  defer model.dispose()
  let surface_generation = Ref(7)
  let host = symbol_navigation_test_host(model, surface_generation)
  let calls = Ref(0)
  let first : @language.Location = {
    uri: @base_common.Uri::file("/first.mbt"),
    range: Range(3, 2, 3, 8),
  }
  let second : @language.Location = {
    uri: @base_common.Uri::file("/second.mbt"),
    range: Range(9, 4, 9, 10),
  }
  let languages = @languages.Languages()
  let registration = languages.register_definition_provider(
    LanguageId("moonbit"),
    SymbolNavigationTestDefinitionProvider::{
      locations: [],
      calls,
      tokens: [],
      started: None,
      release: None,
    },
  )
  let action = SymbolNavigationAction(
    languages.language_handle(@log.LogService().log_handle()),
    host.host(),
    symbol_navigation_run_test_tasks,
  )
  let definition = DefinitionAction(action)
  let anchor = symbol_navigation_test_anchor(model, surface_generation.val)

  definition.run(anchor, SymbolNavigationActionConfig::goto())
  assert_eq(calls.val, 1)
  assert_eq(host.opened.length(), 0)
  assert_eq(host.peek_results.length(), 0)
  assert_eq(host.messages, ["No definition found for 'target'"])

  registration.dispose()
  let single_calls = Ref(0)
  let single = languages.register_definition_provider(LanguageId("moonbit"), SymbolNavigationTestDefinitionProvider::{
    locations: [first],
    calls: single_calls,
    tokens: [],
    started: None,
    release: None,
  })
  definition.run(anchor, SymbolNavigationActionConfig::goto())
  assert_eq(single_calls.val, 1)
  assert_eq(host.opened.length(), 1)
  assert_eq(host.opened[0].uri.to_string(), first.uri.to_string())
  assert_eq(host.opened[0].range, first.range)
  assert_eq(host.open_modes, [Current])
  assert_eq(host.peek_results.length(), 0)

  single.dispose()
  let multiple_calls = Ref(0)
  let multiple = languages.register_definition_provider(LanguageId("moonbit"), SymbolNavigationTestDefinitionProvider::{
    locations: [first, first, second],
    calls: multiple_calls,
    tokens: [],
    started: None,
    release: None,
  })
  definition.run(anchor, SymbolNavigationActionConfig::goto())
  assert_eq(multiple_calls.val, 1)
  assert_eq(host.opened.length(), 1)
  assert_eq(host.peek_modes, [Definitions])
  assert_eq(host.peek_results.length(), 1)
  assert_eq(host.peek_results[0].length(), 2)
  assert_eq(host.peek_results[0][0].uri.to_string(), first.uri.to_string())
  assert_eq(host.peek_results[0][0].range, first.range)
  assert_eq(host.peek_results[0][1].uri.to_string(), second.uri.to_string())
  assert_eq(host.peek_results[0][1].range, second.range)

  multiple.dispose()
  action.dispose()
}

///|
async test "forced Peek and ReferencesAction share policy but query only their provider" {
  let model = symbol_navigation_test_model()
  defer model.dispose()
  let surface_generation = Ref(1)
  let host = symbol_navigation_test_host(model, surface_generation)
  let definition_calls = Ref(0)
  let references_calls = Ref(0)
  let location : @language.Location = {
    uri: model.uri,
    range: Range(1, 5, 1, 11),
  }
  let languages = @languages.Languages()
  let definition_registration = languages.register_definition_provider(
    LanguageId("moonbit"),
    SymbolNavigationTestDefinitionProvider::{
      locations: [location],
      calls: definition_calls,
      tokens: [],
      started: None,
      release: None,
    },
  )
  let references_registration = languages.register_references_provider(
    LanguageId("moonbit"),
    SymbolNavigationTestReferencesProvider::{
      locations: [location],
      calls: references_calls,
    },
  )
  let action = SymbolNavigationAction(
    languages.language_handle(@log.LogService().log_handle()),
    host.host(),
    symbol_navigation_run_test_tasks,
  )
  let anchor = symbol_navigation_test_anchor(model, surface_generation.val)
  DefinitionAction(action).run(anchor, SymbolNavigationActionConfig::peek())
  assert_eq(definition_calls.val, 1)
  assert_eq(references_calls.val, 0)
  assert_eq(host.peek_modes, [Definitions])
  assert_eq(host.opened.length(), 0)

  ReferencesAction(action).run(anchor, SymbolNavigationActionConfig::goto())
  assert_eq(definition_calls.val, 1)
  assert_eq(references_calls.val, 1)
  assert_eq(host.opened.length(), 1)
  assert_eq(host.opened[0].uri.to_string(), location.uri.to_string())
  assert_eq(host.opened[0].range, location.range)

  host.accept_peek.val = false
  ReferencesAction(action).run(anchor, SymbolNavigationActionConfig::peek())
  assert_eq(references_calls.val, 2)
  assert_eq(host.opened.length(), 1)
  assert_eq(host.messages.last(), Some("No preview available"))

  action.dispose()
  definition_registration.dispose()
  references_registration.dispose()
}

///|
async test "cancellation model version and surface generation suppress stale results" {
  let model = symbol_navigation_test_model()
  defer model.dispose()
  let surface_generation = Ref(3)
  let host = symbol_navigation_test_host(model, surface_generation)
  let started = @async.Semaphore(1, initial_value=0)
  let release = @async.Semaphore(1, initial_value=0)
  let calls = Ref(0)
  let tokens : Array[@language.CancellationToken] = []
  let target : @language.Location = {
    uri: @base_common.Uri::file("/target.mbt"),
    range: Range(4, 2, 4, 8),
  }
  let languages = @languages.Languages()
  let registration = languages.register_definition_provider(
    LanguageId("moonbit"),
    SymbolNavigationTestDefinitionProvider::{
      locations: [target],
      calls,
      tokens,
      started: Some(started),
      release: Some(release),
    },
  )
  let action = SymbolNavigationAction(
    languages.language_handle(@log.LogService().log_handle()),
    host.host(),
    symbol_navigation_run_test_tasks,
  )
  let definition = DefinitionAction(action)
  let anchor = symbol_navigation_test_anchor(model, surface_generation.val)
  @async.with_task_group() <| group => {
    let pending = group.spawn(() => {
      definition.run(anchor, SymbolNavigationActionConfig::goto())
    })
    started.acquire()
    action.cancel()
    release.release()
    pending.wait()
  }
  assert_eq(calls.val, 1)
  assert_true(tokens[0].is_cancellation_requested())
  assert_eq(host.opened.length(), 0)

  let started_version = @async.Semaphore(1, initial_value=0)
  let release_version = @async.Semaphore(1, initial_value=0)
  registration.dispose()
  let version_registration = languages.register_definition_provider(
    LanguageId("moonbit"),
    SymbolNavigationTestDefinitionProvider::{
      locations: [target],
      calls,
      tokens,
      started: Some(started_version),
      release: Some(release_version),
    },
  )
  let version_anchor = symbol_navigation_test_anchor(
    model,
    surface_generation.val,
  )
  @async.with_task_group() <| group => {
    let pending = group.spawn(() => {
      definition.run(version_anchor, SymbolNavigationActionConfig::goto())
    })
    started_version.acquire()
    model.set_value("let source = changed\n")
    release_version.release()
    pending.wait()
  }
  assert_eq(host.opened.length(), 0)
  version_registration.dispose()

  let started_surface = @async.Semaphore(1, initial_value=0)
  let release_surface = @async.Semaphore(1, initial_value=0)
  let surface_registration = languages.register_definition_provider(
    LanguageId("moonbit"),
    SymbolNavigationTestDefinitionProvider::{
      locations: [target],
      calls,
      tokens,
      started: Some(started_surface),
      release: Some(release_surface),
    },
  )
  let surface_anchor = symbol_navigation_test_anchor(
    model,
    surface_generation.val,
  )
  @async.with_task_group() <| group => {
    let pending = group.spawn(() => {
      definition.run(surface_anchor, SymbolNavigationActionConfig::goto())
    })
    started_surface.acquire()
    surface_generation.val += 1
    release_surface.release()
    pending.wait()
  }
  assert_eq(host.opened.length(), 0)

  surface_registration.dispose()
  action.dispose()
}

///|
test "shared command descriptors own ids labels keybindings and enablement" {
  let model = symbol_navigation_test_model()
  defer model.dispose()
  let languages = @languages.Languages()
  let handle = languages.language_handle(@log.LogService().log_handle())
  assert_eq(symbol_navigation_context_commands(handle, model, true), [])
  let definition = languages.register_definition_provider(
    LanguageId("moonbit"),
    SymbolNavigationTestDefinitionProvider::{
      locations: [],
      calls: Ref(0),
      tokens: [],
      started: None,
      release: None,
    },
  )
  assert_eq(symbol_navigation_context_commands(handle, model, false), [
    RevealDefinition,
  ])
  assert_eq(symbol_navigation_context_commands(handle, model, true), [
    RevealDefinition,
    PeekDefinition,
  ])
  assert_eq(RevealDefinition.id(), "editor.action.revealDefinition")
  assert_eq(PeekDefinition.title(), "Peek Definition")
  assert_eq(GoToReferences.id(), "editor.action.goToReferences")
  assert_eq(PeekReferences.id(), "editor.action.referenceSearch.trigger")
  definition.dispose()
}

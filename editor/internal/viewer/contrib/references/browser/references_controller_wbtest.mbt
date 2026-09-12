///|
priv struct ReferencesControllerTestTasks {
  tasks : Array[async () -> Unit noraise]
}

///|
fn ReferencesControllerTestTasks::ReferencesControllerTestTasks() -> ReferencesControllerTestTasks {
  { tasks: [], }
}

///|
fn ReferencesControllerTestTasks::schedule(
  self : ReferencesControllerTestTasks,
  task : async () -> Unit noraise,
) -> Unit {
  self.tasks.push(task)
}

///|
async fn ReferencesControllerTestTasks::run_next(
  self : ReferencesControllerTestTasks,
) -> Unit noraise {
  guard !self.tasks.is_empty() else { return }
  self.tasks.remove(0)()
}

///|
async fn ReferencesControllerTestTasks::run_all(
  self : ReferencesControllerTestTasks,
) -> Unit noraise {
  while !self.tasks.is_empty() {
    self.run_next()
  }
}

///|
priv struct ReferencesControllerTestHost {
  source_model : @model.TextModel
  surface_generation : Ref[Int]
  current : Ref[Bool]
  container : @rdom.Element
  mount_count : Ref[Int]
  mount_dispose_count : Ref[Int]
  reveal_count : Ref[Int]
  restore_focus_count : Ref[Int]
  opened_resources : Array[String]
  messages : Array[String]
}

///|
fn ReferencesControllerTestHost::host(
  self : ReferencesControllerTestHost,
) -> ReferencesPeekHost {
  {
    is_anchor_current: anchor => {
      self.current.val &&
      anchor.model().same(self.source_model) &&
      anchor.surface_generation() == self.surface_generation.val
    },
    mount: (root, _anchor) => {
      self.mount_count.val += 1
      self.container.append_child(root.as_node())
      let current = Ref(true)
      Some(
        ReferencesPeekMount(
          is_current=() => {
            current.val &&
            self.current.val &&
            @base_browser.element_contains(self.container, root)
          },
          dispose=() => {
            if current.val {
              current.val = false
              self.mount_dispose_count.val += 1
              @base_browser.remove_element(root)
            }
          },
        ),
      )
    },
    reveal_anchor: _anchor => self.reveal_count.val += 1,
    restore_source_focus: () => self.restore_focus_count.val += 1,
    open_location: (location, _mode, _source) => {
      self.opened_resources.push(location.uri.to_string())
      true
    },
    show_message: (_anchor, message) => self.messages.push(message),
  }
}

///|
fn references_controller_test_host(
  model : @model.TextModel,
  surface_generation : Ref[Int],
) -> ReferencesControllerTestHost {
  {
    source_model: model,
    surface_generation,
    current: Ref(true),
    container: @rdom.document().create_element("div"),
    mount_count: Ref(0),
    mount_dispose_count: Ref(0),
    reveal_count: Ref(0),
    restore_focus_count: Ref(0),
    opened_resources: [],
    messages: [],
  }
}

///|
priv struct ReferencesControllerTestPreviewLog {
  resources : Array[String]
  targets : Array[@base_common.Range]
  match_counts : Array[Int]
  modes : Array[@references.ReferencesPeekMode]
  dispose_count : Ref[Int]
  focus_count : Ref[Int]
  contains_focus : Ref[Bool]
  on_dispose : Ref[(() -> Unit)?]
}

///|
fn ReferencesControllerTestPreviewLog::ReferencesControllerTestPreviewLog() -> ReferencesControllerTestPreviewLog {
  {
    resources: [],
    targets: [],
    match_counts: [],
    modes: [],
    dispose_count: Ref(0),
    focus_count: Ref(0),
    contains_focus: Ref(false),
    on_dispose: Ref(None),
  }
}

///|
fn ReferencesControllerTestPreviewLog::factory(
  self : ReferencesControllerTestPreviewLog,
) -> ReferencesPeekPreviewFactory {
  {
    create: (_host, model, target, matches, mode) => {
      self.resources.push(model.uri.to_string())
      self.targets.push(target)
      self.match_counts.push(matches.length())
      self.modes.push(mode)
      Some(
        ReferencesPeekPreview(
          contains_focus=() => self.contains_focus.val,
          focus=() => self.focus_count.val += 1,
          dispose=() => {
            self.dispose_count.val += 1
            match self.on_dispose.val {
              Some(callback) => callback()
              None => ()
            }
          },
        ),
      )
    },
  }
}

///|
fn references_controller_test_model(resource : String) -> @model.TextModel {
  TextModel(
    try! @base_common.Uri::parse(resource),
    "controller.mbt",
    "moonbit",
    1,
    "revision-1",
    "let source = target\nlet second = target\nlet third = target\n",
  )
}

///|
fn references_controller_test_anchor(
  model : @model.TextModel,
  surface_generation : Int,
) -> @goto_symbol.SymbolNavigationAnchor {
  @goto_symbol.SymbolNavigationAnchor::from_model(
    model,
    Position(1, 14),
    Range(1, 14, 1, 20),
    surface_generation,
  )
}

///|
test "preview cancellation callbacks cannot clobber a replacement source" {
  let browser = install_references_peek_test_browser()
  defer browser.dispose()
  let model = references_controller_test_model("file:///cancel-source.mbt")
  defer model.dispose()
  let surface_generation = Ref(1)
  let host = references_controller_test_host(model, surface_generation)
  let tasks = ReferencesControllerTestTasks()
  let controller = ReferencesController(
    host.host(),
    ReferencesControllerTestPreviewLog().factory(),
    resolver?=None,
    task => tasks.schedule(task),
  )
  let old_source = @language.CancellationTokenSource()
  let replacement_source = @language.CancellationTokenSource()
  old_source
  .token()
  .on_cancellation_requested(() => {
    controller.preview_source = Some(replacement_source)
  })
  |> ignore
  controller.preview_source = Some(old_source)
  controller.cancel_preview_request()
  guard controller.preview_source is Some(current_source) else {
    fail("preview cancellation clobbered its replacement source")
  }
  assert_true(physical_equal(current_source, replacement_source))
  controller.preview_source = None
  replacement_source.dispose(cancel=true)
  controller.dispose()
}

///|
async test "controller toggles one surface session and replaces previews in place" {
  let browser = install_references_peek_test_browser()
  defer browser.dispose()
  let model = references_controller_test_model("file:///source.mbt")
  defer model.dispose()
  let surface_generation = Ref(4)
  let host = references_controller_test_host(model, surface_generation)
  let previews = ReferencesControllerTestPreviewLog()
  let tasks = ReferencesControllerTestTasks()
  let controller = ReferencesController(
    host.host(),
    previews.factory(),
    resolver?=None,
    task => tasks.schedule(task),
  )
  let anchor = references_controller_test_anchor(model, surface_generation.val)
  let locations : Array[@language.Location] = [
    { uri: model.uri, range: Range(1, 14, 1, 20), },
    { uri: model.uri, range: Range(2, 14, 2, 20), },
  ]

  assert_true(controller.toggle_locations(anchor, Definitions, locations))
  assert_eq(tasks.tasks.length(), 1)
  tasks.run_all()
  browser.flush_animation_frames()
  assert_eq(host.mount_count.val, 1)
  assert_eq(host.reveal_count.val, 1)
  assert_eq(previews.resources, [model.uri.to_string()])
  assert_eq(previews.targets, [Range(1, 14, 1, 20)])
  assert_eq(previews.match_counts, [2])
  assert_true(controller.phase() is PeekShown(_, _))

  previews.contains_focus.val = true
  controller.move_selection(1)
  assert_eq(previews.dispose_count.val, 0)
  assert_eq(tasks.tasks.length(), 1)
  tasks.run_all()
  assert_eq(previews.dispose_count.val, 1)
  assert_eq(previews.resources.length(), 2)
  assert_eq(previews.targets[1], Range(2, 14, 2, 20))
  assert_eq(previews.focus_count.val, 1)
  assert_true(controller.phase() is PeekShown(_, _))

  assert_true(controller.toggle_locations(anchor, Definitions, locations))
  assert_eq(controller.phase(), PeekClosed)
  assert_eq(host.mount_dispose_count.val, 1)
  assert_eq(previews.dispose_count.val, 2)
  assert_eq(host.restore_focus_count.val, 1)
  controller.dispose()
}

///|
async test "separate controllers keep Code and Markdown-like sessions isolated" {
  let browser = install_references_peek_test_browser()
  defer browser.dispose()
  let model = references_controller_test_model("file:///shared-source.mbt")
  defer model.dispose()
  let code_generation = Ref(1)
  let markdown_generation = Ref(9)
  let code_host = references_controller_test_host(model, code_generation)
  let markdown_host = references_controller_test_host(
    model, markdown_generation,
  )
  let code_preview = ReferencesControllerTestPreviewLog()
  let markdown_preview = ReferencesControllerTestPreviewLog()
  let tasks = ReferencesControllerTestTasks()
  let code = ReferencesController(
    code_host.host(),
    code_preview.factory(),
    resolver?=None,
    task => tasks.schedule(task),
  )
  let markdown = ReferencesController(
    markdown_host.host(),
    markdown_preview.factory(),
    resolver?=None,
    task => tasks.schedule(task),
  )
  let location : @language.Location = {
    uri: model.uri,
    range: Range(1, 14, 1, 20),
  }
  assert_true(
    code.toggle_locations(
      references_controller_test_anchor(model, code_generation.val),
      Definitions,
      [location],
    ),
  )
  assert_true(
    markdown.toggle_locations(
      references_controller_test_anchor(model, markdown_generation.val),
      References,
      [location],
    ),
  )
  tasks.run_all()
  browser.flush_animation_frames()
  assert_true(code.phase() is PeekShown(_, _))
  assert_true(markdown.phase() is PeekShown(_, _))
  code.close(restore_focus=false)
  assert_eq(code.phase(), PeekClosed)
  assert_true(markdown.phase() is PeekShown(_, _))
  assert_eq(code_preview.dispose_count.val, 1)
  assert_eq(markdown_preview.dispose_count.val, 0)

  markdown.dispose()
  code.dispose()
}

///|
async test "dispose marks the controller stale before resource callbacks can reopen it" {
  let browser = install_references_peek_test_browser()
  defer browser.dispose()
  let model = references_controller_test_model("file:///dispose-source.mbt")
  defer model.dispose()
  let surface_generation = Ref(3)
  let host = references_controller_test_host(model, surface_generation)
  let previews = ReferencesControllerTestPreviewLog()
  let tasks = ReferencesControllerTestTasks()
  let controller = ReferencesController(
    host.host(),
    previews.factory(),
    resolver?=None,
    task => tasks.schedule(task),
  )
  let anchor = references_controller_test_anchor(model, surface_generation.val)
  let location : @language.Location = {
    uri: model.uri,
    range: Range(1, 14, 1, 20),
  }
  assert_true(controller.toggle_locations(anchor, Definitions, [location]))
  tasks.run_all()
  assert_true(controller.phase() is PeekShown(_, _))
  let mut reopen_result = true
  previews.on_dispose.val = Some(() => {
    reopen_result = controller.toggle_locations(anchor, Definitions, [location])
  })
  controller.dispose()
  assert_false(reopen_result)
  assert_eq(controller.phase(), PeekClosed)
  assert_eq(host.mount_count.val, 1)
  assert_eq(host.mount_dispose_count.val, 1)
  assert_eq(previews.dispose_count.val, 1)
  browser.flush_animation_frames()
}

///|
async test "resolver leases transfer on preview replacement and release on close" {
  let browser = install_references_peek_test_browser()
  defer browser.dispose()
  let source = references_controller_test_model("file:///source.mbt")
  let target_a = references_controller_test_model("file:///target-a.mbt")
  let target_b = references_controller_test_model("file:///target-b.mbt")
  defer source.dispose()
  defer target_a.dispose()
  defer target_b.dispose()
  let mut release_a = 0
  let mut release_b = 0
  let resolver_calls : Array[String] = []
  let resolver = @navigation_api.TextModelResolverHandle(resolve=(
    resource,
    _token,
  ) => {
    resolver_calls.push(resource.to_string())
    if resource.to_string() == target_a.uri.to_string() {
      Some(TextModelReference(target_a, release=() => release_a += 1))
    } else if resource.to_string() == target_b.uri.to_string() {
      Some(TextModelReference(target_b, release=() => release_b += 1))
    } else {
      None
    }
  })
  let surface_generation = Ref(2)
  let host = references_controller_test_host(source, surface_generation)
  let previews = ReferencesControllerTestPreviewLog()
  let tasks = ReferencesControllerTestTasks()
  let controller = ReferencesController(
    host.host(),
    previews.factory(),
    resolver~,
    task => tasks.schedule(task),
  )
  let locations : Array[@language.Location] = [
    { uri: target_a.uri, range: Range(1, 5, 1, 11), },
    { uri: target_b.uri, range: Range(2, 5, 2, 11), },
  ]
  assert_true(
    controller.toggle_locations(
      references_controller_test_anchor(source, surface_generation.val),
      References,
      locations,
    ),
  )
  // One lease fills the selected group snippets and another owns the editor
  // preview, matching the controller's independent group/preview lifetimes.
  assert_eq(tasks.tasks.length(), 2)
  tasks.run_all()
  assert_eq(resolver_calls.length(), 2)
  assert_eq(resolver_calls[0], target_a.uri.to_string())
  assert_eq(resolver_calls[1], target_a.uri.to_string())
  assert_eq(previews.resources, [target_a.uri.to_string()])
  assert_eq(release_a, 0)

  controller.move_selection(1)
  assert_eq(release_a, 0)
  assert_eq(previews.dispose_count.val, 0)
  assert_eq(tasks.tasks.length(), 2)
  tasks.run_all()
  assert_eq(release_a, 1)
  assert_eq(previews.dispose_count.val, 1)
  assert_eq(resolver_calls.length(), 4)
  assert_eq(resolver_calls[2], target_b.uri.to_string())
  assert_eq(resolver_calls[3], target_b.uri.to_string())
  assert_eq(previews.resources[1], target_b.uri.to_string())
  assert_eq(release_b, 0)

  controller.close(restore_focus=false)
  assert_eq(release_a, 2)
  assert_eq(release_b, 2)
  assert_eq(previews.dispose_count.val, 2)
  assert_false(target_a.is_disposed())
  assert_false(target_b.is_disposed())
  browser.flush_animation_frames()
  controller.dispose()
}

///|
async test "stale and invalid resolver results are released without preview installation" {
  let browser = install_references_peek_test_browser()
  defer browser.dispose()
  let source = references_controller_test_model("file:///source.mbt")
  let requested = references_controller_test_model("file:///requested.mbt")
  let wrong = references_controller_test_model("file:///wrong.mbt")
  defer source.dispose()
  defer requested.dispose()
  defer wrong.dispose()
  let mut releases = 0
  let mut saw_cancelled = false
  let resolver = @navigation_api.TextModelResolverHandle(resolve=(
    _resource,
    token,
  ) => {
    saw_cancelled = token.is_cancellation_requested()
    Some(TextModelReference(wrong, release=() => releases += 1))
  })
  let surface_generation = Ref(5)
  let host = references_controller_test_host(source, surface_generation)
  let previews = ReferencesControllerTestPreviewLog()
  let tasks = ReferencesControllerTestTasks()
  let controller = ReferencesController(
    host.host(),
    previews.factory(),
    resolver~,
    task => tasks.schedule(task),
  )
  let location : @language.Location = {
    uri: requested.uri,
    range: Range(1, 5, 1, 11),
  }
  assert_true(
    controller.toggle_locations(
      references_controller_test_anchor(source, surface_generation.val),
      Definitions,
      [location],
    ),
  )
  controller.close(restore_focus=false)
  tasks.run_all()
  assert_true(saw_cancelled)
  assert_eq(releases, 2)
  assert_eq(previews.resources.length(), 0)
  assert_eq(controller.phase(), PeekClosed)

  assert_true(
    controller.toggle_locations(
      references_controller_test_anchor(source, surface_generation.val),
      Definitions,
      [location],
    ),
  )
  tasks.run_all()
  assert_eq(releases, 4)
  assert_eq(previews.resources.length(), 0)
  assert_true(controller.phase() is PeekUnavailable(_, _))
  browser.flush_animation_frames()
  controller.dispose()
}

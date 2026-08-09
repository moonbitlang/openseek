// Mounted root-controller coverage for the public precomputed-locations
// References Peek entry. Keep every case in one async test: the mounted Viewer
// fixture replaces process DOM globals and independent async tests must not
// install competing fake browser realms.

///|
priv struct ReferencesPeekGuardDefinitionProvider {
  calls : Ref[Int]
}

///|
impl @language.DefinitionProvider for ReferencesPeekGuardDefinitionProvider with fn provide_definition(
  self,
  _model,
  _position,
  _token,
) {
  self.calls.val += 1
  []
}

///|
priv struct PendingReferencesPeekDefinitionProvider {
  calls : Ref[Int]
  locations : Array[@language.Location]
}

///|
impl @language.DefinitionProvider for PendingReferencesPeekDefinitionProvider with fn provide_definition(
  self,
  _model,
  _position,
  _token,
) {
  self.calls.val += 1
  self.locations.copy()
}

///|
priv struct ReferencesPeekQueryProvider {
  calls : Ref[Int]
  locations : Array[@language.Location]
  observed_tokens : Array[@language.CancellationToken]
}

///|
impl @language.ReferencesProvider for ReferencesPeekQueryProvider with fn provide_references(
  self,
  _model,
  _position,
  token,
) {
  self.calls.val += 1
  self.observed_tokens.push(token)
  self.locations.copy()
}

///|
priv struct ManualReferencesPeekTasks {
  tasks : Array[async () -> Unit noraise]
}

///|
fn ManualReferencesPeekTasks::ManualReferencesPeekTasks() -> ManualReferencesPeekTasks {
  { tasks: [] }
}

///|
fn ManualReferencesPeekTasks::schedule(
  self : ManualReferencesPeekTasks,
  task : async () -> Unit noraise,
) -> Unit {
  self.tasks.push(task)
}

///|
async fn ManualReferencesPeekTasks::run_next(
  self : ManualReferencesPeekTasks,
) -> Unit noraise {
  guard !self.tasks.is_empty() else { return }
  self.tasks.remove(0)()
}

///|
async fn ManualReferencesPeekTasks::run_all(
  self : ManualReferencesPeekTasks,
) -> Unit noraise {
  while !self.tasks.is_empty() {
    self.run_next()
  }
}

///|
fn references_peek_test_model(
  resource : String,
  text? : String = "let source = target\n",
) -> @model.TextModel {
  TextModel(
    try! @base_common.Uri::parse(resource),
    @base_common.basename_or_authority(try! @base_common.Uri::parse(resource)),
    "moonbit",
    1,
    "references-peek-test",
    text,
  )
}

///|
fn references_peek_test_services(
  opener? : @navigation_api.LocationOpenerHandle,
  resolver? : @navigation_api.TextModelResolverHandle,
  definition_provider_calls? : Ref[Int],
  references_provider? : &@language.ReferencesProvider,
) -> ViewerServices {
  let languages = @languages.Languages()
  match definition_provider_calls {
    Some(calls) =>
      languages.register_definition_provider(LanguageId("moonbit"), ReferencesPeekGuardDefinitionProvider::{
        calls,
      })
      |> ignore
    None => ()
  }
  match references_provider {
    Some(provider) =>
      languages.register_references_provider(LanguageId("moonbit"), provider)
      |> ignore
    None => ()
  }
  let log_service = @log.LogService()
  ViewerServices(
    languages=languages.language_handle(log_service.log_handle()),
    location_opener?=opener,
    text_model_resolver?=resolver,
    log_service=log_service.log_handle(),
  )
}

///|
fn references_peek_test_viewer(
  services : ViewerServices,
  model : @model.TextModel,
) -> Viewer {
  let host = @rdom.document().create_element("div")
  set_mounted_test_client_size(host, 640.0, 360.0)
  let viewer = Viewer::create(host, services~)
  viewer.set_model(Some(model))
  viewer
}

///|
extern "js" fn references_peek_root_test_text(
  element : @rdom.Element,
) -> String =
  #| element => {
  #|   const read = node => node?.nodeType === 3
  #|     ? String(node.textContent ?? node.nodeValue ?? "")
  #|     : (node?.childNodes ?? []).map(read).join("");
  #|   return read(element);
  #| }

///|
extern "js" fn references_peek_root_test_class_count(
  root : @rdom.Element,
  class_name : String,
) -> Int =
  #| (root, className) => {
  #|   let result = 0;
  #|   const visit = node => {
  #|     if (
  #|       node?.nodeType === 1 &&
  #|       (node.getAttribute("class") ?? "").split(/\s+/).includes(className)
  #|     ) result += 1;
  #|     for (const child of node?.children ?? []) visit(child);
  #|   };
  #|   visit(root);
  #|   return result;
  #| }

///|
fn assert_references_peek_code_mount(viewer : Viewer) -> Unit raise {
  let state = viewer.references_contribution().unwrap()
  guard state.widget is Some(widget) else {
    fail("References Peek widget was not published")
  }
  guard state.zone_id is Some(zone_id) else {
    fail("References Peek ViewZone was not published")
  }
  guard state.overlay_widget is Some(overlay) else {
    fail("References Peek overlay was not published")
  }
  guard viewer.overlay_widget_for_id(overlay.get_id()) is Some(registered) else {
    fail("References Peek overlay registration was not retained")
  }
  assert_true(physical_equal(registered, overlay))
  assert_true(
    same_mounted_test_element(widget.get_dom_node(), overlay.get_dom_node()),
  )
  let whitespaces = viewer.test_view_model().get_whitespaces()
  assert_eq(whitespaces.length(), 1)
  assert_eq(whitespaces[0].id, zone_id)
  let root = viewer.get_dom_node().unwrap()
  assert_eq(
    references_peek_root_test_class_count(
      root, "moonbit-viewer-references-peek",
    ),
    1,
  )
  assert_eq(
    references_peek_root_test_class_count(
      root, "moonbit-viewer-references-peek-zone",
    ),
    1,
  )
}

///|
extern "js" fn references_peek_root_test_dispatch_key(
  element : @rdom.Element,
  key : String,
  shift : Bool,
) -> Bool =
  #| (element, key, shift) => {
  #|   const original = globalThis.KeyboardEvent;
  #|   class MountedKeyboardEvent extends Event {
  #|     constructor(type, options) {
  #|       super(type, options);
  #|       this.key = options.key;
  #|       this.shiftKey = options.shiftKey;
  #|       this.altKey = false;
  #|       this.ctrlKey = false;
  #|       this.metaKey = false;
  #|       this.isComposing = false;
  #|       this.repeat = false;
  #|       this.location = 0;
  #|     }
  #|   }
  #|   globalThis.KeyboardEvent = MountedKeyboardEvent;
  #|   try {
  #|     const event = new MountedKeyboardEvent(
  #|       "keydown",
  #|       { key, shiftKey: shift, bubbles: true, cancelable: true },
  #|     );
  #|     element.dispatchEvent(event);
  #|     return event.defaultPrevented;
  #|   } finally {
  #|     if (original === undefined) delete globalThis.KeyboardEvent;
  #|     else globalThis.KeyboardEvent = original;
  #|   }
  #| }

///|
extern "js" fn references_peek_root_test_row(
  tree : @rdom.Element,
  kind : String,
  index : Int,
) -> @rdom.Element =
  #| (tree, kind, index) => {
  #|   const name = kind === "group"
  #|     ? "data-reference-group-index"
  #|     : "data-reference-flat-index";
  #|   const visit = node => {
  #|     if (
  #|       node?.nodeType === 1 &&
  #|       node.getAttribute("data-reference-row-kind") === kind &&
  #|       node.getAttribute(name) === String(index)
  #|     ) return node;
  #|     for (const child of node?.children ?? []) {
  #|       const found = visit(child);
  #|       if (found) return found;
  #|     }
  #|     return null;
  #|   };
  #|   const result = visit(tree);
  #|   if (!result) throw new Error(`missing ${kind} row ${index}`);
  #|   return result;
  #| }

///|
extern "js" fn references_peek_root_test_tree(
  root : @rdom.Element,
) -> @rdom.Element =
  #| root => {
  #|   const tree = root.querySelector(
  #|     ".moonbit-viewer-reference-results-tree",
  #|   );
  #|   if (!tree) throw new Error("missing reference results tree");
  #|   return tree;
  #| }

///|
fn assert_references_peek_session_key(
  viewer : Viewer,
  model : @model.TextModel,
  anchor : @base_common.Position,
) -> Unit raise {
  let state = viewer.references_contribution().unwrap()
  assert_eq(
    state.session_key,
    Some(
      @references.ReferencesSessionKey::from_model(
        model,
        viewer.model_slot.generation,
        anchor,
      ),
    ),
  )
}

///|
extern "js" fn references_peek_root_test_dispatch_target(
  dispatcher : @rdom.Element,
  target : @rdom.Element,
  event_type : String,
) -> Bool =
  #| (dispatcher, target, eventType) => {
  #|   class TargetEvent extends Event {
  #|     constructor() {
  #|       super(eventType, { bubbles: true, cancelable: true });
  #|     }
  #|     get target() { return target; }
  #|   }
  #|   const event = new TargetEvent();
  #|   dispatcher.dispatchEvent(event);
  #|   return event.defaultPrevented;
  #| }

///|
fn references_peek_decoration_ranges(
  model : @model.TextModel,
  class_name : String,
) -> Array[@base_common.Range] {
  model
  .get_decorations_in_range(model.get_full_model_range())
  .filter_map(decoration => {
    if decoration.options.class_name == class_name {
      Some(decoration.range)
    } else {
      None
    }
  })
}

///|
fn run_references_peek_public_contract_test() -> Unit raise {
  let source = references_peek_test_model(
    "file:///workspace/source.mbt",
    text="let source = target\nlet second = target\n",
  )
  let provider_calls = Ref(0)
  let services = references_peek_test_services(
    definition_provider_calls=provider_calls,
  )

  // The public entry is presentation-only.
  let headless = Viewer(services~)
  headless.set_model(Some(source))
  headless.show_references(Position(1, 1), [])
  assert_true(headless.references_contribution().unwrap().widget is None)
  headless.dispose()

  let viewer = references_peek_test_viewer(services, source)
  let tasks = ManualReferencesPeekTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  let original_uri = source.uri
  let replacement_uri = try! @base_common.Uri::parse(
    "file:///workspace/replaced-by-caller.mbt",
  )
  let locations : Array[@language.Location] = [
    { uri: original_uri, range: Range(1, 14, 1, 20) },
  ]
  let invalid_anchor = @base_common.Position(99, 99)
  let validated_anchor = source.validate_position(invalid_anchor)
  viewer.show_references(invalid_anchor, locations)
  let state = viewer.references_contribution().unwrap()
  assert_eq(state.mode, Some(References))
  assert_references_peek_session_key(viewer, source, validated_anchor)
  assert_eq(state.model.unwrap().references.length(), 1)
  assert_eq(
    state.model.unwrap().references[0].uri_string,
    original_uri.to_string(),
  )
  assert_eq(provider_calls.val, 0)

  // Mutation after the call cannot affect the normalized controller model.
  locations[0] = { uri: replacement_uri, range: Range(2, 1, 2, 2) }
  locations.clear()
  assert_eq(state.model.unwrap().references.length(), 1)
  assert_eq(
    state.model.unwrap().references[0].uri_string,
    original_uri.to_string(),
  )

  // Toggle identity uses the validated anchor, not the invalid caller value.
  viewer.show_references(Position(199, 199), [])
  assert_eq(viewer.definition_peek_phase_for_test(), PeekClosed)
  assert_true(state.widget is None)

  // Empty precomputed results retain an accessible shell.
  viewer.show_references(Position(1, 1), [])
  guard state.widget is Some(empty_widget) else {
    fail("empty references did not retain the Peek shell")
  }
  assert_true(
    references_peek_root_test_text(empty_widget.get_dom_node()).contains(
      "No references found",
    ),
  )
  assert_true(state.model.unwrap().is_empty())
  assert_true(state.preview_viewer is None)

  // A different anchor replaces instead of toggling.
  let empty_generation = state.generation
  viewer.show_references(Position(1, 2), [
    { uri: original_uri, range: Range(2, 14, 2, 20) },
  ])
  assert_true(state.generation > empty_generation)
  assert_references_peek_session_key(viewer, source, Position(1, 2))
  assert_eq(state.model.unwrap().references.length(), 1)

  // A Peek preview Viewer cannot recursively create another shell.
  let nested_host = @rdom.document().create_element("div")
  set_mounted_test_client_size(nested_host, 320.0, 180.0)
  let nested = Viewer(
    services~,
    initial_container=nested_host,
    role=PeekPreviewViewer,
  )
  nested.attach(nested_host)
  nested.set_model(Some(source))
  nested.show_references(Position(1, 1), [
    { uri: original_uri, range: Range(1, 14, 1, 20) },
  ])
  assert_true(nested.references_contribution().unwrap().widget is None)

  nested.dispose()
  viewer.dispose()
  services.dispose()
  source.dispose()
}

///|
async fn run_references_peek_same_resource_test() -> Unit {
  let source = references_peek_test_model(
    "file:///workspace/source.mbt",
    text="let alpha = target\nlet beta = target\n",
  )
  let resolver_calls = Ref(0)
  let resolver = @navigation_api.TextModelResolverHandle(resolve=(
    _resource,
    _token,
  ) => {
    resolver_calls.val += 1
    None
  })
  let opener_calls = Ref(0)
  let opener = @navigation_api.LocationOpenerHandle(open=_request => {
    opener_calls.val += 1
    true
  })
  let services = references_peek_test_services(opener~, resolver~)
  let viewer = references_peek_test_viewer(services, source)
  let tasks = ManualReferencesPeekTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  let locations : Array[@language.Location] = [
    { uri: source.uri, range: Range(1, 13, 1, 19) },
    { uri: source.uri, range: Range(2, 12, 2, 18) },
  ]
  viewer.show_references(Position(1, 1), locations)
  let state = viewer.references_contribution().unwrap()
  guard state.widget is Some(widget) else {
    fail("same-resource References Peek did not open")
  }
  assert_eq(resolver_calls.val, 0)
  assert_eq(
    references_peek_root_test_class_count(
      references_peek_root_test_tree(widget.get_dom_node()),
      "moonbit-viewer-reference-results-snippet-match",
    ),
    2,
  )
  assert_true(
    references_peek_root_test_text(
      references_peek_root_test_tree(widget.get_dom_node()),
    ).contains("target"),
  )
  tasks.run_all()
  guard state.preview_viewer is Some(preview) else {
    fail("same-resource nested preview was not installed")
  }
  assert_true(preview.get_model().unwrap().same(source))
  assert_true(state.preview_reference is None)
  assert_eq(resolver_calls.val, 0)
  assert_eq(
    references_peek_decoration_ranges(
      source, "moonbit-viewer-references-peek-reference-match",
    ).length(),
    2,
  )
  let selected_before = references_peek_decoration_ranges(
    source, "moonbit-viewer-references-peek-reference-match-selected",
  )
  assert_eq(selected_before.length(), 1)
  assert_eq(
    source
    .get_decorations_in_range(source.get_full_model_range())
    .filter(decoration => {
      decoration.options.class_name.has_prefix(
        "moonbit-viewer-references-peek-reference-match",
      )
    })
    .length(),
    3,
  )

  // F4 and Shift+F4 route through the widget and circular controller.
  assert_true(
    references_peek_root_test_dispatch_key(widget.get_dom_node(), "F4", false),
  )
  tasks.run_all()
  assert_eq(state.selected_index, 1)
  let selected_after = references_peek_decoration_ranges(
    source, "moonbit-viewer-references-peek-reference-match-selected",
  )
  assert_eq(selected_after, [locations[1].range])
  assert_true(
    references_peek_root_test_dispatch_key(widget.get_dom_node(), "F4", true),
  )
  tasks.run_all()
  assert_eq(state.selected_index, 0)
  assert_eq(
    references_peek_decoration_ranges(
      source, "moonbit-viewer-references-peek-reference-match-selected",
    ),
    selected_before,
  )

  // Current mode reveals a same-resource result locally and bypasses opener.
  let selected = state.model.unwrap().references[1]
  viewer.confirm_references_peek_item(selected, Current)
  assert_eq(viewer.definition_peek_phase_for_test(), PeekClosed)
  tasks.run_all()
  assert_eq(viewer.get_position(), Some(Position(2, 12)))
  assert_eq(opener_calls.val, 0)
  assert_eq(
    references_peek_decoration_ranges(
      source, "moonbit-viewer-references-peek-reference-match",
    ).length(),
    0,
  )
  assert_eq(
    references_peek_decoration_ranges(
      source, "moonbit-viewer-references-peek-reference-match-selected",
    ).length(),
    0,
  )

  viewer.dispose()
  services.dispose()
  source.dispose()
}

///|
async fn run_references_peek_cross_resource_ownership_test() -> Unit {
  let source = references_peek_test_model("file:///workspace/source.mbt")
  let first = references_peek_test_model(
    "file:///workspace/a.mbt",
    text="let alpha = 1\nlet again = alpha\n",
  )
  let second = references_peek_test_model(
    "file:///z/b.mbt",
    text="let beta = 2\n",
  )
  let requests : Array[String] = []
  let issued : Array[@navigation_api.TextModelReference] = []
  let first_releases = Ref(0)
  let second_releases = Ref(0)
  let resolver = @navigation_api.TextModelResolverHandle(resolve=(
    resource,
    _token,
  ) => {
    let resource_string = resource.to_string()
    requests.push(resource_string)
    let (model, releases) = if resource_string == first.uri.to_string() {
      (first, first_releases)
    } else {
      (second, second_releases)
    }
    let reference = @navigation_api.TextModelReference(model, release=() => {
      releases.val += 1
    })
    issued.push(reference)
    Some(reference)
  })
  let services = references_peek_test_services(resolver~)
  let viewer = references_peek_test_viewer(services, source)
  let tasks = ManualReferencesPeekTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  let locations : Array[@language.Location] = [
    { uri: first.uri, range: Range(1, 5, 1, 10) },
    { uri: first.uri, range: Range(2, 13, 2, 18) },
    { uri: second.uri, range: Range(1, 5, 1, 9) },
  ]
  viewer.show_references(Position(1, 1), locations)
  let state = viewer.references_contribution().unwrap()
  assert_eq(state.selected_index, 0)
  assert_eq(state.group_preview_owners.length(), 2)
  assert_true(state.group_preview_owners[0].source is Some(_))
  assert_true(state.group_preview_owners[1].source is None)
  // The selected group and selected nested preview resolve independently.
  assert_eq(tasks.tasks.length(), 2)
  assert_eq(requests.length(), 0)
  tasks.run_all()
  assert_eq(requests, [first.uri.to_string(), first.uri.to_string()])
  guard state.group_preview_owners[0].reference is Some(group_reference) else {
    fail("selected group did not retain its snippet lease")
  }
  guard state.preview_reference is Some(selected_reference) else {
    fail("selected preview did not retain its independent lease")
  }
  assert_false(physical_equal(group_reference, selected_reference))
  assert_true(state.group_preview_owners[1].reference is None)
  assert_eq(first_releases.val, 0)
  assert_eq(second_releases.val, 0)
  guard state.widget is Some(widget) else {
    fail("cross-resource References Peek lost its widget")
  }
  assert_true(
    references_peek_root_test_text(
      references_peek_root_test_tree(widget.get_dom_node()),
    ).contains("alpha"),
  )
  assert_eq(
    references_peek_decoration_ranges(
      first, "moonbit-viewer-references-peek-reference-match",
    ).length(),
    2,
  )
  assert_eq(
    references_peek_decoration_ranges(
      first, "moonbit-viewer-references-peek-reference-match-selected",
    ).length(),
    1,
  )

  // The collapsed second group has not resolved until expansion asks for it.
  let result_model = state.model.unwrap()
  viewer.load_references_peek_group(result_model.groups[1])
  assert_eq(tasks.tasks.length(), 1)
  tasks.run_all()
  assert_eq(requests, [
    first.uri.to_string(),
    first.uri.to_string(),
    second.uri.to_string(),
  ])
  assert_true(state.group_preview_owners[1].reference is Some(_))
  assert_true(
    references_peek_root_test_text(
      references_peek_root_test_tree(widget.get_dom_node()),
    ).contains("beta"),
  )

  // Selecting across groups obtains a distinct selected lease and swaps all
  // active-resource decorations while retaining both group leases. The old
  // child and selected lease remain installed until the replacement is ready
  // to commit.
  guard state.preview_viewer is Some(first_preview) else {
    fail("first cross-resource preview was not installed")
  }
  first_preview.focus()
  assert_true(first_preview.has_text_focus())
  viewer.select_references_peek_result(2)
  assert_eq(tasks.tasks.length(), 1)
  assert_false(first_preview.disposed)
  assert_eq(first_releases.val, 0)
  tasks.run_next()
  assert_false(first_preview.disposed)
  assert_eq(first_releases.val, 0)
  assert_eq(tasks.tasks.length(), 1)
  // A user focus move while resolution is pending wins over automatic
  // restoration sampled at replacement commit time.
  match first_preview.mount {
    Mounted(mounted) => mounted.set_editor_focus(false) |> ignore
    Headless => fail("cross-resource preview unexpectedly became headless")
  }
  viewer.focus()
  tasks.run_all()
  assert_eq(requests.last(), Some(second.uri.to_string()))
  assert_eq(first_releases.val, 1)
  assert_eq(second_releases.val, 0)
  assert_true(first_preview.disposed)
  guard state.preview_viewer is Some(second_preview) else {
    fail("second cross-resource preview was not installed")
  }
  assert_false(second_preview.has_text_focus())
  assert_true(state.group_preview_owners[0].reference is Some(_))
  assert_true(state.group_preview_owners[1].reference is Some(_))
  assert_true(state.preview_reference is Some(_))
  assert_eq(
    references_peek_decoration_ranges(
      first, "moonbit-viewer-references-peek-reference-match",
    ).length(),
    0,
  )
  assert_eq(
    references_peek_decoration_ranges(
      second, "moonbit-viewer-references-peek-reference-match",
    ),
    [locations[2].range],
  )
  assert_eq(
    references_peek_decoration_ranges(
      second, "moonbit-viewer-references-peek-reference-match-selected",
    ),
    [locations[2].range],
  )

  viewer.close_references_peek(restore_focus=false)
  assert_eq(first_releases.val, 2)
  assert_eq(second_releases.val, 2)
  assert_true(state.group_preview_owners.is_empty())
  assert_true(state.preview_reference is None)
  assert_true(state.preview_decorations is None)
  // TextModelReference itself enforces exactly-once release even when an old
  // host retains and redundantly disposes the issued lease values.
  for reference in issued {
    reference.dispose()
  }
  assert_eq(first_releases.val, 2)
  assert_eq(second_releases.val, 2)

  viewer.dispose()
  services.dispose()
  source.dispose()
  first.dispose()
  second.dispose()
}

///|
async fn run_references_peek_failure_and_opening_test() -> Unit {
  let source = references_peek_test_model("file:///workspace/source.mbt")
  let target_uri = try! @base_common.Uri::parse("file:///workspace/target.mbt")
  let open_requests : Array[@navigation_api.OpenLocationRequest] = []
  let opener = @navigation_api.LocationOpenerHandle(open=request => {
    open_requests.push(request)
    true
  })

  // A missing resolver keeps both the selectable fallback row and the
  // unavailable selected-preview state. Current and Side both use the host
  // opener for cross-resource results.
  let missing_services = references_peek_test_services(opener~)
  let missing_viewer = references_peek_test_viewer(missing_services, source)
  let missing_tasks = ManualReferencesPeekTasks()
  missing_viewer.set_definition_host_for_test(task => {
    missing_tasks.schedule(task)
  })
  let target : @language.Location = {
    uri: target_uri,
    range: Range(1, 5, 1, 11),
  }
  missing_viewer.show_references(Position(1, 1), [target])
  let missing_state = missing_viewer.references_contribution().unwrap()
  match missing_viewer.definition_peek_phase_for_test() {
    PeekUnavailable(_, _) => ()
    _ => fail("missing resolver did not expose unavailable preview")
  }
  guard missing_state.widget is Some(missing_widget) else {
    fail("missing-resolver fallback lost its shell")
  }
  assert_true(
    references_peek_root_test_text(
      references_peek_root_test_tree(missing_widget.get_dom_node()),
    ).contains("target.mbt:1:5"),
  )
  let missing_item = missing_state.model.unwrap().references[0]
  missing_viewer.confirm_references_peek_item(missing_item, Current)
  missing_tasks.run_all()
  assert_eq(open_requests.length(), 1)
  assert_eq(open_requests[0].mode, Current)
  assert_eq(open_requests[0].location.uri.to_string(), target.uri.to_string())
  assert_eq(open_requests[0].location.range, target.range)

  missing_viewer.show_references(Position(1, 2), [target])
  let side_item = missing_state.model.unwrap().references[0]
  missing_viewer.confirm_references_peek_item(side_item, Side)
  missing_tasks.run_all()
  assert_eq(open_requests.length(), 2)
  assert_eq(open_requests[1].mode, Side)
  assert_eq(open_requests[1].location.uri.to_string(), target.uri.to_string())
  assert_eq(open_requests[1].location.range, target.range)
  missing_viewer.dispose()
  missing_services.dispose()

  // Resolver `None` is a completed failure distinct from an absent service:
  // both the group and selected-preview request retire without a lease.
  let failed_calls = Ref(0)
  let failed_resolver = @navigation_api.TextModelResolverHandle(resolve=(
    _resource,
    _token,
  ) => {
    failed_calls.val += 1
    None
  })
  let failed_services = references_peek_test_services(resolver=failed_resolver)
  let failed_viewer = references_peek_test_viewer(failed_services, source)
  let failed_tasks = ManualReferencesPeekTasks()
  failed_viewer.set_definition_host_for_test(task => failed_tasks.schedule(task))
  failed_viewer.show_references(Position(1, 3), [target])
  failed_tasks.run_all()
  let failed_state = failed_viewer.references_contribution().unwrap()
  assert_eq(failed_calls.val, 2)
  assert_true(failed_state.group_preview_owners[0].source is None)
  assert_true(failed_state.group_preview_owners[0].reference is None)
  assert_true(failed_state.preview_source is None)
  assert_true(failed_state.preview_reference is None)
  match failed_viewer.definition_peek_phase_for_test() {
    PeekUnavailable(_, _) => ()
    _ => fail("resolver None did not expose unavailable preview")
  }
  failed_viewer.dispose()
  failed_services.dispose()

  // Wrong-resource leases are never committed and each independent request
  // releases its returned reference exactly once.
  let wrong = references_peek_test_model(
    "file:///workspace/wrong.mbt",
    text="let wrong = 1\n",
  )
  let wrong_releases = Ref(0)
  let wrong_issued : Array[@navigation_api.TextModelReference] = []
  let wrong_resolver = @navigation_api.TextModelResolverHandle(resolve=(
    _resource,
    _token,
  ) => {
    let reference = @navigation_api.TextModelReference(wrong, release=() => {
      wrong_releases.val += 1
    })
    wrong_issued.push(reference)
    Some(reference)
  })
  let wrong_services = references_peek_test_services(resolver=wrong_resolver)
  let wrong_viewer = references_peek_test_viewer(wrong_services, source)
  let wrong_tasks = ManualReferencesPeekTasks()
  wrong_viewer.set_definition_host_for_test(task => wrong_tasks.schedule(task))
  wrong_viewer.show_references(Position(1, 4), [target])
  wrong_tasks.run_all()
  let wrong_state = wrong_viewer.references_contribution().unwrap()
  assert_eq(wrong_issued.length(), 2)
  assert_eq(wrong_releases.val, 2)
  assert_true(wrong_state.group_preview_owners[0].reference is None)
  assert_true(wrong_state.preview_reference is None)
  match wrong_viewer.definition_peek_phase_for_test() {
    PeekUnavailable(_, _) => ()
    _ => fail("wrong-URI selected preview did not become unavailable")
  }
  for reference in wrong_issued {
    reference.dispose()
  }
  assert_eq(wrong_releases.val, 2)

  wrong_viewer.dispose()
  wrong_services.dispose()
  source.dispose()
  wrong.dispose()
}

///|
async fn run_references_peek_stale_resolution_test() -> Unit {
  let source = references_peek_test_model("file:///workspace/source.mbt")
  let replacement_source = references_peek_test_model(
    "file:///workspace/replacement-source.mbt",
  )
  let target = references_peek_test_model(
    "file:///workspace/target.mbt",
    text="let target = 1\n",
  )
  let location : @language.Location = {
    uri: target.uri,
    range: Range(1, 5, 1, 11),
  }
  let releases = Ref(0)
  let issued : Array[@navigation_api.TextModelReference] = []
  let tokens : Array[@language.CancellationToken] = []
  let resolver = @navigation_api.TextModelResolverHandle(resolve=(
    _resource,
    token,
  ) => {
    tokens.push(token)
    let reference = @navigation_api.TextModelReference(target, release=() => {
      releases.val += 1
    })
    issued.push(reference)
    Some(reference)
  })
  let services = references_peek_test_services(resolver~)
  let viewer = references_peek_test_viewer(services, source)
  let tasks = ManualReferencesPeekTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  let state = viewer.references_contribution().unwrap()

  // A non-cooperative resolver can return after cancellation, but both the
  // group and selected-preview leases are rejected and released.
  viewer.show_references(Position(1, 1), [location])
  assert_eq(tasks.tasks.length(), 2)
  viewer.close_references_peek(restore_focus=false)
  tasks.run_all()
  assert_eq(releases.val, 2)
  assert_true(tokens.all(token => token.is_cancellation_requested()))
  assert_eq(viewer.definition_peek_phase_for_test(), PeekClosed)
  assert_true(state.preview_viewer is None)
  assert_true(state.group_preview_owners.is_empty())

  // Attachment replacement invalidates the complete source freshness
  // denominator before either late resolver result can commit.
  viewer.show_references(Position(1, 2), [location])
  assert_eq(tasks.tasks.length(), 2)
  viewer.set_model(Some(replacement_source))
  assert_eq(viewer.definition_peek_phase_for_test(), PeekClosed)
  tasks.run_all()
  assert_eq(releases.val, 4)
  assert_true(state.preview_viewer is None)
  assert_true(state.widget is None)

  // Content version replacement has the same stale-result contract.
  viewer.set_model(Some(source))
  viewer.show_references(Position(1, 3), [location])
  assert_eq(tasks.tasks.length(), 2)
  viewer.set_value("let source = changed\n")
  assert_eq(viewer.definition_peek_phase_for_test(), PeekClosed)
  tasks.run_all()
  assert_eq(releases.val, 6)
  assert_true(state.preview_viewer is None)
  assert_true(state.widget is None)

  // Disposal detaches every owner before late callbacks run.
  viewer.show_references(Position(1, 4), [location])
  assert_eq(tasks.tasks.length(), 2)
  viewer.dispose()
  tasks.run_all()
  assert_eq(releases.val, 8)
  assert_true(state.preview_viewer is None)
  assert_true(state.group_preview_owners.is_empty())
  for reference in issued {
    reference.dispose()
  }
  assert_eq(releases.val, 8)

  services.dispose()
  source.dispose()
  replacement_source.dispose()
  target.dispose()
}

///|
fn run_references_peek_stale_widget_callback_test() -> Unit raise {
  let source = references_peek_test_model("file:///workspace/source.mbt")
  let first_uri = try! @base_common.Uri::parse("file:///workspace/a.mbt")
  let second_uri = try! @base_common.Uri::parse("file:///workspace/b.mbt")
  let open_requests : Array[@navigation_api.OpenLocationRequest] = []
  let opener = @navigation_api.LocationOpenerHandle(open=request => {
    open_requests.push(request)
    true
  })
  let services = references_peek_test_services(opener~)
  let viewer = references_peek_test_viewer(services, source)
  let tasks = ManualReferencesPeekTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  let locations : Array[@language.Location] = [
    { uri: first_uri, range: Range(1, 1, 1, 2) },
    { uri: second_uri, range: Range(1, 1, 1, 2) },
  ]
  viewer.show_references(Position(1, 1), locations)
  let state = viewer.references_contribution().unwrap()
  guard state.widget is Some(old_widget) else {
    fail("initial stale-callback widget was not installed")
  }
  let old_tree = references_peek_root_test_tree(old_widget.get_dom_node())
  let old_second_reference = references_peek_root_test_row(
    old_tree, "reference", 1,
  )
  let old_second_group = references_peek_root_test_row(old_tree, "group", 1)

  // Install an identical result model in a newer generation. Value equality
  // alone cannot distinguish the old items, so disposed event paths and root
  // generation guards must reject all old-widget activity.
  viewer.show_references(Position(1, 2), locations)
  let replacement_generation = state.generation
  guard state.widget is Some(replacement_widget) else {
    fail("replacement stale-callback widget was not installed")
  }
  assert_false(physical_equal(old_widget, replacement_widget))
  assert_eq(state.selected_index, 0)
  assert_false(
    references_peek_root_test_dispatch_target(
      old_tree, old_second_reference, "click",
    ),
  )
  assert_false(
    references_peek_root_test_dispatch_target(
      old_tree, old_second_reference, "dblclick",
    ),
  )
  assert_false(
    references_peek_root_test_dispatch_target(
      old_tree, old_second_group, "click",
    ),
  )
  assert_false(
    references_peek_root_test_dispatch_key(
      old_widget.get_dom_node(),
      "F4",
      false,
    ),
  )
  assert_eq(state.generation, replacement_generation)
  assert_eq(state.selected_index, 0)
  assert_true(
    state.widget is Some(current_widget) &&
    physical_equal(current_widget, replacement_widget),
  )
  assert_eq(open_requests.length(), 0)
  assert_eq(tasks.tasks.length(), 0)

  viewer.dispose()
  services.dispose()
  source.dispose()
}

///|
async fn run_references_peek_reentrant_release_test() -> Unit {
  let source = references_peek_test_model(
    "file:///workspace/source.mbt",
    text="let source = target\n",
  )
  let old_target = references_peek_test_model(
    "file:///workspace/old-target.mbt",
    text="let old = 1\n",
  )
  let old_location : @language.Location = {
    uri: old_target.uri,
    range: Range(1, 5, 1, 8),
  }
  let releases = Ref(0)
  let issued : Array[@navigation_api.TextModelReference] = []
  let armed = Ref(false)
  let release_hook : Ref[() -> Unit] = Ref(() => ())
  let resolver = @navigation_api.TextModelResolverHandle(resolve=(
    _resource,
    _token,
  ) => {
    let reference = @navigation_api.TextModelReference(old_target, release=() => {
      releases.val += 1
      if armed.val {
        armed.val = false
        (release_hook.val)()
      }
    })
    issued.push(reference)
    Some(reference)
  })
  let services = references_peek_test_services(resolver~)
  let viewer = references_peek_test_viewer(services, source)
  let tasks = ManualReferencesPeekTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  viewer.show_references(Position(1, 1), [old_location])
  tasks.run_all()
  let state = viewer.references_contribution().unwrap()
  assert_true(state.group_preview_owners[0].reference is Some(_))
  assert_true(state.preview_reference is Some(_))

  let reentrant_anchor = @base_common.Position(1, 4)
  let reentrant_location : @language.Location = {
    uri: source.uri,
    range: Range(1, 14, 1, 20),
  }
  let outer_location : @language.Location = {
    uri: source.uri,
    range: Range(1, 5, 1, 11),
  }
  release_hook.val = () => {
    viewer.show_references(reentrant_anchor, [reentrant_location])
  }
  armed.val = true
  // The outer replacement starts by closing the old session. Its old selected
  // lease re-enters and opens a newer session; the outer call must then abort
  // instead of overwriting that new widget/owner set.
  viewer.show_references(Position(1, 5), [outer_location])
  assert_eq(releases.val, 2)
  assert_references_peek_session_key(viewer, source, reentrant_anchor)
  assert_eq(state.model.unwrap().references[0].range, reentrant_location.range)
  assert_eq(state.mode, Some(References))
  assert_true(state.widget is Some(_))
  assert_eq(state.group_preview_owners.length(), 1)
  assert_true(state.group_preview_owners[0].reference is None)
  // The old shell retained a same-id overlay handle. Its remaining teardown
  // must not unregister or unmount the newer reentrant Code shell.
  assert_references_peek_code_mount(viewer)
  tasks.run_all()
  match viewer.definition_peek_phase_for_test() {
    PeekShown(_, _) => ()
    _ => fail("reentrant newer References session was not retained")
  }
  assert_references_peek_code_mount(viewer)
  for reference in issued {
    reference.dispose()
  }
  assert_eq(releases.val, 2)

  viewer.dispose()
  services.dispose()
  source.dispose()
  old_target.dispose()
}

///|
async fn run_references_peek_reentrant_model_swap_zone_test() -> Unit {
  let old_source = references_peek_test_model(
    "file:///workspace/old-source.mbt",
    text="let old_source = target\n",
  )
  let new_source = references_peek_test_model(
    "file:///workspace/new-source.mbt",
    text="let new_source = target\n",
  )
  let old_target = references_peek_test_model(
    "file:///workspace/old-zone-target.mbt",
    text="let old_target = 1\n",
  )
  let armed = Ref(false)
  let releases = Ref(0)
  let release_hook : Ref[() -> Unit] = Ref(() => ())
  let resolver = @navigation_api.TextModelResolverHandle(resolve=(
    _resource,
    _token,
  ) => {
    Some(
      TextModelReference(old_target, release=() => {
        releases.val += 1
        if armed.val {
          armed.val = false
          (release_hook.val)()
        }
      }),
    )
  })
  let services = references_peek_test_services(resolver~)
  let viewer = references_peek_test_viewer(services, old_source)
  let tasks = ManualReferencesPeekTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  let old_location : @language.Location = {
    uri: old_target.uri,
    range: Range(1, 5, 1, 15),
  }
  viewer.show_references(Position(1, 1), [old_location])
  tasks.run_all()
  let state = viewer.references_contribution().unwrap()
  let old_zone_id = state.zone_id.unwrap()
  assert_true(state.preview_reference is Some(_))
  assert_true(state.group_preview_owners[0].reference is Some(_))

  let new_anchor = @base_common.Position(1, 3)
  let new_location : @language.Location = {
    uri: new_source.uri,
    range: Range(1, 18, 1, 24),
  }
  release_hook.val = () => {
    // The new model owns a fresh View whose first whitespace deliberately
    // receives the same model-scoped id as the outgoing ViewZone. Monaco's
    // single-letter per-layout namespace wraps after 52 instances; the old
    // nested preview already consumed one successor, so 50 fillers make the
    // replacement root collide deterministically.
    for _ in 0..<50 {
      @view_layout.LinesLayout(1, 18, 0, 0) |> ignore
    }
    viewer.set_model(Some(new_source))
    viewer.show_references(new_anchor, [new_location])
  }
  armed.val = true
  viewer.close_references_peek(restore_focus=false)

  assert_true(viewer.get_model() is Some(model) && model.same(new_source))
  assert_references_peek_session_key(viewer, new_source, new_anchor)
  assert_eq(state.model.unwrap().references[0].range, new_location.range)
  assert_eq(state.zone_id, Some(old_zone_id))
  assert_eq(releases.val, 2)
  assert_eq(tasks.tasks.length(), 1)
  assert_references_peek_code_mount(viewer)

  viewer.dispose()
  services.dispose()
  old_source.dispose()
  new_source.dispose()
  old_target.dispose()
}

///|
async fn run_references_peek_reentrant_preview_cancellation_test() -> Unit {
  let source = references_peek_test_model(
    "file:///workspace/source.mbt",
    text="let source = target\n",
  )
  let old_target = references_peek_test_model(
    "file:///workspace/old-preview.mbt",
    text="let old = 1\nlet old_again = old\n",
  )
  let new_target = references_peek_test_model(
    "file:///workspace/new-preview.mbt",
    text="let newer = 2\n",
  )
  let resolver = @navigation_api.TextModelResolverHandle(resolve=(
    resource,
    _token,
  ) => {
    let model = if resource.to_string() == old_target.uri.to_string() {
      old_target
    } else {
      new_target
    }
    Some(TextModelReference(model, release=() => ()))
  })
  let services = references_peek_test_services(resolver~)
  let viewer = references_peek_test_viewer(services, source)
  let tasks = ManualReferencesPeekTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  let old_locations : Array[@language.Location] = [
    { uri: old_target.uri, range: Range(1, 5, 1, 8) },
    { uri: old_target.uri, range: Range(2, 17, 2, 20) },
  ]
  viewer.show_references(Position(1, 1), old_locations)
  let state = viewer.references_contribution().unwrap()
  let old_generation = state.generation
  guard state.widget is Some(old_widget) else {
    fail("old cancellation-test widget was not installed")
  }
  guard state.preview_source is Some(old_source) else {
    fail("old selected preview did not retain a request source")
  }
  let new_anchor = @base_common.Position(1, 4)
  let new_location : @language.Location = {
    uri: new_target.uri,
    range: Range(1, 5, 1, 10),
  }
  let reentered = Ref(false)
  let captured_generation = Ref(-1)
  let captured_preview_generation = Ref(-1)
  let captured_widget : Ref[@references_browser.ReferencesPeekWidget?] = Ref(
    None,
  )
  let captured_source : Ref[@language.CancellationTokenSource?] = Ref(None)
  let cancellation_listener = old_source
    .token()
    .on_cancellation_requested(() => {
      reentered.val = true
      viewer.show_references(new_anchor, [new_location])
      captured_generation.val = state.generation
      captured_preview_generation.val = state.preview_generation
      captured_widget.val = state.widget
      captured_source.val = state.preview_source
    })
  defer cancellation_listener.dispose()

  // Cancelling the old selected request synchronously opens a newer session.
  // The stale outer selection must return before touching that new shell or
  // replacing its independently owned request source.
  viewer.load_references_peek_preview(old_generation, 1)
  assert_true(reentered.val)
  assert_true(state.generation > old_generation)
  assert_eq(state.generation, captured_generation.val)
  assert_eq(state.preview_generation, captured_preview_generation.val)
  assert_references_peek_session_key(viewer, source, new_anchor)
  assert_eq(state.model.unwrap().references[0].range, new_location.range)
  assert_eq(state.selected_index, 0)
  guard captured_widget.val is Some(new_widget) else {
    fail("cancellation listener did not capture the newer widget")
  }
  assert_false(physical_equal(old_widget, new_widget))
  assert_true(
    state.widget is Some(current_widget) &&
    physical_equal(current_widget, new_widget),
  )
  guard captured_source.val is Some(new_source) else {
    fail("cancellation listener did not capture the newer preview source")
  }
  assert_true(
    state.preview_source is Some(current_source) &&
    physical_equal(current_source, new_source),
  )
  assert_false(new_source.token().is_cancellation_requested())
  assert_eq(
    state.phase,
    PeekLoadingPreview(captured_generation.val, captured_preview_generation.val),
  )
  assert_eq(tasks.tasks.length(), 4)
  assert_references_peek_code_mount(viewer)

  tasks.run_all()
  assert_true(state.preview_source is None)
  assert_true(
    state.preview_viewer is Some(preview) &&
    preview.get_model() is Some(preview_model) &&
    preview_model.same(new_target),
  )
  match state.phase {
    PeekShown(generation, _) => assert_eq(generation, captured_generation.val)
    _ => fail("newer preview remained stuck after stale cancellation returned")
  }
  assert_references_peek_code_mount(viewer)

  viewer.dispose()
  services.dispose()
  source.dispose()
  old_target.dispose()
  new_target.dispose()
}

///|
async fn run_references_peek_reentrant_set_selected_test() -> Unit {
  let source = references_peek_test_model(
    "file:///workspace/source.mbt",
    text="let source = target\n",
  )
  let first_target = references_peek_test_model(
    "file:///workspace/a-selected.mbt",
    text="let first = 1\n",
  )
  let second_target = references_peek_test_model(
    "file:///workspace/b-selected.mbt",
    text="let second = 2\n",
  )
  let new_target = references_peek_test_model(
    "file:///workspace/new-selected.mbt",
    text="let newer = 3\n",
  )
  let resolver = @navigation_api.TextModelResolverHandle(resolve=(
    resource,
    _token,
  ) => {
    let resource_string = resource.to_string()
    let model = if resource_string == first_target.uri.to_string() {
      first_target
    } else if resource_string == second_target.uri.to_string() {
      second_target
    } else {
      new_target
    }
    Some(TextModelReference(model, release=() => ()))
  })
  let services = references_peek_test_services(resolver~)
  let viewer = references_peek_test_viewer(services, source)
  let tasks = ManualReferencesPeekTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  viewer.show_references(Position(1, 1), [
    { uri: first_target.uri, range: Range(1, 5, 1, 10) },
    { uri: second_target.uri, range: Range(1, 5, 1, 11) },
  ])
  let state = viewer.references_contribution().unwrap()
  let old_generation = state.generation
  guard state.widget is Some(old_widget) else {
    fail("old set-selected widget was not installed")
  }
  assert_eq(tasks.tasks.length(), 2)

  let armed = Ref(true)
  let new_anchor = @base_common.Position(1, 5)
  let new_location : @language.Location = {
    uri: new_target.uri,
    range: Range(1, 5, 1, 10),
  }
  let captured_generation = Ref(-1)
  let captured_preview_generation = Ref(-1)
  let captured_widget : Ref[@references_browser.ReferencesPeekWidget?] = Ref(
    None,
  )
  let captured_source : Ref[@language.CancellationTokenSource?] = Ref(None)
  state.launch_async_task = task => {
    if armed.val {
      // Selecting the collapsed second group enters this host from
      // `set_selected` -> `on_expand_group`.
      armed.val = false
      viewer.show_references(new_anchor, [new_location])
      captured_generation.val = state.generation
      captured_preview_generation.val = state.preview_generation
      captured_widget.val = state.widget
      captured_source.val = state.preview_source
    } else {
      tasks.schedule(task)
    }
  }
  viewer.select_references_peek_result(1)

  assert_false(armed.val)
  assert_true(state.generation > old_generation)
  assert_eq(state.generation, captured_generation.val)
  assert_eq(state.preview_generation, captured_preview_generation.val)
  assert_references_peek_session_key(viewer, source, new_anchor)
  assert_eq(state.model.unwrap().references[0].range, new_location.range)
  assert_eq(state.selected_index, 0)
  guard captured_widget.val is Some(new_widget) else {
    fail("group-expansion reentry did not capture the newer widget")
  }
  assert_false(physical_equal(old_widget, new_widget))
  assert_true(
    state.widget is Some(current_widget) &&
    physical_equal(current_widget, new_widget),
  )
  guard captured_source.val is Some(new_source) else {
    fail("group-expansion reentry did not capture the newer preview source")
  }
  assert_true(
    state.preview_source is Some(current_source) &&
    physical_equal(current_source, new_source),
  )
  assert_false(new_source.token().is_cancellation_requested())
  assert_eq(
    state.phase,
    PeekLoadingPreview(captured_generation.val, captured_preview_generation.val),
  )
  assert_eq(tasks.tasks.length(), 4)
  assert_references_peek_code_mount(viewer)
  tasks.run_all()
  assert_true(
    state.preview_viewer is Some(preview) &&
    preview.get_model() is Some(preview_model) &&
    preview_model.same(new_target),
  )
  match state.phase {
    PeekShown(generation, _) => assert_eq(generation, captured_generation.val)
    _ => fail("newer preview was corrupted after set-selected reentry")
  }
  assert_references_peek_code_mount(viewer)

  viewer.dispose()
  services.dispose()
  source.dispose()
  first_target.dispose()
  second_target.dispose()
  new_target.dispose()
}

///|
async fn run_references_peek_reentrant_preview_commit_test() -> Unit {
  let source = references_peek_test_model(
    "file:///workspace/source.mbt",
    text="let source = target\n",
  )
  let target = references_peek_test_model(
    "file:///workspace/commit-target.mbt",
    text="let target = 1\n",
  )
  let releases = Ref(0)
  let resolver = @navigation_api.TextModelResolverHandle(resolve=(
    _resource,
    _token,
  ) => Some(TextModelReference(target, release=() => releases.val += 1)))
  let services = references_peek_test_services(resolver~)
  let viewer = references_peek_test_viewer(services, source)
  let tasks = ManualReferencesPeekTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  let old_location : @language.Location = {
    uri: target.uri,
    range: Range(1, 5, 1, 11),
  }
  viewer.show_references(Position(1, 1), [old_location])
  let state = viewer.references_contribution().unwrap()
  // Resolve the group and selected lease, leaving only the selected-preview
  // commit task pending.
  tasks.run_next()
  tasks.run_next()
  assert_eq(tasks.tasks.length(), 1)

  let new_anchor = @base_common.Position(1, 6)
  let new_location : @language.Location = {
    uri: source.uri,
    range: Range(1, 14, 1, 20),
  }
  let reentered = Ref(false)
  let captured_generation = Ref(-1)
  let captured_preview_generation = Ref(-1)
  let captured_widget : Ref[@references_browser.ReferencesPeekWidget?] = Ref(
    None,
  )
  let decoration_listener = target.on_did_change_decorations(_event => {
    let has_preview_match = target
      .get_decorations_in_range(target.get_full_model_range())
      .any(decoration => {
        decoration.options.class_name.has_prefix(
          "moonbit-viewer-references-peek-reference-match",
        )
      })
    if !reentered.val && has_preview_match {
      reentered.val = true
      viewer.show_references(new_anchor, [new_location])
      captured_generation.val = state.generation
      captured_preview_generation.val = state.preview_generation
      captured_widget.val = state.widget
    }
  })
  defer decoration_listener.dispose()

  // Creating the provisional preview collection emits synchronously on the
  // target model. The listener installs a newer session before the stale
  // collection call returns.
  tasks.run_next()
  assert_true(reentered.val)
  assert_eq(state.generation, captured_generation.val)
  assert_eq(state.preview_generation, captured_preview_generation.val)
  assert_references_peek_session_key(viewer, source, new_anchor)
  assert_eq(state.model.unwrap().references[0].range, new_location.range)
  guard captured_widget.val is Some(new_widget) else {
    fail("decoration reentry did not capture the newer widget")
  }
  assert_true(
    state.widget is Some(current_widget) &&
    physical_equal(current_widget, new_widget),
  )
  assert_true(state.preview_viewer is None)
  assert_true(state.preview_reference is None)
  assert_true(state.preview_decorations is None)
  assert_true(state.preview_resize_observer is None)
  assert_true(state.preview_layout_frame is None)
  assert_eq(
    state.phase,
    PeekLoadingPreview(captured_generation.val, captured_preview_generation.val),
  )
  assert_eq(
    target
    .get_decorations_in_range(target.get_full_model_range())
    .filter(decoration => {
      decoration.options.class_name.has_prefix(
        "moonbit-viewer-references-peek-reference-match",
      )
    })
    .length(),
    0,
  )
  assert_eq(releases.val, 2)
  assert_eq(tasks.tasks.length(), 1)
  assert_references_peek_code_mount(viewer)
  tasks.run_all()
  match state.phase {
    PeekShown(generation, _) => assert_eq(generation, captured_generation.val)
    _ => fail("newer session was corrupted by stale preview commit")
  }
  assert_true(
    state.preview_viewer is Some(preview) &&
    preview.get_model() is Some(preview_model) &&
    preview_model.same(source),
  )
  assert_references_peek_code_mount(viewer)

  viewer.dispose()
  services.dispose()
  source.dispose()
  target.dispose()
}

///|
async fn run_references_peek_reentrant_view_zone_test() -> Unit {
  let source = references_peek_test_model(
    "file:///workspace/source.mbt",
    text="let first = target\nlet second = target\n",
  )
  let services = references_peek_test_services()
  let viewer = references_peek_test_viewer(services, source)
  let tasks = ManualReferencesPeekTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  let outer_anchor = @base_common.Position(1, 1)
  let outer_location : @language.Location = {
    uri: source.uri,
    range: Range(1, 13, 1, 19),
  }
  let inner_anchor = @base_common.Position(2, 1)
  let inner_location : @language.Location = {
    uri: source.uri,
    range: Range(2, 14, 2, 20),
  }
  let state = viewer.references_contribution().unwrap()
  let reentered = Ref(false)
  let event_count = Ref(0)
  let captured_generation = Ref(-1)
  let captured_widget : Ref[@references_browser.ReferencesPeekWidget?] = Ref(
    None,
  )
  let captured_zone_id : Ref[String?] = Ref(None)
  let captured_overlay : Ref[@editor_browser.OverlayWidget?] = Ref(None)
  let listener = viewer.on_did_change_view_zones(() => {
    event_count.val += 1
    if !reentered.val {
      // Arm before the nested mutation because its own ViewZone event is
      // delivered synchronously through the public event source.
      reentered.val = true
      viewer.show_references(inner_anchor, [inner_location])
      captured_generation.val = state.generation
      captured_widget.val = state.widget
      captured_zone_id.val = state.zone_id
      captured_overlay.val = state.overlay_widget
    }
  })
  viewer.show_references(outer_anchor, [outer_location])
  listener.dispose()

  assert_true(reentered.val)
  assert_true(event_count.val >= 1)
  assert_eq(state.generation, captured_generation.val)
  assert_references_peek_session_key(viewer, source, inner_anchor)
  assert_eq(state.model.unwrap().references[0].range, inner_location.range)
  guard captured_widget.val is Some(inner_widget) else {
    fail("ViewZone listener did not capture the newer widget")
  }
  assert_true(
    state.widget is Some(current_widget) &&
    physical_equal(current_widget, inner_widget),
  )
  assert_eq(state.zone_id, captured_zone_id.val)
  guard captured_overlay.val is Some(inner_overlay) else {
    fail("ViewZone listener did not capture the newer overlay")
  }
  assert_true(
    state.overlay_widget is Some(current_overlay) &&
    physical_equal(current_overlay, inner_overlay),
  )
  // Only the nested session reaches location installation; the stale outer
  // shell leaves neither a whitespace nor an overlay/widget mount behind.
  assert_eq(tasks.tasks.length(), 1)
  assert_references_peek_code_mount(viewer)
  tasks.run_all()
  match state.phase {
    PeekShown(generation, _) => assert_eq(generation, captured_generation.val)
    _ => fail("reentrant ViewZone session did not install its preview")
  }
  assert_references_peek_code_mount(viewer)

  viewer.dispose()
  services.dispose()
  source.dispose()
}

///|
async fn run_definition_peek_reentrant_view_zone_test() -> Unit {
  let source = references_peek_test_model(
    "file:///workspace/definition-source.mbt",
    text="let source = target\n",
  )
  let provider_calls = Ref(0)
  let services = references_peek_test_services(
    definition_provider_calls=provider_calls,
  )
  let viewer = references_peek_test_viewer(services, source)
  let tasks = ManualReferencesPeekTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  viewer.set_position(Position(1, 5))
  let state = viewer.references_contribution().unwrap()
  let new_anchor = @base_common.Position(1, 7)
  let new_location : @language.Location = {
    uri: source.uri,
    range: Range(1, 14, 1, 20),
  }
  let reentered = Ref(false)
  let listener = viewer.on_did_change_view_zones(() => {
    if !reentered.val {
      reentered.val = true
      viewer.show_references(new_anchor, [new_location])
    }
  })
  viewer.start_peek_definition()
  listener.dispose()

  assert_true(reentered.val)
  assert_eq(state.mode, Some(References))
  assert_references_peek_session_key(viewer, source, new_anchor)
  assert_eq(state.model.unwrap().references[0].range, new_location.range)
  assert_true(viewer.definition_message_for_test() is None)
  assert_eq(provider_calls.val, 0)
  assert_eq(tasks.tasks.length(), 1)
  assert_references_peek_code_mount(viewer)
  tasks.run_all()
  match state.phase {
    PeekShown(_, _) => ()
    _ => fail("newer References session lost to stale Definition shell")
  }
  assert_true(viewer.definition_message_for_test() is None)
  assert_references_peek_code_mount(viewer)

  viewer.dispose()
  services.dispose()
  source.dispose()
}

///|
async fn run_references_peek_cancels_definition_intent_test() -> Unit {
  let source = references_peek_test_model("file:///workspace/source.mbt")
  let old_target_uri = try! @base_common.Uri::parse(
    "file:///workspace/old-definition.mbt",
  )
  let provider_calls = Ref(0)
  let languages = @languages.Languages()
  languages.register_definition_provider(LanguageId("moonbit"), PendingReferencesPeekDefinitionProvider::{
    calls: provider_calls,
    locations: [{ uri: old_target_uri, range: Range(1, 1, 1, 2) }],
  })
  |> ignore
  let opener_calls = Ref(0)
  let opener = @navigation_api.LocationOpenerHandle(open=_request => {
    opener_calls.val += 1
    true
  })
  let log_service = @log.LogService()
  let services = ViewerServices(
    languages=languages.language_handle(log_service.log_handle()),
    location_opener=opener,
    log_service=log_service.log_handle(),
  )
  let viewer = references_peek_test_viewer(services, source)
  let tasks = ManualReferencesPeekTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  viewer.set_position(Position(1, 5))
  viewer.start_goto_definition()
  let definition = viewer.definition_contribution().unwrap()
  guard definition.action_source is Some(action_source) else {
    fail("pending Definition action did not retain its source")
  }
  let link_source = @language.CancellationTokenSource()
  definition.link_source = Some(link_source)
  let reference_location : @language.Location = {
    uri: source.uri,
    range: Range(1, 14, 1, 20),
  }
  viewer.show_references(Position(1, 1), [reference_location])
  assert_true(action_source.token().is_cancellation_requested())
  assert_true(link_source.token().is_cancellation_requested())
  assert_true(definition.action_source is None)
  assert_true(definition.link_source is None)
  let state = viewer.references_contribution().unwrap()
  let references_generation = state.generation
  guard state.widget is Some(references_widget) else {
    fail("newer References intent did not install its widget")
  }
  assert_eq(tasks.tasks.length(), 2)

  // The cancelled old action task still runs. Cancellation stops it before
  // provider invocation and it cannot replace the newer precomputed model or
  // launch its opener.
  tasks.run_next()
  assert_eq(provider_calls.val, 0)
  assert_eq(state.generation, references_generation)
  assert_eq(state.mode, Some(References))
  assert_true(
    state.widget is Some(current_widget) &&
    physical_equal(current_widget, references_widget),
  )
  assert_eq(
    state.model.unwrap().references[0].uri_string,
    source.uri.to_string(),
  )
  assert_eq(opener_calls.val, 0)
  tasks.run_all()
  assert_eq(opener_calls.val, 0)

  viewer.dispose()
  services.dispose()
  source.dispose()
}

///|
async fn run_references_peek_provider_action_test() -> Unit {
  let source = references_peek_test_model(
    "file:///workspace/provider-source.mbt",
    text="let first = target\nlet second = target\n",
  )
  let calls = Ref(0)
  let locations : Array[@language.Location] = [
    { uri: source.uri, range: Range(1, 13, 1, 19) },
    { uri: source.uri, range: Range(2, 14, 2, 20) },
  ]
  let observed_tokens : Array[@language.CancellationToken] = []
  let provider = ReferencesPeekQueryProvider::{
    calls,
    locations,
    observed_tokens,
  }
  let services = references_peek_test_services(references_provider=provider)
  let viewer = references_peek_test_viewer(services, source)
  let tasks = ManualReferencesPeekTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  viewer.set_position(Position(1, 13))
  let state = viewer.references_contribution().unwrap()

  assert_true(viewer.references_action_available())
  assert_true(
    viewer.handle_editor_key_down("F12", alt=false, ctrl_cmd=false, shift=true),
  )
  match state.phase {
    PeekLoadingReferences(_) => ()
    _ => fail("Shift F12 did not open the references loading shell")
  }
  guard state.widget is Some(loading_widget) else {
    fail("provider-backed references did not publish its loading shell")
  }
  assert_true(
    references_peek_root_test_text(loading_widget.get_dom_node()).contains(
      "Loading references",
    ),
  )
  guard state.query_source is Some(first_source) else {
    fail("provider-backed references did not retain its query source")
  }
  assert_eq(calls.val, 0)
  assert_eq(tasks.tasks.length(), 1)
  tasks.run_next()
  assert_eq(calls.val, 1)
  assert_eq(observed_tokens.length(), 1)
  assert_true(physical_equal(observed_tokens[0], first_source.token()))
  assert_true(state.query_source is None)
  assert_eq(state.model.unwrap().references.length(), 2)
  tasks.run_all()
  match state.phase {
    PeekShown(_, _) => ()
    _ => fail("provider-backed references did not install its preview")
  }

  // The exact same provider action toggles its populated session closed.
  assert_true(
    viewer.handle_editor_key_down("F12", alt=false, ctrl_cmd=false, shift=true),
  )
  assert_eq(state.phase, PeekClosed)

  // An authoritative empty provider result keeps the accessible shell.
  locations.clear()
  assert_true(
    viewer.handle_editor_key_down("F12", alt=false, ctrl_cmd=false, shift=true),
  )
  tasks.run_all()
  assert_eq(calls.val, 2)
  guard state.widget is Some(empty_widget) else {
    fail("empty provider result did not retain the references shell")
  }
  assert_true(
    references_peek_root_test_text(empty_widget.get_dom_node()).contains(
      "No references found",
    ),
  )

  // Toggle the empty shell closed, then prove a cursor change cancels a
  // pending query before it can invoke the provider.
  viewer.start_peek_references()
  assert_eq(state.phase, PeekClosed)
  viewer.start_peek_references()
  guard state.query_source is Some(cancelled_source) else {
    fail("second provider query did not retain its source")
  }
  viewer.set_position(Position(2, 14))
  assert_eq(state.phase, PeekClosed)
  assert_true(cancelled_source.token().is_cancellation_requested())
  tasks.run_all()
  assert_eq(calls.val, 2)

  // A newer precomputed References intent also cancels the provider query and
  // owns the resulting shared session.
  viewer.start_peek_references()
  guard state.query_source is Some(superseded_source) else {
    fail("provider query was not pending before precomputed replacement")
  }
  viewer.show_references(Position(2, 15), [
    { uri: source.uri, range: Range(2, 14, 2, 20) },
  ])
  assert_true(superseded_source.token().is_cancellation_requested())
  assert_eq(state.mode, Some(References))
  assert_eq(state.model.unwrap().references.length(), 1)
  tasks.run_all()
  assert_eq(calls.val, 2)

  viewer.dispose()
  services.dispose()
  source.dispose()
}

///|
async test "Peek References public entry, snippets, ownership, navigation, and freshness" {
  install_mounted_test_browser()
  defer restore_mounted_test_browser()
  run_references_peek_public_contract_test()
  run_references_peek_same_resource_test()
  run_references_peek_cross_resource_ownership_test()
  run_references_peek_failure_and_opening_test()
  run_references_peek_stale_resolution_test()
  run_references_peek_stale_widget_callback_test()
  run_references_peek_reentrant_release_test()
  run_references_peek_reentrant_model_swap_zone_test()
  run_references_peek_reentrant_preview_cancellation_test()
  run_references_peek_reentrant_set_selected_test()
  run_references_peek_reentrant_preview_commit_test()
  run_references_peek_reentrant_view_zone_test()
  run_definition_peek_reentrant_view_zone_test()
  run_references_peek_cancels_definition_intent_test()
  run_references_peek_provider_action_test()
}

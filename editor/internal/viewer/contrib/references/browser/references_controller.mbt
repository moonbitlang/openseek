///|
/// Exact surface mount owned by one Peek session. The adapter captures its
/// concrete ViewZone/overlay or Markdown overlay node; the shared controller
/// only asks whether that mount is still current and disposes it once.
pub struct ReferencesPeekMount {
  priv is_current_callback : () -> Bool
  priv dispose_callback : () -> Unit
  priv mut disposed : Bool
}

///|
pub fn ReferencesPeekMount::ReferencesPeekMount(
  is_current~ : () -> Bool,
  dispose~ : () -> Unit,
) -> ReferencesPeekMount {
  {
    is_current_callback: is_current,
    dispose_callback: dispose,
    disposed: false,
  }
}

///|
pub fn ReferencesPeekMount::is_current(self : ReferencesPeekMount) -> Bool {
  !self.disposed && (self.is_current_callback)()
}

///|
pub fn ReferencesPeekMount::dispose(self : ReferencesPeekMount) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  (self.dispose_callback)()
}

///|
/// Surface-independent lifetime of the embedded CodeEditor preview. The
/// injected factory owns concrete editor construction and decorations.
pub struct ReferencesPeekPreview {
  priv contains_focus_callback : () -> Bool
  priv focus_callback : () -> Unit
  priv dispose_callback : () -> Unit
  priv mut disposed : Bool
}

///|
pub fn ReferencesPeekPreview::ReferencesPeekPreview(
  contains_focus~ : () -> Bool,
  focus~ : () -> Unit,
  dispose~ : () -> Unit,
) -> ReferencesPeekPreview {
  {
    contains_focus_callback: contains_focus,
    focus_callback: focus,
    dispose_callback: dispose,
    disposed: false,
  }
}

///|
pub fn ReferencesPeekPreview::contains_focus(
  self : ReferencesPeekPreview,
) -> Bool {
  !self.disposed && (self.contains_focus_callback)()
}

///|
pub fn ReferencesPeekPreview::focus(self : ReferencesPeekPreview) -> Unit {
  if !self.disposed {
    (self.focus_callback)()
  }
}

///|
pub fn ReferencesPeekPreview::dispose(self : ReferencesPeekPreview) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  (self.dispose_callback)()
}

///|
pub(all) struct ReferencesPeekPreviewFactory {
  create : (
    @rdom.Element,
    @model.TextModel,
    @base_common.Range,
    Array[@base_common.Range],
    @references.ReferencesPeekMode,
  ) -> ReferencesPeekPreview?
}

///|
/// The only surface capabilities visible to the shared controller.
pub(all) struct ReferencesPeekHost {
  is_anchor_current : (@goto_symbol.SymbolNavigationAnchor) -> Bool
  mount : (@rdom.Element, @goto_symbol.SymbolNavigationAnchor) -> ReferencesPeekMount?
  reveal_anchor : (@goto_symbol.SymbolNavigationAnchor) -> Unit
  restore_source_focus : () -> Unit
  open_location : async (
    @language.Location,
    @navigation_api.OpenLocationMode,
    String,
  ) -> Bool noraise
  show_message : (@goto_symbol.SymbolNavigationAnchor, String) -> Unit
}

///|
priv struct ReferencesGroupPreviewOwner {
  group_index : Int
  mut generation : Int
  mut source : @language.CancellationTokenSource?
  mut reference : @navigation_api.TextModelReference?
}

///|
fn ReferencesGroupPreviewOwner::ReferencesGroupPreviewOwner(
  group_index : Int,
) -> ReferencesGroupPreviewOwner {
  { group_index, generation: 0, source: None, reference: None, }
}

///|
priv struct DetachedReferencesGroupResources {
  sources : Array[@language.CancellationTokenSource]
  references : Array[@navigation_api.TextModelReference]
}

///|
/// One mutable Peek state machine per source surface. Controller instances are
/// never shared between Code and Markdown surfaces.
pub struct ReferencesController {
  priv host : ReferencesPeekHost
  priv preview_factory : ReferencesPeekPreviewFactory
  priv resolver : @navigation_api.TextModelResolverHandle?
  priv mut launch_async_task : (async () -> Unit noraise) -> Unit
  priv mut generation : Int
  priv mut preview_generation : Int
  priv mut mode : @references.ReferencesPeekMode?
  priv mut phase : @references.ReferencesPeekPhase
  priv mut anchor : @goto_symbol.SymbolNavigationAnchor?
  priv mut session_key : @references.ReferencesSessionKey?
  priv mut model : @references.ReferencesModel?
  priv mut selected_index : Int
  priv mut widget : ReferencesPeekWidget?
  priv mut mount : ReferencesPeekMount?
  priv mut preview_source : @language.CancellationTokenSource?
  priv mut preview_reference : @navigation_api.TextModelReference?
  priv mut preview : ReferencesPeekPreview?
  priv mut group_preview_owners : Array[ReferencesGroupPreviewOwner]
  priv mut focus_frame : @base_common.Disposable?
  priv mut disposed : Bool
}

///|
pub fn ReferencesController::ReferencesController(
  host : ReferencesPeekHost,
  preview_factory : ReferencesPeekPreviewFactory,
  resolver? : @navigation_api.TextModelResolverHandle,
  launch_async_task : (async () -> Unit noraise) -> Unit,
) -> ReferencesController {
  {
    host,
    preview_factory,
    resolver,
    launch_async_task,
    generation: 0,
    preview_generation: 0,
    mode: None,
    phase: PeekClosed,
    anchor: None,
    session_key: None,
    model: None,
    selected_index: -1,
    widget: None,
    mount: None,
    preview_source: None,
    preview_reference: None,
    preview: None,
    group_preview_owners: [],
    focus_frame: None,
    disposed: false,
  }
}

///|
pub fn ReferencesController::set_task_launcher(
  self : ReferencesController,
  launch : (async () -> Unit noraise) -> Unit,
) -> Unit {
  self.launch_async_task = launch
}

///|
fn ReferencesController::anchor_is_current(
  self : ReferencesController,
  anchor : @goto_symbol.SymbolNavigationAnchor,
) -> Bool {
  !self.disposed &&
  anchor.model_is_current() &&
  (self.host.is_anchor_current)(anchor)
}

///|
fn ReferencesController::session_is_current(
  self : ReferencesController,
  generation : Int,
) -> Bool {
  guard !self.disposed && self.generation == generation else { return false }
  guard self.anchor is Some(anchor) && self.anchor_is_current(anchor) else {
    return false
  }
  guard self.widget is Some(_) && self.mount is Some(mount) else {
    return false
  }
  mount.is_current()
}

///|
fn ReferencesController::session_is_open(
  self : ReferencesController,
  key : @references.ReferencesSessionKey,
  mode : @references.ReferencesPeekMode,
) -> Bool {
  self.session_key == Some(key) &&
  self.mode == Some(mode) &&
  self.widget is Some(_) &&
  self.mount is Some(_) &&
  self.session_is_current(self.generation)
}

///|
/// Toggles one already-computed result set. Provider work is owned by the
/// shared SymbolNavigationAction, so this method never re-queries it.
pub fn ReferencesController::toggle_locations(
  self : ReferencesController,
  anchor : @goto_symbol.SymbolNavigationAnchor,
  mode : @references.ReferencesPeekMode,
  locations : Array[@language.Location],
) -> Bool {
  guard self.anchor_is_current(anchor) else { return false }
  let key = @references.ReferencesSessionKey::from_model(
    anchor.model(),
    anchor.surface_generation(),
    anchor.position(),
  )
  if self.session_is_open(key, mode) {
    self.close(restore_focus=true)
    return true
  }
  self.close(restore_focus=false)
  guard self.anchor_is_current(anchor) else { return false }
  self.generation += 1
  let generation = self.generation
  self.mode = Some(mode)
  self.phase = match mode {
    Definitions => PeekLoadingDefinitions(generation)
    References => PeekLoadingReferences(generation)
  }
  self.anchor = Some(anchor)
  self.session_key = Some(key)
  let widget = ReferencesPeekWidget(mode, {
    on_close: () => {
      if self.session_is_current(generation) {
        self.close(restore_focus=true)
      }
    },
    on_select: item => {
      if self.session_is_current(generation) {
        self.select_item(item)
      }
    },
    on_confirm: item => {
      if self.session_is_current(generation) {
        self.confirm_item(item, Current)
      }
    },
    on_open_side: item => {
      if self.session_is_current(generation) {
        self.confirm_item(item, Side)
      }
    },
    on_next: () => {
      if self.session_is_current(generation) {
        self.move_selection(1)
      }
    },
    on_previous: () => {
      if self.session_is_current(generation) {
        self.move_selection(-1)
      }
    },
    on_expand_group: group => {
      if self.session_is_current(generation) {
        self.load_group(group)
      }
    },
  })
  self.widget = Some(widget)
  let mount = (self.host.mount)(widget.get_dom_node(), anchor)
  guard mount is Some(mount) else {
    if self.generation == generation &&
      self.widget is Some(current_widget) &&
      physical_equal(current_widget, widget) {
      self.widget = None
      self.mode = None
      self.anchor = None
      self.session_key = None
      self.phase = PeekClosed
    }
    widget.dispose()
    return false
  }
  let widget_is_current = match self.widget {
    Some(current_widget) => physical_equal(current_widget, widget)
    None => false
  }
  if self.generation != generation ||
    !widget_is_current ||
    !self.anchor_is_current(anchor) ||
    !mount.is_current() {
    mount.dispose()
    let still_owns_widget = self.generation == generation &&
      self.widget is Some(current_widget) &&
      physical_equal(current_widget, widget)
    if still_owns_widget {
      self.close(restore_focus=false)
    } else {
      widget.dispose()
    }
    return false
  }
  self.mount = Some(mount)
  (self.host.reveal_anchor)(anchor)
  guard self.session_is_current(generation) else {
    self.close(restore_focus=false)
    return false
  }
  self.install_locations(generation, locations.copy())
  guard self.session_is_current(generation) else { return true }
  self.focus_frame = Some(
    @base_browser.schedule_at_next_animation_frame(
      () => {
        if self.generation == generation {
          self.focus_frame = None
        }
        if self.session_is_current(generation) &&
          self.widget is Some(current_widget) &&
          physical_equal(current_widget, widget) {
          widget.focus()
        }
      },
      priority=0,
    ),
  )
  true
}

///|
fn ReferencesController::install_locations(
  self : ReferencesController,
  generation : Int,
  locations : Array[@language.Location],
) -> Unit {
  guard self.session_is_current(generation) else { return }
  guard self.anchor is Some(anchor) && self.widget is Some(widget) else {
    return
  }
  let result_model = @references.ReferencesModel(locations)
  self.model = Some(result_model)
  let owners : Array[ReferencesGroupPreviewOwner] = []
  for group in result_model.groups {
    owners.push(ReferencesGroupPreviewOwner(group.group_index))
  }
  self.group_preview_owners = owners
  if result_model.is_empty() {
    if self.mode == Some(Definitions) {
      self.close(restore_focus=true)
      (self.host.show_message)(anchor, definition_no_result_message(anchor))
    } else {
      widget.show_empty()
      self.phase = PeekShown(generation, self.preview_generation)
    }
    return
  }
  guard result_model.nearest_reference(anchor.model().uri, anchor.position())
    is Some(selected) else {
    return
  }
  self.selected_index = selected.flat_index
  widget.set_results(result_model, Some(selected))
  widget.show_preview_loading()
  self.load_preview(generation, selected.flat_index)
}

///|
fn definition_no_result_message(
  anchor : @goto_symbol.SymbolNavigationAnchor,
) -> String {
  match anchor.model().get_word_at_position(anchor.position()) {
    Some(word) if !word.word.is_empty() =>
      "No definition found for '\{word.word}'"
    _ => "No definition found"
  }
}

///|
fn ReferencesController::group_is_current(
  self : ReferencesController,
  generation : Int,
  group : @references.ReferenceGroup,
) -> Bool {
  guard self.session_is_current(generation) && self.model is Some(model) else {
    return false
  }
  group.group_index >= 0 &&
  group.group_index < model.groups.length() &&
  model.groups[group.group_index] == group
}

///|
fn ReferencesController::group_slot_is_current(
  self : ReferencesController,
  generation : Int,
  group : @references.ReferenceGroup,
  owner_generation : Int,
) -> Bool {
  guard self.group_is_current(generation, group) else { return false }
  guard group.group_index >= 0 &&
    group.group_index < self.group_preview_owners.length() else {
    return false
  }
  let owner = self.group_preview_owners[group.group_index]
  owner.group_index == group.group_index && owner.generation == owner_generation
}

///|
fn reference_group_row_previews(
  group : @references.ReferenceGroup,
  model : @model.TextModel,
) -> Array[@references.ReferenceRowPreview] {
  group.references.map(item => item.row_preview(Some(model)))
}

///|
fn ReferencesController::load_group(
  self : ReferencesController,
  group : @references.ReferenceGroup,
) -> Unit {
  let generation = self.generation
  guard self.group_is_current(generation, group) else { return }
  guard group.group_index >= 0 &&
    group.group_index < self.group_preview_owners.length() else {
    return
  }
  let owner = self.group_preview_owners[group.group_index]
  guard owner.group_index == group.group_index &&
    owner.source is None &&
    owner.reference is None else {
    return
  }
  match self.anchor {
    Some(anchor) if anchor.model().uri.to_string() == group.uri_string => {
      guard self.widget is Some(widget) else { return }
      widget.set_group_previews(
        group.group_index,
        reference_group_row_previews(group, anchor.model()),
      )
      return
    }
    _ => ()
  }
  guard self.resolver is Some(resolver) else { return }
  owner.generation += 1
  let owner_generation = owner.generation
  let source = @language.CancellationTokenSource()
  owner.source = Some(source)
  let task = self.launch_async_task
  task(async fn() noraise {
    let reference = resolver.resolve(group.uri, source.token())
    let current = self.group_slot_is_current(
        generation, group, owner_generation,
      ) &&
      !source.token().is_cancellation_requested() &&
      owner.source is Some(current_source) &&
      physical_equal(current_source, source)
    if !current {
      match owner.source {
        Some(current_source) if physical_equal(current_source, source) =>
          owner.source = None
        _ => ()
      }
      source.dispose(cancel=true)
      match reference {
        Some(reference) => reference.dispose()
        None => ()
      }
      return
    }
    owner.source = None
    source.dispose()
    guard self.group_slot_is_current(generation, group, owner_generation) else {
      match reference {
        Some(reference) => reference.dispose()
        None => ()
      }
      return
    }
    match reference {
      None => ()
      Some(reference) => {
        let model = reference.model()
        if model.is_disposed() || model.uri.to_string() != group.uri_string {
          reference.dispose()
          return
        }
        guard self.group_slot_is_current(generation, group, owner_generation) &&
          self.widget is Some(widget) else {
          reference.dispose()
          return
        }
        owner.reference = Some(reference)
        widget.set_group_previews(
          group.group_index,
          reference_group_row_previews(group, model),
        )
      }
    }
  })
}

///|
fn ReferencesController::cancel_preview_request(
  self : ReferencesController,
) -> Unit {
  let source = self.preview_source
  self.preview_source = None
  match source {
    Some(source) => source.dispose(cancel=true)
    None => ()
  }
}

///|
fn ReferencesController::clear_installed_preview(
  self : ReferencesController,
) -> Bool {
  let preview = self.preview
  self.preview = None
  let reference = self.preview_reference
  self.preview_reference = None
  let had_focus = match preview {
    Some(preview) => preview.contains_focus()
    None => false
  }
  match preview {
    Some(preview) => preview.dispose()
    None => ()
  }
  match reference {
    Some(reference) => reference.dispose()
    None => ()
  }
  had_focus
}

///|
fn ReferencesController::preview_selection_is_current(
  self : ReferencesController,
  generation : Int,
  result_model : @references.ReferencesModel,
  index : Int,
  item : @references.ReferenceItem,
  widget : ReferencesPeekWidget,
) -> Bool {
  self.session_is_current(generation) &&
  self.model is Some(current_model) &&
  physical_equal(current_model, result_model) &&
  index >= 0 &&
  index < current_model.references.length() &&
  current_model.references[index] == item &&
  self.widget is Some(current_widget) &&
  physical_equal(current_widget, widget)
}

///|
fn ReferencesController::preview_commit_is_current(
  self : ReferencesController,
  generation : Int,
  preview_generation : Int,
  expected_uri : String,
  model : @model.TextModel,
  result_model : @references.ReferencesModel,
  widget : ReferencesPeekWidget,
) -> Bool {
  self.session_is_current(generation) &&
  self.preview_generation == preview_generation &&
  !model.is_disposed() &&
  model.uri.to_string() == expected_uri &&
  self.model is Some(current_model) &&
  physical_equal(current_model, result_model) &&
  self.widget is Some(current_widget) &&
  physical_equal(current_widget, widget)
}

///|
fn ReferencesController::load_preview(
  self : ReferencesController,
  generation : Int,
  index : Int,
) -> Unit {
  guard self.session_is_current(generation) &&
    self.model is Some(result_model) &&
    self.widget is Some(widget) &&
    index >= 0 &&
    index < result_model.references.length() else {
    return
  }
  if index == self.selected_index &&
    (self.preview is Some(_) || self.preview_source is Some(_)) {
    return
  }
  let item = result_model.references[index]
  self.cancel_preview_request()
  guard self.preview_selection_is_current(
    generation, result_model, index, item, widget,
  ) else {
    return
  }
  self.selected_index = index
  widget.set_selected(item)
  guard self.preview_selection_is_current(
    generation, result_model, index, item, widget,
  ) else {
    return
  }
  widget.show_preview_loading()
  guard self.preview_selection_is_current(
    generation, result_model, index, item, widget,
  ) else {
    return
  }
  self.preview_generation += 1
  let preview_generation = self.preview_generation
  self.phase = PeekLoadingPreview(generation, preview_generation)
  let location = item.location()
  guard self.anchor is Some(anchor) else { return }
  if anchor.model().uri.to_string() == item.uri_string &&
    !anchor.model().is_disposed() {
    self.schedule_preview(
      generation,
      preview_generation,
      location,
      anchor.model(),
      None,
    )
    return
  }
  guard self.resolver is Some(resolver) else {
    self.show_preview_unavailable(
      generation, preview_generation, "No preview available",
    )
    return
  }
  let source = @language.CancellationTokenSource()
  self.preview_source = Some(source)
  let task = self.launch_async_task
  task(async fn() noraise {
    let reference = resolver.resolve(location.uri, source.token())
    let current = self.session_is_current(generation) &&
      self.preview_generation == preview_generation &&
      self.preview_source is Some(current_source) &&
      physical_equal(current_source, source) &&
      !source.token().is_cancellation_requested()
    if !current {
      match self.preview_source {
        Some(current_source) if physical_equal(current_source, source) =>
          self.preview_source = None
        _ => ()
      }
      source.dispose(cancel=true)
      match reference {
        Some(reference) => reference.dispose()
        None => ()
      }
      return
    }
    self.preview_source = None
    source.dispose()
    match reference {
      None =>
        self.show_preview_unavailable(
          generation, preview_generation, "No preview available",
        )
      Some(reference) => {
        let model = reference.model()
        if model.is_disposed() ||
          model.uri.to_string() != location.uri.to_string() {
          reference.dispose()
          self.show_preview_unavailable(
            generation, preview_generation, "No preview available",
          )
          return
        }
        self.schedule_preview(
          generation,
          preview_generation,
          location,
          model,
          Some(reference),
        )
      }
    }
  })
}

///|
#warnings("-unused_async")
fn ReferencesController::schedule_preview(
  self : ReferencesController,
  generation : Int,
  preview_generation : Int,
  location : @language.Location,
  model : @model.TextModel,
  reference : @navigation_api.TextModelReference?,
) -> Unit {
  let dispose_reference = () => {
    if reference is Some(current) {
      current.dispose()
    }
  }
  guard !model.is_disposed() &&
    self.session_is_current(generation) &&
    self.preview_generation == preview_generation else {
    dispose_reference()
    return
  }
  let task = self.launch_async_task
  task(async fn() noraise {
    guard self.model is Some(result_model) &&
      self.widget is Some(widget) &&
      self.mode is Some(mode) &&
      self.preview_commit_is_current(
        generation,
        preview_generation,
        location.uri.to_string(),
        model,
        result_model,
        widget,
      ) else {
      dispose_reference()
      return
    }
    let commit_is_current = () => {
      self.preview_commit_is_current(
        generation,
        preview_generation,
        location.uri.to_string(),
        model,
        result_model,
        widget,
      )
    }
    let restore_preview_focus = self.clear_installed_preview()
    guard commit_is_current() else {
      dispose_reference()
      return
    }
    let uri = model.uri.to_string()
    let matches : Array[@base_common.Range] = [
      for item in result_model.references if item.uri_string == uri => {
        model.validate_range(item.range)
      }
    ]
    let preview = (self.preview_factory.create)(
      widget.get_preview_host(),
      model,
      model.validate_range(location.range),
      matches,
      mode,
    )
    guard preview is Some(preview) else {
      dispose_reference()
      self.show_preview_unavailable(
        generation, preview_generation, "No preview available",
      )
      return
    }
    if !commit_is_current() {
      preview.dispose()
      dispose_reference()
      return
    }
    widget.show_preview_ready()
    if !commit_is_current() {
      preview.dispose()
      dispose_reference()
      return
    }
    if restore_preview_focus {
      preview.focus()
    }
    if !commit_is_current() {
      preview.dispose()
      dispose_reference()
      return
    }
    self.preview = Some(preview)
    self.preview_reference = reference
    self.phase = PeekShown(generation, preview_generation)
  })
}

///|
fn ReferencesController::show_preview_unavailable(
  self : ReferencesController,
  generation : Int,
  preview_generation : Int,
  message : String,
) -> Unit {
  guard self.session_is_current(generation) &&
    self.preview_generation == preview_generation else {
    return
  }
  guard self.widget is Some(widget) else { return }
  let had_focus = self.clear_installed_preview()
  guard self.session_is_current(generation) &&
    self.preview_generation == preview_generation &&
    self.widget is Some(current_widget) &&
    physical_equal(current_widget, widget) else {
    return
  }
  self.phase = PeekUnavailable(generation, preview_generation)
  widget.show_preview_unavailable(message)
  if had_focus {
    widget.focus()
  }
}

///|
fn ReferencesController::item_is_current(
  self : ReferencesController,
  item : @references.ReferenceItem,
) -> Bool {
  guard self.model is Some(model) else { return false }
  item.flat_index >= 0 &&
  item.flat_index < model.references.length() &&
  model.references[item.flat_index] == item
}

///|
fn ReferencesController::select_item(
  self : ReferencesController,
  item : @references.ReferenceItem,
) -> Unit {
  if self.item_is_current(item) {
    self.load_preview(self.generation, item.flat_index)
  }
}

///|
fn ReferencesController::move_selection(
  self : ReferencesController,
  delta : Int,
) -> Unit {
  guard self.model is Some(model) && !model.references.is_empty() else {
    return
  }
  let current = if self.selected_index >= 0 &&
    self.selected_index < model.references.length() {
    model.references[self.selected_index]
  } else {
    model.references[0]
  }
  let next = if delta < 0 {
    model.previous_reference(current)
  } else {
    model.next_reference(current)
  }
  match next {
    Some(item) => self.select_item(item)
    None => ()
  }
}

///|
fn ReferencesController::confirm_item(
  self : ReferencesController,
  item : @references.ReferenceItem,
  open_mode : @navigation_api.OpenLocationMode,
) -> Unit {
  guard self.item_is_current(item) &&
    self.mode is Some(peek_mode) &&
    self.anchor is Some(anchor) else {
    return
  }
  let location = item.location()
  let task = self.launch_async_task
  let closed_generation = self.generation + 1
  self.close(restore_focus=true)
  task(async fn() noraise {
    guard !self.disposed &&
      self.generation == closed_generation &&
      self.anchor_is_current(anchor) else {
      return
    }
    let accepted = (self.host.open_location)(
      location,
      open_mode,
      if peek_mode == Definitions {
        "peekDefinition"
      } else {
        "showReferences"
      },
    )
    if !accepted &&
      self.generation == closed_generation &&
      self.anchor_is_current(anchor) &&
      peek_mode == Definitions {
      (self.host.show_message)(anchor, "Unable to open definition")
    }
  })
}

///|
fn ReferencesController::detach_group_resources(
  self : ReferencesController,
) -> DetachedReferencesGroupResources {
  let owners = self.group_preview_owners
  self.group_preview_owners = []
  let sources : Array[@language.CancellationTokenSource] = []
  let references : Array[@navigation_api.TextModelReference] = []
  for owner in owners {
    owner.generation += 1
    match owner.source {
      Some(source) => sources.push(source)
      None => ()
    }
    match owner.reference {
      Some(reference) => references.push(reference)
      None => ()
    }
    owner.source = None
    owner.reference = None
  }
  { sources, references, }
}

///|
pub fn ReferencesController::close(
  self : ReferencesController,
  restore_focus~ : Bool,
) -> Unit {
  self.generation += 1
  let closing_generation = self.generation
  self.preview_generation += 1
  self.phase = PeekClosed
  let anchor = self.anchor
  self.anchor = None
  self.session_key = None
  self.mode = None
  self.model = None
  self.selected_index = -1
  let source = self.preview_source
  self.preview_source = None
  let preview = self.preview
  self.preview = None
  let reference = self.preview_reference
  self.preview_reference = None
  let groups = self.detach_group_resources()
  let frame = self.focus_frame
  self.focus_frame = None
  let mount = self.mount
  self.mount = None
  let widget = self.widget
  self.widget = None
  match source {
    Some(source) => source.dispose(cancel=true)
    None => ()
  }
  for source in groups.sources {
    source.dispose(cancel=true)
  }
  match frame {
    Some(frame) => frame.dispose()
    None => ()
  }
  match preview {
    Some(preview) => preview.dispose()
    None => ()
  }
  match reference {
    Some(reference) => reference.dispose()
    None => ()
  }
  for reference in groups.references {
    reference.dispose()
  }
  match mount {
    Some(mount) => mount.dispose()
    None => ()
  }
  match widget {
    Some(widget) => widget.dispose()
    None => ()
  }
  if restore_focus &&
    !self.disposed &&
    self.generation == closing_generation &&
    self.phase == PeekClosed &&
    anchor is Some(anchor) &&
    self.anchor_is_current(anchor) {
    (self.host.restore_source_focus)()
  }
}

///|
pub fn ReferencesController::contains_focus(
  self : ReferencesController,
) -> Bool {
  match self.widget {
    Some(widget) =>
      @base_browser.element_contains_active_element(widget.get_dom_node())
    None => false
  }
}

///|
pub fn ReferencesController::phase(
  self : ReferencesController,
) -> @references.ReferencesPeekPhase {
  self.phase
}

///|
pub fn ReferencesController::dispose(self : ReferencesController) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  self.close(restore_focus=false)
}

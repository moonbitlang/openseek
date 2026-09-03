// Standalone readonly CodeLens controller and browser presentation. The
// provider/query split follows VS Code's codelens.ts/controller.ts while the
// row itself uses the viewer's existing ViewZone + ContentWidget machinery.

///|
let code_lens_contribution_id : String = "css.editor.codeLens"

///|
let code_lens_debounce_milliseconds : Int = 250

///|
priv struct CodeLensTrackedItem {
  source : @languages.CodeLensItem
  mut lens : @language.CodeLens
  was_empty : Bool
  mut resolution_complete : Bool
}

///|
priv struct CodeLensRenderedLine {
  line_number : Ref[Int]
  item_indexes : Array[Int]
  zone : @editor_browser.ViewZone
  mut zone_id : String?
  widget : @view.ContentWidgetHandle
  widget_dom : @rdom.Element
}

///|
priv struct CodeLensContributionState {
  mut disposed : Bool
  mut refresh_generation : Int
  mut resolve_generation : Int
  mut provide_source : @language.CancellationTokenSource?
  mut resolve_source : @language.CancellationTokenSource?
  mut refresh_timer : @base_common.Disposable?
  mut resolve_timer : @base_common.Disposable?
  mut schedule_timeout : (() -> Unit, Int) -> @base_common.Disposable
  mut launch_async_task : (async () -> Unit noraise) -> Unit
  decorations : EditorDecorationsCollection
  mut items : Array[CodeLensTrackedItem]
  mut rows : Array[CodeLensRenderedLine]
  mut widget_id_pool : Int
}

///|
fn CodeLensContributionState::CodeLensContributionState(
  viewer : CodeEditorWidget,
) -> CodeLensContributionState {
  {
    disposed: false,
    refresh_generation: 0,
    resolve_generation: 0,
    provide_source: None,
    resolve_source: None,
    refresh_timer: None,
    resolve_timer: None,
    schedule_timeout: @base_browser.schedule_timeout,
    launch_async_task,
    decorations: viewer.create_decorations_collection(),
    items: [],
    rows: [],
    widget_id_pool: 0,
  }
}

///|
fn CodeLensContributionState::cancel_provide(
  self : CodeLensContributionState,
) -> Unit {
  self.refresh_generation += 1
  match self.refresh_timer {
    Some(timer) => timer.dispose()
    None => ()
  }
  self.refresh_timer = None
  match self.provide_source {
    Some(source) => source.dispose(cancel=true)
    None => ()
  }
  self.provide_source = None
}

///|
fn CodeLensContributionState::cancel_resolve(
  self : CodeLensContributionState,
) -> Unit {
  self.resolve_generation += 1
  match self.resolve_timer {
    Some(timer) => timer.dispose()
    None => ()
  }
  self.resolve_timer = None
  match self.resolve_source {
    Some(source) => source.dispose(cancel=true)
    None => ()
  }
  self.resolve_source = None
}

///|
fn CodeLensContributionState::dispose(
  self : CodeLensContributionState,
  viewer : CodeEditorWidget,
) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  self.cancel_provide()
  self.cancel_resolve()
  viewer.clear_rendered_code_lenses()
}

///|
fn register_code_lens_contribution(
  registry : EditorContributionRegistry,
) -> Unit {
  registry.register_editor_contribution(
    code_lens_contribution_id,
    CodeLens,
    AfterFirstRender,
    viewer => CodeLens(CodeLensContributionState(viewer)),
    viewer => {
      let listeners : Array[@base_common.Disposable] = []
      listeners.push(
        viewer.on_did_change_model(_ => {
          viewer.clear_code_lens_model_state()
          viewer.apply_code_lens_style_and_height()
          viewer.schedule_code_lens_refresh()
        }),
      )
      listeners.push(
        viewer.on_did_change_model_content(_ => {
          viewer.update_tracked_code_lens_ranges()
          viewer.cancel_code_lens_resolve()
          viewer.schedule_code_lens_refresh()
        }),
      )
      listeners.push(
        viewer.services.languages.on_did_change_code_lenses(() => {
          viewer.schedule_code_lens_refresh()
        }),
      )
      listeners.push(
        viewer.on_did_scroll_change(event => {
          if event.scroll_top_changed {
            viewer.schedule_code_lens_resolve()
          }
        }),
      )
      listeners.push(
        viewer.on_did_layout_change(_ => {
          viewer.apply_code_lens_style_and_height()
          viewer.schedule_code_lens_resolve()
        }),
      )
      listeners
    },
  )
}

///|
fn CodeEditorWidget::code_lens_contribution(
  self : CodeEditorWidget,
) -> CodeLensContributionState? {
  match self.contributions.lookup(code_lens_contribution_id) {
    Some({ instance: CodeLens(state), .. }) => Some(state)
    _ => None
  }
}

///|
fn CodeEditorWidget::cancel_code_lens_resolve(self : CodeEditorWidget) -> Unit {
  match self.code_lens_contribution() {
    Some(state) => state.cancel_resolve()
    None => ()
  }
}

///|
fn CodeEditorWidget::clear_code_lens_model_state(
  self : CodeEditorWidget,
) -> Unit {
  guard self.code_lens_contribution() is Some(state) else { return }
  state.cancel_provide()
  state.cancel_resolve()
  self.clear_rendered_code_lenses()
}

///|
fn CodeEditorWidget::clear_rendered_code_lenses(
  self : CodeEditorWidget,
) -> Unit {
  guard self.code_lens_contribution() is Some(state) else { return }
  if state.items.is_empty() && state.rows.is_empty() {
    return
  }
  let viewport_state = self.capture_stable_viewport_state()
  match self.current_code_view() {
    Some(view) => {
      for row in state.rows {
        view.content_widgets.remove_widget(row.widget)
      }
      self.change_view_zones(accessor => {
        for row in state.rows {
          match row.zone_id {
            Some(id) => accessor.remove_zone(id)
            None => ()
          }
        }
      })
    }
    None => ()
  }
  state.rows = []
  state.items = []
  state.decorations.clear()
  match viewport_state {
    Some(viewport_state) =>
      self.restore_stable_viewport_state(viewport_state) |> ignore
    None => ()
  }
}

///|
fn CodeEditorWidget::schedule_code_lens_refresh(
  self : CodeEditorWidget,
) -> Unit {
  guard self.code_lens_contribution() is Some(state) && !state.disposed else {
    return
  }
  state.cancel_provide()
  state.cancel_resolve()
  if !self.get_options().code_lens {
    self.clear_rendered_code_lenses()
    return
  }
  guard self.get_model() is Some(model) else {
    self.clear_rendered_code_lenses()
    return
  }
  if !self.services.languages.has_code_lens_provider(model) {
    self.clear_rendered_code_lenses()
    return
  }
  let generation = state.refresh_generation
  state.refresh_timer = Some(
    (state.schedule_timeout)(
      () => self.begin_code_lens_refresh(model, generation),
      code_lens_debounce_milliseconds,
    ),
  )
}

///|
fn CodeEditorWidget::begin_code_lens_refresh(
  self : CodeEditorWidget,
  model : @model.TextModel,
  generation : Int,
) -> Unit {
  guard self.code_lens_contribution() is Some(state) &&
    !state.disposed &&
    generation == state.refresh_generation &&
    self.is_current_model(model) else {
    return
  }
  state.refresh_timer = None
  let source = @language.CancellationTokenSource()
  state.provide_source = Some(source)
  let launch = state.launch_async_task
  launch(async fn() noraise {
    let items = self.services.languages.code_lenses(
      model,
      token=source.token(),
      run_tasks=run_async_tasks_concurrently,
    )
    guard self.code_lens_refresh_is_current(state, model, source, generation) else {
      source.dispose(cancel=true)
      return
    }
    state.provide_source = None
    source.dispose()
    let tracked : Array[CodeLensTrackedItem] = []
    for item in items {
      let lens = item.lens()
      if code_lens_range_is_valid(model, lens.range) {
        tracked.push({
          source: item,
          lens,
          was_empty: lens.range.is_empty(),
          resolution_complete: lens.command is Some(_) || !item.has_resolver(),
        })
      }
    }
    self.render_code_lens_items(tracked)
    self.schedule_code_lens_resolve()
  })
}

///|
fn CodeEditorWidget::code_lens_refresh_is_current(
  self : CodeEditorWidget,
  state : CodeLensContributionState,
  model : @model.TextModel,
  source : @language.CancellationTokenSource,
  generation : Int,
) -> Bool {
  if self.disposed ||
    state.disposed ||
    generation != state.refresh_generation ||
    source.token().is_cancellation_requested() ||
    !self.get_options().code_lens ||
    !self.is_current_model(model) {
    return false
  }
  match state.provide_source {
    Some(current) => physical_equal(current, source)
    None => false
  }
}

///|
fn code_lens_range_is_valid(
  model : @model.TextModel,
  range : @base_common.Range,
) -> Bool {
  model.validate_range(range) == range
}

///|
fn CodeEditorWidget::render_code_lens_items(
  self : CodeEditorWidget,
  items : Array[CodeLensTrackedItem],
) -> Unit {
  guard self.code_lens_contribution() is Some(state) && !state.disposed else {
    return
  }
  let viewport_state = self.capture_stable_viewport_state()
  match self.current_code_view() {
    Some(view) => {
      for row in state.rows {
        view.content_widgets.remove_widget(row.widget)
      }
      self.change_view_zones(accessor => {
        for row in state.rows {
          match row.zone_id {
            Some(id) => accessor.remove_zone(id)
            None => ()
          }
        }
      })
    }
    None => ()
  }
  state.rows = []
  state.items = items
  let decorations : Array[@model.ModelDeltaDecoration] = []
  for item in items {
    decorations.push({
      range: item.lens.range,
      options: ModelDecorationOptions(
        "",
        collapse_on_replace_edit=true,
        description="codelens",
      ),
    })
  }
  state.decorations.set(decorations) |> ignore
  guard self.current_code_view() is Some(view) else { return }
  let height = self.code_lens_layout().1
  let rows : Array[CodeLensRenderedLine] = []
  let mut index = 0
  while index < items.length() {
    let line_number = items[index].lens.range.start_line_number
    let indexes : Array[Int] = []
    while index < items.length() &&
          items[index].lens.range.start_line_number == line_number {
      indexes.push(index)
      index += 1
    }
    rows.push(self.create_code_lens_row(state, line_number, indexes, height))
  }
  self.change_view_zones(accessor => {
    for row in rows {
      let id = accessor.add_zone(row.zone)
      row.zone_id = Some(id)
    }
  })
  state.rows = rows
  for row in state.rows {
    view.content_widgets.add_widget(row.widget)
    view.content_widgets.set_widget_position(row.widget)
    self.render_code_lens_row(row)
  }
  self.schedule_render()
  match viewport_state {
    Some(viewport_state) =>
      self.restore_stable_viewport_state(viewport_state) |> ignore
    None => ()
  }
}

///|
fn CodeEditorWidget::create_code_lens_row(
  self : CodeEditorWidget,
  state : CodeLensContributionState,
  line_number : Int,
  item_indexes : Array[Int],
  height : Double,
) -> CodeLensRenderedLine {
  let document = @rdom.document()
  let zone_dom = document.create_element("div")
  zone_dom.set_attribute("class", "codelens-view-zone")
  zone_dom.set_attribute("aria-hidden", "true")
  let widget_dom = document.create_element("span")
  widget_dom.set_attribute("class", "codelens-decoration")
  widget_dom.set_attribute("data-code-lens-line", line_number.to_string())
  let line_number_ref = Ref(line_number)
  let widget_index = state.widget_id_pool
  state.widget_id_pool = widget_index + 1
  let widget_id = "codelens.widget-\{self.get_id()}-\{widget_index.to_string()}"
  let widget = @view.ContentWidgetHandle(() => widget_id, () => widget_dom, () => {
    guard self.get_model() is Some(model) else { return None }
    let line = line_number_ref.val
    guard line >= 1 && line <= model.get_line_count() else { return None }
    let first_non_whitespace = model.get_line_first_non_whitespace_column(line)
    let position : @view.ContentWidgetPosition = {
      position: Some(@base_common.Position(line, first_non_whitespace.max(1))),
      secondary_position: None,
      preference: Some([@view.Above]),
      position_affinity: None,
    }
    Some(position)
  })
  let zone = view_zone(
    line_number - 1,
    zone_dom,
    after_column=1073741823,
    suppress_mouse_down=true,
    height_in_px=height,
    on_computed_height=_ => self.schedule_code_lens_resolve(),
  )
  {
    line_number: line_number_ref,
    item_indexes,
    zone,
    zone_id: None,
    widget,
    widget_dom,
  }
}

///|
fn CodeEditorWidget::render_code_lens_row(
  self : CodeEditorWidget,
  row : CodeLensRenderedLine,
) -> Unit {
  guard self.code_lens_contribution() is Some(state) else { return }
  code_lens_reset_children(row.widget_dom)
  let document = @rdom.document()
  let mut rendered_commands = 0
  for index in row.item_indexes {
    guard index >= 0 && index < state.items.length() else { continue }
    let lens = state.items[index].lens
    guard lens.command is Some(command) else { continue }
    if rendered_commands > 0 {
      let separator = document.create_element("span")
      separator.set_attribute("class", "codelens-separator")
      separator.set_attribute("aria-hidden", "true")
      separator.append_child(document.create_text_node(" | ").as_node())
      row.widget_dom.append_child(separator.as_node())
    }
    let command_node = match self.services.code_lens_command_executor {
      Some(_) => {
        let link = document.create_element("a")
        link.set_attribute("role", "button")
        link.set_attribute("tabindex", "0")
        link.add_event_listener("mousedown", event => {
          event.prevent_default()
          event.stop_propagation()
        })
        link.add_event_listener("click", event => {
          event.prevent_default()
          event.stop_propagation()
          self.execute_code_lens_command(lens.range, command)
        })
        link.add_event_listener("keydown", event => {
          guard event.to_keyboard_event() is Some(keyboard) else { return }
          match keyboard.key() {
            "Enter" | " " | "Spacebar" => {
              event.prevent_default()
              event.stop_propagation()
              self.execute_code_lens_command(lens.range, command)
            }
            _ => ()
          }
        })
        link
      }
      None => document.create_element("span")
    }
    command_node.set_attribute("data-code-lens-command", command.id)
    match command.tooltip {
      Some(tooltip) => command_node.set_attribute("title", tooltip)
      None => ()
    }
    command_node.append_child(
      document.create_text_node(command.title.trim().to_owned()).as_node(),
    )
    row.widget_dom.append_child(command_node.as_node())
    rendered_commands += 1
  }
  if rendered_commands > 0 {
    row.widget_dom.set_attribute("data-code-lens-has-commands", "true")
  } else {
    row.widget_dom.remove_attribute("data-code-lens-has-commands")
  }
}

///|
fn CodeEditorWidget::execute_code_lens_command(
  self : CodeEditorWidget,
  range : @base_common.Range,
  command : @language.CodeLensCommand,
) -> Unit {
  guard self.services.code_lens_command_executor is Some(executor) else {
    return
  }
  guard self.get_model() is Some(model) else { return }
  let request : @code_lens_api.CodeLensCommandRequest = {
    source_viewer_id: self.get_id(),
    resource: model.uri,
    range,
    command,
  }
  launch_async_task(async fn() noraise { executor.execute(request) |> ignore })
}

///|
fn CodeEditorWidget::update_tracked_code_lens_ranges(
  self : CodeEditorWidget,
) -> Unit {
  guard self.code_lens_contribution() is Some(state) && !state.items.is_empty() else {
    return
  }
  let updated : Array[CodeLensTrackedItem] = []
  for index, item in state.items {
    match state.decorations.get_range(index) {
      Some(range) if range.is_empty() == item.was_empty =>
        updated.push({
          source: item.source,
          lens: { ..item.lens, range, },
          was_empty: item.was_empty,
          resolution_complete: item.resolution_complete,
        })
      _ => ()
    }
  }
  self.render_code_lens_items(updated)
}

///|
fn CodeEditorWidget::schedule_code_lens_resolve(
  self : CodeEditorWidget,
) -> Unit {
  guard self.code_lens_contribution() is Some(state) &&
    !state.disposed &&
    self.get_options().code_lens else {
    return
  }
  let mut has_unresolved = false
  for item in state.items {
    if !item.resolution_complete {
      has_unresolved = true
      break
    }
  }
  if !has_unresolved {
    return
  }
  state.cancel_resolve()
  let generation = state.resolve_generation
  state.resolve_timer = Some(
    (state.schedule_timeout)(
      () => self.begin_code_lens_resolve(generation),
      code_lens_debounce_milliseconds,
    ),
  )
}

///|
fn CodeEditorWidget::begin_code_lens_resolve(
  self : CodeEditorWidget,
  generation : Int,
) -> Unit {
  guard self.code_lens_contribution() is Some(state) &&
    !state.disposed &&
    generation == state.resolve_generation else {
    return
  }
  state.resolve_timer = None
  guard self.get_model() is Some(model) else { return }
  let target_indexes : Array[Int] = []
  for row in state.rows {
    if code_lens_line_is_visible(self, row.line_number.val) {
      for index in row.item_indexes {
        if index >= 0 &&
          index < state.items.length() &&
          !state.items[index].resolution_complete {
          target_indexes.push(index)
        }
      }
    }
  }
  if target_indexes.is_empty() {
    return
  }
  let source = @language.CancellationTokenSource()
  state.resolve_source = Some(source)
  let results : Array[@language.CodeLens?] = [
    for _ in 0..<state.items.length() => None
  ]
  let tasks : Array[async () -> Unit] = []
  for index in target_indexes {
    let item = state.items[index]
    tasks.push(() => {
      results[index] = self.services.languages.resolve_code_lens(
        model,
        item.source,
        item.lens,
        token=source.token(),
      )
    })
  }
  let launch = state.launch_async_task
  launch(async fn() noraise {
    run_async_tasks_concurrently(tasks) catch {
      _ => ()
    }
    guard self.code_lens_resolve_is_current(state, model, source, generation) else {
      source.dispose(cancel=true)
      return
    }
    state.resolve_source = None
    source.dispose()
    for index in target_indexes {
      state.items[index].resolution_complete = true
      match results[index] {
        Some(resolved) =>
          state.items[index].lens = {
            ..state.items[index].lens,
            command: resolved.command,
          }
        None => ()
      }
    }
    match self.current_code_view() {
      Some(view) =>
        for row in state.rows {
          self.render_code_lens_row(row)
          view.content_widgets.set_widget_position(row.widget)
        }
      None => ()
    }
    self.schedule_render()
  })
}

///|
fn CodeEditorWidget::code_lens_resolve_is_current(
  self : CodeEditorWidget,
  state : CodeLensContributionState,
  model : @model.TextModel,
  source : @language.CancellationTokenSource,
  generation : Int,
) -> Bool {
  if self.disposed ||
    state.disposed ||
    generation != state.resolve_generation ||
    source.token().is_cancellation_requested() ||
    !self.get_options().code_lens ||
    !self.is_current_model(model) {
    return false
  }
  match state.resolve_source {
    Some(current) => physical_equal(current, source)
    None => false
  }
}

///|
fn code_lens_line_is_visible(
  viewer : CodeEditorWidget,
  line_number : Int,
) -> Bool {
  for range in viewer.get_visible_ranges() {
    if line_number >= range.start_line_number &&
      line_number <= range.end_line_number {
      return true
    }
  }
  false
}

///|
fn CodeEditorWidget::code_lens_layout(
  self : CodeEditorWidget,
) -> (Double, Double) {
  let snapshot = self.configuration.snapshot()
  let font_info = snapshot.font_info
  let font_size = match snapshot.options.code_lens_font_size {
    Some(value) => value.max(1.0)
    None => (font_info.font_size * 0.9).max(1.0)
  }
  let line_height_factor = (font_info.line_height.to_double() /
  font_info.font_size.max(1.0)).max(1.3)
  let height = (font_size * line_height_factor).to_int().max(1).to_double()
  (font_size, height)
}

///|
fn CodeEditorWidget::apply_code_lens_style_and_height(
  self : CodeEditorWidget,
) -> Unit {
  guard self.code_lens_contribution() is Some(state) && !state.disposed else {
    return
  }
  let snapshot = self.configuration.snapshot()
  let (font_size, height) = self.code_lens_layout()
  match self.mount {
    Mounted(mounted) => {
      @base_browser.set_style_property(
        mounted.container,
        "--vscode-editorCodeLens-lineHeight",
        "\{height.to_string()}px",
      )
      @base_browser.set_style_property(
        mounted.container,
        "--vscode-editorCodeLens-fontSize",
        "\{font_size.to_string()}px",
      )
      @base_browser.set_style_property(
        mounted.container,
        "--vscode-editorCodeLens-fontFeatureSettings",
        snapshot.font_info.font_feature_settings,
      )
      @base_browser.set_style_property(
        mounted.container,
        "--vscode-editorCodeLens-fontFamily",
        snapshot.options.code_lens_font_family.unwrap_or(
          snapshot.font_info.font_family,
        ),
      )
    }
    Headless => ()
  }
  if state.rows.is_empty() {
    return
  }
  let viewport_state = self.capture_stable_viewport_state()
  self.change_view_zones(accessor => {
    for row in state.rows {
      row.zone.height_in_px = Some(height)
      match row.zone_id {
        Some(id) => accessor.layout_zone(id)
        None => ()
      }
    }
  })
  match self.current_code_view() {
    Some(view) =>
      for row in state.rows {
        view.content_widgets.set_widget_position(row.widget)
      }
    None => ()
  }
  match viewport_state {
    Some(viewport_state) =>
      self.restore_stable_viewport_state(viewport_state) |> ignore
    None => ()
  }
}

///|
fn CodeEditorWidget::code_lens_on_configuration_changed(
  self : CodeEditorWidget,
  previous : CodeEditorOptions,
) -> Unit {
  guard self.code_lens_contribution() is Some(_) else { return }
  let current = self.get_options()
  if previous.code_lens != current.code_lens {
    if current.code_lens {
      self.apply_code_lens_style_and_height()
      self.schedule_code_lens_refresh()
    } else {
      self.clear_code_lens_model_state()
    }
    return
  }
  if previous.code_lens_font_family != current.code_lens_font_family ||
    previous.code_lens_font_size != current.code_lens_font_size ||
    previous.font_family != current.font_family ||
    previous.font_size != current.font_size ||
    previous.line_height != current.line_height ||
    previous.font_weight != current.font_weight ||
    previous.letter_spacing != current.letter_spacing {
    self.apply_code_lens_style_and_height()
  }
  if previous != current {
    self.schedule_code_lens_refresh()
  }
}

///|
fn CodeEditorWidget::set_code_lens_host_for_test(
  self : CodeEditorWidget,
  schedule : (() -> Unit, Int) -> @base_common.Disposable,
  launch : (async () -> Unit noraise) -> Unit,
) -> Unit {
  match self.code_lens_contribution() {
    Some(state) => {
      state.schedule_timeout = schedule
      state.launch_async_task = launch
    }
    None => ()
  }
}

///|
fn CodeEditorWidget::code_lens_item_count_for_test(
  self : CodeEditorWidget,
) -> Int {
  match self.code_lens_contribution() {
    Some(state) => state.items.length()
    None => 0
  }
}

///|
let _code_lens_test_seam_anchor : Unit = ignore(
  (
    CodeEditorWidget::set_code_lens_host_for_test,
    CodeEditorWidget::code_lens_item_count_for_test,
  ),
)

///|
extern "js" fn code_lens_reset_children(element : @rdom.Element) -> Unit = "element => { element.textContent = ''; }"

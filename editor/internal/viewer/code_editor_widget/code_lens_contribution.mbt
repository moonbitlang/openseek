// Complete provider actions displayed above their declaration with the
// existing ViewZone and ContentWidget geometry. Each refresh owns one token,
// which remains live until these results are invalidated.

///|
let code_lens_contribution_id : String = "css.editor.codeLens"

///|
let code_lens_debounce_milliseconds : Int32 = 250

///|
priv struct CodeLensRenderedLine {
  item_indexes : Array[Int32]
  zone : @editor_browser.ViewZone
  mut zone_id : String?
  widget : @view.ContentWidgetHandle
  widget_dom : @rdom.Element
}

///|
priv struct CodeLensContributionState {
  mut disposed : Bool
  mut provide_source : @language.CancellationTokenSource?
  mut refresh_timer : @base_common.Disposable?
  mut schedule_timeout : (() -> Unit, Int32) -> @base_common.Disposable
  mut launch_async_task : (async () -> Unit noraise) -> Unit
  mut items : Array[@language.CodeLens]
  mut rows : Array[CodeLensRenderedLine]
  mut widget_id_pool : Int32
}

///|
fn CodeLensContributionState::CodeLensContributionState() -> CodeLensContributionState {
  {
    disposed: false,
    provide_source: None,
    refresh_timer: None,
    schedule_timeout: @base_browser.schedule_timeout,
    launch_async_task,
    items: [],
    rows: [],
    widget_id_pool: 0,
  }
}

///|
fn CodeLensContributionState::cancel_provide(
  self : CodeLensContributionState,
) -> Unit {
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
  for row in self.rows {
    row.widget_dom.set_attribute("inert", "")
    row.widget_dom.set_attribute("aria-disabled", "true")
  }
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
    _viewer => CodeLens(CodeLensContributionState()),
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
          viewer.clear_code_lens_model_state()
          viewer.schedule_code_lens_refresh()
        }),
      )
      listeners.push(
        viewer.services.languages.on_did_change_code_lenses(() => {
          viewer.schedule_code_lens_refresh()
        }),
      )
      listeners.push(
        viewer.on_did_layout_change(_ => {
          viewer.apply_code_lens_style_and_height()
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
fn CodeEditorWidget::clear_code_lens_model_state(
  self : CodeEditorWidget,
) -> Unit {
  guard self.code_lens_contribution() is Some(state) else { return }
  state.cancel_provide()
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
  let source = @language.CancellationTokenSource()
  state.provide_source = Some(source)
  state.refresh_timer = Some(
    (state.schedule_timeout)(
      () => self.begin_code_lens_refresh(model, source),
      code_lens_debounce_milliseconds,
    ),
  )
}

///|
fn CodeEditorWidget::begin_code_lens_refresh(
  self : CodeEditorWidget,
  model : @model.TextModel,
  source : @language.CancellationTokenSource,
) -> Unit {
  guard self.code_lens_contribution() is Some(state) &&
    !state.disposed &&
    !source.token().is_cancellation_requested() &&
    self.is_current_model(model) else {
    return
  }
  state.refresh_timer = None
  let launch = state.launch_async_task
  launch(async fn() noraise {
    let items = self.services.languages.code_lenses(
      model,
      token=source.token(),
      run_tasks=run_async_tasks_concurrently,
    )
    guard !source.token().is_cancellation_requested() &&
      self.is_current_model(model) else {
      source.dispose(cancel=true)
      return
    }
    self.render_code_lens_items(
      items.filter(lens => {
        code_lens_range_is_valid(model, lens.range) &&
        !lens.title.trim().is_empty()
      }),
    )
  })
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
  items : Array[@language.CodeLens],
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
  guard self.current_code_view() is Some(view) else { return }
  let height = self.code_lens_layout().1
  let rows : Array[CodeLensRenderedLine] = []
  let mut index = 0
  while index < items.length() {
    let line_number = items[index].range.start_line_number
    let indexes : Array[Int32] = []
    while index < items.length() &&
          items[index].range.start_line_number == line_number {
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
  line_number : Int32,
  item_indexes : Array[Int32],
  height : Double,
) -> CodeLensRenderedLine {
  let document = @rdom.document()
  let zone_dom = document.create_element("div")
  zone_dom.set_attribute("class", "codelens-view-zone")
  zone_dom.set_attribute("aria-hidden", "true")
  let widget_dom = document.create_element("span")
  widget_dom.set_attribute("class", "codelens-decoration")
  widget_dom.set_attribute("data-code-lens-line", line_number.to_string())
  let widget_index = state.widget_id_pool
  state.widget_id_pool = widget_index + 1
  let widget_id = "codelens.widget-\{self.get_id()}-\{widget_index.to_string()}"
  let widget = @view.ContentWidgetHandle(() => widget_id, () => widget_dom, () => {
    guard self.get_model() is Some(model) else { return None }
    let line = line_number
    guard line >= 1 && line <= model.get_line_count() else { return None }
    let first_non_whitespace = model.get_line_first_non_whitespace_column(line)
    let position : @view.ContentWidgetPosition = {
      position: Some(Position(line, first_non_whitespace.max(1))),
      secondary_position: None,
      preference: Some([Above]),
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
  )
  { item_indexes, zone, zone_id: None, widget, widget_dom, }
}

///|
fn CodeEditorWidget::render_code_lens_row(
  self : CodeEditorWidget,
  row : CodeLensRenderedLine,
) -> Unit {
  guard self.code_lens_contribution() is Some(state) else { return }
  let document = @rdom.document()
  let mut rendered_commands = 0
  for index in row.item_indexes {
    guard index >= 0 && index < state.items.length() else { continue }
    let lens = state.items[index]
    if rendered_commands > 0 {
      let separator = document.create_element("span")
      separator.set_attribute("class", "codelens-separator")
      separator.set_attribute("aria-hidden", "true")
      separator.append_child(document.create_text_node(" | ").as_node())
      row.widget_dom.append_child(separator.as_node())
    }
    let command_node = document.create_element("a")
    command_node.set_attribute("role", "button")
    command_node.set_attribute("tabindex", "0")
    guard state.provide_source is Some(source) else { return }
    let execute = () => {
      if !source.token().is_cancellation_requested() {
        (state.launch_async_task)(async fn() noraise {
          if !source.token().is_cancellation_requested() {
            (lens.execute)()
          }
        })
      }
    }
    command_node.add_event_listener("mousedown", event => {
      event.prevent_default()
      event.stop_propagation()
    })
    command_node.add_event_listener("click", event => {
      event.prevent_default()
      event.stop_propagation()
      execute()
    })
    command_node.add_event_listener("keydown", event => {
      guard event.to_keyboard_event() is Some(keyboard) else { return }
      if keyboard.key() == "Enter" || keyboard.key() == " " {
        event.prevent_default()
        event.stop_propagation()
        execute()
      }
    })
    match lens.tooltip {
      Some(tooltip) => command_node.set_attribute("title", tooltip)
      None => ()
    }
    command_node.append_child(
      document.create_text_node(lens.title.trim().to_owned()).as_node(),
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
  schedule : (() -> Unit, Int32) -> @base_common.Disposable,
  launch : (async () -> Unit noraise) -> Unit,
) -> Unit {
  guard self.code_lens_contribution() is Some(state) else { return }
  state.schedule_timeout = schedule
  state.launch_async_task = launch
}

///|
let _code_lens_test_host_anchor : Unit = ignore(
  CodeEditorWidget::set_code_lens_host_for_test,
)

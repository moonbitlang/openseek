///|
/// Backend-neutral document view model: the backing text model plus line
/// projection, decorations, and coordinate conversion. Long-lived like
/// Monaco's `ViewModel` (`viewModelImpl.ts`): constructed once at model
/// attach and updated in place through `on_configuration_changed` and
/// `on_did_change_content_or_injected_text`. Like Monaco, the line collection
/// is always `ViewModelLinesFromProjectedModel` — no-wrap documents stay
/// cheap through per-line `Identity` projections, not through a swapped
/// collection.
pub struct ViewModel {
  model : @model.TextModel
  mut options : ViewModelOptions
  lines : ViewModelLinesFromProjectedModel
  /// Outgoing-only cursor/ViewZones half of Monaco's
  /// `ViewModelEventDispatcher`. The mixed browser-view collector remains in
  /// the browser tier.
  cursor_event_dispatcher : CursorEventDispatcher
  /// Borrowed exact handle returned by TextModel attachment. ModelData alone
  /// owns its detach lifetime; ViewModel only publishes visible ranges.
  priv attached_view : @model.AttachedViewImpl?
  /// ViewModel's earlier scroll listener publishes unstable visible ranges
  /// before the root's later scroll/render listener.
  priv mut visible_lines_subscription : @base_common.Disposable?
  /// Constructor-owned model token listener (`viewModelImpl.ts:510-523`).
  /// Dispose it before the outgoing dispatcher so no late callback can
  /// enqueue into a retired ViewModel.
  priv mut model_tokens_subscription : @base_common.Disposable?
  /// The cursor state, owned per view model like Monaco's `_cursor`
  /// (`viewModelImpl.ts:65,124`): a new model starts with a fresh cursor at
  /// the origin, and reflows re-point it internally
  /// (`_cursor.onLineMappingChanged`, `viewModelImpl.ts:287`).
  cursor : @cursor.CursorsController
  /// The scroll/layout model, owned per view model like Monaco's
  /// `public readonly viewLayout` (`viewModelImpl.ts:64,126`): a new model
  /// starts at the scroll origin structurally. The viewport box is seeded
  /// from the widget's measured dimensions after construction (Monaco's
  /// `ViewLayout` reads `EditorOption.layoutInfo` from the configuration).
  view_layout : @view_layout.ViewLayout
  mut decorations : ViewModelDecorations
  coordinates_converter : CoordinatesConverter
  /// Per-source hidden-area sets, merged before they reach the line
  /// collection — Monaco's `hiddenAreasModel` (`viewModelImpl.ts:70`).
  priv hidden_areas_model : HiddenAreasModel
  /// The last merged hidden-area union, for `setHiddenAreas`'s no-change
  /// short-circuit — Monaco's `previousHiddenAreas` (`viewModelImpl.ts:71`).
  priv mut previous_hidden_areas : Array[@base_common.Range]
  /// Registration returned by `TextModel::register_view_model`
  /// (`viewModelImpl.ts:169`). Disposing it performs the source's
  /// `unregisterViewModel(this)` without relying on object identity.
  priv mut model_registration : @base_common.Disposable?
}

///|
/// Creates a view model with default no-wrap options.
pub fn ViewModel::ViewModel(model : @model.TextModel) -> ViewModel {
  ViewModel::with_options(model, ViewModelOptions::no_wrap())
}

///|
/// Creates a view model with wrapping/tab options — the line-collection
/// construction of Monaco's `ViewModel` constructor
/// (`viewModelImpl.ts:98-122`).
pub fn ViewModel::with_options(
  model : @model.TextModel,
  options : ViewModelOptions,
  smooth_scrolling? : Bool = false,
  schedule_at_next_animation_frame? : (() -> Unit) -> @base_common.Disposable = view_model_no_animation_scheduler,
  now? : () -> Double = view_model_zero_clock,
  attached_view? : @model.AttachedViewImpl,
  emit_view_tokens_changed? : (Array[ViewTokensChangedRange]) -> Unit = view_model_no_token_event_sink,
) -> ViewModel {
  let lines = ViewModelLinesFromProjectedModel(
    model,
    font_info=options.font_info,
    tab_size=options.tab_size,
    wrapping_column=options.soft_wrap_column,
    wrapping_indent=options.wrapping_indent,
  )
  let coordinates_converter = lines.create_coordinates_converter()
  // Monaco's member order: `_lines` → `coordinatesConverter` → `_cursor` →
  // `viewLayout` (`viewModelImpl.ts:122-126`) → `_decorations` (`:146`).
  let cursor_event_dispatcher = CursorEventDispatcher::CursorEventDispatcher()
  let cursor = @cursor.CursorsController(
    model,
    coordinates_converter.cursor_context(),
  )
  let view_layout = @view_layout.ViewLayout(
    line_height=options.font_info.line_height,
    line_count=lines.get_view_line_count(),
    smooth_scrolling~,
    schedule_at_next_animation_frame~,
    now~,
  )
  let decorations = ViewModelDecorations(
    options.editor_id,
    model,
    filter_validation_decorations(options.render_validation_decorations),
    lines,
    coordinates_converter,
  )
  let view_model : ViewModel = {
    model,
    options,
    lines,
    cursor_event_dispatcher,
    attached_view,
    visible_lines_subscription: None,
    model_tokens_subscription: None,
    cursor,
    view_layout,
    decorations,
    coordinates_converter,
    hidden_areas_model: HiddenAreasModel(),
    previous_hidden_areas: [],
    model_registration: None,
  }
  // `this.model.registerViewModel(this)` — the constructor tail
  // (`viewModelImpl.ts:169`). The callback registration keeps the model
  // package independent of this concrete type.
  view_model.model_registration = Some(
    model.register_view_model(
      e => view_model.on_did_change_content_or_injected_text(e~),
      e => view_model.emit_content_change_event(e),
    ),
  )
  view_model.visible_lines_subscription = Some(
    view_layout.on_did_scroll(change => {
      if change.scroll_top_changed {
        view_model.handle_visible_lines_changed()
      }
    }),
  )
  // Preserve `viewModelImpl.ts:510-523`: convert every inclusive model range
  // through the live projection, finish browser ViewEvent delivery, then
  // enqueue the original model event through the outgoing-only dispatcher.
  view_model.model_tokens_subscription = Some(
    model.on_did_change_tokens(event => {
      let view_ranges : Array[ViewTokensChangedRange] = []
      for model_range in event.ranges {
        let view_start = view_model.model_position_to_view_position(
          Position(model_range.from_line_number, 1),
        )
        let view_end = view_model.model_position_to_view_position(
          Position(
            model_range.to_line_number,
            model.get_line_max_column(model_range.to_line_number),
          ),
        )
        view_ranges.push({
          from_line_number: view_start.line_number,
          to_line_number: view_end.line_number,
        })
      }
      emit_view_tokens_changed(view_ranges)
      view_model.emit_model_tokens_changed(event)
    }),
  )
  view_model
}

///|
/// Detaches this view model from its model — the live half of Monaco's
/// `ViewModel.dispose` (`viewModelImpl.ts:172-181`):
/// `this.model.unregisterViewModel(this)`. The outgoing dispatcher owns its
/// registered cursor listeners and is retired here before layout teardown.
/// Called from the Viewer's `ModelData::dispose`.
pub fn ViewModel::dispose(self : ViewModel) -> Unit {
  if self.visible_lines_subscription is Some(subscription) {
    subscription.dispose()
  }
  self.visible_lines_subscription = None
  if self.model_tokens_subscription is Some(subscription) {
    subscription.dispose()
  }
  self.model_tokens_subscription = None
  self.cursor_event_dispatcher.dispose()
  self.lines.dispose()
  self.view_layout.dispose()
  if self.model_registration is Some(registration) {
    registration.dispose()
  }
  self.model_registration = None
}

///|
fn view_model_no_animation_scheduler(
  _callback : () -> Unit,
) -> @base_common.Disposable {
  @base_common.Disposable::from(() => ())
}

///|
fn view_model_zero_clock() -> Double {
  0.0
}

///|
/// Applies changed options to the live view model — Monaco's
/// `ViewModel._onConfigurationChanged` (`viewModelImpl.ts:274`) over the one
/// options struct: `_lines.setWrappingSettings` + `setTabSize` update the
/// collection in place, and a changed decoration filter input
/// (`renderValidationDecorations`, `editorId`) rotates the decoration
/// provider (Monaco's `_decorations.reset()` — the viewer's provider closes
/// over the filter at construction). Returns whether the view-line mapping
/// changed (Monaco emits `ViewFlushedEvent`/`ViewLineMappingChangedEvent`),
/// so the caller re-flushes the layout.
pub fn ViewModel::on_configuration_changed(
  self : ViewModel,
  options : ViewModelOptions,
) -> Bool {
  let previous = self.options
  if previous == options {
    return false
  }
  self.options = options
  let wrapping_changed = self.lines.set_wrapping_settings(
    options.font_info,
    options.soft_wrap_column,
    options.wrapping_indent,
  )
  let tab_size_changed = self.lines.set_tab_size(options.tab_size)
  let mapping_changed = wrapping_changed || tab_size_changed
  if mapping_changed {
    self.decorations.on_line_mapping_changed()
    // `this._cursor.onLineMappingChanged(...)` (`viewModelImpl.ts:287`): the
    // view model re-points its own cursor, re-projecting the selection from
    // its model positions.
    self.cursor.set_context(self.coordinates_converter.cursor_context())
  }
  if previous.editor_id != options.editor_id ||
    previous.render_validation_decorations !=
    options.render_validation_decorations {
    self.decorations = ViewModelDecorations(
      options.editor_id,
      self.model,
      filter_validation_decorations(options.render_validation_decorations),
      self.lines,
      self.coordinates_converter,
    )
  }
  mapping_changed
}

///|
/// Content or injected text changed — Monaco's
/// `onDidChangeContentOrInjectedText` (`viewModelImpl.ts:319-457`, called
/// directly by the text model), reduced to the two forms the viewer
/// produces. `e = None` is the `ModelInjectedTextChangedEvent` arm (the
/// union member is not ported — `text_model_events.mbt` header): Monaco
/// re-runs the line-breaks computer per changed line, the viewer reprojects
/// whole. `e = Some(_)` is the `InternalModelContentChangeEvent` arm, whose
/// only constructed change today is `Flush` (`:356-363`); the per-line
/// branches (`:364-408`) are the tier-2 lane. The root Viewer brackets the
/// reduced whole-document projection and emits the corresponding typed
/// `ViewFlushed`/mapping/decoration events through its View collector.
pub fn ViewModel::on_did_change_content_or_injected_text(
  self : ViewModel,
  e? : @model.InternalModelContentChangeEvent,
) -> Unit {
  match e {
    None => {
      self.lines.on_injected_text_changed()
      self.decorations.reset()
      // The reprojection changed the view-line mapping; re-point the cursor
      // (Monaco's injected-text arm updates cursor view positions through
      // `_cursor.onModelContentChanged`'s `setStates` re-project).
      self.cursor.set_context(self.coordinates_converter.cursor_context())
    }
    Some(e) => {
      for change in e.raw_content_changed_event.changes {
        match change {
          ModelRawFlush => {
            // The `Flush` branch (`viewModelImpl.ts:356-363`):
            // `_lines.onModelFlushed()` → `ViewFlushedEvent` (emitted by the
            // root source collector) → `_decorations.reset()` →
            // `viewLayout.onFlushed(lineCount)`. The custom-line-heights
            // argument is N-A (uniform line height).
            self.lines.on_model_flushed()
            self.decorations.reset()
            self.view_layout.on_flushed(self.lines.get_view_line_count())
          }
          // LinesDeleted/LinesInserted/LineChanged (`:364-404`): tier-2
          // (never constructed today). EOLChanged (`:405-408`): no-op in
          // the source; the EOL lane is a recorded scope cut.
          _ => ()
        }
      }
      // `_lines.acceptVersionId` (`:412-414`): N-A — the wholesale-rebuild
      // collection keeps no version assertion state.
      // Custom line heights (`:417-426`): N-A (uniform line height).
      // `viewLayout.onHeightMaybeChanged()` (`:428`).
      self.view_layout.on_height_maybe_changed() |> ignore
      // The `hadModelLineChangeThatChangedLineMapping` branch (`:430-435`)
      // is tier-2-only: a flush sets `hadOtherModelChange` instead.
      // `_viewportStart` invalidate + recovery (`:441-454`): scope cut 3 —
      // the recovery is gated on >= 2 attached editors; the single-editor
      // scroll clamps through the layout like Monaco's single-editor case.
      // `_configuration.setModelLineCount`/`_updateConfigurationViewLineCountNow`
      // (`:443-444`): the Viewer re-derives wrap facts in its content
      // listener.
    }
  }
  // `_handleVisibleLinesChanged` (`viewModelImpl.ts:456`) runs after the
  // projection/layout update so background priority observes current ranges.
  self.handle_visible_lines_changed()
}

///|
/// The text model's loop-two callback — `emitContentChangeEvent`
/// (`viewModelImpl.ts:462-469`). The outgoing `ModelContentChangedEvent` is
/// re-fired by the Viewer from the model's public emitter (the viewer's
/// outgoing-event seam), so the live half here is
/// `_cursor.onModelContentChanged`.
fn ViewModel::emit_content_change_event(
  self : ViewModel,
  e : @model.InternalModelContentChangeEvent,
) -> Unit {
  self.emit_cursor_state_change(self.cursor.on_model_content_changed(e))
  |> ignore
}

///|
/// The line collection for this view model.
pub fn ViewModel::lines(self : ViewModel) -> ViewModelLinesFromProjectedModel {
  self.lines
}

///|
/// ModelDecorationOptions buckets for this view model.
pub fn ViewModel::decorations(self : ViewModel) -> ViewModelDecorations {
  self.decorations
}

///|
/// Concrete coordinate converter owned by this view model. Callers erase it
/// only at lower-tier boundaries that genuinely retain heterogeneous
/// converters, such as `CursorContext`.
pub fn ViewModel::coordinates_converter(
  self : ViewModel,
) -> CoordinatesConverter {
  self.coordinates_converter
}

///|
/// Snaps a view position at injected-text/wrap boundaries per the affinity —
/// `ViewModel.normalizePosition` (`viewModelImpl.ts:1281-1283`).
pub fn ViewModel::normalize_position(
  self : ViewModel,
  position : @base_common.Position,
  affinity : @model.PositionAffinity,
) -> @base_common.Position {
  self.lines.normalize_position(position, affinity)
}

///|
/// Number of view lines.
pub fn ViewModel::line_count(self : ViewModel) -> Int {
  self.lines.get_view_line_count()
}

///|
/// The injected-text source index at a view position, or `-1`
/// for source text — the viewer's index-valued form of Monaco's
/// `ViewModel.getInjectedTextAt` (`viewModelImpl.ts`, delegating to the line
/// projection).
pub fn ViewModel::injected_text_index_at(
  self : ViewModel,
  position : @base_common.Position,
) -> Int {
  self.lines.injected_text_index_at(position.line_number, position.column - 1)
}

///|
/// Source document version.
pub fn ViewModel::version(self : ViewModel) -> Int {
  self.model.version
}

///|
/// Source document language id.
pub fn ViewModel::language_id(self : ViewModel) -> String {
  self.model.language_id
}

///|
/// Clamps a 1-based half-open view-line window to the document, the same
/// clamping the viewport-data builder applies (`viewport_data_from_view_model`)
/// so window consumers (the DOM recycler, hit tests) agree on the rendered
/// range.
pub fn ViewModel::clamp_window(
  self : ViewModel,
  window : @view_layout.LineWindow,
) -> @view_layout.LineWindow {
  let start = window.start.clamp(min=1, max=self.line_count())
  let end = window.end.clamp(min=start + 1, max=self.line_count() + 1)
  { start, end, }
}

///|
/// Monaco `ViewModel.getLineContent`: the text of a view line.
pub fn ViewModel::get_line_content(
  self : ViewModel,
  line_number : Int,
) -> String {
  // Text-only callers must not enter `getViewLineData`, whose token field is
  // a passive store read. Monaco's `getViewLineContent` delegates directly to
  // the projection (`viewModelImpl.ts` / `viewModelLines.ts`).
  self.lines.get_view_line_content(line_number)
}

///|
/// Monaco `ViewModel.getLineLength`: the text length of a view line.
pub fn ViewModel::get_line_length(self : ViewModel, line_number : Int) -> Int {
  self.lines.get_view_line_content(line_number).length()
}

///|
/// Monaco `ViewModel.getInjectedTextAt` (`viewModelImpl.ts`): the injected
/// text at a view position, or `None` on source text. The object is
/// re-derived from the position's model line (the projections retain only
/// per-column indices); `source_index` is the decoration's `attached_index`,
/// the same value `injected_text_index_at` reports.
pub fn ViewModel::get_injected_text_at(
  self : ViewModel,
  position : @base_common.Position,
) -> InjectedText? {
  let index = self.injected_text_index_at(position)
  if index < 0 {
    return None
  }
  let info = self.lines.get_view_line_info(position.line_number)
  for text in injected_text_for_model_line(self.model, info.model_line_number) {
    if text.source_index == index {
      return Some(text)
    }
  }
  None
}

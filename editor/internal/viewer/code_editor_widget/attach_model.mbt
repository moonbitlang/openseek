///|
/// Monaco's `_attachModel` (`codeEditorWidget.ts:1745-1913`): hook the
/// swap-scoped listeners, build the per-model `ViewModel`, create the per-model `View` inside the
/// container, and bundle everything into `ModelData`. Later option and
/// decoration changes update the view model in place
/// (`ViewModel::on_configuration_changed`,
/// `on_did_change_content_or_injected_text`). Token reads are passive;
/// explicit/visible/background demand owns lexer work. The paint happens in
/// the next render flush.
///
/// ```mermaid
/// flowchart LR
///   A[set_model] --> B[Install model-scoped<br>listeners and leases]
///   B --> C[Build ViewModel]
///   C --> D{Mounted?}
///   D -->|yes| E[Create View and<br>input handler]
///   D -->|no| F[Stay headless]
///   E --> G[Install one<br>ModelData bundle]
///   F --> G
///   G --> H[Publish flush facts,<br>schedule render frame]
/// ```
///
/// ViewModel callbacks use the generation gate, while model listeners are
/// disposed by `ModelData` teardown before a replacement can observe them.
fn CodeEditorWidget::attach_model(
  self : CodeEditorWidget,
  model : @model.TextModel,
) -> Unit {
  let model_data_generation = self.model_slot.begin_attach_generation()
  let listeners_to_remove : Array[@base_common.Disposable] = []
  // `data-mode-id` on the container (`cew:1758`), removed at detach.
  match self.mount {
    Headless => ()
    Mounted(mounted) =>
      mounted.container.set_attribute("data-mode-id", model.language_id)
  }
  // Monaco updates the configuration's model line-count environment before it
  // constructs ViewModel. Preserve the already measured outer client width,
  // then derive the new gutter/content width and wrap column synchronously.
  let model_line_count = model.snapshot.line_count()
  self.configuration.adjust_content_width_for_model_line_count(model_line_count)
  |> ignore
  self.configuration.set_line_counts(model_line_count, 0)
  self.configuration.recompute_soft_wrap_column() |> ignore
  // The decoration-change subscription attaches before the marker service
  // seeds the model so the seeding delta is observed too.
  listeners_to_remove.push(
    model.on_did_change_decorations(event => {
      let event_batch = self.begin_view_event_batch()
      // Monaco: `onDidChangeDecorations` → `viewModel.decorations
      // .onModelDecorationsChanged()` (`viewModelImpl.ts`) — drop the
      // computer + viewport caches before the re-render reads them.
      match self.get_view_model() {
        Some(view_model) => {
          view_model.decorations().on_model_decorations_changed()
          // Cache first, typed View event second. The direct model
          // subscription remains the approved outgoing-event seam.
          self.emit_view_event(ViewDecorationsChanged)
          // Injected-text deltas re-run the line-breaks computer per line in
          // Monaco (`onDidChangeContentOrInjectedText`); the viewer's
          // granularity is the whole-document reproject
          // (`_lines.on_injected_text_changed()`), applied to the live view
          // model. Content flushes take the event-carrying form of the same
          // member through the model's registered-view-model seam instead.
          if event.affects_injected_text {
            // The registered local reduction folds the injected structural
            // pass into this callback. The outer collector preserves: exact
            // Decorations → Flushed → LineMapping → all-Decorations →
            // optional Cursor reprojection.
            let previous_view_selection = view_model.cursor.get_view_selection()
            view_model.on_did_change_content_or_injected_text()
            self.on_line_mapping_changed(
              view_model,
              model,
              previous_view_selection~,
            )
          }
        }
        None => ()
      }
      end_view_event_batch(event_batch)
      self.schedule_render()
    }),
  )
  // One service registration owns marker seeding plus the model-content and
  // model-dispose watches. It is acquired before the CodeEditorWidget content/will/token
  // listeners so marker refresh and ModelDisposed handling run first; the
  // returned idempotent lease is released with this ModelData.
  listeners_to_remove.push(
    self.services.marker_decorations.acquire_model(model),
  )
  // The `set_value` flush lane (`model.onDidChangeContent`). By the time
  // this fires, the registered view models already re-projected (the
  // model's two-loop dispatch runs before its public emitter), so the
  // service registration already re-seeded marker decorations. The CodeEditorWidget
  // side re-flushes layout facts, re-fires the public event for contribs, and
  // schedules the repaint without acquiring another marker lease.
  listeners_to_remove.push(
    model.on_did_change_content(event => {
      let event_batch = self.begin_view_event_batch()
      if event.is_flush {
        self.emit_view_event(ViewFlushed)
      }
      match self.get_view_model() {
        Some(view_model) =>
          self.on_line_mapping_changed(view_model, model, notify_view=false)
        None => ()
      }
      end_view_event_batch(event_batch)
      // Monaco cancels the pending mouse reaction on content change. The
      // CodeEditorWidget also retires hover provider/timer ownership and rotates the operation
      // generation while preserving only an already settled hover until a new
      // pointer request replaces it. Incomplete/loading state is retired.
      match self.content_hover_controller() {
        Some(hc) => {
          hc.cancel_react()
          hc.cancel_operation_timers()
          hc.cancel_request()
          hc.hover = hc.hover.cancel_operation_preserving_view()
          // `set_value` just destroyed every model decoration. Retire the
          // matching hover bookkeeping. If a settled result stays visible, a
          // later accepted result still must not falsely dedupe against
          // decoration IDs/range that no longer exist.
          hc.reset_model_state()
          // The operation transition can remove an incomplete/loading-only
          // view. Reconcile the logical widget cache immediately; render
          // flushing only owns model decorations and cannot retire stale hover
          // DOM or headless visibility state for us.
          self.sync_content_hover_widget()
        }
        None => ()
      }
      self.schedule_render()
      self.did_change_model_content.fire(event)
      self.complete_model_content_delivery(model, event.version_id)
    }),
  )
  // A disposed model detaches itself
  // (`codeEditorWidget.ts:1787` `model.onWillDispose(() => this.setModel(null))`).
  listeners_to_remove.push(model.on_will_dispose(() => self.set_model(None)))
  // Decorations live in the model's interval-tree storage; the view
  // model queries them lazily per viewport (no per-frame bake). The render
  // pass pulls its viewport data from the view model at flush time.
  let attached_view = match self.mount {
    Mounted(_) =>
      model.on_before_attached(scheduler=browser_tokenization_scheduler)
    Headless => model.on_before_attached()
  }
  let build_started = @base_browser.monotonic_now_ms()
  let view_model = self.build_view_model(model, attached_view)
  self.configuration.set_line_counts(
    model.snapshot.line_count(),
    view_model.line_count(),
  )
  // The cursor outgoing alias is model-scoped. The ViewModel has already
  // committed both cursor coordinate states before this fires; the CodeEditorWidget
  // adds the public content barrier and position-before-selection relay.
  listeners_to_remove.push(
    view_model.on_cursor_state_changed(event => {
      if self.is_current_model_data_generation(model_data_generation) &&
        self.is_code_presentation() {
        // A real content flush waits behind the public content barrier so
        // `ViewFlushed` remains before the cursor event. Ordinary cursor
        // transitions notify ViewParts before the public outgoing pair.
        if !is_model_flush_cursor_event(event) {
          self.emit_view_cursor_state_changed(view_model)
        }
        self.enqueue_cursor_state_change(event)
      }
    }),
  )
  // The ViewZones outgoing arm is model-scoped. The root transaction emits
  // the internal ViewEvent first, then asks the ViewModel dispatcher to reach
  // this public alias.
  listeners_to_remove.push(
    view_model.on_view_zones_changed(_event => {
      if self.is_current_model_data_generation(model_data_generation) &&
        self.is_code_presentation() {
        self.did_change_view_zones.fire(())
      }
    }),
  )
  // Hidden-area changes use the same model-scoped outgoing relay. The
  // ViewModel publishes only after mapping, cursor/decorations, layout, stable
  // viewport recovery, and the root ViewEvent batch have completed.
  listeners_to_remove.push(
    view_model.on_hidden_areas_changed(_event => {
      if self.is_current_model_data_generation(model_data_generation) &&
        self.is_code_presentation() {
        self.did_change_hidden_areas.fire(())
      }
    }),
  )
  // `viewModelImpl.ts:522` reaches the root only after the ViewModel's
  // browser callback has synchronously delivered `ViewTokensChanged`. This
  // replaces the old direct TextModel listener and never invokes the lexer.
  listeners_to_remove.push(
    view_model.on_model_tokens_changed(event => {
      if self.is_current_model_data_generation(model_data_generation) {
        self.handle_model_tokens_changed(model, event.event)
      }
    }),
  )
  // Monaco's `ViewLayout.onDidScroll` is the single scroll-to-render seam.
  // Immediate calls and rAF animation ticks both arrive here, avoiding a
  // separate browser-only animation path.
  listeners_to_remove.push(
    view_model.view_layout.on_did_scroll(change => {
      self.apply_scroll_change(Some(change))
    }),
  )
  let browser = self.create_code_browser(model, view_model)
  self.model_slot.install_current({
    model,
    view_model,
    browser,
    attached_view,
    listeners_to_remove,
  })
  self.emit_view_event(ViewFlushed)
  self.apply_view_model_layout(view_model)
  let build_finished = @base_browser.monotonic_now_ms()
  self.emit_view_model_built({
    model,
    line_count: view_model.line_count(),
    token_count: model.tokenization.token_count(),
    tokenize_ms: 0.0,
    build_ms: build_finished - build_started,
  })
  self.pending_rendered = Some({ model, fresh: true, })
  self.configuration.request_measure()
  self.schedule_render()
}

///|
/// Whether a swap-scoped callback still belongs to the installed ModelData.
fn CodeEditorWidget::is_current_model_data_generation(
  self : CodeEditorWidget,
  generation : Int,
) -> Bool {
  self.model_slot.is_current_generation(generation)
}

///|
/// Build the browser code view inside the shared container. `None` while
/// headless.
fn CodeEditorWidget::create_code_browser(
  self : CodeEditorWidget,
  model : @model.TextModel,
  view_model : @view_model.ViewModel,
) -> CodeBrowserData? {
  let mounted = match self.mount {
    Headless => return None
    Mounted(mounted) => mounted
  }
  let read_view_zones_configuration = () => {
    self.configuration
    .snapshot()
    .view_zones_configuration(model.snapshot.line_count())
  }
  let view = @view.View(
    localization=self.services.localization,
    view_zones_configuration_reader=read_view_zones_configuration,
  )
  view.install_view_zones_context(
    view_model,
    self.services.log_service,
    read_view_zones_configuration,
    () => {
      // Common ViewModel cannot import browser ViewEvent. Complete the source
      // `changeWhitespace` order at this model-scoped seam for both public API
      // transactions and configuration/line-mapping recomputations.
      view.emit_view_zones_changed_then(() => {
        view_model.emit_view_zones_changed()
      })
    },
  )
  // ViewLines rereads the same live configuration snapshot in its
  // `onConfigurationChanged` handler, and its one retained-line factory
  // dynamically captures the equality-gated `ViewLineOptions` identity.
  view.view_lines.install_live_configuration_reader(() => {
    self.configuration.snapshot().view_lines_configuration()
  })
  view.view_lines.install_geometry_readers(
    view_line_number => {
      view_model
      .coordinates_converter()
      .view_position_to_model_position(Position(view_line_number, 1)).line_number
    },
    // The local ViewModel currently emits only LTR ViewLineRenderingData; the
    // reader remains explicit so model-direction ownership can replace this
    // fixed product seam without changing ViewLines aggregation again.
    _model_line_number => LTR,
  )
  // ContentWidgets retains Monaco's ViewContext for source-time layout-cache
  // refreshes and anchor reprojection. Install the model-scoped live readers
  // before any persistent widget is re-added to this fresh View.
  view.content_widgets.install_live_view_context_with_affinity(
    () => {
      self.configuration
      .snapshot()
      .content_widget_configuration(model.snapshot.line_count())
    },
    (position, affinity) => {
      let valid_position = model.validate_position(position)
      if view_model.model_position_is_visible(valid_position) {
        Some(
          view_model
          .coordinates_converter()
          .model_position_to_view_position(valid_position, affinity?),
        )
      } else {
        None
      }
    },
  )
  view.install_current_line_configuration_reader(() => {
    self.configuration
    .snapshot()
    .current_line_configuration(model.snapshot.line_count())
  })
  view.root.set_attribute(
    "data-theme",
    self.configuration.snapshot().options.theme,
  )
  mounted.install_presentation_root(view.root)
  view.apply_squiggly_theme()
  // The editor root carries the configured font — Monaco's
  // `applyFontInfo(this.domNode, fontInfo)` in `view.ts`.
  self.apply_font_info_to_view(view)
  // The pointer handler is view-owned (Monaco's `PointerHandler` lives in
  // the `View`), so a fresh `MouseHandler` hooks each new view.
  let mouse_handler = self.hook_view_input(view)
  // Re-add every registered widget to the new view (`cew:1893-1909`).
  match self.content_hover_contribution() {
    Some(state) =>
      match state.widget {
        Some(widget) => {
          // The widget survives model swaps, but its scrollbar listeners
          // belong to the per-View MouseHandler. The outgoing handler removed
          // its hooks, so bind the persistent scrollable to the freshly
          // created handler before remounting the widget.
          mouse_handler.hook_scrollable_scrollbar_input(
            widget.scrollable,
            HoverScrollableElement,
          )
          view.content_widgets.add_widget(widget.content_widget_handle())
        }
        None => ()
      }
    None => ()
  }
  for _, widget in self.overlay_widgets {
    view.overlay_widgets.add_widget(widget)
  }
  // `data-uri` (`cew:1912`).
  view.root.set_attribute("data-uri", model.uri.to_string())
  Some(CodeBrowserData(view, mouse_handler))
}

///|
fn CodeEditorWidget::build_view_model(
  self : CodeEditorWidget,
  model : @model.TextModel,
  attached_view : @model.AttachedViewImpl,
) -> @view_model.ViewModel {
  let configuration = self.configuration.snapshot()
  let options = configuration.view_model_options(self.editor_id)
  // Injected text reaches the projection through the model's decoration
  // storage, not through construction arguments.
  let view_model = @view_model.ViewModel::with_options(
    model,
    options,
    smooth_scrolling=configuration.options.smooth_scrolling,
    schedule_at_next_animation_frame=callback => {
      @base_browser.schedule_at_next_animation_frame(callback)
    },
    now=@base_browser.wall_clock_now_ms,
    attached_view~,
    emit_view_tokens_changed=ranges => {
      let changed_ranges : Array[(Int, Int)] = []
      for range in ranges {
        changed_ranges.push((range.from_line_number, range.to_line_number))
      }
      self.emit_view_event(
        ViewTokensChanged(view_tokens_changed_event(changed_ranges)),
      )
    },
  )
  // Seed the fresh layout's viewport box from the widget's measured
  // dimensions — Monaco's `ViewLayout` reads `EditorOption.layoutInfo` from
  // the configuration at construction.
  view_model.view_layout.set_viewport_size(
    width=configuration.content_width,
    height=configuration.height,
  )
  |> ignore
  view_model
}

///|
/// The root half of the ViewModel's outgoing model-token event. The internal
/// browser ViewEvent has already completed; telemetry reads stored counts
/// passively and the next frame repaints without re-warming the lexer.
fn CodeEditorWidget::handle_model_tokens_changed(
  self : CodeEditorWidget,
  model : @model.TextModel,
  _event : @model.ModelTokensChangedEvent,
) -> Unit {
  guard self.get_view_model() is Some(view_model) else { return }
  self.emit_view_model_built({
    model,
    line_count: view_model.line_count(),
    token_count: model.tokenization.token_count(),
    tokenize_ms: 0.0,
    build_ms: 0.0,
  })
  let fresh = match self.pending_rendered {
    Some(pending) => pending.fresh
    None => false
  }
  self.pending_rendered = Some({ model, fresh, })
  self.schedule_render()
}

///|
/// Routes a layout-affecting option change into the live view model —
/// Monaco's `_configuration.onDidChangeFast` → `_onConfigurationChanged`
/// subscription. A changed view-line mapping re-flushes the layout; anything
/// else only re-syncs the content width.
fn CodeEditorWidget::on_configuration_changed(
  self : CodeEditorWidget,
  previous_options? : CodeEditorOptions = self.configuration.snapshot().options,
) -> Unit {
  let event_batch = self.begin_view_event_batch()
  match (self.get_view_model(), self.get_model()) {
    (Some(view_model), Some(model)) => {
      let previous_view_selection = view_model.cursor.get_view_selection()
      let configuration = self.configuration.snapshot()
      let options = configuration.view_model_options(self.editor_id)
      if view_model.on_configuration_changed(options) {
        // Source order: Flushed → LineMapping → Decorations(null) →
        // cursor reprojection, followed by the layout flush.
        self.emit_view_event(ViewFlushed)
        self.emit_view_event(ViewLineMappingChanged)
        self.emit_view_event(ViewDecorationsChanged)
        self.emit_view_cursor_reprojection(view_model, previous_view_selection)
        self.on_line_mapping_changed(
          view_model,
          model,
          notify_view=false,
          notify_configuration=false,
        )
      } else {
        self.sync_content_width()
      }
      if previous_options.render_validation_decorations !=
        configuration.options.render_validation_decorations {
        // `ViewModel::on_configuration_changed` has already rotated the
        // filtered decoration provider; invalidate every decorations
        // consumer before the final Configuration event.
        self.emit_view_event(ViewDecorationsChanged)
      }
    }
    _ => self.sync_content_width()
  }
  end_view_event_batch(event_batch)
}

///|
/// The viewer's side of a changed view-line mapping (wrapping reflow,
/// injected text): re-flush the layout, drop the rendered window, and mark
/// the content stale — Monaco's `ViewFlushedEvent`/
/// `ViewLineMappingChangedEvent` handling (`viewLayout.onFlushed`; the view
/// model already re-pointed its own cursor).
fn CodeEditorWidget::on_line_mapping_changed(
  self : CodeEditorWidget,
  view_model : @view_model.ViewModel,
  model : @model.TextModel,
  notify_view? : Bool = true,
  notify_configuration? : Bool = true,
  layout_already_applied? : Bool = false,
  previous_view_selection? : @core.Selection,
) -> Unit {
  let previous_layout_identity = self.configuration.event_snapshot().layout
  let event_batch = if notify_view || notify_configuration {
    self.begin_view_event_batch()
  } else {
    None
  }
  if notify_view {
    self.emit_view_event(ViewFlushed)
    self.emit_view_event(ViewLineMappingChanged)
    self.emit_view_event(ViewDecorationsChanged)
    match previous_view_selection {
      Some(previous) => self.emit_view_cursor_reprojection(view_model, previous)
      None => ()
    }
  }
  if layout_already_applied {
    self.sync_content_width()
  } else {
    self.apply_view_model_layout(view_model)
  }
  match self.current_code_browser_data() {
    Some(browser) => browser.invalidate_rendered_window()
    None => ()
  }
  let current_model_line_count = model.snapshot.line_count()
  let current_view_line_count = view_model.line_count()
  self.sync_content_box_for_model_line_count(
    view_model, current_model_line_count,
  )
  |> ignore
  self.configuration.set_line_counts(
    current_model_line_count, current_view_line_count,
  )
  if notify_configuration &&
    previous_layout_identity != self.configuration.event_snapshot().layout {
    self.emit_view_event(
      ViewConfigurationChanged(
        @view.ViewConfigurationChangedEvent::from_changed_options([LayoutInfo]),
      ),
    )
  }
  end_view_event_batch(event_batch)
  if notify_configuration {
    self.emit_layout_change_if_needed(previous_layout_identity)
  }
  let fresh = match self.pending_rendered {
    Some(pending) => pending.fresh
    None => false
  }
  self.pending_rendered = Some({ model, fresh, })
}

///|
fn CodeEditorWidget::apply_view_model_layout(
  self : CodeEditorWidget,
  view_model : @view_model.ViewModel,
) -> Unit {
  view_model.view_layout.set_line_count(view_model.line_count()) |> ignore
  self.sync_content_width()
}

///|

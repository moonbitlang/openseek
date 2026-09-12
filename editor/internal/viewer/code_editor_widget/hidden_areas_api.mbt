// The hidden-areas slice of Monaco's `codeEditorWidget.ts` (vscode submodule
// checked-in source): `setHiddenAreas` (:637).
// The folding contrib is the producer; hidden lines fold out of the view
// axis entirely.

///|
/// `setHiddenAreas` (`codeEditorWidget.ts:637-639`): hides the given model
/// line ranges from the view, keyed by `source` so independent features
/// merge rather than clobber each other. A changed view-line mapping
/// re-flushes the layout and emits Monaco's typed `ViewFlushedEvent`/
/// `ViewLineMappingChangedEvent` fan-out at the source.
pub fn CodeEditorWidget::set_hidden_areas(
  self : CodeEditorWidget,
  ranges : Array[@base_common.Range],
  source? : String = "",
  force_update? : Bool = false,
) -> Unit {
  guard self.get_view_model() is Some(view_model) else { return }
  guard self.get_model() is Some(model) else { return }
  let mut previous_view_selection : @core.Selection? = None
  let mapping_changed = view_model.set_hidden_areas(
    ranges,
    source~,
    force_update~,
    with_event_batch=mutation => {
      // The unchanged gate runs before this source-shaped owner seam. Once
      // entered, cleanup-safe collection covers mutation, mapping/cursor
      // events, layout flush, recovery Scroll, and root bookkeeping.
      let event_batch = self.begin_view_event_batch()
      defer end_view_event_batch(event_batch)
      previous_view_selection = Some(view_model.cursor.get_view_selection())
      let changed = mutation()
      if changed {
        self.on_line_mapping_changed(
          view_model,
          model,
          notify_view=false,
          layout_already_applied=true,
        )
      }
      changed
    },
    on_line_mapping_changed=reproject_cursor => {
      // Pinned order inside one collector: Flushed → Mapping → Decorations →
      // cursor reprojection/event → layout flush/recovery Scroll.
      self.emit_view_event(ViewFlushed)
      self.emit_view_event(ViewLineMappingChanged)
      self.emit_view_event(ViewDecorationsChanged)
      reproject_cursor()
      match previous_view_selection {
        Some(previous) =>
          self.emit_view_cursor_reprojection(view_model, previous)
        None => ()
      }
    },
  )
  // A source may change while its complete range is already covered by
  // another source. The merged line projection is then unchanged, but a
  // ViewZone that ignores exactly one source can still become hidden/visible.
  // Recompute retained zone whitespace from the raw source map in that case;
  // the changed-only whitespace transaction keeps exact repeated inputs inert.
  let zone_visibility_changed = match self.current_code_browser_data() {
    Some(browser) =>
      browser.view.view_zones.refresh_hidden_area_source_visibility()
    None => false
  }
  if mapping_changed || zone_visibility_changed {
    self.schedule_render()
  }
}

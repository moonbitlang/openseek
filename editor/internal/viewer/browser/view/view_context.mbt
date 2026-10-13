///|
/// Shared browser render state passed to view parts during one coordinated
/// render. It exposes only the explicit capabilities parts need; the public
/// facade remains `Viewer` and browser DOM ownership stays on each part.
///
/// `pub(all)`: built by `Viewer::build_view_context` (`view_host.mbt`), which
/// stays beside the root-owned Viewer state to preserve dependency direction.
/// Construction is therefore a plain cross-package record literal rather than
/// a same-package constructor.
pub(all) struct ViewContext {
  // Monaco's `RenderingContext.linesVisibleRangesForRange` seam: measures the
  // pixel rects of a zero-based view-column range on a view line off the live
  // line DOM, which the selection overlay renders after `ViewLines` writes.
  measure_line_selection : (Int32, Int32, Int32) -> Array[(Double, Double)]
  // The same measurement with `keep_empty=true`, for the decorations overlay:
  // a collapsed range must yield its zero-width caret rect so the
  // `showIfCollapsed` widening has geometry to center on.
  measure_line_decorations : (Int32, Int32, Int32) -> Array[(Double, Double)]
  // Monaco's `RenderingContext.visibleRangeForPosition(...).left` seam: the
  // caret x of a one-based view column on a rendered view line
  // (`View::offset_for_column`; `-1` when the line is not rendered).
  offset_for_column : (Int32, Int32) -> Double
  // Model position → view position through the active coordinates converter
  // (Monaco `convertModelPositionToViewPosition`). Content-widget anchors are
  // model-space; their pixel placement resolves to the view-line axis here.
  model_position_to_view_position : (@base_common.Position) -> @base_common.Position
}

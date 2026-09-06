// VS Code renders original and modified overview data against their own
// editor/model coordinates. Keeping the two streams separate avoids inventing
// a modified-side anchor for deletion-only changes.

///|
let diff_overview_removed_color = "var(--vscode-diffEditorOverview-removedForeground, var(--vscode-diffEditor-removedLineBackground, rgba(255, 0, 0, 0.6)))"

///|
let diff_overview_inserted_color = "var(--vscode-diffEditorOverview-insertedForeground, var(--vscode-diffEditor-insertedLineBackground, rgba(155, 185, 85, 0.6)))"

///|
priv struct DiffOverviewViewportGeometry {
  top : Double
  height : Double
}

///|
/// Algorithm-fidelity port of the viewport-thumb calculation in VS Code's
/// `OverviewRulerFeature`: use the same ScrollbarState geometry as the
/// modified editor instead of estimating the visible fraction independently.
fn diff_overview_viewport_geometry(
  viewport_height : Double,
  scroll_height : Double,
  scroll_top : Double,
  scrollbar_size : Double,
) -> DiffOverviewViewportGeometry {
  let state = @view_layout.ScrollbarState(scrollbar_size~)
  state.set_visible_size(viewport_height) |> ignore
  state.set_scroll_size(scroll_height) |> ignore
  state.set_scroll_position(scroll_top) |> ignore
  { top: state.slider_position(), height: state.slider_size(), }
}

///|
fn diff_overview_ruler_entries(
  diff_state : DiffState,
  color : String,
  range_of : (@diff.DetailedLineRangeMapping) -> @base_common.LineRange,
) -> Array[@code_widget.CodeEditorOverviewRulerEntry] {
  let entries : Array[@code_widget.CodeEditorOverviewRulerEntry] = []
  for change_index, mapping in diff_state.mappings {
    let range = range_of(mapping.line_range_mapping)
    if !range.is_empty() {
      entries.push({ id: change_index, range, color, lane: Full, })
    }
  }
  entries
}

///|
fn original_diff_overview_ruler_entries(
  diff_state : DiffState,
) -> Array[@code_widget.CodeEditorOverviewRulerEntry] {
  diff_overview_ruler_entries(diff_state, diff_overview_removed_color, mapping => {
    mapping.original
  })
}

///|
fn modified_diff_overview_ruler_entries(
  diff_state : DiffState,
) -> Array[@code_widget.CodeEditorOverviewRulerEntry] {
  diff_overview_ruler_entries(diff_state, diff_overview_inserted_color, mapping => {
    mapping.modified
  })
}

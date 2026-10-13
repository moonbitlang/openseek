// Monaco's `LineNumbersOverlay`
// (`vscode/src/vs/editor/browser/viewParts/lineNumbers/lineNumbers.ts`), as a
// pure per-line HTML builder for `browser/view`'s `MarginViewOverlays` rows,
// reduced to the readonly subset of `lineNumbers: 'on'`: the model line
// number renders on the model line's first view line, and a soft-wrap
// continuation renders nothing (`modelPosition.column !== 1` → no output,
// the source's `:168-176` + empty-output skip `:181-184`). The
// relative/interval custom renderers and final-newline dimming are out of
// scope. The active model line follows the primary cursor independently of
// whether the blinking cursor itself is visible. Preparation is wired from
// `view_overlays_lifecycle.mbt`.

///|
/// The package-private line-numbers dynamic overlay state: the prepared
/// per-line HTML (`_renderResult`).
priv struct LineNumbersOverlay {
  mut render_result : Array[String]
}

///|
fn LineNumbersOverlay::LineNumbersOverlay() -> LineNumbersOverlay {
  { render_result: [], }
}

///|
/// `LineNumbersOverlay.prepareRender` (`lineNumbers.ts:158-206`) for the
/// readonly `'on'` subset: `<div class="line-numbers"
/// style="left:{lineNumbersLeft}px;width:{lineNumbersWidth}px;">{n}</div>`
/// per model-line-starting view line (`LineNumbersOverlay.CLASS_NAME`).
fn prepare_line_numbers_render(
  viewport : @view_layout.ViewportData,
  view_model : @view_model.ViewModel?,
  active_model_line_number : Int32?,
  left~ : Double,
  width~ : Double,
) -> Array[String] {
  let output : Array[String] = []
  for index in 0..<viewport.lines.length() {
    let view_line = viewport.start_line_number + index
    let model_position = match view_model {
      Some(view_model) =>
        view_model
        .coordinates_converter()
        .view_position_to_model_position(Position(view_line, 1))
      None => Position(view_line, 1)
    }
    if model_position.column != 1 {
      // A soft-wrap continuation: no line number
      // (`modelPosition.column !== 1`, `lineNumbers.ts:168-171`).
      output.push("")
      continue
    }
    let class_name = if active_model_line_number ==
      Some(model_position.line_number) {
      "line-numbers active-line-number"
    } else {
      "line-numbers"
    }
    output.push(
      "<div class=\"\{class_name}\" style=\"left:\{left.to_string()}px;width:\{width.to_string()}px;\">\{model_position.line_number.to_string()}</div>",
    )
  }
  output
}

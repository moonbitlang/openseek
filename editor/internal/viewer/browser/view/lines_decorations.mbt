// Ported from `vscode/src/vs/editor/browser/viewParts/linesDecorations/
// linesDecorations.ts` (`LinesDecorationsOverlay.prepareRender`/`render`), as
// a pure per-line HTML builder for `browser/view`'s `MarginViewOverlays`
// rows. The DOM-free half (decoration filtering + `DedupOverlay` expansion)
// lives in `viewer/common/view_model/margin_decorations.mbt`; preparation is
// wired from `view_overlays_lifecycle.mbt`.

///|
/// The package-private lines-decorations dynamic overlay state: the prepared
/// per-line HTML (`_renderResult`).
priv struct LinesDecorationsOverlay {
  mut render_result : Array[String]
}

///|
fn LinesDecorationsOverlay::LinesDecorationsOverlay() -> LinesDecorationsOverlay {
  { render_result: [], }
}

///|
/// `LinesDecorationsOverlay.prepareRender` (`linesDecorations.ts:96-118`):
/// per visible line, one `div.cldr.<class>` at `left = decorations_left`,
/// `width = decorations_width` (the shared `common` suffix); height comes
/// from the row (`height: 100%` in `lines_decorations.css`). A zero-width
/// lane renders nothing.
fn prepare_lines_decorations_render(
  class_names_per_line : Array[Array[String]],
  decorations_left~ : Double,
  decorations_width~ : Double,
) -> Array[String] {
  let output : Array[String] = []
  if decorations_width <= 0.0 {
    return Array::make(class_names_per_line.length(), "")
  }
  let common = "\" style=\"left:\{decorations_left.to_string()}px;width:\{decorations_width.to_string()}px;\"></div>"
  for class_names in class_names_per_line {
    let line_output = for class_name in class_names; line_output = "" {
      continue "\{line_output}<div class=\"cldr \{class_name}\{common}"
    } nobreak {
      line_output
    }
    output.push(line_output)
  }
  output
}

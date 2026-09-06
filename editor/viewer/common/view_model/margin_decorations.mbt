// Ported from `vscode/src/vs/editor/browser/viewParts/glyphMargin/glyphMargin.ts`
// (`DecorationToRender`, `DedupOverlay._render`) and the decoration-collection
// half of
// `vscode/src/vs/editor/browser/viewParts/linesDecorations/linesDecorations.ts`
// (`LinesDecorationsOverlay._getDecorations`). Kept DOM-free in the view-model
// tier so the dedup/expansion logic is unit-testable; the margin view part
// turns the per-line class names into `.cldr` nodes.

///|
/// A decoration to render along margin lines `start_line_number` through
/// `end_line_number` — Monaco's `DecorationToRender` (`glyphMargin.ts`).
/// `tooltip` (`linesDecorationsTooltip`) is not carried by the viewer's
/// decoration options; `z_index` is kept for parity but — like Monaco's
/// `LinesDecorationsOverlay` — does not affect the emitted order.
pub struct DecorationToRender {
  start_line_number : Int
  end_line_number : Int
  class_name : String
  z_index : Int
} derive(Eq, Debug)

///|
/// `LinesDecorationsOverlay._getDecorations`: the viewport decorations that
/// carry a `linesDecorationsClassName` — plus, on their first line only, a
/// `firstLineDecorationClassName` (the folding chevron's lane) — as render
/// entries. Ranges are view-space (the viewport decoration collection
/// already converted them).
pub fn lines_decorations_to_render(
  decorations : Array[ViewModelDecoration],
) -> Array[DecorationToRender] {
  let result : Array[DecorationToRender] = []
  for decoration in decorations {
    if decoration.options.lines_decorations_class_name is Some(class_name) {
      result.push({
        start_line_number: decoration.range.start_line_number,
        end_line_number: decoration.range.end_line_number,
        class_name,
        z_index: decoration.options.z_index,
      })
    }
    if decoration.options.first_line_decoration_class_name is Some(class_name) {
      result.push({
        start_line_number: decoration.range.start_line_number,
        end_line_number: decoration.range.start_line_number,
        class_name,
        z_index: decoration.options.z_index,
      })
    }
  }
  result
}

///|
/// `DedupOverlay._render`: expands the decorations into one class-name list
/// per visible line, skipping a class name already emitted on a line by an
/// earlier decoration of the same class. Sorting groups equal class names so
/// the previous-decoration dedup window works; `@base_common.compare` also
/// preserves JavaScript's UTF-16 lexicographic order for different classes.
pub fn dedup_margin_decorations(
  visible_start_line_number : Int,
  visible_end_line_number : Int,
  decorations : Array[DecorationToRender],
) -> Array[Array[String]] {
  let output : Array[Array[String]] = []
  for _ in visible_start_line_number..<=visible_end_line_number {
    output.push([])
  }
  if decorations.length() == 0 {
    return output
  }
  // Sort decorations by className, then by startLineNumber and then by
  // endLineNumber (`glyphMargin.ts DedupOverlay._render`).
  decorations.sort_by((a, b) => {
    if a.class_name == b.class_name {
      if a.start_line_number == b.start_line_number {
        a.end_line_number - b.end_line_number
      } else {
        a.start_line_number - b.start_line_number
      }
    } else {
      @base_common.compare(a.class_name, b.class_name)
    }
  })
  let mut prev_class_name : String? = None
  let mut prev_end_line_index = 0
  for decoration in decorations {
    let class_name = decoration.class_name
    let mut start_line_index = (decoration.start_line_number -
    visible_start_line_number).max(0)
    let end_line_index = (decoration.end_line_number - visible_start_line_number).min(
      visible_end_line_number - visible_start_line_number,
    )
    if prev_class_name == Some(class_name) {
      // Here we avoid rendering the same className multiple times on the
      // same line.
      start_line_index = start_line_index.max(prev_end_line_index + 1)
      prev_end_line_index = prev_end_line_index.max(end_line_index)
    } else {
      prev_class_name = Some(class_name)
      prev_end_line_index = end_line_index
    }
    for line_index in start_line_index..<=prev_end_line_index {
      output[line_index].push(class_name)
    }
  }
  output
}

///|
pub extend DecorationToRender with Debug::{to_repr}

///|
pub extend DecorationToRender with Eq::{equal, not_equal}

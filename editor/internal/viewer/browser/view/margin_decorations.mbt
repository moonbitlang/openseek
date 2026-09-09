// Ported from `vscode/src/vs/editor/browser/viewParts/marginDecorations/
// marginDecorations.ts`. Unlike the adjacent line-decorations lane, these
// pieces span the complete margin width and therefore color the line-number
// band as well as the marker lane.

///|
priv struct MarginDecorationsOverlay {
  mut render_result : Array[String]
}

///|
priv struct WholeMarginDecoration {
  start_line_number : Int
  end_line_number : Int
  class_name : String
}

///|
fn MarginDecorationsOverlay::MarginDecorationsOverlay() -> MarginDecorationsOverlay {
  { render_result: [], }
}

///|
/// `MarginViewLineDecorationsOverlay._getDecorations`: collect only the
/// viewport decorations that paint the complete editor margin. Keep this in
/// the internal DOM renderer so adding the overlay does not widen the public
/// view-model API.
fn margin_decorations_to_render(
  decorations : Array[@view_model.ViewModelDecoration],
) -> Array[WholeMarginDecoration] {
  let result : Array[WholeMarginDecoration] = []
  for decoration in decorations {
    match decoration.options.margin_class_name {
      Some(class_name) =>
        result.push({
          start_line_number: decoration.range.start_line_number,
          end_line_number: decoration.range.end_line_number,
          class_name,
        })
      None => ()
    }
  }
  result
}

///|
/// Internal counterpart of `DedupOverlay._render`. The public view-model
/// helper remains dedicated to `linesDecorationsClassName`; whole-margin
/// decoration plumbing stays implementation detail here.
fn dedup_whole_margin_decorations(
  visible_start_line_number : Int,
  visible_end_line_number : Int,
  decorations : Array[WholeMarginDecoration],
) -> Array[Array[String]] {
  let output : Array[Array[String]] = []
  for _ in visible_start_line_number..<=visible_end_line_number {
    output.push([])
  }
  if decorations.length() == 0 {
    return output
  }
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
  let mut previous_class_name : String? = None
  let mut previous_end_line_index = 0
  for decoration in decorations {
    let class_name = decoration.class_name
    let mut start_line_index = if decoration.start_line_number >
      visible_start_line_number {
      decoration.start_line_number - visible_start_line_number
    } else {
      0
    }
    let end_line_index = if decoration.end_line_number < visible_end_line_number {
      decoration.end_line_number - visible_start_line_number
    } else {
      visible_end_line_number - visible_start_line_number
    }
    if previous_class_name is Some(prev_class) && prev_class == class_name {
      start_line_index = if previous_end_line_index + 1 > start_line_index {
        previous_end_line_index + 1
      } else {
        start_line_index
      }
      if end_line_index > previous_end_line_index {
        previous_end_line_index = end_line_index
      }
    } else {
      previous_class_name = Some(class_name)
      previous_end_line_index = end_line_index
    }
    for line_index in start_line_index..<=previous_end_line_index {
      output[line_index].push(class_name)
    }
  }
  output
}

///|
fn prepare_margin_decorations_render(
  class_names_per_line : Array[Array[String]],
) -> Array[String] {
  let output : Array[String] = []
  for class_names in class_names_per_line {
    let line_output = for class_name in class_names; line_output = "" {
      continue "\{line_output}<div class=\"cmdr \{class_name}\" style=\"\"></div>"
    } nobreak {
      line_output
    }
    output.push(line_output)
  }
  output
}

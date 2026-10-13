// The DOM-free half of Monaco's
// `viewParts/currentLineHighlight/currentLineHighlight.ts` (oracle checked-in source):
// the abstract overlay's should-render predicates, the two concrete class
// builders, and the wrapped-line span helper. The canonical option enum lives
// in `viewer/common/editor_api`. The DOM overlays that consume these are in
// `internal/viewer/browser/view/current_line_highlight.mbt` and its
// `current_line_margin_highlight.mbt` sibling. This DOM-free option behavior
// stays here; canonical public option values live in `viewer/common/editor_api`.

///|
/// `AbstractLineHighlightOverlay._shouldRenderInMargin`
/// (`currentLineHighlight.ts:184-189`).
pub fn should_render_line_highlight_in_margin(
  mode : @editor_api.RenderLineHighlight,
  only_when_focus : Bool,
  focused : Bool,
) -> Bool {
  (mode == Gutter || mode == All) && (!only_when_focus || focused)
}

///|
/// `AbstractLineHighlightOverlay._shouldRenderInContent`
/// (`currentLineHighlight.ts:191-197`): the content fill/border renders only
/// while the selection is empty.
pub fn should_render_line_highlight_in_content(
  mode : @editor_api.RenderLineHighlight,
  only_when_focus : Bool,
  focused : Bool,
  selection_is_empty : Bool,
) -> Bool {
  (mode == Line || mode == All) &&
  selection_is_empty &&
  (!only_when_focus || focused)
}

///|
/// `CurrentLineHighlightOverlay._renderOne`'s class string
/// (`currentLineHighlight.ts:210`).
pub fn current_line_content_class(in_margin~ : Bool, exact~ : Bool) -> String {
  "current-line\{(if in_margin { " current-line-both" } else { "" })}\{(if exact { " current-line-exact" } else { "" })}"
}

///|
/// `CurrentLineMarginHighlightOverlay._renderOne`'s class string
/// (`currentLineHighlight.ts:226`).
pub fn current_line_margin_class(
  in_margin~ : Bool,
  other~ : Bool,
  exact~ : Bool,
) -> String {
  "current-line\{(if in_margin { " current-line-margin" } else { "" })}\{(if other { " current-line-margin-both" } else { "" })}\{(if in_margin && exact { " current-line-exact-margin" } else { "" })}"
}

///|
/// The first and last one-based view lines of the model line containing
/// `view_line_number` — the wrapped-line pass's converter round-trip
/// (`currentLineHighlight.ts:146-149`), realized as a scan over the
/// view→model line mapping (same result: view lines of one model line are
/// contiguous). `model_line_of` is the caller's
/// `model_line_number_of_view_line`; `line_count` is the view line count.
pub fn view_line_span_of_model_line(
  view_line_number : Int32,
  line_count : Int32,
  model_line_of : (Int32) -> Int32,
) -> (Int32, Int32) {
  let model_line = model_line_of(view_line_number)
  let first = for first = view_line_number; first > 1 &&
                 model_line_of(first - 1) == model_line; {
    continue first - 1
  } nobreak {
    first
  }
  let last = for last = view_line_number; last < line_count &&
                model_line_of(last + 1) == model_line; {
    continue last + 1
  } nobreak {
    last
  }
  (first, last)
}

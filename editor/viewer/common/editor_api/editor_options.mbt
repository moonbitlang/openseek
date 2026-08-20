///|
/// Monaco's `renderWhitespace` option. The renderer owns the behavior while
/// this dependency-bottom package owns the public value contract.
pub(all) enum RenderWhitespace {
  None
  Boundary
  Selection
  Trailing
  All
} derive(Eq, Debug)

///|
/// Monaco's `renderLineHighlight` option.
pub(all) enum RenderLineHighlight {
  None
  Gutter
  Line
  All
} derive(Eq, Debug)

///|
/// Monaco's `WrappingIndent` option (`config/editorOptions.ts`). `None` is
/// flush-left, `Same` retains the model line's indentation, and
/// `Indent`/`DeepIndent` add one/two tab stops.
pub(all) enum WrappingIndent {
  None
  Same
  Indent
  DeepIndent
} derive(Eq, Debug)

///|
/// Monaco's `renderValidationDecorations` option (`editorOptions.ts`).
/// `Editable` follows editor mutability, while `On` and `Off` are
/// unconditional. Monaco defaults to `Editable`; the readonly Viewer chooses
/// `On` so its diagnostic decorations remain visible.
pub(all) enum RenderValidationDecorations {
  Editable
  On
  Off
} derive(Eq, Debug)

///|
/// Monaco's `showFoldingControls` option.
pub(all) enum ShowFoldingControls {
  Always
  Never
  Mouseover
} derive(Eq, Debug)

///|
pub extend RenderLineHighlight with Debug::{to_repr}

///|
pub extend RenderLineHighlight with Eq::{equal, not_equal}

///|
pub extend RenderValidationDecorations with Debug::{to_repr}

///|
pub extend RenderValidationDecorations with Eq::{equal, not_equal}

///|
pub extend RenderWhitespace with Debug::{to_repr}

///|
pub extend RenderWhitespace with Eq::{equal, not_equal}

///|
pub extend ShowFoldingControls with Debug::{to_repr}

///|
pub extend ShowFoldingControls with Eq::{equal, not_equal}

///|
pub extend WrappingIndent with Debug::{to_repr}

///|
pub extend WrappingIndent with Eq::{equal, not_equal}

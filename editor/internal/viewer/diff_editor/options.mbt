///|
/// The concrete presentation used by a diff editor. `SideBySide` renders one
/// code editor per pane; `Inline` keeps the modified editor as the primary
/// surface and projects original-only content into managed view zones.
pub(all) enum DiffEditorLayout {
  SideBySide
  Inline
} derive(Eq, Debug)

///|
/// Diff panes normally inherit the host's code-editor wrapping policy. `Off`
/// is retained for hosts that require horizontally stable comparison rows.
pub(all) enum DiffWordWrap {
  Inherit
  Off
} derive(Eq, Debug)

///|
/// Diff-level options. Code-editor presentation details remain owned by the
/// two child widgets; these values only control the comparison coordinator.
pub(all) struct DiffEditorOptions {
  layout : DiffEditorLayout
  automatic_inline : Bool
  automatic_inline_width : Double
  sash_enabled : Bool
  split_ratio : Double
  diff_word_wrap : DiffWordWrap
  overview_ruler : Bool
  render_indicators : Bool
  render_markdown_comments : Bool
  handle_mouse_wheel : Bool
  ignore_trim_whitespace : Bool
}

///|
pub fn DiffEditorOptions::DiffEditorOptions(
  layout~ : DiffEditorLayout = SideBySide,
  automatic_inline~ : Bool = true,
  automatic_inline_width~ : Double = 900.0,
  sash_enabled~ : Bool = true,
  split_ratio~ : Double = 0.5,
  diff_word_wrap~ : DiffWordWrap = Inherit,
  overview_ruler~ : Bool = true,
  render_indicators~ : Bool = true,
  render_markdown_comments~ : Bool = true,
  handle_mouse_wheel~ : Bool = true,
  ignore_trim_whitespace~ : Bool = true,
) -> DiffEditorOptions {
  {
    layout,
    automatic_inline,
    automatic_inline_width: automatic_inline_width.max(0.0),
    sash_enabled,
    split_ratio: split_ratio.clamp(min=0.1, max=0.9),
    diff_word_wrap,
    overview_ruler,
    render_indicators,
    render_markdown_comments,
    handle_mouse_wheel,
    ignore_trim_whitespace,
  }
}

///|
pub fn DiffEditorOptions::default() -> DiffEditorOptions {
  DiffEditorOptions()
}

///|
pub extend DiffEditorLayout with Eq::{equal, not_equal}

///|
pub extend DiffEditorLayout with Debug::{to_repr}

///|
pub extend DiffWordWrap with Eq::{equal, not_equal}

///|
pub extend DiffWordWrap with Debug::{to_repr}

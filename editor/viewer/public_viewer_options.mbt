///|
/// Opaque public options for the standalone code surface. The canonical
/// option state lives in the code kernel; this wrapper prevents the internal
/// package type from leaking through the public package boundary.
struct ViewerOptions {
  inner : @code_widget.CodeEditorOptions
} derive(Eq, Debug)

///|
pub fn ViewerOptions::ViewerOptions(
  soft_wrap? : Bool = false,
  tab_size? : Int = 2,
  wrapping_indent? : @editor_api.WrappingIndent = Same,
  render_whitespace? : @editor_api.RenderWhitespace = Selection,
  render_control_characters? : Bool = true,
  render_line_highlight? : @editor_api.RenderLineHighlight = Line,
  render_line_highlight_only_when_focus? : Bool = false,
  render_validation_decorations? : @editor_api.RenderValidationDecorations = On,
  theme? : String = "dark",
  placeholder? : String = "",
  line_decorations_width? : Int = 10,
  line_numbers_min_chars? : Int = 5,
  folding? : Bool = true,
  show_folding_controls? : @editor_api.ShowFoldingControls = Mouseover,
  folding_highlight? : Bool = true,
  folding_maximum_regions? : Int = 5000,
  unfold_on_click_after_end_of_line? : Bool = false,
  smooth_scrolling? : Bool = false,
  show_unused? : Bool = true,
  show_deprecated? : Bool = true,
  code_lens? : Bool = true,
  code_lens_font_family? : String,
  code_lens_font_size? : Double,
  font_family? : String = @config.editor_font_defaults.font_family,
  font_weight? : String = @config.editor_font_defaults.font_weight,
  font_size? : Double = @config.editor_font_defaults.font_size,
  line_height? : Double = @config.editor_font_defaults.line_height,
  letter_spacing? : Double = @config.editor_font_defaults.letter_spacing,
) -> ViewerOptions {
  {
    inner: CodeEditorOptions(
      soft_wrap~,
      tab_size~,
      wrapping_indent~,
      render_whitespace~,
      render_control_characters~,
      render_line_highlight~,
      render_line_highlight_only_when_focus~,
      render_validation_decorations~,
      theme~,
      placeholder~,
      line_decorations_width~,
      line_numbers_min_chars~,
      folding~,
      show_folding_controls~,
      folding_highlight~,
      folding_maximum_regions~,
      unfold_on_click_after_end_of_line~,
      smooth_scrolling~,
      show_unused~,
      show_deprecated~,
      code_lens~,
      code_lens_font_family?,
      code_lens_font_size?,
      font_family~,
      font_weight~,
      font_size~,
      line_height~,
      letter_spacing~,
    ),
  }
}

///|
pub fn ViewerOptions::default() -> ViewerOptions {
  { inner: @code_widget.CodeEditorOptions::default(), }
}

///|
pub fn ViewerOptions::with_placeholder(
  self : ViewerOptions,
  value : String,
) -> ViewerOptions {
  { inner: self.inner.with_placeholder(value), }
}

///|
pub fn ViewerOptions::with_theme(
  self : ViewerOptions,
  value : String,
) -> ViewerOptions {
  { inner: self.inner.with_theme(value), }
}

///|
pub fn ViewerOptions::with_font_family(
  self : ViewerOptions,
  value : String,
) -> ViewerOptions {
  { inner: self.inner.with_font_family(value), }
}

///|
pub fn ViewerOptions::with_font_size(
  self : ViewerOptions,
  value : Double,
) -> ViewerOptions {
  { inner: self.inner.with_font_size(value), }
}

///|
pub fn ViewerOptions::with_code_lens(
  self : ViewerOptions,
  value : Bool,
) -> ViewerOptions {
  { inner: self.inner.with_code_lens(value), }
}

///|
pub fn ViewerOptions::with_code_lens_font_family(
  self : ViewerOptions,
  value : String?,
) -> ViewerOptions {
  { inner: self.inner.with_code_lens_font_family(value), }
}

///|
pub fn ViewerOptions::with_code_lens_font_size(
  self : ViewerOptions,
  value : Double?,
) -> ViewerOptions {
  { inner: self.inner.with_code_lens_font_size(value), }
}

///|
pub fn ViewerOptions::with_render_whitespace(
  self : ViewerOptions,
  value : @editor_api.RenderWhitespace,
) -> ViewerOptions {
  { inner: self.inner.with_render_whitespace(value), }
}

///|
pub fn ViewerOptions::with_render_control_characters(
  self : ViewerOptions,
  value : Bool,
) -> ViewerOptions {
  { inner: self.inner.with_render_control_characters(value), }
}

///|
pub fn ViewerOptions::with_render_line_highlight(
  self : ViewerOptions,
  value : @editor_api.RenderLineHighlight,
) -> ViewerOptions {
  { inner: self.inner.with_render_line_highlight(value), }
}

///|
pub fn ViewerOptions::with_render_line_highlight_only_when_focus(
  self : ViewerOptions,
  value : Bool,
) -> ViewerOptions {
  { inner: self.inner.with_render_line_highlight_only_when_focus(value), }
}

///|
pub fn ViewerOptions::with_render_validation_decorations(
  self : ViewerOptions,
  value : @editor_api.RenderValidationDecorations,
) -> ViewerOptions {
  { inner: self.inner.with_render_validation_decorations(value), }
}

///|
pub fn ViewerOptions::with_tab_size(
  self : ViewerOptions,
  value : Int,
) -> ViewerOptions {
  { inner: self.inner.with_tab_size(value), }
}

///|
pub fn ViewerOptions::with_soft_wrap(
  self : ViewerOptions,
  value : Bool,
) -> ViewerOptions {
  { inner: self.inner.with_soft_wrap(value), }
}

///|
pub fn ViewerOptions::with_line_numbers_min_chars(
  self : ViewerOptions,
  value : Int,
) -> ViewerOptions {
  { inner: self.inner.with_line_numbers_min_chars(value), }
}

///|
pub fn ViewerOptions::with_line_decorations_width(
  self : ViewerOptions,
  value : Int,
) -> ViewerOptions {
  { inner: self.inner.with_line_decorations_width(value), }
}

///|
pub fn ViewerOptions::with_line_height(
  self : ViewerOptions,
  value : Double,
) -> ViewerOptions {
  { inner: self.inner.with_line_height(value), }
}

///|
pub fn ViewerOptions::soft_wrap(self : ViewerOptions) -> Bool {
  self.inner.soft_wrap()
}

///|
pub fn ViewerOptions::line_height(self : ViewerOptions) -> Double {
  self.inner.line_height()
}

///|
fn ViewerOptions::code_options(
  self : ViewerOptions,
) -> @code_widget.CodeEditorOptions {
  self.inner
}

///|
pub extend ViewerOptions with Debug::{to_repr}

///|
pub extend ViewerOptions with Eq::{equal, not_equal}

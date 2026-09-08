///|
/// Runtime viewer options that affect view-model construction and layout.
struct CodeEditorOptions {
  soft_wrap : Bool
  tab_size : Int
  wrapping_indent : @editor_api.WrappingIndent
  render_whitespace : @editor_api.RenderWhitespace
  render_control_characters : Bool
  render_line_highlight : @editor_api.RenderLineHighlight
  render_line_highlight_only_when_focus : Bool
  /// `renderValidationDecorations`. Product default `On` — Monaco defaults to
  /// `Editable`, which hides validation squiggles in readonly editors, and the
  /// readonly viewer's diagnostics rendering is a shipped feature. Hosts can
  /// pass `Editable`/`Off` for Monaco's semantics.
  render_validation_decorations : @editor_api.RenderValidationDecorations
  /// The color theme, Monaco's standalone `theme` option
  /// (`IStandaloneEditorConstructionOptions.theme`, also accepted by
  /// `updateOptions`). Mirrored onto the view root as `data-theme`.
  theme : String
  /// The message shown while the viewer has no rendered model — Monaco's
  /// `placeholder` editor option.
  placeholder : String
  /// Width in pixels of the line-decorations gutter lane between the line
  /// numbers and the content — Monaco's `lineDecorationsWidth` editor option
  /// (default `10`, `editorOptions.ts:3304-3307`). Features that draw gutter
  /// decorations (e.g. agent feedback) reserve extra lane width on top
  /// through `update_options`.
  line_decorations_width : Int
  /// Minimum digit slots reserved by the line-number band — Monaco's
  /// `lineNumbersMinChars` editor option (default `5`, minimum `1`,
  /// `editorOptions.ts:6379-6381`). The band widens past this when the model
  /// has more-digit line numbers.
  line_numbers_min_chars : Int
  /// Monaco's `folding` editor option (default `true`): whether code folding
  /// is enabled.
  folding : Bool
  /// Monaco's `showFoldingControls` editor option (default `mouseover`):
  /// when the gutter chevrons are visible. `always`/`never`/`mouseover`.
  show_folding_controls : @editor_api.ShowFoldingControls
  /// Monaco's `foldingHighlight` editor option (default `true`): whether
  /// folded ranges get the `folded-background` highlight.
  folding_highlight : Bool
  /// Monaco's `foldingMaximumRegions` editor option (default `5000`).
  folding_maximum_regions : Int
  /// Monaco's `unfoldOnClickAfterEndOfLine` editor option (default `false`).
  unfold_on_click_after_end_of_line : Bool
  /// Monaco's `smoothScrolling` option (`false` by default). Physical mouse
  /// wheels animate for 125 ms when enabled; trackpads remain immediate.
  smooth_scrolling : Bool
  /// Monaco's `handleMouseWheel` option (`true` by default). MultiDiffEditor
  /// items disable this so their single outer scroll plane owns wheel input.
  handle_mouse_wheel : Bool
  /// Monaco's `showUnused` editor option (default `true`,
  /// `editorOptions.ts:6645-6647`): adds the `showUnused` root class that
  /// gates the `squiggly-unnecessary` / `squiggly-inline-unnecessary`
  /// styling (`EditorClassName.compute`, `editorOptions.ts:1680-1682`).
  show_unused : Bool
  /// Monaco's `showDeprecated` editor option (default `true`,
  /// `editorOptions.ts:6649-6653`): adds the `showDeprecated` root class
  /// gating the `squiggly-inline-deprecated` strike-through.
  show_deprecated : Bool
  /// Monaco's standalone `codeLens` option. The contribution is installed
  /// only for standalone viewers, but this live gate can hide/show it without
  /// rebuilding the code view.
  code_lens : Bool
  /// Optional CodeLens-specific font overrides. `None` inherits the measured
  /// editor font family and 90% of its measured size.
  code_lens_font_family : String?
  code_lens_font_size : Double?
  /// Monaco's `fontFamily`/`fontWeight`/`fontSize`/`lineHeight`/
  /// `letterSpacing` editor options, defaulting to `EDITOR_FONT_DEFAULTS`.
  /// `line_height` follows `BareFontInfo._create`'s rules: `0` derives the
  /// golden-ratio height from `font_size`, values below `8` multiply the
  /// font size (ems), anything else is pixels.
  font_family : String
  font_weight : String
  font_size : Double
  line_height : Double
  letter_spacing : Double
} derive(Eq, Debug)

///|
/// Builds viewer options, normalizing `tab_size` to at least one column.
/// `wrapping_indent` defaults to `Same`, Monaco's default, and applies only when
/// `soft_wrap` is on. `render_whitespace` defaults to `Selection`, Monaco's
/// default — whitespace glyphs render under the active selection.
/// `render_control_characters` defaults to `true`, also matching Monaco — it
/// only changes output on lines that contain control characters.
/// `render_line_highlight` defaults to `Line` and
/// `render_line_highlight_only_when_focus` to `false`, Monaco's defaults for
/// the current-line highlight (`editorOptions.ts`).
pub fn CodeEditorOptions::CodeEditorOptions(
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
  handle_mouse_wheel? : Bool = true,
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
) -> CodeEditorOptions {
  {
    soft_wrap,
    tab_size: tab_size.max(1),
    wrapping_indent,
    render_whitespace,
    render_control_characters,
    render_line_highlight,
    render_line_highlight_only_when_focus,
    render_validation_decorations,
    theme,
    placeholder,
    line_decorations_width: line_decorations_width.max(0),
    line_numbers_min_chars: line_numbers_min_chars.max(1),
    folding,
    show_folding_controls,
    folding_highlight,
    folding_maximum_regions,
    unfold_on_click_after_end_of_line,
    smooth_scrolling,
    handle_mouse_wheel,
    show_unused,
    show_deprecated,
    code_lens,
    code_lens_font_family,
    code_lens_font_size,
    font_family,
    font_weight,
    font_size,
    line_height,
    letter_spacing,
  }
}

///|
/// Whether the two option sets agree on every field that feeds view-model
/// construction or layout — `theme`, `placeholder`, and the root-class flags
/// (`show_unused`/`show_deprecated`) apply without a rebuild.
fn CodeEditorOptions::same_layout_options(
  self : CodeEditorOptions,
  other : CodeEditorOptions,
) -> Bool {
  {
    ..self,
    theme: other.theme,
    placeholder: other.placeholder,
    show_unused: other.show_unused,
    show_deprecated: other.show_deprecated,
    code_lens: other.code_lens,
    code_lens_font_family: other.code_lens_font_family,
    code_lens_font_size: other.code_lens_font_size,
    smooth_scrolling: other.smooth_scrolling,
    handle_mouse_wheel: other.handle_mouse_wheel,
  } ==
  other
}

///|
/// Default readonly viewer options.
pub fn CodeEditorOptions::default() -> CodeEditorOptions {
  CodeEditorOptions()
}

///|
/// Returns a copy with Monaco's no-model placeholder changed.
pub fn CodeEditorOptions::with_placeholder(
  self : CodeEditorOptions,
  placeholder : String,
) -> CodeEditorOptions {
  { ..self, placeholder, }
}

///|
/// Returns a copy with the standalone theme changed.
pub fn CodeEditorOptions::with_theme(
  self : CodeEditorOptions,
  theme : String,
) -> CodeEditorOptions {
  { ..self, theme, }
}

///|
/// Returns a copy with the measured editor font family changed.
pub fn CodeEditorOptions::with_font_family(
  self : CodeEditorOptions,
  font_family : String,
) -> CodeEditorOptions {
  { ..self, font_family, }
}

///|
/// Returns a copy with the measured editor font size changed.
pub fn CodeEditorOptions::with_font_size(
  self : CodeEditorOptions,
  font_size : Double,
) -> CodeEditorOptions {
  { ..self, font_size, }
}

///|
/// Returns a copy with CodeLens rendering enabled or disabled.
pub fn CodeEditorOptions::with_code_lens(
  self : CodeEditorOptions,
  code_lens : Bool,
) -> CodeEditorOptions {
  { ..self, code_lens, }
}

///|
/// Returns a copy with the optional CodeLens font-family override changed.
pub fn CodeEditorOptions::with_code_lens_font_family(
  self : CodeEditorOptions,
  code_lens_font_family : String?,
) -> CodeEditorOptions {
  { ..self, code_lens_font_family, }
}

///|
/// Returns a copy with the optional CodeLens font-size override changed.
pub fn CodeEditorOptions::with_code_lens_font_size(
  self : CodeEditorOptions,
  code_lens_font_size : Double?,
) -> CodeEditorOptions {
  { ..self, code_lens_font_size, }
}

///|
/// Returns a copy with `renderWhitespace` changed.
pub fn CodeEditorOptions::with_render_whitespace(
  self : CodeEditorOptions,
  render_whitespace : @editor_api.RenderWhitespace,
) -> CodeEditorOptions {
  { ..self, render_whitespace, }
}

///|
/// Returns a copy with `renderControlCharacters` changed.
pub fn CodeEditorOptions::with_render_control_characters(
  self : CodeEditorOptions,
  render_control_characters : Bool,
) -> CodeEditorOptions {
  { ..self, render_control_characters, }
}

///|
/// Returns a copy with `renderLineHighlight` changed.
pub fn CodeEditorOptions::with_render_line_highlight(
  self : CodeEditorOptions,
  render_line_highlight : @editor_api.RenderLineHighlight,
) -> CodeEditorOptions {
  { ..self, render_line_highlight, }
}

///|
/// Returns a copy with the focused-only line-highlight gate changed.
pub fn CodeEditorOptions::with_render_line_highlight_only_when_focus(
  self : CodeEditorOptions,
  render_line_highlight_only_when_focus : Bool,
) -> CodeEditorOptions {
  { ..self, render_line_highlight_only_when_focus, }
}

///|
/// Returns a copy with `renderValidationDecorations` changed.
pub fn CodeEditorOptions::with_render_validation_decorations(
  self : CodeEditorOptions,
  render_validation_decorations : @editor_api.RenderValidationDecorations,
) -> CodeEditorOptions {
  { ..self, render_validation_decorations, }
}

///|
/// Returns a copy with the tab size changed, normalized to at least one.
pub fn CodeEditorOptions::with_tab_size(
  self : CodeEditorOptions,
  tab_size : Int,
) -> CodeEditorOptions {
  { ..self, tab_size: tab_size.max(1), }
}

///|
/// Returns a copy with soft wrapping enabled or disabled.
pub fn CodeEditorOptions::with_soft_wrap(
  self : CodeEditorOptions,
  soft_wrap : Bool,
) -> CodeEditorOptions {
  { ..self, soft_wrap, }
}

///|
/// Returns a copy with Monaco's folding option changed. The option also
/// controls the line-decoration space reserved for folding affordances.
pub fn CodeEditorOptions::with_folding(
  self : CodeEditorOptions,
  folding : Bool,
) -> CodeEditorOptions {
  { ..self, folding, }
}

///|
/// Returns a copy with Monaco's `handleMouseWheel` policy changed.
pub fn CodeEditorOptions::with_handle_mouse_wheel(
  self : CodeEditorOptions,
  handle_mouse_wheel : Bool,
) -> CodeEditorOptions {
  { ..self, handle_mouse_wheel, }
}

///|
/// Returns a copy with the minimum line-number digit count changed, normalized
/// to at least one.
pub fn CodeEditorOptions::with_line_numbers_min_chars(
  self : CodeEditorOptions,
  line_numbers_min_chars : Int,
) -> CodeEditorOptions {
  { ..self, line_numbers_min_chars: line_numbers_min_chars.max(1), }
}

///|
/// Returns a copy with the line-decoration gutter width changed, normalized to
/// a non-negative value.
pub fn CodeEditorOptions::with_line_decorations_width(
  self : CodeEditorOptions,
  line_decorations_width : Int,
) -> CodeEditorOptions {
  { ..self, line_decorations_width: line_decorations_width.max(0), }
}

///|
/// Returns a copy with a non-negative width added to the line-decoration
/// gutter. Hosts use this when their surface owns controls in that lane
/// independently of the editor's folding affordances.
pub fn CodeEditorOptions::with_additional_line_decorations_width(
  self : CodeEditorOptions,
  additional_width : Int,
) -> CodeEditorOptions {
  {
    ..self,
    line_decorations_width: self.line_decorations_width +
    additional_width.max(0),
  }
}

///|
/// Returns a copy with the requested line height changed.
pub fn CodeEditorOptions::with_line_height(
  self : CodeEditorOptions,
  line_height : Double,
) -> CodeEditorOptions {
  { ..self, line_height, }
}

///|
/// Whether soft wrapping is enabled in this snapshot.
pub fn CodeEditorOptions::soft_wrap(self : CodeEditorOptions) -> Bool {
  self.soft_wrap
}

///|
/// The requested line height in this snapshot.
pub fn CodeEditorOptions::line_height(self : CodeEditorOptions) -> Double {
  self.line_height
}

///|
/// The `BareFontInfo` these options request — Monaco's
/// `BareFontInfo.createFromValidatedSettings`. The viewer has no
/// `fontLigatures` option, so `font-feature-settings` is constantly
/// `EditorFontLigatures.OFF` (Monaco's default).
fn CodeEditorOptions::bare_font_info(
  self : CodeEditorOptions,
  pixel_ratio~ : Double,
) -> @config.BareFontInfo {
  @config.BareFontInfo::create(
    font_family=self.font_family,
    font_weight=self.font_weight,
    font_size=self.font_size,
    font_feature_settings=@config.editor_font_ligatures_off,
    font_variation_settings=@config.font_variation_off,
    line_height=self.line_height,
    letter_spacing=self.letter_spacing,
    pixel_ratio~,
  )
}

///|
/// Computes the soft-wrap column that fits the measured content width, or zero
/// when wrapping is disabled or measurement is not ready.
fn CodeEditorOptions::soft_wrap_column_for_content_width(
  self : CodeEditorOptions,
  content_width : Double,
  char_width : Double,
) -> Int {
  if !self.soft_wrap || content_width <= 0.0 || char_width <= 0.0 {
    0
  } else {
    (1).max((content_width / char_width).to_int())
  }
}

///|
/// Converts browser-level options into backend-neutral view-model options.
/// `font_info` is the viewer's measured font (Monaco's `EditorOption.fontInfo`),
/// not an option field, so it rides in as an argument.
fn CodeEditorOptions::view_model_options(
  self : CodeEditorOptions,
  soft_wrap_column : Int,
  font_info~ : @config.FontInfo,
  editor_id? : Int = 0,
) -> @view_model.ViewModelOptions {
  if self.soft_wrap && soft_wrap_column > 0 {
    ViewModelOptions(
      font_info~,
      soft_wrap_column~,
      tab_size=self.tab_size,
      wrapping_indent=self.wrapping_indent,
      editor_id~,
      render_validation_decorations=self.render_validation_decorations,
    )
  } else {
    ViewModelOptions(
      font_info~,
      tab_size=self.tab_size,
      editor_id~,
      render_validation_decorations=self.render_validation_decorations,
    )
  }
}

///|
pub extend CodeEditorOptions with Eq::{equal, not_equal}

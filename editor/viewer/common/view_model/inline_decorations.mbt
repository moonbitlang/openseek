///|
/// Faithful 1:1 port of Monaco's viewModel/inlineDecorations.ts
/// (InlineDecoration, InlineDecorationType, InlineModelDecorationsComputer,
/// InjectedTextInlineDecorationsComputer) from checked-in vscode submodule.
///
/// Production uses the package's concrete TextModel, CoordinatesConverter,
/// ModelDecorationOptions, and ModelDecoration types. The white-box reference
/// suite supplies resolved private option values only for source branches that
/// the current model tier cannot produce.
///
/// DEVIATIONS:
///   * isModelDecorationVisible always returns true: the
///     hideInCommentTokens/hideInStringTokens paths need model option fields
///     and token queries this readonly port does not carry.
///   * ModelDecorationOptions has no beforeContentClassName or affectsFont, so
///     production resolves those fields to None/false. The reference suite
///     still executes the source branches through a private resolved-options
///     adapter; that proves the algorithm, not product reach.
///   * The canonical converter does not expose allowZeroLineNumber or
///     belowHiddenRanges switches. Existing whole-line affinities and hidden
///     line handling remain unchanged.

///|
/// Placement of an inline decoration relative to the source text (Monaco's
/// InlineDecorationType, declared in inlineDecorations.ts).
priv enum InlineDecorationType {
  Regular
  Before
  After
  RegularAffectingLetterSpacing
} derive(Eq)

///|
/// An inline decoration over a line/column Range.
priv struct InlineDecoration {
  range : @base_common.Range
  inline_class_name : String
  type_ : InlineDecorationType
} derive(Eq)

///|
/// Builds an inline decoration (Monaco new InlineDecoration).
fn InlineDecoration::InlineDecoration(
  range : @base_common.Range,
  inline_class_name : String,
  type_ : InlineDecorationType,
) -> InlineDecoration {
  { range, inline_class_name, type_, }
}

///|
/// The six source option reads used by the computer. Production resolves this
/// value from the concrete model options; wbtests may construct it directly
/// for source branches whose model fields remain deferred.
priv struct ResolvedInlineDecorationOptions {
  inline_class_name : String?
  inline_class_name_affects_letter_spacing : Bool
  before_content_class_name : String?
  after_content_class_name : String?
  affects_font : Bool
  is_whole_line : Bool
}

///|
fn ResolvedInlineDecorationOptions::from_model(
  options : @model.ModelDecorationOptions,
) -> ResolvedInlineDecorationOptions {
  {
    inline_class_name: options.inline_class_name,
    inline_class_name_affects_letter_spacing: options.inline_class_name_affects_letter_spacing,
    // DEFERRED: ModelDecorationOptions has no beforeContentClassName.
    before_content_class_name: None,
    after_content_class_name: options.after_content_class_name,
    // DEFERRED: ModelDecorationOptions has no affectsFont.
    affects_font: false,
    is_whole_line: options.is_whole_line,
  }
}

///|
/// Decorations in a range of lines: ungrouped, grouped per line as inline
/// decorations, and a per-line affects-font flag (Monaco
/// IViewDecorationsCollection). Only the resolved decoration list crosses the
/// package boundary.
pub struct ViewDecorationsCollection {
  decorations : Array[ViewModelDecoration]
  priv inline_decorations : Array[Array[InlineDecoration]]
  priv has_variable_fonts : Array[Bool]
}

///|
let _inline_decorations_wbtest_anchors : Unit = {
  ignore(fn(left : InlineDecoration, right : InlineDecoration) -> Bool {
    left == right
  })
  ignore(fn(collection : ViewDecorationsCollection) -> Array[Bool] {
    collection.has_variable_fonts
  })
  ignore(InlineModelDecorationsComputer::get_inline_decorations)
}

///|
/// Concrete context for InlineModelDecorationsComputer.
priv struct InlineModelContext {
  get_model_decorations : (@base_common.Range, Bool, Bool) -> Array[
    @model.ModelDecoration,
  ]
}

///|
/// Computes inline decorations from concrete model decorations, mapped into
/// view coordinates and grouped per view line.
priv struct InlineModelDecorationsComputer {
  context : InlineModelContext
  model : @model.TextModel
  coordinates_converter : CoordinatesConverter
  mut decorations_cache : Map[String, ViewModelDecoration]
}

///|
/// Builds an inline-model-decorations computer.
fn InlineModelDecorationsComputer::InlineModelDecorationsComputer(
  context : InlineModelContext,
  model : @model.TextModel,
  coordinates_converter : CoordinatesConverter,
) -> InlineModelDecorationsComputer {
  { context, model, coordinates_converter, decorations_cache: Map([]), }
}

///|
/// Inline decorations for one model line, split by view line.
fn InlineModelDecorationsComputer::get_inline_decorations(
  self : InlineModelDecorationsComputer,
  model_line_number : Int,
) -> Array[Array[InlineDecoration]] {
  let model_range = @base_common.Range(
    model_line_number,
    1,
    model_line_number,
    self.model.snapshot.get_line_max_column(model_line_number),
  )
  let view_range = self.coordinates_converter.model_range_to_view_range(
    model_range,
  )
  self.get_decorations(view_range, false, false).inline_decorations
}

///|
/// Resolve the decorations intersecting a view range through production model
/// options.
fn InlineModelDecorationsComputer::get_decorations(
  self : InlineModelDecorationsComputer,
  view_range : @base_common.Range,
  only_minimap_decorations : Bool,
  only_margin_decorations : Bool,
) -> ViewDecorationsCollection {
  let model_decorations = (self.context.get_model_decorations)(
    view_range, only_minimap_decorations, only_margin_decorations,
  )
  self.compute_decorations(model_decorations, view_range, decoration => {
    ResolvedInlineDecorationOptions::from_model(decoration.options)
  })
}

///|
/// Source-shaped algorithm over concrete model decorations. The resolver is a
/// package-private wbtest seam for source option branches absent from the
/// current model representation; production always uses from_model above.
fn InlineModelDecorationsComputer::compute_decorations(
  self : InlineModelDecorationsComputer,
  model_decorations : Array[@model.ModelDecoration],
  view_range : @base_common.Range,
  resolve_options : (@model.ModelDecoration) -> ResolvedInlineDecorationOptions,
) -> ViewDecorationsCollection {
  let start_line_number = view_range.start_line_number
  let end_line_number = view_range.end_line_number
  let decorations_in_viewport : Array[ViewModelDecoration] = []
  let inline_decorations : Array[Array[InlineDecoration]] = []
  let has_variable_fonts : Array[Bool] = []
  for _j in start_line_number..<=end_line_number {
    inline_decorations.push([])
    has_variable_fonts.push(false)
  }
  for model_decoration in model_decorations {
    let decoration_options = resolve_options(model_decoration)
    if !is_model_decoration_visible(self.model, model_decoration) {
      continue
    }
    let view_model_decoration = self.get_or_create_view_model_decoration(
      model_decoration, decoration_options,
    )
    let view_range = view_model_decoration.range
    decorations_in_viewport.push(view_model_decoration)
    if decoration_options.inline_class_name is Some(inline_class_name) {
      let type_ = if decoration_options.inline_class_name_affects_letter_spacing {
        RegularAffectingLetterSpacing
      } else {
        Regular
      }
      let inline_decoration = InlineDecoration::InlineDecoration(
        view_range, inline_class_name, type_,
      )
      let intersected_start_line_number = start_line_number.max(
        view_range.start_line_number,
      )
      let intersected_end_line_number = end_line_number.min(
        view_range.end_line_number,
      )
      for j in intersected_start_line_number..<=intersected_end_line_number {
        inline_decorations[j - start_line_number].push(inline_decoration)
        if decoration_options.affects_font {
          has_variable_fonts[j - start_line_number] = true
        }
      }
    }
    if decoration_options.before_content_class_name
      is Some(before_content_class_name) &&
      start_line_number <= view_range.start_line_number &&
      view_range.start_line_number <= end_line_number {
      let inline_decoration = InlineDecoration::InlineDecoration(
        Range(
          view_range.start_line_number,
          view_range.start_column,
          view_range.start_line_number,
          view_range.start_column,
        ),
        before_content_class_name,
        Before,
      )
      inline_decorations[view_range.start_line_number - start_line_number].push(
        inline_decoration,
      )
      if decoration_options.affects_font {
        has_variable_fonts[view_range.start_line_number - start_line_number] = true
      }
    }
    if decoration_options.after_content_class_name
      is Some(after_content_class_name) &&
      start_line_number <= view_range.end_line_number &&
      view_range.end_line_number <= end_line_number {
      let inline_decoration = InlineDecoration::InlineDecoration(
        Range(
          view_range.end_line_number,
          view_range.end_column,
          view_range.end_line_number,
          view_range.end_column,
        ),
        after_content_class_name,
        After,
      )
      inline_decorations[view_range.end_line_number - start_line_number].push(
        inline_decoration,
      )
      if decoration_options.affects_font {
        has_variable_fonts[view_range.end_line_number - start_line_number] = true
      }
    }
  }
  {
    decorations: decorations_in_viewport,
    inline_decorations,
    has_variable_fonts,
  }
}

///|
/// Drop the per-decoration view-model cache.
fn InlineModelDecorationsComputer::reset(
  self : InlineModelDecorationsComputer,
) -> Unit {
  self.decorations_cache = Map([])
}

///|
/// onModelDecorationsChanged (inlineDecorations.ts:155-157).
fn InlineModelDecorationsComputer::on_model_decorations_changed(
  self : InlineModelDecorationsComputer,
) -> Unit {
  self.reset()
}

///|
/// onLineMappingChanged (inlineDecorations.ts:159-161).
fn InlineModelDecorationsComputer::on_line_mapping_changed(
  self : InlineModelDecorationsComputer,
) -> Unit {
  self.reset()
}

///|
/// Re-resolve, or reuse the cached, view-model decoration for a model decoration.
fn InlineModelDecorationsComputer::get_or_create_view_model_decoration(
  self : InlineModelDecorationsComputer,
  model_decoration : @model.ModelDecoration,
  decoration_options : ResolvedInlineDecorationOptions,
) -> ViewModelDecoration {
  let id = model_decoration.id
  match self.decorations_cache.get(id) {
    Some(r) => r
    None => {
      let model_range = model_decoration.range
      let options = model_decoration.options
      let view_range = if decoration_options.is_whole_line {
        // For backwards compatibility, whole-line decorations span min..max
        // col, kept outside injected text (inlineDecorations.ts:171-172).
        // DEFERRED: the source belowHiddenRanges switch is absent; hidden-line
        // handling remains in the projection.
        let start = self.coordinates_converter.model_position_to_view_position(
          Position(model_range.start_line_number, 1),
          affinity=Left,
        )
        let end = self.coordinates_converter.model_position_to_view_position(
          Position(
            model_range.end_line_number,
            self.model.snapshot.get_line_max_column(model_range.end_line_number),
          ),
          affinity=Right,
        )
        @base_common.Range(
          start.line_number,
          start.column,
          end.line_number,
          end.column,
        )
      } else {
        // inlineDecorations.ts:177: Right keeps an empty decoration right of
        // injected text at its position.
        self.coordinates_converter.model_range_to_view_range(
          model_range,
          affinity=Right,
        )
      }
      let r = ViewModelDecoration::ViewModelDecoration(view_range, options)
      self.decorations_cache[id] = r
      r
    }
  }
}

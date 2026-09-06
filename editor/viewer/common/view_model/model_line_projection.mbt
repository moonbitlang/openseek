///|
/// Per-model-line projection, Monaco's `IModelLineProjection`
/// (`modelLineProjection.ts:16`) with the package's enum dispatch standing in
/// for interface polymorphism. `Identity` is Monaco's
/// `IdentityModelLineProjection.INSTANCE`: a visible line with no wrapping
/// and no injected text that delegates straight to the model, so the common
/// no-wrap document allocates no per-line projection data at all. `Hidden` is
/// Monaco's `HiddenModelLineProjection.INSTANCE`: a line hidden by
/// `setHiddenAreas` (folding), producing zero view lines. `Projected` is
/// Monaco's `ModelLineProjection` class, used to wrap model lines and inject
/// text; it carries its own visibility like Monaco's `_isVisible`.
///
/// Content queries on an invisible projection abort — the `Hidden` arms are
/// the port of both `HiddenModelLineProjection`'s `throw new Error('Not
/// supported')` and `ModelLineProjection._assertVisible` (an invisible
/// `Projected` is not asserted per method; only valid view lines reach these
/// accessors).
pub enum ModelLineProjection {
  Identity
  Hidden
  Projected(ModelLineProjectionData, is_visible~ : Bool)
}

///|
/// `createModelLineProjection` (`modelLineProjection.ts:52`): `None`
/// line-break data means no mapping is needed.
pub fn create_model_line_projection(
  data : ModelLineProjectionData?,
  is_visible : Bool,
) -> ModelLineProjection {
  match data {
    None => if is_visible { Identity } else { Hidden }
    Some(data) => Projected(data, is_visible~)
  }
}

///|
/// Whether this model line is visible — `isVisible`.
pub fn ModelLineProjection::is_visible(self : ModelLineProjection) -> Bool {
  match self {
    Identity => true
    Hidden => false
    Projected(_, is_visible~) => is_visible
  }
}

///|
/// Returns this projection with the given visibility — `setVisible`
/// (`modelLineProjection.ts:22`, "this invalidates the current instance"):
/// callers store the returned projection back, exactly Monaco's
/// `projections[i] = projections[i].setVisible(v)` pattern. The identity
/// singletons swap between `Identity` and `Hidden`.
pub fn ModelLineProjection::set_visible(
  self : ModelLineProjection,
  is_visible : Bool,
) -> ModelLineProjection {
  match self {
    Identity | Hidden => if is_visible { Identity } else { Hidden }
    Projected(data, ..) => Projected(data, is_visible~)
  }
}

///|
/// Number of view lines this model line produces — `getViewLineCount`:
/// zero while hidden.
pub fn ModelLineProjection::get_view_line_count(
  self : ModelLineProjection,
) -> Int {
  match self {
    Identity => 1
    Hidden => 0
    Projected(data, is_visible~) =>
      if is_visible {
        data.view_line_count()
      } else {
        0
      }
  }
}

///|
/// Text of one view line — `getViewLineContent`: the projected segment's
/// slice with the continuation indent prepended (`spaces(...) + r`), or the
/// model line as-is.
pub fn ModelLineProjection::get_view_line_content(
  self : ModelLineProjection,
  model : @model.TextModel,
  model_line_number : Int,
  output_line_index : Int,
) -> String {
  match self {
    Identity => model.snapshot.line_text(model_line_number - 1)
    Hidden => abort("Not supported")
    Projected(data, ..) => {
      let segment = data.segment_at_view_line_index(output_line_index)
      let content = data.projected_line.text[segment.start_offset:segment.end_offset].to_owned()
      if segment.wrapped_text_indent_length > 0 {
        spaces(segment.wrapped_text_indent_length) + content
      } else {
        content
      }
    }
  }
}

///|
/// Minimum one-based column of one view line — `getViewLineMinColumn`
/// (`modelLineProjection.ts:141-144`): `getMinOutputOffset + 1`, i.e. the
/// continuation indent width plus one (view columns are segment-local; the
/// segment's `start_column` is a projected-line column, a different axis).
pub fn ModelLineProjection::get_view_line_min_column(
  self : ModelLineProjection,
  output_line_index : Int,
) -> Int {
  match self {
    Identity => 1
    Hidden => abort("Not supported")
    Projected(data, ..) =>
      data.segment_at_view_line_index(output_line_index).wrapped_text_indent_length +
      1
  }
}

///|
/// Maximum one-based column of one view line — `getViewLineMaxColumn`.
pub fn ModelLineProjection::get_view_line_max_column(
  self : ModelLineProjection,
  model : @model.TextModel,
  model_line_number : Int,
  output_line_index : Int,
) -> Int {
  match self {
    Identity => model.snapshot.line_text(model_line_number - 1).length() + 1
    Hidden => abort("Not supported")
    Projected(data, ..) => {
      // `getMaxOutputOffset + 1` (`modelLineProjectionData.ts:73-79`): the
      // segment's rendered length (indent included) plus one — segment-local,
      // like `get_view_line_min_column`.
      let segment = data.segment_at_view_line_index(output_line_index)
      segment.end_offset -
      segment.start_offset +
      segment.wrapped_text_indent_length +
      1
    }
  }
}

///|
/// The view-line data of one view line — `getViewLineData`. The identity arm
/// is Monaco's `IdentityModelLineProjection.getViewLineData`
/// (`modelLineProjection.ts:298`): the model line whole, tokens inflated, no
/// injected inline decorations.
pub fn ModelLineProjection::get_view_line_data(
  self : ModelLineProjection,
  model : @model.TextModel,
  model_line_number : Int,
  output_line_index : Int,
  base_view_line_number : Int,
) -> ViewLineData {
  match self {
    Identity => {
      let line_tokens = model.tokenization.get_line_tokens(model_line_number)
      let content = line_tokens.get_line_content()
      {
        content,
        continues_with_wrapped_line: false,
        min_column: 1,
        max_column: content.length() + 1,
        start_visible_column: 0,
        tokens: line_tokens.inflate(),
        inline_decorations: [],
      }
    }
    Hidden => abort("Not supported")
    Projected(_, ..) => {
      let result : Array[ViewLineData?] = [None]
      ignore(
        self.get_view_lines_data(
          model,
          model_line_number,
          output_line_index,
          1,
          base_view_line_number,
          0,
          [true],
          result,
        ),
      )
      result[0].unwrap()
    }
  }
}

///|
/// Batch form of `get_view_line_data` (`modelLineProjection.ts:160-184,
/// 312-320`). A projected model line performs exactly one passive token-store
/// read after computing its injected-text decorations, including when every
/// requested output is unneeded. Identity retains its distinct early return.
fn ModelLineProjection::get_view_lines_data(
  self : ModelLineProjection,
  model : @model.TextModel,
  model_line_number : Int,
  output_line_index : Int,
  line_count : Int,
  base_view_line_number : Int,
  global_start_index : Int,
  needed : Array[Bool],
  result : Array[ViewLineData?],
) -> Bool {
  match self {
    Identity => {
      if !needed[global_start_index] {
        result[global_start_index] = None
        return false
      }
      result[global_start_index] = Some(
        self.get_view_line_data(
          model, model_line_number, 0, base_view_line_number,
        ),
      )
      true
    }
    Hidden => abort("Not supported")
    Projected(data, is_visible~) => {
      if !is_visible {
        abort("Not supported")
      }

      // `modelLineProjection.ts:163-176`: materialize the five-callback
      // injected-decoration context and compute the per-output decorations
      // before the passive token-store read below. This ordering is observable
      // even for an all-false `needed` mask.
      let injection_offsets = injection_offsets_for_projected_line(
        data.projected_line,
      )
      let injection_options = injection_options_for_projected_line(
        data.projected_line,
      )
      let resolved_injection_options = resolve_injection_options(
        injection_options[:],
      )
      let break_offsets = data.segments.map(segment => segment.end_offset)
      let wrapped_text_indent_length = if data.segments.length() > 1 {
        data.segments[1].wrapped_text_indent_length
      } else {
        0
      }
      let context : InjectedTextInlineDecorationsComputerContext = {
        get_injection_options: _ => {
          if resolved_injection_options.length() == 0 {
            None
          } else {
            Some(resolved_injection_options)
          }
        },
        get_injection_offsets: _ => {
          if injection_offsets.length() == 0 {
            None
          } else {
            Some(injection_offsets)
          }
        },
        get_break_offsets: _ => break_offsets,
        get_wrapped_text_indent_length: _ => wrapped_text_indent_length,
        get_base_view_line_number: _ => base_view_line_number,
      }
      let prepared = prepare_projected_line_demand(
        context,
        model_line_number,
        injection_options,
        injection_offsets,
        () => model.tokenization.get_line_tokens(model_line_number),
      )
      let line_inline_decorations = prepared.line_inline_decorations
      let with_injections = prepared.line_with_injections
      for local_index in 0..<line_count {
        let global_index = global_start_index + local_index
        if !needed[global_index] {
          result[global_index] = None
          continue
        }
        let requested_output_line_index = output_line_index + local_index
        let inline_decorations = if line_inline_decorations.length() > 0 {
          Some(line_inline_decorations[requested_output_line_index])
        } else {
          None
        }
        result[global_index] = Some(
          view_line_data_for_segment_with_injections(
            with_injections,
            data.segment_at_view_line_index(requested_output_line_index),
            inline_decorations,
          ),
        )
      }
      true
    }
  }
}

///|
/// Model column for a view position on one view line —
/// `getModelColumnOfViewPosition` (`translateToInputOffset`, which undoes the
/// continuation indent and clamps into the segment).
pub fn ModelLineProjection::get_model_column_of_view_position(
  self : ModelLineProjection,
  output_line_index : Int,
  output_column : Int,
) -> Int {
  match self {
    Identity => output_column
    Hidden => abort("Not supported")
    Projected(data, ..) => {
      let segment = data.segment_at_view_line_index(output_line_index)
      let width = segment.end_offset - segment.start_offset
      let projected_column = segment.start_offset +
        (output_column - 1 - segment.wrapped_text_indent_length).clamp(
          min=0,
          max=width,
        )
      data.projected_line.projected_column_to_model_column(projected_column) + 1
    }
  }
}

///|
/// View position of a model column — `getViewPositionOfModelPosition`
/// (`translateToOutputPosition(inputColumn - 1, affinity).toPosition(delta)`).
/// `delta_line_number` is the model line's first view line, so a continuation
/// segment adds its index; the view column regains the continuation indent
/// (Monaco's `getOutputPositionOfInputOffset`).
pub fn ModelLineProjection::get_view_position_of_model_position(
  self : ModelLineProjection,
  delta_line_number : Int,
  input_column : Int,
  affinity? : @model.PositionAffinity,
) -> @base_common.Position {
  match self {
    Identity => {
      ignore(affinity)
      Position(delta_line_number, input_column)
    }
    Hidden => abort("Not supported")
    Projected(data, ..) => {
      let model_column = (input_column - 1).clamp(min=0, max=data.line_length)
      let projected_column = data.projected_line.model_column_to_projected_column(
        model_column,
        affinity?,
      )
      let segment_index = data.view_line_index_for_projected_column(
        projected_column,
        affinity?,
      )
      let segment = data.segment_at_view_line_index(segment_index)
      Position(
        delta_line_number + segment_index,
        projected_column -
        segment.start_offset +
        1 +
        segment.wrapped_text_indent_length,
      )
    }
  }
}

///|
/// Snaps a view position at an injected-text or wrap boundary to the side the
/// affinity asks for — `normalizePosition` (`modelLineProjection.ts:237-241`)
/// over `normalizeOutputPosition` (`modelLineProjectionData.ts:169-192`).
pub fn ModelLineProjection::normalize_position(
  self : ModelLineProjection,
  output_line_index : Int,
  position : @base_common.Position,
  affinity : @model.PositionAffinity,
) -> @base_common.Position {
  match self {
    Identity => position
    Hidden => abort("Not supported")
    Projected(data, ..) => {
      let segment = data.segment_at_view_line_index(output_line_index)
      let width = segment.end_offset - segment.start_offset
      // `outputPositionToOffsetInInputWithInjections`: undo the continuation
      // indent and clamp into the segment.
      let output_offset = (position.column -
      1 -
      segment.wrapped_text_indent_length).clamp(min=0, max=width)
      let projected = segment.start_offset + output_offset
      let normalized = data.projected_line.normalize_projected_column_around_injections(
        projected, affinity,
      )
      if normalized != projected {
        // Injected text caused a change: re-derive the view position with the
        // same affinity, relative to this model line's first view line.
        let base_view_line_number = position.line_number - output_line_index
        let segment_index = data.view_line_index_for_projected_column(
          normalized,
          affinity~,
        )
        let target = data.segment_at_view_line_index(segment_index)
        return Position(
          base_view_line_number + segment_index,
          normalized -
          target.start_offset +
          1 +
          target.wrapped_text_indent_length,
        )
      }
      // Wrap-boundary snap: `Left` at the line's min output offset moves to
      // the previous view line's max; `Right` at max moves to the next line's
      // min.
      match affinity {
        Left =>
          if output_line_index > 0 && output_offset == 0 {
            let previous = data.segment_at_view_line_index(
              output_line_index - 1,
            )
            Position(
              position.line_number - 1,
              previous.end_offset -
              previous.start_offset +
              1 +
              previous.wrapped_text_indent_length,
            )
          } else {
            position
          }
        Right =>
          if output_line_index + 1 < data.view_line_count() &&
            output_offset == width {
            Position(
              position.line_number + 1,
              1 +
              data.segment_at_view_line_index(output_line_index + 1).wrapped_text_indent_length,
            )
          } else {
            position
          }
        _ => position
      }
    }
  }
}

///|
/// The injected-text source index at a 0-based view column of
/// one view line, or `-1` for source text (including the synthetic
/// continuation indent) — the index-valued form of Monaco's
/// `getInjectedTextAt`.
pub fn ModelLineProjection::injected_text_index_at(
  self : ModelLineProjection,
  output_line_index : Int,
  column : Int,
) -> Int {
  match self {
    Identity => -1
    Hidden => abort("Not supported")
    Projected(data, ..) => {
      let segment = data.segment_at_view_line_index(output_line_index)
      let indent = segment.wrapped_text_indent_length
      if column < indent {
        return -1
      }
      let offset = segment.start_offset + (column - indent)
      if offset >= segment.end_offset {
        return -1
      }
      data.projected_line.injected_text_index_at_projected_column(offset)
    }
  }
}

///|
/// Builds one segment after the batch caller has shared the model line's
/// passive token read, injection splice, and source-shaped decoration
/// computation. The source decoration ranges carry absolute view-line numbers;
/// this local renderer adapter converts the selected line to zero-based offsets.
fn view_line_data_for_segment_with_injections(
  with_injections : @tokens.LineTokens,
  segment : ModelLineProjectionSegment,
  inline_decorations : Array[InlineDecoration]?,
) -> ViewLineData {
  let indent = segment.wrapped_text_indent_length
  let start_offset = segment.start_offset
  let end_offset = segment.end_offset
  let tokens = with_injections.slice_and_inflate(
    start_offset, end_offset, indent,
  )
  let content = tokens.get_line_content()
  let content = if indent > 0 { spaces(indent) + content } else { content }
  let inline_decorations = match inline_decorations {
    Some(decorations) =>
      decorations.map(decoration => {
        @view_layout.InlineDecoration(
          OffsetRange(
            decoration.range.start_column - 1,
            decoration.range.end_column - 1,
          ),
          decoration.inline_class_name,
        )
      })
    None => []
  }
  {
    content,
    continues_with_wrapped_line: segment.continues_with_wrapped_line,
    // Segment-local view columns (`getViewLineMinColumn`/`MaxColumn`): the
    // indent-prefixed rendered content's bounds.
    min_column: segment.wrapped_text_indent_length + 1,
    max_column: content.length() + 1,
    // The renderer's whitespace math counts code units in Int columns;
    // Monaco feeds the raw (possibly fractional) number into the same
    // formulas. Truncation only diverges when `columnsForFullWidthChar` is
    // fractional, and only for whitespace glyph tab stops.
    start_visible_column: segment.start_visible_column.to_int(),
    tokens,
    inline_decorations,
  }
}

///|
/// A run of `n` spaces — the leading indent prepended to a wrapped continuation
/// line. Monaco's `spaces(count)`.
fn spaces(n : Int) -> String {
  " ".repeat(n)
}

///|
/// Source-shaped injection options captured by the batch context.
fn injection_options_for_projected_line(
  projected_line : ProjectedTextLine,
) -> Array[@model.InjectedTextOptions] {
  projected_line.parts.filter_map(part => {
    match part.kind {
      InjectedSegment(class_name~, ..) =>
        Some(
          InjectedTextOptions(
            projected_line.text[part.start:part.end].to_owned(),
            inline_class_name?=if class_name == "" {
              None
            } else {
              Some(class_name)
            },
          ),
        )
      SourceSegment(_) => None
    }
  })
}

///|
/// Resolves the canonical model injection options consumed by the projection
/// into the complete source fields used by the decoration computer.
fn resolve_injection_options(
  options : ArrayView[@model.InjectedTextOptions],
) -> Array[ResolvedInjectedTextOptions] {
  options.map(option => {
    ResolvedInjectedTextOptions(
      content=option.content(),
      inline_class_name?=option.inline_class_name(),
      // DEFERRED: the canonical model option has no
      // inlineClassNameAffectsLetterSpacing field.
      inline_class_name_affects_letter_spacing=false,
    )
  })
}

///|
/// Source-shaped injection offsets captured by the batch context.
fn injection_offsets_for_projected_line(
  projected_line : ProjectedTextLine,
) -> Array[Int] {
  projected_line.parts.filter_map(part => {
    match part.kind {
      InjectedSegment(model_column~, ..) => Some(model_column)
      SourceSegment(_) => None
    }
  })
}

///|
/// Monaco's five-callback `IInjectedTextInlineDecorationsComputerContext`.
/// Keeping this literal callback shape makes ordering and the
/// `baseViewLineNumber` value directly executable in white-box tests.
priv struct ResolvedInjectedTextOptions {
  content : String
  inline_class_name : String?
  inline_class_name_affects_letter_spacing : Bool
}

///|
fn ResolvedInjectedTextOptions::ResolvedInjectedTextOptions(
  content~ : String,
  inline_class_name? : String,
  inline_class_name_affects_letter_spacing? : Bool = false,
) -> ResolvedInjectedTextOptions {
  { content, inline_class_name, inline_class_name_affects_letter_spacing, }
}

///|
priv struct InjectedTextInlineDecorationsComputerContext {
  get_injection_options : (Int) -> Array[ResolvedInjectedTextOptions]?
  get_injection_offsets : (Int) -> Array[Int]?
  get_break_offsets : (Int) -> Array[Int]
  get_wrapped_text_indent_length : (Int) -> Int
  get_base_view_line_number : (Int) -> Int
}

///|
/// Monaco's `InjectedTextInlineDecorationsComputer` retained at the exact
/// projection seam rather than precomputing decorations while constructing the
/// projected line.
priv struct InjectedTextInlineDecorationsComputer {
  context : InjectedTextInlineDecorationsComputerContext
}

///|
fn InjectedTextInlineDecorationsComputer::InjectedTextInlineDecorationsComputer(
  context : InjectedTextInlineDecorationsComputerContext,
) -> InjectedTextInlineDecorationsComputer {
  { context, }
}

///|
/// `inlineDecorations.ts:213-267`, including callback order, wrapped clipping,
/// continuation indent, and absolute view-line ranges.
fn InjectedTextInlineDecorationsComputer::get_inline_decorations(
  self : InjectedTextInlineDecorationsComputer,
  model_line_number : Int,
) -> Array[Array[InlineDecoration]] {
  let injection_offsets = (self.context.get_injection_offsets)(
    model_line_number,
  )
  guard injection_offsets is Some(injection_offsets) else { [] }
  let line_inline_decorations : Array[Array[InlineDecoration]] = []
  let mut total_injected_text_length_before = 0
  let mut current_injected_offset = 0
  let injection_options = (self.context.get_injection_options)(
    model_line_number,
  )
  let break_offsets = (self.context.get_break_offsets)(model_line_number)
  for output_line_index in 0..<break_offsets.length() {
    let inline_decorations : Array[InlineDecoration] = []
    line_inline_decorations.push(inline_decorations)
    let line_start_offset_in_input_with_injections = if output_line_index > 0 {
      break_offsets[output_line_index - 1]
    } else {
      0
    }
    let line_end_offset_in_input_with_injections = break_offsets[output_line_index]
    while current_injected_offset < injection_offsets.length() {
      let options = injection_options.unwrap()[current_injected_offset]
      let length = options.content.length()
      let injected_text_start_offset_in_input_with_injections = injection_offsets[current_injected_offset] +
        total_injected_text_length_before
      let injected_text_end_offset_in_input_with_injections = injected_text_start_offset_in_input_with_injections +
        length
      if injected_text_start_offset_in_input_with_injections >
        line_end_offset_in_input_with_injections {
        break
      }
      if line_start_offset_in_input_with_injections <
        injected_text_end_offset_in_input_with_injections {
        if options.inline_class_name is Some(inline_class_name) {
          let wrapped_text_indent_length = (self.context.get_wrapped_text_indent_length)(
            model_line_number,
          )
          let offset = if output_line_index > 0 {
            wrapped_text_indent_length
          } else {
            0
          }
          let start = offset +
            (injected_text_start_offset_in_input_with_injections -
            line_start_offset_in_input_with_injections).max(0)
          let end = offset +
            (injected_text_end_offset_in_input_with_injections -
            line_start_offset_in_input_with_injections).min(
              line_end_offset_in_input_with_injections -
              line_start_offset_in_input_with_injections,
            )
          if start != end {
            let view_line_number = (self.context.get_base_view_line_number)(
                model_line_number,
              ) +
              output_line_index
            inline_decorations.push(
              InlineDecoration(
                Range(view_line_number, start + 1, view_line_number, end + 1),
                inline_class_name,
                if options.inline_class_name_affects_letter_spacing {
                  RegularAffectingLetterSpacing
                } else {
                  Regular
                },
              ),
            )
          }
        }
      }
      if injected_text_end_offset_in_input_with_injections <=
        line_end_offset_in_input_with_injections {
        total_injected_text_length_before += length
        current_injected_offset += 1
      } else {
        break
      }
    }
  }
  line_inline_decorations
}

///|
/// The exact ordered source seam at `modelLineProjection.ts:175-178`:
/// construct/use the decoration computer, then passively read the model-line
/// tokens, then splice injections into that one shared value. Keeping the token
/// read as the `ISimpleModel.tokenization` dependency closure gives white-box
/// tests executable ordering evidence without widening the package API.
priv struct PreparedProjectedLineDemand {
  line_inline_decorations : Array[Array[InlineDecoration]]
  line_with_injections : @tokens.LineTokens
}

///|
fn prepare_projected_line_demand(
  context : InjectedTextInlineDecorationsComputerContext,
  model_line_number : Int,
  injection_options : Array[@model.InjectedTextOptions],
  injection_offsets : Array[Int],
  read_line_tokens : () -> @tokens.LineTokens,
) -> PreparedProjectedLineDemand {
  let computer = InjectedTextInlineDecorationsComputer::InjectedTextInlineDecorationsComputer(
    context,
  )
  let line_inline_decorations = computer.get_inline_decorations(
    model_line_number,
  )
  let line_tokens = read_line_tokens()
  let line_with_injections = line_tokens.with_inserted(
    inserted_tokens_from_injection_data(injection_options, injection_offsets),
  )
  { line_inline_decorations, line_with_injections, }
}

///|
/// Monaco's `getLineTokensWithInjections` adapter over the same options and
/// offsets read by the decoration context.
fn inserted_tokens_from_injection_data(
  injection_options : Array[@model.InjectedTextOptions],
  injection_offsets : Array[Int],
) -> Array[@tokens.InsertedToken] {
  let inserts : Array[@tokens.InsertedToken] = []
  for index, options in injection_options {
    inserts.push(
      InsertedToken(
        injection_offsets[index],
        options.content(),
        @tokens.LineTokens::default_token_metadata(),
      ),
    )
  }
  inserts
}

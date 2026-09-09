// 1:1 port of Monaco's `viewModel/viewModelDecorations.ts` (whole file) plus
// the `viewModelLines.ts:923` `getDecorationsInRange` slice its context
// closure delegates to, from checked-in vscode submodule (decoration plan Phase 3 — this
// replaces the previous simplified eager-conversion `ViewModelDecorations`).
//
// Deviations:
// - The editor configuration reads (`filterValidationDecorations(options)`,
//   `filterFontDecorations(options)`) are resolved once at construction: the
//   view model rotates its decoration provider when those options change
//   (`ViewModel::on_configuration_changed`), so the per-call read has no
//   observable difference. Font decorations are out of scope, so that filter
//   is constantly `false`.
// - `getMinimapDecorationsInRange` is DEFERRED with the minimap view part
//   (plan out-of-scope list); `onlyMinimapDecorations` is carried through the
//   context signature (it only forwards to the out-of-scope bracket provider
//   in the source).
// - `dispose` is folded into `reset` (no dispose lifecycle in the readonly
//   view model; both bodies are identical in the source).

///|
/// `filterValidationDecorations` (`editorOptions.ts`): `editable` defers to
/// `readOnly`, which is constantly `true` for this viewer.
pub fn filter_validation_decorations(
  option : @editor_api.RenderValidationDecorations,
) -> Bool {
  match option {
    Editable => true // editable → readOnly; the viewer is always readonly
    On => false
    Off => true
  }
}

///|
/// `ViewModelDecorations` (`viewModelDecorations.ts:16`): the lazy,
/// viewport-cached decoration provider for one view model.
struct ViewModelDecorations {
  computer : InlineModelDecorationsComputer
  mut cached_model_decorations_resolver : ViewDecorationsCollection?
  mut cached_model_decorations_resolver_view_range : @base_common.Range?
}

///|
/// Constructor (`viewModelDecorations.ts:27-37`): the context closure hands
/// the computer model decorations for a view range via the lines collection.
fn ViewModelDecorations::ViewModelDecorations(
  editor_id : Int,
  model : @model.TextModel,
  filter_validation : Bool,
  lines : ViewModelLinesFromProjectedModel,
  coordinates_converter : CoordinatesConverter,
) -> ViewModelDecorations {
  let context : InlineModelContext = {
    get_model_decorations: (
      view_range,
      only_minimap_decorations,
      only_margin_decorations,
    ) => {
      view_model_lines_get_decorations_in_range(
        lines, model, coordinates_converter, view_range, editor_id, filter_validation,
        only_minimap_decorations, only_margin_decorations,
      )
    },
  }
  {
    computer: InlineModelDecorationsComputer(
      context, model, coordinates_converter,
    ),
    cached_model_decorations_resolver: None,
    cached_model_decorations_resolver_view_range: None,
  }
}

///|
/// `_clearCachedModelDecorationsResolver` (`viewModelDecorations.ts:39-42`).
fn ViewModelDecorations::clear_cached_model_decorations_resolver(
  self : ViewModelDecorations,
) -> Unit {
  self.cached_model_decorations_resolver = None
  self.cached_model_decorations_resolver_view_range = None
}

///|
/// `reset` (`viewModelDecorations.ts:49-52`; `dispose` has the same body).
fn ViewModelDecorations::reset(self : ViewModelDecorations) -> Unit {
  self.computer.reset()
  self.clear_cached_model_decorations_resolver()
}

///|
/// `onModelDecorationsChanged` (`viewModelDecorations.ts:54-57`).
pub fn ViewModelDecorations::on_model_decorations_changed(
  self : ViewModelDecorations,
) -> Unit {
  self.computer.on_model_decorations_changed()
  self.clear_cached_model_decorations_resolver()
}

///|
/// `onLineMappingChanged` (`viewModelDecorations.ts:59-63`).
fn ViewModelDecorations::on_line_mapping_changed(
  self : ViewModelDecorations,
) -> Unit {
  self.computer.on_line_mapping_changed()
  self.clear_cached_model_decorations_resolver()
}

///|
/// `getDecorationsViewportData` (`viewModelDecorations.ts:69-77`): one-entry
/// cache keyed by the exact view range.
pub fn ViewModelDecorations::get_decorations_viewport_data(
  self : ViewModelDecorations,
  view_range : @base_common.Range,
) -> ViewDecorationsCollection {
  let mut cache_is_valid = self.cached_model_decorations_resolver is Some(_)
  cache_is_valid = cache_is_valid &&
    self.cached_model_decorations_resolver_view_range is Some(cached_range) &&
    cached_range == view_range
  if !cache_is_valid {
    self.cached_model_decorations_resolver = Some(
      self.compute_decorations(view_range),
    )
    self.cached_model_decorations_resolver_view_range = Some(view_range)
  }
  self.cached_model_decorations_resolver.unwrap()
}

///|
fn ViewModelDecorations::compute_decorations(
  self : ViewModelDecorations,
  view_range : @base_common.Range,
) -> ViewDecorationsCollection {
  self.computer.get_decorations(view_range, false, false)
}

///|
/// `getDecorationsInRange` (`viewModelLines.ts:923-975`): view-range query
/// against the model with hidden-line splitting. The fast path
/// covers the no-hidden-lines case; otherwise visible model-line runs are
/// fetched separately, sorted, and deduplicated. Like the source, the
/// split-path requests drop the `onlyMarginDecorations` argument.
fn view_model_lines_get_decorations_in_range(
  lines : ViewModelLinesFromProjectedModel,
  model : @model.TextModel,
  converter : CoordinatesConverter,
  range : @base_common.Range,
  owner_id : Int,
  filter_out_validation : Bool,
  only_minimap_decorations : Bool,
  only_margin_decorations : Bool,
) -> Array[@model.ModelDecoration] {
  // onlyMinimapDecorations only forwards to the out-of-scope bracket
  // provider in the source's model.getDecorationsInRange.
  ignore(only_minimap_decorations)
  let model_start = converter.view_position_to_model_position(
    Position(range.start_line_number, range.start_column),
  )
  let model_end = converter.view_position_to_model_position(
    Position(range.end_line_number, range.end_column),
  )
  if model_end.line_number - model_start.line_number <=
    range.end_line_number - range.start_line_number {
    // most likely there are no hidden lines => fast path
    // fetch decorations from column 1 to cover the case of wrapped lines that
    // have whole line decorations at column 1
    return model.get_decorations_in_range(
      Range(model_start.line_number, 1, model_end.line_number, model_end.column),
      owner_id~,
      filter_out_validation~,
      only_margin_decorations~,
    )
  }
  let result : Array[@model.ModelDecoration] = []
  let model_start_line_index = model_start.line_number - 1
  let model_end_line_index = model_end.line_number - 1
  let mut req_start : @base_common.Position? = None
  for model_line_index in model_start_line_index..<=model_end_line_index {
    if lines.model_position_is_visible(model_line_index + 1) {
      // merge into previous request
      if req_start is None {
        req_start = Some(
          Position(
            model_line_index + 1,
            if model_line_index == model_start_line_index {
              model_start.column
            } else {
              1
            },
          ),
        )
      }
    } else if req_start is Some(start) {
      // hit invisible line => flush request
      let max_line_column = model.snapshot.get_line_max_column(model_line_index)
      result.append(
        model.get_decorations_in_range(
          Range(
            start.line_number,
            start.column,
            model_line_index,
            max_line_column,
          ),
          owner_id~,
          filter_out_validation~,
        ),
      )
      req_start = None
    }
  }
  if req_start is Some(start) {
    result.append(
      model.get_decorations_in_range(
        Range(
          start.line_number,
          start.column,
          model_end.line_number,
          model_end.column,
        ),
        owner_id~,
        filter_out_validation~,
      ),
    )
    req_start = None
  }
  result.sort_by((a, b) => {
    let res = @base_common.Range::compare_ranges_using_starts(a.range, b.range)
    if res == 0 {
      // JS `<` on decoration ids; ids share one `<instance>;` prefix, where
      // MoonBit's length-first compare and JS lexicographic order agree for
      // the numeric suffixes only when lengths match — compare code units.
      @base_common.compare(a.id, b.id)
    } else {
      res
    }
  })

  // Eliminate duplicate decorations that might have intersected our visible
  // ranges multiple times
  let final_result : Array[@model.ModelDecoration] = []
  for dec in result; last_dec_id = "" {
    let dec_id = dec.id
    if last_dec_id == dec_id {
      continue
    }
    final_result.push(dec)
    continue dec_id
  }
  final_result
}

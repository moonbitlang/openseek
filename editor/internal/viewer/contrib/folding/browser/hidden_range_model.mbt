// Port of `vscode/src/vs/editor/contrib/folding/browser/hiddenRangeModel.ts`
// (checked-in vscode submodule): derives
// the hidden line ranges from the folding model's collapsed regions and
// fires them at the consumer (the controller applies them via
// `editor.setHiddenAreas`).
//
// Omission: `notifyChangeModelContent`/`_hasLineChanges` (a re-derive
// trigger for edits that add or remove lines) — the viewer's `TextModel` is
// readonly.

///|
/// Monaco's `HiddenRangeModel` (`hiddenRangeModel.ts:16`).
struct HiddenRangeModel {
  folding_model : FoldingModel
  mut hidden_ranges : Array[@base_common.Range]
  mut folding_model_listener : @base_common.Disposable?
  update_event_emitter : @base_common.Emitter[Array[@base_common.Range]]
}

///|
/// The constructor (`hiddenRangeModel.ts:27`): subscribes to the folding
/// model and derives the initial set.
pub fn HiddenRangeModel::HiddenRangeModel(
  model : FoldingModel,
) -> HiddenRangeModel {
  let hidden_range_model = {
    folding_model: model,
    hidden_ranges: [],
    folding_model_listener: None,
    update_event_emitter: Emitter(),
  }
  hidden_range_model.folding_model_listener = Some(
    model.on_did_change(_ => hidden_range_model.update_hidden_ranges()),
  )
  if model.regions().length() > 0 {
    hidden_range_model.update_hidden_ranges()
  }
  hidden_range_model
}

///|
/// `onDidChange` subscription: fires the new hidden ranges.
pub fn HiddenRangeModel::on_did_change(
  self : HiddenRangeModel,
  listener : (Array[@base_common.Range]) -> Unit,
) -> @base_common.Disposable {
  self.update_event_emitter.event(listener)
}

///|
/// `updateHiddenRanges` (`hiddenRangeModel.ts:44`): one hidden range per
/// outermost collapsed region (the header line stays visible), reusing the
/// previous array entries when unchanged so no event fires for no change.
fn HiddenRangeModel::update_hidden_ranges(self : HiddenRangeModel) -> Unit {
  let mut update_hidden_areas = false
  let new_hidden_areas : Array[@base_common.Range] = []
  let mut k = 0
  let mut last_collapsed_start = 0x7FFFFFFF
  let mut last_collapsed_end = -1
  let ranges = self.folding_model.regions()
  for i in 0..<ranges.length() {
    if !ranges.is_collapsed(i) {
      continue
    }
    // the first line is not hidden
    let start_line_number = ranges.get_start_line_number(i) + 1
    let end_line_number = ranges.get_end_line_number(i)
    if last_collapsed_start <= start_line_number &&
      end_line_number <= last_collapsed_end {
      // ignore ranges contained in collapsed regions
      continue
    }
    if !update_hidden_areas &&
      k < self.hidden_ranges.length() &&
      self.hidden_ranges[k].start_line_number == start_line_number &&
      self.hidden_ranges[k].end_line_number == end_line_number {
      // reuse the old ranges
      new_hidden_areas.push(self.hidden_ranges[k])
      k += 1
    } else {
      update_hidden_areas = true
      new_hidden_areas.push(Range(start_line_number, 1, end_line_number, 1))
    }
    last_collapsed_start = start_line_number
    last_collapsed_end = end_line_number
  }
  if update_hidden_areas || k < self.hidden_ranges.length() {
    self.apply_hidden_ranges(new_hidden_areas)
  }
}

///|
/// `applyHiddenRanges` (`hiddenRangeModel.ts:82`).
fn HiddenRangeModel::apply_hidden_ranges(
  self : HiddenRangeModel,
  new_hidden_areas : Array[@base_common.Range],
) -> Unit {
  self.hidden_ranges = new_hidden_areas
  self.update_event_emitter.fire(new_hidden_areas)
}

///|
/// `hasRanges` (`hiddenRangeModel.ts:88`).
pub fn HiddenRangeModel::has_ranges(self : HiddenRangeModel) -> Bool {
  self.hidden_ranges.length() > 0
}

///|
/// `isHidden` (`hiddenRangeModel.ts:92`).
pub fn HiddenRangeModel::is_hidden(
  self : HiddenRangeModel,
  line : Int32,
) -> Bool {
  find_hidden_range(self.hidden_ranges, line) is Some(_)
}

///|
/// `adjustSelections` (`hiddenRangeModel.ts:96`): moves selection endpoints
/// that landed inside a hidden range up to the fold's (visible) header
/// line, in place. Returns whether anything moved.
pub fn HiddenRangeModel::adjust_selections(
  self : HiddenRangeModel,
  selections : Array[@core.Selection],
) -> Bool {
  let mut has_changes = false
  let editor_model = self.folding_model.text_model()
  let mut last_range : @base_common.Range? = None
  let adjust_line = (line : Int32) => {
    if !(last_range is Some(range) && is_inside_hidden_range(line, range)) {
      last_range = find_hidden_range(self.hidden_ranges, line)
    }
    match last_range {
      Some(range) => Some(range.start_line_number - 1)
      None => None
    }
  }
  for i in 0..<selections.length() {
    let mut selection = selections[i]
    match adjust_line(selection.start().line_number) {
      Some(adjusted_start_line) => {
        selection = selection.set_start_position(
          adjusted_start_line,
          editor_model.snapshot.get_line_max_column(adjusted_start_line),
        )
        has_changes = true
      }
      None => ()
    }
    match adjust_line(selection.end().line_number) {
      Some(adjusted_end_line) => {
        selection = selection.set_end_position(
          adjusted_end_line,
          editor_model.snapshot.get_line_max_column(adjusted_end_line),
        )
        has_changes = true
      }
      None => ()
    }
    selections[i] = selection
  }
  has_changes
}

///|
/// `dispose` (`hiddenRangeModel.ts:128`).
fn HiddenRangeModel::dispose(self : HiddenRangeModel) -> Unit {
  if self.hidden_ranges.length() > 0 {
    self.hidden_ranges = []
    self.update_event_emitter.fire(self.hidden_ranges)
  }
  match self.folding_model_listener {
    Some(listener) => {
      listener.dispose()
      self.folding_model_listener = None
    }
    None => ()
  }
}

///|
/// `isInside` (`hiddenRangeModel.ts:141`).
fn is_inside_hidden_range(line : Int32, range : @base_common.Range) -> Bool {
  line >= range.start_line_number && line <= range.end_line_number
}

///|
/// `findRange` (`hiddenRangeModel.ts:144`): the hidden range containing
/// `line`, by binary search (`findFirstIdxMonotonousOrArrLen`).
fn find_hidden_range(
  ranges : Array[@base_common.Range],
  line : Int32,
) -> @base_common.Range? {
  // first index whose range starts after `line`
  let (low, _high) = for low = 0, high = ranges.length(); low < high; {
    let mid = (low + high) / 2
    if line < ranges[mid].start_line_number {
      continue low, mid
    } else {
      continue mid + 1, high
    }
  } nobreak {
    (low, high)
  }
  let i = low - 1
  if i >= 0 && ranges[i].end_line_number >= line {
    return Some(ranges[i])
  }
  None
}

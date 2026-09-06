// Port of `vscode/src/vs/editor/contrib/folding/browser/foldingModel.ts`
// (checked-in vscode submodule): the
// `FoldingModel` (regions + their tracking editor decorations + the change
// emitter) and the reachable collapse-state helpers the commands drive.
//
// The persistence slice (`getMemento`/`applyMemento`/`_getLinesChecksum`) is
// retained because readonly hosts replace or flush models when disk contents
// change and must restore the user's fold choices afterward.

///|
/// One persisted fold range — Monaco's private `ILineMemento`
/// (`foldingModel.ts:21`). Optional fields retain the source's compatibility
/// defaults even though states produced by this version fill all three.
priv struct FoldingLineMemento {
  start_line_number : Int
  end_line_number : Int
  checksum : Int?
  is_collapsed : Bool?
  source : FoldSource?
} derive(Debug)

///|
/// The exact decoration capabilities `FoldingModel` writes through — Monaco's
/// structural `IDecorationProvider` (`foldingModel.ts:13`). This is a closed
/// function record instead of a MoonBit trait object: the source boundary is
/// three callbacks, not a runtime-subtyped object hierarchy.
struct FoldingDecorationAccess {
  get_decoration_option_ : (Bool, Bool, Bool, Bool) -> @model.ModelDecorationOptions
  change_decorations_ : ((@model.ModelDecorationsChangeAccessor) -> Unit) -> Unit
  remove_decorations_ : (Array[String]) -> Unit
}

///|
fn FoldingDecorationAccess::FoldingDecorationAccess(
  get_decoration_option : (Bool, Bool, Bool, Bool) -> @model.ModelDecorationOptions,
  change_decorations : ((@model.ModelDecorationsChangeAccessor) -> Unit) -> Unit,
  remove_decorations : (Array[String]) -> Unit,
) -> FoldingDecorationAccess {
  {
    get_decoration_option_: get_decoration_option,
    change_decorations_: change_decorations,
    remove_decorations_: remove_decorations,
  }
}

///|
fn FoldingDecorationAccess::get_decoration_option(
  self : FoldingDecorationAccess,
  is_collapsed : Bool,
  is_hidden : Bool,
  is_manual : Bool,
  is_outline_body : Bool,
) -> @model.ModelDecorationOptions {
  (self.get_decoration_option_)(
    is_collapsed, is_hidden, is_manual, is_outline_body,
  )
}

///|
fn FoldingDecorationAccess::change_decorations(
  self : FoldingDecorationAccess,
  callback : (@model.ModelDecorationsChangeAccessor) -> Unit,
) -> Unit {
  (self.change_decorations_)(callback)
}

///|
fn FoldingDecorationAccess::remove_decorations(
  self : FoldingDecorationAccess,
  decoration_ids : Array[String],
) -> Unit {
  (self.remove_decorations_)(decoration_ids)
}

///|
/// The folding state of one text model — Monaco's `FoldingModel`
/// (`foldingModel.ts:32`): the current `FoldingRegions` plus one editor
/// decoration per region. The decorations both render the fold UI (chevron,
/// highlight, `⋯`) and anchor the regions across edits.
struct FoldingModel {
  text_model : @model.TextModel
  decoration_access : FoldingDecorationAccess
  mut regions : FoldingRegions
  mut editor_decoration_ids : Array[String]
  update_event_emitter : @base_common.Emitter[Unit]
}

///|
pub fn FoldingModel::FoldingModel(
  text_model : @model.TextModel,
  decoration_access : FoldingDecorationAccess,
) -> FoldingModel {
  {
    text_model,
    decoration_access,
    regions: FoldingRegions(FixedArray::make(0, 0U), FixedArray::make(0, 0U)),
    editor_decoration_ids: [],
    update_event_emitter: Emitter(),
  }
}

///|
/// The `regions` getter.
pub fn FoldingModel::regions(self : FoldingModel) -> FoldingRegions {
  self.regions
}

///|
/// The `textModel` getter.
pub fn FoldingModel::text_model(self : FoldingModel) -> @model.TextModel {
  self.text_model
}

///|
/// `onDidChange` subscription.
fn FoldingModel::on_did_change(
  self : FoldingModel,
  listener : (Unit) -> Unit,
) -> @base_common.Disposable {
  self.update_event_emitter.event(listener)
}

///|
/// `toggleCollapseState` (`foldingModel.ts:53`): flips each region's
/// collapse bit and rewrites the decoration options of every region whose
/// rendering that dirties (regions nested under a new fold become hidden,
/// under an unfold visible again).
pub fn FoldingModel::toggle_collapse_state(
  self : FoldingModel,
  toggled_regions : Array[FoldingRegion],
) -> Unit {
  if toggled_regions.length() == 0 {
    return
  }
  let toggled_regions = toggled_regions.copy()
  toggled_regions.sort_by((r1, r2) => r1.region_index() - r2.region_index())
  let processed : Map[String, Bool] = Map([])
  self.decoration_access.change_decorations(accessor => {
    // index from [0 ... this.regions.length]
    let k : Ref[Int] = { val: 0, }
    // end of the range where decorations need to be updated
    let dirty_region_end_line : Ref[Int] = { val: -1, }
    // the end of the last hidden lines
    let last_hidden_line : Ref[Int] = { val: -1, }
    let update_decorations_until = (index : Int) => {
      while k.val < index {
        let end_line_number = self.regions.get_end_line_number(k.val)
        let is_collapsed = self.regions.is_collapsed(k.val)
        if end_line_number <= dirty_region_end_line.val {
          let is_manual = self.regions.get_source(k.val) != Provider
          (accessor.change_decoration_options)(
            self.editor_decoration_ids[k.val],
            self.decoration_access.get_decoration_option(
              is_collapsed,
              end_line_number <= last_hidden_line.val,
              is_manual,
              self.regions.get_type(k.val) ==
              Some(OUTLINE_BODY_FOLDING_RANGE_TYPE),
            ),
          )
        }
        if is_collapsed && end_line_number > last_hidden_line.val {
          last_hidden_line.val = end_line_number
        }
        k.val += 1
      }
    }
    for region in toggled_regions {
      let index = region.region_index()
      if index < self.editor_decoration_ids.length() {
        let editor_decoration_id = self.editor_decoration_ids[index]
        if !(processed.get(editor_decoration_id) is Some(true)) {
          processed[editor_decoration_id] = true
          // update all decorations up to current index using the old
          // dirtyRegionEndLine
          update_decorations_until(index)
          let new_collapse_state = !self.regions.is_collapsed(index)
          self.regions.set_collapsed(index, new_collapse_state)
          dirty_region_end_line.val = dirty_region_end_line.val.max(
            self.regions.get_end_line_number(index),
          )
        }
      }
    }
    update_decorations_until(self.regions.length())
  })
  self.update_event_emitter.fire(())
}

///|
/// `update` (`foldingModel.ts:116`): reconciles freshly computed provider
/// regions with the currently folded/manual ranges.
pub fn FoldingModel::update(
  self : FoldingModel,
  new_regions : FoldingRegions,
  selection? : SelectedLines,
) -> Unit {
  let folded_or_manual_ranges = self.current_folded_or_manual_ranges(selection?)
  let new_ranges = FoldingRegions::sanitize_and_merge(
    Regions(new_regions),
    Ranges(folded_or_manual_ranges),
    Some(self.text_model.snapshot.line_count()),
    selection?,
  )
  self.update_post(FoldingRegions::from_fold_ranges(new_ranges))
}

///|
/// `updatePost` (`foldingModel.ts:122`): adopts the new regions and rewrites
/// every region's tracking decoration. The decoration spans the fold —
/// header line's last column through the end line — so edits move the
/// region with the text.
pub fn FoldingModel::update_post(
  self : FoldingModel,
  new_regions : FoldingRegions,
) -> Unit {
  let new_editor_decorations : Array[@model.ModelDeltaDecoration] = []
  let mut last_hidden_line = -1
  for index in 0..<new_regions.length() {
    let start_line_number = new_regions.get_start_line_number(index)
    let end_line_number = new_regions.get_end_line_number(index)
    let is_collapsed = new_regions.is_collapsed(index)
    let is_manual = new_regions.get_source(index) != Provider
    let decoration_range : @base_common.Range = Range(
      start_line_number,
      self.text_model.snapshot.get_line_max_column(start_line_number),
      end_line_number,
      self.text_model.snapshot.get_line_max_column(end_line_number) + 1,
    )
    new_editor_decorations.push({
      range: decoration_range,
      options: self.decoration_access.get_decoration_option(
        is_collapsed,
        end_line_number <= last_hidden_line,
        is_manual,
        new_regions.get_type(index) == Some(OUTLINE_BODY_FOLDING_RANGE_TYPE),
      ),
    })
    if is_collapsed && end_line_number > last_hidden_line {
      last_hidden_line = end_line_number
    }
  }
  self.decoration_access.change_decorations(accessor => {
    self.editor_decoration_ids = (accessor.delta_decorations)(
      self.editor_decoration_ids,
      new_editor_decorations,
    )
  })
  self.regions = new_regions
  self.update_event_emitter.fire(())
}

///|
/// `_currentFoldedOrManualRanges` (`foldingModel.ts:146`): the folded and
/// user-defined ranges, read back through their tracking decorations so
/// edits since the last update are reflected.
fn FoldingModel::current_folded_or_manual_ranges(
  self : FoldingModel,
  selection? : SelectedLines,
) -> Array[FoldRange] {
  let folded_ranges : Array[FoldRange] = []
  for i in 0..<self.regions.length() {
    let mut is_collapsed = self.regions.is_collapsed(i)
    let source = self.regions.get_source(i)
    if is_collapsed || source != Provider {
      let fold_range = self.regions.to_fold_range(i)
      match
        self.text_model.get_decoration_range(self.editor_decoration_ids[i]) {
        Some(dec_range) => {
          if is_collapsed &&
            selection is Some(sel) &&
            (sel.starts_inside)(
              dec_range.start_line_number + 1,
              dec_range.end_line_number,
            ) {
            is_collapsed = false // uncollapse is the range is blocked
          }
          folded_ranges.push({
            start_line_number: dec_range.start_line_number,
            end_line_number: dec_range.end_line_number,
            type_: fold_range.type_,
            is_collapsed,
            source,
          })
        }
        None => ()
      }
    }
  }
  folded_ranges
}

///|
/// `getMemento` (`foldingModel.ts:188-210`): persist collapsed provider ranges
/// and every manual range. Expanded provider ranges are deliberately omitted;
/// a newly computed folding model starts expanded, then `apply_memento`
/// reapplies only the saved exceptions.
fn FoldingModel::get_memento(self : FoldingModel) -> Array[FoldingLineMemento]? {
  let folded_or_manual_ranges = self.current_folded_or_manual_ranges()
  let result : Array[FoldingLineMemento] = []
  let max_line_number = self.text_model.get_line_count()
  for range in folded_or_manual_ranges {
    if range.start_line_number >= range.end_line_number ||
      range.start_line_number < 1 ||
      range.end_line_number > max_line_number {
      continue
    }
    result.push({
      start_line_number: range.start_line_number,
      end_line_number: range.end_line_number,
      is_collapsed: Some(range.is_collapsed),
      source: Some(range.source),
      checksum: Some(
        self.get_lines_checksum(
          range.start_line_number + 1,
          range.end_line_number,
        ),
      ),
    })
  }
  if result.is_empty() {
    None
  } else {
    Some(result)
  }
}

///|
/// `applyMemento` (`foldingModel.ts:212-239`): validate persisted ranges
/// against the current document before merging them with freshly computed
/// provider ranges. A changed boundary checksum drops only that stale range.
fn FoldingModel::apply_memento(
  self : FoldingModel,
  state : Array[FoldingLineMemento],
) -> Unit {
  let ranges_to_restore : Array[FoldRange] = []
  let max_line_number = self.text_model.get_line_count()
  for range in state {
    if range.start_line_number >= range.end_line_number ||
      range.start_line_number < 1 ||
      range.end_line_number > max_line_number {
      continue
    }
    let checksum = self.get_lines_checksum(
      range.start_line_number + 1,
      range.end_line_number,
    )
    if range.checksum is None || range.checksum == Some(checksum) {
      ranges_to_restore.push({
        start_line_number: range.start_line_number,
        end_line_number: range.end_line_number,
        type_: None,
        is_collapsed: range.is_collapsed.unwrap_or(true),
        source: range.source.unwrap_or(Provider),
      })
    }
  }
  let new_ranges = FoldingRegions::sanitize_and_merge(
    Regions(self.regions),
    Ranges(ranges_to_restore),
    Some(max_line_number),
  )
  self.update_post(FoldingRegions::from_fold_ranges(new_ranges))
}

///|
/// `_getLinesChecksum` (`foldingModel.ts:241-245`) with the pinned
/// `base/common/hash.ts` string hash: seed `149417`, then multiply by 31 and
/// add each UTF-16 code unit. Six decimal digits are sufficient for rejecting
/// stale persisted ranges.
fn FoldingModel::get_lines_checksum(
  self : FoldingModel,
  line_number_1 : Int,
  line_number_2 : Int,
) -> Int {
  let text = self.text_model.get_line_content(line_number_1) +
    self.text_model.get_line_content(line_number_2)
  let mut hash = 149417
  for code_unit in text.code_units() {
    hash = hash * 31 + code_unit.to_int()
  }
  hash % 1000000
}

///|
/// `dispose` (`foldingModel.ts:231`).
fn FoldingModel::dispose(self : FoldingModel) -> Unit {
  self.decoration_access.remove_decorations(self.editor_decoration_ids)
}

///|
/// `getAllRegionsAtLine` (`foldingModel.ts:236`): the innermost region at
/// `line_number` and its parents, innermost first, optionally filtered by
/// `(region, level)` (level 1 = innermost).
pub fn FoldingModel::get_all_regions_at_line(
  self : FoldingModel,
  line_number : Int,
  filter? : (FoldingRegion, Int) -> Bool,
) -> Array[FoldingRegion] {
  let result : Array[FoldingRegion] = []
  let mut index = self.regions.find_range(line_number)
  let mut level = 1
  while index >= 0 {
    let current = self.regions.to_region(index)
    match filter {
      Some(filter) => if filter(current, level) { result.push(current) }
      None => result.push(current)
    }
    level += 1
    index = current.parent_index()
  }
  result
}

///|
/// `getRegionAtLine` (`foldingModel.ts:253`): the innermost region at
/// `line_number`.
pub fn FoldingModel::get_region_at_line(
  self : FoldingModel,
  line_number : Int,
) -> FoldingRegion? {
  let index = self.regions.find_range(line_number)
  if index >= 0 {
    return Some(self.regions.to_region(index))
  }
  None
}

///|
/// The externally-used plain filter shape of `getRegionsInside`
/// (`foldingModel.ts:263,301-302`). The package also builds a private
/// with-level form for the collapse helpers that track relative nesting.
struct RegionFilter {
  plain : ((FoldingRegion) -> Bool)?
  with_level : ((FoldingRegion, Int) -> Bool)?
}

///|
pub fn RegionFilter::RegionFilter(
  filter : (FoldingRegion) -> Bool,
) -> RegionFilter {
  { plain: Some(filter), with_level: None, }
}

///|
fn region_filter_with_level(
  filter : (FoldingRegion, Int) -> Bool,
) -> RegionFilter {
  { plain: None, with_level: Some(filter), }
}

///|
/// `getRegionsInside` (`foldingModel.ts:263`): every region strictly inside
/// `region` (or all regions for `None`), in document order.
pub fn FoldingModel::get_regions_inside(
  self : FoldingModel,
  region : FoldingRegion?,
  filter? : RegionFilter,
) -> Array[FoldingRegion] {
  let result : Array[FoldingRegion] = []
  let index = match region {
    Some(region) => region.region_index() + 1
    None => 0
  }
  let end_line_number = match region {
    Some(region) => region.end_line_number()
    None => 0x7FFFFFFF // Number.MAX_VALUE
  }
  let with_level_filter = match filter {
    Some({ with_level: Some(filter), .. }) => Some(filter)
    _ => None
  }
  let plain_filter = match filter {
    Some({ plain: Some(f), .. }) => Some(f)
    _ => None
  }
  let level_stack : Array[FoldingRegion] = []
  for i in index..<self.regions.length() {
    guard self.regions.get_start_line_number(i) < end_line_number else { break }
    let current = self.regions.to_region(i)
    let keep = match (with_level_filter, plain_filter) {
      (Some(filter), _) => {
        while level_stack.length() > 0 &&
              !current.contained_by({
                start_line_number: level_stack[level_stack.length() - 1].start_line_number(),
                end_line_number: level_stack[level_stack.length() - 1].end_line_number(),
              }) {
          level_stack.pop() |> ignore
        }
        level_stack.push(current)
        filter(current, level_stack.length())
      }
      (None, Some(f)) => f(current)
      (None, None) => true
    }
    if keep {
      result.push(current)
    }
  }
  result
}

///|
/// `setCollapseStateLevelsDown` (`foldingModel.ts:333`): collapse or expand
/// the regions at the given locations including `levels` levels of
/// children; all regions when `line_numbers` is absent.
pub fn set_collapse_state_levels_down(
  folding_model : FoldingModel,
  do_collapse : Bool,
  levels? : Int = 0x7FFFFFFF,
  line_numbers? : Array[Int],
) -> Unit {
  let to_toggle : Array[FoldingRegion] = []
  let inside_filter = region_filter_with_level((r, level) => {
    r.is_collapsed() != do_collapse && level < levels
  })
  match line_numbers {
    Some(line_numbers) if line_numbers.length() > 0 =>
      for line_number in line_numbers {
        guard folding_model.get_region_at_line(line_number) is Some(region) else {
          continue
        }
        if region.is_collapsed() != do_collapse {
          to_toggle.push(region)
        }
        if levels > 1 {
          to_toggle.append(
            folding_model.get_regions_inside(Some(region), filter=inside_filter),
          )
        }
      }
    _ =>
      to_toggle.append(
        folding_model.get_regions_inside(None, filter=inside_filter),
      )
  }
  folding_model.toggle_collapse_state(to_toggle)
}

///|
/// `setCollapseStateUp` (`foldingModel.ts:375`): collapse or expand the
/// innermost not-yet-matching region at each location.
pub fn set_collapse_state_up(
  folding_model : FoldingModel,
  do_collapse : Bool,
  line_numbers : Array[Int],
) -> Unit {
  let to_toggle : Array[FoldingRegion] = []
  for line_number in line_numbers {
    let regions = folding_model.get_all_regions_at_line(line_number, filter=(
      region,
      _level,
    ) => region.is_collapsed() != do_collapse)
    if regions is [first, ..] {
      to_toggle.push(first)
    }
  }
  folding_model.toggle_collapse_state(to_toggle)
}

///|
/// `setCollapseStateAtLevel` (`foldingModel.ts:391`): folds or unfolds all
/// regions at `fold_level` (1 = top level), except those containing a
/// blocked line.
pub fn set_collapse_state_at_level(
  folding_model : FoldingModel,
  fold_level : Int,
  do_collapse : Bool,
  blocked_line_numbers : Array[Int],
) -> Unit {
  let filter = region_filter_with_level((region, level) => {
    level == fold_level &&
    region.is_collapsed() != do_collapse &&
    !blocked_line_numbers.iter().any(line => region.contains_line(line))
  })
  let to_toggle = folding_model.get_regions_inside(None, filter~)
  folding_model.toggle_collapse_state(to_toggle)
}

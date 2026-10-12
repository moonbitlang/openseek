// Reachable subset of Monaco/VS Code's TextModel decoration cluster.
//
// Source: vscode/src/vs/editor/common/model/textModel.ts
// (checked-in vscode submodule):
// fields `:285-290` (carried on `TextModel`, `text_model.mbt`), event
// plumbing `:225-226,:1624-1667`, public API
// `:1669-1886`, private impls `:1890-2062`, `DecorationsTrees` `:2196-2353`,
// node predicates `:2180-2190`, `DidChangeDecorationsEmitter` `:2586-2666`.
//
// Deviations (plan `monaco-decoration-system-port.md`):
// - D5 (options interning): `register`/`createDynamic`/`_normalizeOptions`
//   collapse into the `ModelDecorationOptions::ModelDecorationOptions` constructor (in the source
//   both statics are the identical `new ModelDecorationOptions(options)`,
//   and `_normalizeOptions` is an `instanceof` test that has no analogue
//   with a single nominal options type).
// - D6 (model swap): decoration state is per-`TextModel` instance; the viewer
//   swaps whole models on version change, so owners re-attach on swap.
//   `set_value` bumps `_versionId` in place, but it also replaces the trees
//   wholesale ("Destroy all my decorations"), so each tree lifetime still
//   sees exactly one version in `cached_version_id`.
// - `changeDecorations`' `try/catch onUnexpectedError` around the callback is
//   unreachable (MoonBit callbacks here are non-raising), so the `T | null`
//   result is `T`.
// - `_assertNotDisposed`/`_isDisposed` guards are N-A (the readonly model has
//   no dispose lifecycle).
//
// Out-of-scope members (explicitly deferred/N-A, per plan):
// - Query helpers with no product caller (`getAllDecorations`,
//   `getOverviewRulerDecorations`, margin/injected-text interval queries, and
//   direct decoration-option lookup) are DEFERRED.
// - `DecorationsTrees.acceptReplace` and the model edit path: N-A — the
//   readonly viewer never edits a model (the interval tree's edit cluster is
//   not ported, see `interval_tree.mbt`'s header).
// - Injected-text per-line events: the `LineInjectedText` event type and
//   `recordLineAffectedByInjectedText` are DEFERRED with the whole-rebuild
//   deviation (consumers rebuild the projection on `affects_injected_text`;
//   the tree query surface itself is ported —
//   `get_injected_text_decorations`/`get_injected_text_in_interval`, the
//   latter subsuming `getLineInjectedText`'s tree query).
// - Line-height/font: `getCustomLineHeights*`, `getFontDecorations*`,
//   `handleBeforeFireDecorationsChangedEvent` fan-out,
//   `recordLineAffectedByLineHeightChange`/`FontChange`,
//   `_fireOnDidChangeLineHeight`/`Font` are N-A (uniform line height).
// - Bracket/font providers (`_decorationProvider`,
//   `_fontTokenDecorationsProvider`): getters return tree results only.
// - `_getTrackedRange`/`_setTrackedRange`/`TRACKED_RANGE_OPTIONS`: N-A —
//   editing-cursor internals with no consumer in the readonly viewer.
// - `DecorationsTrees.collectNodesPostOrder`: N-A — its only consumer is
//   TextModel.dispose.
// - `DecorationsTrees.ensureAllNodesHaveRanges`: N-A — its only consumer is
//   the `_onBeforeEOLChange` edit path.
// - `DidChangeDecorationsEmitter.hasListeners`: N-A — no consumer in the
//   ported slices.

///|
/// `DidChangeDecorationsEmitter::fire` (event-contract member with no product
/// caller) is consumed only by `text_model_decorations_wbtest.mbt`; anchor
/// it so the non-test build keeps it (the `moon explain 1` idiom).
let _test_only_member_anchor : Unit = ignore(DidChangeDecorationsEmitter::fire)

///|
/// `MODEL_ID` (`textModel.ts:123`): process-wide model counter. The full value
/// is both the stable MoonBit model identity and the decoration-id namespace.
/// This intentionally differs from Monaco's wrapped single-letter hash because
/// marker lookup exposes decoration ids across multiple same-URI models.
let model_identity_counter : Ref[Int32] = Ref(0)

///|
fn next_model_identity() -> (Int32, String) {
  model_identity_counter.val += 1
  let identity = model_identity_counter.val
  // Monaco's single-letter hash is only a compact decoration namespace; it
  // wraps every 52 models. This port also exposes decoration ids through a
  // same-URI marker lookup, so the namespace itself must stay unambiguous.
  (identity, identity.to_string())
}

// #region DidChangeDecorationsEmitter (textModel.ts:2586-2666)

///|
/// `DidChangeDecorationsEmitter` (`textModel.ts:2586`): batches
/// decoration-change notifications into one event per deferred-emit bracket,
/// accumulating the affects flags. The injected-text/line-height/font record
/// sets and the `handleBeforeFire` fan-out are dropped with their
/// out-of-scope features (see file header).
struct DidChangeDecorationsEmitter {
  actual : @base_common.Emitter[ModelDecorationsChangedEvent]
  mut deferred_cnt : Int32
  mut should_fire_deferred : Bool
  mut affects_minimap : Bool
  mut affects_overview_ruler : Bool
  mut affects_glyph_margin : Bool
  /// Whether any changed decoration carried injected-text options.
  /// Deviation: Monaco routes injected-text deltas through
  /// `onDidChangeContentOrInjectedText` with per-line granularity
  /// (`handleBeforeFireDecorationsChangedEvent` → affected-lines event);
  /// the viewer's pipeline rebuilds the projection whole, so a single
  /// event flag is the seam.
  mut affects_injected_text : Bool
  /// Carried for event shape only: `lineNumberClassName` is not ported, so
  /// nothing sets this (and, like the source's `doFire`, it is never reset).
  affects_line_number : Bool
}

///|
fn DidChangeDecorationsEmitter::DidChangeDecorationsEmitter() -> DidChangeDecorationsEmitter {
  {
    actual: Emitter(),
    deferred_cnt: 0,
    should_fire_deferred: false,
    affects_minimap: false,
    affects_overview_ruler: false,
    affects_glyph_margin: false,
    affects_injected_text: false,
    affects_line_number: false,
  }
}

///|
fn DidChangeDecorationsEmitter::begin_deferred_emit(
  self : DidChangeDecorationsEmitter,
) -> Unit {
  self.deferred_cnt += 1
}

///|
fn DidChangeDecorationsEmitter::end_deferred_emit(
  self : DidChangeDecorationsEmitter,
) -> Unit {
  self.deferred_cnt -= 1
  if self.deferred_cnt == 0 {
    if self.should_fire_deferred {
      self.do_fire()
    }
    // affected injected-text/line-height/font sets cleared here in the
    // source — N-A (features out of scope)
  }
}

///|
/// `checkAffectedAndFire`: `_affectsLineNumber ||= !!options.lineNumberClassName`
/// is dropped (field not ported). Truthiness of `overviewRuler?.color` and
/// `glyphMarginClassName` means a present, non-empty string.
fn DidChangeDecorationsEmitter::check_affected_and_fire(
  self : DidChangeDecorationsEmitter,
  options : ModelDecorationOptions,
) -> Unit {
  if !self.affects_minimap {
    self.affects_minimap = options.minimap is Some(_)
  }
  if !self.affects_overview_ruler {
    self.affects_overview_ruler = options.overview_ruler is Some(ruler) &&
      ruler.color is Some(color) &&
      color != ""
  }
  if !self.affects_glyph_margin {
    self.affects_glyph_margin = options.glyph_margin_class_name is Some(name) &&
      name != ""
  }
  if !self.affects_injected_text {
    self.affects_injected_text = options_is_injected_text(options)
  }
  self.try_fire()
}

///|
fn DidChangeDecorationsEmitter::fire(
  self : DidChangeDecorationsEmitter,
) -> Unit {
  self.affects_minimap = true
  self.affects_overview_ruler = true
  self.affects_glyph_margin = true
  self.affects_injected_text = true
  self.try_fire()
}

///|
fn DidChangeDecorationsEmitter::try_fire(
  self : DidChangeDecorationsEmitter,
) -> Unit {
  if self.deferred_cnt == 0 {
    self.do_fire()
  } else {
    self.should_fire_deferred = true
  }
}

///|
fn DidChangeDecorationsEmitter::do_fire(
  self : DidChangeDecorationsEmitter,
) -> Unit {
  // handleBeforeFire fan-out: N-A (all three arms out of scope)
  let event : ModelDecorationsChangedEvent = {
    affects_minimap: self.affects_minimap,
    affects_overview_ruler: self.affects_overview_ruler,
    affects_glyph_margin: self.affects_glyph_margin,
    affects_injected_text: self.affects_injected_text,
    affects_line_number: self.affects_line_number,
  }
  self.should_fire_deferred = false
  self.affects_minimap = false
  self.affects_overview_ruler = false
  self.affects_glyph_margin = false
  self.affects_injected_text = false
  self.actual.fire(event)
}

// #endregion

// #region ModelDecorationOptions node predicates (textModel.ts:2180-2190)

///|
/// `isNodeInOverviewRuler` (`textModel.ts:2180-2182`).
fn is_node_in_overview_ruler(node : IntervalNode) -> Bool {
  node.options is Some(options) && options_in_overview_ruler(options)
}

///|
fn options_in_overview_ruler(options : ModelDecorationOptions) -> Bool {
  options.overview_ruler is Some(ruler) &&
  ruler.color is Some(color) &&
  color != ""
}

///|
/// `isNodeInjectedText` (`textModel.ts:2188-2190`) over
/// `isOptionsInjectedText`: the node carries `before`/`after` injected-text
/// options.
fn is_node_injected_text(node : IntervalNode) -> Bool {
  node.options is Some(options) && options_is_injected_text(options)
}

///|
fn options_is_injected_text(options : ModelDecorationOptions) -> Bool {
  options.before is Some(_) || options.after is Some(_)
}

// #endregion

// #region DecorationsTrees (textModel.ts:2196-2353)

///|
/// `DecorationsTrees`: tree0 holds decorations that do not show up in the
/// overview ruler, tree1 those that do, and the injected-text tree is the
/// stubbed-empty third slot (see file header).
struct DecorationsTrees {
  decorations_tree_0 : IntervalTree
  decorations_tree_1 : IntervalTree
  injected_text_decorations_tree : IntervalTree
}

///|
fn DecorationsTrees::DecorationsTrees() -> DecorationsTrees {
  {
    decorations_tree_0: IntervalTree(),
    decorations_tree_1: IntervalTree(),
    injected_text_decorations_tree: IntervalTree(),
  }
}

///|
/// `_ensureNodesHaveRanges` (`textModel.ts:2224-2232`). Monaco fills missing
/// ranges then casts the nodes to `IModelDecoration`; the port materializes
/// `ModelDecoration` copies (same data — noted on the type).
fn DecorationsTrees::ensure_nodes_have_ranges(
  self : DecorationsTrees,
  host : TextModel,
  nodes : Array[IntervalNode],
) -> Array[ModelDecoration] {
  ignore(self)
  for node in nodes {
    if node.range is None {
      node.range = Some(
        host.get_range_at(node.cached_absolute_start, node.cached_absolute_end),
      )
    }
  }
  nodes.map(node => {
    id: node.id,
    owner_id: node.owner_id,
    range: node.range.unwrap(),
    options: node.options.unwrap(),
  })
}

///|
/// `getAllInInterval` (`textModel.ts:2233-2238`).
fn DecorationsTrees::get_all_in_interval(
  self : DecorationsTrees,
  host : TextModel,
  start : Int32,
  end : Int32,
  filter_owner_id : Int32,
  filter_out_validation : Bool,
  filter_font_decorations : Bool,
  only_margin_decorations : Bool,
) -> Array[ModelDecoration] {
  let version_id = host.get_version_id()
  let result = self.interval_search(
    start, end, filter_owner_id, filter_out_validation, filter_font_decorations,
    version_id, only_margin_decorations,
  )
  self.ensure_nodes_have_ranges(host, result)
}

///|
/// `_intervalSearch` (`textModel.ts:2240-2245`).
fn DecorationsTrees::interval_search(
  self : DecorationsTrees,
  start : Int32,
  end : Int32,
  filter_owner_id : Int32,
  filter_out_validation : Bool,
  filter_font_decorations : Bool,
  cached_version_id : Int32,
  only_margin_decorations : Bool,
) -> Array[IntervalNode] {
  let r0 = self.decorations_tree_0.interval_search(
    start, end, filter_owner_id, filter_out_validation, filter_font_decorations,
    cached_version_id, only_margin_decorations,
  )
  let r1 = self.decorations_tree_1.interval_search(
    start, end, filter_owner_id, filter_out_validation, filter_font_decorations,
    cached_version_id, only_margin_decorations,
  )
  let r2 = self.injected_text_decorations_tree.interval_search(
    start, end, filter_owner_id, filter_out_validation, filter_font_decorations,
    cached_version_id, only_margin_decorations,
  )
  r0 + r1 + r2
}

///|
/// `getAllInjectedText` (`textModel.ts`, DecorationsTrees).
fn DecorationsTrees::get_all_injected_text(
  self : DecorationsTrees,
  host : TextModel,
  filter_owner_id : Int32,
) -> Array[ModelDecoration] {
  let version_id = host.get_version_id()
  let result = self.injected_text_decorations_tree.search(
    filter_owner_id, false, false, version_id, false,
  )
  self
  .ensure_nodes_have_ranges(host, result)
  .filter(d => d.options.show_if_collapsed || !d.range.is_empty())
}

///|
/// `collectNodesFromOwner` (`textModel.ts:2328-2333`).
fn DecorationsTrees::collect_nodes_from_owner(
  self : DecorationsTrees,
  owner_id : Int32,
) -> Array[IntervalNode] {
  let r0 = self.decorations_tree_0.collect_nodes_from_owner(owner_id)
  let r1 = self.decorations_tree_1.collect_nodes_from_owner(owner_id)
  let r2 = self.injected_text_decorations_tree.collect_nodes_from_owner(
    owner_id,
  )
  r0 + r1 + r2
}

///|
/// `insert` (`textModel.ts:2342-2350` region): route by node bits.
fn DecorationsTrees::insert(
  self : DecorationsTrees,
  node : IntervalNode,
) -> Unit {
  if is_node_injected_text(node) {
    self.injected_text_decorations_tree.insert(node)
  } else if is_node_in_overview_ruler(node) {
    self.decorations_tree_1.insert(node)
  } else {
    self.decorations_tree_0.insert(node)
  }
}

///|
/// `delete`.
fn DecorationsTrees::delete(
  self : DecorationsTrees,
  node : IntervalNode,
) -> Unit {
  if is_node_injected_text(node) {
    self.injected_text_decorations_tree.delete(node)
  } else if is_node_in_overview_ruler(node) {
    self.decorations_tree_1.delete(node)
  } else {
    self.decorations_tree_0.delete(node)
  }
}

///|
/// `getNodeRange` (`textModel.ts:2327-2340` region).
fn DecorationsTrees::get_node_range(
  self : DecorationsTrees,
  host : TextModel,
  node : IntervalNode,
) -> @base_common.Range {
  let version_id = host.get_version_id()
  if node.cached_version_id != version_id {
    self.resolve_node(node, version_id)
  }
  if node.range is None {
    node.range = Some(
      host.get_range_at(node.cached_absolute_start, node.cached_absolute_end),
    )
  }
  node.range.unwrap()
}

///|
/// `_resolveNode`.
fn DecorationsTrees::resolve_node(
  self : DecorationsTrees,
  node : IntervalNode,
  cached_version_id : Int32,
) -> Unit {
  if is_node_injected_text(node) {
    self.injected_text_decorations_tree.resolve_node(node, cached_version_id)
  } else if is_node_in_overview_ruler(node) {
    self.decorations_tree_1.resolve_node(node, cached_version_id)
  } else {
    self.decorations_tree_0.resolve_node(node, cached_version_id)
  }
}

// #endregion

// #region TextModel decoration API (textModel.ts:1669-2062)

///|
/// `onDidChangeDecorations` (`textModel.ts:225-226`): one event per
/// deferred-emit bracket. The backing `_onDidChangeDecorations` emitter is
/// the same-named `TextModel` field.
pub fn TextModel::on_did_change_decorations(
  self : TextModel,
  listener : (ModelDecorationsChangedEvent) -> Unit,
) -> @base_common.Disposable {
  self.on_did_change_decorations.actual.event(listener)
}

///|
/// `getRangeAt` (`textModel.ts:1886-1889` region): offsets → line/column
/// range via the snapshot.
fn TextModel::get_range_at(
  self : TextModel,
  start : Int32,
  end : Int32,
) -> @base_common.Range {
  self.snapshot.range_of(OffsetRange(start, end))
}

///|
/// The `IModelDecorationsChangeAccessor` handed to `change_decorations`
/// callbacks (`textModel.ts:1681-1701`). Fields are invalidated after the
/// callback returns, like the source's `invalidFunc` swap.
pub struct ModelDecorationsChangeAccessor {
  mut add_decoration : (@base_common.Range, ModelDecorationOptions) -> String
  mut change_decoration : (String, @base_common.Range) -> Unit
  mut change_decoration_options : (String, ModelDecorationOptions) -> Unit
  mut remove_decoration : (String) -> Unit
  mut delta_decorations : (Array[String], Array[ModelDeltaDecoration]) -> Array[
    String,
  ]
}

///|
/// `changeDecorations` (`textModel.ts:1669-1678`): runs `callback` against a
/// change accessor inside one deferred-emit bracket.
pub fn[T] TextModel::change_decorations(
  self : TextModel,
  callback : (ModelDecorationsChangeAccessor) -> T,
  owner_id~ : Int32 = 0,
) -> T {
  // _assertNotDisposed: N-A (readonly model)
  self.on_did_change_decorations.begin_deferred_emit()
  let result = self.change_decorations_impl(owner_id, callback)
  self.on_did_change_decorations.end_deferred_emit()
  result
}

///|
/// `_changeDecorations` (`textModel.ts:1680-1715`).
fn[T] TextModel::change_decorations_impl(
  self : TextModel,
  owner_id : Int32,
  callback : (ModelDecorationsChangeAccessor) -> T,
) -> T {
  let accessor : ModelDecorationsChangeAccessor = {
    add_decoration: (range, options) => {
      self.delta_decorations_impl(owner_id, [], [{ range, options, }])[0]
    },
    change_decoration: (id, new_range) => {
      self.change_decoration_impl(owner_id, id, new_range)
    },
    change_decoration_options: (id, options) => {
      self.change_decoration_options_impl(owner_id, id, options)
    },
    remove_decoration: id => {
      ignore(self.delta_decorations_impl(owner_id, [id], []))
    },
    delta_decorations: (old_decorations, new_decorations) => {
      if old_decorations.length() == 0 && new_decorations.length() == 0 {
        // nothing to do
        []
      } else {
        self.delta_decorations_impl(owner_id, old_decorations, new_decorations)
      }
    },
  }
  let result = callback(accessor)
  // Invalidate change accessor
  accessor.add_decoration = (_range, _options) => {
    abort("Invalid change accessor")
  }
  accessor.change_decoration = (_id, _range) => abort("Invalid change accessor")
  accessor.change_decoration_options = (_id, _options) => {
    abort("Invalid change accessor")
  }
  accessor.remove_decoration = _id => abort("Invalid change accessor")
  accessor.delta_decorations = (_old, _new) => abort("Invalid change accessor")
  result
}

///|
/// `deltaDecorations` (`textModel.ts:1717-1740`): the atomic remove+add
/// primitive. Returns the new decoration ids.
pub fn TextModel::delta_decorations(
  self : TextModel,
  old_decorations : Array[String],
  new_decorations : Array[ModelDeltaDecoration],
  owner_id~ : Int32 = 0,
) -> Array[String] {
  // _assertNotDisposed: N-A (readonly model)
  if old_decorations.length() == 0 && new_decorations.length() == 0 {
    // nothing to do
    return []
  }
  self.delta_decoration_call_cnt += 1
  if self.delta_decoration_call_cnt > 1 {
    // console.warn + onUnexpectedError in the source; println is the js
    // backend's console.
    println(
      "Invoking deltaDecorations recursively could lead to leaking decorations.",
    )
  }
  self.on_did_change_decorations.begin_deferred_emit()
  let result = self.delta_decorations_impl(
    owner_id, old_decorations, new_decorations,
  )
  self.on_did_change_decorations.end_deferred_emit()
  self.delta_decoration_call_cnt -= 1
  result
}

///|
/// `removeAllDecorationsWithOwnerId` (`textModel.ts:1777-1789`). Like the
/// source, this fires no change event.
pub fn TextModel::remove_all_decorations_with_owner_id(
  self : TextModel,
  owner_id : Int32,
) -> Unit {
  // _isDisposed guard: N-A (readonly model)
  let nodes = self.decorations_tree.collect_nodes_from_owner(owner_id)
  for node in nodes {
    self.decorations_tree.delete(node)
    self.decorations.remove(node.id)
  }
}

///|
/// `getDecorationRange` (`textModel.ts:1798-1804`).
pub fn TextModel::get_decoration_range(
  self : TextModel,
  decoration_id : String,
) -> @base_common.Range? {
  match self.decorations.get(decoration_id) {
    Some(node) => Some(self.decorations_tree.get_node_range(self, node))
    None => None
  }
}

///|
/// `getLineDecorations` (`textModel.ts:1806-1812`).
pub fn TextModel::get_line_decorations(
  self : TextModel,
  line_number : Int32,
  owner_id~ : Int32 = 0,
  filter_out_validation~ : Bool = false,
  filter_font_decorations~ : Bool = false,
) -> Array[ModelDecoration] {
  if line_number < 1 || line_number > self.snapshot.line_count() {
    return []
  }
  self.get_lines_decorations(
    line_number,
    line_number,
    owner_id~,
    filter_out_validation~,
    filter_font_decorations~,
  )
}

///|
/// `getLinesDecorations` (`textModel.ts:1813-1825`). The bracket/font
/// provider merges are N-A (providers out of scope) — tree results only.
fn TextModel::get_lines_decorations(
  self : TextModel,
  start_line_number : Int32,
  end_line_number : Int32,
  owner_id~ : Int32 = 0,
  filter_out_validation~ : Bool = false,
  filter_font_decorations~ : Bool = false,
  only_margin_decorations~ : Bool = false,
) -> Array[ModelDecoration] {
  let line_count = self.snapshot.line_count()
  let start_line_number = start_line_number.clamp(min=1, max=line_count)
  let end_line_number = end_line_number.clamp(min=1, max=line_count)
  let end_column = self.snapshot.get_line_max_column(end_line_number)
  let range : @base_common.Range = Range(
    start_line_number, 1, end_line_number, end_column,
  )
  self.get_decorations_in_range_impl(
    range, owner_id, filter_out_validation, filter_font_decorations, only_margin_decorations,
  )
}

///|
/// `getDecorationsInRange` (`textModel.ts:1826-1834`). The
/// `onlyMinimapDecorations` argument is dropped — the source forwards it only
/// to the out-of-scope bracket provider. Provider merges N-A as above.
pub fn TextModel::get_decorations_in_range(
  self : TextModel,
  range : @base_common.Range,
  owner_id~ : Int32 = 0,
  filter_out_validation~ : Bool = false,
  filter_font_decorations~ : Bool = false,
  only_margin_decorations~ : Bool = false,
) -> Array[ModelDecoration] {
  let validated_range = self.validate_range(range)
  self.get_decorations_in_range_impl(
    validated_range, owner_id, filter_out_validation, filter_font_decorations, only_margin_decorations,
  )
}

///|
/// `getInjectedTextDecorations` (`textModel.ts`): every decoration carrying
/// `before`/`after` injected-text options. `owner_id = 0` matches all
/// owners (the tree's filter semantics).
pub fn TextModel::get_injected_text_decorations(
  self : TextModel,
  owner_id~ : Int32 = 0,
) -> Array[ModelDecoration] {
  self.decorations_tree.get_all_injected_text(self, owner_id)
}

///|
/// `_getDecorationsInRange` (`textModel.ts:1880-1889`).
fn TextModel::get_decorations_in_range_impl(
  self : TextModel,
  filter_range : @base_common.Range,
  filter_owner_id : Int32,
  filter_out_validation : Bool,
  filter_font_decorations : Bool,
  only_margin_decorations : Bool,
) -> Array[ModelDecoration] {
  let start_offset = self.snapshot.get_offset_at(
    filter_range.start_line_number,
    filter_range.start_column,
  )
  let end_offset = self.snapshot.get_offset_at(
    filter_range.end_line_number,
    filter_range.end_column,
  )
  self.decorations_tree.get_all_in_interval(
    self, start_offset, end_offset, filter_owner_id, filter_out_validation, filter_font_decorations,
    only_margin_decorations,
  )
}

///|
/// `_changeDecorationImpl` (`textModel.ts:1890-1935`). The injected-text/
/// line-height/font record arms are dropped with their features; `ownerId`
/// is consumed only by those arms in the source, hence unused here.
fn TextModel::change_decoration_impl(
  self : TextModel,
  _owner_id : Int32,
  decoration_id : String,
  range : @base_common.Range,
) -> Unit {
  guard self.decorations.get(decoration_id) is Some(node) else { return }
  let range = self.validate_range_relaxed(range)
  let start_offset = self.snapshot.get_offset_at(
    range.start_line_number,
    range.start_column,
  )
  let end_offset = self.snapshot.get_offset_at(
    range.end_line_number,
    range.end_column,
  )
  self.decorations_tree.delete(node)
  node.reset(self.get_version_id(), start_offset, end_offset, Some(range))
  self.decorations_tree.insert(node)
  self.on_did_change_decorations.check_affected_and_fire(node.options.unwrap())
}

///|
/// `_changeDecorationOptionsImpl` (`textModel.ts:1936-1975`). The
/// injected-text/line-height/font arms are dropped with their features;
/// `changedWhetherInjectedText` is constantly false, so only the
/// overview-ruler tree migration remains.
fn TextModel::change_decoration_options_impl(
  self : TextModel,
  _owner_id : Int32,
  decoration_id : String,
  options : ModelDecorationOptions,
) -> Unit {
  guard self.decorations.get(decoration_id) is Some(node) else { return }
  let node_was_in_overview_ruler = is_node_in_overview_ruler(node)
  let node_is_in_overview_ruler = options_in_overview_ruler(options)
  self.on_did_change_decorations.check_affected_and_fire(node.options.unwrap())
  self.on_did_change_decorations.check_affected_and_fire(options)
  let moved_in_overview_ruler = node_was_in_overview_ruler !=
    node_is_in_overview_ruler
  if moved_in_overview_ruler {
    self.decorations_tree.delete(node)
    node.set_options(options)
    self.decorations_tree.insert(node)
  } else {
    node.set_options(options)
  }
}

///|
/// `_deltaDecorationsImpl` (`textModel.ts:1976-2062`): the two-pointer
/// old/new walk with node reuse. Injected-text/line-height/font record arms
/// dropped with their features.
fn TextModel::delta_decorations_impl(
  self : TextModel,
  owner_id : Int32,
  old_decorations_ids : Array[String],
  new_decorations : Array[ModelDeltaDecoration],
  suppress_events~ : Bool = false,
) -> Array[String] {
  let version_id = self.get_version_id()
  let old_decorations_len = old_decorations_ids.length()
  let mut old_decoration_index = 0
  let new_decorations_len = new_decorations.length()
  let mut new_decoration_index = 0
  self.on_did_change_decorations.begin_deferred_emit()
  let result : Array[String] = Array::make(new_decorations_len, "")
  while old_decoration_index < old_decorations_len ||
        new_decoration_index < new_decorations_len {
    let mut node : IntervalNode? = None
    if old_decoration_index < old_decorations_len {
      // (1) get ourselves an old node
      for ;; {
        let decoration_id = old_decorations_ids[old_decoration_index]
        old_decoration_index += 1
        node = self.decorations.get(decoration_id)
        if node is Some(_) || old_decoration_index >= old_decorations_len {
          break
        }
      }
      // (2) remove the node from the tree (if it exists)
      if node is Some(found) {
        self.decorations_tree.delete(found)
        if !suppress_events {
          self.on_did_change_decorations.check_affected_and_fire(
            found.options.unwrap(),
          )
        }
      }
    }
    if new_decoration_index < new_decorations_len {
      // (3) create a new node if necessary
      let live_node = match node {
        Some(found) => found
        None => {
          self.last_decoration_id += 1
          let decoration_id = "\{self.decoration_id_namespace};\{self.last_decoration_id}"
          let created = IntervalNode(decoration_id, 0, 0)
          self.decorations[decoration_id] = created
          created
        }
      }
      // (4) initialize node
      let new_decoration = new_decorations[new_decoration_index]
      let range = self.validate_range_relaxed(new_decoration.range)
      // _normalizeOptions: the single ModelDecorationOptions constructor already
      // normalized (Deviation D5)
      let options = new_decoration.options
      let start_offset = self.snapshot.get_offset_at(
        range.start_line_number,
        range.start_column,
      )
      let end_offset = self.snapshot.get_offset_at(
        range.end_line_number,
        range.end_column,
      )
      live_node.owner_id = owner_id
      live_node.reset(version_id, start_offset, end_offset, Some(range))
      live_node.set_options(options)
      if !suppress_events {
        self.on_did_change_decorations.check_affected_and_fire(options)
      }
      self.decorations_tree.insert(live_node)
      result[new_decoration_index] = live_node.id
      new_decoration_index += 1
    } else if node is Some(found) {
      self.decorations.remove(found.id)
    }
  }
  self.on_did_change_decorations.end_deferred_emit()
  result
}

// #endregion

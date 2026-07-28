///|
/// Readonly editor model identity plus immutable text snapshot, plus the
/// Monaco decoration fields (the one mutable part; the decoration API lives
/// in `text_model_decorations.mbt`).
const LARGE_FILE_SIZE_THRESHOLD : Int = 20 * 1024 * 1024

///|
const LARGE_FILE_LINE_COUNT_THRESHOLD : Int = 300 * 1000

///|
pub struct TextModel {
  uri : @base_common.Uri
  display_name : String
  language_id : String
  version : Int
  revision : String
  /// Mutable since the `set_value` flush lane: swapped whole
  /// (`_setValueFromTextBuffer`'s `this._buffer = textBuffer`,
  /// `textModel.ts:521`), never edited in place.
  mut snapshot : TextSnapshot
  /// The `model.tokenization` part (Monaco's `TokenizationTextModelPart`,
  /// wired in the `TextModel` constructor exactly as `textModel.ts` does).
  tokenization : TokenizationTextModelPart
  /// TextModel owns the attached-view aggregate; tokenization only borrows it.
  priv attached_views : AttachedViews
  /// Construction-safe live facts shared with the model-owned tokenization part.
  priv tokenization_state : TokenizationModelState
  /// `_onDidChangeAttached` (`textModel.ts:235`), owned and released by the
  /// model rather than by the borrowed attached-view aggregate.
  priv attached_change_emitter : @base_common.Emitter[Unit]
  // Lifecycle (`_onWillDispose` textModel.ts:222, `_isDisposed` :190,
  // `__isDisposing` :260)
  on_will_dispose : @base_common.Emitter[Unit]
  priv mut is_disposed : Bool
  /// `_versionId` (`textModel.ts:262`, init 1 at `:370`): bumped by the
  /// content lane (`_increaseVersionId`). Together with the stable model
  /// identity this is async freshness authority; the host-facing `version`
  /// is caller-owned metadata.
  priv mut version_id : Int
  // Content events (`_eventEmitter` textModel.ts:244; `_viewModels` :303)
  priv event_emitter : DidChangeContentEmitter
  priv view_models : Array[ViewModelCallbacks]
  // #region Decorations (textModel.ts:285-290; `_onDidChangeDecorations` :225)
  /// Full process-local identity used for exact model-instance comparisons.
  priv identity : Int
  /// Stable decoration-id namespace prefix derived from `identity`.
  priv decoration_id_namespace : String
  mut delta_decoration_call_cnt : Int
  mut last_decoration_id : Int
  /// Mutable since the `set_value` flush lane: replaced wholesale
  /// ("Destroy all my decorations", `textModel.ts:526-528`).
  mut decorations : Map[String, IntervalNode]
  mut decorations_tree : DecorationsTrees
  on_did_change_decorations : DidChangeDecorationsEmitter
  // #endregion
}

///|
pub impl Debug for TextModel with fn to_repr(self) {
  Repr(
    "<TextModel \{self.uri.to_string()} v\{self.version} decorations: \{self.decorations.length()}>",
  )
}

///|
/// Whether two handles name the same stable text-model instance.
pub fn TextModel::same(self : TextModel, other : TextModel) -> Bool {
  self.identity == other.identity
}

///|
/// Stable process-local key for identity-indexed package services.
///
/// Most callers should prefer `same`; this numeric form exists for maps that
/// cannot key directly by `TextModel` without falling back to reference
/// equality.
pub fn TextModel::identity(self : TextModel) -> Int {
  self.identity
}

///|
/// Builds a readonly text model.
///
/// `version` and `revision` are caller-owned metadata, not async freshness
/// keys. Request owners use stable model identity plus `get_version_id()`.
/// Empty display name and language id are normalized; non-positive versions
/// become version 1.
pub fn TextModel::TextModel(
  uri : @base_common.Uri,
  display_name : String,
  language_id : String,
  version : Int,
  revision : String,
  text : String,
) -> TextModel {
  new_text_model(
    uri,
    display_name,
    language_id,
    version,
    revision,
    text,
    None,
    None,
  )
}

///|
/// Shared production/test constructor. Production passes no resolver and
/// therefore uses the registry-backed token part; the package test seam can
/// inject a failing source-shaped adapter while retaining the exact TextModel
/// ownership, reporting, and lifecycle path.
fn new_text_model(
  uri : @base_common.Uri,
  display_name : String,
  language_id : String,
  version : Int,
  revision : String,
  text : String,
  support_resolver : ((String) -> InternalTokenizationSupportAdapter?)?,
  unexpected_error_observer : ((String) -> Unit)?,
) -> TextModel {
  let display_name = if display_name == "" {
    uri.to_string()
  } else {
    display_name
  }
  let language_id = if language_id == "" { "moonbit" } else { language_id }
  let version = if version < 1 { 1 } else { version }
  let snapshot = TextSnapshot(text)
  // Permanently respect the construction-time large-file decision. Equality
  // stays enabled; only strict greater-than disables tokenization.
  let is_too_large_for_tokenization = snapshot.get_length() >
    LARGE_FILE_SIZE_THRESHOLD ||
    snapshot.line_count() > LARGE_FILE_LINE_COUNT_THRESHOLD
  let model_state = TokenizationModelState(
    snapshot=Ref(snapshot),
    language_id~,
    attached_count=Ref(0),
    too_large=is_too_large_for_tokenization,
    disposing=Ref(false),
    scheduler=Ref(None),
    report_unexpected_error=message => {
      // This package is deliberately host-neutral. `println` reaches the JS
      // console and native stderr/stdout plumbing without importing browser or
      // shell effects, matching the established decoration warning seam.
      println("[viewer/tokenization] unexpected tokenizer error: \{message}")
      match unexpected_error_observer {
        Some(observer) => observer(message)
        None => ()
      }
    },
  )
  let attached_views = AttachedViews()
  let tokenization = match support_resolver {
    Some(resolve_support) =>
      TokenizationTextModelPart::new_with_support_resolver(
        model_state, attached_views, resolve_support,
      )
    None => TokenizationTextModelPart(model_state, attached_views)
  }
  let (identity, decoration_id_namespace) = next_model_identity()
  {
    uri,
    display_name,
    language_id,
    version,
    revision,
    snapshot,
    tokenization,
    attached_views,
    tokenization_state: model_state,
    attached_change_emitter: Emitter(),
    on_will_dispose: Emitter(),
    is_disposed: false,
    version_id: 1,
    event_emitter: DidChangeContentEmitter::new(),
    view_models: [],
    identity,
    decoration_id_namespace,
    delta_decoration_call_cnt: 0,
    last_decoration_id: 0,
    decorations: Map([]),
    decorations_tree: DecorationsTrees::new(),
    on_did_change_decorations: DidChangeDecorationsEmitter::new(),
  }
}

///|
/// Releases the model — `dispose` (`textModel.ts:414`). Fires `onWillDispose`
/// first (the attached editor detaches itself there), then disposes the
/// tokenization part — dropping its registry subscription — and the emitters.
/// Monaco's disposed-buffer swap is N-A: the snapshot is immutable and
/// garbage-collected.
pub fn TextModel::dispose(self : TextModel) -> Unit {
  run_text_model_dispose_sequence(
    set_disposing=value => self.tokenization_state.disposing.val = value,
    fire_will_dispose=() => self.on_will_dispose.fire(()),
    dispose_tokenization=() => self.tokenization.dispose(),
    set_disposed=() => self.is_disposed = true,
    dispose_registered_resources=() => {
      self.attached_views.dispose()
      self.tokenization_state.scheduler.val = None
      self.attached_change_emitter.dispose()
      self.on_will_dispose.dispose()
      self.on_did_change_decorations.actual.dispose()
      self.event_emitter.emitter.dispose()
    },
  )
}

///|
/// `TextModel.dispose` (`textModel.ts:414-421`) retained as one directly
/// testable source-order sequence. In particular, the terminal flag is set
/// after the token part is released but before superclass/registered resources.
fn run_text_model_dispose_sequence(
  set_disposing~ : (Bool) -> Unit,
  fire_will_dispose~ : () -> Unit,
  dispose_tokenization~ : () -> Unit,
  set_disposed~ : () -> Unit,
  dispose_registered_resources~ : () -> Unit,
) -> Unit {
  // `__isDisposing = true` before the will-dispose fire (`textModel.ts:415`);
  // `_emitContentChangedEvent` early-returns while set so no listener is
  // confused by an event after disposing (`:468-471`).
  set_disposing(true)
  fire_will_dispose()
  dispose_tokenization()
  set_disposed()
  dispose_registered_resources()
  set_disposing(false)
}

///|
/// Whether `dispose` has run — `isDisposed` (`textModel.ts:445`).
pub fn TextModel::is_disposed(self : TextModel) -> Bool {
  self.is_disposed
}

///|
/// Constructor-fixed large-file tokenization policy. A later `set_value`
/// never changes this fact (`textModel.ts:334-346,637-639`).
pub fn TextModel::is_too_large_for_tokenization(self : TextModel) -> Bool {
  self.tokenization_state.too_large
}

///|
/// Number of currently attached Viewer instances.
pub fn TextModel::get_attached_editor_count(self : TextModel) -> Int {
  self.tokenization_state.attached_count.val
}

///|
/// Whether at least one Viewer is attached.
pub fn TextModel::is_attached_to_editor(self : TextModel) -> Bool {
  self.tokenization_state.attached_count.val > 0
}

///|
/// Subscribes to the aggregate attachment boundary. The event fires after the
/// tokenization part has observed exactly `0 -> 1` or `1 -> 0`, matching
/// `onDidChangeAttached` (`textModel.ts:235-236,607-623`; `model.ts:1365`).
pub fn TextModel::on_did_change_attached(
  self : TextModel,
  listener : () -> Unit,
) -> @base_common.Disposable {
  self.attached_change_emitter.event(_ => listener())
}

///|
/// Begins one Viewer attachment (`textModel.ts:607-614`). The first non-None
/// scheduler of an attached epoch wins. A late first scheduler wakes existing
/// background work once without synthesizing another 0->1 notification.
pub fn TextModel::on_before_attached(
  self : TextModel,
  scheduler? : TokenizationScheduler,
) -> AttachedViewImpl {
  let mut installed_late_scheduler = false
  if self.tokenization_state.scheduler.val is None {
    match scheduler {
      Some(scheduler) => {
        self.tokenization_state.scheduler.val = Some(scheduler)
        installed_late_scheduler = self.tokenization_state.attached_count.val >
          0
      }
      None => ()
    }
  }
  if installed_late_scheduler {
    self.tokenization.handle_did_change_attached()
  }
  self.tokenization_state.attached_count.val += 1
  if self.tokenization_state.attached_count.val == 1 {
    self.tokenization.handle_did_change_attached()
    self.attached_change_emitter.fire(())
  }
  self.attached_views.attach_view()
}

///|
/// Finishes one Viewer attachment (`textModel.ts:616-623`). The final
/// transition notifies/cancels backend work first, detaches the exact handle
/// second, and clears the epoch scheduler last.
pub fn TextModel::on_before_detached(
  self : TextModel,
  attached_view : AttachedViewImpl,
) -> Unit {
  self.tokenization_state.attached_count.val -= 1
  if self.tokenization_state.attached_count.val == 0 {
    self.tokenization.handle_did_change_attached()
    self.attached_change_emitter.fire(())
  }
  self.attached_views.detach_view(attached_view)
  if self.tokenization_state.attached_count.val == 0 {
    self.tokenization_state.scheduler.val = None
  }
}

///|
/// Model listener ownership query (`textModel.ts:430-440`). The readonly
/// model carries will-dispose, decoration, token, attached, and content
/// emitters; unported options/line-height/font emitters are N-A. In
/// particular, the token-part substep must not be omitted.
fn TextModel::has_listeners(self : TextModel) -> Bool {
  self.on_will_dispose.has_listeners() ||
  self.on_did_change_decorations.actual.has_listeners() ||
  self.tokenization.has_listeners() ||
  self.attached_change_emitter.has_listeners() ||
  self.event_emitter.emitter.has_listeners()
}

///|
/// Keeps the package-internal source member in the non-test build; wbtests
/// exercise the token-listener ownership branch directly.
let _test_only_text_model_has_listeners_anchor : Unit = ignore(
  TextModel::has_listeners,
)

///|
/// Subscribes to the start of `dispose` — `onWillDispose` (`textModel.ts:223`).
pub fn TextModel::on_will_dispose(
  self : TextModel,
  listener : () -> Unit,
) -> @base_common.Disposable {
  self.on_will_dispose.event(_ => listener())
}

///|
/// Subscribes to grammar-token changes — `onDidChangeTokens`, delegating to
/// the tokenization part as the source's forwarded emitter does.
pub fn TextModel::on_did_change_tokens(
  self : TextModel,
  listener : (ModelTokensChangedEvent) -> Unit,
) -> @base_common.Disposable {
  self.tokenization.on_did_change_tokens(listener)
}

///|
/// Returns the immutable snapshot consumed by tokenization, providers, and
/// rendering.
pub fn TextModel::snapshot(self : TextModel) -> TextSnapshot {
  self.snapshot
}

// #region Reading text — the `textModel.ts` read section (:737-1176, word
// cluster :2085-2124), delegating to the snapshot buffer exactly as Monaco's
// members delegate to `this._buffer`. `_assertNotDisposed` guards are not
// ported (the immutable snapshot stays readable after `dispose`) and the
// viewer clamps where Monaco throws `BugIndicatingError`; see the README
// parity ledger.

///|
/// Source document language id. Mirrors `getLanguageId` (`textModel.ts:2085`),
/// delegating to the tokenization part as Monaco does.
pub fn TextModel::get_language_id(self : TextModel) -> String {
  self.tokenization.get_language_id()
}

///|
/// Whether the text contains any right-to-left character. Mirrors
/// `mightContainRTL` (`textModel.ts:742`).
pub fn TextModel::might_contain_rtl(self : TextModel) -> Bool {
  self.snapshot.might_contain_rtl()
}

///|
/// Whether the normalized stored text contains any non-basic-ASCII code unit.
/// Mirrors `mightContainNonBasicASCII` (`textModel.ts:756`) while recomputing
/// from the immutable snapshot instead of trusting builder cache metadata.
pub fn TextModel::might_contain_non_basic_ascii(self : TextModel) -> Bool {
  self.snapshot.might_contain_non_basic_ascii()
}

///|
/// Clamped document offset of `position`. Mirrors `getOffsetAt`
/// (`textModel.ts:770`): relaxed-validate, then the buffer's line/column
/// arity.
pub fn TextModel::get_offset_at(
  self : TextModel,
  position : @base_common.Position,
) -> Int {
  let position = self.validate_position_impl(
    position.line_number,
    position.column,
    false,
  )
  self.snapshot.get_offset_at(position.line_number, position.column)
}

///|
/// Position at the clamped document `offset`. Mirrors `getPositionAt`
/// (`textModel.ts:776`).
pub fn TextModel::get_position_at(
  self : TextModel,
  offset : Int,
) -> @base_common.Position {
  let offset = @base_common.clamp_int(offset, 0, self.snapshot.get_length())
  self.snapshot.get_position_at(offset)
}

///|
/// Full normalized document text. Mirrors `getValue` (`textModel.ts:799`):
/// derive the full model range, then read that range. U+FEFF is ordinary
/// Viewer content and there is no EOL or preserve-BOM selector.
pub fn TextModel::get_value(self : TextModel) -> String {
  self.get_value_in_range(self.get_full_model_range())
}

///|
/// Length of `get_value` in UTF-16 code units. Mirrors `getValueLength`
/// (`textModel.ts:819`).
pub fn TextModel::get_value_length(self : TextModel) -> Int {
  self.get_value_length_in_range(self.get_full_model_range())
}

///|
/// Text inside a validated `range`. Mirrors `getValueInRange`
/// (`textModel.ts:831`): validate, then read the buffer.
pub fn TextModel::get_value_in_range(
  self : TextModel,
  range : @base_common.Range,
) -> String {
  self.snapshot.get_value_in_range(self.validate_range(range))
}

///|
/// Length, in UTF-16 code units, of `get_value_in_range`. Mirrors
/// `getValueLengthInRange` (`textModel.ts:836`).
pub fn TextModel::get_value_length_in_range(
  self : TextModel,
  range : @base_common.Range,
) -> Int {
  self.snapshot.get_value_length_in_range(self.validate_range(range))
}

///|
/// Number of logical lines. Mirrors `getLineCount` (`textModel.ts:846`).
pub fn TextModel::get_line_count(self : TextModel) -> Int {
  self.snapshot.line_count()
}

///|
/// Text of the one-based `line_number`, clamped into the document. Mirrors
/// `getLineContent` (`textModel.ts:851`).
pub fn TextModel::get_line_content(
  self : TextModel,
  line_number : Int,
) -> String {
  self.snapshot.get_line_content(line_number)
}

///|
/// Content length of the one-based `line_number`, EOL excluded. Mirrors
/// `getLineLength` (`textModel.ts:860`).
pub fn TextModel::get_line_length(self : TextModel, line_number : Int) -> Int {
  self.snapshot.get_line_length(line_number)
}

///|
/// Every line's content, EOLs excluded. Mirrors `getLinesContent`
/// (`textModel.ts:869`).
pub fn TextModel::get_lines_content(self : TextModel) -> Array[String] {
  let lines : Array[String] = []
  for line in 0..<self.snapshot.line_count() {
    lines.push(self.snapshot.line_text(line))
  }
  lines
}

///|
/// Stored model end-of-line sequence. Mirrors `getEOL` (`textModel.ts:879`)
/// with the Viewer's approved fixed-LF representation.
pub fn TextModel::get_eol(self : TextModel) -> String {
  self.snapshot.get_eol()
}

///|
/// Minimum column of a line, always `1`. Mirrors `getLineMinColumn`
/// (`textModel.ts:892`).
pub fn TextModel::get_line_min_column(
  _self : TextModel,
  _line_number : Int,
) -> Int {
  1
}

///|
/// Max (1-based) column for `line_number`: content length + 1. Mirrors
/// `getLineMaxColumn` (`textModel.ts:897`).
pub fn TextModel::get_line_max_column(
  self : TextModel,
  line_number : Int,
) -> Int {
  self.snapshot.get_line_max_column(line_number)
}

///|
/// 1-based column of the first non-whitespace character on `line_number`, or
/// `0` for whitespace-only lines. Mirrors `getLineFirstNonWhitespaceColumn`
/// (`textModel.ts:905`).
pub fn TextModel::get_line_first_non_whitespace_column(
  self : TextModel,
  line_number : Int,
) -> Int {
  self.snapshot.get_line_first_non_whitespace_column(line_number)
}

///|
/// 1-based column just past the last non-whitespace character on
/// `line_number`, or `0` for whitespace-only lines. Mirrors
/// `getLineLastNonWhitespaceColumn` (`textModel.ts:913`).
pub fn TextModel::get_line_last_non_whitespace_column(
  self : TextModel,
  line_number : Int,
) -> Int {
  self.snapshot.get_line_last_non_whitespace_column(line_number)
}

///|
/// The whole document as a `Range`. Mirrors `getFullModelRange`
/// (`textModel.ts:1168`).
pub fn TextModel::get_full_model_range(self : TextModel) -> @base_common.Range {
  let line_count = self.get_line_count()
  Range(1, 1, line_count, self.get_line_max_column(line_count))
}

///|
/// Core of `validate_position` (Monaco's `_validatePosition`). When `surrogate`
/// is true, a column landing in the middle of a high-low surrogate pair is
/// moved to before the pair. `surrogate=false` is Monaco's `Relaxed` mode (a
/// plain clamp). Inputs are integers, so Monaco's `NaN`/float coercion is moot.
fn TextModel::validate_position_impl(
  self : TextModel,
  line_number : Int,
  column : Int,
  surrogate : Bool,
) -> @base_common.Position {
  let snapshot = self.snapshot
  let line_count = snapshot.line_count()
  if line_number < 1 {
    return Position(1, 1)
  }
  if line_number > line_count {
    return Position(line_count, snapshot.get_line_max_column(line_count))
  }
  if column <= 1 {
    return Position(line_number, 1)
  }
  let max_column = snapshot.get_line_max_column(line_number)
  if column >= max_column {
    return Position(line_number, max_column)
  }
  if surrogate {
    // column > 1 here; if it would split a high-low pair, move before it.
    let char_code_before = snapshot.get_line_char_code(line_number, column - 2)
    if @base_common.is_high_surrogate(char_code_before) {
      return Position(line_number, column - 1)
    }
  }
  Position(line_number, column)
}

///|
/// Clamps a position into the document, snapping out of the middle of a
/// surrogate pair. Mirrors `validatePosition` (`textModel.ts:1063`).
pub fn TextModel::validate_position(
  self : TextModel,
  position : @base_common.Position,
) -> @base_common.Position {
  self.validate_position_impl(position.line_number, position.column, true)
}

///|
/// Clamps a range into the document without surrogate snapping. Mirrors
/// `_validateRangeRelaxedNoAllocations` (`textModel.ts:925`) — the
/// decoration paths use this cheaper clamp instead of `validateRange`.
pub fn TextModel::validate_range_relaxed(
  self : TextModel,
  range : @base_common.Range,
) -> @base_common.Range {
  let start = self.validate_position_impl(
    range.start_line_number,
    range.start_column,
    false,
  )
  let end = self.validate_position_impl(
    range.end_line_number,
    range.end_column,
    false,
  )
  Range(start.line_number, start.column, end.line_number, end.column)
}

///|
/// Clamps a range into the document, expanding out of any surrogate pair its
/// ends land inside. Mirrors `validateRange` (`textModel.ts:1110`).
pub fn TextModel::validate_range(
  self : TextModel,
  range : @base_common.Range,
) -> @base_common.Range {
  let snapshot = self.snapshot
  let start = self.validate_position_impl(
    range.start_line_number,
    range.start_column,
    false,
  )
  let end = self.validate_position_impl(
    range.end_line_number,
    range.end_column,
    false,
  )
  let sl = start.line_number
  let sc = start.column
  let el = end.line_number
  let ec = end.column
  let char_before_start = if sc > 1 {
    snapshot.get_line_char_code(sl, sc - 2)
  } else {
    0
  }
  let char_before_end = if ec > 1 && ec <= snapshot.get_line_length(el) {
    snapshot.get_line_char_code(el, ec - 2)
  } else {
    0
  }
  let start_inside = @base_common.is_high_surrogate(char_before_start)
  let end_inside = @base_common.is_high_surrogate(char_before_end)
  if !start_inside && !end_inside {
    return Range(sl, sc, el, ec)
  }
  if sl == el && sc == ec {
    // do not expand a collapsed range, simply move it to a valid location
    return Range(sl, sc - 1, el, ec - 1)
  }
  if start_inside && end_inside {
    return Range(sl, sc - 1, el, ec + 1)
  }
  if start_inside {
    return Range(sl, sc - 1, el, ec)
  }
  Range(sl, sc, el, ec + 1)
}

///|
/// The current content version — `getVersionId` (`textModel.ts:737-740`);
/// init 1 (`:370`), bumped by every content change. The decoration trees
/// cache against it. `_assertNotDisposed`: N-A (readonly reads survive
/// dispose, see the region header).
pub fn TextModel::get_version_id(self : TextModel) -> Int {
  self.version_id
}

///|
/// `_increaseVersionId` (`textModel.ts:782-785`). The
/// `_alternativeVersionId` mirror is N-A (undo/redo not ported).
fn TextModel::increase_version_id(self : TextModel) -> Unit {
  self.version_id = self.version_id + 1
}

///|
/// Position `offset` UTF-16 code units away from `position`, clamped to the
/// document. Mirrors `modifyPosition` (`textModel.ts:1162`): relaxed-validate,
/// then offset round-trip.
pub fn TextModel::modify_position(
  self : TextModel,
  position : @base_common.Position,
  offset : Int,
) -> @base_common.Position {
  let valid = self.validate_position_impl(
    position.line_number,
    position.column,
    false,
  )
  let candidate = self.snapshot.get_offset_at(valid.line_number, valid.column) +
    offset
  let clamped = @base_common.clamp_int(candidate, 0, self.snapshot.get_length())
  self.snapshot.get_position_at(clamped)
}

// #endregion

// #region setValue flush lane (textModel.ts:457-545) — plan
// `monaco-set-value-api-port.md`. Scope cuts recorded there: no undo stack
// (`_commandManager.clear`, `:531`), no `setEOL` lane (`:547+`), no
// bracket-pair/font-token parts (`:473-474`), no incremental (tier-2) lane.

///|
/// Subscribes to content changes — `onDidChangeContent` (`textModel.ts:
/// 245-247`), unwrapping the internal event to its public payload.
pub fn TextModel::on_did_change_content(
  self : TextModel,
  listener : (ModelContentChangedEvent) -> Unit,
) -> @base_common.Disposable {
  self.event_emitter.event(e => listener(e.content_changed_event))
}

///|
/// Whole-buffer equality against another snapshot — `equalsTextBuffer`
/// (`textModel.ts:457-460`). The host-side no-op early return before a
/// refresh belongs to the caller (`modelService.ts:370-373`).
pub fn TextModel::equals_text_snapshot(
  self : TextModel,
  other : TextSnapshot,
) -> Bool {
  self.snapshot.equals(other)
}

///|
/// Replaces the whole content in place — `setValue` (`textModel.ts:484-493`):
/// build the new buffer, then flush. The same model (and its registered view
/// models) survives; all decorations are destroyed and the version bumps.
/// The `null | undefined` argument guard is N-A (non-nullable `String`);
/// `EditSources.setValue()` reasons are not ported (event deviation).
pub fn TextModel::set_value(self : TextModel, value : String) -> Unit {
  // _assertNotDisposed: N-A (the immutable snapshot stays readable after
  // dispose; see the Reading region header).
  self.set_value_from_snapshot(TextSnapshot(value))
}

///|
/// `_createContentChanged2` (`textModel.ts:495-512`). `rangeEndPosition` is
/// accepted-and-unused in the source too; `detailedReasons` are not ported
/// (`text_model_events.mbt` header).
fn TextModel::create_content_changed_2(
  self : TextModel,
  range : @base_common.Range,
  range_offset : Int,
  range_length : Int,
  _range_end_position : @base_common.Position,
  text : String,
  is_undoing : Bool,
  is_redoing : Bool,
  is_flush : Bool,
  is_eol_change : Bool,
) -> ModelContentChangedEvent {
  {
    changes: [{ range, range_offset, range_length, text }],
    // `this._buffer.getEOL()`: read from the newly installed snapshot.
    eol: self.get_eol(),
    is_eol_change,
    version_id: self.get_version_id(),
    is_undoing,
    is_redoing,
    is_flush,
  }
}

///|
/// `_setValueFromTextBuffer` (`textModel.ts:514-545`): capture the old full
/// range/length, swap the buffer, bump the version, destroy all decorations,
/// and emit `[ModelRawFlush]` plus the full-range public change
/// (`isFlush: true`). `_bufferDisposable` is N-A (GC); the undo-stack and
/// trim-whitespace clears (`:531-532`) are N-A (no edit stack).
fn TextModel::set_value_from_snapshot(
  self : TextModel,
  snapshot : TextSnapshot,
) -> Unit {
  let old_full_model_range = self.get_full_model_range()
  let old_model_value_length = self.get_value_length_in_range(
    old_full_model_range,
  )
  let end_line_number = self.get_line_count()
  let end_column = self.get_line_max_column(end_line_number)
  self.snapshot = snapshot
  // Synchronize shared live state before token content handling.
  self.tokenization_state.snapshot.val = snapshot
  self.increase_version_id()

  // Destroy all my decorations
  self.decorations = Map([])
  self.decorations_tree = DecorationsTrees::new()
  self.emit_content_changed_event(
    {
      changes: [ModelRawFlush],
      version_id: self.version_id,
      is_undoing: false,
      is_redoing: false,
    },
    self.create_content_changed_2(
      Range(1, 1, end_line_number, end_column),
      0,
      old_model_value_length,
      Position(end_line_number, end_column),
      self.get_value(),
      false,
      false,
      true,
      false,
    ),
  )
}

///|
/// `_emitContentChangedEvent` (`textModel.ts:467-482`). Call order is the
/// contract: tokenization part first, then the registered view models
/// (two-loop dispatch), then the public emitter. The bracket-pair and
/// font-token parts (`:473-474`) are N-A (not ported); `resultingSelection`
/// (`:476-479`) drops with the unported field (`text_model_events.mbt`).
fn TextModel::emit_content_changed_event(
  self : TextModel,
  raw_change : ModelRawContentChangedEvent,
  change : ModelContentChangedEvent,
) -> Unit {
  if self.tokenization_state.disposing.val {
    // Do not confuse listeners by emitting any event after disposing
    return
  }
  // The shared model state already sees the replacement snapshot. The part only
  // needs the flush fact (`tokenizationTextModelPart.ts:136-165`).
  self.tokenization.handle_did_change_content(is_flush=change.is_flush)
  let content_change_event : InternalModelContentChangeEvent = {
    raw_content_changed_event: raw_change,
    content_changed_event: change,
  }
  self.on_did_change_content_or_injected_text(content_change_event)
  self.event_emitter.fire(content_change_event)
}

// #endregion

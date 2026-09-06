// 1:1 port of the model content-change event types from
// vscode/src/vs/editor/common/textModelEvents.ts (checked-in vscode submodule), plus `DidChangeContentEmitter`
// (`textModel.ts:2698-2743`) and the registered-view-model seam
// (`textModel.ts:303,449-455,1652-1667`). Only the `Flush` raw change is
// constructed today (`TextModel::set_value`); the full raw-change union is
// kept so the tier-2 incremental lane (plan
// `monaco-set-value-api-port.md`, scope cut 5) slots in without reshaping.
//
// Deviations:
// - `ModelRawContentChangedEvent.resultingSelection` (`textModelEvents.ts:473`)
//   is not ported: `Selection` lives above this package (`viewer/common/core`,
//   MoonBit no-cycle rule), and the readonly flush lane always carries `null`
//   (only `pushEditOperations` sets it). `DidChangeContentEmitter
//   .endDeferredEmit`'s `resultingSelection` write drops with it.
// - `LineInjectedText` and `ModelInjectedTextChangedEvent`
//   (`textModelEvents.ts:241-302,506-513`) are not ported: the viewer's
//   injected-text lane is the whole-document reproject through the
//   decorations listener (`attach_model.mbt`), not per-line events.
// - `IModelContentChangedEvent.detailedReasons`/`detailedReasonsChangeLengths`
//   (`textModelEvents.ts:78-84`) are not ported (`TextModelEditSource` is an
//   editing-telemetry type with no readonly consumer).
// - `ModelLineHeightChanged*`/`ModelFontChanged*` events: N-A (line-height/
//   font decoration features not ported, see `text_model_decorations.mbt`).

///|
/// `DidChangeContentEmitter::{begin,end}_deferred_emit` are the tier-2
/// deferred-emit seam (`textModel.ts:2716-2730`; Monaco brackets them around
/// `pushEditOperations`), consumed only by `set_value_wbtest.mbt` today;
/// anchor them so the non-test build keeps them (the `moon explain 1`
/// idiom, same as `text_model_decorations.mbt`).
let _test_only_content_emitter_anchor : Unit = ignore(
  (
    DidChangeContentEmitter::begin_deferred_emit,
    DidChangeContentEmitter::end_deferred_emit,
  ),
)

///|
/// `RawContentChangedType` (`textModelEvents.ts:221-227`). The source's
/// numeric const-enum values (1-5) are not observable through this port;
/// identity is by constructor.
pub(all) enum RawContentChangedType {
  Flush
  LineChanged
  LinesDeleted
  LinesInserted
  EOLChanged
} derive(Eq, Debug)

///|
/// The `ModelRawChange` union (`textModelEvents.ts:451`): `ModelRawFlush`
/// (`:233`), `ModelRawLineChanged` (`:308`), `ModelRawLinesDeleted` (`:380`),
/// `ModelRawLinesInserted` (`:406`), `ModelRawEOLChanged` (`:444`), with each
/// class's fields as labeled payloads.
#warnings("-unused_constructor")
pub enum ModelRawChange {
  ModelRawFlush
  ModelRawLineChanged(line_number~ : Int, line_number_post_edit~ : Int)
  ModelRawLinesDeleted(
    from_line_number~ : Int,
    to_line_number~ : Int,
    last_untouched_line_post_edit~ : Int
  )
  ModelRawLinesInserted(
    from_line_number~ : Int,
    from_line_number_post_edit~ : Int,
    count~ : Int
  )
  ModelRawEOLChanged
} derive(Debug)

///|
/// Each class's `changeType` member (`textModelEvents.ts:234,309,381,407,445`).
fn ModelRawChange::change_type(self : ModelRawChange) -> RawContentChangedType {
  match self {
    ModelRawFlush => Flush
    ModelRawLineChanged(..) => LineChanged
    ModelRawLinesDeleted(..) => LinesDeleted
    ModelRawLinesInserted(..) => LinesInserted
    ModelRawEOLChanged => EOLChanged
  }
}

///|
/// `ModelRawContentChangedEvent` (`textModelEvents.ts:457-500`) minus
/// `resultingSelection` (file-header deviation).
pub struct ModelRawContentChangedEvent {
  changes : Array[ModelRawChange]
  /// The new version id the model has transitioned to.
  version_id : Int
  is_undoing : Bool
  is_redoing : Bool
} derive(Debug)

///|
/// `containsEvent` (`textModelEvents.ts:483-491`).
pub fn ModelRawContentChangedEvent::contains_event(
  self : ModelRawContentChangedEvent,
  change_type : RawContentChangedType,
) -> Bool {
  self.changes.any(change => change.change_type() == change_type)
}

///|
/// `ModelRawContentChangedEvent.merge` (`textModelEvents.ts:493-499`).
fn ModelRawContentChangedEvent::merge(
  a : ModelRawContentChangedEvent,
  b : ModelRawContentChangedEvent,
) -> ModelRawContentChangedEvent {
  {
    changes: a.changes + b.changes,
    version_id: b.version_id,
    is_undoing: a.is_undoing || b.is_undoing,
    is_redoing: a.is_redoing || b.is_redoing,
  }
}

///|
/// The public `IModelContentChangedEvent` (`textModelEvents.ts:42-85`) minus
/// `detailedReasons`/`detailedReasonsChangeLengths` (file-header deviation).
/// The I-prefix drops per the repo naming policy.
pub struct ModelContentChangedEvent {
  /// Ordered from the end of the document to the beginning.
  changes : Array[ModelContentChange]
  /// The (new) end-of-line character.
  eol : String
  /// The new version id the model has transitioned to.
  version_id : Int
  is_undoing : Bool
  is_redoing : Bool
  /// All decorations were lost with this edit; the model was reset.
  is_flush : Bool
  is_eol_change : Bool
} derive(Debug)

///|
/// `InternalModelContentChangeEvent` (`textModelEvents.ts:562-594`).
pub struct InternalModelContentChangeEvent {
  raw_content_changed_event : ModelRawContentChangedEvent
  content_changed_event : ModelContentChangedEvent
} derive(Debug)

///|
/// `InternalModelContentChangeEvent.merge` (`textModelEvents.ts:568-572`).
fn InternalModelContentChangeEvent::merge(
  self : InternalModelContentChangeEvent,
  other : InternalModelContentChangeEvent,
) -> InternalModelContentChangeEvent {
  {
    raw_content_changed_event: ModelRawContentChangedEvent::merge(
      self.raw_content_changed_event,
      other.raw_content_changed_event,
    ),
    content_changed_event: merge_change_events(
      self.content_changed_event,
      other.content_changed_event,
    ),
  }
}

///|
/// `_mergeChangeEvents` (`textModelEvents.ts:574-593`), minus the
/// `detailedReasons` concatenation (fields not ported).
fn merge_change_events(
  a : ModelContentChangedEvent,
  b : ModelContentChangedEvent,
) -> ModelContentChangedEvent {
  {
    changes: a.changes + b.changes,
    eol: b.eol,
    version_id: b.version_id,
    is_undoing: a.is_undoing || b.is_undoing,
    is_redoing: a.is_redoing || b.is_redoing,
    is_flush: a.is_flush || b.is_flush,
    // both must be true to not confuse listeners who skip such edits
    is_eol_change: a.is_eol_change && b.is_eol_change,
  }
}

// #region DidChangeContentEmitter (textModel.ts:2698-2743)

///|
/// `DidChangeContentEmitter` (`textModel.ts:2698`): defers and merges
/// content-change events inside a deferred-emit bracket. `hasListeners`
/// (`:2712`) is N-A (no consumer in the ported slices); `endDeferredEmit`'s
/// `resultingSelection` write drops with the unported field (file header).
struct DidChangeContentEmitter {
  emitter : @base_common.Emitter[InternalModelContentChangeEvent]
  mut deferred_cnt : Int
  mut deferred_event : InternalModelContentChangeEvent?
}

///|
fn DidChangeContentEmitter::DidChangeContentEmitter() -> DidChangeContentEmitter {
  { emitter: Emitter(), deferred_cnt: 0, deferred_event: None, }
}

///|
fn DidChangeContentEmitter::event(
  self : DidChangeContentEmitter,
  listener : (InternalModelContentChangeEvent) -> Unit,
) -> @base_common.Disposable {
  self.emitter.event(listener)
}

///|
fn DidChangeContentEmitter::begin_deferred_emit(
  self : DidChangeContentEmitter,
) -> Unit {
  self.deferred_cnt += 1
}

///|
/// `endDeferredEmit` (`textModel.ts:2720-2730`).
fn DidChangeContentEmitter::end_deferred_emit(
  self : DidChangeContentEmitter,
) -> Unit {
  self.deferred_cnt -= 1
  if self.deferred_cnt == 0 {
    if self.deferred_event is Some(e) {
      self.deferred_event = None
      self.emitter.fire(e)
    }
  }
}

///|
/// `fire` (`textModel.ts:2732-2742`): merge into the deferred slot while a
/// bracket is open, emit immediately otherwise.
fn DidChangeContentEmitter::fire(
  self : DidChangeContentEmitter,
  e : InternalModelContentChangeEvent,
) -> Unit {
  if self.deferred_cnt > 0 {
    match self.deferred_event {
      Some(deferred) => self.deferred_event = Some(deferred.merge(e))
      None => self.deferred_event = Some(e)
    }
    return
  }
  self.emitter.fire(e)
}

// #endregion

// #region Registered view models (textModel.ts:303,449-455,1652-1667)

///|
/// The two callbacks the text model invokes for one registered view model.
/// Keeping this record private preserves the package direction
/// `view_model -> model` without turning Monaco's erased `IViewModel` type
/// edge into a MoonBit trait object. `active` is shared with the returned
/// registration handle so disposal can remove exactly this entry without
/// object-identity comparison.
priv struct ViewModelCallbacks {
  active : Ref[Bool]
  on_did_change_content_or_injected_text : (InternalModelContentChangeEvent) -> Unit
  emit_content_change_event : (InternalModelContentChangeEvent) -> Unit
}

///|
/// `registerViewModel` (`textModel.ts:449-451`) as a callback registration.
/// The returned idempotent handle owns the matching `unregisterViewModel`
/// lifetime (`:453-455`); callers never compare or retain trait-object boxes.
pub fn TextModel::register_view_model(
  self : TextModel,
  on_did_change_content_or_injected_text : (InternalModelContentChangeEvent) -> Unit,
  emit_content_change_event : (InternalModelContentChangeEvent) -> Unit,
) -> @base_common.Disposable {
  let active = Ref(true)
  self.view_models.push({
    active,
    on_did_change_content_or_injected_text,
    emit_content_change_event,
  })
  @base_common.Disposable::from(() => {
    active.val = false
    self.view_models.retain(callbacks => callbacks.active.val)
  })
}

///|
/// `_onDidChangeContentOrInjectedText` (`textModel.ts:1652-1667`). The
/// two-loop order is load-bearing: every view model applies its structural
/// update before any emits outgoing events or updates its cursor, so no
/// listener observes a torn state. The source's per-call
/// `try/catch onUnexpectedError` is unreachable (MoonBit callbacks here are
/// non-raising — same deviation as `change_decorations`).
fn TextModel::on_did_change_content_or_injected_text(
  self : TextModel,
  e : InternalModelContentChangeEvent,
) -> Unit {
  for callbacks in self.view_models {
    (callbacks.on_did_change_content_or_injected_text)(e)
  }
  for callbacks in self.view_models {
    (callbacks.emit_content_change_event)(e)
  }
}

// #endregion

///|
pub extend InternalModelContentChangeEvent with Debug::{to_repr}

///|
pub extend ModelContentChangedEvent with Debug::{to_repr}

///|
pub extend ModelRawChange with Debug::{to_repr}

///|
pub extend ModelRawContentChangedEvent with Debug::{to_repr}

///|
pub extend RawContentChangedType with Debug::{to_repr}

///|
pub extend RawContentChangedType with Eq::{equal, not_equal}

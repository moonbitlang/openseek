// Port of `vscode/src/vs/editor/contrib/folding/browser/folding.ts` (vscode
// checked-in submodule): the contracts
// other folding files consume — `FoldingLimitReporter`,
// `SelectedLines`, `toSelectedLines` — and the `FoldingController`'s state.
//
// Structural deviation: the controller's *state* lives here and is owned by
// the root Viewer's central contribution registry. Event-handler bodies that
// need private Viewer state and root-owned model/input wiring
// (`onModelChanged`, `onHiddenRangesChanges`, the mouse handlers, and the
// actions) remain `Viewer::` glue in the root package
// (`viewer/folding_host.mbt` / `viewer/folding_contribution.mbt`). This keeps
// the internal folding package independent of the root Viewer.
//
// Omissions: the syntax range provider (`SyntaxRangeProvider` — no folding
// range providers in the language registry yet), `foldingImportsByDefault`
// (needs provider kinds), and the update `Delayer`/debounce (the viewer
// computes synchronously). Folding view-state persistence is retained.

///|
/// The supported subset of Monaco's `FoldingStateMemento`
/// (`folding.ts:54-59`). Provider identity and folded-import state are absent
/// with those unported features; `line_count` remains part of the persisted
/// shape for source fidelity.
struct FoldingStateMemento {
  collapsed_regions : Array[FoldingLineMemento]?
  line_count : Int?
} derive(Debug)

///|
/// Receives how many ranges a provider computed and whether the limit
/// truncated them — Monaco's `FoldingLimitReporter` (`folding.ts`). `update`
/// takes the computed count and the applied limit, `None` standing for the
/// source's `false` ("not limited").
pub(all) struct FoldingLimitReporter {
  limit : () -> Int
  update : (Int, Int?) -> Unit
}

///|
/// The selection probe `sanitizeAndMerge` consults to keep a shrunk region
/// expanded while the user is editing inside it — Monaco's `SelectedLines`
/// (`folding.ts`): whether any selection starts within the given inclusive
/// line range.
struct SelectedLines {
  starts_inside : (Int, Int) -> Bool
}

///|
/// `toSelectedLines` (`folding.ts:591`).
pub fn to_selected_lines(selections : Array[@core.Selection]) -> SelectedLines {
  if selections.length() == 0 {
    return { starts_inside: (_start_line, _end_line) => false, }
  }
  {
    starts_inside: (start_line, end_line) => {
      selections.any(s => {
        let line = s.start().line_number
        line >= start_line && line <= end_line
      })
    },
  }
}

///|
/// `FoldingController.ID` (`folding.ts:70`).
pub const FOLDING_CONTROLLER_ID : String = "editor.contrib.folding"

///|
/// The controller's `mouseDownInfo` (`folding.ts:112`).
pub(all) struct FoldingMouseDownInfo {
  line_number : Int
  icon_clicked : Bool
}

///|
/// The per-editor folding state — the fields of Monaco's `FoldingController`
/// (`folding.ts:68`). The editor-facing behavior lives in the root package's
/// `Viewer::` glue (see the header).
pub(all) struct FoldingController {
  mut folding_model : FoldingModel?
  mut hidden_range_model : HiddenRangeModel?
  mut folding_decoration_provider : FoldingDecorationProvider?
  mut range_provider : IndentRangeProvider?
  mut mouse_down_info : FoldingMouseDownInfo?
  mut restoring_view_state : Bool
  /// The model-scoped subscriptions of `localToDispose`.
  local_to_dispose : Array[@base_common.Disposable]
}

///|
/// Creates the bare controller stored by this editor's central contribution
/// entry.
pub fn FoldingController::FoldingController() -> FoldingController {
  {
    folding_model: None,
    hidden_range_model: None,
    folding_decoration_provider: None,
    range_provider: None,
    mouse_down_info: None,
    restoring_view_state: false,
    local_to_dispose: [],
  }
}

///|
/// `saveViewState` (`folding.ts:188-202`) reduced to the supported folding
/// state. `None` means no live folding model was available.
pub fn FoldingController::save_view_state(
  self : FoldingController,
) -> FoldingStateMemento? {
  guard self.folding_model is Some(folding_model) else { return None }
  Some({
    collapsed_regions: folding_model.get_memento(),
    line_count: Some(folding_model.text_model().get_line_count()),
  })
}

///|
/// `restoreViewState` (`folding.ts:204-225`). The restoring flag prevents the
/// hidden-range listener from moving a selection while persisted folds are
/// being applied.
pub fn FoldingController::restore_view_state(
  self : FoldingController,
  state : FoldingStateMemento,
) -> Unit {
  guard state.collapsed_regions is Some(collapsed_regions) &&
    !collapsed_regions.is_empty() &&
    self.folding_model is Some(folding_model) else {
    return
  }
  self.restoring_view_state = true
  folding_model.apply_memento(collapsed_regions)
  self.restoring_view_state = false
}

///|
/// Clears the model-scoped state — `localToDispose.clear()` plus the inline
/// dispose block of `onModelChanged` (`folding.ts:255-270`), in the store's
/// insertion order: the models first (the hidden-range model's dispose
/// fires an empty range set through the still-live listener, clearing the
/// editor's hidden areas), then the subscriptions.
pub fn FoldingController::clear_local(self : FoldingController) -> Unit {
  match self.folding_model {
    Some(folding_model) => folding_model.dispose()
    None => ()
  }
  self.folding_model = None
  match self.hidden_range_model {
    Some(hidden_range_model) => hidden_range_model.dispose()
    None => ()
  }
  self.hidden_range_model = None
  for disposable in self.local_to_dispose {
    disposable.dispose()
  }
  self.local_to_dispose.clear()
  match self.range_provider {
    Some(provider) => provider.dispose()
    None => ()
  }
  self.range_provider = None
  self.folding_decoration_provider = None
  self.mouse_down_info = None
  self.restoring_view_state = false
}

///|
#deprecated("Use `Debug::to_repr` via the trait or `Repr(value)` instead", skip_current_package=true)
#doc(hidden)
pub extend FoldingStateMemento with Debug::{to_repr}

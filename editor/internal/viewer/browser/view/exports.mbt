// Explicit staged browser-view contracts. These closed enums contain source
// compatibility cases that are not all exercised by current production
// callers; keeping their definitions here makes that exception visible to
// `moon ide analyze`.

///|
/// Monaco `ContentWidgetPositionPreference` (`editorBrowser.ts`). `Exact` is
/// retained for the staged exact-coordinate widget contract.
pub(all) enum ContentWidgetPositionPreference {
  Above
  Below
  Exact
} derive(Eq)

///|
/// `PartFingerprint` (`vscode/src/vs/editor/browser/view/viewPart.ts:34-46`).
/// Numeric order is load-bearing; reserved source slots remain present even
/// when the readonly viewer does not currently create those parts.
pub(all) enum PartFingerprint {
  None
  ContentWidgets
  OverflowingContentWidgets
  OverflowGuard
  OverlayWidgets
  OverflowingOverlayWidgets
  ScrollableElement
  TextArea
  ViewLines
  Minimap
  ViewLinesGpu
} derive(Eq, Debug)

///|
/// Monaco-shaped option identifiers queried by browser view parts. The root
/// Viewer currently emits a subset; the remaining identifiers preserve the
/// staged configuration-change contract.
pub(all) enum ViewConfigurationOption {
  LayoutInfo
  FontInfo
  LineHeight
  WrappingInfo
  RevealHorizontalRightPadding
  CursorSurroundingLines
  CursorSurroundingLinesStyle
  DisableLayerHinting
  StickyScroll
  RenderWhitespace
  RenderControlCharacters
  RenderLineHighlight
  RenderLineHighlightOnlyWhenFocus
  RenderValidationDecorations
  ReadOnly
  CursorBlinking
  EffectiveCursorStyle
  CursorSmoothCaretAnimation
  EffectiveEditContext
} derive(Eq, Debug)

///|
/// Closed readonly-view event union. `ViewZonesChanged` remains part of the
/// staged source-shaped dispatcher contract even though it is currently
/// produced and consumed within this package.
pub(all) enum ViewEvent {
  ViewConfigurationChanged(ViewConfigurationChangedEvent)
  ViewCursorStateChanged(ViewCursorStateChangedEvent)
  ViewDecorationsChanged
  ViewFlushed
  ViewFocusChanged(ViewFocusChangedEvent)
  ViewLineMappingChanged
  ViewScrollChanged(ViewScrollChangedEvent)
  ViewTokensChanged(ViewTokensChangedEvent)
  ViewZonesChanged
}

///|
pub extend ContentWidgetPositionPreference with Eq::{equal, not_equal}

///|
pub extend PartFingerprint with Debug::{to_repr}

///|
pub extend PartFingerprint with Eq::{equal, not_equal}

///|
pub extend ViewConfigurationOption with Debug::{to_repr}

///|
pub extend ViewConfigurationOption with Eq::{equal, not_equal}

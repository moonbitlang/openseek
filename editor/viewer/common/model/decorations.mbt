///|
/// How a decoration's range grows when text is typed at its edges,
/// `TrackedRangeStickiness` (`model.ts`). Inert in the readonly viewer; carried
/// for fidelity.
pub(all) enum TrackedRangeStickiness {
  AlwaysGrowsWhenTypingAtEdges
  NeverGrowsWhenTypingAtEdges
  GrowsOnlyWhenTypingBefore
  GrowsOnlyWhenTypingAfter
} derive(Eq, Debug)

///|
/// Numeric value of the stickiness, matching Monaco's
/// `TrackedRangeStickiness` enum values (`model.ts`) — the interval tree
/// packs it into the node metadata byte.
fn TrackedRangeStickiness::to_int(self : TrackedRangeStickiness) -> Int {
  match self {
    AlwaysGrowsWhenTypingAtEdges => 0
    NeverGrowsWhenTypingAtEdges => 1
    GrowsOnlyWhenTypingBefore => 2
    GrowsOnlyWhenTypingAfter => 3
  }
}

///|
/// Overview-ruler lane, `OverviewRulerLane` (`model.ts`).
pub(all) enum OverviewRulerLane {
  Left
  Center
  Right
  Full
} derive(Eq, Debug)

///|
/// Minimap decoration position, `MinimapPosition` (`model.ts`).
pub(all) enum MinimapPosition {
  Inline
  Gutter
} derive(Eq, Debug)

///|
/// Overview-ruler decoration options, `IModelDecorationOverviewRulerOptions`.
/// `color` is a theme-color id (`themeColorFromId`), carried inert (no overview
/// ruler part paints it — plan D4).
pub(all) struct ModelDecorationOverviewRulerOptions {
  color : String?
  position : OverviewRulerLane
} derive(Eq, Debug)

///|
/// Minimap decoration options, `IModelDecorationMinimapOptions`. `color` is a
/// theme-color id, carried inert (plan D4).
pub(all) struct ModelDecorationMinimapOptions {
  color : String
  position : MinimapPosition
} derive(Eq, Debug)

///|
/// `cleanClassName` (`textModel.ts:2355-2357`): `[^a-z0-9\-_]/gi → ' '`,
/// applied per UTF-16 code unit like the JS regex (no /u flag).
fn clean_class_name(class_name : String) -> String {
  let sb = StringBuilder()
  for unit in class_name.code_units() {
    if unit is ('a'..='z' | 'A'..='Z' | '0'..='9' | '-' | '_') {
      sb.write_char(unit.to_int().unsafe_to_char())
    } else {
      sb.write_char(' ')
    }
  }
  sb.to_string()
}

///|
/// The `ModelDecorationOptions` subset (`textModel.ts:2478-2580`). Monaco
/// field mapping: `class_name` = `className` ("" = undefined), `message` =
/// `hoverMessage`, `inline_class_name` = `inlineClassName`, the rest keep
/// their names.
///
/// Omitted `ModelDecorationOptions` fields (out of scope, plan
/// `monaco-decoration-system-port.md`): `blockClassName`/`blockIsAfterEnd`/
/// `blockDoesNotCollapse`/`blockPadding` (block decorations),
/// `lineNumberClassName`/`lineNumberHoverMessage`/`linesDecorationsTooltip`/
/// `glyphMarginHoverMessage` (no consumer), `hideInCommentTokens`/
/// `hideInStringTokens`, `lineHeight`/`fontSize`/`affectsFont` (font/line-
/// height decorations), `textDirection`, `glyphMargin` lane options (glyph
/// margin view part deferred). `overview_ruler`/`minimap` colors are carried
/// as strings — no theme-object resolution (recorded theming design).
pub struct ModelDecorationOptions {
  class_name : String
  message : String?
  inline_class_name : String?
  inline_class_name_affects_letter_spacing : Bool
  z_index : Int
  is_whole_line : Bool
  show_if_collapsed : Bool
  should_fill_line_on_line_break : Bool
  stickiness : TrackedRangeStickiness
  overview_ruler : ModelDecorationOverviewRulerOptions?
  minimap : ModelDecorationMinimapOptions?
  glyph_margin_class_name : String?
  lines_decorations_class_name : String?
  first_line_decoration_class_name : String?
  margin_class_name : String?
  /// CSS applied as an `::after` pseudo-element behind the range's last
  /// line — `afterContentClassName`. Folding's `inline-folded` "⋯" is the
  /// producer.
  after_content_class_name : String?
  collapse_on_replace_edit : Bool
  description : String
  /// Injected text rendered before/after the decoration range —
  /// `ModelDecorationOptions.before`/`after` (`InjectedTextOptions`,
  /// `model.ts`), stored in the interval tree's injected-text slot.
  before : InjectedTextOptions?
  after : InjectedTextOptions?
} derive(Debug)

///|
/// `InjectedTextOptions` at the model tier (`model.ts`): the rendered
/// content, its inline class, and the producer's attachment
/// (`attachedData`, reduced to a source index for injected-text consumers).
/// `cursorStops` is unported — the readonly viewer treats
/// every injection as `InjectedTextCursorStops.Both` (the default), see
/// `normalize_projected_column_around_injections`.
struct InjectedTextOptions {
  content : String
  inline_class_name : String?
  /// `attachedData` reduced to a producer-defined index (`-1` = none), carried
  /// through the projection into hit-testing lookup.
  attached_index : Int
} derive(Debug, Eq)

///|
/// A (range, options) pair handed to `TextModel::delta_decorations` —
/// Monaco's `IModelDeltaDecoration`.
pub(all) struct ModelDeltaDecoration {
  range : @base_common.Range
  options : ModelDecorationOptions
} derive(Debug)

///|
/// A decoration query result — Monaco's `IModelDecoration` (id + ownerId +
/// range + options). Monaco returns the tree's `IntervalNode`s cast to this
/// interface; the port materializes value copies (same data, no aliasing).
pub(all) struct ModelDecoration {
  id : String
  owner_id : Int
  range : @base_common.Range
  options : ModelDecorationOptions
} derive(Debug)

///|
/// `IModelDecorationsChangedEvent` (`textModelEvents.ts`), fired by
/// `TextModel::on_did_change_decorations`.
pub struct ModelDecorationsChangedEvent {
  affects_minimap : Bool
  affects_overview_ruler : Bool
  affects_glyph_margin : Bool
  /// Whether the change touched injected-text (`before`/`after`) options —
  /// the viewer's whole-event stand-in for Monaco's per-line
  /// `onDidChangeContentOrInjectedText` (consumers rebuild the projection
  /// when set).
  affects_injected_text : Bool
  affects_line_number : Bool
} derive(Eq, Debug)

///|
/// The single decoration-options constructor. Monaco's `register`/
/// `createDynamic`/`_normalizeOptions` collapse into this one function (plan
/// Deviation 5 — `register` exists only to intern per-instance allocations).
/// Class names are normalized with `clean_class_name` like the
/// `ModelDecorationOptions` ctor; defaults mirror the source (`stickiness`
/// AlwaysGrows, `zIndex` 0). Direct record literals bypass the cleaning, like
/// nothing does in Monaco.
pub fn ModelDecorationOptions::ModelDecorationOptions(
  class_name : String,
  message? : String,
  inline_class_name? : String,
  inline_class_name_affects_letter_spacing? : Bool = false,
  z_index? : Int = 0,
  is_whole_line? : Bool = false,
  show_if_collapsed? : Bool = false,
  should_fill_line_on_line_break? : Bool = false,
  stickiness? : TrackedRangeStickiness = AlwaysGrowsWhenTypingAtEdges,
  overview_ruler? : ModelDecorationOverviewRulerOptions,
  minimap? : ModelDecorationMinimapOptions,
  glyph_margin_class_name? : String,
  lines_decorations_class_name? : String,
  first_line_decoration_class_name? : String,
  margin_class_name? : String,
  after_content_class_name? : String,
  collapse_on_replace_edit? : Bool = false,
  description? : String = "",
  before? : InjectedTextOptions,
  after? : InjectedTextOptions,
) -> ModelDecorationOptions {
  {
    class_name: clean_class_name(class_name),
    message,
    inline_class_name: inline_class_name.map(clean_class_name),
    inline_class_name_affects_letter_spacing,
    z_index,
    is_whole_line,
    show_if_collapsed,
    should_fill_line_on_line_break,
    stickiness,
    overview_ruler,
    minimap,
    glyph_margin_class_name: glyph_margin_class_name.map(clean_class_name),
    lines_decorations_class_name: lines_decorations_class_name.map(
      clean_class_name,
    ),
    first_line_decoration_class_name: first_line_decoration_class_name.map(
      clean_class_name,
    ),
    margin_class_name: margin_class_name.map(clean_class_name),
    after_content_class_name: after_content_class_name.map(clean_class_name),
    collapse_on_replace_edit,
    description,
    before,
    after,
  }
}

///|
pub extend InjectedTextOptions with Debug::{to_repr}

///|
pub extend InjectedTextOptions with Eq::{equal, not_equal}

///|
pub extend MinimapPosition with Debug::{to_repr}

///|
pub extend MinimapPosition with Eq::{equal, not_equal}

///|
pub extend ModelDecoration with Debug::{to_repr}

///|
pub extend ModelDecorationMinimapOptions with Debug::{to_repr}

///|
pub extend ModelDecorationMinimapOptions with Eq::{equal, not_equal}

///|
pub extend ModelDecorationOptions with Debug::{to_repr}

///|
pub extend ModelDecorationOverviewRulerOptions with Debug::{to_repr}

///|
pub extend ModelDecorationOverviewRulerOptions with Eq::{equal, not_equal}

///|
pub extend ModelDecorationsChangedEvent with Debug::{to_repr}

///|
pub extend ModelDecorationsChangedEvent with Eq::{equal, not_equal}

///|
pub extend ModelDeltaDecoration with Debug::{to_repr}

///|
pub extend OverviewRulerLane with Debug::{to_repr}

///|
pub extend OverviewRulerLane with Eq::{equal, not_equal}

///|
pub extend TrackedRangeStickiness with Debug::{to_repr}

///|
pub extend TrackedRangeStickiness with Eq::{equal, not_equal}

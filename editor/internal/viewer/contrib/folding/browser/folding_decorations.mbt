// Port of `vscode/src/vs/editor/contrib/folding/browser/foldingDecorations.ts`
// (checked-in vscode submodule): the
// `FoldingDecorationProvider` and its registered decoration options. The
// chevron renders through `firstLineDecorationClassName` (the line-numbers
// side `.cldr` lane), the collapsed `⋯` through `afterContentClassName:
// "inline-folded"`, and the folded highlight through `className:
// "folded-background"`; icon classes carry the codicon codepoints from
// `codicon.css` (`ThemeIcon.asClassName(registerIcon(...))` in the source).
//
// Omissions: `minimap` options (no minimap part), `linesDecorationsTooltip`
// (decoration tooltips are unported), and the `registerColor` calls (theme
// colors live as CSS variables in `folding.css`/`theme.css`).

///|
/// `ThemeIcon.asClassName(foldingExpandedIcon)`.
const FOLDING_EXPANDED_ICON_CLASS : String = "codicon codicon-folding-expanded"

///|
/// `ThemeIcon.asClassName(foldingCollapsedIcon)`.
const FOLDING_COLLAPSED_ICON_CLASS : String = "codicon codicon-folding-collapsed"

///|
/// `ThemeIcon.asClassName(foldingManualCollapsedIcon)` (an alias of the
/// collapsed icon).
const FOLDING_MANUAL_COLLAPSED_ICON_CLASS : String = "codicon codicon-folding-manual-collapsed"

///|
/// `ThemeIcon.asClassName(foldingManualExpandedIcon)` (an alias of the
/// expanded icon).
const FOLDING_MANUAL_EXPANDED_ICON_CLASS : String = "codicon codicon-folding-manual-expanded"

///|
/// `COLLAPSED_VISUAL_DECORATION`.
let collapsed_visual_decoration : @model.ModelDecorationOptions = ModelDecorationOptions(
  "",
  description="folding-collapsed-visual-decoration",
  stickiness=AlwaysGrowsWhenTypingAtEdges,
  after_content_class_name="inline-folded",
  is_whole_line=true,
  first_line_decoration_class_name=FOLDING_COLLAPSED_ICON_CLASS,
)

///|
/// `COLLAPSED_HIGHLIGHTED_VISUAL_DECORATION`.
let collapsed_highlighted_visual_decoration : @model.ModelDecorationOptions = ModelDecorationOptions(
  "folded-background",
  description="folding-collapsed-highlighted-visual-decoration",
  stickiness=AlwaysGrowsWhenTypingAtEdges,
  after_content_class_name="inline-folded",
  is_whole_line=true,
  first_line_decoration_class_name=FOLDING_COLLAPSED_ICON_CLASS,
)

///|
/// A collapsed host outline whose visible line already ends at the body
/// delimiter. A quiet inline suffix completes the hidden body as `{ … }`.
let collapsed_outline_body_visual_decoration : @model.ModelDecorationOptions = ModelDecorationOptions(
  "",
  description="folding-collapsed-outline-body-visual-decoration",
  stickiness=AlwaysGrowsWhenTypingAtEdges,
  after_content_class_name="inline-folded-body",
  is_whole_line=true,
  first_line_decoration_class_name=FOLDING_COLLAPSED_ICON_CLASS,
)

///|
let collapsed_outline_body_highlighted_visual_decoration : @model.ModelDecorationOptions = ModelDecorationOptions(
  "folded-background",
  description="folding-collapsed-outline-body-highlighted-visual-decoration",
  stickiness=AlwaysGrowsWhenTypingAtEdges,
  after_content_class_name="inline-folded-body",
  is_whole_line=true,
  first_line_decoration_class_name=FOLDING_COLLAPSED_ICON_CLASS,
)

///|
/// `MANUALLY_COLLAPSED_VISUAL_DECORATION`.
let manually_collapsed_visual_decoration : @model.ModelDecorationOptions = ModelDecorationOptions(
  "",
  description="folding-manually-collapsed-visual-decoration",
  stickiness=AlwaysGrowsWhenTypingAtEdges,
  after_content_class_name="inline-folded",
  is_whole_line=true,
  first_line_decoration_class_name=FOLDING_MANUAL_COLLAPSED_ICON_CLASS,
)

///|
/// `MANUALLY_COLLAPSED_HIGHLIGHTED_VISUAL_DECORATION`.
let manually_collapsed_highlighted_visual_decoration : @model.ModelDecorationOptions = ModelDecorationOptions(
  "folded-background",
  description="folding-manually-collapsed-highlighted-visual-decoration",
  stickiness=AlwaysGrowsWhenTypingAtEdges,
  after_content_class_name="inline-folded",
  is_whole_line=true,
  first_line_decoration_class_name=FOLDING_MANUAL_COLLAPSED_ICON_CLASS,
)

///|
/// `NO_CONTROLS_COLLAPSED_RANGE_DECORATION`.
let no_controls_collapsed_range_decoration : @model.ModelDecorationOptions = ModelDecorationOptions(
  "",
  description="folding-no-controls-range-decoration",
  stickiness=AlwaysGrowsWhenTypingAtEdges,
  after_content_class_name="inline-folded",
  is_whole_line=true,
)

///|
/// `NO_CONTROLS_COLLAPSED_HIGHLIGHTED_RANGE_DECORATION`.
let no_controls_collapsed_highlighted_range_decoration : @model.ModelDecorationOptions = ModelDecorationOptions(
  "folded-background",
  description="folding-no-controls-range-decoration",
  stickiness=AlwaysGrowsWhenTypingAtEdges,
  after_content_class_name="inline-folded",
  is_whole_line=true,
)

///|
let no_controls_collapsed_outline_body_range_decoration : @model.ModelDecorationOptions = ModelDecorationOptions(
  "",
  description="folding-no-controls-outline-body-range-decoration",
  stickiness=AlwaysGrowsWhenTypingAtEdges,
  after_content_class_name="inline-folded-body",
  is_whole_line=true,
)

///|
let no_controls_collapsed_outline_body_highlighted_range_decoration : @model.ModelDecorationOptions = ModelDecorationOptions(
  "folded-background",
  description="folding-no-controls-outline-body-range-decoration",
  stickiness=AlwaysGrowsWhenTypingAtEdges,
  after_content_class_name="inline-folded-body",
  is_whole_line=true,
)

///|
/// `EXPANDED_VISUAL_DECORATION`.
let expanded_visual_decoration : @model.ModelDecorationOptions = ModelDecorationOptions(
  "",
  description="folding-expanded-visual-decoration",
  stickiness=NeverGrowsWhenTypingAtEdges,
  is_whole_line=true,
  first_line_decoration_class_name="alwaysShowFoldIcons \{FOLDING_EXPANDED_ICON_CLASS}",
)

///|
/// `EXPANDED_AUTO_HIDE_VISUAL_DECORATION`.
let expanded_auto_hide_visual_decoration : @model.ModelDecorationOptions = ModelDecorationOptions(
  "",
  description="folding-expanded-auto-hide-visual-decoration",
  stickiness=NeverGrowsWhenTypingAtEdges,
  is_whole_line=true,
  first_line_decoration_class_name=FOLDING_EXPANDED_ICON_CLASS,
)

///|
/// `MANUALLY_EXPANDED_VISUAL_DECORATION`.
let manually_expanded_visual_decoration : @model.ModelDecorationOptions = ModelDecorationOptions(
  "",
  description="folding-manually-expanded-visual-decoration",
  stickiness=AlwaysGrowsWhenTypingAtEdges,
  is_whole_line=true,
  first_line_decoration_class_name="alwaysShowFoldIcons \{FOLDING_MANUAL_EXPANDED_ICON_CLASS}",
)

///|
/// `MANUALLY_EXPANDED_AUTO_HIDE_VISUAL_DECORATION`.
let manually_expanded_auto_hide_visual_decoration : @model.ModelDecorationOptions = ModelDecorationOptions(
  "",
  description="folding-manually-expanded-auto-hide-visual-decoration",
  stickiness=AlwaysGrowsWhenTypingAtEdges,
  is_whole_line=true,
  first_line_decoration_class_name=FOLDING_MANUAL_EXPANDED_ICON_CLASS,
)

///|
/// `NO_CONTROLS_EXPANDED_RANGE_DECORATION`.
let no_controls_expanded_range_decoration : @model.ModelDecorationOptions = ModelDecorationOptions(
  "",
  description="folding-no-controls-range-decoration",
  stickiness=AlwaysGrowsWhenTypingAtEdges,
  is_whole_line=true,
)

///|
/// `HIDDEN_RANGE_DECORATION`.
let hidden_range_decoration : @model.ModelDecorationOptions = ModelDecorationOptions(
  "",
  description="folding-hidden-range-decoration",
  stickiness=NeverGrowsWhenTypingAtEdges,
)

///|
/// The folding decoration source — Monaco's `FoldingDecorationProvider`
/// (`foldingDecorations.ts:31`). The source holds an `ICodeEditor` whose
/// `changeDecorations`/`removeDecorations` delegate to the attached model
/// with the editor's id; the port holds that (model, owner id) pair
/// directly.
struct FoldingDecorationProvider {
  model : @model.TextModel
  owner_id : Int
  mut show_folding_controls : @editor_api.ShowFoldingControls
  mut show_folding_highlights : Bool
}

///|
pub fn FoldingDecorationProvider::FoldingDecorationProvider(
  model : @model.TextModel,
  owner_id? : Int = 0,
) -> FoldingDecorationProvider {
  {
    model,
    owner_id,
    show_folding_controls: Mouseover,
    show_folding_highlights: true,
  }
}

///|
/// The controller's option push — `folding.ts`'s direct
/// `foldingDecorationProvider.showFoldingControls = ...` assignments on
/// configuration changes.
pub fn FoldingDecorationProvider::update_options(
  self : FoldingDecorationProvider,
  show_folding_controls~ : @editor_api.ShowFoldingControls,
  show_folding_highlights~ : Bool,
) -> Unit {
  self.show_folding_controls = show_folding_controls
  self.show_folding_highlights = show_folding_highlights
}

///|
/// `getDecorationOption` (`foldingDecorations.ts:141`).
fn FoldingDecorationProvider::get_decoration_option(
  self : FoldingDecorationProvider,
  is_collapsed : Bool,
  is_hidden : Bool,
  is_manual : Bool,
  is_outline_body : Bool,
) -> @model.ModelDecorationOptions {
  if is_hidden {
    // is inside another collapsed region
    return hidden_range_decoration
  }
  if self.show_folding_controls == Never {
    if is_collapsed {
      if is_outline_body {
        return if self.show_folding_highlights {
          no_controls_collapsed_outline_body_highlighted_range_decoration
        } else {
          no_controls_collapsed_outline_body_range_decoration
        }
      }
      return if self.show_folding_highlights {
        no_controls_collapsed_highlighted_range_decoration
      } else {
        no_controls_collapsed_range_decoration
      }
    }
    return no_controls_expanded_range_decoration
  }
  if is_collapsed {
    if is_outline_body {
      if self.show_folding_highlights {
        collapsed_outline_body_highlighted_visual_decoration
      } else {
        collapsed_outline_body_visual_decoration
      }
    } else if is_manual {
      if self.show_folding_highlights {
        manually_collapsed_highlighted_visual_decoration
      } else {
        manually_collapsed_visual_decoration
      }
    } else if self.show_folding_highlights {
      collapsed_highlighted_visual_decoration
    } else {
      collapsed_visual_decoration
    }
  } else if self.show_folding_controls == Mouseover {
    if is_manual {
      manually_expanded_auto_hide_visual_decoration
    } else {
      expanded_auto_hide_visual_decoration
    }
  } else if is_manual {
    manually_expanded_visual_decoration
  } else {
    expanded_visual_decoration
  }
}

///|
/// `changeDecorations` (`foldingDecorations.ts:162`), through the editor's
/// (model, owner id).
fn FoldingDecorationProvider::change_decorations(
  self : FoldingDecorationProvider,
  callback : (@model.ModelDecorationsChangeAccessor) -> Unit,
) -> Unit {
  self.model.change_decorations(callback, owner_id=self.owner_id)
}

///|
/// `removeDecorations` (`foldingDecorations.ts:166`).
fn FoldingDecorationProvider::remove_decorations(
  self : FoldingDecorationProvider,
  decoration_ids : Array[String],
) -> Unit {
  self.model.change_decorations(
    accessor => ignore((accessor.delta_decorations)(decoration_ids, [])),
    owner_id=self.owner_id,
  )
}

///|
/// Binds the source provider to the three operations consumed by
/// `FoldingModel`, without introducing a runtime trait object.
pub fn FoldingDecorationProvider::access(
  self : FoldingDecorationProvider,
) -> FoldingDecorationAccess {
  FoldingDecorationAccess(
    (is_collapsed, is_hidden, is_manual, is_outline_body) => {
      self.get_decoration_option(
        is_collapsed, is_hidden, is_manual, is_outline_body,
      )
    },
    callback => self.change_decorations(callback),
    decoration_ids => self.remove_decorations(decoration_ids),
  )
}

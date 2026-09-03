// Ported from `vscode/src/vs/editor/browser/viewParts/contentWidgets/contentWidgets.ts`
// (`ViewContentWidgets` + its inner `Widget`), with the `IContentWidget` /
// `IContentWidgetPosition` contracts of `editorBrowser.ts`. Its focused
// lifecycle wiring lives beside the package-private rendering context.
//
// The widget lifecycle is the viewer's consumed source slice: a widget's DOM
// is appended once by `add_widget` and stays mounted for the View lifetime;
// `set_widget_position` only records anchors/preference; each frame
// `prepare_render` computes the box layout and `render` writes
// `top`/`left`/`visibility`. Hiding is
// normally `visibility:hidden`; a focused off-viewport widget is parked at
// `top:-1000px` instead. Neither path unmounts — re-inserting a mounted node
// would restart CSS animations on its subtree (the hover's `fade-in`).

///|
/// Monaco `IContentWidgetPosition` (`editorBrowser.ts`): the model-space
/// anchors, nullable placement preference order, and affinity. Affinity is
/// retained and fed back into model-to-view conversion whenever mappings
/// change.
pub(all) struct ContentWidgetPosition {
  position : @base_common.Position?
  secondary_position : @base_common.Position?
  preference : Array[ContentWidgetPositionPreference]?
  position_affinity : @model.PositionAffinity?
}

///|
/// Monaco `IDimension`, returned by an optional content-widget `beforeRender`
/// callback when the widget can provide its dimensions without a DOM read.
priv struct ContentWidgetDimension {
  width : Double
  height : Double
}

///|
/// Monaco `IContentWidgetRenderedCoordinate`, passed to `afterRender` after
/// the write phase has selected and applied a concrete placement.
priv struct ContentWidgetRenderedCoordinate {
  top : Double
  left : Double
}

///|
/// Value-level adapter for Monaco's `IContentWidget` (`editorBrowser.ts`).
/// Required source methods remain getter closures so their values stay live;
/// optional source fields and callbacks remain independently optional instead
/// of being expanded into mandatory trait methods plus `has_*` sentinels.
struct ContentWidgetHandle {
  get_id : () -> String
  get_dom_node : () -> @rdom.Element
  get_position : () -> ContentWidgetPosition?
  allow_editor_overflow : Bool
  use_display_none : Bool
  before_render : (() -> ContentWidgetDimension? raise)?
  after_render : ((
    ContentWidgetPositionPreference?,
    ContentWidgetRenderedCoordinate?,
  ) -> Unit raise)?
}

///|
/// Creates the production content-widget adapter. The public callback reports
/// only the selected preference consumed by concrete widgets; dimension hints,
/// rendered coordinates, and `useDisplayNone` remain package implementation
/// seams exercised by white-box geometry tests.
pub fn ContentWidgetHandle::ContentWidgetHandle(
  get_id : () -> String,
  get_dom_node : () -> @rdom.Element,
  get_position : () -> ContentWidgetPosition?,
  allow_editor_overflow? : Bool = false,
  after_render? : (ContentWidgetPositionPreference?) -> Unit raise,
) -> ContentWidgetHandle {
  let after_render_with_coordinate = match after_render {
    Some(callback) => Some((position, _coordinate) => callback(position))
    None => None
  }
  ContentWidgetHandle::with_render_callbacks(
    get_id,
    get_dom_node,
    get_position,
    allow_editor_overflow,
    false,
    None,
    after_render_with_coordinate,
  )
}

///|
/// Package-private full adapter used by the renderer's white-box contract
/// tests. It retains Monaco's dimension hint and exact rendered-coordinate
/// callbacks without making either geometry DTO part of the public API.
fn ContentWidgetHandle::with_render_callbacks(
  get_id : () -> String,
  get_dom_node : () -> @rdom.Element,
  get_position : () -> ContentWidgetPosition?,
  allow_editor_overflow : Bool,
  use_display_none : Bool,
  before_render : (() -> ContentWidgetDimension? raise)?,
  after_render : ((
    ContentWidgetPositionPreference?,
    ContentWidgetRenderedCoordinate?,
  ) -> Unit raise)?,
) -> ContentWidgetHandle {
  {
    get_id,
    get_dom_node,
    get_position,
    allow_editor_overflow,
    use_display_none,
    before_render,
    after_render,
  }
}

///|
/// Monaco's `IRenderData` (`contentWidgets.ts:177-188`): where the widget
/// renders this frame. `top` is viewport-relative (the render pass converts to
/// the content layer's coordinate space, the source's `+ ctx.scrollTop -
/// ctx.bigNumbersDelta`), `left` is content-space.
priv enum WidgetRenderData {
  InViewport(
    coordinate~ : ContentWidgetRenderedCoordinate,
    position~ : ContentWidgetPositionPreference
  )
  OffViewport(preserve_focus~ : Bool)
}

///|
/// Monaco `PositionPair` (`contentWidgets.ts:625-630`): retain the widget's
/// model anchor and the view position projected at source-event time. Mapping
/// events replace only `view_position`, so the original model anchor remains
/// the input to every later reprojection.
priv struct PositionPair {
  model_position : @base_common.Position?
  view_position : @base_common.Position?
}

///|
/// Monaco's inner `Widget` (`contentWidgets.ts:190`): per-widget position
/// state, the cached DOM box, and this frame's render data.
priv struct Widget {
  actual : ContentWidgetHandle
  dom_node : @rdom.Element
  id : String
  /// Monaco `Widget.allowEditorOverflow`. The editor-level `allowOverflow`
  /// conjunction remains an explicit deferred option seam.
  allow_editor_overflow : Bool
  mut content_width : Double
  mut content_left : Double
  mut primary_anchor : PositionPair
  mut secondary_anchor : PositionPair
  mut affinity : @model.PositionAffinity?
  mut preference : Array[ContentWidgetPositionPreference]?
  /// Monaco `_cachedDomNodeOffsetWidth/Height`, invalidated by `set_position`.
  mut cached_dom_node_offset_width : Double
  mut cached_dom_node_offset_height : Double
  /// Monaco `Widget._maxWidth` (`_getMaxWidth`), initialized with the widget
  /// and refreshed only by layoutInfo configuration changes. `onBeforeRender`
  /// reapplies this cached value without recomputing it.
  mut max_width : Double
  mut is_visible : Bool
  use_display_none : Bool
  mut render_data : WidgetRenderData?
}

///|
/// Public widget owner for root callers. Package-local lifecycle code
/// reads/writes its private `should_render` / `dom_node` state directly.
struct ContentWidgets {
  dom_node : @rdom.Element
  overflowing_content_widgets_dom_node : @rdom.Element
  /// Monaco `ViewContentWidgets._viewDomNode`: the editor's root node, the
  /// page-space reference box for `_layoutBoxInPage`.
  view_dom_node : @rdom.Element
  widgets : Map[String, Widget]
  /// Live stand-ins for Monaco's retained `ViewContext`: configuration reads
  /// and model-to-view conversion happen when their source events arrive, not
  /// from a later render snapshot.
  mut read_layout_info : () -> (Double, Double)
  mut model_position_to_valid_view_position : (
    @base_common.Position,
    @model.PositionAffinity?,
  ) -> @base_common.Position?
  mut should_render : Bool
}

///|
fn ContentWidgets::ContentWidgets(
  document : @rdom.Document,
  view_dom_node : @rdom.Element,
) -> ContentWidgets {
  let dom_node = document.create_element("div")
  dom_node.set_attribute("class", "contentWidgets")
  dom_node.set_attribute("data-view-part", "contentWidgets")
  @base_browser.set_style_property(dom_node, "position", "absolute")
  @base_browser.set_style_property(dom_node, "top", "0px")
  let overflowing_content_widgets_dom_node = document.create_element("div")
  overflowing_content_widgets_dom_node.set_attribute(
    "class", "overflowingContentWidgets",
  )
  overflowing_content_widgets_dom_node.set_attribute(
    "data-view-part", "overflowingContentWidgets",
  )
  let result : ContentWidgets = {
    dom_node,
    overflowing_content_widgets_dom_node,
    view_dom_node,
    widgets: Map([]),
    read_layout_info: () => (0.0, 0.0),
    model_position_to_valid_view_position: (position, _affinity) => {
      Some(position)
    },
    should_render: true,
  }
  offer_browser_content_widgets_diagnostic(
    run_browser_content_widgets_diagnostic,
  )
  result
}

///|
/// Installs the live configuration/converter capabilities owned by the active
/// ViewModel. The root calls this before re-adding retained widgets; the
/// closures then remain stable for the View's model-scoped lifetime.
fn ContentWidgets::install_live_view_context(
  self : ContentWidgets,
  read_layout_info : () -> (Double, Double),
  model_position_to_valid_view_position : (@base_common.Position) -> @base_common.Position?,
) -> Unit {
  self.read_layout_info = read_layout_info
  self.model_position_to_valid_view_position = (position, _affinity) => {
    model_position_to_valid_view_position(position)
  }
}

///|
/// Affinity-aware variant of `install_live_view_context`. The integration
/// owner uses this when its coordinate converter exposes Monaco's
/// `PositionAffinity` axis.
pub fn ContentWidgets::install_live_view_context_with_affinity(
  self : ContentWidgets,
  read_layout_info : () -> (Double, Double),
  model_position_to_valid_view_position : (
    @base_common.Position,
    @model.PositionAffinity?,
  ) -> @base_common.Position?,
) -> Unit {
  self.read_layout_info = read_layout_info
  self.model_position_to_valid_view_position = model_position_to_valid_view_position
}

///|
fn ContentWidgets::dom_node(self : ContentWidgets) -> @rdom.Element {
  self.dom_node
}

///|
fn ContentWidgets::overflowing_content_widgets_dom_node(
  self : ContentWidgets,
) -> @rdom.Element {
  self.overflowing_content_widgets_dom_node
}

///|
/// Monaco `ViewContentWidgets.addWidget` (`contentWidgets.ts:102-113`): mount
/// the widget's DOM once — every later frame only repositions it. The initial
/// `display:none; visibility:hidden` mirrors the source `Widget` constructor.
pub fn ContentWidgets::add_widget(
  self : ContentWidgets,
  actual : ContentWidgetHandle,
) -> Unit {
  let (content_left, content_width) = (self.read_layout_info)()
  let dom_node = (actual.get_dom_node)()
  let id = (actual.get_id)()
  let allow_editor_overflow = actual.allow_editor_overflow
  let use_display_none = actual.use_display_none
  let widget : Widget = {
    actual,
    dom_node,
    id,
    allow_editor_overflow,
    content_width,
    content_left,
    primary_anchor: { model_position: None, view_position: None, },
    secondary_anchor: { model_position: None, view_position: None, },
    affinity: None,
    preference: Some([]),
    cached_dom_node_offset_width: -1.0,
    cached_dom_node_offset_height: -1.0,
    max_width: content_widget_max_width(
      dom_node, allow_editor_overflow, content_width,
    ),
    is_visible: false,
    use_display_none,
    render_data: None,
  }
  @base_browser.set_style_property(widget.dom_node, "position", "absolute")
  @base_browser.set_style_property(widget.dom_node, "display", "none")
  @base_browser.set_style_property(widget.dom_node, "visibility", "hidden")
  // `widgetId` is the attribute Monaco's hit test resolves through
  // `HitTestContext.findAttribute` (contentWidgets.ts:246).
  dom_node.set_attribute("widgetId", widget.id)
  widget.apply_max_width()
  // Local compatibility marker, deliberately after the complete source-owned
  // constructor write sequence above.
  dom_node.set_attribute("data-content-widget", widget.id)
  self.widgets[widget.id] = widget
  if widget.allow_editor_overflow {
    self.overflowing_content_widgets_dom_node.append_child(dom_node.as_node())
  } else {
    self.dom_node.append_child(dom_node.as_node())
  }
  self.should_render = true
}

///|
/// Monaco `ViewContentWidgets.setWidgetPosition` (`contentWidgets.ts:115-122`)
/// fed by `CodeEditorWidget.layoutContentWidget` reading the widget's
/// `getPosition()`: record the anchors/preference, flip `display` so the
/// prepare pass can measure a widget that wants to become visible, and
/// invalidate the cached box (`Widget.setPosition`, `:293-307`).
pub fn ContentWidgets::set_widget_position(
  self : ContentWidgets,
  actual : ContentWidgetHandle,
) -> Unit {
  let widget = self.widgets[(actual.get_id)()]
  match (actual.get_position)() {
    Some(position) => {
      widget.affinity = position.position_affinity
      widget.set_anchor_positions(
        position.position,
        position.secondary_position,
        self.model_position_to_valid_view_position,
      )
      widget.preference = position.preference
    }
    None => {
      widget.affinity = None
      widget.set_anchor_positions(
        None,
        None,
        self.model_position_to_valid_view_position,
      )
      widget.preference = None
    }
  }
  let display = match widget.preference {
    Some(preferences) =>
      if !widget.use_display_none &&
        widget.primary_anchor.view_position is Some(_) &&
        preferences.length() > 0 {
        "block"
      } else {
        "none"
      }
    None => "none"
  }
  @base_browser.set_style_property(widget.dom_node, "display", display)
  widget.cached_dom_node_offset_width = -1.0
  widget.cached_dom_node_offset_height = -1.0
  if !widget.use_display_none {
    self.should_render = true
  }
}

///|
/// Monaco `ViewContentWidgets.removeWidget`: forget the widget, detach its DOM
/// node, clear the visibility marker, and schedule the remaining widgets for
/// layout. This is required by model-scoped CodeLens widgets; persistent hover
/// widgets continue to be owned by their existing per-View teardown path.
pub fn ContentWidgets::remove_widget(
  self : ContentWidgets,
  actual : ContentWidgetHandle,
) -> Unit {
  let id = (actual.get_id)()
  guard self.widgets.get(id) is Some(widget) else { return }
  self.widgets.remove(id)
  @base_browser.remove_element(widget.dom_node)
  widget.dom_node.remove_attribute("monaco-visible-content-widget")
  self.should_render = true
}

///|
/// Monaco `ViewContentWidgets.onConfigurationChanged` (`:56-62`) delegates
/// to every retained widget. Each inner handler rereads layout caches only for
/// the `layoutInfo` option identity (`Widget.onConfigurationChanged`, :250-258).
fn ContentWidgets::on_configuration_changed(
  self : ContentWidgets,
  layout_info_changed : Bool,
) -> Unit {
  let widget_ids = self.widget_ids_snapshot()
  for widget_id in widget_ids {
    self.widgets[widget_id].on_configuration_changed(
      layout_info_changed,
      self.read_layout_info,
    )
  }
}

///|
/// Monaco `_updateAnchorsViewPositions` (`:95-100`): Map iteration preserves
/// insertion/key order, matching `Object.keys(_widgets)`, and every retained
/// model anchor is reprojected before the part is marked dirty.
fn ContentWidgets::update_anchors_view_positions(self : ContentWidgets) -> Unit {
  let widget_ids = self.widget_ids_snapshot()
  for widget_id in widget_ids {
    self.widgets[widget_id].update_anchor_view_position(
      self.model_position_to_valid_view_position,
    )
  }
}

///|
/// Source `Object.keys(this._widgets)`: freeze one insertion-ordered id list
/// before an outer phase begins, then perform each source-shaped lookup at the
/// moment that id is visited. A reentrant callback can mutate the live map but
/// cannot change the phase's key traversal.
fn ContentWidgets::widget_ids_snapshot(self : ContentWidgets) -> Array[String] {
  let widget_ids : Array[String] = []
  for widget_id, _ in self.widgets {
    widget_ids.push(widget_id)
  }
  widget_ids
}

///|
/// The geometry capabilities the prepare pass needs from the render context —
/// Monaco's `RenderingContext` surface as data plus closures, the same host
/// pattern `PointerHandlerHelper` uses. The record makes the widget's exact
/// geometry requirements explicit and independently testable.
priv struct ContentWidgetsRenderContext {
  /// Content-space vertical offset of a view line
  /// (`ctx.getVerticalOffsetForLineNumber`).
  vertical_offset_for_line : (Int) -> Double
  /// Monaco `getLineHeightForLineNumber`; the current uniform-height product
  /// still preserves the exact queried line through this capability.
  line_height_for_line : (Int) -> Double
  /// Monaco `RenderingContext.visibleRangeForPosition(...).left`: a rounded,
  /// DOM-measured caret x, or `None` when the line is not rendered.
  visible_range_for_position : (@base_common.Position) -> Double?
  /// `fontInfo.typicalFullwidthCharacterWidth`, the `_reduceAnchorCoordinates`
  /// clamp unit.
  typical_fullwidth_character_width : Double
  scroll_top : Double
  scroll_left : Double
  viewport_width : Double
  viewport_height : Double
}

///|
/// Monaco `ViewContentWidgets.onBeforeRender` (`contentWidgets.ts:145-150`):
/// complete the max-width write pass for every retained widget before text
/// rendering and the later DOM-read phase begin.
fn ContentWidgets::on_before_render_widgets(
  self : ContentWidgets,
  viewport_start : Int,
  viewport_end : Int,
) -> Unit {
  let widget_ids = self.widget_ids_snapshot()
  for widget_id in widget_ids {
    self.widgets[widget_id].on_before_render(viewport_start, viewport_end)
  }
}

///|
/// Monaco `ViewContentWidgets.prepareRender` (`contentWidgets.ts:152-157`):
/// compute each widget's render data for this frame after the distinct
/// `onBeforeRender` write phase and text rendering have completed.
fn ContentWidgets::prepare_render_widgets(
  self : ContentWidgets,
  ctx : ContentWidgetsRenderContext,
) -> Unit {
  let widget_ids = self.widget_ids_snapshot()
  for widget_id in widget_ids {
    let widget = self.widgets[widget_id]
    widget.render_data = widget.prepare_render_widget(ctx, self.view_dom_node)
  }
}

///|
/// Monaco `ViewContentWidgets.render` (`contentWidgets.ts:159-164`) over
/// `Widget.render` (`:556-596`). `translate_y` is the content layer's vertical
/// transform, so `top_style = viewport_top - translate_y` is the source's
/// `coordinate.top + ctx.scrollTop - ctx.bigNumbersDelta` on the transformed
/// layer.
fn ContentWidgets::render_widgets(
  self : ContentWidgets,
  scroll_top : Double,
  big_numbers_delta : Double,
) -> Unit {
  let widget_ids = self.widget_ids_snapshot()
  for widget_id in widget_ids {
    self.widgets[widget_id].render(scroll_top, big_numbers_delta)
  }
}

///|
/// Monaco `AnchorCoordinate` (`contentWidgets.ts:615-623`).
priv struct AnchorCoordinate {
  top : Double
  left : Double
  height : Double
}

///|
/// Monaco `IBoxLayoutResult` (`contentWidgets.ts:167-175`).
priv struct BoxLayoutResult {
  fits_above : Bool
  above_top : Double
  fits_below : Bool
  below_top : Double
  left : Double
}

///|
/// Monaco `Widget._getMaxWidth` (`contentWidgets.ts:283-291`).
fn content_widget_max_width(
  dom_node : @rdom.Element,
  allow_editor_overflow : Bool,
  content_width : Double,
) -> Double {
  owner_document_max_width(dom_node, allow_editor_overflow, content_width)
}

///|
/// Monaco `onBeforeRender`'s `setMaxWidth(this._maxWidth)` write.
fn Widget::apply_max_width(self : Widget) -> Unit {
  @base_browser.set_style_property(
    self.dom_node,
    "max-width",
    "\{self.max_width.to_string()}px",
  )
}

///|
fn Widget::on_configuration_changed(
  self : Widget,
  layout_info_changed : Bool,
  read_layout_info : () -> (Double, Double),
) -> Unit {
  if layout_info_changed {
    let (content_left, content_width) = read_layout_info()
    self.content_left = content_left
    self.content_width = content_width
    self.max_width = content_widget_max_width(
      self.dom_node,
      self.allow_editor_overflow,
      self.content_width,
    )
  }
}

///|
fn position_pair(
  model_position : @base_common.Position?,
  affinity : @model.PositionAffinity?,
  model_position_to_valid_view_position : (
    @base_common.Position,
    @model.PositionAffinity?,
  ) -> @base_common.Position?,
) -> PositionPair {
  match model_position {
    Some(position) =>
      {
        model_position: Some(position),
        view_position: model_position_to_valid_view_position(position, affinity),
      }
    None => { model_position: None, view_position: None, }
  }
}

///|
fn Widget::set_anchor_positions(
  self : Widget,
  primary_anchor : @base_common.Position?,
  secondary_anchor : @base_common.Position?,
  model_position_to_valid_view_position : (
    @base_common.Position,
    @model.PositionAffinity?,
  ) -> @base_common.Position?,
) -> Unit {
  self.primary_anchor = position_pair(
    primary_anchor,
    self.affinity,
    model_position_to_valid_view_position,
  )
  self.secondary_anchor = position_pair(
    secondary_anchor,
    self.affinity,
    model_position_to_valid_view_position,
  )
}

///|
fn Widget::update_anchor_view_position(
  self : Widget,
  model_position_to_valid_view_position : (
    @base_common.Position,
    @model.PositionAffinity?,
  ) -> @base_common.Position?,
) -> Unit {
  self.set_anchor_positions(
    self.primary_anchor.model_position,
    self.secondary_anchor.model_position,
    model_position_to_valid_view_position,
  )
}

///|
/// Monaco `Widget.onBeforeRender`: only a positionable widget whose primary
/// anchor line is inside the inclusive rendered viewport receives the cached
/// max-width write.
fn Widget::on_before_render(
  self : Widget,
  viewport_start : Int,
  viewport_end : Int,
) -> Unit {
  guard self.primary_anchor.view_position is Some(primary) &&
    self.preference is Some(_) else {
    return
  }
  if primary.line_number < viewport_start || primary.line_number > viewport_end {
    return
  }
  self.apply_max_width()
}

///|
/// Monaco `Widget._prepareRenderWidget` (`contentWidgets.ts:447-534`):
/// `_layoutBoxInPage` for overflowing widgets (`allowEditorOverflow`, e.g.
/// the content hover), `_layoutBoxInViewport` for widgets clipped to the
/// content area.
fn Widget::prepare_render_widget(
  self : Widget,
  ctx : ContentWidgetsRenderContext,
  view_dom_node : @rdom.Element,
) -> WidgetRenderData? {
  guard self.preference is Some(preferences) && preferences.length() > 0 else {
    return None
  }
  let (primary, secondary) = self.anchors_coordinates(ctx)
  guard primary is Some(primary) else {
    return Some(
      OffViewport(
        preserve_focus=@base_browser.element_contains_active_element(
          self.dom_node,
        ),
      ),
    )
  }
  if self.cached_dom_node_offset_width == -1.0 ||
    self.cached_dom_node_offset_height == -1.0 {
    let preferred_dimensions = match self.actual.before_render {
      Some(before_render) => safe_invoke_before_render(before_render)
      None => None
    }
    match preferred_dimensions {
      Some(dimensions) => {
        self.cached_dom_node_offset_width = dimensions.width
        self.cached_dom_node_offset_height = dimensions.height
      }
      None => {
        let rect = self.dom_node.get_bounding_client_rect()
        self.cached_dom_node_offset_width = js_math_round(rect.get_width())
        self.cached_dom_node_offset_height = js_math_round(rect.get_height())
      }
    }
  }
  let anchor = reduce_anchor_coordinates(
    primary,
    secondary,
    self.cached_dom_node_offset_width,
    ctx.typical_fullwidth_character_width,
  )
  let placement = if self.allow_editor_overflow {
    layout_box_in_page(
      anchor,
      self.cached_dom_node_offset_width,
      self.cached_dom_node_offset_height,
      ctx,
      view_dom_node,
      self.content_left,
    )
  } else {
    layout_box_in_viewport(
      anchor,
      self.cached_dom_node_offset_width,
      self.cached_dom_node_offset_height,
      ctx,
    )
  }
  // Do two passes, first for perfect fit, second picks first option.
  for pass in 1..<=2 {
    for pref in preferences {
      match pref {
        Above =>
          if pass == 2 || placement.fits_above {
            return Some(
              InViewport(
                coordinate={ top: placement.above_top, left: placement.left, },
                position=Above,
              ),
            )
          }
        Below =>
          if pass == 2 || placement.fits_below {
            return Some(
              InViewport(
                coordinate={ top: placement.below_top, left: placement.left, },
                position=Below,
              ),
            )
          }
        Exact =>
          // `_prepareRenderWidgetAtExactPositionOverflowing`: the overflowing
          // layer's coordinate space is the editor root, so the content-space
          // `left` shifts right by `contentLeft`.
          if self.allow_editor_overflow {
            return Some(
              InViewport(
                coordinate={
                  top: anchor.top,
                  left: anchor.left + self.content_left,
                },
                position=Exact,
              ),
            )
          } else {
            return Some(
              InViewport(
                coordinate={ top: anchor.top, left: anchor.left, },
                position=Exact,
              ),
            )
          }
      }
    }
  }
  None
}

///|
/// Monaco `Widget._getAnchorsCoordinates` (`contentWidgets.ts:407-429`): the
/// primary/secondary anchors as viewport-relative top + content-space left.
/// The secondary participates only when it sits on the primary's line.
fn Widget::anchors_coordinates(
  self : Widget,
  ctx : ContentWidgetsRenderContext,
) -> (AnchorCoordinate?, AnchorCoordinate?) {
  let primary_view = self.primary_anchor.view_position
  let coordinate = fn(position : @base_common.Position) -> AnchorCoordinate? {
    guard (ctx.visible_range_for_position)(position) is Some(measured_left) else {
      return None
    }
    let left = if position.column == 1 &&
      self.affinity is Some(LeftOfInjectedText) {
      0.0
    } else {
      measured_left
    }
    Some({
      top: (ctx.vertical_offset_for_line)(position.line_number) - ctx.scroll_top,
      left,
      height: (ctx.line_height_for_line)(position.line_number),
    })
  }
  let primary = match primary_view {
    Some(position) => coordinate(position)
    None => None
  }
  let secondary_view = match
    (self.secondary_anchor.view_position, primary_view) {
    (Some(secondary), Some(primary)) =>
      if secondary.line_number == primary.line_number {
        Some(secondary)
      } else {
        None
      }
    _ => None
  }
  let secondary = match secondary_view {
    Some(position) => coordinate(position)
    None => None
  }
  (primary, secondary)
}

///|
/// Monaco `Widget._reduceAnchorCoordinates` (`contentWidgets.ts:431-445`): the
/// widget must touch the primary anchor; the secondary pulls its left edge as
/// far as one fullwidth glyph keeps them overlapping.
fn reduce_anchor_coordinates(
  primary : AnchorCoordinate,
  secondary : AnchorCoordinate?,
  width : Double,
  typical_fullwidth_character_width : Double,
) -> AnchorCoordinate {
  guard secondary is Some(secondary) else { return primary }
  let mut left = secondary.left
  if left < primary.left {
    left = left.max(primary.left - width + typical_fullwidth_character_width)
  } else {
    left = left.min(primary.left + width - typical_fullwidth_character_width)
  }
  { top: primary.top, left, height: primary.height, }
}

///|
/// Monaco `Widget._layoutBoxInViewport` (`contentWidgets.ts:309-335`). Vertical
/// coordinates are viewport-relative; `left` is content-space, clamped to the
/// horizontal scroll window (`[scrollLeft, scrollLeft + viewportWidth]`) — the
/// source's right/left-edge containment.
fn layout_box_in_viewport(
  anchor : AnchorCoordinate,
  width : Double,
  height : Double,
  ctx : ContentWidgetsRenderContext,
) -> BoxLayoutResult {
  // Our visible box is split horizontally by the current line => 2 boxes

  // a) the box above the line
  let above_line_top = anchor.top
  let height_available_above_line = above_line_top

  // b) the box under the line
  let under_line_top = anchor.top + anchor.height
  let height_available_under_line = ctx.viewport_height - under_line_top
  let above_top = above_line_top - height
  let fits_above = height_available_above_line >= height
  let below_top = under_line_top
  let fits_below = height_available_under_line >= height

  // And its left
  let mut left = anchor.left
  if left + width > ctx.scroll_left + ctx.viewport_width {
    left = ctx.scroll_left + ctx.viewport_width - width
  }
  if left < ctx.scroll_left {
    left = ctx.scroll_left
  }
  { fits_above, above_top, fits_below, below_top, left, }
}

///|
/// Monaco `dom.getDomNodePagePosition` narrowed to the fields
/// `_layoutBoxInPage` reads: the node's page-space box (client rect plus the
/// window scroll offset).
priv struct DomNodePagePosition {
  top : Double
  left : Double
  width : Double
}

///|
fn dom_node_page_position(node : @rdom.Element) -> DomNodePagePosition {
  let rect = node.get_bounding_client_rect()
  // `dom.getDomNodePagePosition` uses `dom.getWindow(node)`: a detached owner
  // document falls back to the registered main window, unlike the explicit
  // optional-owner scroll reads in the page-layout helpers below.
  let scroll_x = dom_helper_window_scroll_x(node)
  let scroll_y = dom_helper_window_scroll_y(node)
  {
    top: rect.get_top() + scroll_y,
    left: rect.get_left() + scroll_x,
    width: rect.get_width(),
  }
}

///|
/// Monaco `Widget._layoutHorizontalSegmentInPage` (`contentWidgets.ts:
/// 337-362`): clamp the widget's horizontal segment so it stays inside the
/// window (15px side clearance) while staying within one widget-width of the
/// editor box. Returns the clamped editor-root-relative `left` (the absolute
/// variant only feeds the unported `fixedOverflowWidgets` arm).
fn layout_horizontal_segment_in_page(
  window_width : Double,
  dom_node_position : DomNodePagePosition,
  scroll_x : Double,
  left : Double,
  width : Double,
) -> (Double, Double) {
  // Leave some clearance to the left/right
  let left_padding = 15.0
  let right_padding = 15.0

  // Initially, the limits are defined as the dom node limits
  let min_limit = left_padding.max(dom_node_position.left - width)
  let max_limit = (dom_node_position.left + dom_node_position.width + width).min(
    window_width - right_padding,
  )
  let mut left = left
  let mut absolute_left = dom_node_position.left + left - scroll_x
  if absolute_left + width > max_limit {
    let delta = absolute_left - (max_limit - width)
    absolute_left -= delta
    left -= delta
  }
  if absolute_left < min_limit {
    let delta = absolute_left - min_limit
    absolute_left -= delta
    left -= delta
  }
  (left, absolute_left)
}

///|
/// Monaco `Widget._layoutBoxInPage` (`contentWidgets.ts:364-395`): the
/// overflowing widget renders in the editor root's coordinate space but its
/// fit is judged against the *page* (22px top/bottom clearance), so a narrow
/// or short editor no longer constrains the widget. The
/// `fixedOverflowWidgets` arm is unported (the viewer never sets the option).
fn layout_box_in_page(
  anchor : AnchorCoordinate,
  width : Double,
  height : Double,
  ctx : ContentWidgetsRenderContext,
  view_dom_node : @rdom.Element,
  content_left : Double,
) -> BoxLayoutResult {
  let above_top = anchor.top - height
  let below_top = anchor.top + anchor.height
  let dom_node_position = dom_node_page_position(view_dom_node)
  let scroll_x = owner_window_scroll_x(view_dom_node)
  let scroll_y = owner_window_scroll_y(view_dom_node)
  let absolute_above_top = dom_node_position.top + above_top - scroll_y
  let absolute_below_top = dom_node_position.top + below_top - scroll_y
  let (window_width, window_height) = body_client_area(view_dom_node)
  let (left, _absolute_left) = layout_horizontal_segment_in_page(
    window_width,
    dom_node_position,
    scroll_x,
    anchor.left - ctx.scroll_left + content_left,
    width,
  )

  // Leave some clearance to the top/bottom
  let top_padding = 22.0
  let bottom_padding = 22.0
  let fits_above = absolute_above_top >= top_padding
  let fits_below = absolute_below_top + height <= window_height - bottom_padding
  { fits_above, above_top, fits_below, below_top, left, }
}

///|
/// Monaco `Widget.render` (`contentWidgets.ts:556-596`), the write half: only
/// `top`/`left`/`visibility` change per frame; the DOM stays mounted. An
/// overflowing widget's coordinates are already editor-root-relative, so the
/// content layer's `translate_y` does not apply (`contentWidgets.ts:585-591`).
fn Widget::render(
  self : Widget,
  scroll_top : Double,
  big_numbers_delta : Double,
) -> Unit {
  match self.render_data {
    Some(InViewport(coordinate~, position~)) => {
      let top = if self.allow_editor_overflow {
        coordinate.top
      } else {
        coordinate.top + scroll_top - big_numbers_delta
      }
      @base_browser.set_style_property(
        self.dom_node,
        "top",
        "\{top.to_string()}px",
      )
      @base_browser.set_style_property(
        self.dom_node,
        "left",
        "\{coordinate.left.to_string()}px",
      )
      if !self.is_visible {
        @base_browser.set_style_property(self.dom_node, "visibility", "inherit")
        self.dom_node.set_attribute("monaco-visible-content-widget", "true")
        self.is_visible = true
      }
      match self.actual.after_render {
        Some(after_render) =>
          safe_invoke_after_render(
            after_render,
            Some(position),
            Some(coordinate),
          )
        None => ()
      }
    }
    Some(OffViewport(preserve_focus~)) => {
      if self.is_visible {
        self.dom_node.remove_attribute("monaco-visible-content-widget")
        self.is_visible = false
        if preserve_focus {
          @base_browser.set_style_property(self.dom_node, "top", "-1000px")
        } else {
          @base_browser.set_style_property(
            self.dom_node,
            "visibility",
            "hidden",
          )
        }
      }
      match self.actual.after_render {
        Some(after_render) => safe_invoke_after_render(after_render, None, None)
        None => ()
      }
    }
    None => {
      if self.is_visible {
        self.dom_node.remove_attribute("monaco-visible-content-widget")
        self.is_visible = false
        @base_browser.set_style_property(self.dom_node, "visibility", "hidden")
      }
      match self.actual.after_render {
        Some(after_render) => safe_invoke_after_render(after_render, None, None)
        None => ()
      }
    }
  }
}

///|
/// Monaco `safeInvoke(actual.beforeRender, actual)`: callback failures become
/// a null preferred-dimension result and therefore fall back to DOM measure.
fn safe_invoke_before_render(
  before_render : () -> ContentWidgetDimension? raise,
) -> ContentWidgetDimension? {
  before_render() catch {
    _ => None
  }
}

///|
/// Monaco `safeInvoke(actual.afterRender, actual, position, coordinate)`:
/// callback failures must not abort the frame.
fn safe_invoke_after_render(
  after_render : (
    ContentWidgetPositionPreference?,
    ContentWidgetRenderedCoordinate?,
  ) -> Unit raise,
  position : ContentWidgetPositionPreference?,
  coordinate : ContentWidgetRenderedCoordinate?,
) -> Unit {
  after_render(position, coordinate) catch {
    _ => ()
  }
}

///|
/// Monaco `_getMaxWidth`: use the widget node's owner document/window, never
/// the ambient global window. JavaScript `||` intentionally treats a zero
/// `innerWidth` as unavailable before the two offset-width fallbacks.
extern "js" fn owner_document_max_width(
  element : @rdom.Element,
  allow_editor_overflow : Bool,
  content_width : Double,
) -> Double =
  #| (element, allowOverflow, contentWidth) => {
  #|   if (!allowOverflow) return contentWidth;
  #|   const doc = element.ownerDocument;
  #|   const win = doc?.defaultView;
  #|   return (win?.innerWidth || doc?.documentElement?.offsetWidth || doc?.body?.offsetWidth || 0);
  #| }

///|
/// Owner-window page scroll with the source's exact `defaultView ?? 0`
/// fallback for detached documents.
extern "js" fn owner_window_scroll_x(element : @rdom.Element) -> Double =
  #| (element) => element?.ownerDocument?.defaultView?.scrollX ?? 0

///|
extern "js" fn owner_window_scroll_y(element : @rdom.Element) -> Double =
  #| (element) => element?.ownerDocument?.defaultView?.scrollY ?? 0

///|
extern "js" fn dom_helper_window_scroll_x(element : @rdom.Element) -> Double =
  #| (element) => (element?.ownerDocument?.defaultView ?? globalThis.window)?.scrollX ?? 0

///|
extern "js" fn dom_helper_window_scroll_y(element : @rdom.Element) -> Double =
  #| (element) => (element?.ownerDocument?.defaultView ?? globalThis.window)?.scrollY ?? 0

///|
/// Monaco `dom.getClientArea(elDocument.body)`: the page box the overflowing
/// placement is clamped to.
fn body_client_area(node : @rdom.Element) -> (Double, Double) {
  (body_client_width(node), body_client_height(node))
}

///|
extern "js" fn body_client_width(node : @rdom.Element) -> Double =
  #| (node) => {
  #|   const doc = node.ownerDocument;
  #|   const win = doc?.defaultView;
  #|   // `getClientArea(doc.body)` sees a detached body as a non-main-body
  #|   // element after `getWindow` falls back, and returns its client box
  #|   // immediately — including an exact zero.
  #|   if (!win) return doc?.body?.clientWidth ?? 0;
  #|   const userAgent = globalThis.navigator?.userAgent ?? '';
  #|   const isIOS = (
  #|     userAgent.includes('Macintosh') ||
  #|     userAgent.includes('iPad') ||
  #|     userAgent.includes('iPhone')
  #|   ) && (globalThis.navigator?.maxTouchPoints ?? 0) > 0;
  #|   if (isIOS && win.visualViewport) return win.visualViewport.width;
  #|   if (win?.innerWidth && win?.innerHeight) return win.innerWidth;
  #|   if (doc?.body?.clientWidth && doc?.body?.clientHeight) return doc.body.clientWidth;
  #|   if (doc?.documentElement?.clientWidth && doc?.documentElement?.clientHeight) return doc.documentElement.clientWidth;
  #|   throw new Error('Unable to figure out browser width and height');
  #| }

///|
extern "js" fn body_client_height(node : @rdom.Element) -> Double =
  #| (node) => {
  #|   const doc = node.ownerDocument;
  #|   const win = doc?.defaultView;
  #|   if (!win) return doc?.body?.clientHeight ?? 0;
  #|   const userAgent = globalThis.navigator?.userAgent ?? '';
  #|   const isIOS = (
  #|     userAgent.includes('Macintosh') ||
  #|     userAgent.includes('iPad') ||
  #|     userAgent.includes('iPhone')
  #|   ) && (globalThis.navigator?.maxTouchPoints ?? 0) > 0;
  #|   if (isIOS && win.visualViewport) return win.visualViewport.height;
  #|   if (win?.innerWidth && win?.innerHeight) return win.innerHeight;
  #|   if (doc?.body?.clientWidth && doc?.body?.clientHeight) return doc.body.clientHeight;
  #|   if (doc?.documentElement?.clientWidth && doc?.documentElement?.clientHeight) return doc.documentElement.clientHeight;
  #|   throw new Error('Unable to figure out browser width and height');
  #| }

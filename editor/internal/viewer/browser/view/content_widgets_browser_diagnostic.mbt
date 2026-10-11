// Browser-only diagnostics for the private ContentWidgets renderer. Product
// hosts do not install `__viewerPrivateTestProbe`, so this bridge is inert
// outside the focused browser geometry fixture and adds no MoonBit API.

///|
priv struct BrowserContentWidgetDiagnosticWidget {
  id : String
  node : @rdom.Element
  allow_overflow : Bool
  mut preference : Array[ContentWidgetPositionPreference]
  mut after_position : String
  mut after_top : Double
  mut after_left : Double
}

///|
fn BrowserContentWidgetDiagnosticWidget::handle(
  self : BrowserContentWidgetDiagnosticWidget,
) -> ContentWidgetHandle {
  ContentWidgetHandle::with_render_callbacks(
    () => self.id,
    () => self.node,
    () => {
      Some({
        position: Some(Position(1, 1)),
        secondary_position: None,
        preference: Some(self.preference),
        position_affinity: None,
      })
    },
    self.allow_overflow,
    false,
    Some(() => Some({ width: 80.0, height: 30.0, })),
    Some((position, coordinate) => {
      self.after_position = match position {
        Some(Above) => "above"
        Some(Below) => "below"
        Some(Exact) => "exact"
        None => "null"
      }
      match coordinate {
        Some(coordinate) => {
          self.after_top = coordinate.top
          self.after_left = coordinate.left
        }
        None => {
          self.after_top = -9999.0
          self.after_left = -9999.0
        }
      }
    }),
  )
}

///|
fn BrowserContentWidgetDiagnosticWidget::BrowserContentWidgetDiagnosticWidget(
  document : @rdom.Document,
  id : String,
  allow_overflow : Bool,
) -> BrowserContentWidgetDiagnosticWidget {
  let node = document.create_element("div")
  node.set_attribute("data-geometry-owner-widget", id)
  node.set_attribute(
    "data-geometry-owner-overflow",
    if allow_overflow {
      "true"
    } else {
      "false"
    },
  )
  node.set_attribute(
    "style", "box-sizing:border-box;width:80px;height:30px;background:rgba(0,128,255,.15)",
  )
  node.set_inner_html(id)
  {
    id,
    node,
    allow_overflow,
    preference: [Exact],
    after_position: "null",
    after_top: -9999.0,
    after_left: -9999.0,
  }
}

///|
priv struct BrowserContentWidgetsDiagnostic {
  widgets : ContentWidgets
  normal : BrowserContentWidgetDiagnosticWidget
  overflow : BrowserContentWidgetDiagnosticWidget
  anchor_left : Ref[Double]
  anchor_top : Ref[Double]
}

///|
fn BrowserContentWidgetsDiagnostic::BrowserContentWidgetsDiagnostic(
  document : @rdom.Document,
  root : @rdom.Element,
) -> BrowserContentWidgetsDiagnostic {
  let widgets = ContentWidgets::ContentWidgets(document, root)
  let normal_container = widgets.dom_node()
  normal_container.set_attribute(
    "style", "position:absolute;top:0;left:0;width:430px;height:300px",
  )
  let overflow_container = widgets.overflowing_content_widgets_dom_node()
  overflow_container.set_attribute(
    "style", "position:absolute;top:0;left:0;width:430px;height:300px",
  )
  root.append_child(normal_container.as_node())
  root.append_child(overflow_container.as_node())
  let anchor_left = Ref(20.0)
  let anchor_top = Ref(50.0)
  widgets.install_live_view_context(() => (0.0, 430.0), position => {
    Some(position)
  })
  let normal = BrowserContentWidgetDiagnosticWidget::BrowserContentWidgetDiagnosticWidget(
    document, "normal", false,
  )
  let overflow = BrowserContentWidgetDiagnosticWidget::BrowserContentWidgetDiagnosticWidget(
    document, "overflow", true,
  )
  widgets.add_widget(normal.handle())
  widgets.set_widget_position(normal.handle())
  widgets.add_widget(overflow.handle())
  widgets.set_widget_position(overflow.handle())
  { widgets, normal, overflow, anchor_left, anchor_top, }
}

///|
fn BrowserContentWidgetsDiagnostic::context(
  self : BrowserContentWidgetsDiagnostic,
) -> ContentWidgetsRenderContext {
  {
    vertical_offset_for_line: _ => self.anchor_top.val,
    line_height_for_line: _ => 20.0,
    visible_range_for_position: _ => Some(self.anchor_left.val),
    typical_fullwidth_character_width: 16.0,
    scroll_top: 0.0,
    scroll_left: 0.0,
    viewport_width: 500.0,
    viewport_height: 360.0,
  }
}

///|
fn BrowserContentWidgetsDiagnostic::capture(
  _self : BrowserContentWidgetsDiagnostic,
  widget : BrowserContentWidgetDiagnosticWidget,
) -> Json {
  let rect = widget.node.get_bounding_client_rect()
  Json({
    "position": Json(widget.after_position),
    "top": Json::number(widget.after_top),
    "left": Json::number(widget.after_left),
    "rectLeft": Json::number(rect.get_left()),
    "rectTop": Json::number(rect.get_top()),
    "rectRight": Json::number(rect.get_right()),
    "rectBottom": Json::number(rect.get_bottom()),
  })
}

///|
fn BrowserContentWidgetsDiagnostic::run_case(
  self : BrowserContentWidgetsDiagnostic,
  widget : BrowserContentWidgetDiagnosticWidget,
  left : Double,
  top : Double,
  preference : Array[ContentWidgetPositionPreference],
) -> Json {
  self.anchor_left.val = left
  self.anchor_top.val = top
  widget.preference = preference
  self.widgets.set_widget_position(widget.handle())
  self.widgets.prepare_render_widgets(self.context())
  self.widgets.render_widgets(0.0, 0.0)
  self.capture(widget)
}

///|
fn BrowserContentWidgetsDiagnostic::run_matrix(
  self : BrowserContentWidgetsDiagnostic,
) -> String {
  Json({
    "normalExact": self.run_case(self.normal, 20.0, 50.0, [Exact]),
    // Root page-left=40 and owner scrollX=31. These one-pixel overflow inputs
    // clamp the rendered edges to exactly 15px and innerWidth-15px.
    "leftClamp": self.run_case(self.overflow, 5.0, 100.0, [Below]),
    "rightClamp": self.run_case(self.overflow, 397.0, 100.0, [Below]),
    // Root page-top=80 and owner scrollY=47. With a 30px widget these anchor
    // tops put the box exactly on, then one pixel outside, each 22px fit edge.
    "topEqual": self.run_case(self.overflow, 100.0, 19.0, [Above, Below]),
    "topOutside": self.run_case(self.overflow, 100.0, 18.0, [Above, Below]),
    "bottomEqual": self.run_case(self.overflow, 100.0, 255.0, [Below, Above]),
    "bottomOutside": self.run_case(self.overflow, 100.0, 256.0, [Below, Above]),
  }).stringify()
}

///|
fn run_browser_content_widgets_diagnostic(
  document : @rdom.Document,
  root : @rdom.Element,
) -> String {
  BrowserContentWidgetsDiagnostic::BrowserContentWidgetsDiagnostic(
    document, root,
  ).run_matrix()
}

///|
/// Offers the private renderer diagnostic to an explicitly installed browser
/// test host. The callback is neither exported nor attached in product pages.
extern "js" fn offer_browser_content_widgets_diagnostic(
  run : (@rdom.Document, @rdom.Element) -> String,
) -> Unit =
  #| (run) => globalThis.__viewerPrivateTestProbe?.acceptContentWidgets?.(run)

///|
const DiffHunkActionGutterWidth = 24.0

///|
fn DiffEditorWidget::hunk_action_gutter_width(
  self : DiffEditorWidget,
) -> Double {
  if self.hunk_action_renderer is Some(_) {
    DiffHunkActionGutterWidth
  } else {
    0.0
  }
}

///|
/// Host-owned actions share the hunk's rendered position, including deletion
/// space. The widget owns their attachment and lifetime, but not their policy.
pub fn DiffEditorWidget::set_hunk_action_renderer(
  self : DiffEditorWidget,
  renderer : ((Int) -> @rdom.Element?)?,
) -> Unit {
  let previous_width = self.hunk_action_gutter_width()
  self.hunk_action_renderer = renderer
  let width = self.hunk_action_gutter_width()
  @base_browser.set_style_property(
    self.root,
    "--diff-hunk-action-gutter-width",
    "\{width}px",
  )
  if width != previous_width {
    self.layout()
  }
  self.render_hunk_actions()
}

///|
fn DiffEditorWidget::clear_hunk_actions(self : DiffEditorWidget) -> Unit {
  for (_, node) in self.hunk_actions {
    self.root.remove_child(node.as_node())
  }
  self.hunk_actions.clear()
}

///|
fn DiffEditorWidget::install_hunk_action_hover(self : DiffEditorWidget) -> Unit {
  let update_pointer = fn(event : @rdom.Event) {
    guard event.to_mouse_event() is Some(mouse) else { return }
    self.hunk_pointer_position = Some(
      (mouse.get_client_x(), mouse.get_client_y()),
    )
    self.update_hunk_action_hover()
  }
  self.listen(self.root.as_event_target(), "pointerenter", update_pointer)
  self.listen(self.root.as_event_target(), "pointermove", update_pointer)
  self.listen(self.root.as_event_target(), "pointerleave", _ => {
    self.hunk_pointer_position = None
    self.update_hunk_action_hover()
  })
  // Outer-scroll hosts move the entire widget without scrolling either pane.
  let document = @rdom.document().as_event_target()
  let on_scroll : @rdom.Listener = _ => {
    if self.hunk_pointer_position is Some(_) {
      self.update_hunk_action_hover()
    }
  }
  document.add_event_listener_with_options("scroll", on_scroll, capture=true)
  self.lifetime.push(
    @base_common.Disposable::from(() => {
      document.remove_event_listener_with_options(
        "scroll",
        on_scroll,
        capture=true,
      )
    }),
  )
}

///|
/// Hit-test the rendered hunk geometry without making its overlay intercept
/// pointer events intended for code selection. Hosts own the action's styling.
fn DiffEditorWidget::update_hunk_action_hover(self : DiffEditorWidget) -> Unit {
  guard !self.hunk_actions.is_empty() else { return }
  let offset = self.hunk_pointer_position.bind(position => {
    let (x, y) = position
    let rect = self.root.get_bounding_client_rect()
    if x >= rect.get_left() &&
      x < rect.get_right() &&
      y >= rect.get_top() &&
      y < rect.get_bottom() {
      Some(y - rect.get_top())
    } else {
      None
    }
  })
  let hunks = self.get_hunks()
  let mut matched = false
  for (index, node) in self.hunk_actions {
    let hovered = if !matched &&
      !node.has_attribute("hidden") &&
      offset is Some(y) {
      hunks
      .get(index)
      .bind(hunk => self.hunk_viewport_bounds(hunk))
      .map(bounds => {
        let (top, bottom) = bounds
        y >= top && y < bottom
      })
      .unwrap_or(false)
    } else {
      false
    }
    if hovered {
      matched = true
      if !node.has_attribute("data-hovered") {
        node.set_attribute("data-hovered", "true")
      }
    } else if node.has_attribute("data-hovered") {
      node.remove_attribute("data-hovered")
    }
  }
}

///|
fn DiffEditorWidget::render_hunk_actions(self : DiffEditorWidget) -> Unit {
  let mut focused : (Int, Int?)? = None
  for (index, node) in self.hunk_actions {
    if @base_browser.element_contains_active_element(node) {
      focused = Some(
        (
          index,
          [
            for button in node.query_selector_all("button") => button
          ].search_by(button => {
            @base_browser.element_contains_active_element(button)
          }),
        ),
      )
    }
  }
  self.clear_hunk_actions()
  guard self.hunk_action_renderer is Some(render) else { return }
  for index, _ in self.get_hunks() {
    if render(index) is Some(content) {
      let wrapper = @rdom.document().create_element("div")
      wrapper.set_attribute("class", "moonbit-diff-hunk-action")
      wrapper.add_event_listener("wheel", event => {
        if self.options.handle_mouse_wheel {
          self.editors.modified.delegate_scroll_from_mouse_wheel_event(event)
          |> ignore
        }
      })
      wrapper.append_child(content.as_node())
      self.root.append_child(wrapper.as_node())
      self.hunk_actions.push((index, wrapper))
      if focused is Some((focused_index, action_index)) &&
        focused_index == index {
        let action = action_index
          .bind(index => {
            [
              for button in wrapper.query_selector_all("button") => button
            ].get(index)
          })
          .unwrap_or(content)
        @base_browser.focus_prevent_scroll(action)
      }
    }
  }
  self.layout_hunk_actions()
}

///|
/// Pixel bounds relative to the widget viewport, also usable by outer-scroll
/// hosts. Original lines retain deletion geometry in both Split and Inline.
pub fn DiffEditorWidget::get_hunk_viewport_bounds(
  self : DiffEditorWidget,
  index : Int,
) -> (Double, Double)? {
  let hunks = self.get_hunks()
  guard index >= 0 && index < hunks.length() else { return None }
  self.hunk_viewport_bounds(hunks[index])
}

///|
fn DiffEditorWidget::hunk_viewport_bounds(
  self : DiffEditorWidget,
  hunk : DiffHunk,
) -> (Double, Double)? {
  let mapping = hunk.reveal_mapping
  let mut bounds : (Double, Double)? = None
  for
    (pane, range) in [
      (self.editors.original, mapping.original),
      (self.editors.modified, mapping.modified),
    ] {
    guard !range.is_empty() && pane.get_model() is Some(model) else { continue }
    let start = range.start_line_number.clamp(min=1, max=model.get_line_count())
    let end = (range.end_line_number_exclusive - 1).clamp(
      min=start,
      max=model.get_line_count(),
    )
    if pane.get_vertical_reveal_bounds(
        Range(start, 1, end, model.get_line_max_column(end)),
      )
      is Some((top, bottom)) {
      let top = top - self.editors.modified.get_scroll_top()
      let bottom = bottom - self.editors.modified.get_scroll_top()
      bounds = Some(
        match bounds {
          None => (top, bottom)
          Some((previous_top, previous_bottom)) =>
            (previous_top.min(top), previous_bottom.max(bottom))
        },
      )
    }
  }
  bounds
}

///|
fn DiffEditorWidget::layout_hunk_actions(self : DiffEditorWidget) -> Unit {
  let height = self.root.get_client_height()
  for (index, node) in self.hunk_actions {
    match self.get_hunk_viewport_bounds(index) {
      Some((top, bottom)) if bottom > 0.0 && top < height => {
        node.remove_attribute("hidden")
        @base_browser.set_style_property(
          node,
          "--diff-hunk-height",
          "\{bottom - top.max(0.0)}px",
        )
        @base_browser.set_style_property(node, "top", "\{top.max(0.0)}px")
      }
      _ => node.set_attribute("hidden", "")
    }
  }
  self.update_hunk_action_hover()
}

///|
/// Select without moving the cursor or scrolling. Subsequent navigation starts
/// at this hunk, so manual reading and toolbar navigation share one position.
pub fn DiffEditorWidget::select_hunk(
  self : DiffEditorWidget,
  index : Int,
) -> Unit {
  guard index >= 0 && index < self.get_hunks().length() else { return }
  self.navigate_from_active_hunk = true
  self.set_active_hunk_index(Some(index))
}

///|
fn hunk_distance(top : Double, bottom : Double, offset : Double) -> Double {
  if offset < top {
    top - offset
  } else {
    (offset - bottom).max(0.0)
  }
}

///|
fn DiffEditorWidget::track_hunk_at_viewport_offset(
  self : DiffEditorWidget,
  offset : Double,
) -> Unit {
  let mut nearest : (Int, Double)? = None
  for index, _ in self.get_hunks() {
    if self.get_hunk_viewport_bounds(index) is Some((top, bottom)) {
      let distance = hunk_distance(top, bottom, offset)
      if nearest is None ||
        (nearest is Some((_, previous)) && distance < previous) {
        nearest = Some((index, distance))
      }
    }
  }
  if nearest is Some((index, _)) {
    self.select_hunk(index)
  }
}

///|
fn DiffEditorWidget::navigate_active_hunk(
  self : DiffEditorWidget,
  direction : Int,
  wrap : Bool,
) -> Bool {
  let hunks = self.get_hunks()
  guard self.active_hunk_index is Some(current) && !hunks.is_empty() else {
    return false
  }
  let next = current + direction
  guard wrap || (next >= 0 && next < hunks.length()) else { return false }
  let index = (next + hunks.length()) % hunks.length()
  self.reveal_navigation_target({
    change_index: index,
    change_count: hunks.length(),
    change: hunks[index].reveal_mapping,
  })
}

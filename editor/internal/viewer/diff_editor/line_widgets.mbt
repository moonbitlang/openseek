///|
/// A host-owned inline block in model coordinates. Original blocks in Inline
/// layout follow the deleted block containing their line; unchanged lines map
/// exactly to the modified side. Hosts label original ranges in their content.
pub(all) struct DiffLineWidget {
  original : Bool
  line : Int
  node : @rdom.Element
  on_layout : ((Double, Double, Double)?) -> Unit
}

///|
priv struct MountedDiffLineWidget {
  spec : DiffLineWidget
  mut original : Bool
  zone : @editor_browser.ViewZone
  mut id : String
  mut observer : @base_common.Disposable?
  wheel_listener : @base_common.Disposable
}

///|
fn inline_widget_line(
  line : Int,
  mappings : Array[@diff.DetailedLineRangeMapping],
) -> Int {
  let mut delta = 0
  for mapping in mappings {
    if line < mapping.original.start_line_number {
      break
    }
    if line < mapping.original.end_line_number_exclusive {
      return (mapping.modified.start_line_number - 1).max(0)
    }
    delta = mapping.modified.end_line_number_exclusive -
      mapping.original.end_line_number_exclusive
  }
  (line + delta).max(0)
}

///|
fn DiffEditorWidget::line_widget_pane(
  self : DiffEditorWidget,
  original : Bool,
) -> @code_widget.CodeEditorWidget {
  if original {
    self.editors.original
  } else {
    self.editors.modified
  }
}

///|
fn line_widget_native_scroll(
  event : @rdom.Event,
  boundary : @rdom.Element,
) -> Bool {
  guard event.to_wheel_event() is Some(wheel) else { return false }
  let mut element = event.target().to_element()
  while element is Some(node) {
    if node.matches("textarea, pre") {
      let top = node.get_scroll_top()
      let left = node.get_scroll_left()
      if (wheel.get_delta_y() < 0.0 && top > 0.0) ||
        (
          wheel.get_delta_y() > 0.0 &&
          top + node.get_client_height() < node.get_scroll_height()
        ) ||
        (wheel.get_delta_x() < 0.0 && left > 0.0) ||
        (
          wheel.get_delta_x() > 0.0 &&
          left + node.get_client_width() < node.get_scroll_width()
        ) {
        return true
      }
    }
    if physical_equal(node, boundary) {
      break
    }
    element = node
      .as_node()
      .get_parent_node()
      .to_option()
      .bind(parent => parent.to_element())
  }
  false
}

///|
/// Nodes retain their identity while typing; only membership changes attach or
/// remove zones. Resize changes the existing zone rather than replacing inputs.
pub fn DiffEditorWidget::set_line_widgets(
  self : DiffEditorWidget,
  specs : Array[DiffLineWidget],
) -> Unit {
  for index = self.line_widgets.length() - 1; index >= 0; index = index - 1 {
    let mounted = self.line_widgets[index]
    if !specs.any(spec => {
        physical_equal(spec.node, mounted.spec.node) &&
        spec.original == mounted.spec.original &&
        spec.line == mounted.spec.line
      }) {
      (mounted.spec.on_layout)(None)
      if mounted.observer is Some(observer) {
        observer.dispose()
      }
      mounted.wheel_listener.dispose()
      self
      .line_widget_pane(mounted.original)
      .change_view_zones(accessor => accessor.remove_zone(mounted.id))
      self.line_widgets.remove(index) |> ignore
    }
  }
  for spec in specs {
    if self.line_widgets.any(mounted => {
        physical_equal(mounted.spec.node, spec.node)
      }) {
      continue
    }
    let original = spec.original &&
      self.layout_state.actual_layout == SideBySide
    let line = if spec.original && !original {
      inline_widget_line(
        spec.line,
        self.diff_state
        .map(state => state.mappings.map(mapping => mapping.line_range_mapping))
        .unwrap_or([]),
      )
    } else {
      spec.line
    }
    let wrapper = @rdom.document().create_element("div")
    wrapper.set_attribute("class", "moonbit-diff-line-widget")
    let zone = @editor_browser.ViewZone(
      line,
      wrapper,
      height_in_px=spec.node.get_bounding_client_rect().get_height().max(1.0),
      ordinal=100000,
      suppress_mouse_down=false,
      show_in_hidden_areas=true,
      on_dom_node_layout=(visible, top) => {
        let on_original = spec.original &&
          self.layout_state.actual_layout == SideBySide
        let host = if on_original {
          self.original_host
        } else {
          self.modified_host
        }
        let rect = host.get_bounding_client_rect()
        let inset = self.line_widget_pane(on_original).get_layout_info().content_left
        (spec.on_layout)(
          if visible {
            Some(
              (
                rect.get_left() + inset,
                rect.get_top() + top,
                (rect.get_width() - inset - 16.0).max(0.0),
              ),
            )
          } else {
            None
          },
        )
      },
    )
    let pane = self.line_widget_pane(original)
    let mut id = None
    pane.change_view_zones(accessor => id = Some(accessor.add_zone(zone)))
    guard id is Some(id) else { continue }
    let on_wheel = event => {
      // Native overflow consumes its own wheel; otherwise the surrounding
      // diff must remain scrollable even with the pointer inside a composer.
      if !line_widget_native_scroll(event, spec.node) {
        self
        .line_widget_pane(
          spec.original && self.layout_state.actual_layout == SideBySide,
        )
        .delegate_scroll_from_mouse_wheel_event(event)
        |> ignore
      }
    }
    spec.node.add_event_listener_with_options("wheel", on_wheel, passive=false)
    let wheel_listener = @base_common.Disposable::from(() => {
      spec.node.remove_event_listener("wheel", on_wheel)
    })
    let mounted : MountedDiffLineWidget = {
      spec,
      original,
      zone,
      id,
      observer: None,
      wheel_listener,
    }
    self.line_widgets.push(mounted)
    mounted.observer = @base_browser.observe_element_resize(spec.node, () => {
      if self.disposed {
        return
      }
      let height = spec.node.get_bounding_client_rect().get_height().max(1.0)
      if mounted.zone.height_in_px != Some(height) {
        mounted.zone.height_in_px = Some(height)
        self
        .line_widget_pane(mounted.original)
        .change_view_zones(accessor => accessor.layout_zone(mounted.id))
      }
    })
  }
}

///|
fn DiffEditorWidget::sync_line_widget_anchors(
  self : DiffEditorWidget,
  state : DiffState,
) -> Unit {
  let mappings = state.mappings.map(mapping => mapping.line_range_mapping)
  for mounted in self.line_widgets {
    let original = mounted.spec.original &&
      self.layout_state.actual_layout == SideBySide
    let line = if mounted.spec.original && !original {
      inline_widget_line(mounted.spec.line, mappings)
    } else {
      mounted.spec.line
    }
    if original != mounted.original {
      self
      .line_widget_pane(mounted.original)
      .change_view_zones(accessor => accessor.remove_zone(mounted.id))
      mounted.original = original
      mounted.zone.after_line_number = line
      self
      .line_widget_pane(original)
      .change_view_zones(accessor => {
        mounted.id = accessor.add_zone(mounted.zone)
      })
    } else if line != mounted.zone.after_line_number {
      mounted.zone.after_line_number = line
      self
      .line_widget_pane(original)
      .change_view_zones(accessor => accessor.layout_zone(mounted.id))
    }
  }
}

///|
/// The host owns the action (e.g. open a comment composer); the editor owns
/// model-side hit testing and positioning. None removes the affordance.
pub fn DiffEditorWidget::set_line_action(
  self : DiffEditorWidget,
  action : ((Bool, Int) -> Unit)?,
) -> Unit {
  self.line_action = action
  if self.line_action_button is Some(button) {
    if action is Some(_) &&
      self.line_action_target is Some(_) &&
      self.is_diff_up_to_date() {
      button.remove_attribute("hidden")
    } else {
      button.set_attribute("hidden", "")
    }
  }
}

///|
fn DiffEditorWidget::hide_line_action(self : DiffEditorWidget) -> Unit {
  self.line_action_target = None
  if self.line_action_button is Some(button) {
    button.set_attribute("hidden", "")
  }
}

///|
fn DiffEditorWidget::install_line_action(self : DiffEditorWidget) -> Unit {
  let button = @rdom.document().create_element("button")
  button.set_attribute("class", "moonbit-diff-line-action")
  button.set_attribute("type", "button")
  button.set_attribute("aria-label", "Add line comment")
  button.set_attribute("title", "Add line comment")
  button.set_attribute("hidden", "")
  let icon = @rdom.document().create_element("span")
  icon.set_attribute("class", "codicon codicon-add")
  icon.set_attribute("aria-hidden", "true")
  button.append_child(icon.as_node())
  button.add_event_listener("mousedown", event => {
    event.prevent_default()
    event.stop_propagation()
  })
  button.add_event_listener("click", event => {
    event.stop_propagation()
    guard self.is_diff_up_to_date() else {
      self.hide_line_action()
      return
    }
    if self.line_action is Some(action) &&
      self.line_action_target is Some((original, line)) {
      action(original, line)
    }
  })
  self.root.append_child(button.as_node())
  self.line_action_button = Some(button)
  for
    (original, pane, host) in [
      (true, self.editors.original, self.original_host),
      (false, self.editors.modified, self.modified_host),
    ] {
    self.lifetime.push(
      pane.on_mouse_move(event => {
        guard self.is_diff_up_to_date() else {
          self.hide_line_action()
          return
        }
        match event.target.type_() {
          GutterLineNumbers
          | GutterLineDecorations
          | GutterGlyphMargin
          | ContentText
          | ContentEmpty => ()
          _ => return
        }
        guard event.target.position() is Some(position) else { return }
        let line = position.line_number
        self.line_action_target = Some((original, line))
        let top = pane.get_top_for_line_number(line) - pane.get_scroll_top()
        let host_left = host.get_bounding_client_rect().get_left() -
          self.root.get_bounding_client_rect().get_left()
        let left = host_left + pane.get_layout_info().content_left - 20.0
        @base_browser.set_style_property(button, "top", "\{top}px")
        @base_browser.set_style_property(button, "left", "\{left.max(0.0)}px")
        // Keep hit testing live while the host loads its context, so enabling
        // the action does not require another mouse movement.
        if self.line_action is Some(_) {
          button.remove_attribute("hidden")
        } else {
          button.set_attribute("hidden", "")
        }
      }),
    )
    self.lifetime.push(pane.on_did_scroll_change(_ => self.hide_line_action()))
  }
  self.root.add_event_listener("mouseleave", _ => self.hide_line_action())
}

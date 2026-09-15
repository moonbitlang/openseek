// Presentation commands for the new-tab popup. Open state stays with its caller.

///|
priv struct LauncherMenu {
  toggle : @cmd.Cmd
  dismiss : @cmd.Cmd
}

///|
/// Like select_control, open in the browser's top layer after rendering.
/// CSS anchors handle fitting around the trigger; no panel-width arithmetic
/// or application-owned geometry is needed.
fn LauncherMenu::toggle(self : LauncherMenu) -> @cmd.Cmd {
  @cmd.batch([
    self.toggle,
    @cmd.custom_cmd(
      _ => {
        if @dom.document().get_element_by_id("dock-new-tab-menu").to_option()
          is Some(element) &&
          element.to_html_element() is Some(menu) {
          menu.show_popover()
          if element.query_selector("[role=menuitem]") is Some(first) &&
            first.to_html_element() is Some(button) {
            button.focus()
          }
        }
      },
      kind=@cmd.after_render,
    ),
  ])
}

///|
fn LauncherMenu::dismiss(self : LauncherMenu) -> @cmd.Cmd {
  @cmd.batch([
    self.dismiss,
    @cmd.custom_cmd(
      _ => {
        if @dom.document().get_element_by_id("dock-new-tab").to_option()
          is Some(element) &&
          element.to_html_element() is Some(button) {
          button.focus()
        }
      },
      kind=@cmd.after_render,
    ),
  ])
}

///|
/// Menu actions use arrow navigation without pretending to be selected values.
fn LauncherMenu::keydown(
  self : LauncherMenu,
  event : @dom.KeyboardEvent,
) -> @cmd.Cmd {
  let key = event.key()
  if key == "Escape" {
    event.prevent_default()
    return self.dismiss()
  }
  if key != "ArrowDown" && key != "ArrowUp" && key != "Home" && key != "End" {
    return @cmd.none
  }
  event.prevent_default()
  @cmd.custom_cmd(_ => {
    let items = @dom.document().query_selector_all(
      "#dock-new-tab-menu [role=menuitem]",
    )
    let count = items.length()
    guard count > 0 else { return }
    let mut current = 0
    if @dom.document().get_active_element() is Some(active) {
      for i, item in items.iter() {
        if item.as_node().is_same_node(active.as_node()) {
          current = i
        }
      }
    }
    let next = match key {
      "Home" => 0
      "End" => count - 1
      "ArrowUp" => if current > 0 { current - 1 } else { count - 1 }
      _ => if current + 1 < count { current + 1 } else { 0 }
    }
    if items.item(next.to_double()).to_option() is Some(item) &&
      item.to_html_element() is Some(button) {
      button.focus()
    }
  })
}

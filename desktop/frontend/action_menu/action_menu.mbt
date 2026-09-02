///|
/// Where a menu was requested. Button geometry is resolved inside this
/// module after render; pointer coordinates are used only for a context menu.
pub(all) enum Anchor {
  Button
  Pointer(Int, Int)
} derive(Debug, Eq)

///|
/// One actionable menu row. Callers describe meaning and appearance; this
/// module owns selection, dismissal, keyboard navigation, and focus.
pub(all) struct Item {
  label : String
  title : String
  icon : @html.Html?
  enabled : Bool
  destructive : Bool
  command : @cmd.Cmd
}

///|
pub(all) enum Entry {
  Action(Item)
  Separator
}

///|
/// Complete rendering input for one open menu.
pub(all) struct Menu {
  id : String
  trigger_id : String
  label : String
  anchor : Anchor
  entries : Array[Entry]
  dismiss : @cmd.Cmd
}

///|
fn focus_element(id : String, after_render : Bool) -> @cmd.Cmd {
  let focus = _ => {
    if @dom.document().get_element_by_id(id).to_option() is Some(element) {
      let _ : @js.Value = @js.Value::cast_from(element).apply_with_string(
        "focus",
        ([] : Array[@js.Value]),
      )
    }
  }
  if after_render {
    @cmd.custom_cmd(focus, kind=@cmd.after_render)
  } else {
    @cmd.custom_cmd(focus)
  }
}

///|
fn item_id(menu_id : String, index : Int) -> String {
  "\{menu_id}-item-\{index}"
}

///|
fn Menu::enabled_count(self : Menu) -> Int {
  let mut count = 0
  for entry in self.entries {
    if entry is Action(item) && item.enabled {
      count += 1
    }
  }
  count
}

///|
fn Menu::focus_item(self : Menu, index : Int, after_render : Bool) -> @cmd.Cmd {
  focus_element(item_id(self.id, index), after_render)
}

///|
fn Menu::focus_trigger(self : Menu, after_render : Bool) -> @cmd.Cmd {
  focus_element(self.trigger_id, after_render)
}

///|
fn set_style(element : @dom.Element, key : String, value : String) -> Unit {
  let style : @js.Value = @js.Value::cast_from(element).get_with_string("style")
  let _ : @js.Value = style.apply_with_string("setProperty", [
    @js.Value::cast_from(key),
    @js.Value::cast_from(value),
  ])
}

///|
fn clamp(value : Double, low : Double, high : Double) -> Double {
  if value < low {
    low
  } else if value > high {
    high
  } else {
    value
  }
}

///|
/// Resolve the anchor only after the menu exists, then keep the whole surface
/// inside the visual viewport. The hidden first frame prevents a flash at the
/// document origin while Rabbita commits the DOM.
fn position(menu_id : String, trigger_id : String, anchor : Anchor) -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      guard @dom.document().get_element_by_id(menu_id).to_option() is Some(menu) else {
        return
      }
      let window = @dom.window()
      let mut viewport_left = 0.0
      let mut viewport_top = 0.0
      let mut viewport_width = window.inner_width().to_double()
      let mut viewport_height = window.inner_height().to_double()
      if window.get_visual_viewport() is Some(viewport) {
        viewport_left = viewport.get_offset_left()
        viewport_top = viewport.get_offset_top()
        viewport_width = viewport.get_width()
        viewport_height = viewport.get_height()
      }
      let menu_rect = menu.get_bounding_client_rect()
      let menu_width = menu_rect.get_width()
      let menu_height = menu_rect.get_height()
      let gap = 2.0
      let (wanted_left, wanted_top) = match anchor {
        Pointer(x, y) => (x.to_double(), y.to_double())
        Button => {
          guard @dom.document().get_element_by_id(trigger_id).to_option()
            is Some(trigger) else {
            return
          }
          let trigger_rect = trigger.get_bounding_client_rect()
          let below = viewport_top + viewport_height - trigger_rect.get_bottom()
          let above = trigger_rect.get_top() - viewport_top
          let top = if below >= menu_height || below >= above {
            trigger_rect.get_bottom() + gap
          } else {
            trigger_rect.get_top() - menu_height - gap
          }
          (trigger_rect.get_right() - menu_width, top)
        }
      }
      let margin = 4.0
      let max_left = viewport_left + viewport_width - menu_width - margin
      let max_top = viewport_top + viewport_height - menu_height - margin
      let left = clamp(
        wanted_left,
        viewport_left + margin,
        if max_left < viewport_left + margin {
          viewport_left + margin
        } else {
          max_left
        },
      )
      let top = clamp(
        wanted_top,
        viewport_top + margin,
        if max_top < viewport_top + margin {
          viewport_top + margin
        } else {
          max_top
        },
      )
      set_style(menu, "left", "\{left.to_int()}px")
      set_style(menu, "top", "\{top.to_int()}px")
      menu.set_attribute("data-positioned", "true")
    },
    kind=@cmd.after_render,
  )
}

///|
/// Open commands always measure and focus after the caller has committed its
/// open state. Callers never inspect button geometry themselves.
fn open(
  menu_id : String,
  trigger_id : String,
  anchor : Anchor,
  show : @cmd.Emit[Anchor],
) -> @cmd.Cmd {
  @cmd.batch([
    show(anchor),
    position(menu_id, trigger_id, anchor),
    focus_element(item_id(menu_id, 0), true),
  ])
}

///|
/// Attributes for the ellipsis trigger. Opening, positioning, and focus are a
/// single operation; an already-open trigger toggles the menu closed.
pub fn button_attrs(
  menu_id : String,
  trigger_id : String,
  is_open : Bool,
  show : @cmd.Emit[Anchor],
  dismiss : @cmd.Cmd,
) -> @html.Attrs {
  @html.Attrs::build()
  .id(trigger_id)
  .data_set("action-menu-owner", trigger_id)
  .aria_haspopup("menu")
  .aria_controls(menu_id)
  .aria_expanded(is_open.to_string())
  .on_click(event => {
    event.stop_propagation()
    if is_open {
      dismiss
    } else {
      open(menu_id, trigger_id, Button, show)
    }
  })
}

///|
/// Attributes for a surface that opens the same menu on right click.
pub fn context_attrs(
  menu_id : String,
  trigger_id : String,
  show : @cmd.Emit[Anchor],
) -> @html.Attrs {
  @html.Attrs::build()
  .data_set("action-menu-owner", trigger_id)
  .on_contextmenu(event => {
    event.prevent_default()
    open(
      menu_id,
      trigger_id,
      Pointer(event.get_client_x(), event.get_client_y()),
      show,
    )
  })
}

///|
fn Menu::item_attrs(
  self : Menu,
  index : Int,
  count : Int,
  select : @cmd.Cmd,
) -> @html.Attrs {
  @html.Attrs::build()
  .id(item_id(self.id, index))
  .role("menuitem")
  .on_click(event => {
    event.stop_propagation()
    select
  })
  .on_keydown(event => {
    let next = match event.key() {
      "ArrowDown" => Some(if index + 1 < count { index + 1 } else { 0 })
      "ArrowUp" => Some(if index > 0 { index - 1 } else { count - 1 })
      "Home" => Some(0)
      "End" => Some(count - 1)
      _ => None
    }
    if next is Some(next) {
      event.prevent_default()
      self.focus_item(next, false)
    } else if event.key() == "Escape" {
      event.prevent_default()
      @cmd.batch([self.dismiss, self.focus_trigger(true)])
    } else if event.key() == "Tab" {
      self.dismiss
    } else {
      @cmd.none
    }
  })
}

///|
pub fn Menu::render(self : Menu) -> @html.Html {
  let rows : Array[@html.Html] = []
  let count = self.enabled_count()
  let mut index = 0
  for entry in self.entries {
    match entry {
      Separator =>
        rows.push(
          @html.div(
            class="action-menu-separator",
            attrs=@html.Attrs::build().role("separator"),
            "",
          ),
        )
      Action(item) => {
        let class = if item.destructive {
          "action-menu-item destructive"
        } else {
          "action-menu-item"
        }
        let attrs = if item.enabled {
          self.item_attrs(index, count, item.command)
        } else {
          @html.Attrs::build().role("menuitem").aria_disabled("true")
        }
        rows.push(
          @html.button(
            class~,
            type_="button",
            title=item.title,
            disabled=!item.enabled,
            attrs~,
            [
              match item.icon {
                Some(icon) => icon
                None => @html.span(class="action-menu-icon-placeholder", "")
              },
              @html.span(item.label),
            ],
          ),
        )
        if item.enabled {
          index += 1
        }
      }
    }
  }
  @html.div(
    class="action-menu",
    attrs=@html.Attrs::build()
      .id(self.id)
      .role("menu")
      .aria_label(self.label)
      .data_set("positioned", "false")
      .on_click(event => {
        event.stop_propagation()
        @cmd.none
      })
      .on_contextmenu(event => {
        event.prevent_default()
        event.stop_propagation()
        @cmd.none
      }),
    rows,
  )
}

///|
priv suberror DismissSubscription {
  DismissSubscription(String, @cmd.Emit[Unit])
}

///|
/// Close an open menu when a click or context-menu request starts outside its
/// trigger or owning row. Menu-item clicks therefore dismiss from the capture
/// listener before their caller-owned action runs at the target. Exact owner
/// comparison lets another row's trigger close this menu while opening its own
/// in the same gesture.
pub fn dismiss_subscription(
  key : String,
  trigger_id : String,
  emit : @cmd.Emit[Unit],
) -> @sub.Sub {
  @sub.custom_sub(key, Global, DismissSubscription(trigger_id, emit), (
    payload,
    scheduler,
  ) => {
    guard payload is DismissSubscription(owner, emit) else { return None }
    let mut emit = emit
    let target = @dom.document().as_event_target()
    let window = @dom.window().as_event_target()
    let listener : @dom.Listener = event => {
      if event.target().to_element() is Some(element) &&
        element.closest("[data-action-menu-owner]") is Some(owned) &&
        owned.get_attribute("data-action-menu-owner") is Some(found) &&
        found == owner {
        return
      }
      scheduler.add(emit(()))
    }
    target.add_event_listener_with_options("click", listener, capture=true)
    target.add_event_listener_with_options(
      "contextmenu",
      listener,
      capture=true,
    )
    let blur_listener : @dom.Listener = _ => scheduler.add(emit(()))
    window.add_event_listener("blur", blur_listener)
    Some({
      unload: _ => {
        target.remove_event_listener_with_options(
          "click",
          listener,
          capture=true,
        )
        target.remove_event_listener_with_options(
          "contextmenu",
          listener,
          capture=true,
        )
        window.remove_event_listener("blur", blur_listener)
      },
      update_tagger: payload => {
        guard payload is DismissSubscription(next_owner, next_emit) &&
          next_owner == owner else {
          return
        }
        emit = next_emit
      },
    })
  })
}

///|
pub extend Anchor with Debug::{to_repr}

///|
pub extend Anchor with Eq::{equal, not_equal}

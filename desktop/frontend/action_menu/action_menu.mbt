///|
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
/// Current menu meaning for one target. The open state retains only the
/// target and gesture; callers resolve this definition from their latest
/// input whenever it is rendered or acted upon.
pub(all) struct Definition {
  label : String
  entries : Array[Entry]
}

///|
priv enum Anchor {
  Button
  Pointer(Int, Int)
} derive(Eq)

///|
priv struct Open {
  target : String
  anchor : Anchor
  restore_focus_id : String?
} derive(Eq)

///|
priv struct State {
  menu : Open?
} derive(Eq)

///|
priv enum Msg {
  Open(Open)
  Close
}

///|
const OpenEvent : String = "openseek-action-menu-open"

///|
fn menu_id(target : String) -> String {
  target + ":actions"
}

///|
fn trigger_id(target : String) -> String {
  target + ":actions-trigger"
}

///|
fn item_id(target : String, index : Int) -> String {
  menu_id(target) + ":item:\{index}"
}

///|
fn focused_element_id() -> String? {
  guard @dom.document().get_active_element() is Some(element) else {
    return None
  }
  element.get_attribute("id")
}

///|
fn remember_context_focus(event : @dom.MouseEvent) -> @cmd.Cmd {
  guard event.get_button() == 2 &&
    event.current_target().to_option() is Some(target) &&
    target.to_element() is Some(element) else {
    return @cmd.none
  }
  match focused_element_id() {
    Some(id) => element.set_attribute("data-action-menu-restore-focus", id)
    None => element.remove_attribute("data-action-menu-restore-focus")
  }
  @cmd.none
}

///|
fn remembered_context_focus(event : @dom.MouseEvent) -> String? {
  guard event.current_target().to_option() is Some(target) &&
    target.to_element() is Some(element) else {
    return None
  }
  element.get_attribute("data-action-menu-restore-focus")
}

///|
fn dispatch_open(open : Open) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => {
    let detail = @js.Object::new()
    detail["target"] = open.target
    match open.anchor {
      Button => detail["anchor"] = "button"
      Pointer(x, y) => {
        detail["anchor"] = "pointer"
        detail["x"] = x
        detail["y"] = y
      }
    }
    if open.restore_focus_id is Some(id) {
      detail["restoreFocusId"] = id
    }
    let event = @dom.CustomEvent::new(
      OpenEvent,
      detail=@js.Optional::from_option(Some(detail.to_value())),
    )
    @dom.document().as_event_target().dispatch_event(event.as_event())
  })
}

///|
/// Build an ellipsis trigger for a stable target. The menu component owns
/// toggle state, positioning, and focus.
pub fn button_attrs(target : String) -> @html.Attrs {
  @html.Attrs::build()
  .id(trigger_id(target))
  .data_set("action-menu-owner", target)
  .aria_haspopup("menu")
  .aria_controls(menu_id(target))
  .on_click(event => {
    event.stop_propagation()
    dispatch_open({
      target,
      anchor: Button,
      restore_focus_id: focused_element_id(),
    })
  })
}

///|
/// Build the context-menu entry point for a stable target.
pub fn context_attrs(target : String) -> @html.Attrs {
  @html.Attrs::build()
  .data_set("action-menu-context", target)
  .on_mousedown(event => remember_context_focus(event))
  .on_contextmenu(event => {
    event.prevent_default()
    dispatch_open({
      target,
      anchor: Pointer(event.get_client_x(), event.get_client_y()),
      restore_focus_id: remembered_context_focus(event),
    })
  })
}

///|
fn parse_open(event : @dom.Event) -> Open? {
  guard event.to_custom_event() is Some(event) else { return None }
  let detail = event.get_detail()
  let target : @js.Value = detail.get_with_string("target")
  let anchor : @js.Value = detail.get_with_string("anchor")
  guard target.is_string() && anchor.is_string() else { return None }
  let anchor = match anchor.cast() {
    "button" => Button
    "pointer" => {
      let x : @js.Value = detail.get_with_string("x")
      let y : @js.Value = detail.get_with_string("y")
      guard x.is_number() && y.is_number() else { return None }
      Pointer(x.cast(), y.cast())
    }
    _ => return None
  }
  let restore : @js.Value = detail.get_with_string("restoreFocusId")
  Some({
    target: target.cast(),
    anchor,
    restore_focus_id: if restore.is_string() {
      Some(restore.cast())
    } else {
      None
    },
  })
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
fn set_trigger_open(target : String, open : Bool) -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      if @dom.document().get_element_by_id(trigger_id(target)).to_option()
        is Some(trigger) {
        trigger.set_attribute("aria-expanded", open.to_string())
      }
    },
    kind=@cmd.after_render,
  )
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
fn position(target : String, anchor : Anchor) -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      guard @dom.document().get_element_by_id(menu_id(target)).to_option()
        is Some(menu) else {
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
          guard @dom.document()
            .get_element_by_id(trigger_id(target))
            .to_option()
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
fn Definition::enabled_indices(self : Definition) -> Array[Int] {
  let result : Array[Int] = []
  for index, entry in self.entries {
    if entry is Action(item) && item.enabled {
      result.push(index)
    }
  }
  result
}

///|
fn enabled_position(indices : Array[Int], index : Int) -> Int? {
  for position, candidate in indices {
    if candidate == index {
      return Some(position)
    }
  }
  None
}

///|
fn item_attrs(
  open : Open,
  enabled : Array[Int],
  index : Int,
  select : @cmd.Cmd,
  dismiss : @cmd.Cmd,
) -> @html.Attrs {
  @html.Attrs::build()
  .id(item_id(open.target, index))
  .role("menuitem")
  .on_click(event => {
    event.stop_propagation()
    @cmd.batch([dismiss, @cmd.delay(select, 0)])
  })
  .on_contextmenu(event => {
    event.prevent_default()
    event.stop_propagation()
    @cmd.batch([dismiss, @cmd.delay(select, 0)])
  })
  .on_keydown(event => {
    guard enabled_position(enabled, index) is Some(position) else {
      return @cmd.none
    }
    let destination = match event.key() {
      "ArrowDown" => Some(enabled[(position + 1) % enabled.length()])
      "ArrowUp" =>
        Some(
          enabled[if position > 0 {
            position - 1
          } else {
            enabled.length() - 1
          }],
        )
      "Home" => Some(enabled[0])
      "End" => Some(enabled[enabled.length() - 1])
      _ => None
    }
    if destination is Some(destination) {
      event.prevent_default()
      focus_element(item_id(open.target, destination), false)
    } else if event.key() == "Escape" {
      event.prevent_default()
      @cmd.batch([
        dismiss,
        match open.restore_focus_id {
          Some(id) => focus_element(id, true)
          None => @cmd.none
        },
      ])
    } else if event.key() == "Tab" {
      @cmd.delay(dismiss, 0)
    } else if event.key() == "Enter" || event.key() == " " {
      event.prevent_default()
      @cmd.batch([dismiss, @cmd.delay(select, 0)])
    } else {
      @cmd.none
    }
  })
}

///|
fn render_menu(
  open : Open,
  definition : Definition,
  dismiss : @cmd.Cmd,
) -> @html.Html {
  let rows : Array[@html.Html] = []
  let enabled = definition.enabled_indices()
  for index, entry in definition.entries {
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
          item_attrs(open, enabled, index, item.command, dismiss)
        } else {
          @html.Attrs::build()
          .role("menuitem")
          .aria_disabled("true")
          .on_click(event => {
            event.stop_propagation()
            @cmd.none
          })
          .on_contextmenu(event => {
            event.prevent_default()
            event.stop_propagation()
            @cmd.none
          })
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
      }
    }
  }
  @html.div(
    class="action-menu",
    attrs=@html.Attrs::build()
      .id(menu_id(open.target))
      .role("menu")
      .aria_label(definition.label)
      .tabindex(-1)
      .data_set("action-menu-surface", open.target)
      .data_set("positioned", "false")
      .on_click(event => {
        event.stop_propagation()
        @cmd.none
      })
      .on_contextmenu(event => {
        event.prevent_default()
        event.stop_propagation()
        @cmd.none
      })
      .on_keydown(event => {
        guard focused_element_id() == Some(menu_id(open.target)) else {
          return @cmd.none
        }
        let destination = match event.key() {
          "ArrowDown" | "Home" => Some(enabled[0])
          "ArrowUp" | "End" => Some(enabled[enabled.length() - 1])
          _ => None
        }
        if destination is Some(destination) {
          event.prevent_default()
          focus_element(item_id(open.target, destination), false)
        } else if event.key() == "Escape" {
          event.prevent_default()
          @cmd.batch([
            dismiss,
            match open.restore_focus_id {
              Some(id) => focus_element(id, true)
              None => @cmd.none
            },
          ])
        } else if event.key() == "Tab" {
          @cmd.delay(dismiss, 0)
        } else {
          @cmd.none
        }
      }),
    rows,
  )
}

///|
priv suberror OpenSubscription {
  OpenSubscription(@cmd.Emit[Open])
}

///|
fn open_subscription(emit : @cmd.Emit[Open]) -> @sub.Sub {
  @sub.custom_sub("action-menu-open", Local, OpenSubscription(emit), (
    payload,
    scheduler,
  ) => {
    guard payload is OpenSubscription(emit) else { return None }
    let mut emit = emit
    let target = @dom.document().as_event_target()
    let listener : @dom.Listener = event => {
      if parse_open(event) is Some(open) {
        scheduler.add(emit(open))
      }
    }
    target.add_event_listener(OpenEvent, listener)
    Some({
      unload: _ => target.remove_event_listener(OpenEvent, listener),
      update_tagger: payload => {
        guard payload is OpenSubscription(next) else { return }
        emit = next
      },
    })
  })
}

///|
priv suberror DismissSubscription {
  DismissSubscription(String, @cmd.Emit[Unit])
}

///|
fn dismiss_subscription(
  target_key : String,
  emit : @cmd.Emit[Unit],
) -> @sub.Sub {
  @sub.custom_sub(
    "action-menu-dismiss",
    Local,
    DismissSubscription(target_key, emit),
    (payload, scheduler) => {
      guard payload is DismissSubscription(owner, emit) else { return None }
      let mut emit = emit
      let document = @dom.document().as_event_target()
      let dom_window = @dom.window()
      let window = dom_window.as_event_target()
      let click_listener : @dom.Listener = event => {
        if event.target().to_element() is Some(element) {
          if element.closest("[data-action-menu-surface]") is Some(_) ||
            element.closest("[data-action-menu-owner]") is Some(_) {
            return
          }
        }
        let _ = @dom.window().set_timeout(() => scheduler.add(emit(())), 0)
      }
      let context_listener : @dom.Listener = event => {
        if event.target().to_element() is Some(element) {
          if element.closest("[data-action-menu-surface]") is Some(_) ||
            element.closest("[data-action-menu-context]") is Some(_) ||
            element.closest("[data-action-menu-owner]") is Some(_) {
            return
          }
        }
        scheduler.add(emit(()))
      }
      document.add_event_listener_with_options(
        "click",
        click_listener,
        capture=true,
      )
      document.add_event_listener("contextmenu", context_listener)
      let blur_listener : @dom.Listener = _ => scheduler.add(emit(()))
      let resize_listener : @dom.Listener = _ => scheduler.add(emit(()))
      window.add_event_listener("blur", blur_listener)
      window.add_event_listener("resize", resize_listener)
      let mut viewport_target : @dom.EventTarget? = None
      if dom_window.get_visual_viewport() is Some(viewport) {
        let target = viewport.as_event_target()
        target.add_event_listener("resize", resize_listener)
        viewport_target = Some(target)
      }
      let mut scroll_target : @dom.EventTarget? = None
      let scroll_listener : @dom.Listener = _ => scheduler.add(emit(()))
      if @dom.document().query_selector(".sidebar-main").to_option()
        is Some(sidebar) {
        let target = sidebar.as_event_target()
        target.add_event_listener("scroll", scroll_listener)
        scroll_target = Some(target)
      }
      Some({
        unload: _ => {
          document.remove_event_listener_with_options(
            "click",
            click_listener,
            capture=true,
          )
          document.remove_event_listener("contextmenu", context_listener)
          window.remove_event_listener("blur", blur_listener)
          window.remove_event_listener("resize", resize_listener)
          if viewport_target is Some(target) {
            target.remove_event_listener("resize", resize_listener)
          }
          if scroll_target is Some(target) {
            target.remove_event_listener("scroll", scroll_listener)
          }
        },
        update_tagger: payload => {
          guard payload is DismissSubscription(next_owner, next_emit) &&
            next_owner == owner else {
            return
          }
          emit = next_emit
        },
      })
    },
  )
}

///|
priv suberror FocusSubscription {
  FocusSubscription(String, Array[Int]?, @cmd.Emit[Unit])
}

///|
/// Close when the open target is no longer actionable. Otherwise, if current
/// input disables the focused entry, move to the next enabled entry and fall
/// back to the previous one.
fn focus_subscription(
  target : String,
  enabled : Array[Int]?,
  close : @cmd.Emit[Unit],
) -> @sub.Sub {
  @sub.custom_sub(
    "action-menu-focus:\{target}",
    Local,
    FocusSubscription(target, enabled, close),
    (payload, scheduler) => {
      guard payload is FocusSubscription(target, enabled, close) else {
        return None
      }
      let mut previous = enabled.unwrap_or([])
      let mut close = close
      if enabled is None || previous.is_empty() {
        scheduler.add(close(()))
      }
      Some({
        unload: _ => (),
        update_tagger: payload => {
          guard payload
            is FocusSubscription(next_target, next_enabled, next_close) &&
            next_target == target else {
            return
          }
          close = next_close
          guard next_enabled is Some(next) && !next.is_empty() else {
            scheduler.add(close(()))
            previous = []
            return
          }
          guard focused_element_id() is Some(focused) else {
            previous = next
            return
          }
          let mut old_index : Int? = None
          for index in previous {
            if focused == item_id(target, index) {
              old_index = Some(index)
            }
          }
          if old_index is Some(old_index) &&
            enabled_position(next, old_index) is None {
            let mut replacement : Int? = None
            for index in next {
              if replacement is None && index > old_index {
                replacement = Some(index)
              }
            }
            if replacement is None {
              replacement = Some(next[next.length() - 1])
            }
            if replacement is Some(index) {
              let _ = @dom.window().set_timeout(
                () => {
                  scheduler.add(focus_element(item_id(target, index), false))
                },
                0,
              )
            }
          }
          previous = next
        },
      })
    },
  )
}

///|
/// Own one WebView menu surface. Rows only dispatch stable targets; the
/// resolver supplies current labels, enabled state, and commands.
pub fn[Input : Eq] component(
  input : @rabbita.Val[Input],
  resolve : (Input, String) -> Definition?,
) -> @rabbita.Val[@html.Html] {
  let (state, emit) = @rabbita.create_state_with_input(
    input~,
    init=(_, _) => ({ menu: None, }, @cmd.none),
    update=(state, input, msg, _) => {
      match msg {
        Open(next) => {
          if next.anchor is Button &&
            state.menu is Some(current) &&
            current.target == next.target {
            return ({ menu: None, }, set_trigger_open(next.target, false))
          }
          guard resolve(input, next.target) is Some(definition) &&
            definition.enabled_indices() is [_, ..] else {
            return (state, @cmd.none)
          }
          let close_previous = match state.menu {
            Some(current) if current.target != next.target =>
              set_trigger_open(current.target, false)
            _ => @cmd.none
          }
          (
            { menu: Some(next), },
            @cmd.batch([
              close_previous,
              set_trigger_open(next.target, true),
              position(next.target, next.anchor),
              focus_element(menu_id(next.target), true),
            ]),
          )
        }
        Close => {
          let command = match state.menu {
            Some(current) => set_trigger_open(current.target, false)
            None => @cmd.none
          }
          ({ menu: None, }, command)
        }
      }
    },
    subscriptions=(state, input, emit) => {
      let open = open_subscription(emit.map(open => Msg::Open(open)))
      guard state.menu is Some(menu) else { return open }
      let enabled = resolve(input, menu.target).map(definition => {
        definition.enabled_indices()
      })
      let focus = focus_subscription(
        menu.target,
        enabled,
        emit.map((_ : Unit) => Msg::Close),
      )
      guard enabled is Some(enabled) && !enabled.is_empty() else {
        return @sub.batch([open, focus])
      }
      @sub.batch([
        open,
        dismiss_subscription(menu.target, emit.map((_ : Unit) => Msg::Close)),
        focus,
      ])
    },
  )
  state.map2(input, (state, input) => {
    guard state.menu is Some(open) &&
      resolve(input, open.target) is Some(definition) &&
      !definition.enabled_indices().is_empty() else {
      return @html.nothing
    }
    render_menu(open, definition, emit(Close))
  })
}

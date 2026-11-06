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
#derive(Eq)
priv enum Anchor {
  Button
  Pointer(Int32, Int32)
}

///|
#derive(Eq)
priv struct Open {
  target : String
  anchor : Anchor
  restore_focus_id : String?
}

///|
#derive(Eq)
priv struct State {
  menu : Open?
}

///|
priv enum Msg {
  Open(Open)
  Close(Open)
}

///|
const OpenEvent : String = "openseek-action-menu-open"

///|
const TemporaryFocusAttribute : String = "data-action-menu-temporary-focus"

///|
fn menu_id(target : String) -> String {
  target + ":actions-content"
}

///|
fn trigger_id(target : String) -> String {
  target + ":actions-trigger"
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
pub fn button_attrs(
  target : String,
  align_right~ : Bool = true,
  open_upward~ : Bool = false,
) -> @html.Attrs {
  @html.Attrs::build()
  .id(trigger_id(target))
  .data_set("action-menu-owner", target)
  .data_set("action-menu-align", if align_right { "end" } else { "start" })
  .data_set("action-menu-side", if open_upward { "top" } else { "bottom" })
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
  .id(target + ":context-trigger")
  .data_set("action-menu-context", target)
  .aria_haspopup("menu")
  .aria_controls(target + ":pointer-menu-content")
  .on_mousedown(event => remember_context_focus(event))
  .on_contextmenu(event => {
    event.prevent_default()
    dispatch_open({
      target,
      anchor: Pointer(
        event.get_client_x().to_int(),
        event.get_client_y().to_int(),
      ),
      restore_focus_id: remembered_context_focus(event),
    })
  })
  .on_keydown(event => {
    guard event.key() == "ContextMenu" ||
      (event.key() == "F10" && event.shift_key()) else {
      return @cmd.none
    }
    guard event.current_target().to_option() is Some(target_element) &&
      target_element.to_element() is Some(element) else {
      return @cmd.none
    }
    event.prevent_default()
    event.stop_propagation()
    let rect = element.get_bounding_client_rect()
    dispatch_open({
      target,
      anchor: Pointer(rect.get_left().to_int(), rect.get_bottom().to_int()),
      restore_focus_id: focused_element_id(),
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
        ([] : FixedArray[@js.Value]),
      )
      if element.get_attribute(TemporaryFocusAttribute) is Some(focus_id) &&
        focus_id == id {
        element.remove_attribute(TemporaryFocusAttribute)
        element.remove_attribute("id")
      }
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
      if @dom.document()
        .get_element_by_id(target + ":context-trigger")
        .to_option()
        is Some(trigger) {
        trigger.set_attribute("aria-expanded", open.to_string())
      }
    },
    kind=@cmd.after_render,
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
fn Definition::has_enabled_actions(self : Definition) -> Bool {
  self.entries.any(entry => entry is Action(item) && item.enabled)
}

///|
fn Definition::has_actions(self : Definition) -> Bool {
  self.entries.any(entry => entry is Action(_))
}

///|
fn Definition::revision(self : Definition) -> String {
  Repr::Repr(
    (
      self.label,
      self.entries.map(entry => {
        match entry {
          Separator => None
          Action(item) =>
            Some((item.label, item.title, item.enabled, item.destructive))
        }
      }),
    ),
  ).to_string()
}

///|
fn Open::key(self : Open) -> String {
  let anchor = match self.anchor {
    Button => self.target + ":button"
    Pointer(x, y) => self.target + ":context:\{x}:\{y}"
  }
  anchor + ":" + self.restore_focus_id.unwrap_or("")
}

///|
fn surface_attrs(open : Open, close : @cmd.Cmd) -> @html.Attrs {
  let attrs = @html.Attrs::build()
    .data_set("action-menu-surface", open.target)
    .on_keydown(event => {
      guard event.key() == "Escape" &&
        !event.repeat() &&
        !event.is_composing() &&
        !event.ctrl_key() &&
        !event.meta_key() &&
        !event.alt_key() &&
        !event.shift_key() else {
        return @cmd.none
      }
      event.prevent_default()
      event.stop_propagation()
      @cmd.batch([
        close,
        open.restore_focus_id.map_or(@cmd.none, id => focus_element(id, true)),
      ])
    })
    .on_click(event => {
      event.stop_propagation()
      @cmd.none
    })
    .on_contextmenu(event => {
      event.prevent_default()
      event.stop_propagation()
      @cmd.none
    })
  if open.restore_focus_id is Some(id) {
    ignore(attrs.data_set("final-focus-id", id))
  }
  attrs
}

///|
/// A row's button and menu share one scope; context menus remain owned by
/// the sidebar overlay so right-click keeps its pointer anchor and focus.
pub fn dropdown(
  target : String,
  definition : Definition,
  class~ : String,
  icon : @html.Html,
) -> @rabbita.Val[@html.Html] {
  @rui.dropdown_menu(id=target + ":actions", scope => {
    @html.fragment([
      @rui.dropdown_menu_trigger(
        scope,
        variant=Ghost,
        size=IconXs,
        class~,
        title=definition.label,
        aria_label=definition.label,
        icon,
      ),
      @rui.dropdown_menu_content(
        scope,
        align=End,
        aria_label=definition.label,
        class="action-menu",
        attrs=@html.Attrs::build().data_set("action-menu-surface", target),
        definition.entries.map(entry => {
          match entry {
            Separator => @rui.dropdown_menu_separator()
            Action(item) =>
              @rui.dropdown_menu_item(
                scope,
                disabled=!item.enabled,
                destructive=item.destructive,
                on_select=item.command,
                class="action-menu-item",
                title=item.title,
                item_children(item),
              )
          }
        }),
      ),
    ])
  })
}

///|
fn item_children(item : Item) -> Array[@html.Html] {
  [
    item.icon.unwrap_or(@html.span(class="action-menu-icon-placeholder", "")),
    @html.span(item.label),
  ]
}

///|
fn[Input : Eq] menu_component(
  input : @rabbita.Val[Input],
  open : Open,
  resolve : (Input) -> Definition?,
  close : @cmd.Cmd,
) -> @rabbita.Val[@html.Html] {
  input
  .map(input => {
    resolve(input).map_or(false, definition => definition.has_actions())
  })
  .switch_by(
    available => {
      if !available {
        let (closed, _) = @rabbita.create_state_with_init(
          init=_ => ((), close),
          update=(state, _ : Unit, _) => (state, @cmd.none),
        )
        return closed.view(_ => @html.nothing)
      }
      let changed = visible => if visible { @cmd.none } else { close }
      match open.anchor {
        Button => {
          let trigger = @dom.document()
            .get_element_by_id(trigger_id(open.target))
            .to_option()
          let side = if trigger.bind(element => {
              element.get_attribute("data-action-menu-side")
            }) ==
            Some("top") {
            @rui.Top
          } else {
            @rui.Bottom
          }
          let align = if trigger.bind(element => {
              element.get_attribute("data-action-menu-align")
            }) ==
            Some("start") {
            @rui.Start
          } else {
            @rui.End
          }
          input.switch_by(
            input => {
              @rui.dropdown_menu(
                id=open.target + ":actions",
                default_open=true,
                on_open_change=changed,
                scope => {
                  guard resolve(input) is Some(definition) else {
                    return @html.nothing
                  }
                  @rui.dropdown_menu_content(
                    scope,
                    side~,
                    align~,
                    aria_label=definition.label,
                    class="action-menu",
                    attrs=surface_attrs(open, close),
                    definition.entries.map(entry => {
                      match entry {
                        Separator => @rui.dropdown_menu_separator()
                        Action(item) =>
                          @rui.dropdown_menu_item(
                            scope,
                            disabled=!item.enabled,
                            destructive=item.destructive,
                            on_select=item.command,
                            class="action-menu-item",
                            title=item.title,
                            item_children(item),
                          )
                      }
                    }),
                  )
                },
              )
            },
            by=input => {
              resolve(input).map_or("closed", definition => {
                definition.revision()
              })
            },
          )
        }
        Pointer(x, y) =>
          input.switch_by(
            input => {
              @rui.dropdown_menu(
                id=open.target + ":pointer-menu",
                default_open=true,
                on_open_change=changed,
                scope => {
                  guard resolve(input) is Some(definition) else {
                    return @html.nothing
                  }
                  @html.fragment([
                    @rui.popover_anchor(
                      id=open.target + ":pointer-menu-trigger",
                      style=[
                        "position:fixed;left:\{x}px;top:\{y}px;width:0;height:0",
                      ],
                      @html.nothing,
                    ),
                    @rui.dropdown_menu_content(
                      scope,
                      align=Start,
                      side_offset=0,
                      aria_label=definition.label,
                      class="action-menu",
                      attrs=surface_attrs(open, close),
                      definition.entries.map(entry => {
                        match entry {
                          Separator => @rui.dropdown_menu_separator()
                          Action(item) =>
                            @rui.dropdown_menu_item(
                              scope,
                              disabled=!item.enabled,
                              destructive=item.destructive,
                              on_select=item.command,
                              class="action-menu-item",
                              title=item.title,
                              item_children(item),
                            )
                        }
                      }),
                    ),
                  ])
                },
              )
            },
            by=input => {
              resolve(input).map_or("closed", definition => {
                definition.revision()
              })
            },
          )
      }
    },
    by=available => available.to_string(),
  )
}

///|
pub fn[Input : Eq] component(
  input : @rabbita.Val[Input],
  resolve : (Input, String) -> Definition?,
  on_open_change? : @cmd.Emit[Bool],
) -> @rabbita.Val[@html.Html] {
  let notify = on_open_change.unwrap_or(_ => @cmd.none)
  let (state, emit) = @rabbita.create_state_with_input(
    input~,
    init=(_, _) => ({ menu: None, }, @cmd.none),
    update=(state, input, msg, _) => {
      match msg {
        Open(next) => {
          let previous = match state.menu {
            Some(current) => set_trigger_open(current.target, false)
            None => @cmd.none
          }
          if (
              next.anchor is Button &&
              state.menu is Some(current) &&
              current.target == next.target
            ) ||
            !(resolve(input, next.target) is Some(definition) &&
            definition.has_actions()) {
            return ({ menu: None, }, @cmd.batch([previous, notify(false)]))
          }
          (
            { menu: Some(next), },
            @cmd.batch([
              previous,
              set_trigger_open(next.target, true),
              notify(true),
            ]),
          )
        }
        Close(open) => {
          guard state.menu == Some(open) else { return (state, @cmd.none) }
          (
            { menu: None, },
            @cmd.batch([set_trigger_open(open.target, false), notify(false)]),
          )
        }
      }
    },
    subscriptions=(state, _, emit) => {
      @sub.batch(
        [
          open_subscription(emit.map(open => Msg::Open(open))),
          ..state.menu.map_or([], open => {
            [
              @dismiss.on_back("action-menu-back", level=TopLayer, _ => {
                emit(Close(open))
              }),
              @sub.on_resize(_ => emit(Close(open))),
            ]
          }),
        ],
      )
    },
  )
  state
  .map(state => state.menu)
  .switch_by(
    current => {
      match current {
        None => @rabbita.Val::constant(@html.nothing)
        Some(open) =>
          menu_component(
            input,
            open,
            input => resolve(input, open.target),
            emit(Close(open)),
          )
      }
    },
    by=current => {
      match current {
        None => "closed"
        Some(open) => open.key()
      }
    },
  )
}

///|
/// One selectable value. Labels are deliberately separate from wire values so
/// compact triggers and readable menu rows never have to expose protocol text.
pub(all) struct Option {
  value : String
  label : String
}

///|
/// One optional group inside a custom select menu. A single group renders
/// without a heading; several groups retain their boundaries in the popup.
pub(all) struct Group {
  label : String
  options : Array[Option]
}

///|
/// The two visual forms used by the desktop. Both share menu rows, keyboard
/// behavior, focus restoration, and accessibility; only their trigger geometry
/// and popup sizing differ.
pub(all) enum Presentation {
  Composer(String, Bool)
  Setting
}

///|
/// Caller-owned input for one custom select. Open state stays in the caller's
/// model; this component only renders that state and returns commands from DOM
/// events, preserving Rabbita's pure update boundary.
pub(all) struct Control {
  id : String
  groups : Array[Group]
  selected : String
  disabled : Bool
  open : Bool
  toggle : @cmd.Cmd
  dismiss : @cmd.Cmd
  change : @cmd.Emit[String]
  title : String
  aria_label : String
  presentation : Presentation
}

///|
fn Presentation::root_class(self : Presentation) -> String {
  match self {
    Composer(_, align_right) =>
      if align_right {
        "custom-select composer-picker composer-picker-right"
      } else {
        "custom-select composer-picker"
      }
    Setting => "custom-select setting-select"
  }
}

///|
fn Presentation::button_class(self : Presentation, open : Bool) -> String {
  let state = if open { " open" } else { "" }
  match self {
    Composer(_, _) => "custom-select-button composer-model" + state
    Setting => "custom-select-button setting-select-button" + state
  }
}

///|
fn Presentation::menu_class(self : Presentation) -> String {
  match self {
    Composer(_, _) => "custom-select-menu composer-picker-menu"
    Setting => "custom-select-menu setting-select-menu"
  }
}

///|
fn Presentation::trigger_contents(
  self : Presentation,
  selected_label : String,
) -> Array[@html.Html] {
  match self {
    Composer(glyph, _) =>
      [
        @html.span(class="composer-model-glyph", glyph),
        @html.span(class="composer-model-label", selected_label),
        @html.span(class="composer-model-chevron", ""),
      ]
    Setting =>
      [
        @html.span(class="setting-select-label", selected_label),
        @html.span(
          class="setting-select-chevron",
          @icons.icon(@icons.icon_chevron_down),
        ),
      ]
  }
}

///|
fn Control::menu_id(self : Control) -> String {
  self.id + "-menu"
}

///|
fn Control::root_id(self : Control) -> String {
  self.id + "-control"
}

///|
fn Control::option_id(self : Control, index : Int) -> String {
  "\{self.id}-option-\{index}"
}

///|
/// Focus writes stay inside an event command. `after_render=true` is used
/// when opening or closing changes which option nodes exist.
fn Control::focus(
  self : Control,
  option : Int?,
  after_render : Bool,
) -> @cmd.Cmd {
  let id = if option is Some(index) { self.option_id(index) } else { self.id }
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
/// Lift the menu into CEF's top layer after Rabbita commits it. CSS anchor
/// positioning keeps it attached to the trigger and chooses the side that
/// fits, so opening a select needs no geometry measurement or clipping-parent
/// traversal in application code.
fn Control::show_menu(self : Control) -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      guard @dom.document().get_element_by_id(self.menu_id()).to_option()
        is Some(element) &&
        element.to_html_element() is Some(menu) else {
        return
      }
      menu.show_popover()
    },
    kind=@cmd.after_render,
  )
}

///|
/// Toggling changes whether the menu exists, so it enters the browser's top
/// layer only after Rabbita has committed that render.
fn Control::toggle_menu(self : Control) -> @cmd.Cmd {
  @cmd.batch([self.toggle, self.show_menu()])
}

///|
/// Keep the menu open while Tab moves between its trigger and options. Once
/// focus leaves the whole control (including a null target when the document
/// loses focus), dismiss without moving focus back to the trigger.
fn Control::dismiss_on_blur(
  self : Control,
  event : @dom.FocusEvent,
) -> @cmd.Cmd {
  if !self.open {
    return @cmd.none
  }
  if event.related_target() is Some(target) &&
    target.to_node() is Some(next) &&
    @dom.document().get_element_by_id(self.root_id()).to_option() is Some(root) &&
    root.contains(next) {
    @cmd.none
  } else {
    self.dismiss
  }
}

///|
fn Control::trigger_attrs(
  self : Control,
  selected_index : Int,
  option_count : Int,
) -> @html.Attrs {
  @html.Attrs::build()
  .id(self.id)
  .aria_label(self.aria_label)
  .aria_haspopup("listbox")
  .aria_controls(self.menu_id())
  .aria_expanded(self.open.to_string())
  .data_set("focus-owner", "")
  .on_blur(event => self.dismiss_on_blur(event))
  .on_keydown(event => {
    match event.key() {
      "Escape" if self.open => {
        event.prevent_default()
        self.dismiss
      }
      "ArrowDown" | "ArrowUp" if option_count > 0 => {
        event.prevent_default()
        let index = if event.key() == "ArrowUp" && self.open {
          option_count - 1
        } else {
          selected_index
        }
        if self.open {
          self.focus(Some(index), false)
        } else {
          @cmd.batch([self.toggle_menu(), self.focus(Some(index), true)])
        }
      }
      _ => @cmd.none
    }
  })
}

///|
fn Control::option_attrs(
  self : Control,
  index : Int,
  option_count : Int,
  selected : Bool,
) -> @html.Attrs {
  @html.Attrs::build()
  .id(self.option_id(index))
  .role("option")
  .aria_selected(selected.to_string())
  .on_blur(event => self.dismiss_on_blur(event))
  .on_keydown(event => {
    let next = match event.key() {
      "ArrowDown" => Some(if index + 1 < option_count { index + 1 } else { 0 })
      "ArrowUp" => Some(if index > 0 { index - 1 } else { option_count - 1 })
      "Home" => Some(0)
      "End" => Some(option_count - 1)
      _ => None
    }
    if next is Some(next) {
      event.prevent_default()
      self.focus(Some(next), false)
    } else if event.key() == "Escape" {
      event.prevent_default()
      @cmd.batch([self.dismiss, self.focus(None, true)])
    } else {
      @cmd.none
    }
  })
}

///|
pub fn Control::render(self : Control) -> @html.Html {
  let mut selected_label = self.selected
  let mut selected_index = 0
  let mut option_count = 0
  for group in self.groups {
    for option in group.options {
      if option.value == self.selected {
        selected_label = option.label
        selected_index = option_count
      }
      option_count += 1
    }
  }
  let children : Array[@html.Html] = [
    @html.button(
      class=self.presentation.button_class(self.open),
      type_="button",
      title=self.title,
      disabled=self.disabled,
      on_click=self.toggle_menu(),
      attrs=self.trigger_attrs(selected_index, option_count),
      self.presentation.trigger_contents(selected_label),
    ),
  ]
  if self.open && !self.disabled {
    let menu : Array[@html.Html] = []
    let flat = self.groups.length() <= 1
    let mut index = 0
    for group in self.groups {
      let rows : Array[@html.Html] = []
      for option in group.options {
        let selected = option.value == self.selected
        // Clicking a row completes the single-choice interaction even when it
        // is already selected. Close in both cases, but only a new value may
        // reach caller update logic as a change.
        let choose = if selected {
          @cmd.batch([self.dismiss, self.focus(None, true)])
        } else {
          @cmd.batch([(self.change)(option.value), self.focus(None, true)])
        }
        rows.push(
          @html.button(
            class=if selected {
              "custom-select-option selected"
            } else {
              "custom-select-option"
            },
            type_="button",
            title=option.label,
            on_click=choose,
            attrs=self.option_attrs(index, option_count, selected),
            [
              @html.span(class="custom-select-option-label", option.label),
              @html.span(
                class="custom-select-option-check",
                if selected {
                  "✓"
                } else {
                  ""
                },
              ),
            ],
          ),
        )
        index += 1
      }
      if flat {
        for row in rows {
          menu.push(row)
        }
      } else {
        menu.push(
          @html.div(
            class="custom-select-group",
            attrs=@html.Attrs::build().role("group").aria_label(group.label),
            [@html.div(class="custom-select-group-label", group.label), ..rows],
          ),
        )
      }
    }
    children.push(
      @html.div(
        class=self.presentation.menu_class(),
        attrs=@html.Attrs::build()
          .id(self.menu_id())
          .role("listbox")
          .aria_label(self.aria_label)
          .popover("manual"),
        menu,
      ),
    )
  }
  @html.div(
    class=self.presentation.root_class(),
    attrs=@html.Attrs::build().id(self.root_id()),
    children,
  )
}

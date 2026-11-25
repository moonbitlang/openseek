///|
pub(all) struct RowContext {
  target : String
  class : String?
  title : String?
  content : @html.Html
  definition : Definition?
}

///|
pub impl Eq for RowContext with fn equal(a, b) {
  physical_equal(a, b)
}

///|
pub extend RowContext with Eq::{equal, not_equal}

///|
#derive(Eq)
priv struct ContextMenuTrigger {
  class : String?
  title : String?
  content : @html.Html
}

///|
/// Keep the context menu mounted while its trigger follows the input.
/// RUI 0.5 binds the trigger and positioning anchor by DOM ID.
fn context_menu_with_input(
  input~ : @rabbita.Val[ContextMenuTrigger],
  id~ : String,
  tabindex~ : Int32 = 0,
  on_open_change? : @cmd.Emit[Bool],
  trigger_attrs? : @html.Attrs,
  trigger_style~ : Array[String] = [],
  popup : (@rui.ContextMenuScope) -> @html.Html,
) -> @rabbita.Val[@html.Html] {
  let (open, set_open) = @rabbita.create_variable(false)
  let menu = @rui.context_menu(
    id~,
    on_open_change=visible => {
      @cmd.batch([
        set_open(_ => visible),
        on_open_change.map_or(@cmd.none, emit => emit(visible)),
      ])
    },
    popup,
  )
  let trigger_id = id + "-trigger"
  input.view3(menu, open, (trigger, menu, open) => {
    let attrs = trigger_attrs.map_or(@html.Attrs::build(), attrs => attrs.copy())
    ignore(
      attrs
      .data_set("slot", "context-menu-trigger")
      .data_set("state", if open { "open" } else { "closed" })
      .data_set(if open { "open" } else { "closed" }, "")
      .tabindex(tabindex)
      .aria_haspopup("menu")
      .aria_expanded(open.to_string())
      .aria_controls(id + "-content"),
    )
    @html.fragment([
      @html.div(
        id=trigger_id,
        class?=trigger.class,
        title?=trigger.title,
        style=["box-sizing:border-box", "position:relative", ..trigger_style],
        attrs~,
        [
          @html.div(style=["display:contents"], trigger.content),
          @rui.popover_anchor(
            id=trigger_id + "-point",
            style=["position:absolute;width:0;height:0;pointer-events:none"],
            attrs=@html.Attrs::build().aria_hidden("true"),
            @html.nothing,
          ),
        ],
      ),
      menu,
    ])
  })
}

///|
/// Keep the row live while reusing the right-click menu. Each open reads the
/// latest menu definition so locale and capability changes take effect without
/// remounting the row.
pub fn row_context(row : @rabbita.Val[RowContext]) -> @rabbita.Val[@html.Html] {
  row.switch_by(
    input => {
      guard input.definition is Some(initial) else {
        return row.view(row => {
          @html.div(class?=row.class, title?=row.title, row.content)
        })
      }
      let id = input.target + ":context"
      let on_open_change = context_open_change(id)
      let latest = Ref(initial)
      let trigger = row.map(row => {
        if row.definition is Some(definition) {
          latest.val = definition
        }
        ContextMenuTrigger::{
          class: row.class,
          title: row.title,
          content: row.content,
        }
      })
      context_menu_with_input(
        input=trigger,
        id~,
        tabindex=-1,
        on_open_change~,
        scope => context_popup(scope, latest.val),
      )
    },
    by=row => if row.definition is Some(_) { row.target } else { "" },
  )
}

///|
fn context_open_change(id : String) -> @cmd.Emit[Bool] {
  let (_, emit) = @rabbita.create_state(
    false,
    update=(_, visible : Bool, _) => (visible, @cmd.none),
    subscriptions=(visible, _) => {
      if visible {
        @dismiss.on_back("row-context-back", level=TopLayer, _ => {
          @rui.popover_close(id + "-content")
        })
      } else {
        @sub.none
      }
    },
  )
  emit
}

///|
fn context_popup(
  scope : @rui.ContextMenuScope,
  definition : Definition,
) -> @html.Html {
  @rui.context_menu_content(
    scope,
    aria_label=definition.label,
    class="action-menu",
    definition.entries.map(entry => {
      match entry {
        Separator => @rui.context_menu_separator()
        Action(item) =>
          @rui.context_menu_item(
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
}

///|
pub fn link_target(href : String) -> ContextTarget {
  guard href.split_once(":") is Some((scheme, _)) else { return NoTarget }
  match scheme.to_lower() {
    "http" | "https" => WebLink(href)
    "mailto" =>
      EmailLink(
        url=href,
        address=@uri.decode_component(
          href[7:].split("?").next().unwrap_or(href[7:]),
        ),
      )
    _ => NoTarget
  }
}

///|
fn link_trigger_attrs(inline : Bool) -> @html.Attrs {
  let focus_target = if inline {
    "a[href], button"
  } else {
    "[data-citation-source-title]"
  }
  let attrs = @html.Attrs::build().on_focus(event => {
    if event.current_target().to_option() is Some(target) &&
      target.to_element() is Some(trigger) &&
      trigger.query_selector(focus_target) is Some(link) &&
      link.to_html_element() is Some(link) {
      link.focus_with_options(prevent_scroll=true)
    }
    @cmd.none
  })
  if !inline {
    // The title link owns the card's stretched hit area. A secondary link
    // handles its own event before it reaches the card trigger.
    let on_title = event => {
      event_element(event).bind(element => element.closest(focus_target))
      is Some(_)
    }
    ignore(
      attrs
      .on_contextmenu(event => {
        if !on_title(event.as_event()) {
          event.stop_immediate_propagation()
        }
        @cmd.none
      })
      .on_keydown(event => {
        if (
            event.key() == "ContextMenu" ||
            (event.key() == "F10" && event.shift_key())
          ) &&
          !on_title(event.as_event()) {
          event.stop_immediate_propagation()
        }
        @cmd.none
      }),
    )
  }
  attrs
}

///|
pub fn link_context(
  id : String,
  locale : @rabbita.Val[@i18n.Locale],
  input : @rabbita.Val[ContextInput],
  target : ContextTarget,
  actions : ContextActions,
  content : @rabbita.Val[@html.Html],
  inline~ : Bool = true,
) -> @rabbita.Val[@html.Html] {
  let state = locale.map2(input, (locale, input) => (locale, input))
  state.switch_by(
    initial => {
      guard context_definition(locale=initial.0, initial.1, target, actions)
        is Some(initial_definition) else {
        return content
      }
      let id = id + ":context"
      let on_open_change = context_open_change(id)
      let class = if inline {
        "inline-context-trigger"
      } else {
        "citation-source-trigger"
      }
      let latest = Ref(initial_definition)
      let trigger = content.map2(state, (content, current) => {
        if context_definition(locale=current.0, current.1, target, actions)
          is Some(current_definition) {
          latest.val = current_definition
        }
        ContextMenuTrigger::{ class: Some(class), title: None, content, }
      })
      context_menu_with_input(
        input=trigger,
        id~,
        tabindex=-1,
        on_open_change~,
        trigger_attrs=link_trigger_attrs(inline),
        trigger_style=if inline { ["display:inline"] } else { [] },
        scope => context_popup(scope, latest.val),
      )
    },
    by=current => {
      if context_definition(locale=current.0, current.1, target, actions)
        is Some(_) {
        "menu"
      } else {
        "plain"
      }
    },
  )
}

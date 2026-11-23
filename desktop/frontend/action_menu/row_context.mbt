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
/// Keep the row live while reusing the right-click menu and its initial definition.
pub fn row_context(row : @rabbita.Val[RowContext]) -> @rabbita.Val[@html.Html] {
  row.switch_by(
    input => {
      guard input.definition is Some(definition) else {
        return row.view(row => {
          @html.div(class?=row.class, title?=row.title, row.content)
        })
      }
      let id = input.target + ":context"
      let on_open_change = context_open_change(id)
      let trigger = row.map(row => @ruix.ContextMenuTrigger::{
        class: row.class,
        title: row.title,
        content: row.content,
      })
      @ruix.context_menu_with_input(
        input=trigger,
        id~,
        tabindex=-1,
        on_open_change~,
        scope => context_popup(scope, definition),
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
  locale : @i18n.Locale,
  input : ContextInput,
  target : ContextTarget,
  actions : ContextActions,
  content : @rabbita.Val[@html.Html],
  inline~ : Bool = true,
) -> @rabbita.Val[@html.Html] {
  guard context_definition(locale~, input, target, actions) is Some(definition) else {
    return content
  }
  let id = id + ":context"
  let on_open_change = context_open_change(id)
  let class = if inline {
    "inline-context-trigger"
  } else {
    "citation-source-trigger"
  }
  let trigger = content.map(content => @ruix.ContextMenuTrigger::{
    class: Some(class),
    title: None,
    content,
  })
  @ruix.context_menu_with_input(
    input=trigger,
    id~,
    tabindex=-1,
    on_open_change~,
    trigger_attrs=link_trigger_attrs(inline),
    trigger_style=if inline { ["display:inline"] } else { [] },
    scope => context_popup(scope, definition),
  )
}

///|
pub(all) struct RowContext {
  target : String
  revision : String
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
priv enum ContextTrigger {
  SidebarRow
  InlineLink
  SourceCard
}

///|
/// Use the supplied row as the right-click trigger. The row HTML can update
/// independently of the menu instance selected by the revision.
pub fn row_context(
  input : @rabbita.Val[RowContext],
) -> @rabbita.Val[@html.Html] {
  context_surface(input, SidebarRow)
}

///|
fn context_surface(
  row : @rabbita.Val[RowContext],
  trigger : ContextTrigger,
) -> @rabbita.Val[@html.Html] {
  row.switch_by(
    input => {
      guard input.definition is Some(definition) else {
        return row.map(row => {
          if trigger is SidebarRow {
            @html.div(class?=row.class, title?=row.title, row.content)
          } else {
            row.content
          }
        })
      }
      let (_, emit) = @rabbita.create_state_with_init(
        init=_ => {
          let close = if !(trigger is SidebarRow) {
            // A reparsed message can reuse the trigger and popover DOM after
            // the previous component scope is disposed.
            @rui.popover_close(input.target + ":context-content")
          } else {
            @cmd.none
          }
          (false, close)
        },
        update=(_, visible : Bool, _) => (visible, @cmd.none),
        subscriptions=(visible, _) => {
          if visible {
            @dismiss.on_back("row-context-back", level=TopLayer, _ => {
              @rui.popover_close(input.target + ":context-content")
            })
          } else {
            @sub.none
          }
        },
      )
      let row_scope : Ref[@rui.ContextMenuScope?] = Ref(None)
      let menu = @rui.context_menu(
        id=input.target + ":context",
        on_open_change=emit,
        scope => {
          let popup = context_popup(scope, definition)
          if trigger is SidebarRow {
            row_scope.val = Some(scope)
            popup
          } else {
            @html.fragment([
              @rui.context_menu_trigger(
                scope,
                tabindex=-1,
                class=if trigger is InlineLink {
                  "inline-context-trigger"
                } else {
                  "citation-source-trigger"
                },
                style=if trigger is InlineLink {
                  ["display:inline"]
                } else {
                  []
                },
                attrs=link_trigger_attrs(trigger),
                input.content,
              ),
              popup,
            ])
          }
        },
      )
      if trigger is SidebarRow {
        // The trigger and popup share RUI's scope and are bound by ID. Keep
        // the row outside the popup root so its own dropdown has independent
        // keyboard handling and row updates preserve the context menu.
        row.view2(menu, (row, menu) => {
          match row_scope.val {
            Some(scope) =>
              @html.fragment([
                @rui.context_menu_trigger(
                  scope,
                  tabindex=-1,
                  class?=row.class,
                  title?=row.title,
                  row.content,
                ),
                menu,
              ])
            None => @html.div(class?=row.class, title?=row.title, row.content)
          }
        })
      } else {
        menu
      }
    },
    by=input => input.revision,
  )
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
fn link_trigger_attrs(trigger : ContextTrigger) -> @html.Attrs {
  let focus_target = if trigger is SourceCard {
    "[data-citation-source-title]"
  } else {
    "a[href], button"
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
  if trigger is SourceCard {
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
  let definition = context_definition(locale~, input, target, actions)
  guard definition is Some(_) else { return content }
  let revision = Ref(0)
  context_surface(
    content.map(content => {
      revision.val += 1
      {
        target: id,
        revision: revision.val.to_string(),
        class: None,
        title: None,
        content,
        definition,
      }
    }),
    if inline {
      InlineLink
    } else {
      SourceCard
    },
  )
}

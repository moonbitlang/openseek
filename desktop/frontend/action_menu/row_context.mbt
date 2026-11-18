///|
pub(all) struct RowContext {
  target : String
  revision : String
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
/// The visible content is the native trigger. A changed content revision
/// replaces the menu instance; unrelated trailing status and child rows do not.
pub fn row_context(
  input : @rabbita.Val[RowContext],
  inline~ : Bool = false,
) -> @rabbita.Val[@html.Html] {
  input.switch_by(
    input => {
      guard input.definition is Some(definition) else {
        return @rabbita.Val::constant(input.content)
      }
      let (_, emit) = @rabbita.create_state_with_init(
        init=_ => {
          let close = if inline {
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
      @rui.context_menu(id=input.target + ":context", on_open_change=emit, scope => {
        @html.fragment([
          @rui.context_menu_trigger(
            scope,
            tabindex=-1,
            class=if inline {
              "inline-context-trigger"
            } else {
              "sidebar-context-trigger"
            },
            style=if inline { ["display:inline"] } else { [] },
            attrs?=if inline { Some(inline_trigger_attrs()) } else { None },
            input.content,
          ),
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
          ),
        ])
      })
    },
    by=input => input.revision,
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
fn inline_trigger_attrs() -> @html.Attrs {
  @html.Attrs::build().on_focus(event => {
    if event.current_target().to_option() is Some(target) &&
      target.to_element() is Some(trigger) &&
      trigger.query_selector("a[href], button") is Some(link) &&
      link.to_html_element() is Some(link) {
      link.focus_with_options(prevent_scroll=true)
    }
    @cmd.none
  })
}

///|
/// Bind the RUI trigger to the inline element whose destination was resolved
/// by the renderer. Its enclosing Markdown block never owns keyboard input.
pub fn inline_context(
  id : String,
  locale : @i18n.Locale,
  input : ContextInput,
  target : ContextTarget,
  actions : ContextActions,
  content : @rabbita.Val[@html.Html],
) -> @rabbita.Val[@html.Html] {
  let definition = context_definition(locale~, input, target, actions)
  guard definition is Some(_) else { return content }
  row_context(
    content.map(content => { target: id, revision: id, content, definition, }),
    inline=true,
  )
}
